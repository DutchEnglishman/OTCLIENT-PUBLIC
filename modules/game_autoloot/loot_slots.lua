function AutoLoot.isItemAlreadyAdded(serverId)
    for slotIndex, storedItem in pairs(AutoLoot.items) do
        if storedItem and storedItem.serverId == serverId then
            return true, slotIndex
        end
    end

    return false, nil
end

function AutoLoot.getItemDataByClientId(clientId)
    if not AutoLoot.itemByClientId then
        return nil
    end

    return AutoLoot.itemByClientId[clientId]
end

function AutoLoot.getItemDataByServerId(serverId)
    if not AutoLoot.itemByServerId then
        return nil
    end

    return AutoLoot.itemByServerId[serverId]
end

function AutoLoot.addCatalogItemToSlot(slotIndex, serverId, clientId, count)
    if not AutoLoot.isSlotUnlocked(slotIndex) then
        print(string.format(
            '[AUTOLOOT] Slot %d is locked',
            slotIndex
        ))

        return false
    end

    if not serverId or serverId <= 0 then
        return false
    end

    if not clientId or clientId <= 0 then
        return false
    end

    local alreadyAdded, existingSlot =
        AutoLoot.isItemAlreadyAdded(serverId)

    if alreadyAdded then
        print(string.format(
            '[AUTOLOOT] Server item %d is already assigned to slot %d',
            serverId,
            existingSlot
        ))

        return false
    end

    local slot = AutoLoot.window:recursiveGetChildById(
        'autoLootSlot' .. slotIndex
    )

    if not slot then
        return false
    end

    AutoLoot.items[slotIndex] = {
        serverId = serverId,
        clientId = clientId
    }

    slot:setItem(
        Item.create(
            clientId,
            count or 1
        )
    )

    if AutoLoot.syncItemsToServer then
        AutoLoot.syncItemsToServer()
    end

    print(string.format(
        '[AUTOLOOT] Added server item %d (client item %d) to slot %d',
        serverId,
        clientId,
        slotIndex
    ))

    return true
end

function AutoLoot.addItemToSlot(slotIndex, item)
    if not AutoLoot.isSlotUnlocked(slotIndex) then
        print(string.format(
            '[AUTOLOOT] Slot %d is locked',
            slotIndex
        ))

        return false
    end

    if not item or not item:isItem() then
        return false
    end

    local clientId = item:getId()

    if not clientId or clientId <= 0 then
        return false
    end

    local itemData = AutoLoot.getItemDataByClientId(clientId)

    if not itemData then
        print(string.format(
            '[AUTOLOOT] Client item %d was not found in the item catalog',
            clientId
        ))

        return false
    end

    local added = AutoLoot.addCatalogItemToSlot(
        slotIndex,
        itemData.serverId,
        itemData.clientId,
        item:getCountOrSubType()
    )

    if not added then
        return false
    end

    if AutoLoot.syncItemsToServer then
        AutoLoot.syncItemsToServer()
    end

    if AutoLoot.saveCurrentPreset then
        AutoLoot.saveCurrentPreset()
    end

    if AutoLoot.saveCharacterSettings then
        AutoLoot.saveCharacterSettings()
    end

    return true
end

function AutoLoot.removeItemFromSlot(slotIndex)
    if not AutoLoot.isSlotUnlocked(slotIndex) then
        return false
    end

    local slot = AutoLoot.window:recursiveGetChildById(
        'autoLootSlot' .. slotIndex
    )

    if not slot then
        return false
    end

    if not AutoLoot.items[slotIndex] then
        return false
    end

    AutoLoot.items[slotIndex] = nil
    slot:setItem(nil)

    if AutoLoot.syncItemsToServer then
        AutoLoot.syncItemsToServer()
    end

    if AutoLoot.saveCurrentPreset then
        AutoLoot.saveCurrentPreset()
    end

    if AutoLoot.saveCharacterSettings then
        AutoLoot.saveCharacterSettings()
    end

    print(string.format(
        '[AUTOLOOT] Removed item from slot %d',
        slotIndex
    ))

    return true
end

function AutoLoot.setupItemSlots()
    for index = 1, AutoLoot.MAX_SLOTS do
        local slot = AutoLoot.window:recursiveGetChildById(
            'autoLootSlot' .. index
        )

        if not slot then
            print(string.format(
                '[AUTOLOOT] Slot %d not found',
                index
            ))
        else
            AutoLoot.updateSlotLockVisual(slot, index)

            slot.onDrop = function(widget, draggedWidget, mousePos)
                if not AutoLoot.isSlotUnlocked(index) then
                    print(string.format(
                        '[AUTOLOOT] Slot %d is locked',
                        index
                    ))

                    return false
                end

                if not draggedWidget then
                    return false
                end

                local item = draggedWidget.currentDragThing

                if not item or not item:isItem() then
                    return false
                end

                return AutoLoot.addItemToSlot(
                    index,
                    item
                )
            end

            slot.onMouseRelease = function(widget, mousePos, mouseButton)
                if not AutoLoot.isSlotUnlocked(index) then
                    return false
                end

                if mouseButton ~= MouseRightButton then
                    return false
                end

                return AutoLoot.removeItemFromSlot(index)
            end
        end
    end
end

function AutoLoot.clearItemSlots()
    AutoLoot.items = {}

    if not AutoLoot.window then
        return
    end

    for index = 1, AutoLoot.MAX_SLOTS do
        local slot = AutoLoot.window:recursiveGetChildById(
            'autoLootSlot' .. index
        )

        if slot then
            slot:setItem(nil)
        end
    end
    if AutoLoot.syncItemsToServer then
        AutoLoot.syncItemsToServer()
    end
end