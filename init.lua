-- this is the first file executed when the application starts
-- we have to load the first modules form here

Services = {
    -- Client auto-updater. Set `repository` to the PUBLIC mirror repo that carries the
    -- shipped client tree and its releases, then flip `enabled` to true.
    -- The manifest URLs are derived from `repository` unless set explicitly.
    updater = {
        enabled = true,
        repository = "DutchEnglishman/OTCLIENT-PUBLIC",
        timeout = 30,
        -- Stall timeout: how long the updater tolerates NO progress before giving up.
        -- Not a deadline -- a 55 MB sprite sheet may legitimately take minutes.
        overallTimeout = 60000,
        retries = 3,
        strictManifestSha256 = true,
        allowExecutableUpdate = true,
        allowDeletions = true,
        -- Never written or deleted by the updater, whatever the manifest says.
        -- `data/things/**` is deliberately NOT here: sprites ship through the updater.
        -- Anything added back must also be added to -ManifestExclude in make_release.ps1,
        -- because a manifest naming a protected path is rejected in full.
        protectedPaths = {
            "config.otml", "config.ini", "*.log",
            "data/sounds/**", "mods/**", "downloads/**"
        }
    }, -- ./updater
    --status = "http://localhost/login.php", --./client_entergame | ./client_topmenu
    --websites = "http://localhost/?subtopic=accountmanagement", --./client_entergame "Forgot password and/or email"
    --createAccount = "http://localhost/clientcreateaccount.php", --./client_entergame -- createAccount.lua
    --getCoinsUrl = "http://localhost/?subtopic=shop&step=terms", --./game_market
    clientAssets = {
        enabled = true,
        repository = "dudantas/tibia-client",
        installSounds = true,
        strictManifestSha256 = true,
        allowRawFallbackHashMismatch = false,
        allowMissingPackedRawFallback = true,
        preferArchive = true,
        fallbackToArchiveOnManifestFailure = false,
        installArchiveExtras = true,
        archiveExtraPrefixes = { "bin" },
        installPackagedFiles = true
    }, -- ./client_assets
}

--- Enables or disables the entire server configuration block.
-- Set to `false` to disable all configuration below.
local ENABLE_SERVERS = true

---
-- @module Servers_init
-- Configuration table for all servers used by the system.
--
-- This entire block is conditionally enabled based on ENABLE_SERVERS.
-- When ENABLE_SERVERS == false, everything is ignored/disabled.
--

---
-- Server configuration system for multi-server or multi-world clients.
--
-- This structure allows a single client build to connect to multiple servers
-- without requiring duplicate client folders.
--
-- A server that hosts several worlds, or that provides a separate test environment,
-- can simply define additional entries inside this configuration table.
--
-- Instead of maintaining multiple client installations (one per world/server),
-- the client can switch between servers by selecting the desired configuration entry.
-- This simplifies testing, avoids redundant directories, and centralizes connection settings.
--
-- The ENABLE_SERVERS flag allows the entire configuration block to be enabled or disabled
-- without deleting or commenting out individual entries.
--

---
-- The world's name, as shown in the login screen's Server dropdown.
--
-- One name per edition we launch, so this is the single line that changes when
-- a new world opens. Nothing else should spell it out: read WORLD_NAME rather
-- than repeating the string, or the next edition ships under two names.
--
-- The server keeps its own copy in config.lua (serverName), which is what the
-- character list's World column shows and what the status protocol advertises.
-- The two are not wired together, so a new edition has to change both.
WORLD_NAME = "Shattered Realm"

Servers_init = {}

if ENABLE_SERVERS then

    ---
    -- List of servers and their configuration parameters.
    -- Each entry defines port, protocol, and authentication options.
    -- @table Servers_init
    --
    -- The login screen's "Server" dropdown is exactly this table
    -- (client_entergame/entergame.lua): one row per entry, shown by `name`,
    -- keyed by the host it connects to. There is no host, port or client
    -- version field on the screen any more, so an entry here is the only
    -- way to reach a server.
    -- @table Servers_init
    -- @field name Text shown in the dropdown; WORLD_NAME above, not a literal
    -- @field port TCP port of the login server
    -- @field protocol Client version to speak
    -- @field httpLogin Whether the login goes over HTTP instead of the game protocol
    -- @field useAuthenticator Whether the server asks for a two-factor token
    --
    Servers_init = {
        ["95.216.205.57"] = {
            name = WORLD_NAME,
            port = 7171,
            protocol = 860,
            httpLogin = false,
            useAuthenticator = false
        }
    }
