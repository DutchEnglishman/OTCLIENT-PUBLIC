local BUY = 1
local SELL = 2
local DEFAULT_CURRENCY = 'gold'
local DEFAULT_CURRENCY_DECIMAL = false
local CURRENCY = DEFAULT_CURRENCY
local CURRENCY_DECIMAL = DEFAULT_CURRENCY_DECIMAL

-- Set by a shop that trades in something other than gold (see
-- setShopCurrency). The goods packet only ever carries the player's gold
-- (protocolgame.cpp, sendSaleItemList), so a shop charging task points or
-- hourly tokens has to send its own balance or the window would show a
-- number that has nothing to do with what it is about to spend.
local shopBalance = nil

-- What the player holds in the bank, sent beside the goods packet
-- (SHOP_BANK_BALANCE_OPCODE). Shown as its own row, and only on a shop trading
-- in gold: a shop charging task points or hourly tokens sets shopBalance, and
-- the bank has nothing to do with what it spends.
local bankBalance = 0
local WEIGHT_UNIT = 'oz'
local LAST_INVENTORY = 10

local npcWindow = nil
local itemsPanel = nil
local radioTabs = nil
local radioItems = nil
local searchText = nil
local setupPanel = nil
local quantity = nil
local quantityScroll = nil
local nameLabel = nil
local priceLabel = nil
local moneyLabel = nil
local bankDesc = nil
local bankLabel = nil
local bankRowHeight = nil
local weightDesc = nil
local weightLabel = nil
local capacityDesc = nil
local capacityLabel = nil
local tradeButton = nil
local buyTab = nil
local sellTab = nil
local initialized = false

local showWeight = true
local buyWithBackpack = nil
local ignoreCapacity = nil
local ignoreEquipped = nil
local showAllItems = nil
local sellAllButton = nil

local playerFreeCapacity = 0
local playerMoney = 0
local tradeItems = {[BUY] = {}, [SELL] = {}}
local playerItems = {}
local selectedItem = nil

local cancelNextRelease = nil

function controllerNpcTrader:legacy_init()
    npcWindow = g_ui.displayUI('/game_npctrade/templates/npctrade_legacy')
    npcWindow:setVisible(false)

    itemsPanel = npcWindow:recursiveGetChildById('itemsPanel')
    searchText = npcWindow:recursiveGetChildById('searchText')

    setupPanel = npcWindow:recursiveGetChildById('setupPanel')
    quantityScroll = setupPanel:getChildById('quantityScroll')
    nameLabel = setupPanel:getChildById('name')
    priceLabel = setupPanel:getChildById('price')
    moneyLabel = setupPanel:getChildById('money')
    bankDesc = setupPanel:getChildById('bankDesc')
    bankLabel = setupPanel:getChildById('bank')
    -- Captured before the row is ever collapsed, so restoring it needs no
    -- hardcoded figure. The fallback is the height of verdana-11px-antialised,
    -- which is what a Label with no explicit size comes out as.
    bankRowHeight = bankDesc:getHeight()
    if bankRowHeight <= 0 then
        bankRowHeight = 14
    end
    -- Both halves of the row own their height from here on. UIWidget::updateText
    -- (src/framework/ui/uiwidgettext.cpp) re-sizes a label to its text whenever
    -- text-auto-resize is on -- which it is on the value label -- and for ANY
    -- label whose height is not positive, so a collapsed row would grow itself
    -- back on the next setText. Width still follows the number.
    bankDesc:setTextVerticalAutoResize(false)
    bankLabel:setTextVerticalAutoResize(false)
    weightDesc = setupPanel:getChildById('weightDesc')
    weightLabel = setupPanel:getChildById('weight')
    capacityDesc = setupPanel:getChildById('capacityDesc')
    capacityLabel = setupPanel:getChildById('capacity')
    tradeButton = npcWindow:recursiveGetChildById('tradeButton')

    buyWithBackpack = npcWindow:recursiveGetChildById('buyWithBackpack')
    ignoreCapacity = npcWindow:recursiveGetChildById('ignoreCapacity')
    ignoreEquipped = npcWindow:recursiveGetChildById('ignoreEquipped')
    showAllItems = npcWindow:recursiveGetChildById('showAllItems')
    sellAllButton = npcWindow:recursiveGetChildById('sellAllButton')

    buyTab = npcWindow:getChildById('buyTab')
    sellTab = npcWindow:getChildById('sellTab')

    radioTabs = UIRadioGroup.create()
    radioTabs:addWidget(buyTab)
    radioTabs:addWidget(sellTab)
    radioTabs:selectWidget(buyTab)
    radioTabs.onSelectionChange = onTradeTypeChange

    cancelNextRelease = false

    if g_game.isOnline() then
        playerFreeCapacity = g_game.getLocalPlayer():getFreeCapacity()
    end

    connect(LocalPlayer, {
        onFreeCapacityChange = onFreeCapacityChange,
        onInventoryChange = onInventoryChange
    })

    initialized = true
