-- Stackable stash: the window, and the Stash Stackables menu entry.
--
-- The server owns everything real here. This module draws what it is sent,
-- asks for withdrawals, and names the bag to stow -- it never decides what is
-- stackable and never tracks amounts of its own.
--
-- TILES ARE DRAWN, NOT STORED. The server sends one entry per item type with a
-- total; the grid splits that total into ceil(total / perTile) cells. So
-- clicking any of an item's three cells offers the whole stored amount, not
-- that cell's share -- there is no such thing as "this cell's items" on the
-- server side.
DEPOT_OPCODE = 74

local window
local amountWindow
local perTile = 1000
local tileCount = 120
-- The last payload, kept so changing a filter or typing in the search box
-- redraws from memory instead of asking the server again.
local lastData
local activeFilter
local searchText = ''
-- {[serverId] = {count, clientId, name}} as last drawn, so a tile click knows
-- what to ask for.
local stored = {}

local function send(message)
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedOpcode(DEPOT_OPCODE, json.encode(message))
    end
end

local function closeAmountWindow()
    if amountWindow then
        amountWindow:destroy()
        amountWindow = nil
    end
end

function close()
    closeAmountWindow()
    if window and window:isVisible() then
        window:hide()
    end

    -- Cleared rather than kept: reopening behind a filter that hides
    -- everything reads as an empty depot.
    activeFilter = nil
    searchText = ''
    if window then
        window:getChildById('searchEdit'):setText('')
    end
end

-- Walking away shuts the window here and now. The server refuses stale requests
-- on its own, so this is the half that looks instant rather than the half that
-- is trusted.
local function onPositionChange()
    if window and window:isVisible() then
        close()
        send({a = 'close'})
    end
end

local function askAmount(serverId)
    local entry = stored[serverId]
    if not entry then
        return
    end

    -- Ctrl-click takes the lot, the way ctrl-dragging a stack moves all of it
    -- (gameinterface.lua). It only ASKS for everything: the server still
    -- refuses the whole withdraw and says why if it will not fit.
    if g_keyboard.isCtrlPressed() then
        send({a = 'w', s = serverId, n = entry.count})
        return
    end

    closeAmountWindow()
    amountWindow = g_ui.createWidget('DepotAmountWindow', rootWidget)
    amountWindow:setText(entry.name)

    local maximum = entry.count
    local sprite = amountWindow:getChildById('item')
    sprite:setItemId(entry.clientId)

    local scrollbar = amountWindow:getChildById('countScrollBar')
    scrollbar:setMinimum(1)
    scrollbar:setMaximum(maximum)
    scrollbar:setValue(math.min(maximum, 100))

    -- The scroll bar is the only control: no typed entry, so there is no
    -- second widget to keep in step with it. The amount is shown on a label
    -- rather than painted on the item sprite the way the client own count
    -- window does it, because a depot total outgrows a sprite count.
    local label = amountWindow:getChildById('amountLabel')
    scrollbar.onValueChange = function(self, value)
        label:setText(value .. ' of ' .. maximum)
    end
    label:setText(scrollbar:getValue() .. ' of ' .. maximum)

    amountWindow:getChildById('buttonOk').onClick = function()
        send({a = 'w', s = serverId, n = scrollbar:getValue()})
        closeAmountWindow()
    end
    amountWindow:getChildById('buttonCancel').onClick = closeAmountWindow
end

-- Whether an entry survives the current filter and search box. The tile count
-- shown always reflects the WHOLE depot, not the filtered view -- it is a
-- capacity reading, and hiding part of it behind a filter would misreport it.
local function passes(entry)
    if activeFilter and entry.g ~= activeFilter then
        return false
    end
    if searchText ~= '' and not entry.n:lower():find(searchText, 1, true) then
        return false
    end
    return true
end

local function populate(data)
    -- Floored at one: the cell split below divides by this and subtracts the
    -- result, so a zero would never reduce `remaining` and the loop would never
    -- end.
    perTile = math.max(1, tonumber(data.perTile) or perTile)
    tileCount = tonumber(data.tiles) or tileCount

    stored = {}
    local grid = window:getChildById('grid')
    grid:destroyChildren()

    local used, drawn = 0, 0
    for _, entry in ipairs(type(data.items) == 'table' and data.items or {}) do
        -- An entry missing its server id, count or name cannot be drawn or
        -- clicked, and the id is a table index: a nil one would throw.
        if type(entry) == 'table' and entry.s ~= nil and type(entry.c) == 'number'
            and type(entry.n) == 'string' then
            stored[entry.s] = {count = entry.c, clientId = entry.i, name = entry.n}
            used = used + math.ceil(entry.c / perTile)

            if passes(entry) then
                -- Full cells first, then whatever is left over in the last one.
                local remaining = entry.c
                while remaining > 0 do
                    local onTile = math.min(remaining, perTile)
                    local tile = g_ui.createWidget('DepotTile', grid)
                    tile:getChildById('sprite'):setItemId(entry.i)
                    tile:getChildById('amount'):setText(onTile)
                    tile:setTooltip(entry.n .. ' (' .. entry.c .. ' stored)')
                    tile.onClick = function()
                        askAmount(entry.s)
                    end

                    remaining = remaining - onTile
                    drawn = drawn + 1
                end
            end
        end
    end

    -- Empty cells are drawn too, so the grid reads as a fixed set of slots
    -- filling up rather than a list that happens to be short.
    for _ = drawn + 1, tileCount do
        g_ui.createWidget('DepotTile', grid)
    end

    -- Only market deliveries can take a stash over; stowing is refused until
    -- it is back under.
    local usage = 'Tiles used: ' .. used .. ' / ' .. tileCount
    if used > tileCount then
        usage = usage .. ' (over the limit -- withdraw before stashing more)'
    end
    window:getChildById('usage'):setText(usage)
