-- Dungeon browser. Talks to the server over extended opcode 75 with JSON
-- payloads, the same route game_crafting uses on 108. See OTSERV's
-- data/dungeons/ for the config the window renders and
-- data/scripts/dungeons/dungeons_registration.lua for the matching handler.
DungeonsUI = {}

local DUNGEONS_OPCODE = 75
local REQ_SLOTS = 3

-- Bare globals, not DungeonsUI fields: the otui's @onClick/@onEscape handlers
-- are evaluated as "modules.game_dungeons.X()" expressions, which resolve only
-- to a module's top-level globals and not to fields nested in a table (the same
-- reason game_tasksystem carries a bare toggle()).
function toggle()
    DungeonsUI.toggle()
end

function join()
    DungeonsUI.join()
end

local selectedKey = nil
local selectedTier = nil
local dungeonNames = {}

local function sendMessage(action, data)
    if not g_game.isOnline() then
        return false
    end

    local protocolGame = g_game.getProtocolGame()
    if not protocolGame then
        return false
    end

    protocolGame:sendExtendedOpcode(DUNGEONS_OPCODE, json.encode({action = action, data = data}))
    return true
end

-- The art lives here, in the client, and is found by the dungeon's key. A
-- dungeon whose banner has not been drawn yet returns nil and keeps the plain
-- titled panel, rather than asking the texture loader for a file that is not
-- there.
local function bannerSource(key)
    local path = '/game_dungeons/images/' .. key
    if g_resources.fileExists(path .. '.png') then
        return path
    end
end

local function formatTime(seconds)
    if not seconds then
        return '--'
    end

    return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

function DungeonsUI.init()
    DungeonsUI.window = g_ui.displayUI('dungeons')
    DungeonsUI.window:hide()

    local dungeonList = DungeonsUI.window:getChildById('dungeonList')
    dungeonList.onChildFocusChange = function(_, focusedChild)
        if focusedChild then
            DungeonsUI.selectDungeon(focusedChild:getId())
        end
    end

    ProtocolGame.registerExtendedOpcode(DUNGEONS_OPCODE, DungeonsUI.onExtendedOpcode)

    connect(g_game, {
        onGameEnd = DungeonsUI.onGameEnd
    })

    -- Keybind rather than a panel-scoped g_keyboard.bindKeyDown: a panel-scoped
    -- binding stops firing once this window (or a focusable child inside it,
    -- such as a clicked dungeon) holds keyboard focus, which would open the
    -- window fine but never close it again.
    Keybind.new("Windows", "Show/hide Dungeons", "Ctrl+Shift+D", "")
    Keybind.bind("Windows", "Show/hide Dungeons", {
        {
            type = KEY_DOWN,
            callback = DungeonsUI.toggle,
        }
    })
end

function DungeonsUI.terminate()
    disconnect(g_game, {
        onGameEnd = DungeonsUI.onGameEnd
    })

    ProtocolGame.unregisterExtendedOpcode(DUNGEONS_OPCODE)

    Keybind.delete("Windows", "Show/hide Dungeons")

    if DungeonsUI.window then
        DungeonsUI.window:destroy()
        DungeonsUI.window = nil
    end
end

function DungeonsUI.onGameEnd()
    if DungeonsUI.window then
        DungeonsUI.window:hide()
    end
end

function DungeonsUI.toggle()
    if not DungeonsUI.window then
        return
    end

    if DungeonsUI.window:isVisible() then
        DungeonsUI.window:hide()
        return
    end

    if not g_game.isOnline() then
        return
    end

    DungeonsUI.window:show()
    DungeonsUI.window:raise()
    DungeonsUI.window:focus()

    -- The keybind never reaches the server, so this is the only thing that
    -- fills the window; asking again on every open is also what picks up a
    -- config reload.
    sendMessage('list')
end

function DungeonsUI.selectDungeon(key)
    -- Reopening the window rebuilds the list and re-focuses the same dungeon,
    -- so only an actual change of dungeon drops the chosen tier. With no tier
    -- named the server answers with the dungeon's first and says which.
    if key ~= selectedKey then
        selectedTier = nil
    end

    selectedKey = key
    sendMessage('detail', {key = key, tier = selectedTier})
end

function DungeonsUI.selectTier(tierKey)
    if not selectedKey then
        return
    end

    selectedTier = tierKey
    sendMessage('detail', {key = selectedKey, tier = tierKey})
end

function DungeonsUI.join()
    if not selectedKey or not selectedTier then
        return
    end

    sendMessage('join', {key = selectedKey, tier = selectedTier})
end

local function fillList(dungeons)
    local window = DungeonsUI.window
    local dungeonList = window:getChildById('dungeonList')
    dungeonList:destroyChildren()
    dungeonNames = {}

    for _, dungeon in ipairs(dungeons) do
        local row = g_ui.createWidget('DungeonListLabel', dungeonList)
        row:setId(dungeon.key)
        row:setText(dungeon.name)
        dungeonNames[dungeon.key] = dungeon.name
    end

    local first = dungeonList:getChildByIndex(1)
    if not first then
        return
    end

    -- Focusing fires onChildFocusChange, which requests the detail.
    local keep = selectedKey and dungeonList:getChildById(selectedKey)
    local target = keep or first
    target:focus()
