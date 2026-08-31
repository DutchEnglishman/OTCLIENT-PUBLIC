local iconTopMenu = nil

local inventoryShrink = false

local pvpModeRadioGroup = nil 
local monkMirrorItem = nil

local function getInventoryUi()
    if inventoryShrink then
        return inventoryController.ui.offPanel
    end

    return inventoryController.ui.onPanel
end

local getSlotPanelBySlot = {
    [InventorySlotHead] = function(ui) return ui.helmet, ui.helmet.helmet end,
    [InventorySlotNeck] = function(ui) return ui.amulet, ui.amulet.amulet end,
    [InventorySlotBack] = function(ui) return ui.backpack, ui.backpack.backpack end,
    [InventorySlotBody] = function(ui) return ui.armor, ui.armor.armor end,
    [InventorySlotRight] = function(ui) return ui.shield, ui.shield.shield end,
    [InventorySlotLeft] = function(ui) return ui.sword, ui.sword.sword end,
    [InventorySlotLeg] = function(ui) return ui.legs, ui.legs.legs end,
    [InventorySlotFeet] = function(ui) return ui.boots, ui.boots.boots end,
    [InventorySlotFinger] = function(ui) return ui.ring, ui.ring.ring end,
    [InventorySlotAmmo] = function(ui) return ui.tools, ui.tools.tools end
}

local function isPlayerMonk()
    local player = g_game.getLocalPlayer()
    if not player then
        return false
    end
    return player:isMonk()
end

local function updateMonkMirrorItem(leftItem)
    if not g_game.getFeature(GameVocationMonk) then
        return
    end
    if inventoryShrink then
        return
    end

    local ui = getInventoryUi()
    if not ui or not ui.shield or not ui.shield.item then
        return
    end

    local shieldSlot = ui.shield
    local shieldItemWidget = shieldSlot.item

    if not isPlayerMonk() then
        if monkMirrorItem then
            monkMirrorItem = nil
        end
        return
    end

    local player = g_game.getLocalPlayer()
    local realShieldItem = player and player:getInventoryItem(InventorySlotRight)

    if realShieldItem then
        monkMirrorItem = nil
        return
    end

    if leftItem then
        monkMirrorItem = leftItem
        shieldItemWidget:setItem(leftItem)
        shieldItemWidget:setOpacity(0.5)
        shieldItemWidget:setDraggable(false)
        shieldItemWidget:setEnabled(false)
        shieldItemWidget:setFlipDirection(FlipDirection.Horizontal)
        shieldSlot.shield:setEnabled(false)
    else
        monkMirrorItem = nil
        shieldItemWidget:setItem(nil)
        shieldItemWidget:setOpacity(1.0)
        shieldItemWidget:setDraggable(true)
        shieldItemWidget:setEnabled(true)
        shieldItemWidget:setFlipDirection(FlipDirection.None)
        shieldSlot.shield:setEnabled(true)
        if shieldItemWidget.tier then
            shieldItemWidget.tier:setVisible(false)
        end
    end
end


-- Auto mount. Protection zones dismount the player server-side
-- (Player::onChangeZone), so a plain mount button would have to be pressed
-- again on every trip out of town. This one remembers the intent and re-sends
-- the mount as soon as the zone allows it.
local autoMount = false

-- PlayerStates.Pz mirrors the server's ICON_PIGEON and PzBlock its
-- ICON_REDSWORDS. Player::toggleMount refuses to mount outside a protection
-- zone while pz-locked, and inside one the server dismounts anyway, so asking
-- in either state only earns the player a "Sorry, not possible.".
local function isMountBlocked(states)
    return Player.isStateActive(states, PlayerStates.Pz) or Player.isStateActive(states, PlayerStates.PzBlock)
end

local function tryAutoMount()
    if not autoMount or not g_game.isOnline() or not g_game.getFeature(GamePlayerMounts) then
        return
    end

    local player = g_game.getLocalPlayer()
    if player and not player:isMounted() and not isMountBlocked(player:getStates()) then
        player:mount()
    end
end

