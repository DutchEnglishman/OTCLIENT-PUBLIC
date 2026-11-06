-- Health bars over map tiles, for things the server draws as items but players
-- break by using them: King Thorgrim's kegs and Grakmor's totems (OTSERV
-- data/scripts/boss_skills/). "bar,x,y,z,<percent>,<ms>" on opcode 73 puts the
-- bar up or updates it; percent 0 takes it down, and ms is a safety net so a
-- lost "0" never leaves one standing.
-- The shape and colours are a creature's health bar (Creature::drawInformation,
-- Creature::setHealthPercent).
TileBars = {}

local WIDTH = 31
local HEIGHT = 4
local MARGIN_TOP = -10

local bars = {}

local function keyOf(pos)
    return pos.x .. ':' .. pos.y .. ':' .. pos.z
end

local function colorOf(percent)
    if percent > 92 then
        return '#00BC00'
    elseif percent > 60 then
        return '#50A150'
    elseif percent > 30 then
        return '#A1A100'
    elseif percent > 8 then
        return '#BF0A0A'
    elseif percent > 3 then
        return '#910F0F'
    end
    return '#850C0C'
end

local function remove(key)
    local bar = bars[key]
    if not bar then
        return
    end
    bars[key] = nil
    removeEvent(bar.expiry)
    -- Detaching also destroys it; a plain destroy would leave it in g_map's
    -- attached-widget list for good.
    if not bar.widget:isDestroyed() then
        bar.tile:detachWidget(bar.widget)
    end
end

local function create(pos)
    local tile = g_map.getTile(pos)
    if not tile then
        return nil
    end
    local widget = g_ui.createWidget('UIWidget', modules.game_interface.getMapPanel())
    widget:setPhantom(true)
    widget:setFocusable(false)
    widget:setSize({ width = WIDTH, height = HEIGHT })
    widget:setMarginTop(MARGIN_TOP)
    widget:setBackgroundColor('#000000')

    local fill = g_ui.createWidget('UIWidget', widget)
    fill:setPhantom(true)
    fill:addAnchor(AnchorTop, 'parent', AnchorTop)
    fill:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    fill:setMarginTop(1)
    fill:setMarginLeft(1)
    fill:setHeight(HEIGHT - 2)

    tile:attachWidget(widget)
    return { tile = tile, widget = widget, fill = fill }
end

function TileBars.set(pos, percent, ms)
    local key = keyOf(pos)
    if percent <= 0 or ms <= 0 then
        remove(key)
        return
    end
    local bar = bars[key]
    if not bar then
        bar = create(pos)
        if not bar then
            return
        end
        bars[key] = bar
    end
    percent = math.min(100, percent)
    bar.fill:setWidth(math.max(1, math.floor((WIDTH - 2) * percent / 100)))
    bar.fill:setBackgroundColor(colorOf(percent))
    removeEvent(bar.expiry)
    bar.expiry = scheduleEvent(function() remove(key) end, ms)
end

function TileBars.clear()
    for key in pairs(bars) do
        remove(key)
    end
end