end

g_app.setName("OTClient - Shattered Realms");
g_app.setCompactName("otclient");
g_app.setOrganizationName("otcr");

-- Evaluated once: the consumers below test this at both init() and terminate(), and a
-- value that changed mid-session would leave a connect() without its disconnect().
local UPDATER_ENABLED = (function()
    local updater = Services and Services.updater
    if type(updater) == 'table' then
        return updater.enabled ~= false and (updater.manifestUrl ~= nil or updater.repository ~= nil)
    end
    return type(updater) == 'string' and updater ~= ''
end)()

g_app.hasUpdater = function()
    return UPDATER_ENABLED and g_modules.getModule("updater") ~= nil
end

-- setup logger
g_logger.setLogFile(g_resources.getWorkDir() .. g_app.getCompactName() .. '.log')
g_logger.info("Operating system: " .. g_platform.getOSName())

-- print first terminal message
g_logger.info(g_app.getName() .. ' ' .. g_app.getVersion() .. ' rev ' .. g_app.getBuildRevision() .. ' (' ..
    g_app.getBuildCommit() .. ') built on ' .. g_app.getBuildDate() .. ' for arch ' ..
    g_app.getBuildArch())

-- setup lua debugger
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    require("lldebugger").start()
    g_logger.debug("Started LUA debugger.")
else
    g_logger.debug("LUA debugger not started (not launched with VSCode local-lua).")
end

-- add data directory to the search path
if not g_resources.addSearchPath(g_resources.getWorkDir() .. 'data', true) then
    g_logger.fatal('Unable to add data directory to the search path.')
end

-- add modules directory to the search path
if not g_resources.addSearchPath(g_resources.getWorkDir() .. 'modules', true) then
    g_logger.fatal('Unable to add modules directory to the search path.')
end

g_html.addGlobalStyle('/data/styles/html.css')
g_html.addGlobalStyle('/data/styles/custom.css')

-- try to add mods path too
g_resources.addSearchPath(g_resources.getWorkDir() .. 'mods', true)

-- setup directory for saving configurations
g_resources.setupUserWriteDir(('%s/'):format(g_app.getCompactName()))

-- search all packages
g_resources.searchAndAddPackages('/', '.otpkg', true)

-- load settings
g_configs.loadSettings('/config.otml')

g_modules.discoverModules()

-- libraries modules 0-99
g_modules.autoLoadModules(99)
g_modules.ensureModuleLoaded('corelib')
g_modules.ensureModuleLoaded('gamelib')
g_modules.ensureModuleLoaded('modulelib')
g_modules.ensureModuleLoaded("startup")

g_modules.autoLoadModules(999)
g_modules.ensureModuleLoaded('game_shaders') -- pre load

local function loadModules()
    -- client modules 100-499
    g_modules.autoLoadModules(499)
    g_modules.ensureModuleLoaded('client')

    -- game modules 500-999
    g_modules.autoLoadModules(999)
    g_modules.ensureModuleLoaded('game_interface')
    g_modules.ensureModuleLoaded('game_autoloot')
    -- mods 1000-9999
    g_modules.autoLoadModules(9999)
    --g_modules.ensureModuleLoaded('client_mods')

    local script = '/' .. g_app.getCompactName() .. 'rc.lua'

    if g_resources.fileExists(script) then
        dofile(script)
    end

    -- uncomment the line below so that modules are reloaded when modified. (Note: Use only mod dev)
    -- g_modules.enableAutoReload()
end

-- run updater, must use data.zip
if g_app.hasUpdater() then
    g_modules.ensureModuleLoaded("updater")
    return Updater.init(loadModules)
end

loadModules()
