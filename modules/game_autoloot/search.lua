AutoLoot.searchWindow = nil
AutoLoot.MAX_SEARCH_RESULTS = 100

function openSearchWindow()
    AutoLoot.openSearchWindow()
end

function closeSearchWindow()
    AutoLoot.closeSearchWindow()
end

function AutoLoot.openSearchWindow()
    if AutoLoot.searchWindow then
        AutoLoot.searchWindow:show()
        AutoLoot.searchWindow:raise()
        AutoLoot.searchWindow:focus()

        local searchEdit = AutoLoot.searchWindow:recursiveGetChildById(
            'searchEdit'
        )

        if searchEdit then
            searchEdit:focus()
        end

        return
    end

    AutoLoot.searchWindow = g_ui.loadUI(
        'search',
        modules.game_interface.getRootPanel()
    )

    if not AutoLoot.searchWindow then
        print('[AUTOLOOT] Failed to load search window')
        return
    end

    local searchEdit = AutoLoot.searchWindow:recursiveGetChildById(
        'searchEdit'
    )

    if searchEdit then
        searchEdit.onTextChange = function(widget, text)
            AutoLoot.refreshSearchResults(text)
        end

        searchEdit:focus()
    end
end

function AutoLoot.closeSearchWindow()
    if not AutoLoot.searchWindow then
        return
    end

    AutoLoot.searchWindow:destroy()
    AutoLoot.searchWindow = nil
    
    if modules.game_hotkeys
    and modules.game_hotkeys.setUiHotkeyFocusBlocked then

    modules.game_hotkeys.setUiHotkeyFocusBlocked(false)
end
end

function AutoLoot.closeSearchWindow()
    if not AutoLoot.searchWindow then
        return
    end

    AutoLoot.searchWindow:destroy()
    AutoLoot.searchWindow = nil
end

function AutoLoot.clearSearchResults()
    if not AutoLoot.searchWindow then
        return
    end

    local resultsPanel = AutoLoot.searchWindow:recursiveGetChildById(
        'resultsPanel'
    )

    if resultsPanel then
        resultsPanel:destroyChildren()
    end
end

function AutoLoot.refreshSearchResults(searchText)
    AutoLoot.clearSearchResults()

    if not AutoLoot.searchWindow then
        return
    end

    if not AutoLoot.itemCatalog then
        print('[AUTOLOOT] Item catalog is not loaded')
        return
    end

    searchText = (searchText or ''):trim():lower()

    if searchText:len() < 2 then
        return
    end

    local resultsPanel = AutoLoot.searchWindow:recursiveGetChildById(
        'resultsPanel'
    )

    if not resultsPanel then
        return
    end

    local resultCount = 0

    for _, itemData in ipairs(AutoLoot.itemCatalog) do
        if resultCount >= AutoLoot.MAX_SEARCH_RESULTS then
            break
        end

        if itemData.name:lower():find(searchText, 1, true) then
            AutoLoot.createSearchResult(
                resultsPanel,
                itemData.serverId,
                itemData.clientId,
                itemData.name
            )

            resultCount = resultCount + 1
        end
    end
end
function AutoLoot.createSearchResult(
    parent,
    serverId,
    clientId,
    itemName
)
    local result = g_ui.createWidget(
        'Item',
        parent
    )

    if not result then
        return
    end

    result:setSize({
        width = 32,
        height = 32
    })

    result:setItem(
        Item.create(clientId, 1)
    )
    
    result:setTooltip(itemName)

    result.onMouseRelease = function(
        widget,
        mousePos,
        mouseButton
    )
        if mouseButton ~= MouseLeftButton then
            return false
        end

        AutoLoot.addSearchResult(
            serverId,
            clientId
        )

        return true
    end
end
function AutoLoot.getFirstFreeUnlockedSlot()
    for slotIndex = 1, AutoLoot.unlockedSlots do
        if not AutoLoot.items[slotIndex] then
            return slotIndex
        end
    end

    return nil
end

function AutoLoot.addSearchResult(serverId, clientId)
    local slotIndex = AutoLoot.getFirstFreeUnlockedSlot()

    if not slotIndex then
        print('[AUTOLOOT] No free unlocked slots available')
        return false
    end

    return AutoLoot.addCatalogItemToSlot(
        slotIndex,
        serverId,
        clientId,
        1
    )
end