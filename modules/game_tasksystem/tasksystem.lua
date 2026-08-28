-- Custom task/bestiary progress window. Talks to the server over a plain
-- extended opcode (53) using simple delimited text -- NOT the real Tibia
-- Bestiary protocol -- since this project's client version (860) is below
-- the 1310 OTCLIENT's own game_cyclopedia module requires to even load, so
-- the real Bestiary tab is unreachable regardless of server support. See
-- data/creaturescripts/scripts/others/task_system_opcode.lua (OTSERV) for
-- the matching server-side handler and the wire format both sides use.
TaskSystemUI = {}

local EXTENDED_OPCODE = 53

-- Bare global, not TaskSystemUI.toggle directly -- tasksystem.otui's
-- @onClick/@onEscape handlers are evaluated as "modules.game_tasksystem.X()"
-- expressions, which only resolve to a module's top-level globals, not
-- fields nested inside a table (see game_hotkeys' "function ok()" for the
-- same pattern). The mainpanel button and the keyboard shortcut don't go
-- through this -- they hold a direct reference to TaskSystemUI.toggle -- so
-- only the window's own close button and Escape key were ever broken.
function toggle()
    TaskSystemUI.toggle()
end

function onMonsterTileClick(tile)
    TaskSystemUI.showMonsterDetail(tile)
end

function onSearchTextChange(text)
    TaskSystemUI.onSearchTextChange(text)
end

local categoryDisplayNames = {}
local selectedCategoryKey = nil
local searchDebounceEvent = nil

local function sendMessage(message)
    if not g_game.isOnline() then
        return false
    end

    local protocolGame = g_game.getProtocolGame()
    if not protocolGame then
        return false
    end

    protocolGame:sendExtendedOpcode(EXTENDED_OPCODE, message)
    return true
end

local function capitalize(name)
    return name:gsub('^%l', string.upper)
end

