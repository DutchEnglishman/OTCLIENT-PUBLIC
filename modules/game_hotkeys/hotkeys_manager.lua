HOTKEY_MANAGER_USE = nil
HOTKEY_MANAGER_USEONSELF = 1
HOTKEY_MANAGER_USEONTARGET = 2
HOTKEY_MANAGER_USEWITH = 3
HOTKEY_MANAGER_USEATCURSOR = 4

HOTKEY_ACTION_TOGGLE_WASD = 1
HOTKEY_ACTION_ATTACK_NEXT = 2
HOTKEY_ACTION_ATTACK_PREV = 3
HOTKEY_ACTION_TOGGLE_CHASE = 4

HotkeyActions = {{
    id = HOTKEY_ACTION_TOGGLE_WASD,
    text = tr('Toggle WASD chat mode')
}, {
    id = HOTKEY_ACTION_ATTACK_NEXT,
    text = tr('Attack next creature in battle list')
}, {
    id = HOTKEY_ACTION_ATTACK_PREV,
    text = tr('Attack previous creature in battle list')
}, {
    id = HOTKEY_ACTION_TOGGLE_CHASE,
    text = tr('Toggle chase mode')
}}

HotkeyColors = {
    text = '#888888',
    textAutoSend = '#FFFFFF',
    itemUse = '#8888FF',
    itemUseSelf = '#00FF00',
    itemUseTarget = '#FF0000',
    itemUseWith = '#F5B325',
    action = '#F97ACD'
}

hotkeysManagerLoaded = false
hotkeysWindow = nil

currentHotkeyLabel = nil
currentItemPreview = nil
itemWidget = nil
addHotkeyButton = nil
removeHotkeyButton = nil
hotkeyActionCombo = nil
hotkeyText = nil
hotKeyTextLabel = nil
sendAutomatically = nil
selectObjectButton = nil
clearObjectButton = nil
useOnSelf = nil
useOnTarget = nil
useWith = nil
useAtCursor = nil
defaultComboKeys = nil
perServer = true
perCharacter = true
currentPreset = 1
presetNames = {}
presetCombo = nil
-- addOption() auto-selects the first option it is handed and setCurrentOption
-- signals unless told not to, so rebuilding the list would call straight back
-- into selectPreset. Every rebuild is fenced with this instead.
presetComboUpdating = false
-- Guards the cursor lock: released on every exit from 'Select object', so a
-- cancelled pick can never leave the whole client stuck on the crosshair.
targetCursorActive = false
mouseGrabberWidget = nil
useRadioGroup = nil
currentHotkeys = nil
boundCombosCallback = {}
boundMouseCombos = {}
hotkeysList = {}
local hotkeyBlockingSources = {}
local nextSourceId = 1
-- Per COMBO, not one shared clock: two held hotkeys repeat in lockstep, and
-- with a single timestamp whichever fired first ate the 70ms window and
-- silently swallowed the other on every cycle -- hold exori and a mana
-- potion together and one of them simply stopped, depending on press phase.
lastHotkeyTime = {}
local hotkeysWindowButton = nil
local previousRootMouseRelease = nil

-- Mouse button hotkeys. Left/Right/Middle click rarely reach here in
-- practice (the game map or some other widget consumes them first), same
-- caveat as binding e.g. 'W' as a keyboard hotkey -- the capture UI doesn't
-- stop you either way. Mouse4/Mouse5 (side buttons) are never consumed by
-- anything else in this codebase, so those fire reliably regardless of
-- what's under the cursor.
local MouseButtonNames = {
    [MouseLeftButton] = 'LeftClick',
    [MouseRightButton] = 'RightClick',
    [MouseMidButton] = 'MiddleClick',
    [MouseXButton] = 'Mouse4',
    [MouseXButton2] = 'Mouse5'
}

local function determineMouseComboDesc(mouseButton)
    local name = MouseButtonNames[mouseButton]
    if not name then
        return nil
    end
    local parts = {}
    if g_keyboard.isCtrlPressed() then
        table.insert(parts, 'Ctrl')
    end
    if g_keyboard.isAltPressed() then
        table.insert(parts, 'Alt')
    end
    if g_keyboard.isShiftPressed() then
        table.insert(parts, 'Shift')
    end
    if g_keyboard.isMetaPressed() then
        table.insert(parts, 'Meta')
    end
    table.insert(parts, name)
    return table.concat(parts, '+')
end

local function isMouseCombo(keyCombo)
    if not keyCombo then
        return false
    end
    local mainPart = keyCombo:match('([^+]+)$')
    for _, name in pairs(MouseButtonNames) do
        if mainPart == name then
            return true
        end
    end
    return false
end

local function onGlobalMouseRelease(self, mousePos, mouseButton)
    if g_game.isOnline() then
        local keyCombo = determineMouseComboDesc(mouseButton)
        if keyCombo and boundMouseCombos[keyCombo] then
            doKeyCombo(keyCombo)
            return true
        end
    end
    if previousRootMouseRelease then
        return previousRootMouseRelease(self, mousePos, mouseButton)
    end
    return false
end

