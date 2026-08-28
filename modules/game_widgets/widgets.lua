-- Widgets: one dockable window holding every widget toggle icon.
--
-- The icons here are MIRRORS, not the originals. Each source button stays where
-- its module registered it -- the top bar in view mode 2, the main panel
-- otherwise -- so both places keep working while this window is being judged.
--
-- A mirror carries no behaviour of its own. It reads a `widgetMirror` record
-- (tooltip, artwork, callback) that the two registration choke points leave on
-- every toggle they build: game_mainpanel's createButton and client_topmenu's
-- addButton. None of that is recoverable from the widget itself -- the callback
-- lives inside a closure, and UIWidget binds setIcon with no getter -- which is
-- why the record exists rather than this module reflecting over the button.

local CELL_SIZE = 20
local CELL_SPACING = 2
-- Cheap enough to poll: ~30 buttons, three isOn calls each. Polling is what
-- keeps this window correct without every owning module having to learn about
-- it -- a module flips its own button's on state, never the mirror's.
local SYNC_INTERVAL = 500

-- widgetsButton is this window's own toggle -- mirroring it inside the window
-- would give the player a button that closes the thing they clicked it in.
-- optionsMainButton is the main panel's copy of optionsButton under a second
-- id, so without it here Options would appear twice; logoutButton needs no such
-- entry because both registrations reuse one widget (topmenu.lua addButton
-- looks the id up before creating), leaving tryLogout as the live callback.
-- The dev tools stay top-bar-only.
local EXCLUDED_IDS = {
    widgetsButton = true,
    optionsMainButton = true,
    debugInfoButton = true,
    otuiEditorButton = true,
}

local widgetsWindow = nil
local widgetsButton = nil
local iconGrid = nil
local syncEvent = nil

-- source button id -> mirror widget
local mirrors = {}
local syncMirrors

