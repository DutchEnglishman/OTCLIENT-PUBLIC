-- Remembers which containers were open and reopens them at login.
--
-- The route to a bag is recorded as it happens rather than worked out
-- afterwards, because afterwards it is gone: a container's own item
-- (Container:getContainerItem) is parsed fresh out of the open packet and
-- nothing gives it a position (Game::processOpenContainer), and the client
-- never learns what is inside a closed bag (Item::m_containerItems has no
-- writer anywhere in src/), so once a window has moved on there is no way back
-- to where the bag lived. g_game.open is wrapped instead, where the item still
-- carries its slot.

ContainerRestore = {}

-- Item positions are virtual. An inventory item is (0xFFFF, slot, 0), set in
-- Game::processInventoryChange; an item inside a container is
-- (0xFFFF, containerId | 0x40, slot), set in Container::updateItemsPositions.
-- 0x40 is what separates the two, since a container id is only 0..15.
local VIRTUAL_POSITION_X = 65535
local CONTAINER_POSITION_BASE = 64

local REPLAY_STEP_TIMEOUT_MS = 3000
-- The inventory lands in its own packets just after login, usually within a
-- frame or two. Polling every 250 ms meant a quarter second of nothing before
-- the first bag was even asked for; this keeps the same 5 s budget but notices
-- the moment it arrives.
local INVENTORY_POLL_MS = 50
local INVENTORY_POLL_TRIES = 100

local paths = {}
local replaying = false
local queue = nil
local step = nil
local stepToken = 0
local originalOpen = nil
local originalOpenParent = nil

-- Windows the replay still owes. A replay that ends with any of these unfilled
-- did NOT reproduce what the player left, so its result must never be written
-- back over the stored layout -- writing it is what erased a good layout the
-- first time the replay came up empty.
local replayPending = 0
local hiddenWindows = {}

-- Off. Flip to true to trace the replay into otclient.log, which init.lua
-- already points at <workdir>/otclient.log. Every decision the restore makes is
-- logged: the erasure at logout, the prefix collision and the per-hop round-trip
-- cost were each found this way, and it is the only view into a replay that has
-- no visible failure mode of its own.
local DEBUG = false
local function log(fmt, ...)
    if not DEBUG then
        return
    end
    local ok, msg = pcall(string.format, fmt, ...)
    g_logger.info('[containers] ' .. (ok and msg or tostring(fmt)))
end

