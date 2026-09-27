local iconTopMenu = nil
-- @ Minimap
local minimapWidget = nil -- bot fix
local otmm = true
local oldPos = nil
local fullscreenWidget
local fullscreenControls
local HEIGHT_SETTING = 'minimapPanelHeight'
local WIDE_SETTING = 'minimapWide'
-- The player's choice; the map only actually spans while the extra right panel
-- is open as well.
local wideOn = false
-- Where the map sat in its column before it went wide, so narrowing puts it
-- back there. Non-nil exactly while the map is spanning.
local narrowSlot = nil
-- Which floor the map is showing. Nothing draws it any more -- both the docked
-- panel and the full map pick floors with a pair of arrow buttons -- so this
-- is purely the 0..15 clamp upLayer/downLayer stop at, kept in step with the
-- player's own floor by onPositionChange and by fullscreen().
local virtualFloor = 7
local currentDayTime = {
    h = 12,
    m = 0
}

-- fullscreen() reparents the minimap widget out of mapController.ui, so
-- ui.minimapBorder.minimap reads nil for as long as the full map is open. Every
-- control that reached the map through that path -- floors, zoom, the compass
-- rose, reset -- was therefore dead while fullscreen. Go through here instead.
local function minimapUi()
    return mapController.ui.minimapBorder.minimap or fullscreenWidget
end

local function onPositionChange()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local pos = player:getPosition()
    if not pos then
        return
    end

    local minimapWidget = mapController.ui.minimapBorder.minimap
    if not (minimapWidget) or minimapWidget:isDragging() then
        return
    end

    if not minimapWidget.fullMapView then
        minimapWidget:setCameraPosition(pos)
    end

    minimapWidget:setCrossPosition(pos)
    virtualFloor = pos.z
end

mapController = Controller:new()
mapController:setUI('minimap', modules.game_interface.getMainRightPanel())

local function extraPanelOpen()
    local extra = modules.game_interface.getRightExtraPanel()
    return extra and extra:isOn() and extra:isExplicitlyVisible()
end

-- While spanning, the map is not in either column's stack, so both columns are
-- padded down by its height and their windows start below it.
local function updateColumnPadding()
    local ui = mapController.ui
    local pad = (narrowSlot and ui:isVisible()) and ui:getHeight() or 0
    local columns = { modules.game_interface.getRightPanel(), modules.game_interface.getRightExtraPanel() }
    for _, column in ipairs(columns) do
        if column:getPaddingTop() ~= pad then
            column:setPaddingTop(pad)
            column:fitAll()
        end
    end
end

-- Both columns are children of the root panel, so the map anchors to them by id.
local function goWide()
    local ui = mapController.ui
    local parent = ui:getParent()
    narrowSlot = {
        parent = parent,
        index = parent and parent:getChildIndex(ui) or 1,
        draggable = ui:isDraggable()
    }

    ui:setParent(modules.game_interface.getRootPanel(), true)
    ui:breakAnchors()
    ui:addAnchor(AnchorTop, 'gameRightPanel', AnchorTop)
    ui:addAnchor(AnchorRight, 'gameRightPanel', AnchorRight)
    ui:addAnchor(AnchorLeft, 'gameRightExtraPanel', AnchorLeft)
    ui:setDraggable(false)
    ui:raise()

    if parent and parent.fitAll then
        parent:fitAll()
    end
end

local function goNarrow()
    local ui = mapController.ui
    local slot = narrowSlot
    narrowSlot = nil

    -- A map that went wide from the extra column cannot go back into it once
    -- that column has closed.
    local parent = slot.parent
    local extra = modules.game_interface.getRightExtraPanel()
    if not parent or parent:isDestroyed() or (parent == extra and not extraPanelOpen()) then
        parent = modules.game_interface.getMainRightPanel()
    end

    ui:breakAnchors()
    ui:setParent(parent, true)
    parent:moveChildToIndex(ui, math.max(1, math.min(slot.index, parent:getChildCount())))
    ui:setDraggable(slot.draggable)
end

-- Offline counts as narrow: at logout the map goes back into its column, so
-- onGameStart finds it where it expects and re-spans it from there.
local function refreshWide()
    local ui = mapController.ui
    local canSpan = extraPanelOpen()
    local want = wideOn and canSpan and g_game.isOnline()

    if want and not narrowSlot then
        goWide()
    elseif not want and narrowSlot then
        goNarrow()
    end

    ui.wideToggle:setOn(narrowSlot ~= nil)
    updateColumnPadding()
end

-- One button for both: spanning needs the extra column, so going wide opens it
-- and going narrow closes it again. The side-panel arrows' own handlers do the
-- opening and closing, so their enabled state and the action bars follow.
-- Closing runs while still wide, so the map is not among the windows
-- onDecreaseRightPanels moves out of the column (its movePanel close()s them).
function toggleWide()
    local gameInterface = modules.game_interface
    wideOn = narrowSlot == nil
    g_settings.set(WIDE_SETTING, wideOn)

    if wideOn then
        if not extraPanelOpen() then
            gameInterface.onIncreaseRightPanels()
        end
    elseif extraPanelOpen() then
        gameInterface.onDecreaseRightPanels()
    end

    refreshWide()