end

-- Redraws from the payload already in hand. Changing a filter or typing in
-- the search box never asks the server for anything.
local function redraw()
    if lastData and window and window:isVisible() then
        populate(lastData)
    end
end

-- One button per category the server declared, plus All in front. Rebuilt on
-- every payload so a category added server-side appears without a client edit.
function buildFilters(categories)
    local row = window:getChildById('filters')
    row:destroyChildren()

    local buttons = {}
    local function select(key)
        activeFilter = key
        for buttonKey, button in pairs(buttons) do
            button:setOn(buttonKey == (key or 'all'))
        end
        redraw()
    end

    local function add(key, label, filterKey)
        local button = g_ui.createWidget('FilterButton', row)
        button:setText(label)
        button:setWidth(math.max(60, button:getTextSize().width + 20))
        button.onClick = function() select(filterKey) end
        buttons[key] = button
    end

    add('all', 'All', nil)
    for _, category in ipairs(type(categories) == 'table' and categories or {}) do
        -- The key is a table index here, so a category without one has to be
        -- skipped rather than throwing the whole row away.
        if type(category) == 'table' and category.key ~= nil then
            add(category.key, category.label or tostring(category.key), category.key)
        end
    end

    -- Keeps the chosen filter across a refresh, unless the server stopped
    -- offering it.
    if activeFilter and not buttons[activeFilter] then
        activeFilter = nil
    end
    select(activeFilter)
end

function onExtendedOpcode(protocol, code, buffer)
    if code ~= DEPOT_OPCODE then
        return
    end

    local ok, data = pcall(json.decode, buffer)
    if not ok or type(data) ~= 'table' then
        return
    end

    data = JsonChunks.receive(DEPOT_OPCODE, data, 'items')
    if not data then
        return
    end

    -- A payload arriving after terminate() (or before init finished) has no
    -- window to draw into; every branch below touches one.
    if not window then
        return
    end

    if data.action == 'close' then
        close()
        return
    end

    if data.action == 'open' then
        lastData = data
        buildFilters(data.categories)
        populate(data)
        window:show()
        window:raise()
        window:focus()
    elseif data.action == 'refresh' and window:isVisible() then
        lastData = data
        buildFilters(data.categories)
        populate(data)
    end
end

-- Whether the Stash Stackables row belongs on this thing's menu. Containers
-- only: the server walks whatever it is handed, and handing it a sword would
-- just be a wasted round trip.
function canStow(thing)
    return thing and thing:isItem() and thing:isContainer()
end

-- The same addressing game_protect uses: a container slot reaches the server as
-- x = 0xFFFF, y = 0x40 + containerId, z = slot, a worn item as x = 0xFFFF,
-- y = slot, and anything else as its real map position.
function stow(thing)
    if not canStow(thing) then
        return
    end

    local position = thing:getPosition()
    if not position then
        return
    end

    send({
        a = 'stow',
        p = {x = position.x, y = position.y, z = position.z},
        sp = thing:getStackPos(),
    })
end

function init()
    window = g_ui.displayUI('stackabledepot')
    window:hide()

    -- Filtering is local to what the window already holds, so typing costs
    -- nothing and never waits on the server.
    window:getChildById('searchEdit').onTextChange = function(self, text)
        searchText = text:lower()
        redraw()
    end
    window:getChildById('closeButton').onClick = function()
        close()
        send({a = 'close'})
    end

    connect(LocalPlayer, {onPositionChange = onPositionChange})
    connect(g_game, {onGameEnd = close})
    ProtocolGame.registerExtendedOpcode(DEPOT_OPCODE, onExtendedOpcode)
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(DEPOT_OPCODE, onExtendedOpcode)
    disconnect(g_game, {onGameEnd = close})
    disconnect(LocalPlayer, {onPositionChange = onPositionChange})

    closeAmountWindow()
    if window then
        window:destroy()
        window = nil
    end
end
