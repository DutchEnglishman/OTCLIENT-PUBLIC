local AUTOLOOT_SETTINGS_PREFIX = 'autoloot_'

local function getCharacterSettingsKey()
    local player = g_game.getLocalPlayer()

    if not player then
        return nil
    end

    local name = player:getName()

    if not name or name == '' then
        return nil
    end

    name = name:lower():gsub('[^%w_%-]', '_')

    return AUTOLOOT_SETTINGS_PREFIX .. name
end

function AutoLoot.saveCharacterSettings()
    local key = getCharacterSettingsKey()

    if not key then
        return
    end

    if AutoLoot.saveCurrentPreset then
        AutoLoot.saveCurrentPreset()
    end

    local data = {
        currentPreset = AutoLoot.currentPreset or 1,
        presets = AutoLoot.presets or {},
        presetNames = AutoLoot.presetNames or {}
    }

    g_settings.setNode(key, data)

    print(
        '[AUTOLOOT] Character settings saved: ' ..
        key
    )
end

function AutoLoot.loadCharacterSettings()
    local key = getCharacterSettingsKey()

    if not key then
        return false
    end

    local data = g_settings.getNode(key)

    if not data then
        print(
            '[AUTOLOOT] No saved settings found for: ' ..
            key
        )

        return false
    end

    local loadedPresets = {}

    for presetIndex, presetData in pairs(data.presets or {}) do
        local numericPresetIndex =
            tonumber(presetIndex)

        if numericPresetIndex then
            loadedPresets[numericPresetIndex] = {
                items = AutoLoot.copyItems(
                    presetData.items or {}
                ),

                containers = AutoLoot.copyContainers(
                    presetData.containers or {}
                ),

                filter =
                    presetData.filter or 'accept'
            }
        end
    end

    for presetIndex = 1, AutoLoot.MAX_PRESETS do
        if not loadedPresets[presetIndex] then
            loadedPresets[presetIndex] =
                AutoLoot.createEmptyPreset()
        end
    end

    AutoLoot.presets = loadedPresets

    AutoLoot.presetNames =
        data.presetNames or
        AutoLoot.presetNames or
        {}

    local savedPreset =
        tonumber(data.currentPreset) or 1

    local preset =
        AutoLoot.presets[savedPreset]

    if not preset then
        preset = AutoLoot.createEmptyPreset()
        AutoLoot.presets[savedPreset] = preset
    end

    AutoLoot.currentPreset = savedPreset

    AutoLoot.items =
        AutoLoot.copyItems(preset.items)

    local itemCount = 0

    for _, _ in pairs(AutoLoot.items) do
        itemCount = itemCount + 1
    end

    print(string.format(
        '[AUTOLOOT] Loaded %d items from preset %d',
        itemCount,
        savedPreset
    ))
    AutoLoot.containers =
        AutoLoot.copyContainers(preset.containers)

    AutoLoot.filter =
        preset.filter or 'accept'

    print(
        '[AUTOLOOT] Character settings loaded: ' ..
        key
    )

    if AutoLoot.refreshPresetUI then
        AutoLoot.refreshPresetUI()
    end

    if AutoLoot.syncAllToServer then
        AutoLoot.syncAllToServer()
    end

    return true
end

function AutoLoot.createEmptyPreset()
    return {
        items = {},
        containers = {
            main = nil,
            stackables = nil,
            usables = nil
        },
        filter = 'accept'
    }
end

function AutoLoot.copyItemData(itemData)
    if not itemData then
        return nil
    end

    if type(itemData) == 'number' then
        return itemData
    end

    return {
        serverId = itemData.serverId,
        clientId = itemData.clientId
    }
end

function AutoLoot.copyItems(items)
    local copiedItems = {}

    for slotIndex, itemData in pairs(items or {}) do
        local numericSlotIndex = tonumber(slotIndex)

        if numericSlotIndex then
            copiedItems[numericSlotIndex] =
                AutoLoot.copyItemData(itemData)
        end
    end

    return copiedItems
end

function AutoLoot.copyContainers(containers)
    local copiedContainers = {
        main = nil,
        stackables = nil,
        usables = nil
    }

    if not containers then
        return copiedContainers
    end

    copiedContainers.main =
        AutoLoot.copyItemData(containers.main)

    copiedContainers.stackables =
        AutoLoot.copyItemData(containers.stackables)

    copiedContainers.usables =
        AutoLoot.copyItemData(containers.usables)

    return copiedContainers
end

function AutoLoot.initializePresets()
    AutoLoot.presets = {}

    for presetIndex = 1, AutoLoot.MAX_PRESETS do
        AutoLoot.presets[presetIndex] =
            AutoLoot.createEmptyPreset()
    end

    AutoLoot.currentPreset = 1