end

local function fillTiers(tiers, currentTier)
    local tierList = DungeonsUI.window:getChildById('tierList')
    tierList:destroyChildren()

    for _, tier in ipairs(tiers) do
        local button = g_ui.createWidget('DungeonTierButton', tierList)
        button:setText(tier.name)
        button:setOn(tier.key == currentTier)
        button.onClick = function()
            DungeonsUI.selectTier(tier.key)
        end
    end
end

local function fillBanner(key, name)
    local window = DungeonsUI.window
    local image = window:getChildById('bannerPanel'):getChildById('bannerImage')
    local source = bannerSource(key)

    if source then
        image:setImageSource(source)
        image:show()
    else
        image:hide()
    end

    window:getChildById('bannerPanel'):getChildById('bannerName'):setText(name)
end

local function fillRequirements(data)
    local panel = DungeonsUI.window:getChildById('reqPanel')

    panel:getChildById('levelReqLabel'):setText(tr('Level required') .. ': ' .. data.levelReq)
    panel:getChildById('levelReqLabel'):setColor(data.levelOk and '#c0c0c0' or '#d05050')

    local items = data.itemReq or {}
    for slot = 1, REQ_SLOTS do
        local widget = panel:getChildById('reqItem' .. slot)
        local req = items[slot]

        if req then
            widget:setItemId(req.id)
            widget:setItemCount(req.count)
            -- Money is counted across gold, platinum and crystal, so naming the
            -- coin the slot happens to draw would misstate what is checked.
            if req.money then
                widget:setTooltip(string.format('%d gold (you have %d)', req.count, req.have))
            else
                widget:setTooltip(string.format('%dx %s (you have %d)', req.count, req.name, req.have))
            end
            widget:show()
        else
            widget:setItemId(0)
            widget:setTooltip('')
            widget:hide()
        end
    end

    local lines = {}

    if #items == 0 then
        lines[#lines + 1] = tr('No items required.')
    else
        lines[#lines + 1] = tr('Held, not spent.')
    end

    -- The panel draws three slots; anything past that is named in text rather
    -- than silently dropped.
    for slot = REQ_SLOTS + 1, #items do
        lines[#lines + 1] = string.format('%dx %s', items[slot].count, items[slot].name)
    end

    -- Stated rather than checked: where the player is standing changes as they
    -- walk, so a button greyed out on it would go stale the moment they moved.
    -- The server enforces the rule itself, in Dungeons.join.
    lines[#lines + 1] = tr('Start from a protection zone.')

    panel:getChildById('reqNoteLabel'):setText(table.concat(lines, '\n'))
end

local function fillLeaderboard(panelId, rows)
    local rowsPanel = DungeonsUI.window:getChildById(panelId):getChildById('rows')
    rowsPanel:destroyChildren()

    if #rows == 0 then
        local empty = g_ui.createWidget('DungeonPanelTitle', rowsPanel)
        empty:setText(tr('No runs recorded yet.'))
        empty:setColor('#808080')
        return
    end

    for index, entry in ipairs(rows) do
        local row = g_ui.createWidget('DungeonRankRow', rowsPanel)
        row:getChildById('rank'):setText(index .. '.')
        row:getChildById('name'):setText(entry.name)
        row:getChildById('time'):setText(formatTime(entry.seconds))
    end
end

local function fillItemGrid(panelId, items)
    local grid = DungeonsUI.window:getChildById('rewardsPanel'):getChildById(panelId)
    grid:destroyChildren()

    for _, item in ipairs(items) do
        local widget = g_ui.createWidget('Item', grid)
        widget:setVirtual(true)
        widget:setItemId(item.id)
        widget:setTooltip(item.name)
    end
end

local function fillQueue(data)
    local panel = DungeonsUI.window:getChildById('queuePanel')

    panel:getChildById('queueLabel'):setText(formatTime(data.queue))
    panel:getChildById('blockedLabel'):setText(data.blocked or '')
    panel:getChildById('joinButton'):setEnabled(data.blocked == nil)
end

function DungeonsUI.onExtendedOpcode(_protocol, _opcode, buffer)
    local ok, message = pcall(json.decode, buffer)
    if not ok or type(message) ~= 'table' then
        return
    end

    local data = message.data or {}

    if message.action == 'list' then
        fillList(data.dungeons or {})
    elseif message.action == 'detail' then
        -- A reply for a dungeon the player has since clicked away from would
        -- repaint the panels with the wrong one.
        if data.key ~= selectedKey then
            return
        end

        selectedTier = data.tier
        -- The banner caption is the dungeon's own title, which is not always
        -- the shorter name the left-hand list carries.
        fillBanner(data.key, data.title or data.name or dungeonNames[data.key] or '')
        fillTiers(data.tiers or {}, data.tier)
        fillRequirements(data)
        fillLeaderboard('soloPanel', data.solo or {})
        fillLeaderboard('groupPanel', data.group or {})
        fillItemGrid('bossRewards', data.bossRewards or {})
        fillItemGrid('loot', data.loot or {})
        fillQueue(data)
    end
end
