-- Trainer: auto-eat, mana training and runemaking.
--
-- Runs entirely client-side. That is a deliberate limit rather than an
-- oversight: g_game.getContainers() only reports containers the player has
-- OPENED, so auto-eat cannot see a closed backpack. See
-- plans/2026-08-25-trainer-widget/plan.md for why that trade was accepted.

-- CLIENT ids, not the server ids you see in items.xml -- the two differ and
-- nothing here can translate between them. item:getId() returns the .dat client
-- id, and item:getServerId() is always 0 in this client because g_things.loadOtb
-- is bound but never called, so the OTB mapping is not loaded.
--
-- To add a food: look its server id up in the server's data/items/items.otb and
-- put the CLIENT id here. There is no fixed offset to apply -- it happens to be
-- +911 for meat and +883 for gold coin, so it must be looked up per item.
local FOOD_IDS = {
    [3577] = true, -- meat (server 2666)
}

local EAT_INTERVAL = 60 * 1000
local TICK_INTERVAL = 500

-- Spell cooldowns are modelled here because the server never reports them: this
-- fork sends no spell-cooldown opcode (there is no sendSpellCooldown in
-- src/protocolgame.cpp), and GameSpellList only switches on from protocol 870
-- (modules/game_features/features.lua:80) while this client runs 860.
--
-- 2000 is TFS's class default (src/spells.h:330). Conjure spells are
-- group="support", and Spell::configureSpell (src/spells.cpp:466) special-cases
-- only attack (1600) and healing (1000), so support keeps that 2000 default.
-- Spells that declare their own longer cooldown are found by backing off when a
-- cast is actually refused, rather than by keeping a table of every spell here.
local BASE_COOLDOWN = 2000
local MAX_COOLDOWN = 30000
local BACKOFF_STEP = 1000
-- A refusal is only credited to our cast if it arrives within this window.
local BLAME_WINDOW = 1500

-- The text fields, as opposed to the toggles: these are the only widgets that
-- should hold the keyboard, so a click anywhere else hands it back.
local FIELD_IDS = { 'manaSpell', 'manaPercent', 'runeSpell', 'runePercent' }

local trainerWindow = nil
local trainerButton = nil
local contentsPanel = nil
local tickEvent = nil
local lastEatTime = 0

-- One cooldown model per trainer: they cast different spells with different
-- cooldowns, so a shared timer would let the slower one gate the faster.
local casters = {
    rune = { interval = BASE_COOLDOWN, nextCastAt = 0 },
    mana = { interval = BASE_COOLDOWN, nextCastAt = 0 },
}
local lastCaster = nil
local lastCastAt = 0

local controls = {}

local function resetCooldowns()
    for _, caster in pairs(casters) do
        caster.interval = BASE_COOLDOWN
        caster.nextCastAt = 0
    end
    lastCaster = nil
end

local function settingsKey()
    -- Per character: two characters on one client rarely want the same spells.
    local name = g_game.getCharacterName()
    if not name or name == '' then
        return nil
    end
    return 'Trainer-' .. name
end

local function saveSettings()
    local key = settingsKey()
    if not key then
        return
    end

    g_settings.mergeNode(key, {
        autoEat = controls.autoEat:isChecked(),
        manaTraining = controls.manaTraining:isChecked(),
        manaSpell = controls.manaSpell:getText(),
        manaPercent = controls.manaPercent:getText(),
        runemaking = controls.runemaking:isChecked(),
        runeSpell = controls.runeSpell:getText(),
        runePercent = controls.runePercent:getText(),
    })
end

local function loadSettings()
    local key = settingsKey()
    local saved = key and g_settings.getNode(key) or {}

    controls.autoEat:setChecked(saved.autoEat or false)
    controls.manaTraining:setChecked(saved.manaTraining or false)
    controls.manaSpell:setText(saved.manaSpell or '')
    controls.manaPercent:setText(saved.manaPercent or '40')
    controls.runemaking:setChecked(saved.runemaking or false)
    controls.runeSpell:setText(saved.runeSpell or '')
    controls.runePercent:setText(saved.runePercent or '40')
end

-- Restores the keyboard focus chain for a widget inside a docked side panel.
--
-- Key events descend only into children that report isFocused()
-- (src/framework/ui/uiwidget.cpp:2081), so every link from rootWidget down to
-- the field has to be its parent's focused child. UIWidget::focus() cannot
-- build that chain here: it early-returns on a non-focusable widget and only
-- ever sets its IMMEDIATE parent's focused child, and side panels are created
-- with setFocusable(false) (corelib/ui/uiminiwindowcontainer.lua:7). The chain
-- therefore breaks at the panel, which is why typing worked only while the
-- window was floating -- floating parents it to rootWidget instead.
--
-- focusChild() carries no focusable check, so walking up by hand reconnects the
-- chain for this window alone, without changing focus policy for every docked
-- window in the client.
local function forceFocusChain(widget)
    local child = widget
    local parent = child:getParent()
    while parent do
        parent:focusChild(child, ActiveFocusReason)
        child = parent
        parent = child:getParent()
    end
end