end

AutoLoot.unlockedPresets = AutoLoot.unlockedPresets or 1

function AutoLoot.isPresetUnlocked(presetIndex)
    return presetIndex <= (AutoLoot.unlockedPresets or 1)
end

function AutoLoot.setUnlockedPresets(amount)
    amount = tonumber(amount) or 1

    if amount < 1 then
        amount = 1
    end

    if amount > AutoLoot.MAX_PRESETS then
        amount = AutoLoot.MAX_PRESETS
    end

    AutoLoot.unlockedPresets = amount

    if AutoLoot.refreshPresetButtons then
        AutoLoot.refreshPresetButtons()
    end

    if AutoLoot.refreshUnlocks then
        AutoLoot.refreshUnlocks()
    end

    print(string.format(
        '[AUTOLOOT] Unlocked presets: %d/%d',
        amount,
        AutoLoot.MAX_PRESETS
    ))
end

function AutoLoot.saveCurrentPreset()
    local preset = AutoLoot.presets[
        AutoLoot.currentPreset
    ]

    if not preset then
        preset = AutoLoot.createEmptyPreset()
        AutoLoot.presets[
            AutoLoot.currentPreset
        ] = preset
    end

    preset.items =
        AutoLoot.copyItems(AutoLoot.items)

    preset.containers =
        AutoLoot.copyContainers(AutoLoot.containers)

    preset.filter =
        AutoLoot.filter or 'accept'

    print(string.format(
        '[AUTOLOOT] Preset %d saved',
        AutoLoot.currentPreset
    ))
end

function AutoLoot.loadPreset(presetIndex)
    if presetIndex < 1
        or presetIndex > AutoLoot.MAX_PRESETS then
        return false
    end

    if presetIndex == AutoLoot.currentPreset then
        return true
    end

    AutoLoot.saveCurrentPreset()

    local preset = AutoLoot.presets[presetIndex]

    if not preset then
        preset = AutoLoot.createEmptyPreset()
        AutoLoot.presets[presetIndex] = preset
    end

    AutoLoot.currentPreset = presetIndex

    AutoLoot.items =
        AutoLoot.copyItems(preset.items)

    AutoLoot.containers =
        AutoLoot.copyContainers(preset.containers)

    AutoLoot.filter =
        preset.filter or 'accept'

    AutoLoot.refreshPresetUI()

    if AutoLoot.syncAllToServer then
        AutoLoot.syncAllToServer()
    end

    print(string.format(
        '[AUTOLOOT] Switched to preset %d',
        presetIndex
    ))

    return true
end

function AutoLoot.refreshPresetUI()

    AutoLoot.refreshPresetItemSlots()
    AutoLoot.refreshPresetFilter()
    AutoLoot.refreshPresetButtons()
    AutoLoot.refreshPresetName()

    if AutoLoot.refreshContainerSlots then
        AutoLoot.refreshContainerSlots()
    end
end

function AutoLoot.refreshPresetItemSlots()
    if not AutoLoot.window then
        return
    end

    for slotIndex = 1, AutoLoot.MAX_SLOTS do
        local slot = AutoLoot.window:recursiveGetChildById(
            'autoLootSlot' .. slotIndex
        )

        if slot then
            local itemData =
                AutoLoot.items[slotIndex]

            if itemData then
                slot:setItem(
                    Item.create(
                        itemData.clientId,
                        1
                    )
                )
            else
                slot:setItem(nil)
            end
        end
    end
end

function AutoLoot.refreshPresetFilter()
    if not AutoLoot.window then
        return
    end

    local acceptFilter =
        AutoLoot.window:recursiveGetChildById(
            'acceptFilter'
        )

    local ignoreFilter =
        AutoLoot.window:recursiveGetChildById(
            'ignoreFilter'
        )

    AutoLoot.updatingFilterUI = true

    if acceptFilter then
        acceptFilter:setChecked(
            AutoLoot.filter == 'accept'
        )
    end

    if ignoreFilter then
        ignoreFilter:setChecked(
            AutoLoot.filter == 'ignore'
        )
    end

    AutoLoot.updatingFilterUI = false
end

function AutoLoot.refreshPresetButtons()
    if not AutoLoot.window then
        return
    end

    AutoLoot.updatingPresetButtons = true

    for presetIndex = 1, AutoLoot.MAX_PRESETS do
        local button = AutoLoot.window:recursiveGetChildById(
            'presetButton' .. presetIndex
        )

        if button then
            local unlocked =
                AutoLoot.isPresetUnlocked(presetIndex)

            button:setChecked(
                unlocked and
                presetIndex == AutoLoot.currentPreset
            )

            if AutoLoot.updatePresetLockVisual then
                AutoLoot.updatePresetLockVisual(
                    button,
                    presetIndex
                )
            end
        end
    end

    AutoLoot.updatingPresetButtons = false