function TaskSystemUI.init()
    TaskSystemUI.window = g_ui.displayUI('tasksystem')
    TaskSystemUI.window:hide()

    local categoriesList = TaskSystemUI.window:getChildById('categoriesList')
    categoriesList.onChildFocusChange = function(_, focusedChild)
        if focusedChild then
            TaskSystemUI.selectCategory(focusedChild:getId())
        end
    end

    -- g_keyboard.bindKeyDown/bindKeyPress (what spell hotkeys and WASD use)
    -- are global listeners that fire regardless of which widget has focus --
    -- focus alone does NOT suppress them. grabKeyboard() is the only thing
    -- that does: it routes all keyboard input exclusively to one widget
    -- until released. Without this, every keystroke here was also triggering
    -- whatever hotkey that letter was bound to.
    local searchEdit = TaskSystemUI.window:getChildById('searchEdit')
    searchEdit.onFocusChange = function(widget, focused)
        if focused then
            widget:grabKeyboard()
        else
            widget:ungrabKeyboard()
        end
    end

    ProtocolGame.registerExtendedOpcode(EXTENDED_OPCODE, TaskSystemUI.onExtendedOpcode)

    connect(g_game, {
        onGameEnd = TaskSystemUI.onGameEnd
    })

    -- Fallback entry point, independent of the mainpanel button below.
    -- Uses the Keybind system (like game_hotkeys' own Ctrl+K toggle), not
    -- raw g_keyboard.bindKeyDown -- a panel-scoped binding stops firing once
    -- this window (or a focusable child inside it, e.g. a clicked category)
    -- holds keyboard focus, which is exactly why Ctrl+Shift+K opened the
    -- window fine but wouldn't close it again.
    Keybind.new("Windows", "Show/hide Task System", "Ctrl+Shift+K", "")
    Keybind.bind("Windows", "Show/hide Task System", {
        {
            type = KEY_DOWN,
            callback = TaskSystemUI.toggle,
        }
    })

    -- "Task System" topbar button removed by request -- the window itself
    -- still works and is still reachable via its Ctrl+Shift+K keybind above.
end

function TaskSystemUI.terminate()
    disconnect(g_game, {
        onGameEnd = TaskSystemUI.onGameEnd
    })

    ProtocolGame.unregisterExtendedOpcode(EXTENDED_OPCODE)

    Keybind.delete("Windows", "Show/hide Task System")

    if TaskSystemUI.button then
        TaskSystemUI.button:destroy()
        TaskSystemUI.button = nil
    end
    if TaskSystemUI.window then
        TaskSystemUI.window:destroy()
        TaskSystemUI.window = nil
    end
end

function TaskSystemUI.onGameEnd()
    if TaskSystemUI.window then
        TaskSystemUI.window:getChildById('searchEdit'):ungrabKeyboard()
        TaskSystemUI.window:hide()
    end
end

function TaskSystemUI.toggle()
    if not TaskSystemUI.window then
        return
    end

    if TaskSystemUI.window:isVisible() then
        -- Safety net: releases the grab even if this closed some other way
        -- than the search box first losing focus normally (e.g. Escape).
        -- Harmless no-op if it wasn't the current keyboard receiver.
        TaskSystemUI.window:getChildById('searchEdit'):ungrabKeyboard()
        TaskSystemUI.window:hide()
        return
    end

    TaskSystemUI.window:show()
    TaskSystemUI.window:raise()
    TaskSystemUI.window:focus()

    sendMessage('CATEGORIES')
    sendMessage('TASKPOINTS')
end

function TaskSystemUI.selectCategory(tierKey)
    selectedCategoryKey = tierKey

    removeEvent(searchDebounceEvent)
    searchDebounceEvent = nil

    -- false = don't fire @onTextChange -- onSearchTextChange('') would just
    -- re-request this same category, harmlessly, but there's no reason to
    -- make it do that.
    local searchEdit = TaskSystemUI.window:getChildById('searchEdit')
    searchEdit:setText('', false)

    sendMessage('MONSTERS|' .. tierKey)
end

-- Debounced (300ms after the last keystroke) since every search is a server
-- round trip across every category -- typing fast shouldn't fire one request
-- per character.
function TaskSystemUI.onSearchTextChange(text)
    text = text:trim()

    removeEvent(searchDebounceEvent)
    searchDebounceEvent = nil

    if text == '' then
        if selectedCategoryKey then
            sendMessage('MONSTERS|' .. selectedCategoryKey)
        end
        return
    end

    searchDebounceEvent = scheduleEvent(function()
        searchDebounceEvent = nil
        sendMessage('SEARCH|' .. text)
    end, 300)
end

function TaskSystemUI.onExtendedOpcode(_protocol, opcode, buffer)
    if opcode ~= EXTENDED_OPCODE then
        return
    end

    local command, payload = buffer:match('^([^|]+)|?(.*)$')
    if not command then
        return
    end

    if command == 'CATEGORIES' then
        TaskSystemUI.populateCategories(payload)
    elseif command == 'MONSTERS' then
        local tierKey, listPayload = payload:match('^([^|]+)|?(.*)$')
        if tierKey then
            TaskSystemUI.populateMonsters(tierKey, listPayload)
        end
    elseif command == 'SEARCH' then
        TaskSystemUI.populateSearchResults(payload)
    elseif command == 'TASKPOINTS' then
        TaskSystemUI.setTaskPoints(payload)
    end
end

function TaskSystemUI.populateCategories(payload)
    if not TaskSystemUI.window then
        return
    end

    local list = TaskSystemUI.window:getChildById('categoriesList')
    list:destroyChildren()
    categoryDisplayNames = {}

    for record in payload:gmatch('[^;]+') do
        local key, name, unlocked, total = record:match('^([^,]+),([^,]+),(%d+),(%d+)$')
        if key then
            categoryDisplayNames[key] = name

            local label = g_ui.createWidget('TaskListLabel', list)
            label:setId(key)
            label:setText(string.format('%s (%s/%s)', name, unlocked, total))
        end
    end
end

-- Shared by populateMonsters (one category) and populateSearchResults
-- (matches across every category) -- both just hand this a flat records
-- payload in the same "name,killCount,stagesDone,lookType,..." shape.
local function populateMonsterTiles(list, payload)
    list:destroyChildren()

    for record in payload:gmatch('[^;]+') do
        local name, killCount, stagesDone, lookType, lookHead, lookBody, lookLegs, lookFeet, lookAddons =
            record:match('^([^,]+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)$')
        if name then
            local outfit = {
                type = tonumber(lookType),
                head = tonumber(lookHead),
                body = tonumber(lookBody),
                legs = tonumber(lookLegs),
                feet = tonumber(lookFeet),
                addons = tonumber(lookAddons),
            }

            local tile = g_ui.createWidget('TaskMonsterTile', list)
            tile:setId(name)
            tile:getChildById('name'):setText(capitalize(name))
            tile:getChildById('creature'):setOutfit(outfit)

            -- Stashed on the widget for showMonsterDetail to read on click --
            -- OTUI widgets are plain Lua tables, so arbitrary fields like
            -- this are fine (unlike server-side TFS userdata objects). The
            -- outfit itself has to be stashed too: UICreature only binds
            -- setOutfit, not getOutfit, so there's no reading it back off
            -- the widget later.
            tile.killCount = tonumber(killCount)
            tile.stagesDone = tonumber(stagesDone)
            tile.outfit = outfit
        end
    end
end

function TaskSystemUI.populateMonsters(tierKey, payload)
    if not TaskSystemUI.window then
        return
    end

    local monstersLabel = TaskSystemUI.window:getChildById('monstersLabel')
    monstersLabel:setText(tr('Monsters') .. ' - ' .. (categoryDisplayNames[tierKey] or tierKey))

    populateMonsterTiles(TaskSystemUI.window:getChildById('monstersList'), payload)
end

function TaskSystemUI.populateSearchResults(payload)
    if not TaskSystemUI.window then
        return
    end

    local monstersLabel = TaskSystemUI.window:getChildById('monstersLabel')
    monstersLabel:setText(tr('Search results'))

    populateMonsterTiles(TaskSystemUI.window:getChildById('monstersList'), payload)
end

-- Opens (or replaces) a small popup with this tile's kill count/stage.
-- Loot table info is a planned follow-up, not built yet -- see the note in
-- MonsterDetailWindow's otui definition.
function TaskSystemUI.showMonsterDetail(tile)
    if TaskSystemUI.detailWindow then
        TaskSystemUI.detailWindow:destroy()
        TaskSystemUI.detailWindow = nil
    end

    local window = g_ui.createWidget('MonsterDetailWindow', rootWidget)
    TaskSystemUI.detailWindow = window
    window.onDestroy = function()
        TaskSystemUI.detailWindow = nil
    end

    window:getChildById('nameLabel'):setText(capitalize(tile:getId()))
    window:getChildById('killsLabel'):setText(tr('Kills') .. ': ' .. tile.killCount)
    window:getChildById('stageLabel'):setText(tr('Stage') .. ': ' .. tile.stagesDone .. '/4')
    window:getChildById('creature'):setOutfit(tile.outfit)
end

function TaskSystemUI.setTaskPoints(payload)
    -- TEMPORARY DIAGNOSTIC -- remove once the counter is confirmed working.
    if modules.game_console and modules.game_console.addText then
        modules.game_console.addText('[taskpoints] server sent: ' .. tostring(payload),
            modules.game_console.SpeakTypesSettings.privateRed, tr('Server Log'))
    end

    -- The inventory panel's counter is always live, so it updates whether or
    -- not this window happens to be open -- the server pushes on login and on
    -- every stage payout, not only in reply to this window's request.
    if modules.game_inventory and modules.game_inventory.setTaskPoints then
        modules.game_inventory.setTaskPoints(payload)
    end

    if not TaskSystemUI.window then
        return
    end

    local label = TaskSystemUI.window:getChildById('taskPointsLabel')
    label:setText(tr('Task Points') .. ': ' .. payload)
end