-- Hands the keyboard back when a click lands anywhere but a text field.
--
-- forceFocusChain has no natural counterpart: normally clicking elsewhere moves
-- focus by focusing whatever was clicked, but gameMapPanel is focusable: false
-- (gameinterface.otui), so clicking the map focuses nothing and the field keeps
-- the keyboard. Arrow keys then move the text cursor instead of the character.
--
-- Clearing the parent's focused child is enough: propagateOnKeyText only
-- descends into focused children (src/framework/ui/uiwidget.cpp:2081), so with
-- no focused leaf the keys go unconsumed and reach the movement keybinds.
local function releaseFocus()
    for _, id in ipairs(FIELD_IDS) do
        local field = controls[id]
        if field and not field:isDestroyed() and field:isFocused() then
            local parent = field:getParent()
            if parent then
                parent:focusChild(nil, ActiveFocusReason)
            end
        end
    end
end

-- Keyed on the fields rather than on the window, so clicking a toggle, a label
-- or the title bar releases the keyboard just as clicking outside does. Only a
-- click on a field itself keeps it.
local function releaseUnlessOnField(mousePos)
    if not trainerWindow or trainerWindow:isDestroyed() or not trainerWindow:isVisible() then
        return
    end

    for _, id in ipairs(FIELD_IDS) do
        local field = controls[id]
        if field and not field:isDestroyed() and field:containsPoint(mousePos) then
            return
        end
    end

    releaseFocus()
end

-- Two hooks are needed, not one. A mouse press is offered to the deepest widget
-- first and stops at whichever consumes it, so this rootWidget handler only
-- sees clicks nothing else claimed -- the game map, empty space. A click on a
-- toggle is consumed by the toggle and never arrives here, which is why the
-- window needs its own handler below.
local function onRootMousePress(_widget, mousePos)
    releaseUnlessOnField(mousePos)

    -- Never consumes the click; this only observes where it landed.
    return false
end

-- Height goes to 0 when hidden, not just visible=false: a hidden widget still
-- occupies its slot in the anchor chain, so leaving the height at 12 left a gap
-- between the auto-eat row and the one below it whenever there was no hint.
local function setHint(text)
    local shown = text ~= nil
    controls.autoEatHint:setText(text or '')
    controls.autoEatHint:setVisible(shown)
    controls.autoEatHint:setHeight(shown and 12 or 0)
end

-- Current mana as a percentage of maximum, or nil when it can't be read.
local function manaPercent()
    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end

    local maxMana = player:getMaxMana()
    if not maxMana or maxMana <= 0 then
        return nil
    end

    return player:getMana() / maxMana * 100
end

-- The floor reading of the % field: cast while mana is ABOVE the threshold and
-- stop there, leaving that much in reserve. The rejected alternative was to
-- wait until the threshold then drain to empty.
local function aboveThreshold(percentWidget)
    local threshold = tonumber(percentWidget:getText())
    if not threshold then
        return false
    end

    local current = manaPercent()
    return current ~= nil and current > threshold
end

local function tryEat()
    local containers = g_game.getContainers()
    local sawContainer = false

    for _, container in pairs(containers) do
        sawContainer = true
        for _, item in ipairs(container:getItems()) do
            if FOOD_IDS[item:getId()] then
                g_game.use(item)
                lastEatTime = g_clock.millis()
                setHint(nil)
                return
            end
        end
    end

    -- Reported rather than swallowed: with no open container the eater can do
    -- nothing, and silence there reads as a broken toggle.
    -- Kept to one line: the hint row is 12px, so a longer string would wrap and
    -- be clipped rather than widening the window.
    if not sawContainer then
        setHint(tr('Open a backpack to auto-eat.'))
    else
        setHint(tr('No food in open containers.'))
    end
end

local function castSpell(caster, spell)
    local now = g_clock.millis()
    if now < caster.nextCastAt then
        return
    end

    g_game.talk(spell)
    caster.nextCastAt = now + caster.interval
    lastCaster = caster
    lastCastAt = now
end

-- The server's refusal is the only cooldown signal available, so it is what
-- calibrates the interval. Each refusal pushes this caster's spacing out a
-- second until casts stop bouncing; the spacing resets whenever the spell or
-- the toggle changes, so a slow spell's backoff is not inherited by a fast one.
local function onTextMessage(_mode, text)
    if not lastCaster or not text then
        return
    end

    if not text:lower():find('exhausted', 1, true) then
        return
    end

    -- Only blame our own cast. Manual casting or another source producing this
    -- message would otherwise ratchet the interval up for no reason.
    local now = g_clock.millis()
    if now - lastCastAt > BLAME_WINDOW then
        return
    end

    lastCaster.interval = math.min(lastCaster.interval + BACKOFF_STEP, MAX_COOLDOWN)
    lastCaster.nextCastAt = now + lastCaster.interval
end

