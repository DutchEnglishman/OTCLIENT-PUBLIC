-- Client auto-updater.
--
-- Fetches a manifest published as a GitHub Release asset, compares it against the
-- installed tree, downloads whatever changed into a staging directory, verifies every
-- staged file's SHA-256, and only then commits them into place.
--
-- The overriding rule here is FAIL OPEN: a GitHub outage, a malformed manifest, a bad
-- hash or a dropped connection must never stop the client from starting. Every error
-- path funnels into finish(), which tears down the window and lets startup continue.

Updater = {}

local DEFAULT_CONFIG = {
  enabled = true,
  repository = nil,
  manifestUrl = nil,
  manifestSha256Url = nil,
  versionUrl = nil,
  timeout = 30,
  -- A STALL timeout, not a deadline: the watchdog fires only after this long with NO
  -- progress at all. It has to work that way now the manifest can carry sprite sheets --
  -- a 55 MB Tibia.spr takes minutes on a slow line, and a fixed deadline would abort a
  -- download that was proceeding perfectly well.
  overallTimeout = 60000,
  retries = 3,
  retryDelay = 1500,
  strictManifestSha256 = true,
  allowExecutableUpdate = true,
  allowDeletions = true,
  stagingDir = '.otcupdate',
  protectedPaths = { 'config.otml', '*.log', 'data/sounds/**', 'downloads/**' }
}

local HASH_CHUNK = 40 -- files hashed per frame, so the progress bar keeps animating
-- ...but 40 sprite sheets in one frame would freeze the UI for seconds, because hashing
-- reads the whole file into memory. Whichever limit is reached first ends the chunk.
local HASH_BYTE_BUDGET = 16 * 1024 * 1024
local WATCHDOG_POLL = 1000

local config
local updaterWindow
local loadModulesFunction
local scheduledEvent
local watchdogEvent
local httpOperationId
local finished = false
local lastProgressAt = 0

-- Forward declaration: the watchdog closure below is built before the lifecycle section
-- defines this, so it has to capture the same local rather than a later shadow.
local fail

local manifest
local stagingRoot
local totalDownloadBytes = 0
local doneDownloadBytes = 0

-- helpers ---------------------------------------------------------------------

local function logInfo(message) g_logger.info('[Updater] ' .. message) end
local function logWarning(message) g_logger.warning('[Updater] ' .. message) end

local function humanBytes(bytes)
  bytes = bytes or 0
  if bytes >= 1024 * 1024 then
    return string.format('%.1f MB', bytes / (1024 * 1024))
  elseif bytes >= 1024 then
    return string.format('%.0f KB', bytes / 1024)
  end
  return string.format('%i B', bytes)
end

-- Anything that counts as forward motion calls this: a download progress tick, a
-- completed hash chunk, a committed file.
local function noteProgress()
  lastProgressAt = g_clock.millis()
end

-- The watchdog polls against that marker rather than being torn down and rescheduled on
-- every progress tick, which arrive every 100ms during a download. It still catches the
-- case it exists for -- an HTTP backend that never calls back at all.
local function startWatchdog()
  local function tick()
    if finished then return end
    if g_clock.millis() - lastProgressAt >= config.overallTimeout then
      return fail(string.format('Update stalled for %is with no progress.',
        math.floor(config.overallTimeout / 1000)))
    end
    watchdogEvent = scheduleEvent(tick, WATCHDOG_POLL)
  end

  noteProgress()
  watchdogEvent = scheduleEvent(tick, WATCHDOG_POLL)
end

local function loadModules()
  if loadModulesFunction then
    local tmpLoadFunc = loadModulesFunction
    loadModulesFunction = nil
    tmpLoadFunc()
  end
end

-- HTTP.timeout defaults to 2s, which is far too short for a real download.
local function withHttpTimeout(fn)
  local previous = HTTP.timeout
  HTTP.timeout = config.timeout
  local ok, result = pcall(fn)
  HTTP.timeout = previous
  if not ok then
    error(result, 0)
  end
  return result
end

