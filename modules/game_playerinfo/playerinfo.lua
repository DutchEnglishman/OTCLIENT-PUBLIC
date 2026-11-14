-- The character's name, level and vocation in the window title
-- ("The Shattered Realms - Mike (Level 120 Elite Knight)") and in the Discord status.
-- 8.60 never sends the vocation, so the server sends its name over extended opcode 215
-- (OTSERV data/scripts/player_info/player_vocation.lua) at login, on reconnect and on a
-- promotion. The Discord line is built in C++ (src/main.cpp), which reads g_game.tsrVocation.

local PLAYER_VOCATION_OPCODE = 215

local vocation = ''

local function updateTitle()
    local player = g_game.getLocalPlayer()
    if not g_game.isOnline() or not player then
        g_window.setTitle(g_app.getName())
        return
    end
    local level = 'Level ' .. player:getLevel()
    if vocation ~= '' then
        level = level .. ' ' .. vocation
    end
    g_window.setTitle(g_app.getName() .. ' - ' .. g_game.getCharacterName() .. ' (' .. level .. ')')
end

local function onVocation(_protocol, _opcode, buffer)
    vocation = buffer or ''
    g_game.tsrVocation = vocation
    updateTitle()
end

local function online()
    updateTitle()
end

local function offline()
    vocation = ''
    g_game.tsrVocation = nil
    updateTitle()
end

local function onLevelChange()
    updateTitle()
end

function init()
    connect(g_game, { onGameStart = online, onGameEnd = offline })
    connect(LocalPlayer, { onLevelChange = onLevelChange })
    ProtocolGame.registerExtendedOpcode(PLAYER_VOCATION_OPCODE, onVocation)
    if g_game.isOnline() then
        online()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = online, onGameEnd = offline })
    disconnect(LocalPlayer, { onLevelChange = onLevelChange })
    ProtocolGame.unregisterExtendedOpcode(PLAYER_VOCATION_OPCODE)
    g_game.tsrVocation = nil
    g_window.setTitle(g_app.getName())
end