-- public functions
function init()

    Keybind.new("Windows", "Show/hide Hotkeys", "Ctrl+K", "")
    Keybind.bind("Windows", "Show/hide Hotkeys", {
      {
        type = KEY_DOWN,
        callback = toggle,
      }
    })
    hotkeysWindow = g_ui.displayUI('hotkeys_manager')
    hotkeysWindow:setVisible(false)
    hotkeysWindowButton = modules.client_topmenu.addRightGameToggleButton('hotkeysWindowButton', tr('Hotkeys'), '/images/options/hotkeys', toggle)

    currentHotkeys = hotkeysWindow:getChildById('currentHotkeys')
    currentItemPreview = hotkeysWindow:getChildById('itemPreview')
    addHotkeyButton = hotkeysWindow:getChildById('addHotkeyButton')
    removeHotkeyButton = hotkeysWindow:getChildById('removeHotkeyButton')
    hotkeyText = hotkeysWindow:getChildById('hotkeyText')
    hotKeyTextLabel = hotkeysWindow:getChildById('hotKeyTextLabel')
    sendAutomatically = hotkeysWindow:getChildById('sendAutomatically')
    selectObjectButton = hotkeysWindow:getChildById('selectObjectButton')
    clearObjectButton = hotkeysWindow:getChildById('clearObjectButton')
    useOnSelf = hotkeysWindow:getChildById('useOnSelf')
    useOnTarget = hotkeysWindow:getChildById('useOnTarget')
    useWith = hotkeysWindow:getChildById('useWith')
    useAtCursor = hotkeysWindow:getChildById('useAtCursor')

    useRadioGroup = UIRadioGroup.create()
    useRadioGroup:addWidget(useOnSelf)
    useRadioGroup:addWidget(useOnTarget)
    useRadioGroup:addWidget(useWith)
    useRadioGroup:addWidget(useAtCursor)
    useRadioGroup.onSelectionChange = function(self, selected)
        onChangeUseType(selected)
    end

    hotkeyActionCombo = hotkeysWindow:getChildById('hotkeyActionCombo')

    hotkeyActionCombo:addOption('None', 0)
    for _, action in pairs(HotkeyActions) do
        hotkeyActionCombo:addOption(action.text, action.id)
    end

    hotkeyActionCombo.onOptionChange = onActionChange

    mouseGrabberWidget = g_ui.createWidget('UIWidget')
    mouseGrabberWidget:setVisible(false)
    mouseGrabberWidget:setFocusable(false)
    mouseGrabberWidget.onMouseRelease = onChooseItemMouseRelease

    -- Chained, not overwritten: other modules (e.g. game_actionbar) also
    -- hook this root panel's onMouseRelease and restore whatever was there
    -- before them, so ours needs to keep whatever's already there too.
    local gameRootPanel = modules.game_interface.getRootPanel()
    previousRootMouseRelease = gameRootPanel.onMouseRelease
    gameRootPanel.onMouseRelease = onGlobalMouseRelease

    currentHotkeys.onChildFocusChange = function(self, hotkeyLabel)
        onSelectHotkeyLabel(hotkeyLabel)
    end
    g_keyboard.bindKeyPress('Down', function()
        currentHotkeys:focusNextChild(KeyboardFocusReason)
    end, hotkeysWindow)
    g_keyboard.bindKeyPress('Up', function()
        currentHotkeys:focusPreviousChild(KeyboardFocusReason)
    end, hotkeysWindow)

    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline
    })

    -- Before load(), which ends by pushing the loaded preset onto the combo.
    setupPresetCombo()

    load()
end

function terminate()
    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline
    })

    Keybind.delete("Windows", "Show/hide Hotkeys")

    restoreTargetCursor()

    presetCombo = nil

    unload()

    local gameRootPanel = modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
    if gameRootPanel and gameRootPanel.onMouseRelease == onGlobalMouseRelease then
        gameRootPanel.onMouseRelease = previousRootMouseRelease
    end
    previousRootMouseRelease = nil

    hotkeysWindow:destroy()

    mouseGrabberWidget:destroy()
    hotkeysWindow = nil

    hotkeyActionCombo = nil
    hotKeyTextLabel = nil
    hotkeyText = nil
    sendAutomatically = nil
    selectObjectButton = nil
    clearObjectButton = nil
    mouseGrabberWidget = nil
    addHotkeyButton = nil
    removeHotkeyButton = nil
    itemPreview = nil
    useOnSelf = nil
    useOnTarget = nil
    useWith = nil
    useAtCursor = nil
    currentHotkeys = nil
    hotkeysWindowButton = nil
end

function configure(savePerServer, savePerCharacter)
    perServer = savePerServer
    perCharacter = savePerCharacter
    reload()
end

function online()
    reload()
    hide()
end

function offline()
    -- Logging out mid-pick would otherwise leave the cursor locked to the
    -- crosshair with no grabber left to release it.
    restoreTargetCursor()
    unload()
    hide()
end

function show()
    if not g_game.isOnline() then
        return
    end
    hotkeysWindow:show()
    hotkeysWindow:raise()
    hotkeysWindow:focus()
    if hotkeysWindowButton then
        hotkeysWindowButton:setOn(true)
    end
end

function hide()
    hotkeysWindow:hide()
    if hotkeysWindowButton then
        hotkeysWindowButton:setOn(false)
    end
end

function toggle()
    if not hotkeysWindow:isVisible() then
        show()
    else
        hide()
    end
end

function ok()
    save()
    hide()
end

function cancel()
    reload()
    hide()
end

-- Four hotkey presets. Unlike autoloot's there is nothing to unlock -- all four
-- are usable from the first login.
--
-- They live one level deeper inside the same 'game_hotkeys' settings node the
-- hotkeys already used, so a preset is scoped per server and per character
-- exactly as the hotkeys themselves are:
--
--   game_hotkeys[host][character] = {
--       presets       = { ['1'] = { ['F1'] = {...} }, ['2'] = {}, ... },
--       currentPreset = 2,
--       presetNames   = { ['1'] = 'Attack' },
--   }
--
-- Preset keys are STRINGS. Settings round-trip through OTML, whose tags are
-- text, so a table written under the number 1 comes back under "1" -- reading
-- it back with a numeric key finds nothing, the preset looks empty, and the
-- default F-keys overwrite it. presetKey() is the only way these are indexed,
-- presetNames included: those round-trip through the same file.
MAX_PRESETS = 4

-- Only what a preset is called until someone renames it. The name carries no
-- meaning beyond the label -- nothing checks a preset against the vocation the
-- character actually is.
PRESET_DEFAULT_NAMES = {'Knight', 'Paladin', 'Sorcerer', 'Druid'}

local function presetKey(index)
    return tostring(index)
end

-- Anything on the character node that is NOT one of these is a key combo. The
-- migration below has nothing else to tell them apart by.
local PRESET_RESERVED_KEYS = {
    presets = true,
    currentPreset = true,
    presetNames = true
}