local function globToPattern(glob)
  local pattern = glob:gsub('[%^%$%(%)%%%.%[%]%+%-%?]', '%%%0')
  pattern = pattern:gsub('%*%*', '\1')
  pattern = pattern:gsub('%*', '[^/]*')
  pattern = pattern:gsub('\1', '.*')
  return '^' .. pattern .. '$'
end

-- Compiled once: this runs for every entry in a manifest that can list thousands.
local protectedPatterns

local function protectedPatternList()
  if not protectedPatterns then
    protectedPatterns = {}
    for _, glob in ipairs(config.protectedPaths or {}) do
      table.insert(protectedPatterns, globToPattern(glob))
    end
  end
  return protectedPatterns
end

local function isProtected(path)
  for _, pattern in ipairs(protectedPatternList()) do
    if path:match(pattern) then
      return true
    end
  end
  return false
end

-- Nothing from the manifest is touched until it clears this. A manifest is data from
-- the network, so it is treated as hostile: no traversal, no absolute paths, no
-- reaching into anything the config marked protected.
local function isSafePath(path)
  if type(path) ~= 'string' or path == '' then return false end
  if path:find('\\', 1, true) then return false end
  if path:sub(1, 1) == '/' then return false end
  if path:match('^%a:') then return false end
  for segment in path:gmatch('[^/]+') do
    if segment == '..' or segment == '.' then return false end
  end
  return not isProtected(path)
end

local function isSha256(value)
  return type(value) == 'string' and value:len() == 64 and value:match('^%x+$') ~= nil
end

local function readLocalVersion()
  -- readFileContentsFromWorkDir throws a C++ exception when the file is missing, and
  -- that exception crosses the Lua binding boundary uncaught (luabinder.h's trampoline
  -- has no try/catch), which corrupts the interpreter rather than raising a Lua error --
  -- pcall() cannot save you from it. Checking existence first avoids the throw entirely
  -- for the expected case (no version.txt yet on a fresh install).
  if not g_resources.fileExistsInWorkDir('version.txt') then
    return 0, '0.0.0'
  end

  local ok, contents = pcall(function()
    return g_resources.readFileContentsFromWorkDir('version.txt')
  end)
  if not ok or type(contents) ~= 'string' then
    return 0, '0.0.0'
  end

  local lines = {}
  for line in contents:gmatch('[^\r\n]+') do
    table.insert(lines, line)
  end
  return tonumber(lines[2]) or 0, lines[1] or '0.0.0'
end

-- UI --------------------------------------------------------------------------

local function setStatus(text)
  if updaterWindow then updaterWindow.status:setText(text) end
end

local function setMainProgress(percent)
  if updaterWindow then updaterWindow.mainProgress:setPercent(math.floor(percent)) end
end

local function showDownloadRow(visible)
  if not updaterWindow then return end
  updaterWindow.downloadStatus:setVisible(visible)
  updaterWindow.downloadProgress:setVisible(visible)
end

local function setDownloadStatus(text, percent, speed)
  if not updaterWindow then return end
  if text then
    updaterWindow.downloadStatus:setText(text)
  end
  updaterWindow.downloadProgress:setPercent(math.floor(percent or 0))
  if speed then
    updaterWindow.downloadProgress:setText(speed .. ' kbps')
  end
end

-- lifecycle -------------------------------------------------------------------

-- The single exit point. Every failure and the success path both land here.
local function finish(ok, message)
  if finished then return end
  finished = true

  if message then
    if ok then logInfo(message) else logWarning(message) end
  end

  removeEvent(watchdogEvent)
  watchdogEvent = nil
  Updater.abort()
end

-- No `local` here on purpose: this assigns the forward-declared local above.
function fail(message)
  finish(false, message)
end

-- commit ----------------------------------------------------------------------

local function stagingPathFor(path)
  return stagingRoot .. '/' .. path
end

local function clearStaging()
  if g_resources.removeDirectoryInWorkDir then
    g_resources.removeDirectoryInWorkDir(stagingRoot)
  end
  -- Downloads are buffered in RAM until this point, so release them.
  if g_http and g_http.clearDownloads then
    g_http.clearDownloads()
  end
end