local function copyPath(path, upto)
    local copy = {}
    for i = 1, (upto or #path) do
        copy[i] = path[i]
    end
    return copy
end

-- Settings do not come back the way they went in. g_settings emits to
-- config.otml and parses it again, and every node parsed from a `tag: value`
-- line is unique (otmlparser.cpp:439), which makes push_otml_subnode_luavalue
-- key the rebuilt table by the tag TEXT (luavaluecasts.cpp:289). So the array
-- {3, 0} is written as `1: 3 / 2: 0` and handed back as {["1"] = 3, ["2"] = 0},
-- which ipairs and # both read as empty. Returns a real 1..n array, or nil when
-- the keys are not exactly that. game_autoloot/presets.lua and
-- client_entergame/characterlist.lua both normalize at the same boundary.
local function numericArray(value)
    if type(value) ~= "table" then
        return nil
    end

    local byIndex, count = {}, 0
    for key, entry in pairs(value) do
        local index = tonumber(key)
        if not index then
            return nil
        end
        byIndex[index] = entry
        count = count + 1
    end

    local array = {}
    for i = 1, count do
        if byIndex[i] == nil then
            return nil
        end
        array[i] = byIndex[i]
    end
    return array
end

-- The route to an item: inventory slot, then one slot index per container
-- stepped into. nil when the item sits somewhere a route cannot reach it --
-- the ground, a corpse, a depot -- or when the container holding it has no
-- route of its own.
local function pathToItem(item)
    if not item then
        return nil
    end

    local pos = item:getPosition()
    if not pos or pos.x ~= VIRTUAL_POSITION_X then
        return nil
    end

    if pos.y < CONTAINER_POSITION_BASE then
        if pos.y < InventorySlotFirst or pos.y > InventorySlotLast then
            return nil
        end
        return { pos.y }
    end

    -- The position is only a claim. An item object outlives the container it
    -- was read out of, so once that window has moved to another bag the item
    -- still reads "slot 5 of container 0" while container 0 now shows something
    -- else -- and appending that slot to container 0's route would invent a bag
    -- that was never there. Believe it only when the live container really does
    -- hold this item in that slot.
    local parentId = pos.y - CONTAINER_POSITION_BASE
    local parent = g_game.getContainer(parentId)
    if not parent or parent:getItem(pos.z) ~= item then
        return nil
    end

    local parentPath = paths[parentId]
    if not parentPath then
        return nil
    end

    local path = copyPath(parentPath)
    path[#path + 1] = pos.z
    return path
end

function ContainerRestore.pathOf(container)
    return container and paths[container:getId()] or nil
end

-- The key a container window's size and position are filed under. The stock id
-- is 'container' .. container:getId(), and that id is the server's
-- next-free-slot number -- it names a different bag every session, so a saved
-- height lands on whatever happens to open in that slot next time. The route
-- names the bag.
--
-- Joined with '_' and not ':'. This id becomes an OTML tag under
-- CharMiniWindows, and OTML splits a line at its FIRST colon
-- (otmlparser.cpp:371), so 'container:3:0' was written out fine and read back
-- as the tag 'container' carrying the value '3:0' -- every container window
-- collapsing onto that one tag, with the height and position underneath it
-- dropped.
function ContainerRestore.windowId(container)
    local path = paths[container:getId()]
    if path and #path > 0 then
        return 'container_' .. table.concat(path, '_')
    end
    return 'container' .. container:getId()
end

local function settingsKey()
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return nil
    end
    local world = g_game.getWorldName() or ''
    return 'containerLayout_' .. world:lower() .. '_' .. char:lower()
end

-- Drop a window's stored size and place, so the bag it belonged to opens fresh
-- in the side panel next time rather than reappearing wherever it was last
-- dragged. Writes CharMiniWindows the same read-modify-write way
-- UIMiniWindow:setSettings and :eraseSettings do.
local function forgetWindowSettings(windowId)
    -- The logout teardown closes every window on its way down, and that is not
    -- the player throwing their layout away. Same boundary the save honours.
    if not g_game.isOnline() then
        return
    end

    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local settings = g_settings.getNode('CharMiniWindows')
    if not settings or not settings[char] or settings[char][windowId] == nil then
        return
    end

    log('forget: %s closed for good, dropping its place', windowId)
    settings[char][windowId] = nil
    g_settings.setNode('CharMiniWindows', settings)
end

function ContainerRestore.save()
    -- Mid-replay the open windows are only the ones restored so far, so saving
    -- now would truncate the layout being restored.
    if replaying then
        return
    end

    -- Nothing that happens after the player leaves the game describes what they
    -- left behind. Game::processGameEnd clears m_online BEFORE it fires
    -- onGameEnd (game.cpp:198), so the entire teardown runs with isOnline()
    -- already false: every container the UI closes on its way down reaches
    -- onContainerClose, which drops that route and then saves. With two bags
    -- open that wrote `save: 0 window(s)` straight over a good layout.
    if not g_game.isOnline() then
        return
    end

    local key = settingsKey()
    if not key then
        return
    end

    local ids = {}
    for id in pairs(g_game.getContainers()) do
        if paths[id] and #paths[id] > 0 then
            ids[#ids + 1] = id
        end
    end
    -- By container id, which is the order the windows were opened in, so the
    -- replay rebuilds them in that same order and they land in the same places.
    table.sort(ids)

    local windows = {}
    for _, id in ipairs(ids) do
        windows[#windows + 1] = copyPath(paths[id])
    end

    log('save: %d window(s) under %s', #windows, key)
    g_settings.setNode(key, { windows = windows })
end

-- The longest leading part of this route that some window is already showing,
-- and that window's container id.
--
-- Re-opening a container the player already has open does not give it a second
-- window: the server closes it instead (Actions::internalUseItem,
-- actions.cpp:429-432, `oldContainerId != -1` -> closeContainer). So a saved
-- layout holding both a bag and something inside that same bag -- one route a
-- prefix of the other -- cannot be rebuilt by walking each route from the top.
-- The prefix is on screen already and the deeper window has to be reached
-- THROUGH it, which is exactly what the player's own clicks did.
local function longestOpenPrefix(path)
    local bestLength, bestId = 0, nil

    for id, recorded in pairs(paths) do
        local length = #recorded
        if length <= #path and length > bestLength then
            local container = g_game.getContainer(id)
            if container and not container:isClosed() then
                local same = true
                for i = 1, length do
                    if recorded[i] ~= path[i] then
                        same = false
                        break
                    end
                end
                if same then
                    bestLength, bestId = length, id
                end
            end
        end
    end

    return bestLength, bestId
end

local beginNextWindow

-- Put back everything the replay hid that is still alive.
--
-- Called as each route finishes, not once at the end. Every hop is a server
-- round trip -- about 240 ms against a remote server -- so holding the whole
-- layout back turned five bags into a second and a bit of nothing, when the
-- first could have been up in a quarter of that. What has to stay hidden is a
-- window being navigated THROUGH, and that one is destroyed and replaced rather
-- than revealed: containers.lua's own onContainerClose destroys it
-- (containers.lua:1229), so isDestroyed() filters it out here.
--
-- Also the single exit for every ending -- a full restore, a route that died
-- halfway, and the 3 s timeout -- so nothing can be left invisible.
local function revealWindows()
    for _, window in ipairs(hiddenWindows) do
        if not window:isDestroyed() then
            window:setVisible(true)
        end
    end
    hiddenWindows = {}
end

local function finishReplay()
    revealWindows()
    replaying = false
    queue = nil
    step = nil
    stepToken = stepToken + 1
end

local function advance()
    if not step then
        return
    end

    step.hop = step.hop + 1
    local path = step.path

    if step.hop > #path then
        -- This route is done: show what it built before asking for the next.
        revealWindows()
        replayPending = replayPending - 1
        step = nil
        beginNextWindow()
        return
    end

    local item, previous
    if step.containerId then
        -- This window has already been opened once, so going deeper replaces
        -- what it shows -- the same move as clicking a bag inside an open one.
        previous = g_game.getContainer(step.containerId)
        item = previous and previous:getItem(path[step.hop])
    elseif step.hop == 1 then
        local player = g_game.getLocalPlayer()
        item = player and player:getInventoryItem(path[1])
    else
        -- Read through the window already showing this route's first hops.
        -- `previous` stays nil, so the item opens in a NEW window and the one
        -- we read it out of is left alone.
        local source = g_game.getContainer(step.sourceId)
        item = source and source:getItem(path[step.hop])
    end

    -- A slot that no longer holds a bag ends this window and no more. Opening
    -- whatever is sitting there instead would be a USE: the saved route would
    -- eat the food or drink the potion that took the bag's place.
    if not item or not item:isContainer() then
        log('replay: hop %d of %s stopped -- %s', step.hop, table.concat(path, '/'),
            item and 'that slot no longer holds a container' or 'nothing in that slot')
        step = nil
        beginNextWindow()
        return
    end

    local id = g_game.open(item, previous)
    if not id or id < 0 then
        log('replay: hop %d of %s refused by g_game.open (returned %s)', step.hop,
            table.concat(path, '/'), tostring(id))
        step = nil
        beginNextWindow()
        return
    end

    log('replay: asked for %s hop %d -> window %d', table.concat(path, '/'),
        step.hop, id)

    step.containerId = id
    stepToken = stepToken + 1

    -- Nothing guarantees the server answers. Without this the replay would sit
    -- half-done for ever with saving suppressed, and the layout would never be
    -- written again.
    local token = stepToken
    scheduleEvent(function()
        if replaying and step and stepToken == token then
            log('replay: server never answered, %d window(s) unfilled', replayPending)
            finishReplay()
        end
    end, REPLAY_STEP_TIMEOUT_MS)
end

beginNextWindow = function()
    if not queue or #queue == 0 then
        -- Deliberately no save here. The stored layout is already correct; a
        -- replay that fell short would otherwise write its shortfall over it.
        log('replay: finished, %d window(s) unfilled', replayPending)
        finishReplay()
        return
    end

    local path = table.remove(queue, 1)
    local openedUpto, sourceId = longestOpenPrefix(path)

    if openedUpto >= #path then
        log('replay: %s is already open', table.concat(path, '/'))
        replayPending = replayPending - 1
        beginNextWindow()
        return
    end

    step = { path = path, hop = openedUpto, containerId = nil, sourceId = sourceId }
    advance()
end

local function waitForInventory(triesLeft)
    if not replaying then
        return
    end

    local player = g_game.getLocalPlayer()
    if player and queue and queue[1] and player:getInventoryItem(queue[1][1]) then
        beginNextWindow()
        return
    end

    if triesLeft <= 0 then
        -- The inventory never arrived, so not one window was rebuilt. Marking
        -- this is what stops the logout save from writing that emptiness over
        -- the layout the player actually left.
        log('restore: gave up waiting for the inventory, %d window(s) unfilled', replayPending)
        finishReplay()
        return
    end

    scheduleEvent(function()
        waitForInventory(triesLeft - 1)
    end, INVENTORY_POLL_MS)
end

function ContainerRestore.restore()
    -- Cleared up front, not once a queue exists: a previous character in this
    -- same client run may have left it set, which would suppress this one's
    -- logout save.
    local key = settingsKey()
    if not key then
        return
    end

    local data = g_settings.getNode(key)
    if not data then
        log('restore: nothing saved under %s', key)
        return
    end

    local windows = numericArray(data.windows)
    if not windows then
        log('restore: %s holds no usable window list', key)
        return
    end

    queue = {}
    for _, saved in ipairs(windows) do
        local path = numericArray(saved)
        if path and #path > 0 then
            -- A slot number survives the round trip as an integer, but a value
            -- that failed every numeric cast arrives as a string
            -- (push_otml_subnode_luavalue falls through to pushString), and an
            -- inventory slot compared as a string would never match.
            local intact = true
            for i = 1, #path do
                local slot = tonumber(path[i])
                if not slot then
                    intact = false
                    break
                end
                path[i] = slot
            end

            if intact then
                queue[#queue + 1] = path
            end
        end
    end

    if #queue == 0 then
        queue = nil
        return
    end

    replaying = true
    replayPending = #queue
    log('restore: %d window(s) queued from %s', #queue, key)
    -- The inventory arrives in its own packets after login, so the back slot is
    -- usually still empty at this point.
    waitForInventory(INVENTORY_POLL_TRIES)
end

function ContainerRestore.onContainerOpen(container)
    if replaying then
        if step and container:getId() == step.containerId then
            log('replay: server answered for window %d', container:getId())
            advance()
        end
        return
    end

    -- The player opened this themselves, so what is on screen is their intent
    -- again and a failed replay no longer has any claim on the stored layout.
    ContainerRestore.save()
end

function ContainerRestore.onContainerClose(container)
    -- A window that moved to another bag closes the OLD container after the new
    -- one has already opened on the same id (Game::processOpenContainer calls
    -- onOpen and only then previousContainer->onClose), so clearing the route
    -- unconditionally here would wipe the one just recorded for the new bag.
    -- The live container for that id is the new one and is not closed; on a
    -- genuine close there is no live container at all.
    local id = container:getId()
    local live = g_game.getContainer(id)
    if not live or live:isClosed() then
        -- windowId reads paths[id], so ask before clearing it.
        forgetWindowSettings(ContainerRestore.windowId(container))
        paths[id] = nil
    end

    if not replaying then
        ContainerRestore.save()
    end
end

function ContainerRestore.onGameEnd()
    -- Deliberately no save. The stored layout is already current -- every open
    -- and close during play wrote it -- and by the time this runs the player is
    -- offline with the windows coming down, so anything computed here describes
    -- the teardown rather than the session.
    --
    -- Written out now rather than left to the client's own exit: a logout is
    -- not an exit, and the player may never close the client cleanly at all.
    g_settings.save()

    paths = {}
    finishReplay()
end

-- Size, place and minimized state for one container window. Deliberately not
-- UIMiniWindow:setupOnStart, which would also act on the saved `closed` flag
-- and close the window -- and with it the container -- the moment it opened.
--
-- Back on now that the replay is sound. It was held off while the reopening
-- itself was still wrong: fixing the OTML-safe key made getSettings return
-- something for a container window for the first time, and with the layout
-- being erased at every logout the first run with it live had nothing sensible
-- to apply.
--
-- A window the player dragged free of the panel is the case this serves, and it
-- is also the safe one: it gets setParent + setPosition and disturbs nothing
-- else. A DOCKED window only gets its height, which does re-lay out its
-- siblings in that panel -- that is what moved trainer and skills before.
ContainerRestore.RESTORE_GEOMETRY = true

function ContainerRestore.applyWindowSettings(window)
    -- A replay builds the layout one server answer at a time, and a route with
    -- no window already covering its start has to open its parent first and
    -- then step into it -- all of which the player would otherwise watch
    -- happen. Hold each window off screen and put the finished arrangement up
    -- in one go.
    if replaying then
        hiddenWindows[#hiddenWindows + 1] = window
        window:setVisible(false)
    end

    if not ContainerRestore.RESTORE_GEOMETRY then
        return
    end

    -- Height before minimize: minimize() records the current height as the one
    -- to restore to, so a collapsed 20px would otherwise become the saved size.
    local height = window:getSettings('height')
    if height and window:isResizeable() then
        window:setHeight(height)
    end

    local parentId = window:getSettings('parentId')
    local position = window:getSettings('position')
    if parentId and position then
        local parent = rootWidget:recursiveGetChildById(parentId)
        -- Only a window the player dragged free of the side panel is placed by
        -- coordinate. Docked ones are left to the panel, which stacks them in
        -- open order -- and the replay opens them in the order they were saved.
        if parent and parent:isVisible() and parent:getClassName() ~= 'UIMiniWindowContainer' then
            window:setParent(parent, true)
            window:setPosition(topoint(position))
        end
    end

    window:applyMinimizedPreference(false)
end

function ContainerRestore.install()
    if originalOpen then
        return
    end

    originalOpen = g_game.open
    originalOpenParent = g_game.openParent

    -- One wrapper covers every caller -- the context menu, the use shortcut,
    -- the up button, the bot -- because a module sandbox gets only __index to
    -- the globals and no __newindex (LuaInterface::newSandboxEnv), so this
    -- assignment lands in the real g_game table that all of them read.
    g_game.open = function(item, previousContainer)
        local path = pathToItem(item)
        local id = originalOpen(item, previousContainer)
        if id and id >= 0 then
            -- nil when the route could not be worked out, which clears any
            -- stale route left on this id by the window before it.
            paths[id] = path
        end
        return id
    end

    g_game.openParent = function(container)
        if container and container:hasParent() then
            local path = paths[container:getId()]
            if path and #path > 1 then
                paths[container:getId()] = copyPath(path, #path - 1)
            end
        end
        return originalOpenParent(container)
    end
end

function ContainerRestore.uninstall()
    if not originalOpen then
        return
    end

    g_game.open = originalOpen
    g_game.openParent = originalOpenParent
    originalOpen = nil
    originalOpenParent = nil
end
