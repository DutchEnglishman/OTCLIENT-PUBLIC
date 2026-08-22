AutoLoot = AutoLoot or {}
AutoLoot.EXTENDED_OPCODE = 52

local function sendMessage(message)
    if not g_game.isOnline() then
        return false
    end

    local protocolGame = g_game.getProtocolGame()
    if not protocolGame then
        return false
    end

    protocolGame:sendExtendedOpcode(AutoLoot.EXTENDED_OPCODE, message)
    return true
end

function AutoLoot.getServerIdFromClientId(clientId)
    if AutoLoot.itemByClientId then
        local itemData = AutoLoot.itemByClientId[clientId]
        if itemData then
            return itemData.serverId
        end
    end
    return nil
end

function AutoLoot.syncItemsToServer()
    local ids = {}

    for slotIndex = 1, AutoLoot.MAX_SLOTS or 20 do
        local itemData = AutoLoot.items and AutoLoot.items[slotIndex] or nil
        if itemData then
            local serverId = nil
            if type(itemData) == "table" then
                serverId = itemData.serverId
            elseif type(itemData) == "number" then
                serverId = AutoLoot.getServerIdFromClientId(itemData)
            end

            if serverId then
                ids[#ids + 1] = tostring(serverId)
            end
        end
    end

    sendMessage("ITEMS|" .. table.concat(ids, ","))
end

function AutoLoot.syncFilterToServer(mode)
    mode = mode or AutoLoot.filter or "accept"

    if mode ~= "ignore" then
        mode = "accept"
    end

    AutoLoot.filter = mode

    sendMessage("FILTER|" .. mode)
end

function AutoLoot.sendMainContainer(item)
    if not item then
        return false
    end

    local clientId = item:getId()
    local serverId = AutoLoot.getServerIdFromClientId(clientId)
    if not serverId then
        print(string.format("[AUTOLOOT] No server id mapping for container client id %d", clientId))
        return false
    end

    local position = item:getPosition()
    if not position then
        return false
    end

    return sendMessage(string.format(
        "CONTAINER|main|%d|%d|%d|%d",
        serverId,
        position.x,
        position.y,
        position.z
    ))
end

function AutoLoot.clearMainContainerOnServer()
    return sendMessage("CONTAINER_CLEAR|main")
end

function AutoLoot.syncAllToServer()
    AutoLoot.syncItemsToServer()
    AutoLoot.syncFilterToServer()
end

function AutoLoot.requestDailyBankStatus()
    sendMessage('BANK_STATUS')
end

function AutoLoot.requestUnlockStatus()
    sendMessage('UNLOCK_STATUS')
end

function AutoLoot.requestPresetUnlockStatus()
    sendMessage('PRESET_UNLOCK_STATUS')
end
function AutoLoot.onExtendedOpcode(protocol, opcode, buffer)
    if opcode ~= AutoLoot.EXTENDED_OPCODE then
        return
    end

    print(
        '[AUTOLOOT] Received opcode: ' ..
        tostring(opcode) ..
        ' buffer: ' ..
        tostring(buffer)
    )

    local command, payload =
        buffer:match("^([^|]+)|?(.*)$")

    if command == "BANK" then
        local used, remaining, limit, balance =
            payload:match("^(%d+)|(%d+)|(%d+)|(%d+)$")

        used = tonumber(used)
        remaining = tonumber(remaining)
        limit = tonumber(limit)
        balance = tonumber(balance)

        if not used or not remaining or not limit or not balance then
            return
        end

        AutoLoot.dailyBankUsed = used
        AutoLoot.dailyBankRemaining = remaining
        AutoLoot.dailyBankLimit = limit
        AutoLoot.dailyBankBalance = balance

        if AutoLoot.refreshDailyBankUI then
            AutoLoot.refreshDailyBankUI()
        end

        return
    end

    if command == "UNLOCKS" then
        local unlockedSlots = tonumber(payload)

        if not unlockedSlots then
            return
        end

        AutoLoot.unlockedSlots = math.max(
            AutoLoot.DEFAULT_UNLOCKED_SLOTS,
            math.min(
                unlockedSlots,
                AutoLoot.MAX_SLOTS
            )
        )

        if AutoLoot.refreshUnlocks then
            AutoLoot.refreshUnlocks()
        end

        return
    end

    if command == "PRESETS" then
        local unlockedPresets = tonumber(payload)

        if not unlockedPresets then
            return
        end

        unlockedPresets = math.max(
            1,
            math.min(
                unlockedPresets,
                AutoLoot.MAX_PRESETS
            )
        )

        if AutoLoot.setUnlockedPresets then
            AutoLoot.setUnlockedPresets(
                unlockedPresets
            )
        else
            AutoLoot.unlockedPresets =
                unlockedPresets

            if AutoLoot.refreshUnlocks then
                AutoLoot.refreshUnlocks()
            end
        end

        return
    end
end