function AutoLoot.setFilter(filterType)
    if filterType ~= 'accept' and filterType ~= 'ignore' then
        return
    end

    AutoLoot.filter = filterType

    print(string.format(
        '[AUTOLOOT] Filter changed to %s',
        filterType
    ))
end

function AutoLoot.onAcceptFilterChange(checked)
    if AutoLoot.updatingFilterUI then
        return
    end

    if not AutoLoot.window then
        return
    end

    if AutoLoot.updatingFilter then
        return
    end

    if not checked then
        return
    end

    AutoLoot.updatingFilter = true
    AutoLoot.filter = 'accept'

    local ignoreFilter = AutoLoot.window:recursiveGetChildById(
        'ignoreFilter'
    )

    if ignoreFilter then
        ignoreFilter:setChecked(false)
    end

    AutoLoot.updatingFilter = false

    print('[AUTOLOOT] Filter changed to accept')

    if AutoLoot.syncFilterToServer then
        AutoLoot.syncFilterToServer('accept')
    end

    if AutoLoot.saveCurrentPreset then
        AutoLoot.saveCurrentPreset()
    end

    if AutoLoot.saveCharacterSettings then
        AutoLoot.saveCharacterSettings()
    end
end


function AutoLoot.onIgnoreFilterChange(checked)
    if AutoLoot.isFilterUnlocked
        and not AutoLoot.isFilterUnlocked('ignore') then

        print('[AUTOLOOT] Ignore filter is locked')

        if AutoLoot.refreshFilterUI then
            AutoLoot.refreshFilterUI()
        end

        return
    end
    if AutoLoot.updatingFilterUI then
        return
    end

    if not AutoLoot.window then
        return
    end

    if AutoLoot.updatingFilter then
        return
    end

    if not checked then
        return
    end

    AutoLoot.updatingFilter = true
    AutoLoot.filter = 'ignore'

    local acceptFilter = AutoLoot.window:recursiveGetChildById(
        'acceptFilter'
    )

    if acceptFilter then
        acceptFilter:setChecked(false)
    end

    AutoLoot.updatingFilter = false

    print('[AUTOLOOT] Filter changed to ignore')

    if AutoLoot.syncFilterToServer then
        AutoLoot.syncFilterToServer('ignore')
    end

    if AutoLoot.saveCurrentPreset then
        AutoLoot.saveCurrentPreset()
    end

    if AutoLoot.saveCharacterSettings then
        AutoLoot.saveCharacterSettings()
    end
end

function AutoLoot.refreshFilterUI()
    if not AutoLoot.window then
        return
    end

    AutoLoot.updatingFilterUI = true
    AutoLoot.updatingFilter = true

    local acceptFilter = AutoLoot.window:recursiveGetChildById(
        'acceptFilter'
    )

    local ignoreFilter = AutoLoot.window:recursiveGetChildById(
        'ignoreFilter'
    )

    if AutoLoot.updateFilterLockVisual then
        AutoLoot.updateFilterLockVisual(
            acceptFilter,
            'accept'
        )

        AutoLoot.updateFilterLockVisual(
            ignoreFilter,
            'ignore'
        )
    end

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

    AutoLoot.updatingFilter = false
    AutoLoot.updatingFilterUI = false
end