-- Walks to the per-character node. Read-only: g_settings.getNode hands back a
-- SNAPSHOT (Config::getNode returns a node that is converted to a fresh Lua
-- table), so nothing written to what this returns reaches the file. Every
-- write goes through updateHotkeysNode instead.
local function getHotkeysNode()
    local node = g_settings.getNode('game_hotkeys')
    if not node then
        return nil
    end

    if perServer then
        if G.host == nil then
            return nil
        end
        node = node[string.gsub(G.host, "^https?://", "")]
        if not node then
            return nil
        end
    end

    if perCharacter then
        local char = g_game.getCharacterName()
        if not char or char == '' then
            return nil
        end
        node = node[char]
        if not node then
            return nil
        end
    end

    return node
end

-- Read, mutate, write back. Config::setNode stores a clone(), so the root has
-- to be handed back whole after every change -- mutating a fetched node and
-- calling g_settings.save() persists nothing.
local function updateHotkeysNode(mutator)
    local root = g_settings.getNode('game_hotkeys') or {}
    local node = root

    if perServer then
        if G.host == nil then
            return false
        end
        local host = string.gsub(G.host, "^https?://", "")
        node[host] = node[host] or {}
        node = node[host]
    end

    if perCharacter then
        local char = g_game.getCharacterName()
        if not char or char == '' then
            return false
        end
        node[char] = node[char] or {}
        node = node[char]
    end

    mutator(node)

    g_settings.setNode('game_hotkeys', root)
    g_settings.save()
    return true
end

-- Settings written before presets existed keep their combos directly on the
-- character node. Those become preset 1 rather than being thrown away.
local function getPresets(node, create)
    if not node then
        return nil
    end

    if not node.presets then
        if not create then
            return nil
        end

        local migrated = {}
        for key, value in pairs(node) do
            if not PRESET_RESERVED_KEYS[key] then
                migrated[key] = value
                node[key] = nil
            end
        end
        node.presets = { [presetKey(1)] = migrated }
    end

    return node.presets
end

function getCurrentPreset()
    return currentPreset
end

function getPresetName(index)
    local name = presetNames[presetKey(index)]
    if not name or name == '' then
        return PRESET_DEFAULT_NAMES[index] or (tr('Preset') .. ' ' .. index)
    end
    return name
end

-- Global, not local: init() is defined far above this point and would not see
-- a local declared here.
function setupPresetCombo()
    presetCombo = hotkeysWindow:recursiveGetChildById('presetCombo')
    if not presetCombo then
        return
    end

    -- Selection is read back by data, never by text: two presets renamed to the
    -- same thing would otherwise be indistinguishable to setCurrentOption.
    presetCombo.onOptionChange = function(_, _, data)
        if not presetComboUpdating then
            selectPreset(data)
        end
    end

    refreshPresetCombo()
end

-- Rebuilt rather than patched in place, so a rename lands in the drop-down list
-- as well as on the closed box.
function refreshPresetCombo()
    if not presetCombo then
        return
    end

    presetComboUpdating = true
    presetCombo:clearOptions()
    for i = 1, MAX_PRESETS do
        presetCombo:addOption(getPresetName(i), i)
    end
    presetCombo:setCurrentOptionByData(currentPreset, true)
    presetComboUpdating = false

    -- Name the live preset in the title bar too. The hotkey list gives no hint
    -- that a swap happened, and the window is often read from the title first.
    hotkeysWindow:setText(tr('Hotkeys') .. ' - ' .. getPresetName(currentPreset))
end

-- Asks for the new name in its own small window, in the same shape the key
-- capture dialog above already uses.
function renamePreset()
    local window = g_ui.createWidget('HotkeyPresetRenameWindow', rootWidget)
    window.presetIndex = currentPreset

    local edit = window:getChildById('presetNameEdit')
    edit:setText(getPresetName(currentPreset))
    edit:focus()
    edit:selectAll()

    window.onEnter = function(self)
        renamePresetOk(self)
    end
end

function renamePresetOk(window)
    local index = window.presetIndex
    local name = window:getChildById('presetNameEdit'):getText():trim()

    -- An emptied name is a reset, not a preset called ''. Storing nil puts the
    -- default back rather than leaving a blank drop-down -- and so does typing
    -- the default in by hand. Compared against the DEFAULT, never against the
    -- current display name: confirming an unchanged custom name would then wipe
    -- the very name it was showing.
    if name == '' or name == PRESET_DEFAULT_NAMES[index] then
        presetNames[presetKey(index)] = nil
    else
        presetNames[presetKey(index)] = name
    end

    updateHotkeysNode(function(node)
        node.presetNames = presetNames
    end)

    refreshPresetCombo()
    window:destroy()
end

function selectPreset(index)
    index = tonumber(index)
    if not index or index < 1 or index > MAX_PRESETS then
        return
    end

    if index == currentPreset then
        return
    end

    -- Persist the preset being left before unload destroys its widgets, then
    -- record the new selection so the reload below reads the right one.
    save()
    updateHotkeysNode(function(node)
        node.currentPreset = index
    end)

    currentPreset = index
    reload()
    refreshPresetCombo()
end

function load(forceDefaults)
    hotkeysManagerLoaded = false

    local node = getHotkeysNode()
    local hotkeys = {}

    if node then
        currentPreset = tonumber(node.currentPreset) or 1
        if currentPreset < 1 or currentPreset > MAX_PRESETS then
            currentPreset = 1
        end
        presetNames = node.presetNames or {}

        local presets = getPresets(node, false)
        if presets then
            hotkeys = presets[presetKey(currentPreset)]
        else
            -- Pre-preset settings: the combos are still on the node itself.
            for key, value in pairs(node) do
                if not PRESET_RESERVED_KEYS[key] then
                    hotkeys[key] = value
                end
            end
        end
    end

    -- An empty preset can come back from OTML as something other than a table.
    if type(hotkeys) ~= 'table' then
        hotkeys = {}
    end

    hotkeyList = {}
    if not forceDefaults then
        if not table.empty(hotkeys) then
            for keyCombo, setting in pairs(hotkeys) do
                keyCombo = tostring(keyCombo)
                addKeyCombo(keyCombo, setting)
                hotkeyList[keyCombo] = setting
            end
        end
    end

    if currentHotkeys:getChildCount() == 0 then
        loadDefautComboKeys()
    end

    hotkeysManagerLoaded = true
    refreshPresetCombo()