end

function onChangeWorldTime(hour, minute)
--[[ 

check 
tfs c++ (old) : void ProtocolGame::sendWorldTime()
tfs lua (new) : function Player.sendWorldTime(self, time)
Canary: void ProtocolGame::sendTibiaTime(int32_t time)
 ]]

    currentDayTime = {
        h = hour % 24,
        m = minute
    }

    mapController:scheduleEvent(function()
        local nextH = currentDayTime.h
        local nextM = currentDayTime.m + 12
        if nextM >= 60 then
            nextH = nextH + 1
            nextM = nextM - 60
        end

        onChangeWorldTime(nextH, nextM)
    end, 30000, 'dayTime')

    -- currentDayTime is still tracked and still ticks -- the scheduled event
    -- above is what advances it. Only the drawing is gone: the day/night
    -- scroll lived inside the compass rose, and the panel no longer has one.
end

function mapController:onInit()
    self.ui.minimapBorder.minimap:getChildById('floorUpButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('floorDownButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('zoomInButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('zoomOutButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('resetButton'):hide()

    -- Same action as the fullscreen-map button next to the minimap.
    g_keyboard.bindKeyDown('Ctrl+Shift+M', openCyclopediaMap, modules.game_interface.getRootPanel())

    -- The panel carries no `save` flag, so UIMiniWindow's per-character height
    -- setting is a no-op here; the height is kept client-wide instead.
    local resizeBorder = self.ui.bottomResizeBorder
    -- Anything under the border's minimum is not a chosen size: reloadMainPanelSizes
    -- collapses a hidden panel to 0, and recording that would restore it as 0.
    function self.ui:onHeightChange(height)
        UIMiniWindow.onHeightChange(self, height)
        if height >= resizeBorder:getMinimum() then
            self.panelHeight = height
            g_settings.set(HEIGHT_SETTING, height)
        end
        updateColumnPadding()
    end

    local savedHeight = g_settings.getNumber(HEIGHT_SETTING)
    if savedHeight > 0 then
        self.ui:setHeight(math.min(math.max(savedHeight, resizeBorder:getMinimum()), resizeBorder:getMaximum()))
    end

    wideOn = g_settings.getBoolean(WIDE_SETTING)
    -- The fullscreen map hides this window; the columns must not keep a gap.
    connect(self.ui, { onVisibilityChange = updateColumnPadding })
    connect(modules.game_interface.getRightExtraPanel(), { onVisibilityChange = refreshWide })

    -- Ctrl+Left-click GM teleport lives in UIMinimap:onMouseRelease, not here.
    -- Assigning onMouseRelease on this widget would shadow that class method --
    -- which is also what carries left-click autowalk and the right-click marker
    -- menu -- and silently take both away.
end

function mapController:onGameStart()
    mapController:registerEvents(g_game, {
        onChangeWorldTime = onChangeWorldTime
    })

    mapController:registerEvents(LocalPlayer, {
        onPositionChange = onPositionChange
    }):execute()

    -- Load Map
    g_minimap.clean()

    local minimapFile = '/minimap'
    local loadFnc = nil

    if otmm then
        minimapFile = minimapFile .. '.otmm'
        loadFnc = g_minimap.loadOtmm
    else
        minimapFile = minimapFile .. '_' .. g_game.getClientVersion() .. '.otcm'
        loadFnc = g_map.loadOtcm
    end

    if g_resources.fileExists(minimapFile) then
        loadFnc(minimapFile)
    end

    self.ui.minimapBorder.minimap:load()

    -- make sure this window is docked in the right side panel by default even
    -- when there is no saved position for it (e.g. a fresh/clean client cache)
    local mainRightPanel = modules.game_interface.getMainRightPanel()
    if mainRightPanel and not mainRightPanel:hasChild(mapController.ui) then
        mainRightPanel:insertChild(1, mapController.ui)
        mapController.ui:show()
    end

    refreshWide()
end

function mapController:onGameEnd()
    -- Save Map
    if otmm then
        g_minimap.saveOtmm('/minimap.otmm')
    else
        g_map.saveOtcm('/minimap_' .. g_game.getClientVersion() .. '.otcm')
    end

    self.ui.minimapBorder.minimap:save()

    refreshWide()
end

function mapController:onTerminate()
    if iconTopMenu then
        iconTopMenu:destroy()
        iconTopMenu = nil
    end

    g_keyboard.unbindKeyDown('Ctrl+Shift+M', openCyclopediaMap, modules.game_interface.getRootPanel())
    disconnect(modules.game_interface.getRightExtraPanel(), { onVisibilityChange = refreshWide })
    if narrowSlot then
        goNarrow()
    end
    updateColumnPadding()
end

function zoomIn()
    minimapUi():zoomIn()
end

function zoomOut()
    minimapUi():zoomOut()
end

function openCyclopediaMap()
    if g_game.getClientVersion() >= 1310 then
        modules.game_cyclopedia.toggle('map')
    else
        return fullscreen()
    end
end

function fullscreen()
    local minimapWidget = mapController.ui.minimapBorder.minimap
    if not minimapWidget then
        minimapWidget = fullscreenWidget
    end
    local zoom;

    if not minimapWidget then
        return
    end

    -- Where the map ends up looking once the mode has been switched. Closing
    -- restores whatever the docked minimap was showing; opening centres on the
    -- player rather than resuming wherever the map was left last time.
    local pos

    if minimapWidget.fullMapView then
        fullscreenWidget = nil

        if fullscreenControls and not fullscreenControls:isDestroyed() then
            fullscreenControls:destroy()
        end
        fullscreenControls = nil

        minimapWidget:setParent(mapController.ui.minimapBorder)
        minimapWidget:fill('parent')
        mapController.ui:show()
        zoom = minimapWidget.zoomMinimap
        g_keyboard.unbindKeyDown('Escape')
        minimapWidget.fullMapView = false

        pos = oldPos
        oldPos = nil
    else
        fullscreenWidget = minimapWidget
        oldPos = minimapWidget:getCameraPosition()
        mapController.ui:hide(true)
        minimapWidget:setParent(modules.game_interface.getRootPanel())
        minimapWidget:fill('parent')
        zoom = minimapWidget.zoomFullmap
        g_keyboard.bindKeyDown('Escape', fullscreen)
        minimapWidget.fullMapView = true

        -- The docked panel carrying the floor and zoom buttons is hidden above,
        -- so the full map gets its own copy.
        fullscreenControls = g_ui.createWidget('MinimapFullscreenControls', minimapWidget)

        -- Wired here rather than with @onClick in the style: an @onClick in an
        -- imported style resolves its names in the global environment, not this
        -- module's, so every one of these came back nil ("attempt to call
        -- global 'downLayer'"). The docked panel's copies work only because
        -- loadUI compiles their expressions inside the loading module.
        fullscreenControls.floorUp.onClick = upLayer
        fullscreenControls.floorDown.onClick = downLayer
        fullscreenControls.zoomIn.onClick = zoomIn
        fullscreenControls.zoomOut.onClick = zoomOut

        local player = g_game.getLocalPlayer()
        pos = player and player:getPosition() or nil
        if pos then
            -- Keep the clamp honest: the map has just jumped to the player's
            -- floor, so that is where the arrow buttons count from.
            virtualFloor = pos.z
        end
    end

    pos = pos or minimapWidget:getCameraPosition()
    minimapWidget:setZoom(zoom)
    minimapWidget:setCameraPosition(pos)
end

function upLayer()
    if virtualFloor == 0 then
        return
    end

    minimapUi():floorUp(1)
    virtualFloor = virtualFloor - 1
end

function downLayer()
    if virtualFloor == 15 then
        return
    end

    minimapUi():floorDown(1)
    virtualFloor = virtualFloor + 1
end

function onClickRoseButton(dir)
    if dir == 'north' then
        minimapUi():move(0, 1)
    elseif dir == 'north-east' then
        minimapUi():move(-1, 1)
    elseif dir == 'east' then
        minimapUi():move(-1, 0)
    elseif dir == 'south-east' then
        minimapUi():move(-1, -1)
    elseif dir == 'south' then
        minimapUi():move(0, -1)
    elseif dir == 'south-west' then
        minimapUi():move(1, -1)
    elseif dir == 'west' then
        minimapUi():move(1, 0)
    elseif dir == 'north-west' then
        minimapUi():move(1, 1)
    end
end

function resetMap()
    minimapUi():reset()
    local player = g_game.getLocalPlayer()
    if player then
        virtualFloor = player:getPosition().z
    end
end

function getMiniMapUi()
    return minimapUi()
end

function extendedView(extendedView)
    if extendedView then
        if not iconTopMenu then
            iconTopMenu = modules.client_topmenu.addTopRightToggleButton('miniMap', tr('Show miniMap'),
                '/images/topbuttons/minimap', toggle)
            iconTopMenu:setOn(mapController.ui:isVisible())
            -- See game_inventory/inventory.lua: 2px black outline that only
            -- appeared in extended view. Removed here too.
            mapController.ui:setBorderWidth(0)
        end
    else
        if iconTopMenu then
            iconTopMenu:destroy()
            iconTopMenu = nil
        end
        mapController.ui:setBorderColor('alpha')
        mapController.ui:setBorderWidth(0)
        local mainRightPanel = modules.game_interface.getMainRightPanel()
        if not mainRightPanel:hasChild(mapController.ui) then
            mainRightPanel:insertChild(1, mapController.ui)
        end
        mapController.ui:show()

    end
    -- hp/minimap/equipment are always freely draggable now that they share
    -- the merged right side panel (no separate locked "main" container).
    mapController.ui.moveOnlyToMain = false
end

function toggle()
    if iconTopMenu:isOn() then
        mapController.ui:hide()
        iconTopMenu:setOn(false)
    else
        mapController.ui:show()
        iconTopMenu:setOn(true)
    end
end