end

function controllerNpcTrader:legacy_terminate()
    initialized = false
    if npcWindow then
        npcWindow:destroy()
    end
    npcWindow = nil
    disconnect(LocalPlayer, {
        onFreeCapacityChange = onFreeCapacityChange,
        onInventoryChange = onInventoryChange
    })
end

function controllerNpcTrader:legacy_show()
    if g_game.isOnline() and npcWindow then
        if tradeItems[BUY] and #tradeItems[BUY] > 0 then
            radioTabs:selectWidget(buyTab)
        else
            radioTabs:selectWidget(sellTab)
        end

        npcWindow:show()
        npcWindow:raise()
        npcWindow:focus()
    end
end

function controllerNpcTrader:legacy_hide()
    if npcWindow then
        npcWindow:hide()
    end
end

function onItemBoxChecked(widget)
    if widget:isChecked() then
        local item = widget.item
        selectedItem = item
        refreshItem(item)
        tradeButton:enable()

        if getCurrentTradeType() == SELL then
            quantityScroll:setValue(quantityScroll:getMaximum())
        end
    end
end

function onQuantityValueChange(quantity)
    if selectedItem then
        weightLabel:setText(string.format('%.2f', selectedItem.weight * quantity) .. ' ' .. WEIGHT_UNIT)
        priceLabel:setText(formatCurrency(getItemPrice(selectedItem)))
    end
end

function onTradeTypeChange(radioTabs, selected, deselected)
    tradeButton:setText(selected:getText())
    selected:setOn(true)
    deselected:setOn(false)

    local currentTradeType = getCurrentTradeType()
    buyWithBackpack:setVisible(currentTradeType == BUY)
    ignoreCapacity:setVisible(currentTradeType == BUY)
    ignoreEquipped:setVisible(currentTradeType == SELL)
    showAllItems:setVisible(currentTradeType == SELL)
    sellAllButton:setVisible(currentTradeType == SELL)

    refreshTradeItems()
    refreshPlayerGoods()
end

function onTradeClick()
    if getCurrentTradeType() == BUY then
        g_game.buyItem(selectedItem.ptr, quantityScroll:getValue(), ignoreCapacity:isChecked(),
                       buyWithBackpack:isChecked())
    else
        g_game.sellItem(selectedItem.ptr, quantityScroll:getValue(), ignoreEquipped:isChecked())
    end
end

function onSearchTextChange()
    refreshPlayerGoods()
end

function itemPopup(self, mousePosition, mouseButton)
    if cancelNextRelease then
        cancelNextRelease = false
        return false
    end

    if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption(tr('Look'), function()
            return g_game.inspectNpcTrade(self:getItem())
        end)
        menu:display(mousePosition)
        return true
    elseif ((g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton) or
        (g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton)) then
        cancelNextRelease = true
        g_game.inspectNpcTrade(self:getItem())
        return true
    end
    return false
end

function onBuyWithBackpackChange()
    if selectedItem then
        refreshItem(selectedItem)
    end
end

function onIgnoreCapacityChange()
    refreshPlayerGoods()
end

function onIgnoreEquippedChange()
    refreshPlayerGoods()
end

function onShowAllItemsChange()
    refreshPlayerGoods()
end

function setCurrency(currency, decimal)
    CURRENCY = currency
    CURRENCY_DECIMAL = decimal
end

-- Called from the shop-currency extended opcode. `label` is what every price
-- and the balance are denominated in; `balance` is how much of it the player
-- holds, which the server has to tell us because the goods packet cannot.
-- Passing no label puts the window back on gold.
function setShopCurrency(label, balance)
    if label and label ~= '' then
        CURRENCY = label
        CURRENCY_DECIMAL = false
        shopBalance = tonumber(balance) or 0
    else
        CURRENCY = DEFAULT_CURRENCY
        CURRENCY_DECIMAL = DEFAULT_CURRENCY_DECIMAL
        shopBalance = nil
    end

    if not initialized then
        return
    end

    -- Both, in this order, the same way onTradeTypeChange does it. The price
    -- written into each tile is baked in by refreshTradeItems; refreshPlayerGoods
    -- only re-evaluates what is enabled and redraws the balance, so on its own
    -- the tiles would keep whatever currency they were built with.
    refreshTradeItems()
    refreshPlayerGoods()