end

function unload()
    for keyCombo, callback in pairs(boundCombosCallback) do
        g_keyboard.unbindKeyPress(keyCombo, callback)
    end
    boundCombosCallback = {}
    boundMouseCombos = {}
    currentHotkeys:destroyChildren()
    currentHotkeyLabel = nil
    updateHotkeyForm(true)
    hotkeyList = {}
end

function reset()
    unload()
    load(true)
end

function reload()
    unload()
    load()
end

function save()
    local hotkeys = {}

    for _, child in pairs(currentHotkeys:getChildren()) do
        hotkeys[child.keyCombo] = {
            autoSend = child.autoSend,
            itemId = child.itemId,
            subType = child.subType,
            useType = child.useType,
            value = child.value,
            action = child.action
        }
    end

    updateHotkeysNode(function(node)
        local presets = getPresets(node, true)

        -- Only the selected preset is rewritten; the other three keep
        -- whatever they held.
        presets[presetKey(currentPreset)] = hotkeys
        node.currentPreset = currentPreset
        node.presetNames = presetNames
    end)

    hotkeyList = hotkeys
end

function loadDefautComboKeys()
    if not defaultComboKeys then
        for i = 1, 12 do
            addKeyCombo('F' .. i)
        end
        for i = 1, 4 do
            addKeyCombo('Shift+F' .. i)
        end
    else
        for keyCombo, keySettings in pairs(defaultComboKeys) do
            addKeyCombo(keyCombo, keySettings)
        end
    end
end

function setDefaultComboKeys(combo)
    defaultComboKeys = combo
end

function onActionChange(comboBox, option)
    local action = comboBox:getCurrentOption().data
    if currentHotkeyLabel then
        if action > 0 then
            currentHotkeyLabel.action = action
            currentHotkeyLabel.itemId = nil
            currentHotkeyLabel.value = nil
            currentHotkeyLabel.autoSend = nil
        else
            currentHotkeyLabel.action = nil
        end
        updateHotkeyLabel(currentHotkeyLabel)
        updateHotkeyForm(true, true)
    end
end

-- Deliberately identical to game_interface's own setTargetCursor, so picking an
-- object here looks exactly like right-clicking an item to use it on something.
--
-- Two things were wrong before. It was gated on the 'crosshair' option, which
-- governs the in-game tile crosshair and not this cursor -- with that option
-- off, clicking 'Select object' changed nothing on screen at all. And it never
-- locked the cursor, so the target shape was dropped again the moment the
-- pointer crossed any widget, which is unavoidable here because the mouse has
-- to travel over the interface to reach the item being picked.
local function setTargetCursor()
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    end

    g_mouse.pushCursor('target')
    -- After the push, so the push itself is not blocked by the lock.
    g_mouse.lockCursor()
    targetCursorActive = true
end

-- Global, not local: offline() and terminate() are defined above this point and
-- have to be able to drop the lock if the module goes away mid-pick.
function restoreTargetCursor()
    if targetCursorActive then
        -- Unlock before popping: popCursor has to be able to set the cursor
        -- back.
        g_mouse.unlockCursor()
        g_mouse.popCursor('target')
        targetCursorActive = false
    end

    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    end
end

-- 'Select object' takes runes and useables only -- not armour, not a wall, not
-- the ground you happened to click.
--
-- The only usability flag in Tibia.dat is MultiUse (attribute 7): the 682
-- client types that ask for a crosshair. That covers every rune, potion, vial
-- and tool. The dat's Usable flag (attribute 34) does not exist before 10.10 --
-- it appears on 0 of the 13919 types in data/things/860/Tibia.dat -- and
-- items.otb's FLAG_USEABLE is set on exactly the same 682 items, so the server
-- side knows nothing extra either.
--
-- That leaves food, which is a plain use with no flag anywhere. These are the
-- client ids behind every server id actions.xml binds to other/food/food.lua,
-- mapped through items.otb. Regenerate them the same way if that list changes.
local HOTKEY_EXTRA_USABLE_IDS = {
    130, 169, 229, 836, 841, 901, 904, 3250, 3577, 3578,
    3579, 3580, 3581, 3582, 3583, 3584, 3585, 3586, 3587, 3588,
    3589, 3590, 3591, 3592, 3593, 3594, 3595, 3596, 3597, 3599,
    3600, 3601, 3602, 3606, 3607, 3723, 3724, 3725, 3726, 3727,
    3728, 3729, 3730, 3731, 3732, 5096, 6125, 6277, 6278, 6392,
    6500, 6541, 6542, 6543, 6544, 6545, 6569, 6574, 7158, 7159,
    7373, 7374, 7375, 7376, 7377, 8010, 8011, 8012, 8013, 8014,
    8015, 8016, 8017, 8019, 8177, 8194, 8197, 9537, 10219, 10329,
    10453, 11459, 11460, 11461, 11462, 11681, 11682, 11683
}

local extraUsableIds = {}
for _, id in ipairs(HOTKEY_EXTRA_USABLE_IDS) do
    extraUsableIds[id] = true
end

local function isHotkeyUsable(item)
    return item:isMultiUse() or extraUsableIds[item:getId()] == true
end