local function tick()
    if not g_game.isOnline() then
        return
    end

    if controls.autoEat:isChecked() and g_clock.millis() - lastEatTime >= EAT_INTERVAL then
        tryEat()
    end

    -- Runemaking outranks mana training unconditionally: while its toggle is on
    -- the mana trainer never casts, even when runemaking is holding fire below
    -- its own threshold. Letting mana training fill those gaps would drain the
    -- mana that runemaking is waiting to reach.
    if controls.runemaking:isChecked() then
        local runeSpell = controls.runeSpell:getText()
        if runeSpell ~= '' and aboveThreshold(controls.runePercent) then
            castSpell(casters.rune, runeSpell)
        end
        return
    end

    local manaSpell = controls.manaSpell:getText()
    if controls.manaTraining:isChecked() and manaSpell ~= '' and aboveThreshold(controls.manaPercent) then
        castSpell(casters.mana, manaSpell)
    end
end

local function startTicking()
    if not tickEvent then
        tickEvent = cycleEvent(tick, TICK_INTERVAL)
    end
end

local function stopTicking()
    if tickEvent then
        tickEvent:cancel()
        tickEvent = nil
    end
end

function toggle()
    if not trainerWindow then
        return
    end

    if trainerWindow:isVisible() then
        trainerWindow:close()
    else
        trainerWindow:open()
    end
end

function onMiniWindowOpen()
    if trainerButton then
        trainerButton:setOn(true)
    end
end

function onMiniWindowClose()
    if trainerButton then
        trainerButton:setOn(false)
    end
end

function online()
    loadSettings()
    setHint(nil)
    lastEatTime = 0
    resetCooldowns()
    startTicking()
end

function offline()
    saveSettings()
    stopTicking()
    setHint(nil)
end

function init()
    trainerWindow = g_ui.loadUI('trainer', modules.game_interface.getRightPanel())
    -- Drag the bottom border to resize. The minimum sits just under the natural
    -- content height so there is room to shrink as well as grow.
    trainerWindow:enableResize()
    trainerWindow:setContentMinimumHeight(120)
    trainerWindow:setContentMaximumHeight(420)
    trainerWindow:setup()

    contentsPanel = trainerWindow:getChildById('contentsPanel')
    for _, id in ipairs({ 'autoEat', 'autoEatHint', 'manaTraining', 'manaSpell', 'manaPercent',
                          'runemaking', 'runeSpell', 'runePercent' }) do
        controls[id] = contentsPanel:getChildById(id)
    end

    -- Digits only, three of them: the percent fields are parsed with tonumber
    -- and a stray letter would silently switch that trainer off.
    for _, id in ipairs({ 'manaPercent', 'runePercent' }) do
        controls[id]:setValidCharacters('0123456789')
        controls[id]:setMaxLength(3)
    end

    -- Returning false leaves UITextEdit's own C++ mouse handling (cursor
    -- placement, selection) to run as normal -- this only reconnects focus.
    for _, id in ipairs(FIELD_IDS) do
        controls[id].onMousePress = function(widget)
            forceFocusChain(widget)
            return false
        end
    end

    -- Catches clicks inside the window that never reach rootWidget, either
    -- because this window consumed them (chrome, empty space) or because a
    -- toggle did. Returning false leaves the click to its normal handling.
    trainerWindow.onMousePress = function(_widget, mousePos)
        releaseUnlessOnField(mousePos)
        return false
    end

    trainerWindow:getChildById('miniwindowTitle'):setText(tr('Trainer'))
    trainerWindow:getChildById('miniwindowIcon'):setImageSource('/images/icons/icon-prey-widget')

    -- Every control writes through on change, so a crash or a kill can't lose
    -- settings that were only going to be flushed at logout. Changing any of
    -- them also clears the learned backoff, so a slow spell's spacing is not
    -- inherited by the one that replaces it.
    local function onSettingChanged()
        saveSettings()
        resetCooldowns()
    end

    -- Toggling also drops the keyboard. A checkbox consumes its own click, so
    -- neither the window nor rootWidget handler ever sees it -- this is the
    -- only place a toggle press can be observed.
    for _, id in ipairs({ 'autoEat', 'manaTraining', 'runemaking' }) do
        controls[id].onCheckChange = function()
            onSettingChanged()
            releaseFocus()
        end
    end

    -- Deliberately NOT releasing here: onTextChange fires on every keystroke,
    -- so releasing would drop focus as soon as you typed a character.
    for _, id in ipairs(FIELD_IDS) do
        controls[id].onTextChange = onSettingChanged
    end

    trainerButton = modules.game_mainpanel.addToggleButton('trainerButton', tr('Trainer'),
        '/images/options/button_frags', toggle)
    trainerButton:setOn(trainerWindow:isVisible())

    connect(g_game, { onGameStart = online, onGameEnd = offline, onTextMessage = onTextMessage })
    connect(rootWidget, { onMousePress = onRootMousePress })

    if g_game.isOnline() then
        online()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = online, onGameEnd = offline, onTextMessage = onTextMessage })
    disconnect(rootWidget, { onMousePress = onRootMousePress })
    stopTicking()

    if g_game.isOnline() then
        saveSettings()
    end

    if trainerButton then
        trainerButton:destroy()
        trainerButton = nil
    end

    if trainerWindow then
        trainerWindow:destroy()
        trainerWindow = nil
    end

    contentsPanel = nil
    controls = {}
end