end

-- Called from the bank-balance extended opcode, which arrives right behind the
-- goods packet on every refresh -- so this is current after a purchase that was
-- paid out of the bank, without the window asking for anything.
function setShopBankBalance(balance)
    bankBalance = tonumber(balance) or 0

    if initialized then
        refreshPlayerGoods()
    end
end

-- The setup panel is one anchor chain, each row's top being the bottom of the
-- row above it, so a row that is merely invisible still holds its place and
-- leaves a gap above Weight. Collapsing its height and its top margin as well
-- puts everything below back within a pixel of where it sits with no bank row.
local function setBankRowVisible(state)
    bankDesc:setVisible(state)
    bankLabel:setVisible(state)
    -- 1 rather than 0: a zero height leaves an invalid rect, which is the other
    -- condition that puts updateText back in charge of the height.
    bankDesc:setHeight(state and bankRowHeight or 1)
    bankLabel:setHeight(state and bankRowHeight or 1)
    bankDesc:setMarginTop(state and 5 or 0)
end

function setShowWeight(state)
    showWeight = state
    weightDesc:setVisible(state)
    weightLabel:setVisible(state)
end

function setShowYourCapacity(state)
    capacityDesc:setVisible(state)
    capacityLabel:setVisible(state)
    ignoreCapacity:setVisible(state)
end

function clearSelectedItem()
    nameLabel:clearText()
    weightLabel:clearText()
    priceLabel:clearText()
    tradeButton:disable()
    quantityScroll:setMinimum(0)
    quantityScroll:setMaximum(0)
    if selectedItem then
        radioItems:selectWidget(nil)
        selectedItem = nil
    end
end

function getCurrentTradeType()
    if tradeButton:getText() == tr('Buy') then
        return BUY
    else
        return SELL
    end
end

function getItemPrice(item, single)
    local amount = 1
    local single = single or false
    if not single then
        amount = quantityScroll:getValue()
    end
    if getCurrentTradeType() == BUY then
        if buyWithBackpack:isChecked() then
            if item.ptr:isStackable() then
                return item.price * amount + 20
            else
                return item.price * amount + math.ceil(amount / 20) * 20
            end
        end
    end
    return item.price * amount
end

function getSellQuantityLegacy(item)
    if not item or not playerItems[item:getId()] then
        return 0
    end
    local removeAmount = 0
    if ignoreEquipped:isChecked() then
        local localPlayer = g_game.getLocalPlayer()
        for i = 1, LAST_INVENTORY do
            local inventoryItem = localPlayer:getInventoryItem(i)
            if inventoryItem and inventoryItem:getId() == item:getId() then
                removeAmount = removeAmount + inventoryItem:getCount()
            end
        end
        -- equipped items with an active imbuement are not part of the server goods count
        removeAmount = math.max(0, removeAmount - controllerNpcTrader:getEquippedImbuedCount(item:getId()))
    end
    return math.max(0, playerItems[item:getId()] - removeAmount)
end

-- No money check here on purpose. The goods packet only ever carries the
-- player's GOLD (protocolgame.cpp, sendSaleItemList), but an NPC's onBuy
-- callback is free to charge something else entirely -- the Task Trader
-- spends task points and the Hourly Trader spends hourly tokens. Gating on
-- gold made those shops unusable: the button stayed dead and the quantity
-- slider clamped to zero before the server was ever asked.
--
-- Affordability is settled by the NPC, which refuses and says why. Capacity
-- is still checked here because that one the client does know.
function canTradeItemLegacy(item)
    if getCurrentTradeType() == BUY then
        return ignoreCapacity:isChecked() or playerFreeCapacity >= item.weight
    else
        return getSellQuantityLegacy(item.ptr) > 0
    end
end

-- What the player can spend at this shop. A shop charging task points or
-- hourly tokens sends its own balance (shopBalance); a gold shop pays from
-- carried gold first and the bank after, so both count.
function getSpendableBalance()
    if shopBalance ~= nil then
        return shopBalance
    end
    return playerMoney + bankBalance
