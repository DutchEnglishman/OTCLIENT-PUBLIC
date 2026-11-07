-- Carries a character's saved client settings over to its new name after a Name
-- Change in the coin shop (GameShop.services.name, the server's
-- data/game_shop/game_shop_core.lua). Everything below is saved under the
-- character's name, so without this a rename starts the character from scratch.
--
-- The server sends "old|new" while the old character is still online. Nothing
-- is moved then: the logout that follows saves the old session (hotkeys, open
-- channels, window layout) under the old name once more. The move runs at the
-- next login as the new name, from CharacterList's tryLogin, before any module's
-- onGameStart reads its settings.
--
-- A new per-character store needs a line in moveAll, or a rename loses it.
CharacterRename = {}

local OPCODE = 207
local PENDING_NODE = 'pendingCharacterRenames'

-- Moves t[old] to t[new] unless the new name already has its own.
local function moveKey(t, old, new)
    if type(t) ~= 'table' or t[old] == nil then
        return false
    end
    if t[new] == nil then
        t[new] = t[old]
    end
    t[old] = nil
    return true
end

local function moveNodeKey(nodeName, old, new)
    local node = g_settings.getNode(nodeName)
    if moveKey(node, old, new) then
        g_settings.setNode(nodeName, node)
    end
end

local function moveNode(oldName, newName)
    local node = g_settings.getNode(oldName)
    if node == nil then
        return
    end
    if g_settings.getNode(newName) == nil then
        g_settings.setNode(newName, node)
    end
    g_settings.remove(oldName)
end

local function moveJsonFileKey(path, old, new)
    if not g_resources.fileExists(path) then
        return
    end
    local ok, data = pcall(function()
        return json.decode(g_resources.readFileContents(path))
    end)
    if not ok or type(data) ~= 'table' then
        g_logger.warning(string.format('CharacterRename: could not read %s, %s keeps nothing from it', path, new))
        return
    end
    if moveKey(data, old, new) then
        g_resources.writeFileContents(path, json.encode(data))
    end
end

local function moveAll(old, new, world)
    -- game_hotkeys: the character's node sits at the root, or under the server
    -- host when hotkeys are saved per server.
    local hotkeys = g_settings.getNode('game_hotkeys')
    if type(hotkeys) == 'table' then
        local moved = moveKey(hotkeys, old, new)
        for _, perHost in pairs(hotkeys) do
            moved = moveKey(perHost, old, new) or moved
        end
        if moved then
            g_settings.setNode('game_hotkeys', hotkeys)
        end
    end

    moveNodeKey('CharMiniWindows', old, new)
    moveNodeKey('lastChannelsOpen', old, new)
    moveNodeKey('LastCombatControls', old, new)
    moveNodeKey('healthcircle_skilltypes', old, new)

    -- game_healthcircle holds its table from client start and writes all of it
    -- back on the next change, which would bring the old key back.
    local healthcircle = modules.game_healthcircle
    if healthcircle and type(healthcircle.skillTypes) == 'table' then
        moveKey(healthcircle.skillTypes, old, new)
    end

    for _, tracker in ipairs({ 'bestiaryTracker', 'bosstiaryTracker' }) do
        local oldKey, newKey = tracker .. '_' .. old, tracker .. '_' .. new
        local node = g_settings.getNode(oldKey)
        if type(node) == 'table' and node.character then
            node.character = new
            g_settings.setNode(oldKey, node)
        end
        moveNode(oldKey, newKey)
    end

    if world then
        moveNode('containerLayout_' .. world:lower() .. '_' .. old:lower(),
                 'containerLayout_' .. world:lower() .. '_' .. new:lower())
    end

    local bot = g_settings.getNode('bot')
    if type(bot) == 'table' then
        local moved = false
        for key in pairs(table.copy(bot)) do
            local version = type(key) == 'string' and key:match('^' .. old .. '_(%d+)$')
            if version then
                moved = moveKey(bot, key, new .. '_' .. version) or moved
            end
        end
        if moved then
            g_settings.setNode('bot', bot)
        end
    end

    moveJsonFileKey('/settings/outfit.json', old, new)

    -- A keybind preset is only tied to a character by name, through the
    -- "switch preset to the character's name" option.
    if Keybind and Keybind.presetToIndex and Keybind.presetToIndex[old] and not Keybind.presetToIndex[new] then
        Keybind.renamePreset(old, new)
    end

    g_settings.save()
end

local function onRenamed(protocol, opcode, buffer)
    local old, new = buffer:match('^([^|]+)|([^|]+)$')
    if not old then
        g_logger.warning('CharacterRename: unreadable rename message: ' .. buffer)
        return
    end

    local pending = g_settings.getNode(PENDING_NODE) or {}
    -- A second rename before logging in as the first new name cannot happen:
    -- renaming needs the character online, which needs that login.
    pending[new] = { old = old, world = g_game.getWorldName() }
    g_settings.setNode(PENDING_NODE, pending)
    g_settings.save()
end

-- Called with the character about to log in, while no game session is running.
function CharacterRename.applyPending(characterName)
    local pending = g_settings.getNode(PENDING_NODE)
    if type(pending) ~= 'table' or type(pending[characterName]) ~= 'table' then
        return
    end

    local entry = pending[characterName]
    pending[characterName] = nil
    if next(pending) then
        g_settings.setNode(PENDING_NODE, pending)
    else
        g_settings.remove(PENDING_NODE)
    end

    moveAll(entry.old, characterName, entry.world)
    g_logger.info(string.format('CharacterRename: settings of %s moved to %s', entry.old, characterName))
end

ProtocolGame.registerExtendedOpcode(OPCODE, onRenamed)
