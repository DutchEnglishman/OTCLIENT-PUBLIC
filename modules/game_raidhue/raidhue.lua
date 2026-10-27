-- Puts a dot on the minimap for each monster of a running raid that has a hue
-- (OTSERV data/raids/raids_config.lua, `hue`). The positions come from the
-- server every couple of seconds (Raids.pushHue, raids_core.lua): the client
-- knows no creature outside its own view, so it has nothing local to draw.
--
-- Payload: "#rrggbb,<z>,x:y x:y ..." per colour and floor, joined by ";".
-- Empty clears.

RAID_HUE_OPCODE = 84

-- A dot is one tile across, but at the default zoom a minimap tile is one
-- pixel, so below this it is drawn at this size instead. Every size the zoom
-- can ask for (max(scale, this), scale a power of two) has its own pixel
-- circle in images/, since a scaled circle blurs.
local MIN_DOT_PIXELS = 5

-- From the last payload: { {color=, z=, monsters={ {x=, y=}, ... }}, ... }
local groups = {}
-- { {widget=, z=}, ... }
local dots = {}
local hookedMinimap = nil

local function getMinimapWidget()
    local minimap = modules.game_minimap
    return minimap and minimap.getMiniMapUi and minimap.getMiniMapUi() or nil
end

local function clearDots()
    for _, dot in ipairs(dots) do
        dot.widget:destroy()
    end
    dots = {}
end

-- A tile rect off the camera's floor is invalid, and an anchor to it resolves
-- to 0, so a dot on another floor is hidden rather than left anchored. Before
-- the minimap first centres on the player its camera is invalid and reads as
-- nil, so every dot stays hidden until onCameraPositionChange.
local function updateVisibility(minimapWidget)
    local camera = minimapWidget:getCameraPosition()
    for _, dot in ipairs(dots) do
        dot.widget:setVisible(camera ~= nil and dot.z == camera.z)
    end
end

local function dotSize(minimapWidget)
    return math.max(math.floor(minimapWidget:getScale()), MIN_DOT_PIXELS)
end

local function applySize(minimapWidget)
    local size = dotSize(minimapWidget)
    local image = '/modules/game_raidhue/images/dot_' .. size
    for _, dot in ipairs(dots) do
        dot.widget:setSize({ width = size, height = size })
        dot.widget:setImageSource(image)
    end
end

local function batched(minimapWidget, fn)
    local layout = minimapWidget and minimapWidget:getLayout()
    if layout then
        layout:disableUpdates()
    end
    fn()
    if layout then
        layout:enableUpdates()
        layout:update()
    end
end

local function onCameraPositionChange(minimapWidget)
    if minimapWidget == hookedMinimap then
        updateVisibility(minimapWidget)
    end
end

local function onZoomChange(minimapWidget)
    if minimapWidget == hookedMinimap then
        batched(minimapWidget, function()
            applySize(minimapWidget)
        end)
    end
end

local function buildDots(minimapWidget)
    if hookedMinimap ~= minimapWidget then
        if hookedMinimap and not hookedMinimap:isDestroyed() then
            disconnect(hookedMinimap, { onCameraPositionChange = onCameraPositionChange, onZoomChange = onZoomChange })
        end
        hookedMinimap = minimapWidget
        connect(minimapWidget, { onCameraPositionChange = onCameraPositionChange, onZoomChange = onZoomChange })
    end

    for _, group in ipairs(groups) do
        for _, m in ipairs(group.monsters) do
            local widget = g_ui.createWidget('RaidHueDot', minimapWidget)
            -- Under the floor and zoom buttons, the flags and the cross.
            minimapWidget:moveChildToIndex(widget, 1)
            widget:setImageColor(group.color)
            minimapWidget:centerInPosition(widget, { x = m.x, y = m.y, z = group.z })
            dots[#dots + 1] = { widget = widget, z = group.z }
        end
    end

    applySize(minimapWidget)
    updateVisibility(minimapWidget)
end

local function redraw()
    local minimapWidget = getMinimapWidget()
    batched(minimapWidget, function()
        clearDots()
        if minimapWidget and g_game.isOnline() then
            buildDots(minimapWidget)
        end
    end)
end

local function parse(buffer)
    local parsed = {}
    for entry in (buffer or ''):gmatch('[^;]+') do
        local color, z, list = entry:match('^(#%x+),(%d+),(.*)$')
        if color then
            local monsters = {}
            for x, y in list:gmatch('(%d+):(%d+)') do
                monsters[#monsters + 1] = { x = tonumber(x), y = tonumber(y) }
            end
            parsed[#parsed + 1] = { color = color, z = tonumber(z), monsters = monsters }
        end
    end
    return parsed
end

local function onOpcode(protocol, opcode, buffer)
    groups = parse(buffer)
    redraw()
end

local function onGameEnd()
    groups = {}
    clearDots()
end

function init()
    g_ui.importStyle('raidhue')
    ProtocolGame.registerExtendedOpcode(RAID_HUE_OPCODE, onOpcode)
    connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(RAID_HUE_OPCODE)
    disconnect(g_game, { onGameEnd = onGameEnd })
    if hookedMinimap and not hookedMinimap:isDestroyed() then
        disconnect(hookedMinimap, { onCameraPositionChange = onCameraPositionChange, onZoomChange = onZoomChange })
    end
    hookedMinimap = nil
    clearDots()
end
