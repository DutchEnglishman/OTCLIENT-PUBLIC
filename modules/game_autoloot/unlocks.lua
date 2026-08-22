AutoLoot.ignoreUnlocked =
    AutoLoot.ignoreUnlocked or false

function AutoLoot.isFilterUnlocked(filterType)
    if filterType == 'accept' then
        return true
    end

    if filterType == 'ignore' then
        return AutoLoot.ignoreUnlocked == true
    end

    return false
end

function AutoLoot.isSlotUnlocked(slotIndex)
    return slotIndex <= AutoLoot.unlockedSlots
end

function AutoLoot.isContainerUnlocked(containerType)
    return AutoLoot.unlockedContainers[containerType] == true
end

function AutoLoot.updateSlotLockVisual(widget, slotIndex)
    if not widget then
        return
    end

    local lockLabel = widget:getChildById('lockLabel')

    if not lockLabel then
        lockLabel = g_ui.createWidget('Label', widget)
        lockLabel:setId('lockLabel')
        lockLabel:setText('x')
        lockLabel:setTextAlign(AlignCenter)
        lockLabel:setColor('#777777')
        lockLabel:fill('parent')
    end

    if AutoLoot.isSlotUnlocked(slotIndex) then
        lockLabel:hide()
        widget:setOpacity(1.0)
        widget:setTooltip('Autoloot slot')
    else
        lockLabel:show()
        lockLabel:raise()
        widget:setOpacity(0.55)
        widget:setTooltip('Locked loot container')
    end
end

function AutoLoot.updateContainerLockVisual(widget, containerType)
    if not widget then
        return
    end

    local lockLabel = widget:getChildById('lockLabel')

    if not lockLabel then
        lockLabel = g_ui.createWidget('Label', widget)
        lockLabel:setId('lockLabel')
        lockLabel:setText('x')
        lockLabel:setTextAlign(AlignCenter)
        lockLabel:setColor('#777777')
        lockLabel:fill('parent')
    end

    if AutoLoot.isContainerUnlocked(containerType) then
        lockLabel:hide()
        widget:setOpacity(1.0)
        widget:setTooltip('Loot container')
    else
        lockLabel:show()
        lockLabel:raise()
        widget:setOpacity(0.55)
        widget:setTooltip('Locked loot container')
    end
end

function AutoLoot.updatePresetLockVisual(button, presetIndex)
    if not button then
        return
    end

    local lockLabel = button:getChildById('lockLabel')

    if not lockLabel then
        lockLabel = g_ui.createWidget('Label', button)
        lockLabel:setId('lockLabel')
        lockLabel:setText('*')
        lockLabel:setTextAlign(AlignCenter)
        lockLabel:setColor('#777777')
        lockLabel:fill('parent')
    end

    if AutoLoot.isPresetUnlocked(presetIndex) then
        lockLabel:hide()
        button:setOpacity(1.0)
        button:setEnabled(true)
        button:setTooltip('Preset ' .. presetIndex)
    else
        lockLabel:show()
        lockLabel:raise()
        button:setOpacity(0.55)
        button:setEnabled(false)
        button:setTooltip('Locked autoloot preset')
    end
end

function AutoLoot.updateFilterLockVisual(widget, filterType)
    if not widget then
        return
    end

    local lockLabel = widget:getChildById('lockLabel')

    if not lockLabel then
        lockLabel = g_ui.createWidget('Label', widget)
        lockLabel:setId('lockLabel')
        lockLabel:setText('*')
        lockLabel:setTextAlign(AlignCenter)
        lockLabel:setColor('#777777')
        lockLabel:fill('parent')
    end

    if AutoLoot.isFilterUnlocked(filterType) then
        lockLabel:hide()
        widget:setOpacity(1.0)
        widget:setEnabled(true)
        widget:setTooltip(
            filterType == 'accept'
                and 'Accept listed items'
                or 'Ignore listed items'
        )
    else
        lockLabel:show()
        lockLabel:raise()
        widget:setOpacity(0.55)
        widget:setEnabled(false)
        widget:setTooltip(
            'Locked autoloot filter'
        )
    end
end

function AutoLoot.refreshUnlocks()
    if not AutoLoot.window then
        return
    end

    for index = 1, AutoLoot.MAX_SLOTS do
        local slot = AutoLoot.window:recursiveGetChildById(
            'autoLootSlot' .. index
        )

        if slot then
            AutoLoot.updateSlotLockVisual(slot, index)
        end
    end

    local containerTypes = {
        'main',
        'stackables',
        'usables'
    }

    for _, containerType in ipairs(containerTypes) do
        local widget = AutoLoot.window:recursiveGetChildById(
            containerType .. 'Container'
        )

        if widget then
            AutoLoot.updateContainerLockVisual(
                widget,
                containerType
            )
        end
    end

    for presetIndex = 1, AutoLoot.MAX_PRESETS do
        local button = AutoLoot.window:recursiveGetChildById(
            'presetButton' .. presetIndex
        )

        if button then
            AutoLoot.updatePresetLockVisual(
                button,
                presetIndex
            )
        end
    end

    local acceptFilter =
        AutoLoot.window:recursiveGetChildById(
            'acceptFilter'
        )

    local ignoreFilter =
        AutoLoot.window:recursiveGetChildById(
            'ignoreFilter'
        )

    if acceptFilter then
        AutoLoot.updateFilterLockVisual(
            acceptFilter,
            'accept'
        )
    end

    if ignoreFilter then
        AutoLoot.updateFilterLockVisual(
            ignoreFilter,
            'ignore'
        )
    end
end