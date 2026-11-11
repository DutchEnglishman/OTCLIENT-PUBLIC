local deathTexts = {
    regular = 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back\ninto this world in exchange for a small sacrifice\n\nSimply click on Ok to resume your journeys!',
    unfair = 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back\ninto this world in exchange for a small sacrifice\n\nThis death penalty has been reduced by %i%%\nbecause it was an unfair fight.\n\nSimply click on Ok to resume your journeys!',
    blessed = 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back into this world\n\nThis death penalty has been reduced by 100%\nbecause you are blessed with the Adventurer\'s Blessing\n\nSimply click on Ok to resume your journeys!'
}

local MIN_WIDTH = 220
local TEXT_TO_BUTTONS = 12

deathController = Controller:new()
function deathController:onInit()
    deathController:registerEvents(g_game, {
        onDeath = display,
    })
end

function deathController:onTerminate()
   deathController.ui = destroyWindows()
end

function deathController:onGameEnd()
    deathController.ui = destroyWindows()
end

function destroyWindows()
    if deathController.ui and not deathController.ui:isDestroyed() then
        deathController.ui:destroy()
    end
    return nil
end

function display(deathType, penalty)
    displayDeadMessage()
    openWindow(deathType, penalty)
    scheduleReconnect()
end

function displayDeadMessage()
    local advanceLabel = modules.game_interface.getRootPanel():recursiveGetChildById('middleCenterLabel')
    if advanceLabel:isVisible() then
        return
    end

    modules.game_textmessage.displayGameMessage(tr('You are dead.'))
end

function openWindow(deathType, penalty)
    deathController.ui = destroyWindows()
    deathController.ui = g_ui.displayUI('deathwindow', rootWidget)

    local window = deathController.ui
    local textLabel = window:getChildById('labelText')
    if deathType == DeathType.Blessed then
        textLabel:setText(deathTexts.blessed)
    elseif penalty ~= 100 then
        textLabel:setText(string.format(deathTexts.unfair, 100 - penalty))
    else
        textLabel:setText(deathTexts.regular)
    end

    local okButton = window:getChildById('buttonOk')
    local cancelButton = window:getChildById('buttonCancel')

    -- Sized from the text: fixed sizes went stale whenever the window skin's
    -- padding changed, and the text ran over the frame and the buttons.
    local textSize = textLabel:getTextSize()
    window:setWidth(math.max(MIN_WIDTH, textSize.width + window:getPaddingLeft() + window:getPaddingRight()))
    window:setHeight(window:getPaddingTop() + textSize.height + TEXT_TO_BUTTONS + okButton:getHeight() +
                         window:getPaddingBottom())

    local okFunc = function()
        CharacterList.doLogin()
        deathController.ui = destroyWindows()
    end
    local cancelFunc = function()
        g_game.safeLogout()
        deathController.ui = destroyWindows()
    end

    deathController.ui.onEnter = okFunc
    deathController.ui.onEscape = cancelFunc

    okButton.onClick = okFunc
    cancelButton.onClick = cancelFunc
end

function scheduleReconnect()
    if not g_settings.getBoolean('autoReconnect') then
        return
    end
    deathController:scheduleEvent(function()
        deathController.ui = destroyWindows()
        g_game.cancelLogin()
        CharacterList.doLogin()
    end, 2000, 'scheduleAutoReconnect')
end