function onChooseItemMouseRelease(self, mousePosition, mouseButton)
    local item = nil
    if mouseButton == MouseLeftButton then
        local clickedWidget = modules.game_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)
        if clickedWidget then
            if clickedWidget:getClassName() == 'UIGameMap' then
                local tile = clickedWidget:getTile(mousePosition)
                if tile then
                    local thing = tile:getTopMoveThing()
                    if thing and thing:isItem() then
                        item = thing
                    end
                end
            elseif clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
                item = clickedWidget:getItem()
            end
        end
    end

    -- Rejected out loud. Silently doing nothing reads as a broken button, since
    -- the window reopens looking exactly as it did before the click.
    if item and not isHotkeyUsable(item) then
        modules.game_textmessage.displayFailureMessage(
            tr('You can only assign runes and useable items to a hotkey.'))
        item = nil
    end

    if item and currentHotkeyLabel then
        currentHotkeyLabel.itemId = item:getId()
        if item:isFluidContainer() then
            currentHotkeyLabel.subType = item:getSubType()
        end
        if item:isMultiUse() then
            currentHotkeyLabel.useType = HOTKEY_MANAGER_USEWITH
        else
            currentHotkeyLabel.useType = HOTKEY_MANAGER_USE
        end
        currentHotkeyLabel.value = nil
        currentHotkeyLabel.autoSend = false
        updateHotkeyLabel(currentHotkeyLabel)
        updateHotkeyForm(true)
    end

    show()
    restoreTargetCursor()
    self:ungrabMouse()
    return true
end

function startChooseItem()
    if g_ui.isMouseGrabbed() then
        return
    end
    mouseGrabberWidget:grabMouse()
    setTargetCursor()
    hide()
end

function clearObject()
    currentHotkeyLabel.itemId = nil
    currentHotkeyLabel.subType = nil
    currentHotkeyLabel.useType = nil
    currentHotkeyLabel.autoSend = nil
    currentHotkeyLabel.value = nil
    currentHotkeyLabel.action = nil
    updateHotkeyLabel(currentHotkeyLabel)
    updateHotkeyForm(true)
end

function addHotkey()
    local assignWindow = g_ui.createWidget('HotkeyAssignWindow', rootWidget)
    assignWindow:grabKeyboard()

    local comboLabel = assignWindow:getChildById('comboPreview')
    comboLabel.keyCombo = ''
    assignWindow.onKeyDown = hotkeyCapture
    -- Clicking the Add/Cancel buttons themselves is unaffected: a left-click
    -- release on those is consumed by the button widget itself and never
    -- reaches this window-level handler.
    assignWindow.onMouseRelease = mouseHotkeyCapture
end

function mouseHotkeyCapture(assignWindow, mousePos, mouseButton)
    local keyCombo = determineMouseComboDesc(mouseButton)
    if not keyCombo then
        return false
    end
    local comboPreview = assignWindow:getChildById('comboPreview')
    comboPreview:setText(tr('Current hotkey to add: %s', keyCombo))
    comboPreview.keyCombo = keyCombo
    comboPreview:resizeToText()
    assignWindow:getChildById('addButton'):enable()
    return true
end