local function refreshAutoMountButtons()
    for _, panel in ipairs({inventoryController.ui.onPanel, inventoryController.ui.offPanel}) do
        if panel.autoMount then
            panel.autoMount:setChecked(autoMount)
        end
    end
end

local function onPlayerStatesChange(player, states, oldStates)
    -- Only when one of the two blocking bits actually cleared: every other
    -- condition icon fires this event too, and each pointless attempt would
    -- put another cancel message on the player's screen.
    if autoMount and isMountBlocked(oldStates) and not isMountBlocked(states) then
        tryAutoMount()
    end
end

local function onPlayerOutfitChange(creature, outfit, oldOutfit)
    -- The server clears lookMount when it dismounts the player. Nothing else
    -- reports that, so this is what undoes a dismount taken outside a zone
    -- change -- losing the mount, an outfit condition ending.
    if autoMount and (oldOutfit.mount or 0) > 0 and (outfit.mount or 0) == 0 then
        tryAutoMount()
    end
end

function onSetAutoMount(self, checked)
    if checked == autoMount then
        return
    end

    autoMount = checked
    g_settings.set('autoMount', autoMount)
    refreshAutoMountButtons()

    if not g_game.isOnline() then
        return
    end

    if autoMount then
        tryAutoMount()
    else
        local player = g_game.getLocalPlayer()
        if player and player:isMounted() then
            player:dismount()
        end
    end
end

local function walkEvent()
    if modules.client_options.getOption('autoChaseOverride') then
        if g_game.isAttacking() and g_game.getChaseMode() == ChaseOpponent then
            selectPosture('stand', false)
        end
    end
end

local function combatEvent()
    if g_game.getChaseMode() == ChaseOpponent then
        selectPosture('follow', true)
    else
        selectPosture('stand', true)
    end
    
    if g_game.getFightMode() == FightOffensive then
        selectCombat('attack', true)
    elseif g_game.getFightMode() == FightBalanced then
        selectCombat('balanced', true)
    elseif g_game.getFightMode() == FightDefensive then
        selectCombat('defense', true)
    end
end

local function inventoryEvent(player, slot, item, oldItem)
    if inventoryShrink then
        return
    end

    local ui = getInventoryUi()
    local getSlotInfo = getSlotPanelBySlot[slot]
    if not getSlotInfo then
        return
    end

    if slot == InventorySlotRight and isPlayerMonk() and not item and monkMirrorItem then
        return
    end

    if slot == InventorySlotRight and item then
        local slotPanel, toggler = getSlotInfo(ui)
        slotPanel.item:setOpacity(1.0)
        slotPanel.item:setDraggable(true)
        slotPanel.item:setEnabled(true)
        slotPanel.item:setFlipDirection(FlipDirection.None)
        monkMirrorItem = nil
    end

    local slotPanel, toggler = getSlotInfo(ui)

    slotPanel.item:setItem(item)
    toggler:setEnabled(not item)
    slotPanel.item:setWidth(34)
    slotPanel.item:setHeight(34)
    
    slotPanel.item:setShowDuration(modules.client_options.getOption('showExpiryInInvetory'))
    slotPanel.item:setShowCharges(modules.client_options.getOption('showExpiryInInvetory'))
    ItemsDatabase.setTier(slotPanel.item, item)

    -- Rarity frame on the equipment slot. Deliberately NOT via
    -- ItemsDatabase.setRarityItem: that falls back to /images/ui/item when no
    -- frame applies, which is right for container slots (their Item style
    -- carries that image by default) but wrong here -- the inventory's item
    -- widget is a bare UIItem with no image-source, kept transparent so the
    -- slot's own background art and its empty-slot placeholder icon show
    -- through. Painting that fallback over it hid both. So: draw a frame only
    -- when the item actually has a rarity, and otherwise clear the image
    -- back to nothing.
    local rarityClip, rarityImage = ItemsDatabase.getClipAndImagePath(item)
    if rarityClip and rarityImage and rarityImage ~= '/images/ui/item' then
        slotPanel.item:setImageClip(rarityClip)
        slotPanel.item:setImageSource(rarityImage)
    else
        slotPanel.item:setImageClip(nil)
        slotPanel.item:setImageSource('')
    end

    if slot == InventorySlotLeft then
        if item and modules.game_proficiency then
            g_game.sendWeaponProficiencyAction(WeaponProficiency.WEAPON_PROFICIENCY_ITEM_INFO, item:getId())
            modules.game_proficiency.updateTopBarProficiency()
        end
        updateMonkMirrorItem(item)
    end