end

function AutoLoot.selectPreset(presetIndex)
    if AutoLoot.updatingPresetButtons then
        return
    end

    if not AutoLoot.isPresetUnlocked(presetIndex) then
        print(string.format(
            '[AUTOLOOT] Preset %d is locked',
            presetIndex
        ))

        AutoLoot.refreshPresetButtons()
        return
    end

    if presetIndex == AutoLoot.currentPreset then
        AutoLoot.refreshPresetButtons()
        return
    end

    AutoLoot.loadPreset(presetIndex)

    if AutoLoot.saveCharacterSettings then
        AutoLoot.saveCharacterSettings()
    end
end

function selectPreset(presetIndex)
    AutoLoot.selectPreset(presetIndex)
end

function AutoLoot.refreshPresetName()
    if not AutoLoot.window then
        return
    end

    local presetNameLabel = AutoLoot.window:recursiveGetChildById('presetNameLabel')
    if not presetNameLabel then
        return
    end

    local presetName = AutoLoot.presetNames[AutoLoot.currentPreset]
    if not presetName or presetName == '' then
        presetName = 'Preset ' .. AutoLoot.currentPreset
    end

    presetNameLabel:setText(presetName)
end

function AutoLoot.startPresetRename()
    if not AutoLoot.window then
        return
    end

    local presetNameLabel = AutoLoot.window:recursiveGetChildById('presetNameLabel')
    local presetNameEdit = AutoLoot.window:recursiveGetChildById('presetNameEdit')

    if not presetNameLabel or not presetNameEdit then
        return
    end

    local presetName = AutoLoot.presetNames[AutoLoot.currentPreset]
    if not presetName or presetName == '' then
        presetName = 'Preset ' .. AutoLoot.currentPreset
    end

    presetNameEdit:setText(presetName)
    presetNameLabel:hide()
    presetNameEdit:show()
    presetNameEdit:raise()
    presetNameEdit:focus()
end

function AutoLoot.finishPresetRename()
    if not AutoLoot.window then
        return
    end

    local presetNameLabel = AutoLoot.window:recursiveGetChildById('presetNameLabel')
    local presetNameEdit = AutoLoot.window:recursiveGetChildById('presetNameEdit')

    if not presetNameLabel or not presetNameEdit then
        return
    end

    local newName = presetNameEdit:getText():trim()

    if newName == '' then
        newName = 'Preset ' .. AutoLoot.currentPreset
    end

    AutoLoot.presetNames[AutoLoot.currentPreset] = newName

    presetNameLabel:setText(newName)
    presetNameEdit:hide()
    presetNameLabel:show()

    print(string.format(
        '[AUTOLOOT] Preset %d renamed to "%s"',
        AutoLoot.currentPreset,
        newName
    ))
    if AutoLoot.saveCharacterSettings then
        AutoLoot.saveCharacterSettings()
    end
end

function AutoLoot.cancelPresetRename()
    if not AutoLoot.window then
        return
    end

    local presetNameLabel = AutoLoot.window:recursiveGetChildById('presetNameLabel')
    local presetNameEdit = AutoLoot.window:recursiveGetChildById('presetNameEdit')

    if not presetNameLabel or not presetNameEdit then
        return
    end

    presetNameEdit:hide()
    presetNameLabel:show()
end

function AutoLoot.onPresetCheckChange(presetIndex, checked)
    if AutoLoot.updatingPresetButtons then
        return
    end

    if not checked then
        if presetIndex == AutoLoot.currentPreset then
            scheduleEvent(function()
                if not AutoLoot.window then
                    return
                end

                local button = AutoLoot.window:recursiveGetChildById(
                    'presetButton' .. presetIndex
                )

                if button then
                    AutoLoot.updatingPresetButtons = true
                    button:setChecked(true)
                    AutoLoot.updatingPresetButtons = false
                end
            end, 1)
        end

        return
    end

    AutoLoot.selectPreset(presetIndex)
end

function onPresetCheckChange(presetIndex, checked)
    AutoLoot.onPresetCheckChange(presetIndex, checked)
end

function startPresetRename()
    AutoLoot.startPresetRename()
end

function finishPresetRename()
    AutoLoot.finishPresetRename()
end

function cancelPresetRename()
    AutoLoot.cancelPresetRename()
end