local function writeBreadcrumb(state)
  local ok = pcall(function()
    g_resources.writeFileContentsToWorkDir(stagingRoot .. '/state.json', json.encode(state))
  end)
  return ok
end

local function clearBreadcrumb()
  pcall(function()
    g_resources.deleteFileInWorkDir(stagingRoot .. '/state.json')
  end)
end

local function commit(entries, binaryKey)
  setStatus(tr('Installing update'))
  setMainProgress(0)
  showDownloadRow(false)

  local paths = {}
  for _, entry in ipairs(entries) do
    table.insert(paths, entry.path)
  end

  if not writeBreadcrumb({
    phase = 'committing',
    version = manifest.version,
    versionCode = manifest.versionCode,
    files = paths
  }) then
    return fail('Unable to write the update breadcrumb; refusing to commit.')
  end

  -- Each move is an atomic same-volume rename, so a file is either fully old or fully
  -- new. version.txt goes last: if we die partway, the version still reads as the old
  -- one and the next launch redoes the update rather than trusting a half-written tree.
  for index, entry in ipairs(entries) do
    if entry.path ~= 'version.txt' then
      if not g_resources.moveFileInWorkDir(stagingPathFor(entry.path), entry.path) then
        return fail(string.format('Unable to install %s. The client was left unchanged where possible.', entry.path))
      end
    end
    noteProgress()
    setMainProgress(80 * index / #entries)
  end

  if config.allowDeletions and type(manifest.deleteFiles) == 'table' then
    for _, path in ipairs(manifest.deleteFiles) do
      if isSafePath(path) then
        g_resources.deleteFileInWorkDir(path)
      else
        logWarning('Refusing to delete unsafe or protected path: ' .. tostring(path))
      end
    end
  end

  if binaryKey then
    setStatus(tr('Updating client binary'))
    if not g_resources.updateExecutable(binaryKey) then
      -- The Lua tree is already updated and consistent; only the binary swap failed.
      logWarning('Binary update failed. The client will keep running the current executable.')
    end
  end

  setMainProgress(95)
  for _, entry in ipairs(entries) do
    if entry.path == 'version.txt' then
      if not g_resources.moveFileInWorkDir(stagingPathFor(entry.path), entry.path) then
        return fail('Unable to write version.txt; the update will be retried on next launch.')
      end
    end
  end

  clearBreadcrumb()
  clearStaging()
  setMainProgress(100)

  logInfo(string.format('Updated to %s. Restarting.', manifest.version))
  scheduledEvent = scheduleEvent(function()
    g_app.restart()
  end, 100)
end

-- download --------------------------------------------------------------------

local function verifyStaged(entries, index, binaryKey)
  if not updaterWindow then return end

  index = index or 1
  if index > #entries then
    return commit(entries, binaryKey)
  end

  local chunkEnd = index
  local chunkBytes = 0
  for i = index, math.min(index + HASH_CHUNK - 1, #entries) do
    local entry = entries[i]
    local actual = g_resources.fileSha256InWorkDir(stagingPathFor(entry.path))
    if actual ~= entry.sha256 then
      clearStaging()
      return fail(string.format('Verification failed for %s (expected %s, got %s). Nothing was installed.',
        entry.path, entry.sha256, actual ~= '' and actual or 'nothing'))
    end
    chunkEnd = i
    chunkBytes = chunkBytes + (entry.size or 0)
    if chunkBytes >= HASH_BYTE_BUDGET then break end
  end

  noteProgress()
  setStatus(tr('Verifying update'))
  setMainProgress(100 * chunkEnd / #entries)
  scheduledEvent = scheduleEvent(function()
    verifyStaged(entries, chunkEnd + 1, binaryKey)
  end, 0)
end

-- One 55 MB sprite sheet among two hundred small Lua files makes file-count progress a
-- lie: the bar would jump to 99% and then sit there for minutes. Weight by bytes, and
-- fold in how far the file currently downloading has got.
local function setDownloadedFraction(entries, index, entry, percent)
  percent = percent or 0
  if totalDownloadBytes > 0 then
    local bytes = doneDownloadBytes + (entry.size or 0) * percent / 100
    setMainProgress(100 * math.min(bytes, totalDownloadBytes) / totalDownloadBytes)
  else
    -- A manifest without sizes, so fall back to counting files.
    setMainProgress(100 * (index - 1 + percent / 100) / #entries)
  end
end

local function downloadEntries(entries, index, attempt, onDone)
  if not updaterWindow then return end

  local entry = entries[index]
  if not entry then
    return onDone()
  end

  -- Files small enough to live in the mirror repo are fetched per-path from
  -- raw.githubusercontent. Anything too big for git -- sprite sheets, above all -- is
  -- published as a Release asset instead, and the manifest names that asset here.
  local url = entry.asset and (manifest.assetBaseUrl .. entry.asset)
      or (manifest.rawBaseUrl .. entry.path)
  local key = stagingRoot .. '/' .. entry.path
  local label = string.format('%s (%s)', entry.path, humanBytes(entry.size))

  if attempt > 0 then
    setDownloadStatus(tr('Downloading (retry %i):\n%s', attempt, label), 0)
  else
    setDownloadStatus(tr('Downloading:\n%s', label), 0)
  end
  setDownloadedFraction(entries, index, entry, 0)

  local function retryOrFail(reason)
    if attempt >= config.retries then
      clearStaging()
      return fail(string.format('Could not download %s: %s', entry.path, reason))
    end
    scheduledEvent = scheduleEvent(function()
      downloadEntries(entries, index, attempt + 1, onDone)
    end, config.retryDelay)
  end

  httpOperationId = withHttpTimeout(function()
    return HTTP.download(url, key, function(path, checksum, err)
      if finished then return end
      if err then
        return retryOrFail(err)
      end

      -- Write the downloaded bytes into staging. Nothing reaches the live tree yet.
      if not g_resources.writeDownloadedFileToWorkDir(key, stagingPathFor(entry.path), false) then
        return retryOrFail('unable to write to the staging directory')
      end

      -- The bytes are on disk in staging now, so drop the in-RAM copy. Without this the
      -- cache holds every file downloaded so far until commit, which was harmless when
      -- the manifest was all small text files and is not once a 55 MB sprite sheet is in
      -- it. Safe here because the binary is fetched after every entry, into its own key.
      if g_http and g_http.clearDownloads then
        g_http.clearDownloads()
      end

      doneDownloadBytes = doneDownloadBytes + (entry.size or 0)
      downloadEntries(entries, index + 1, 0, onDone)
    end, function(progress, speed)
      noteProgress()
      setDownloadStatus(nil, progress, speed)
      setDownloadedFraction(entries, index, entry, progress)
    end)
  end)

  if not httpOperationId or httpOperationId < 0 then
    retryOrFail('HTTP is unavailable')
  end
end

local function downloadBinary(entries, binaryEntry)
  if not binaryEntry then
    return verifyStaged(entries, 1, nil)
  end

  local key = stagingRoot .. '/binary-' .. tostring(manifest.versionCode)
  setDownloadStatus(tr('Downloading:\n%s', binaryEntry.path), 0)

  httpOperationId = withHttpTimeout(function()
    return HTTP.download(manifest.assetBaseUrl .. binaryEntry.asset, key, function(path, checksum, err)
      if finished then return end
      if err then
        logWarning('Could not download the new binary: ' .. err .. '. Continuing without a binary update.')
        return verifyStaged(entries, 1, nil)
      end

      -- The binary never touches disk until updateExecutable(), so verify the bytes
      -- held in the download cache rather than a staged file.
      local ok, contents = pcall(function()
        return g_resources.readFileContents('/downloads/' .. key)
      end)
      if not ok or g_crypt.sha256(contents) ~= binaryEntry.sha256 then
        logWarning('Binary hash mismatch. Continuing without a binary update.')
        return verifyStaged(entries, 1, nil)
      end

      verifyStaged(entries, 1, key)
    end, function(progress, speed)
      noteProgress()
      setDownloadStatus(nil, progress, speed)
    end)
  end)

  if not httpOperationId or httpOperationId < 0 then
    logWarning('HTTP unavailable for the binary download. Continuing without a binary update.')
    verifyStaged(entries, 1, nil)
  end
end

-- diff ------------------------------------------------------------------------

local function diffFiles(files, index, changed, binaryEntry)
  if not updaterWindow then return end

  index = index or 1
  changed = changed or {}

  if index > #files then
    if #changed == 0 and not binaryEntry then
      return finish(true, 'Client is already up to date.')
    end

    totalDownloadBytes = 0
    doneDownloadBytes = 0
    for _, entry in ipairs(changed) do
      totalDownloadBytes = totalDownloadBytes + (entry.size or 0)
    end

    logInfo(string.format('%i file(s) to update, %s to download.', #changed, humanBytes(totalDownloadBytes)))
    setStatus(tr('Downloading %i files', #changed))
    showDownloadRow(true)
    return downloadEntries(changed, 1, 0, function()
      downloadBinary(changed, binaryEntry)
    end)
  end

  local chunkEnd = index
  local chunkBytes = 0
  for i = index, math.min(index + HASH_CHUNK - 1, #files) do
    local entry = files[i]
    if g_resources.fileSha256InWorkDir(entry.path) ~= entry.sha256 then
      table.insert(changed, entry)
    end
    chunkEnd = i
    chunkBytes = chunkBytes + (entry.size or 0)
    if chunkBytes >= HASH_BYTE_BUDGET then break end
  end

  noteProgress()
  setStatus(tr('Checking installed files'))
  setMainProgress(100 * chunkEnd / #files)
  scheduledEvent = scheduleEvent(function()
    diffFiles(files, chunkEnd + 1, changed, binaryEntry)
  end, 0)
end

-- manifest --------------------------------------------------------------------

local function validateManifest(data)
  if type(data) ~= 'table' then
    return nil, 'manifest is not an object'
  end
  if type(data.rawBaseUrl) ~= 'string' or data.rawBaseUrl == '' then
    return nil, 'manifest is missing rawBaseUrl'
  end
  if type(data.files) ~= 'table' then
    return nil, 'manifest is missing a files list'
  end

  local files = {}
  for _, entry in ipairs(data.files) do
    if type(entry) ~= 'table' or not isSafePath(entry.path) then
      return nil, 'manifest contains an unsafe or protected path: ' .. tostring(entry and entry.path)
    end
    if not isSha256(entry.sha256) then
      return nil, 'manifest contains a malformed hash for ' .. tostring(entry.path)
    end

    -- An entry may redirect its download to a Release asset instead of the mirror repo,
    -- which is how files too big for git (sprite sheets) get shipped. The asset name is
    -- appended to assetBaseUrl, so it is held to a flat filename -- no separators, no
    -- traversal, nothing that could escape the release's asset namespace.
    local asset = entry.asset
    if asset ~= nil then
      if type(asset) ~= 'string' or not asset:match('^[%w%._%-]+$') or asset:find('..', 1, true) then
        return nil, 'manifest contains a malformed asset name for ' .. tostring(entry.path)
      end
      if type(data.assetBaseUrl) ~= 'string' or data.assetBaseUrl == '' then
        return nil, 'manifest routes ' .. tostring(entry.path) .. ' to an asset but has no assetBaseUrl'
      end
    end

    table.insert(files, {
      path = entry.path,
      sha256 = entry.sha256:lower(),
      size = tonumber(entry.size) or 0,
      asset = asset
    })
  end

  local binaryEntry
  local binary = data.binary
  if config.allowExecutableUpdate and type(binary) == 'table'
      and type(binary.asset) == 'string' and binary.asset ~= ''
      and isSha256(binary.sha256) then
    binaryEntry = { asset = binary.asset, path = binary.path or binary.asset, sha256 = binary.sha256:lower() }
  end

  return { files = files, binary = binaryEntry }
end

local function applyManifest(data)
  local parsed, err = validateManifest(data)
  if not parsed then
    return fail('Rejected update manifest: ' .. err)
  end

  manifest = data
  manifest.versionCode = tonumber(data.versionCode) or 0
  manifest.version = tostring(data.version or '?')
  manifest.assetBaseUrl = data.assetBaseUrl or ''

  local localCode, localVersion = readLocalVersion()

  -- Fast path: nothing to do once the install is at or beyond the published version, and
  -- we skip hashing thousands of files entirely. This is the normal case on every launch.
  --
  -- `>=`, not `==`: a dev tree or a locally built client is routinely AHEAD of the latest
  -- release, and treating "different" as "stale" would quietly overwrite it with older
  -- files -- sprites included, now that data/things ships through here. Roll players back
  -- by publishing a HIGHER version carrying the old content, never by lowering a code.
  if localCode > 0 and localCode >= manifest.versionCode then
    if localCode > manifest.versionCode then
      return finish(true, string.format(
        'Installed version %s is newer than the published %s; leaving it alone.',
        localVersion, manifest.version))
    end
    return finish(true, string.format('Client is up to date (%s).', localVersion))
  end

  logInfo(string.format('Update available: %s -> %s', localVersion, manifest.version))
  clearStaging()
  diffFiles(parsed.files, 1, {}, parsed.binary)
end

local function fetchManifest()
  setStatus(tr('Checking for updates'))
  setMainProgress(5)

  httpOperationId = withHttpTimeout(function()
    return HTTP.get(config.manifestUrl, function(body, err)
      if finished then return end
      if err then
        return fail('Could not reach the update server: ' .. err)
      end
      if type(body) ~= 'string' or body == '' then
        return fail('Update server returned an empty manifest.')
      end

      setMainProgress(10)

      local function decodeAndApply()
        local ok, data = pcall(function() return json.decode(body) end)
        if not ok then
          return fail('Could not parse the update manifest: ' .. tostring(data))
        end
        applyManifest(data)
      end

      if not config.strictManifestSha256 or not config.manifestSha256Url then
        return decodeAndApply()
      end

      httpOperationId = withHttpTimeout(function()
        return HTTP.get(config.manifestSha256Url, function(expected, hashErr)
          if finished then return end
          if hashErr then
            return fail('Could not fetch the manifest checksum: ' .. hashErr)
          end

          expected = tostring(expected):match('%x+')
          local actual = g_crypt.sha256(body)
          if not isSha256(expected) or expected:lower() ~= actual then
            return fail(string.format('Manifest checksum mismatch (expected %s, got %s).',
              tostring(expected), actual))
          end

          decodeAndApply()
        end)
      end)
    end)
  end)

  if not httpOperationId or httpOperationId < 0 then
    fail('HTTP is unavailable; skipping the update check.')
  end
end

-- The manifest lists every shipped file, so it is a few hundred KB. version.json is a
-- few dozen bytes, and in the overwhelmingly common case ("already up to date") it is
-- the only thing we need to fetch.
local function fetchVersionProbe()
  if not config.versionUrl then
    return fetchManifest()
  end

  setStatus(tr('Checking for updates'))
  setMainProgress(5)

  local localCode, localVersion = readLocalVersion()
  if localCode == 0 then
    return fetchManifest() -- unknown install, so the file hashes have to decide
  end

  httpOperationId = withHttpTimeout(function()
    return HTTP.get(config.versionUrl, function(body, err)
      if finished then return end

      -- On any failure fall through to the manifest: this covers an older release
      -- that predates version.json. A real outage fails there instead, and fails open.
      if err or type(body) ~= 'string' or body == '' then
        return fetchManifest()
      end

      local ok, data = pcall(function() return json.decode(body) end)
      if not ok or type(data) ~= 'table' or tonumber(data.versionCode) == nil then
        return fetchManifest()
      end

      -- Same `>=` rule as applyManifest(), for the same reason -- see the comment there.
      -- This is the branch that actually spares a dev tree, since it runs before any
      -- hashing and so before anything can be overwritten.
      local remoteCode = tonumber(data.versionCode)
      if localCode >= remoteCode then
        if localCode > remoteCode then
          return finish(true, string.format(
            'Installed version %s is newer than the published %s; leaving it alone.',
            localVersion, tostring(data.version or remoteCode)))
        end
        return finish(true, string.format('Client is up to date (%s).', localVersion))
      end

      fetchManifest()
    end)
  end)

  if not httpOperationId or httpOperationId < 0 then
    fail('HTTP is unavailable; skipping the update check.')
  end
end

-- config ----------------------------------------------------------------------

local function resolveConfig()
  local raw = Services and Services.updater
  local resolved = {}
  for key, value in pairs(DEFAULT_CONFIG) do
    resolved[key] = value
  end

  if type(raw) == 'string' then
    resolved.manifestUrl = raw
  elseif type(raw) == 'table' then
    for key, value in pairs(raw) do
      resolved[key] = value
    end
  end

  if resolved.repository and not resolved.manifestUrl then
    -- releases/latest/download/ is a plain redirect, so it avoids api.github.com's
    -- 60-requests-per-hour anonymous limit -- which matters when every client checks
    -- on every launch and a whole guild can sit behind one NAT.
    local base = string.format('https://github.com/%s/releases/latest/download/', resolved.repository)
    resolved.manifestUrl = base .. 'manifest.json'
    resolved.manifestSha256Url = resolved.manifestSha256Url or (base .. 'manifest.json.sha256')
    resolved.versionUrl = resolved.versionUrl or (base .. 'version.json')
  end

  return resolved
end

-- public ----------------------------------------------------------------------

-- If a previous run died between "start committing" and "write version.txt", the
-- breadcrumb is still on disk. version.txt is deliberately written last, so the
-- installed version still reads as the old one and the normal check below will
-- re-download exactly the files that are still wrong. All we have to do here is
-- notice, and throw away the stale staging tree so it cannot be trusted.
local function repairInterruptedUpdate()
  -- See the comment in readLocalVersion(): this file being absent is the expected,
  -- routine case (no interrupted update), so it must be checked for, not thrown on.
  local breadcrumbPath = stagingRoot .. '/state.json'
  if not g_resources.fileExistsInWorkDir(breadcrumbPath) then
    return
  end

  local ok, contents = pcall(function()
    return g_resources.readFileContentsFromWorkDir(breadcrumbPath)
  end)
  if not ok or type(contents) ~= 'string' or contents == '' then
    return
  end

  local decoded, state = pcall(function() return json.decode(contents) end)
  local version = (decoded and type(state) == 'table' and state.version) or 'unknown'
  logWarning(string.format(
    'A previous update to %s was interrupted before it finished. Discarding the staged files and re-checking.',
    tostring(version)))

  clearStaging()
end

function Updater.init(loadModulesFunc)
  loadModulesFunction = loadModulesFunc
  finished = false
  config = resolveConfig()
  stagingRoot = config.stagingDir
  protectedPatterns = nil
  totalDownloadBytes = 0
  doneDownloadBytes = 0

  if not config.enabled or not config.manifestUrl then
    return finish(true, 'Updater is not configured; skipping.')
  end

  pcall(repairInterruptedUpdate)
  Updater.check()
end

function Updater.check(args)
  if updaterWindow then return end

  updaterWindow = g_ui.displayUI('updater')
  updaterWindow:show()
  updaterWindow:focus()
  updaterWindow:raise()

  -- The backstop that makes every stall survivable, including an HTTP backend that
  -- never calls back at all. It measures silence, not elapsed time, so a legitimately
  -- long sprite download is left alone for as long as bytes keep arriving.
  startWatchdog()

  local ok, err = pcall(fetchVersionProbe)
  if not ok then
    fail('Update check failed: ' .. tostring(err))
  end
end

function Updater.abort(terminate)
  if httpOperationId and httpOperationId > 0 then
    HTTP.cancel(httpOperationId)
    httpOperationId = nil
  end
  removeEvent(scheduledEvent)
  scheduledEvent = nil
  removeEvent(watchdogEvent)
  watchdogEvent = nil

  if updaterWindow then
    updaterWindow:destroy()
    updaterWindow = nil
  end

  -- Order matters: loadModules() is what loads modules/client, whose init() connects
  -- the onUpdateFinished handler. Signalling first would drop the signal on the floor.
  loadModules()
  if not terminate then
    signalcall(g_app.onUpdateFinished, g_app)
  end
end

function Updater.terminate()
  finished = true
  loadModulesFunction = nil
  Updater.abort(true)
end

function Updater.error(message)
  fail(message)
end