end

-- Task points replace the old Soul slot. They arrive over extended opcode 53
-- (game_tasksystem pushes them here) rather than being a player stat, so the
-- last value has to be held: both panels are re-read on every shrink/expand
-- and on every inventory refresh, and would otherwise drop back to 0.
-- nil until the server's first push. A placeholder rather than 0 keeps "the
-- value has not arrived" distinguishable from "the balance really is zero" --
-- otherwise a server that never sends looks identical to a new character.
local taskPoints = nil

-- Never wider than four characters: the slot is 34px and cipsoftFont draws 8px
-- per glyph, so a fifth one runs off the edge. Balances are fractional
-- (task_system_core.lua awards e.g. 0.75), hence the decimal below 100.
local function formatTaskPoints(points)
    if not points then
        return '-'
    end
    if points >= 10000 then
        return math.min(999, math.floor(points / 1000)) .. 'k'
    end
    if points >= 100 or points == math.floor(points) then
        return tostring(math.floor(points))
    end
    return string.format('%.1f', points)
end

local function refreshTaskPoints()
    local ui = getInventoryUi()
    local text = formatTaskPoints(taskPoints)

    local onWidget = ui.taskPointsPanel and ui.taskPointsPanel.taskPoints
    local offWidget = ui.capacityAndTaskPoints and ui.capacityAndTaskPoints.taskPoints

    if onWidget then
        onWidget:setText(text)
    end

    if offWidget then
        offWidget:setText(text)
    end
end

function setTaskPoints(points)
    taskPoints = tonumber(points) or 0
    refreshTaskPoints()
end

local function onFreeCapacityChange(player, freeCapacity)
    if not player then
        return
    end

    if not freeCapacity then
        return
    end
    if freeCapacity > 99999 then
        freeCapacity = math.min(9999, math.floor(freeCapacity / 1000)) .. "k"
    elseif freeCapacity > 999 then
        freeCapacity = math.floor(freeCapacity)
    elseif freeCapacity > 99 then
        freeCapacity = math.floor(freeCapacity * 10) / 10
    end
    local ui = getInventoryUi()
    if ui.capacityPanel and ui.capacityPanel.capacity then
        ui.capacityPanel.capacity:setText(freeCapacity)
    end
    if ui.capacityAndTaskPoints and ui.capacityAndTaskPoints.capacity then
        ui.capacityAndTaskPoints.capacity:setText(freeCapacity)
    end
end

function getIconsPanelOn()
    return inventoryController.ui.onPanel.icons
end

function getIconsPanelOff()
    return inventoryController.ui.offPanel.icons
end

local function refreshInventory_panel()
    local player = g_game.getLocalPlayer()
    if player then
        refreshTaskPoints()
        onFreeCapacityChange(player, player:getFreeCapacity())
    end
    if inventoryShrink then
        return
    end

    for i = InventorySlotFirst, InventorySlotPurse do
        if g_game.isOnline() then
            inventoryEvent(player, i, player:getInventoryItem(i))
        else
            inventoryEvent(player, i, nil)
        end
    end
end

local function refreshInventorySizes()
    if inventoryShrink then
        inventoryController.ui:setOn(false)
        inventoryController.ui.onPanel:hide()
        inventoryController.ui.offPanel:show()
    else
        inventoryController.ui:setOn(true)
        inventoryController.ui.onPanel:show()
        inventoryController.ui.offPanel:hide()
        refreshInventory_panel()
    end
    combatEvent()
    walkEvent()
    modules.game_mainpanel.reloadMainPanelSizes()
end

function onSetChaseMode(self, selectedChaseModeButton)
    if selectedChaseModeButton == nil then
        return
    end
    
    local buttonId = selectedChaseModeButton:getId()
    local chaseMode
    if buttonId == 'followPosture' then
        chaseMode = ChaseOpponent
    else
        chaseMode = DontChase
    end
    g_game.setChaseMode(chaseMode)