end

-- Largest quantity whose total cost (backpacks included) fits the balance.
function getAffordableCount(item)
    local balance = getSpendableBalance()
    local price = tonumber(item.price) or 0
    if price <= 0 then
        return getMaxAmount()
    end

    local count = math.min(getMaxAmount(), math.floor(balance / price))
    if buyWithBackpack:isChecked() then
        local stackable = item.ptr:isStackable()
        while count > 0 do
            local backpacks = stackable and 20 or math.ceil(count / 20) * 20
            if price * count + backpacks <= balance then
                break
            end
            count = count - 1
        end
    end
    return math.max(0, count)
end

function refreshItem(item)
    nameLabel:setText(item.name)

    if getCurrentTradeType() == BUY then
        local capacityMaxCount = math.floor(playerFreeCapacity / item.weight)
        if ignoreCapacity:isChecked() then
            capacityMaxCount = 65535
        end
        -- getMaxAmount() is the engine's own per-purchase ceiling (100,
        -- matching the amount > 100 guard in Game::playerPurchaseItem). The
        -- slider is further capped by what the player can afford, measured in
        -- the shop's own currency (see getSpendableBalance).
        local finalCount = math.max(0, math.min(getMaxAmount(), capacityMaxCount, getAffordableCount(item)))
        quantityScroll:setMinimum(1)
        quantityScroll:setMaximum(finalCount)
    else
        quantityScroll:setMinimum(1)
        quantityScroll:setMaximum(math.max(0, math.min(getMaxAmount(), getSellQuantityLegacy(item.ptr))))
    end

    onQuantityValueChange(quantityScroll:getValue())

    setupPanel:enable()
end

function refreshTradeItems()
    local layout = itemsPanel:getLayout()
    layout:disableUpdates()

    clearSelectedItem()

    searchText:clearText()
    setupPanel:disable()
    itemsPanel:destroyChildren()

    if radioItems then
        radioItems:destroy()
    end
    radioItems = UIRadioGroup.create()

    local currentTradeItems = tradeItems[getCurrentTradeType()]
    for key, item in pairs(currentTradeItems) do
        local itemBox = g_ui.createWidget('NPCItemBox', itemsPanel)
        itemBox.item = item

        local text = ''
        local name = item.name
        text = text .. name
        if showWeight then
            local weight = string.format('%.2f', item.weight) .. ' ' .. WEIGHT_UNIT
            text = text .. '\n' .. weight
        end
        local price = formatCurrency(item.price)
        text = text .. '\n' .. price
        itemBox:setText(text)

        local itemWidget = itemBox:getChildById('item')
        itemWidget:setItem(item.ptr)
        itemWidget.onMouseRelease = itemPopup

        radioItems:addWidget(itemBox)
    end

    layout:enableUpdates()
    layout:update()
end

function refreshPlayerGoods()
    if not initialized then
        return
    end

    checkSellAllTooltip()

    moneyLabel:setText(formatCurrency(shopBalance or playerMoney))

    -- Gold shops only. A shop trading in task points or hourly tokens has set
    -- shopBalance, and its prices have nothing to do with the bank.
    bankLabel:setText(formatCurrency(bankBalance))
    setBankRowVisible(shopBalance == nil)
    capacityLabel:setText(string.format('%.2f', playerFreeCapacity) .. ' ' .. WEIGHT_UNIT)

    local currentTradeType = getCurrentTradeType()
    local searchFilter = searchText:getText():lower()
    local foundSelectedItem = false

    local items = itemsPanel:getChildCount()
    for i = 1, items do
        local itemWidget = itemsPanel:getChildByIndex(i)
        local item = itemWidget.item

        local canTrade = canTradeItemLegacy(item)
        itemWidget:setOn(canTrade)
        itemWidget:setEnabled(canTrade)

        local searchCondition = (searchFilter == '') or
                                    (searchFilter ~= '' and string.find(item.name:lower(), searchFilter) ~= nil)
        local showAllItemsCondition = (currentTradeType == BUY) or (showAllItems:isChecked()) or
                                          (currentTradeType == SELL and not showAllItems:isChecked() and canTrade)
        itemWidget:setVisible(searchCondition and showAllItemsCondition)

        if selectedItem == item and itemWidget:isEnabled() and itemWidget:isVisible() then
            foundSelectedItem = true
        end
    end

    if not foundSelectedItem then
        clearSelectedItem()
    end

    if selectedItem then
        refreshItem(selectedItem)
    end
