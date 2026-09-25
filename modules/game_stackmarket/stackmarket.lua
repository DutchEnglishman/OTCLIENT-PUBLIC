-- Market for stackable goods: the window.
--
-- The server owns everything real: what may be traded, prices, balances, who
-- holds what. This module draws what it is sent and asks for things; every
-- request that changes something is answered with the outcome, the new
-- balances and the item's offers, so nothing here guesses at a result.
MARKET_OPCODE = 79

local GOLD, COINS = 0, 1

local window
local acceptWindow

-- Sent once per session: every stackable items.xml names, as
-- {s = server id, i = client id, n = name, g = category key}.
local catalog
local categories = {}
-- {[serverId] = {so = sell offers, bo = buy orders}}
local active = {}
local balance = {gold = 0, coins = 0}
local fees = {feePercent = 1, feeMin = 20, feeMax = 1000000, coinFee = 100}

local selectedItem
local selectedOffer
local selectedOwnOffer
local have = 0
local offers = {}

local searchText = ''
local categoryFilter
local onlyWithOffers = false

local createKind = 'sell'
local createCurrency = GOLD

local OFFER_COLUMNS = {
    {title = 'Player', width = 170},
    {title = 'Amount', width = 90},
    {title = 'Price each', width = 130},
    {title = 'Total', width = 140},
    {title = 'Expires', width = 80},
}

local MINE_COLUMNS = {
    {title = 'Item', width = 190},
    {title = 'Type', width = 80},
    {title = 'Amount', width = 90},
    {title = 'Price each', width = 150},
    {title = 'Total', width = 160},
    {title = 'Expires', width = 80},
}

local HISTORY_COLUMNS = {
    {title = 'Date', width = 130},
    {title = 'What happened', width = 660},
}

local function send(message)
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedOpcode(MARKET_OPCODE, json.encode(message))
    end
end