end

inventoryController = Controller:new()
inventoryController:setUI('inventory', modules.game_interface.getMainRightPanel())

function inventoryController:onInit()
    refreshInventory_panel()
    local ui = getInventoryUi()

    connect(inventoryController.ui.onPanel.pvp, {
        onCheckChange = onSetSafeFight
    })
    connect(inventoryController.ui.offPanel.pvp, {
        onCheckChange = onSetSafeFight
    })
    connect(inventoryController.ui.onPanel.expert, {
        onCheckChange = expertMode
    })

    -- Read before connecting so the setChecked below matches what the handler
    -- already holds and is swallowed by its equality guard.
    autoMount = g_settings.getBoolean('autoMount')
    connect(inventoryController.ui.onPanel.autoMount, {
        onCheckChange = onSetAutoMount
    })
    connect(inventoryController.ui.offPanel.autoMount, {
        onCheckChange = onSetAutoMount
    })
    refreshAutoMountButtons()

    pvpModeRadioGroup = UIRadioGroup.create()
    pvpModeRadioGroup:addWidget(inventoryController.ui.onPanel.whiteDoveBox)
    pvpModeRadioGroup:addWidget(inventoryController.ui.onPanel.whiteHandBox)
    pvpModeRadioGroup:addWidget(inventoryController.ui.onPanel.yellowHandBox)
    pvpModeRadioGroup:addWidget(inventoryController.ui.onPanel.redFistBox)
    connect(pvpModeRadioGroup, {
        onSelectionChange = onSetPVPMode
    })
end

function inventoryController:onGameStart()
    local player = g_game.getLocalPlayer()
    if player then
        local char = g_game.getCharacterName()
        local lastCombatControls = g_settings.getNode('LastCombatControls')
        if not table.empty(lastCombatControls) then
            if lastCombatControls[char] then
                g_game.setFightMode(lastCombatControls[char].fightMode)
                g_game.setChaseMode(lastCombatControls[char].chaseMode)
                g_game.setSafeFight(lastCombatControls[char].safeFight)
                if lastCombatControls[char].pvpMode then
                    g_game.setPVPMode(lastCombatControls[char].pvpMode)
                end
            end
        end
    end
    inventoryController:registerEvents(LocalPlayer, {
        onInventoryChange = inventoryEvent,
        onFreeCapacityChange = onFreeCapacityChange
    }):execute()

    inventoryController:registerEvents(g_game, {
        onWalk = walkEvent,
        onAutoWalk = walkEvent,
        onFightModeChange = combatEvent,
        onChaseModeChange = combatEvent,
        onSafeFightChange = combatEvent,
        onPVPModeChange = combatEvent
    }):execute()

    -- Not chained onto the :execute() above: that fires every handler in the
    -- table with no arguments, and both of these read their event payload.
    inventoryController:registerEvents(LocalPlayer, {
        onStatesChange = onPlayerStatesChange,
        onOutfitChange = onPlayerOutfitChange
    })

    -- Delayed: sendIcons() is the last thing the login stream writes, and
    -- mounting before it lands would put the player on a mount inside the
    -- temple they just logged into.
    inventoryController:scheduleEvent(tryAutoMount, 500, 'autoMountOnLogin')

    inventoryShrink = g_settings.getBoolean('mainpanel_shrink_inventory')
    refreshInventorySizes()
    refreshInventory_panel()

    local elements = {
        {inventoryController.ui.offPanel.blessings, inventoryController.ui.onPanel.blessings},
        {inventoryController.ui.offPanel.expert, inventoryController.ui.onPanel.expert},
        {inventoryController.ui.onPanel.whiteDoveBox},
        {inventoryController.ui.onPanel.whiteHandBox},
        {inventoryController.ui.onPanel.yellowHandBox},
        {inventoryController.ui.onPanel.redFistBox}
    }
    
    local showBlessings = g_game.getClientVersion() >= 1000
    local showPVPMode = g_game.getFeature(GamePVPMode)
    
    for i, elementGroup in ipairs(elements) do
        local show = (i == 1 and showBlessings) or (i > 1 and showPVPMode)
        for _, element in ipairs(elementGroup) do
            if show then
                element:show()
            else
                element:hide()
            end
        end
    end
    inventoryController.ui.onPanel.purseButton:setVisible(g_game.getFeature(GamePurseSlot))

    if isPlayerMonk() and player then
        local leftItem = player:getInventoryItem(InventorySlotLeft)
        if leftItem then
            updateMonkMirrorItem(leftItem)
        end
    end

    -- make sure this window is docked in the right side panel by default even
    -- when there is no saved position for it (e.g. a fresh/clean client cache)
    local mainRightPanel = modules.game_interface.getMainRightPanel()
    if mainRightPanel and not mainRightPanel:hasChild(inventoryController.ui) then
        mainRightPanel:insertChild(3, inventoryController.ui)
        inventoryController.ui:show()
    end