function addKeyCombo(keyCombo, keySettings, focus)
    if keyCombo == nil or #keyCombo == 0 then
        return
    end
    if not keyCombo then
        return
    end
    if modules.game_actionbar and modules.game_actionbar.removeHotkeyFromActionBar then
        modules.game_actionbar.removeHotkeyFromActionBar(keyCombo)
    end
    local hotkeyLabel = currentHotkeys:getChildById(keyCombo)
    if not hotkeyLabel then
        hotkeyLabel = g_ui.createWidget('HotkeyListLabel')
        hotkeyLabel:setId(keyCombo)

        local children = currentHotkeys:getChildren()
        children[#children + 1] = hotkeyLabel
        table.sort(children, function(a, b)
            if a:getId():len() < b:getId():len() then
                return true
            elseif a:getId():len() == b:getId():len() then
                return a:getId() < b:getId()
            else
                return false
            end
        end)
        for i = 1, #children do
            if children[i] == hotkeyLabel then
                currentHotkeys:insertChild(i, hotkeyLabel)
                break
            end
        end

        if keySettings then
            currentHotkeyLabel = hotkeyLabel
            hotkeyLabel.keyCombo = keyCombo
            hotkeyLabel.autoSend = toboolean(keySettings.autoSend)
            hotkeyLabel.itemId = tonumber(keySettings.itemId)
            hotkeyLabel.subType = tonumber(keySettings.subType)
            hotkeyLabel.useType = tonumber(keySettings.useType)
            hotkeyLabel.action = tonumber(keySettings.action)
            if keySettings.value then
                hotkeyLabel.value = tostring(keySettings.value)
            end
        else
            hotkeyLabel.keyCombo = keyCombo
            hotkeyLabel.autoSend = false
            hotkeyLabel.itemId = nil
            hotkeyLabel.subType = nil
            hotkeyLabel.useType = nil
            hotkeyLabel.action = nil
            hotkeyLabel.value = ''
        end

        updateHotkeyLabel(hotkeyLabel)

        if isMouseCombo(keyCombo) then
            boundMouseCombos[keyCombo] = true
        else
            boundCombosCallback[keyCombo] = function()
                doKeyCombo(keyCombo)
            end
            g_keyboard.bindKeyPress(keyCombo, boundCombosCallback[keyCombo])
        end
    end

    if focus then
        currentHotkeys:focusChild(hotkeyLabel)
        currentHotkeys:ensureChildVisible(hotkeyLabel)
        updateHotkeyForm(true)
    end
end

function doKeyCombo(keyCombo)
    if not g_game.isOnline() then
        return
    end
    if not canPerformKeyCombo(keyCombo) then
        return
    end
    local hotKey = hotkeyList[keyCombo]
    if not hotKey then
        return
    end

    if g_clock.millis() - (lastHotkeyTime[keyCombo] or 0) < modules.client_options.getOption('hotkeyDelay') then
        return
    end
    lastHotkeyTime[keyCombo] = g_clock.millis()

    if hotKey.action then
        if hotKey.action == HOTKEY_ACTION_TOGGLE_WASD then
            modules.game_console.toggleChat()
        elseif hotKey.action == HOTKEY_ACTION_ATTACK_NEXT then
            modules.game_battle.attackNext()
        elseif hotKey.action == HOTKEY_ACTION_ATTACK_PREV then
            modules.game_battle.attackNext(true)
        elseif hotKey.action == HOTKEY_ACTION_TOGGLE_CHASE then
            toggleChaseMode()
        end

    elseif hotKey.itemId == nil then
        if not hotKey.value or #hotKey.value == 0 then
            return
        end
        if hotKey.autoSend then
            modules.game_console.sendMessage(hotKey.value)
        else
            scheduleEvent(function()
                if not modules.game_console.isChatEnabled() then
                    modules.game_console.switchChatOnCall()
                end
                modules.game_console.setTextEditText(hotKey.value)
            end, 1)
        end
    else
        executeHotkeyItem(hotKey.useType, hotKey.itemId, hotKey.subType)
    end
end

function toggleChaseMode()
    local currentMode = g_game.getChaseMode()
    local nextMode = currentMode == ChaseOpponent and DontChase or ChaseOpponent
    g_game.setChaseMode(nextMode)
end

function executeHotkeyItem(action, itemId, subType)
    local function get_use_thing_under_cursor()
        local mapPanel = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
        if not mapPanel then
            return nil
        end

        local mousePosition = g_window.getMousePosition()
        if not mapPanel:containsPoint(mousePosition) then
            return nil
        end

        local mapPosition = mapPanel:getPosition(mousePosition)
        if not mapPosition then
            return nil
        end

        local localPlayer = g_game.getLocalPlayer()
        if localPlayer and mapPosition.z ~= localPlayer:getPosition().z then
            local dz = mapPosition.z - localPlayer:getPosition().z
            mapPosition.x = mapPosition.x + dz
            mapPosition.y = mapPosition.y + dz
            mapPosition.z = localPlayer:getPosition().z
        end

        local tile = g_map.getTile(mapPosition)
        if not tile then
            return nil
        end

        local virtualItem = Item.create(itemId)
        if virtualItem:isFluidContainer() or virtualItem:isMultiUse() then
            return tile:getTopMultiUseThing()
        end
        return tile:getTopUseThing()
    end

    if action == HOTKEY_MANAGER_USE then
        if g_game.getClientVersion() < 780 or subType then
            local item = g_game.findPlayerItem(itemId, subType or -1)
            if item then
                g_game.use(item)
            end
        else
            g_game.useInventoryItem(itemId)
        end
    elseif action == HOTKEY_MANAGER_USEONSELF then
        if g_game.getClientVersion() < 780 or subType then
            local item = g_game.findPlayerItem(itemId, subType or -1)
            if item then
                g_game.useWith(item, g_game.getLocalPlayer())
            end
        else
            g_game.useInventoryItemWith(itemId, g_game.getLocalPlayer())
        end
    elseif action == HOTKEY_MANAGER_USEONTARGET then
        local attackingCreature = g_game.getAttackingCreature()
        if not attackingCreature then
            local item = Item.create(itemId)
            if g_game.getClientVersion() < 780 or subType then
                local tmpItem = g_game.findPlayerItem(itemId, subType or -1)
                if not tmpItem then
                    return
                end
                item = tmpItem
            end

            modules.game_interface.startUseWith(item)
            return
        end

        if not attackingCreature:getTile() then
            return
        end
        if g_game.getClientVersion() < 780 or subType then
            local item = g_game.findPlayerItem(itemId, subType or -1)
            if item then
                g_game.useWith(item, attackingCreature)
            end
        else
            g_game.useInventoryItemWith(itemId, attackingCreature)
        end
    elseif action == HOTKEY_MANAGER_USEWITH then
        local item = Item.create(itemId)
        if g_game.getClientVersion() < 780 or subType then
            local tmpItem = g_game.findPlayerItem(itemId, subType or -1)
            if not tmpItem then
                return true
            end
            item = tmpItem
        end
        modules.game_interface.startUseWith(item)
    elseif action == HOTKEY_MANAGER_USEATCURSOR then
        local useThing = get_use_thing_under_cursor()
        if not useThing then
            local item = Item.create(itemId)
            if g_game.getClientVersion() < 780 or subType then
                local tmpItem = g_game.findPlayerItem(itemId, subType or -1)
                if not tmpItem then
                    return
                end
                item = tmpItem
            end
            modules.game_interface.startUseWith(item)
            return
        end

        if g_game.getClientVersion() < 780 or subType then
            local item = g_game.findPlayerItem(itemId, subType or -1)
            if item then
                g_game.useWith(item, useThing)
            end
        else
            g_game.useInventoryItemWith(itemId, useThing)
        end
    end
end

function updateHotkeyLabel(hotkeyLabel)
    if not hotkeyLabel then
        return
    end
    if hotkeyLabel.useType == HOTKEY_MANAGER_USEONSELF then
        hotkeyLabel:setText(tr('%s: (use object on yourself)', hotkeyLabel.keyCombo))
        hotkeyLabel:setColor(HotkeyColors.itemUseSelf)
    elseif hotkeyLabel.useType == HOTKEY_MANAGER_USEONTARGET then
        hotkeyLabel:setText(tr('%s: (use object on target)', hotkeyLabel.keyCombo))
        hotkeyLabel:setColor(HotkeyColors.itemUseTarget)
    elseif hotkeyLabel.useType == HOTKEY_MANAGER_USEWITH then
        hotkeyLabel:setText(tr('%s: (use object with crosshair)', hotkeyLabel.keyCombo))
        hotkeyLabel:setColor(HotkeyColors.itemUseWith)
    elseif hotkeyLabel.useType == HOTKEY_MANAGER_USEATCURSOR then
        hotkeyLabel:setText(tr('%s: (use object at cursor position)', hotkeyLabel.keyCombo))
        hotkeyLabel:setColor(HotkeyColors.itemUseWith)
    elseif hotkeyLabel.itemId ~= nil then
        hotkeyLabel:setText(tr('%s: (use object)', hotkeyLabel.keyCombo))
        hotkeyLabel:setColor(HotkeyColors.itemUse)
    elseif hotkeyLabel.action then
        for _, action in pairs(HotkeyActions) do
            if action.id == hotkeyLabel.action then
                hotkeyLabel:setText(tr('%s: ' .. action.text, hotkeyLabel.keyCombo))
                break
            end
        end
        hotkeyLabel:setColor(HotkeyColors.action)
    else
        local text = hotkeyLabel.keyCombo .. ': '
        if hotkeyLabel.value then
            text = text .. hotkeyLabel.value
        end
        hotkeyLabel:setText(text)
        if hotkeyLabel.autoSend then
            hotkeyLabel:setColor(HotkeyColors.autoSend)
        else
            hotkeyLabel:setColor(HotkeyColors.text)
        end
    end
end

function updateHotkeyForm(reset, dontUpdateCombo)
    if currentHotkeyLabel then
        removeHotkeyButton:enable()
        if currentHotkeyLabel.itemId ~= nil then
            if not dontUpdateCombo then
                hotkeyActionCombo:setCurrentIndex(1)
            end
            hotkeyActionCombo:disable()
            hotkeyText:clearText()
            hotkeyText:disable()
            hotKeyTextLabel:disable()
            sendAutomatically:setChecked(false)
            sendAutomatically:disable()
            selectObjectButton:disable()
            clearObjectButton:enable()
            currentItemPreview:setItemId(currentHotkeyLabel.itemId)
            if currentHotkeyLabel.subType then
                currentItemPreview:setItemSubType(currentHotkeyLabel.subType)
            end
            if currentItemPreview:getItem():isMultiUse() then
                useOnSelf:enable()
                useOnTarget:enable()
                useWith:enable()
                useAtCursor:enable()
                if currentHotkeyLabel.useType == HOTKEY_MANAGER_USEONSELF then
                    useRadioGroup:selectWidget(useOnSelf)
                elseif currentHotkeyLabel.useType == HOTKEY_MANAGER_USEONTARGET then
                    useRadioGroup:selectWidget(useOnTarget)
                elseif currentHotkeyLabel.useType == HOTKEY_MANAGER_USEWITH then
                    useRadioGroup:selectWidget(useWith)
                elseif currentHotkeyLabel.useType == HOTKEY_MANAGER_USEATCURSOR then
                    useRadioGroup:selectWidget(useAtCursor)
                end
            else
                useOnSelf:disable()
                useOnTarget:disable()
                useWith:disable()
                useAtCursor:disable()
                useRadioGroup:clearSelected()
            end
        elseif currentHotkeyLabel.action then
            if not dontUpdateCombo then
                hotkeyActionCombo:setCurrentOptionByData(currentHotkeyLabel.action)
            end
            hotkeyActionCombo:enable()
            hotkeyText:clearText()
            hotkeyText:disable()
            hotKeyTextLabel:disable()
            sendAutomatically:setChecked(false)
            sendAutomatically:disable()
            selectObjectButton:disable()
            useOnSelf:disable()
            useOnTarget:disable()
            useWith:disable()
            useAtCursor:disable()
            useRadioGroup:clearSelected()
            selectObjectButton:disable()
            clearObjectButton:disable()
        else
            if not dontUpdateCombo then
                hotkeyActionCombo:setCurrentIndex(1)
            end
            hotkeyActionCombo:enable()
            useOnSelf:disable()
            useOnTarget:disable()
            useWith:disable()
            useAtCursor:disable()
            useRadioGroup:clearSelected()
            hotkeyText:enable()
            hotkeyText:focus()
            hotKeyTextLabel:enable()
            hotkeyText:setText(currentHotkeyLabel.value)
            if reset then
                hotkeyText:setCursorPos(-1)
            end
            sendAutomatically:setChecked(currentHotkeyLabel.autoSend)
            sendAutomatically:setEnabled(currentHotkeyLabel.value and #currentHotkeyLabel.value > 0)
            selectObjectButton:enable()
            clearObjectButton:disable()
            currentItemPreview:clearItem()
        end
    else
        if not dontUpdateCombo then
            hotkeyActionCombo:setCurrentIndex(1)
        end
        hotkeyActionCombo:disable()
        removeHotkeyButton:disable()
        hotkeyText:disable()
        sendAutomatically:disable()
        selectObjectButton:disable()
        clearObjectButton:disable()
        useOnSelf:disable()
        useOnTarget:disable()
        useWith:disable()
        useAtCursor:disable()
        hotkeyText:clearText()
        useRadioGroup:clearSelected()
        sendAutomatically:setChecked(false)
        currentItemPreview:clearItem()
    end
end

function removeHotkey()
    if currentHotkeyLabel == nil then
        return
    end
    local keyCombo = currentHotkeyLabel.keyCombo
    if isMouseCombo(keyCombo) then
        boundMouseCombos[keyCombo] = nil
    else
        g_keyboard.unbindKeyPress(keyCombo, boundCombosCallback[keyCombo])
        boundCombosCallback[keyCombo] = nil
    end
    currentHotkeyLabel:destroy()
    currentHotkeyLabel = nil
end

function onHotkeyTextChange(value)
    if not hotkeysManagerLoaded then
        return
    end
    if currentHotkeyLabel == nil then
        return
    end
    currentHotkeyLabel.value = value
    if value == '' then
        currentHotkeyLabel.autoSend = false
    end
    updateHotkeyLabel(currentHotkeyLabel)
    updateHotkeyForm(false, true)
end

function onSendAutomaticallyChange(autoSend)
    if not hotkeysManagerLoaded then
        return
    end
    if currentHotkeyLabel == nil then
        return
    end
    if not currentHotkeyLabel.value or #currentHotkeyLabel.value == 0 then
        return
    end
    currentHotkeyLabel.autoSend = autoSend
    updateHotkeyLabel(currentHotkeyLabel)
    updateHotkeyForm(false, true)
end

function onChangeUseType(useTypeWidget)
    if not hotkeysManagerLoaded then
        return
    end
    if currentHotkeyLabel == nil then
        return
    end
    if useTypeWidget == useOnSelf then
        currentHotkeyLabel.useType = HOTKEY_MANAGER_USEONSELF
    elseif useTypeWidget == useOnTarget then
        currentHotkeyLabel.useType = HOTKEY_MANAGER_USEONTARGET
    elseif useTypeWidget == useWith then
        currentHotkeyLabel.useType = HOTKEY_MANAGER_USEWITH
    elseif useTypeWidget == useAtCursor then
        currentHotkeyLabel.useType = HOTKEY_MANAGER_USEATCURSOR
    else
        currentHotkeyLabel.useType = HOTKEY_MANAGER_USE
    end
    updateHotkeyLabel(currentHotkeyLabel)
    updateHotkeyForm()
end

function onSelectHotkeyLabel(hotkeyLabel)
    currentHotkeyLabel = hotkeyLabel
    updateHotkeyForm(true)
end

function hotkeyCapture(assignWindow, keyCode, keyboardModifiers)
    local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers)
    local comboPreview = assignWindow:getChildById('comboPreview')
    comboPreview:setText(tr('Current hotkey to add: %s', keyCombo))
    comboPreview.keyCombo = keyCombo
    comboPreview:resizeToText()
    assignWindow:getChildById('addButton'):enable()
    return true
end

function hotkeyCaptureOk(assignWindow, keyCombo)
    addKeyCombo(keyCombo, nil, true)
    assignWindow:destroy()
end

function enableHotkeys(sourceId)
    if sourceId then
        hotkeyBlockingSources[sourceId] = nil
    end
end

function disableHotkeys(sourceIdentifier)
    local sourceId = sourceIdentifier or ("auto_" .. nextSourceId)
    nextSourceId = nextSourceId + 1
    hotkeyBlockingSources[sourceId] = true
    return sourceId
end

local function getCallerModule()
    local info = debug.getinfo(3, "S")
    if info and info.source then
        local source = info.source:gsub("@", "")
        local moduleName = source:match("/modules/([^/]+)/") or 
                          source:match("\\modules\\([^\\]+)\\") or
                          source:match("([^/\\]+)%.lua$") or
                          "unknown"
        return moduleName:gsub("_", "")
    end
    return "unknown"
end

function createHotkeyBlock(sourceIdentifier)
    local callerModule = getCallerModule()
    local fullId = sourceIdentifier and 
        (sourceIdentifier .. "_" .. callerModule) or 
        ("auto_" .. callerModule .. "_" .. nextSourceId)
    local blockId = disableHotkeys(fullId)
    return {
        release = function()
            enableHotkeys(blockId)
        end,
        getId = function()
            return fullId
        end
    }
end

function areHotkeysDisabled()
    for _ in pairs(hotkeyBlockingSources) do
        return true
    end
    return false
end

function clearAllHotkeyBlocks()
    hotkeyBlockingSources = {}
end
function getHotkeyBlockingInfo()
    local count = 0
    local sources = {}
    for sourceId in pairs(hotkeyBlockingSources) do
        count = count + 1
        table.insert(sources, sourceId)
    end
    table.sort(sources)
    return count, sources
end

function printHotkeyBlockingInfo()
    local count, sources = getHotkeyBlockingInfo()
    print("=== Hotkey Blocking Info ===")
    print("Total blocks: " .. count)
    if count > 0 then
        print("Active sources:")
        for i, source in ipairs(sources) do
            print("  " .. i .. ". " .. source)
        end
    else
        print("No active blocks")
    end
    print("===========================")
end

-- Even if hotkeys are enabled, only the hotkeys containing Ctrl or Alt or F1-F12 will be enabled when
-- chat is opened (no WASD mode). This is made to prevent executing hotkeys while typing...
function canPerformKeyCombo(keyCombo)
    if areHotkeysDisabled() then
        return false
    end
    -- Mouse buttons can't type into the chat box, so the WASD-mode
    -- restriction below (which exists purely to stop keyboard hotkeys from
    -- firing while you're typing) doesn't apply to them.
    if isMouseCombo(keyCombo) then
        return true
    end
    if not modules.game_console.isChatEnabled() then
        return true
    end
    local platformType = g_window.getPlatformType() or ""
    local isMacOS = platformType:find("MACOS") ~= nil
    if isMacOS then
        return  string.match(keyCombo, "Cmd%+") or
                string.match(keyCombo, "Ctrl%+") or
                string.match(keyCombo, "Alt%+") or
                string.match(keyCombo, "Option%+") or
                string.match(keyCombo, "F%d+")
    end
    return  string.match(keyCombo, "Ctrl%+") or
            string.match(keyCombo, "Alt%+") or
            string.match(keyCombo, "F%d+")
end

-- Actionbar
function removeHotkeyByCombo(keyCombo)
    if not keyCombo or keyCombo == "" then
        return false
    end
    local hotkeyLabel = currentHotkeys and currentHotkeys:getChildById(keyCombo)
    if hotkeyLabel then
        if boundCombosCallback[keyCombo] then
            g_keyboard.unbindKeyPress(keyCombo, boundCombosCallback[keyCombo])
            boundCombosCallback[keyCombo] = nil
        elseif boundMouseCombos[keyCombo] then
            boundMouseCombos[keyCombo] = nil
        end
        if currentHotkeyLabel == hotkeyLabel then
            currentHotkeyLabel = nil
        end
        hotkeyLabel:destroy()
        updateHotkeyForm(true)
        return true
    end
    return false
end

function isHotkeyUsedByManager(keyCombo)
    if not keyCombo or keyCombo == "" then
        return false
    end
    if boundCombosCallback[keyCombo] or boundMouseCombos[keyCombo] then
        return true
    end
    if currentHotkeys then
        local hotkeyLabel = currentHotkeys:getChildById(keyCombo)
        if hotkeyLabel then
            return true
        end
    end
    return false
end