local function formatNumber(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    local formatted
    repeat
        text, formatted = text:gsub('^(%d+)(%d%d%d)', '%1,%2')
    until formatted == 0
    return text
end

local function formatPrice(amount, currency)
    return formatNumber(amount) .. (currency == COINS and ' coins' or ' gold')
end

local function formatExpiry(expiresAt)
    local left = (tonumber(expiresAt) or 0) - os.time()
    if left <= 0 then
        return 'soon'
    elseif left >= 86400 then
        return math.floor(left / 86400) .. 'd'
    end
    return math.max(1, math.floor(left / 3600)) .. 'h'
end

local function setStatus(text, ok)
    local label = window:getChildById('statusLabel')
    label:setText(text or '')
    label:setColor(ok == false and '#e06060' or '#80d080')
end

-- A row of cells laid out left to right by the column widths.
local function fillRow(row, columns, values, style)
    local x = 4
    for index, column in ipairs(columns) do
        local cell = g_ui.createWidget(style or 'MarketCell', row)
        cell:setMarginLeft(x)
        cell:setWidth(column.width - 6)
        cell:setText(values[index] or '')
        x = x + column.width
    end
end

local function buildHeader(header, columns)
    header:destroyChildren()
    local titles = {}
    for index, column in ipairs(columns) do
        titles[index] = column.title
    end
    fillRow(header, columns, titles, 'MarketHeaderCell')
end

local function closeAcceptWindow()
    if acceptWindow then
        acceptWindow:destroy()
        acceptWindow = nil
    end
end

function close()
    closeAcceptWindow()
    if window and window:isVisible() then
        window:hide()
    end
end

-- A new session may be a different server build with a different item list,
-- so the catalog is asked for again rather than kept.
local function onGameEnd()
    close()
    catalog = nil
    active = {}
    selectedItem = nil
end

local function onPositionChange()
    if window and window:isVisible() then
        close()
        send({a = 'close'})
    end
end

-- ------------------------------------------------------------------ Balances

local function drawBalance()
    window:getChildById('balance'):setText('Bank: ' .. formatPrice(balance.gold, GOLD)
        .. '     Premium coins: ' .. formatNumber(balance.coins))
end

-- ----------------------------------------------------------------- Item list

local function catalogEntry(serverId)
    for _, entry in ipairs(catalog or {}) do
        if entry.s == serverId then
            return entry
        end
    end
end

local function passes(entry)
    if categoryFilter and entry.g ~= categoryFilter then
        return false
    end
    if onlyWithOffers and not active[entry.s] then
        return false
    end
    if searchText ~= '' and not entry.n:lower():find(searchText, 1, true) then
        return false
    end
    return true
end

local function selectItem(serverId)
    selectedItem = serverId
    selectedOffer = nil
    offers = {}
    have = 0

    local panel = window:getChildById('browsePanel')
    local entry = catalogEntry(serverId)
    if entry then
        panel:getChildById('selectedSprite'):setItemId(entry.i)
        panel:getChildById('selectedName'):setText(entry.n)
    end
    panel:getChildById('selectedHave'):setText('')
    panel:getChildById('sellList'):destroyChildren()
    panel:getChildById('buyList'):destroyChildren()
    send({a = 'offers', s = serverId})
end

local function drawItemList()
    if not catalog then
        return
    end

    local list = window:getChildById('browsePanel'):getChildById('itemList')
    list:destroyChildren()
    for _, entry in ipairs(catalog) do
        if passes(entry) then
            local row = g_ui.createWidget('MarketItemRow', list)
            row:getChildById('sprite'):setItemId(entry.i)
            row:getChildById('name'):setText(entry.n)
            local counts = active[entry.s]
            row:getChildById('counts'):setText(counts
                and (counts.so .. ' selling, ' .. counts.bo .. ' buying') or 'no offers')
            row.onClick = function()
                selectItem(entry.s)
            end
            if entry.s == selectedItem then
                row:focus()
            end
        end
    end
end

local function buildCategoryBox()
    local box = window:getChildById('browsePanel'):getChildById('categoryBox')
    box.onOptionChange = nil
    box:clearOptions()
    box:addOption('All categories', nil)
    for _, category in ipairs(categories) do
        if type(category) == 'table' and category.key ~= nil then
            box:addOption(category.label or tostring(category.key), category.key)
        end
    end
    box.onOptionChange = function(self, text, data)
        categoryFilter = data
        drawItemList()
    end
end

-- -------------------------------------------------------------------- Offers

local function openAcceptWindow(offer)
    closeAcceptWindow()
    local buying = offer.k == 1
    local maximum = offer.a
    if buying then
        local funds = offer.c == COINS and balance.coins or balance.gold
        maximum = math.min(maximum, math.floor(funds / math.max(1, offer.p)))
    else
        maximum = math.min(maximum, have)
    end
    if maximum < 1 then
        setStatus(buying and 'You cannot afford any of these.' or 'You have none of these in your stackable stash.', false)
        return
    end

    acceptWindow = g_ui.createWidget('MarketAcceptWindow', rootWidget)
    acceptWindow:setText(buying and tr('Buy') or tr('Sell'))
    acceptWindow:getChildById('item'):setItemId(offer.i)
    acceptWindow:getChildById('summary'):setText((buying and 'From ' or 'To ') .. offer.o .. '\n'
        .. formatPrice(offer.p, offer.c) .. ' each, up to ' .. formatNumber(maximum))

    local edit = acceptWindow:getChildById('amountEdit')
    local total = acceptWindow:getChildById('totalLabel')
    local function amount()
        return math.floor(tonumber(edit:getText()) or 0)
    end
    local function update()
        local n = amount()
        if n < 1 or n > maximum then
            total:setText('Enter 1 to ' .. formatNumber(maximum) .. '.')
        else
            total:setText('Total: ' .. formatPrice(n * offer.p, offer.c))
        end
    end
    edit.onTextChange = update
    edit:setText(tostring(maximum))
    acceptWindow:getChildById('maxButton').onClick = function()
        edit:setText(tostring(maximum))
    end

    acceptWindow:getChildById('buttonOk').onClick = function()
        local n = amount()
        if n >= 1 and n <= maximum then
            send({a = 'accept', id = offer.id, n = n, s = offer.s})
            closeAcceptWindow()
        end
    end
    acceptWindow:getChildById('buttonCancel').onClick = closeAcceptWindow
    acceptWindow.onEscape = closeAcceptWindow
    acceptWindow.onEnter = acceptWindow:getChildById('buttonOk').onClick
    edit:focus()
end

local function drawOfferTable(list, side)
    list:destroyChildren()
    for _, offer in ipairs(offers) do
        if offer.k == side then
            local row = g_ui.createWidget('MarketOfferRow', list)
            fillRow(row, OFFER_COLUMNS, {
                offer.o,
                formatNumber(offer.a),
                formatPrice(offer.p, offer.c),
                formatPrice(offer.a * offer.p, offer.c),
                formatExpiry(offer.e),
            })
            row.onClick = function()
                selectedOffer = offer
            end
            row.onDoubleClick = function()
                selectedOffer = offer
                openAcceptWindow(offer)
            end
        end
    end
end

local function drawOffers()
    local panel = window:getChildById('browsePanel')
    selectedOffer = nil
    drawOfferTable(panel:getChildById('sellList'), 1)
    drawOfferTable(panel:getChildById('buyList'), 0)
    panel:getChildById('selectedHave'):setText('In your stackable stash: ' .. formatNumber(have))
end

local function acceptSelected(side)
    if not selectedOffer or selectedOffer.k ~= side then
        setStatus(side == 1 and 'Pick a sell offer to buy from.' or 'Pick a buy order to sell into.', false)
        return
    end
    if selectedOffer.o == g_game.getCharacterName() then
        setStatus('That is your own offer.', false)
        return
    end
    openAcceptWindow(selectedOffer)
end

-- -------------------------------------------------------------- Create offer

local function fee(total)
    if createCurrency == COINS then
        return fees.coinFee
    end
    return math.max(fees.feeMin, math.min(fees.feeMax, math.floor(total * fees.feePercent / 100)))
end

local function createValues()
    local panel = window:getChildById('browsePanel'):getChildById('createPanel')
    local amount = math.floor(tonumber(panel:getChildById('amountEdit'):getText()) or 0)
    local price = math.floor(tonumber(panel:getChildById('priceEdit'):getText()) or 0)
    return amount, price
end

local function drawCreate()
    local panel = window:getChildById('browsePanel'):getChildById('createPanel')
    panel:getChildById('kindSell'):setOn(createKind == 'sell')
    panel:getChildById('kindBuy'):setOn(createKind == 'buy')
    panel:getChildById('currencyGold'):setOn(createCurrency == GOLD)
    panel:getChildById('currencyCoins'):setOn(createCurrency == COINS)

    local summary = panel:getChildById('createSummary')
    if not selectedItem then
        summary:setText('Pick an item to list.')
        return
    end

    local amount, price = createValues()
    if amount < 1 or price < 1 then
        summary:setText(createKind == 'sell'
            and 'Sells from your stackable stash. The fee is paid from your bank and not refunded.'
            or 'The whole price is held from your balance until the order fills. The fee is paid from your bank.')
        return
    end

    local total = amount * price
    summary:setText('Total: ' .. formatPrice(total, createCurrency) .. '.  Fee: ' .. formatPrice(fee(total), GOLD)
        .. (createKind == 'buy' and '  (the total is held now)' or ''))
end

local function createOffer()
    if not selectedItem then
        setStatus('Pick an item first.', false)
        return
    end
    local amount, price = createValues()
    if amount < 1 or price < 1 then
        setStatus('Enter an amount and a price.', false)
        return
    end
    send({a = 'create', k = createKind == 'sell' and 1 or 0, s = selectedItem, n = amount, p = price,
        c = createCurrency})
end

-- ------------------------------------------------------ My offers / history

local mineOffers = {}

local function drawMine()
    local panel = window:getChildById('minePanel')
    local list = panel:getChildById('mineList')
    list:destroyChildren()
    selectedOwnOffer = nil
    for _, offer in ipairs(mineOffers) do
        local row = g_ui.createWidget('MarketOfferRow', list)
        fillRow(row, MINE_COLUMNS, {
            offer.n,
            offer.k == 1 and 'Selling' or 'Buying',
            formatNumber(offer.a),
            formatPrice(offer.p, offer.c),
            formatPrice(offer.a * offer.p, offer.c),
            formatExpiry(offer.e),
        })
        row.onClick = function()
            selectedOwnOffer = offer
        end
    end
end

local HISTORY_TEXT = {
    sold = 'Sold %s %s to %s for %s',
    bought = 'Bought %s %s from %s for %s',
    expired = 'Offer for %s %s expired and was returned',
}

local function drawHistory(rows)
    local list = window:getChildById('historyPanel'):getChildById('historyList')
    list:destroyChildren()
    for _, entry in ipairs(rows) do
        local row = g_ui.createWidget('MarketOfferRow', list)
        local text = string.format(HISTORY_TEXT[entry.k] or '%s %s', formatNumber(entry.a), entry.n, entry.o,
            formatPrice(entry.a * entry.p, entry.c))
        fillRow(row, HISTORY_COLUMNS, {os.date('%Y-%m-%d %H:%M', entry.t), text})
    end
end

-- ---------------------------------------------------------------------- Tabs

local currentTab = 'browse'

local function showTab(tab)
    currentTab = tab
    window:getChildById('browsePanel'):setVisible(tab == 'browse')
    window:getChildById('minePanel'):setVisible(tab == 'mine')
    window:getChildById('historyPanel'):setVisible(tab == 'history')
    window:getChildById('tabBrowse'):setOn(tab == 'browse')
    window:getChildById('tabMine'):setOn(tab == 'mine')
    window:getChildById('tabHistory'):setOn(tab == 'history')

    if tab == 'mine' then
        send({a = 'mine'})
    elseif tab == 'history' then
        send({a = 'history'})
    end
end

-- ------------------------------------------------------------------ Protocol

local LIST_ACTIONS = {catalog = true, active = true, offers = true, mine = true, history = true}

function onExtendedOpcode(protocol, code, buffer)
    if code ~= MARKET_OPCODE or not window then
        return
    end

    local ok, data = pcall(json.decode, buffer)
    if not ok or type(data) ~= 'table' then
        return
    end

    if LIST_ACTIONS[data.action] then
        -- One reassembly channel per list kind, so an item's offers arriving
        -- in the middle of the catalog cannot splice into it.
        data = JsonChunks.receive(MARKET_OPCODE .. ':' .. data.action, data, 'items')
        if not data then
            return
        end
    end

    local items = type(data.items) == 'table' and data.items or {}

    if data.action == 'close' then
        close()
    elseif data.action == 'open' then
        balance.gold, balance.coins = tonumber(data.gold) or 0, tonumber(data.coins) or 0
        for key in pairs(fees) do
            fees[key] = tonumber(data[key]) or fees[key]
        end
        drawBalance()
        setStatus('')
        window:show()
        window:raise()
        window:focus()
        showTab(currentTab)
        drawCreate()
        if not catalog then
            send({a = 'catalog'})
        end
        send({a = 'active'})
        if selectedItem then
            send({a = 'offers', s = selectedItem})
        end
    elseif data.action == 'balance' then
        balance.gold, balance.coins = tonumber(data.gold) or 0, tonumber(data.coins) or 0
        drawBalance()
    elseif data.action == 'catalog' then
        catalog = items
        categories = type(data.categories) == 'table' and data.categories or {}
        buildCategoryBox()
        drawItemList()
    elseif data.action == 'active' then
        active = {}
        for _, entry in ipairs(items) do
            active[entry.s] = {so = tonumber(entry.so) or 0, bo = tonumber(entry.bo) or 0}
        end
        drawItemList()
    elseif data.action == 'offers' then
        if data.s == selectedItem then
            offers = items
            have = tonumber(data.have) or 0
            drawOffers()
        end
    elseif data.action == 'mine' then
        mineOffers = items
        drawMine()
    elseif data.action == 'history' then
        drawHistory(items)
    elseif data.action == 'msg' then
        setStatus(data.text, data.ok)
        if data.ok then
            send({a = 'active'})
            if currentTab == 'mine' then
                send({a = 'mine'})
            end
        end
    end
end

function init()
    window = g_ui.displayUI('stackmarket')
    window:hide()

    local browse = window:getChildById('browsePanel')
    local create = browse:getChildById('createPanel')

    browse:getChildById('searchEdit').onTextChange = function(self, text)
        searchText = text:lower()
        drawItemList()
    end
    browse:getChildById('onlyOffers').onCheckChange = function(self, checked)
        onlyWithOffers = checked
        drawItemList()
    end

    buildHeader(browse:getChildById('sellHeader'), OFFER_COLUMNS)
    buildHeader(browse:getChildById('buyHeader'), OFFER_COLUMNS)
    buildHeader(window:getChildById('minePanel'):getChildById('mineHeader'), MINE_COLUMNS)
    buildHeader(window:getChildById('historyPanel'):getChildById('historyHeader'), HISTORY_COLUMNS)

    browse:getChildById('buyButton').onClick = function() acceptSelected(1) end
    browse:getChildById('sellButton').onClick = function() acceptSelected(0) end

    create:getChildById('kindSell').onClick = function() createKind = 'sell'; drawCreate() end
    create:getChildById('kindBuy').onClick = function() createKind = 'buy'; drawCreate() end
    create:getChildById('currencyGold').onClick = function() createCurrency = GOLD; drawCreate() end
    create:getChildById('currencyCoins').onClick = function() createCurrency = COINS; drawCreate() end
    create:getChildById('amountEdit').onTextChange = drawCreate
    create:getChildById('priceEdit').onTextChange = drawCreate
    create:getChildById('createButton').onClick = createOffer

    window:getChildById('minePanel'):getChildById('cancelButton').onClick = function()
        if not selectedOwnOffer then
            setStatus('Pick one of your offers to cancel.', false)
            return
        end
        send({a = 'cancel', id = selectedOwnOffer.id, s = selectedOwnOffer.s})
    end

    window:getChildById('tabBrowse').onClick = function() showTab('browse') end
    window:getChildById('tabMine').onClick = function() showTab('mine') end
    window:getChildById('tabHistory').onClick = function() showTab('history') end

    window:getChildById('closeButton').onClick = function()
        close()
        send({a = 'close'})
    end

    connect(LocalPlayer, {onPositionChange = onPositionChange})
    connect(g_game, {onGameEnd = onGameEnd})
    ProtocolGame.registerExtendedOpcode(MARKET_OPCODE, onExtendedOpcode)
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(MARKET_OPCODE, onExtendedOpcode)
    disconnect(g_game, {onGameEnd = onGameEnd})
    disconnect(LocalPlayer, {onPositionChange = onPositionChange})

    closeAcceptWindow()
    if window then
        window:destroy()
        window = nil
    end
end