end

function inventoryController:onGameEnd()
    monkMirrorItem = nil

    -- Otherwise the next character logged in on this client would show the
    -- previous one's balance until the server's first push arrives.
    taskPoints = nil

    local lastCombatControls = g_settings.getNode('LastCombatControls')
    if not lastCombatControls then
        lastCombatControls = {}
    end
    local player = g_game.getLocalPlayer()
    if player then
        local char = g_game.getCharacterName()
        lastCombatControls[char] = {
            fightMode = g_game.getFightMode(),
            chaseMode = g_game.getChaseMode(),
            safeFight = g_game.isSafeFight()
        }
        if g_game.getFeature(GamePVPMode) then
            lastCombatControls[char].pvpMode = g_game.getPVPMode()
        end
        g_settings.setNode('LastCombatControls', lastCombatControls)
    end
    toggleAdventurerStyle(false)
end

function inventoryController:onTerminate()
    if iconTopMenu then
        iconTopMenu:destroy()
        iconTopMenu = nil
    end
    if pvpModeRadioGroup then
        disconnect(pvpModeRadioGroup, {
            onSelectionChange = onSetPVPMode
        })
        pvpModeRadioGroup:destroy()
        pvpModeRadioGroup = nil
    end
end

function onSetSafeFight(self, checked)
    if not checked then
        inventoryController.ui.onPanel.pvp:setChecked(false)
        inventoryController.ui.offPanel.pvp:setChecked(false)
      else
        inventoryController.ui.onPanel.pvp:setChecked(true)  
        inventoryController.ui.offPanel.pvp:setChecked(true)  
      end
    g_game.setSafeFight(not checked)
    if not checked then
        g_game.cancelAttack()
    end
end

function selectPosture(key, ignoreUpdate)
    local ui = getInventoryUi()
    if key == 'stand' then
        ui.standPosture:setEnabled(false)
        ui.followPosture:setEnabled(true)
        if not ignoreUpdate then
            g_game.setChaseMode(DontChase)
        end
    elseif key == 'follow' then
        ui.standPosture:setEnabled(true)
        ui.followPosture:setEnabled(false)
        if not ignoreUpdate then
            g_game.setChaseMode(ChaseOpponent)
        end
    end
end

function selectCombat(combat, ignoreUpdate)
    local ui = getInventoryUi()
    if combat == 'attack' then
        ui.attack:setEnabled(false)
        ui.balanced:setEnabled(true)
        ui.defense:setEnabled(true)
        if not ignoreUpdate then
            g_game.setFightMode(FightOffensive)
        end
    elseif combat == 'balanced' then
        ui.attack:setEnabled(true)
        ui.balanced:setEnabled(false)
        ui.defense:setEnabled(true)
        if not ignoreUpdate then
            g_game.setFightMode(FightBalanced)
        end
    elseif combat == 'defense' then
        ui.attack:setEnabled(true)
        ui.balanced:setEnabled(true)
        ui.defense:setEnabled(false)
        if not ignoreUpdate then
            g_game.setFightMode(FightDefensive)
        end
    end
end

