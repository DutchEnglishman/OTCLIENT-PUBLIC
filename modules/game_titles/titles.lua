-- Server -> client, '|'-separated: "set|<creatureId>|<#rrggbb>|<text>",
-- "clear|<creatureId>", "reset" ahead of a full list, "owned|<json>" (the
-- titles the outfit window may offer), and at login
-- "bosses|<#rrggbb>|<text>|<prefix>,<prefix>|<name>|<name>|..." (the boss tag,
-- matched by lowercased display name, bare or after one variant prefix such as
-- "tainted "). Client -> server: "list" and
-- "choose|<titleId>|<colorIndex>". The 8.60 creature packet has no title field;
-- the server half is data/scripts/titles/titles.lua.
local TITLES_OPCODE = 81

-- Kept by id rather than only on the Creature, because a creature leaving view
-- and coming back can arrive as a fresh object wearing nothing.
local titles = {}
local ownedCallback = nil
local showOthers = true
local bossNames = {}
local bossPrefixes = {}
local bossTag = nil

-- Settings cannot hide it. Matched by text: Titles.list on the server never offers it.
local STAFF_TEXT = '[ADMIN]'

-- The player-titles setting hides players' titles, not the boss tag.
local function visible(creature, entry)
    if showOthers or entry.text == STAFF_TEXT or entry.boss then
        return true
    end
    local player = g_game.getLocalPlayer()
    return player ~= nil and player:getId() == creature:getId()
end

local function isBoss(creature)
    if not creature:isMonster() then
        return false
    end
    local name = creature:getName():lower()
    if bossNames[name] then
        return true
    end
    for _, prefix in ipairs(bossPrefixes) do
        if prefix ~= '' and name:sub(1, #prefix + 1) == prefix .. ' ' and bossNames[name:sub(#prefix + 2)] then
            return true
        end
    end
    return false
end

local function apply(creature)
    local entry = titles[creature:getId()]
    if not entry and bossTag and isBoss(creature) then
        entry = bossTag
    end
    if entry and visible(creature, entry) then
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

    if buffer:sub(1, 7) == 'bosses|' then
        local fields = buffer:sub(8):split('|')
        bossTag = { color = fields[1], text = fields[2], boss = true }
        bossPrefixes = (fields[3] or ''):split(',')
        bossNames = {}
        for i = 4, #fields do
            bossNames[fields[i]] = true
        end
        local player = g_game.getLocalPlayer()
        if player then
            for _, creature in ipairs(g_map.getSpectators(player:getPosition(), true)) do
                apply(creature)
            end
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

-- client_options' showPlayerTitles. Off hides every other player's title but
-- [ADMIN]; the titles stay remembered, so turning it back on shows them at once.
function setShowOthers(value)
    showOthers = value ~= false
    for id in pairs(titles) do
        applyById(id)
    end
end

local function onGameEnd()
    titles = {}
    ownedCallback = nil
    bossNames = {}
    bossPrefixes = {}
    bossTag = nil
end

function init()
    if modules.client_options then
        showOthers = modules.client_options.getOption('showPlayerTitles') ~= false
    end
    ProtocolGame.registerExtendedOpcode(TITLES_OPCODE, onOpcode)
    connect(Creature, { onAppear = apply })
    connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(TITLES_OPCODE)
    disconnect(Creature, { onAppear = apply })
    disconnect(g_game, { onGameEnd = onGameEnd })
end