-- Ordered as the icons appear today: top bar first, then whatever is still
-- sitting in the main panel. isExplicitlyVisible rather than isVisible so a
-- button hidden only because its container is hidden -- which is every main
-- panel button in extended view -- still gets a mirror, while one a module
-- deliberately hid does not. (Options > Control Buttons, which used to be the
-- other way a button got switched off, is no longer registered -- see
-- mainpanel.lua's onInit -- so its saved per-button visibility never applies.)
local function collectSources()
    local sources = {}
    local seen = {}

    local function sweep(panel)
        if not panel or panel:isDestroyed() then
            return
        end
        for _, button in ipairs(panel:getChildren()) do
            local id = button:getId()
            if id and button.widgetMirror and not EXCLUDED_IDS[id] and not seen[id]
                and not button:isDestroyed() and button:isExplicitlyVisible() then
                seen[id] = true
                table.insert(sources, button)
            end
        end
    end

    if modules.client_topmenu then
        sweep(modules.client_topmenu.getRightGameButtonsPanel())
    end
    if modules.game_mainpanel then
        sweep(modules.game_mainpanel.getOptionsPanel())
        sweep(modules.game_mainpanel.getSpecialsPanel())
    end

    return sources
end

local function createMirror(id, source)
    local info = source.widgetMirror
    local mirror = g_ui.createWidget('MainToggleButton', iconGrid)
    mirror:setId('widgetMirror_' .. id)
    mirror:setSize('20 20')
    mirror:setTooltip(info.tooltip)

    -- The two registration paths dress their buttons differently: the main
    -- panel hands over a 20x20 sprite sheet (off state left, on state right)
    -- as the image source, the top menu hands over an icon drawn over the
    -- style's own background.
    if info.image then
        mirror:setImageSource(info.image)
        mirror:setImageClip('0 0 20 20')
    end
    if info.icon then
        mirror:setIcon(info.icon)
    end

    mirror.onMouseRelease = function(widget, mousePos, mouseButton)
        if widget:containsPoint(mousePos) and mouseButton ~= MouseMidButton then
            info.callback()
            -- The owning module flips the SOURCE button's on state, so without
            -- this the mirror would keep the stale one until the next poll.
            addEvent(syncMirrors)
            return true
        end
    end

    return mirror
end

-- Everything between the window's top edge and the grid, plus everything below
-- it: header, the contents panel's margins, its padding. All static style
-- values, so this is read from the widgets rather than hardcoded as 28 -- and
-- read fresh rather than cached, because the window has no laid-out height
-- until it is first opened.
local function chromeHeight()
    local header = widgetsWindow:getChildById('miniwindowHeader')
    local contents = widgetsWindow:getChildById('contentsPanel')
    return header:getHeight() + contents:getMarginTop() + contents:getMarginBottom() +
        contents:getPaddingTop() + contents:getPaddingBottom()
end

local function updateHeight(count)
    local usable = iconGrid:getWidth()
    -- Zero until the window has been laid out once; the next poll picks it up.
    if usable < CELL_SIZE then
        return
    end

    local perRow = math.max(1, math.floor((usable + CELL_SPACING) / (CELL_SIZE + CELL_SPACING)))
    local rows = math.max(1, math.ceil(count / perRow))
    local gridHeight = rows * CELL_SIZE + (rows - 1) * CELL_SPACING

    iconGrid:setHeight(gridHeight)

    -- An exact height, not a draggable range: every row is on screen and there
    -- is no scrollbar to reach the ones that aren't. Re-applied every poll
    -- because the row count moves whenever an icon is added or removed, or the
    -- panel width changes the column count.
    --
    -- Skipped while minimized, which owns the height itself, and skipped when
    -- the height already matches -- UIMiniWindow:setHeight signals
    -- onHeightChange unconditionally and that writes to settings, which this
    -- would otherwise do twice a second forever.
    local target = gridHeight + chromeHeight()
    if not widgetsWindow:isOn() and widgetsWindow:getHeight() ~= target then
        widgetsWindow:setHeight(target)
    end
end

syncMirrors = function()
    if not iconGrid or iconGrid:isDestroyed() then
        return
    end

    local ordered = {}
    local seen = {}

    for _, source in ipairs(collectSources()) do
        local id = source:getId()
        local mirror = mirrors[id]
        if not mirror or mirror:isDestroyed() then
            mirror = createMirror(id, source)
            mirrors[id] = mirror
        end
        mirror:setOn(source:isOn())
        seen[id] = true
        table.insert(ordered, mirror)
    end

    for id, mirror in pairs(mirrors) do
        if not seen[id] then
            if not mirror:isDestroyed() then
                mirror:destroy()
            end
            mirrors[id] = nil
        end
    end

    iconGrid:reorderChildren(ordered)
    updateHeight(#ordered)
end

local function clearMirrors()
    for id, mirror in pairs(mirrors) do
        if not mirror:isDestroyed() then
            mirror:destroy()
        end
        mirrors[id] = nil
    end
end

function toggle()
    if not widgetsWindow then
        return
    end

    if widgetsWindow:isVisible() then
        widgetsWindow:close()
    else
        widgetsWindow:open()
    end
end

function onMiniWindowOpen()
    if widgetsButton then
        widgetsButton:setOn(true)
    end
    -- The grid has no width while the window is closed, so its height could not
    -- be worked out until now; without this it stays wrong until the next poll.
    addEvent(syncMirrors)
end

function onMiniWindowClose()
    if widgetsButton then
        widgetsButton:setOn(false)
    end
end

function online()
    -- Collapsed the first time a character sees it, their own choice after that.
    -- Here rather than in init() because the saved state is per character and
    -- there is no character name until login. Safe against the row-sizing in
    -- updateHeight: that skips while isOn(), and a maximize restores a height the
    -- next sync corrects within SYNC_INTERVAL.
    widgetsWindow:applyMinimizedPreference(true)

    if not syncEvent then
        syncEvent = cycleEvent(syncMirrors, SYNC_INTERVAL)
    end
end

function offline()
    if syncEvent then
        syncEvent:cancel()
        syncEvent = nil
    end
    clearMirrors()
end

function init()
    widgetsWindow = g_ui.loadUI('widgets', modules.game_interface.getRightPanel())
    widgetsWindow:setup()

    -- This window is the only way back to the icons once the top bar is gone, so
    -- closing it would strand the player: the button that reopens it lives in the
    -- main panel, which is itself hidden in extended view. Hidden rather than
    -- destroyed because MiniWindow:setup binds closeButton.onClick unconditionally
    -- and would error on a missing child. minimizeButton then takes the corner the
    -- close button occupied -- closeButton keeps its rect while hidden, so without
    -- this the header would keep a 12px hole where it used to be.
    local closeButton = widgetsWindow:getChildById('closeButton')
    closeButton:hide()
    closeButton:disable()

    local minimizeButton = widgetsWindow:getChildById('minimizeButton')
    minimizeButton:breakAnchors()
    minimizeButton:addAnchor(AnchorTop, 'parent', AnchorTop)
    minimizeButton:addAnchor(AnchorRight, 'parent', AnchorRight)
    minimizeButton:setMarginTop(2)
    minimizeButton:setMarginRight(3)

    -- Nothing binds the scrollbar any more -- contentsPanel is a plain Panel --
    -- so it never turns on and its $!on style already collapses it to width 0.
    -- Hidden as well because maximize() shows it back unconditionally, and a
    -- window that sizes itself to its rows must never grow a scroll strip.
    local scrollBar = widgetsWindow:getChildById('miniwindowScrollBar')
    scrollBar:hide()
    scrollBar:setWidth(0)

    -- The height is computed from the row count on every sync, so a drag would
    -- be undone within half a second. Disabled rather than hidden, because
    -- maximize() shows the border back unconditionally and isResizeable()
    -- checks enabled as well as visible.
    widgetsWindow:disableResize()

    iconGrid = widgetsWindow:recursiveGetChildById('iconGrid')

    widgetsWindow:getChildById('miniwindowTitle'):setText(tr('Widgets'))
    widgetsWindow:getChildById('miniwindowIcon'):setImageSource('/images/icons/icon-prey-widget')

    widgetsButton = modules.game_mainpanel.addToggleButton('widgetsButton', tr('Widgets'),
        '/images/options/button_control', toggle)
    widgetsButton:setOn(widgetsWindow:isVisible())

    connect(g_game, { onGameStart = online, onGameEnd = offline })

    if g_game.isOnline() then
        online()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = online, onGameEnd = offline })

    if syncEvent then
        syncEvent:cancel()
        syncEvent = nil
    end

    clearMirrors()

    if widgetsButton then
        widgetsButton:destroy()
        widgetsButton = nil
    end

    if widgetsWindow then
        widgetsWindow:destroy()
        widgetsWindow = nil
    end

    iconGrid = nil
end