function expertMode(self, checked)
    local ui = getInventoryUi()

    ui.whiteDoveBox:setVisible(checked)
    ui.whiteHandBox:setVisible(checked)
    ui.yellowHandBox:setVisible(checked)
    ui.redFistBox:setVisible(checked)
end

function onSetPVPMode(self, selectedPVPButton)
    if selectedPVPButton == nil then
        return
    end

    local buttonId = selectedPVPButton:getId()
    local pvpMode = PVPWhiteDove

    if buttonId == 'whiteDoveBox' then
        pvpMode = PVPWhiteDove
    elseif buttonId == 'whiteHandBox' then
        pvpMode = PVPWhiteHand
    elseif buttonId == 'yellowHandBox' then
        pvpMode = PVPYellowHand
    elseif buttonId == 'redFistBox' then
        pvpMode = PVPRedFist
    end
    g_game.setPVPMode(pvpMode)
end

function changeInventorySize()
    inventoryShrink = not inventoryShrink
    g_settings.set('mainpanel_shrink_inventory', inventoryShrink)
    refreshInventorySizes()
    modules.game_mainpanel.reloadMainPanelSizes()
    local player = g_game.getLocalPlayer()
    if player and g_game.isOnline() then
        onFreeCapacityChange(player, player:getFreeCapacity())
        refreshTaskPoints()

        -- inventoryEvent skips every slot update while shrunk (offPanel has
        -- no equipment-slot widgets to write to), so anything that changed
        -- during that time never reached onPanel and it still shows the old
        -- sprites -- an item dragged away while shrunk looks like it's still
        -- equipped until relog. Re-apply the real inventory on expand.
        -- Only when expanding: reloadInventory resolves slot widgets before
        -- inventoryEvent's own guard runs, so calling it while shrunk would
        -- index the widgets offPanel doesn't have.
        if not inventoryShrink then
            reloadInventory()
        end
    end
end

function getSlot5()
    return inventoryController.ui.onPanel.shield
end

function reloadInventory()
    
    for slot, getSlotInfo in pairs(getSlotPanelBySlot) do
        local ui = getInventoryUi()
        local slotPanel, toggler = getSlotInfo(ui)
        if slotPanel then
            local player = g_game.getLocalPlayer()
            if player then
                inventoryEvent(player, slot, player:getInventoryItem(slot))
            end
        end
    end
end

function extendedView(extendedView)
    if extendedView then
        if not iconTopMenu then
            iconTopMenu = modules.client_topmenu.addTopRightToggleButton('inventory', tr('Show inventory'),
                '/images/topbuttons/inventory', toggle)
            iconTopMenu:setOn(inventoryController.ui:isVisible())
            -- Was setBorderColor('black') + setBorderWidth(2): a 2px black
            -- outline applied only in extended view. game_minimap and
            -- game_healthinfo carried identical copies; all three removed.
            inventoryController.ui:setBorderWidth(0)
        end
    else
        if iconTopMenu then
            iconTopMenu:destroy()
            iconTopMenu = nil
        end
        inventoryController.ui:setBorderColor('alpha')
        inventoryController.ui:setBorderWidth(0)
        local mainRightPanel = modules.game_interface.getMainRightPanel()
        if not mainRightPanel:hasChild(inventoryController.ui) then
            mainRightPanel:insertChild(3, inventoryController.ui)
        end
        inventoryController.ui:show()
    end
    -- hp/minimap/equipment are always freely draggable now that they share
    -- the merged right side panel (no separate locked "main" container).
    inventoryController.ui.moveOnlyToMain = false

end

function toggle()
    if iconTopMenu:isOn() then
        inventoryController.ui:hide()
        iconTopMenu:setOn(false)
    else
        inventoryController.ui:show()
        iconTopMenu:setOn(true)
    end
end

function toggleAdventurerStyle(hasBlessing)
    for slot, getSlotInfo in pairs(getSlotPanelBySlot) do
        local ui = getInventoryUi()
        local slotPanel, toggler = getSlotInfo(ui)
        if slotPanel then
            slotPanel:setOn(hasBlessing)
        end
    end
end

function getButtonBlessings()
    return getInventoryUi().blessings
end
