-- Server -> client, '|'-separated: "set|<creatureId>|<#rrggbb>|<text>",
-- "clear|<creatureId>", "reset" ahead of a full list, and "owned|<json>" (the
-- titles the outfit window may offer). Client -> server: "list" and
-- "choose|<titleId>|<colorIndex>". The 8.60 creature packet has no title field;
-- the server half is data/scripts/titles/titles.lua.
local TITLES_OPCODE = 81

-- Kept by id rather than only on the Creature, because a creature leaving view
-- and coming back can arrive as a fresh object wearing nothing.
local titles = {}
local ownedCallback = nil

local function apply(creature)
    local entry = titles[creature:getId()]
    if entry then
        creature:setTitle(entry.text, entry.color)
    elseif creature:getTitle() ~= '' then
        creature:clearTitle()
    end
end

local function applyById(id)
    local creature = g_map.getCreatureById(id)
    if creature then
        apply(creature)
    end
end

local function send(message)
    local protocolGame = g_game.isOnline() and g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedOpcode(TITLES_OPCODE, message)
    end
end

local function onOpcode(protocol, opcode, buffer)
    if buffer:sub(1, 6) == 'owned|' then
        local ok, data = pcall(json.decode, buffer:sub(7))
        if not ok or type(data) ~= 'table' then
            g_logger.error('[game_titles] bad owned payload: ' .. tostring(data))
            return
        end
        if ownedCallback then
            ownedCallback(data)
        end
        return
    end

    local verb, id, color, text = buffer:match('^(%a+)|?(%d*)|?([^|]*)|?(.*)$')
    id = tonumber(id)
    if verb == 'reset' then
        local old = titles
        titles = {}
        for oldId in pairs(old) do
            applyById(oldId)
        end
    elseif verb == 'set' and id then
        titles[id] = { text = text, color = color }
        applyById(id)
    elseif verb == 'clear' and id then
        titles[id] = nil
        applyById(id)
    end
end

-- The outfit window's half: ask for the titles this player owns, and pick one.
-- The callback gets { staff, current, color, palette = {hex...}, titles = {{id, text}...} }
-- every time the server answers, which is after a "list" and after every "choose".
function requestOwned(callback)
    ownedCallback = callback
    send('list')
end

function stopOwned()
    ownedCallback = nil
end

function choose(titleId, colorIndex)
    send(string.format('choose|%d|%d', titleId, colorIndex))
end

local function onGameEnd()
    titles = {}
    ownedCallback = nil
end

function init()
    ProtocolGame.registerExtendedOpcode(TITLES_OPCODE, onOpcode)
    connect(Creature, { onAppear = apply })
    connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(TITLES_OPCODE)
    disconnect(Creature, { onAppear = apply })
    disconnect(g_game, { onGameEnd = onGameEnd })
end
