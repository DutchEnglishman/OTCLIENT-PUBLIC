function init()
    print('[AUTOLOOT] Module loaded')

    connect(g_game, {
        onGameStart = AutoLoot.onGameStart,
        onGameEnd = AutoLoot.onGameEnd
    })

    ProtocolGame.registerExtendedOpcode(
        AutoLoot.EXTENDED_OPCODE,
        AutoLoot.onExtendedOpcode
    )

    AutoLoot.window = g_ui.loadUI(
        'autoloot',
        modules.game_interface.getRootPanel()
    )

    if not AutoLoot.window then
        print('[AUTOLOOT] Failed to load autoloot UI')
        return
    end


    AutoLoot.initializePresets()
    AutoLoot.setupItemSlots()
    AutoLoot.setupContainerSlots()
    AutoLoot.refreshFilterUI()

    AutoLoot.window:hide()

    if g_game.isOnline() then
        AutoLoot.onGameStart()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = AutoLoot.onGameStart,
        onGameEnd = AutoLoot.onGameEnd
    })

    ProtocolGame.unregisterExtendedOpcode(
        AutoLoot.EXTENDED_OPCODE
    )

    if AutoLoot.button then
        AutoLoot.button:destroy()
        AutoLoot.button = nil
    end

    if AutoLoot.window then
        AutoLoot.window:destroy()
        AutoLoot.window = nil
    end

end

function AutoLoot.onGameStart()

    scheduleEvent(function()
        if AutoLoot.loadCharacterSettings then
            local loaded = AutoLoot.loadCharacterSettings()

            print(
                '[AUTOLOOT] Character settings load result: ' ..
                tostring(loaded)
            )
        end

        if AutoLoot.refreshPresetUI then
            AutoLoot.refreshPresetUI()
        end

        if AutoLoot.syncAllToServer then
            AutoLoot.syncAllToServer()
        end
        if AutoLoot.requestDailyBankStatus then
            AutoLoot.requestDailyBankStatus()
        end
        if AutoLoot.requestUnlockStatus then
            AutoLoot.requestUnlockStatus()
        end
        if AutoLoot.requestPresetUnlockStatus then
            AutoLoot.requestPresetUnlockStatus()
        end
    end, 250)

    if AutoLoot.button then
        return
    end

    AutoLoot.button = modules.client_topmenu.addRightGameToggleButton(
        'autoLootButton',
        tr('Autoloot'),
        '/images/topbuttons/autoloot',
        toggle
    )

    print('[AUTOLOOT] Button created')
end

function AutoLoot.onGameEnd()
    if AutoLoot.saveCharacterSettings then
        AutoLoot.saveCharacterSettings()
    end

    AutoLoot.hide()

    if AutoLoot.button then
        AutoLoot.button:destroy()
        AutoLoot.button = nil
    end
end

function AutoLoot.toggle()
    if not AutoLoot.window then
        return
    end

    if AutoLoot.window:isVisible() then
        AutoLoot.hide()
    else
        AutoLoot.show()
    end
end

local function formatMoney(value)
    local formatted = tostring(
        math.floor(value or 0)
    )

    while true do
        local replaced

        formatted, replaced =
            formatted:gsub(
                '^(-?%d+)(%d%d%d)',
                '%1,%2'
            )

        if replaced == 0 then
            break
        end
    end

    return formatted
end

function AutoLoot.refreshDailyBankUI()
    if not AutoLoot.window then
        return
    end

    local label =
        AutoLoot.window:recursiveGetChildById(
            'dailyBankLabel'
        )

    local tooltipArea =
        AutoLoot.window:recursiveGetChildById(
            'dailyBankTooltipArea'
        )

    local icon =
        AutoLoot.window:recursiveGetChildById(
            'dailyBankIcon'
        )

    if not label then
        return
    end

    label:setText(string.format(
        ' %s ',
        formatMoney(
            AutoLoot.dailyBankRemaining or 0
        )
    ))

    if tooltipArea then
        tooltipArea:setTooltip(string.format(
            'Bank Balance: %s gp',
            formatMoney(
                AutoLoot.dailyBankBalance or 0
            )
        ))
    end

    if panel then
        panel:setTooltip(tooltip)
    end

    if label then
        label:setTooltip(tooltip)
    end

    if icon then
        icon:setTooltip(tooltip)
    end
end

function AutoLoot.show()
    if not AutoLoot.window then
        return
    end

    AutoLoot.window:show()
    AutoLoot.window:raise()
    AutoLoot.window:focus()
end

function AutoLoot.hide()
    if AutoLoot.window then
        AutoLoot.window:hide()
    end
end

function show()
    AutoLoot.show()
end

function hide()
    AutoLoot.hide()
end

function toggle()
    AutoLoot.toggle()
end