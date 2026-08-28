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

function AutoLoot.sendContainer(role, item)
    if not role or not item then
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
        "CONTAINER|%s|%d|%d|%d|%d",
        role,
        serverId,
        position.x,
        position.y,
        position.z
    ))
end

function AutoLoot.sendMainContainer(item)
    return AutoLoot.sendContainer('main', item)
end

function AutoLoot.clearContainerOnServer(role)
    return sendMessage("CONTAINER_CLEAR|" .. tostring(role))
end

function AutoLoot.clearMainContainerOnServer()
    return AutoLoot.clearContainerOnServer('main')
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

    if command == "CONTAINER_LOST" then
        -- The bag was re-bound to another slot server-side, so drop the stale
        -- binding here instead of leaving the window showing one that is gone.
        if AutoLoot.forgetContainer then
            AutoLoot.forgetContainer(payload)
        end

        return
    end

    if command == "FEATURES" then
        local ignoreFlag, containersFlag =
            payload:match("^(%d+)|(%d+)$")

        if not ignoreFlag or not containersFlag then
            return
        end

        AutoLoot.ignoreUnlocked = ignoreFlag == '1'

        local containersUnlocked = containersFlag == '1'

        AutoLoot.unlockedContainers.stackables = containersUnlocked
        AutoLoot.unlockedContainers.usables = containersUnlocked

        -- A cached preset may have selected the ignore filter before the token
        -- was spent, or on a character that never had it.
        if not AutoLoot.ignoreUnlocked
            and AutoLoot.filter == 'ignore' then
            AutoLoot.filter = 'accept'
            AutoLoot.syncFilterToServer('accept')
        end

        if AutoLoot.refreshUnlocks then
            AutoLoot.refreshUnlocks()
        end

        if AutoLoot.refreshFilterUI then
            AutoLoot.refreshFilterUI()
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