end

function onOpenNpcTrade(items)
    -- Back to gold before anything is drawn. A shop trading in something else
    -- announces it in the extended opcode it sends straight after this packet,
    -- so without the reset the previous shop's label and balance would leak
    -- into an ordinary gold merchant.
    CURRENCY = DEFAULT_CURRENCY
    CURRENCY_DECIMAL = DEFAULT_CURRENCY_DECIMAL
    shopBalance = nil

    tradeItems[BUY] = {}
    tradeItems[SELL] = {}

    for key, item in pairs(items) do
        if item[4] > 0 then
            local newItem = {}
            newItem.ptr = item[1]
            newItem.name = item[2]
            newItem.weight = item[3] / 100
            newItem.price = item[4]
            table.insert(tradeItems[BUY], newItem)
        end

        if item[5] > 0 then
            local newItem = {}
            newItem.ptr = item[1]
            newItem.name = item[2]
            newItem.weight = item[3] / 100
            newItem.price = item[5]
            table.insert(tradeItems[SELL], newItem)
        end
    end

    refreshTradeItems()
    addEvent(function()
        controllerNpcTrader:legacy_show()
    end) -- player goods has not been parsed yet
end

function closeNpcTradeLegacy()
    g_game.closeNpcTrade()
    controllerNpcTrader:legacy_hide()
end

function controllerNpcTrader:onCloseNpcTradeLegacy()
    controllerNpcTrader:legacy_hide()
end

function onPlayerGoods(money, items)
    playerMoney = money

    playerItems = {}
    for key, item in pairs(items) do
        local id = item[1]:getId()
        if not playerItems[id] then
            playerItems[id] = item[2]
        else
            playerItems[id] = playerItems[id] + item[2]
        end
    end

    refreshPlayerGoods()
end

function onFreeCapacityChange(localPlayer, freeCapacity, oldFreeCapacity)
    playerFreeCapacity = freeCapacity

    if npcWindow:isVisible() then
        refreshPlayerGoods()
    end
end

function onInventoryChange(inventory, item, oldItem)
    refreshPlayerGoods()
end

function getTradeItemData(id, type)
    if table.empty(tradeItems[type]) then
        return false
    end

    if type then
        for key, item in pairs(tradeItems[type]) do
            if item.ptr and item.ptr:getId() == id then
                return item
            end
        end
    else
        for _, items in pairs(tradeItems) do
            for key, item in pairs(items) do
                if item.ptr and item.ptr:getId() == id then
                    return item
                end
            end
        end
    end
    return false
end

function checkSellAllTooltip()
    sellAllButton:setEnabled(true)
    sellAllButton:removeTooltip()

    local total = 0
    local info = ''
    local first = true

    for key, amount in pairs(playerItems) do
        local data = getTradeItemData(key, SELL)
        if data then
            amount = getSellQuantityLegacy(data.ptr)
            if amount > 0 then
                if data and amount > 0 then
                    info = info .. (not first and '\n' or '') .. amount .. ' ' .. data.name .. ' (' .. data.price *
                               amount .. ' gold)'

                    total = total + (data.price * amount)
                    if first then
                        first = false
                    end
                end
            end
        end
    end
    if info ~= '' then
        info = info .. '\nTotal: ' .. total .. ' gold'
        sellAllButton:setTooltip(info)
    else
        sellAllButton:setEnabled(false)
    end
end

function formatCurrency(amount)
    if CURRENCY_DECIMAL then
        return string.format('%.02f', amount / 100.0) .. ' ' .. CURRENCY
    else
        return amount .. ' ' .. CURRENCY
    end
end

function getMaxAmount()
    if getCurrentTradeType() == SELL and g_game.getFeature(GameDoubleShopSellAmount) then
        return 10000
    end
    return 100
end

function isTradingLegacy()
    return npcWindow and npcWindow:isVisible() or false
end

function getSellItemsLegacy()
    return tradeItems[SELL] or {}
end

function getBuyItemsLegacy()
    return tradeItems[BUY] or {}
end

function sellAllLegacy()
    for itemid, item in pairs(playerItems) do
        local item = Item.create(itemid)
        local amount = getSellQuantityLegacy(item)
        if amount > 0 then
            g_game.sellItem(item, amount, ignoreEquipped:isChecked())
        end
    end
end
