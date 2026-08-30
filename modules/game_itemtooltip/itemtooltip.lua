-- Hover tooltips for items.
--
-- Text is fetched from the server on hover rather than shipped with every
-- item: rarity, item level, upgrade bonuses and refine rolls are per-instance
-- values composed in Lua server-side, and they change as an item is upgraded,
-- so they can't be baked into the item's wire form or cached here without
-- going stale. See OTSERV's data/tooltip/tooltip_core.lua.
--
-- This deliberately does NOT use g_tooltip: that renders a single label in
-- one colour, and each section here needs its own colour.

-- Must match ItemTooltip.OPCODE on the server.
local TOOLTIP_OPCODE = 61

-- Positions use the standard Tibia "container position" encoding:
--   inventory slot -> {x = 65535, y = slot,               z = 0}
--   container slot -> {x = 65535, y = containerId | 0x40, z = slotIndex}
local CONTAINER_POSITION_X = 65535
local CONTAINER_FLAG = 0x40

-- Colour per section tag. Name and rarity are overridden by rarity colour
-- below when the item has one.
local SECTION_COLORS = {
    N = '#FFFFFF', -- name (recoloured by rarity)
    R = '#FFFFFF', -- rarity (recoloured by rarity)
    L = '#A2E2C2', -- item level
    S = '#FFBB22', -- item stats
    F = '#E257E3', -- refine rolls
    A = '#2266FF', -- attributes
}

-- Rarity id -> colour, matching the upgrade system's COMMON..LEGENDARY.
local RARITY_COLORS = {
    [1] = '#00C000', -- common green
    [2] = '#4080FF', -- rare blue
    [3] = '#A020F0', -- epic purple
    [4] = '#DF7010', -- legendary
}

-- Render order, and the separator boundaries: one hairline between each pair
-- of adjacent groups that both have content, none within a group. N is absent
-- because the name is drawn in the header row, between the weight and the
-- sprite -- and rarity and item level share the name's group, so they run on
-- underneath it with no rule breaking them up.
local SECTION_GROUPS = {
    { 'R', 'L' },
    { 'S' },
    { 'F' },
    { 'A' },
}

local PADDING = 6
local SPRITE_SIZE = 32
local HEADER_GAP = 4
local SEPARATOR_GAP = 3
local SEPARATOR_BLOCK = SEPARATOR_GAP * 2 + 1
local SEPARATOR_WIDTH_RATIO = 1 / 3
local WEIGHT_COLOR = '#DFDFDF'
-- The top row hugs the corners rather than sitting on the body's padding, but
-- has to clear the frame: the background is sliced at image-border 5, and the
-- outline copies reach one pixel further out than the text itself.
local FRAME_INSET_X = 6
local FRAME_INSET_Y = 6
local WIDTH_SCALE = 2

-- 1px offsets used to fake a black outline (8 directions = solid edge).
local OUTLINE_OFFSETS = {
    { -1, -1 }, { 0, -1 }, { 1, -1 },
    { -1, 0 },             { 1, 0 },
    { -1, 1 },  { 0, 1 },  { 1, 1 },
}

local tooltipWindow = nil

local nextRequestId = 0
local pending = {}
local hoveredWidget = nil

-- Forward declaration: renderTooltip (below) calls this, but it's defined
-- further down next to init(). Lua binds locals at compile time, so without
-- this it would resolve to nil.
local ensureWidget

local function positionKey(pos)
    return string.format('%d,%d,%d', pos.x, pos.y, pos.z)
end

local function describeTarget(pos)
    if pos.x ~= CONTAINER_POSITION_X then
        return nil
    end
    if pos.y >= CONTAINER_FLAG then
        return 'container', pos.y - CONTAINER_FLAG, pos.z
    end
    return 'slot', pos.y, 0
end

local function hideTooltip()
    if tooltipWindow then
        tooltipWindow:hide()
    end
end

local function moveTooltip()
    if not tooltipWindow or not tooltipWindow:isVisible() then
        return
    end

    local pos = g_window.getMousePosition()
    local size = tooltipWindow:getSize()
    local screen = { width = g_window.getWidth(), height = g_window.getHeight() }

    -- Offset from the cursor, flipped when it would run off screen.
    local x = pos.x + 12
    local y = pos.y + 12
    if x + size.width > screen.width then
        x = pos.x - size.width - 4
    end
    if y + size.height > screen.height then
        y = pos.y - size.height - 4
    end

    tooltipWindow:setPosition({ x = math.max(0, x), y = math.max(0, y) })
end

-- payload is "<tag>=<text>\t<tag>=<text>..."; A (attributes) repeats.
-- Y (rarity id) and W (weight) drive presentation rather than being body
-- lines, so they come back separately instead of landing in sections.
local function parseSections(payload)
    local sections = {}
    local rarityId = 0
    local weight = nil

    for field in payload:gmatch('[^\t]+') do
        local tag, text = field:match('^(%a)=(.*)$')
        if tag == 'Y' then
            rarityId = tonumber(text) or 0
        elseif tag == 'W' then
            weight = text
        elseif tag then
            sections[tag] = sections[tag] or {}
            sections[tag][#sections[tag] + 1] = text
        end
    end

    return sections, rarityId, weight
end

-- The engine has no text-outline property, and generating a stroked font at
-- runtime hung the client, so the outline is eight 1px black copies. They're
-- created BEFORE the coloured label so they render underneath -- children draw
-- in creation order.
local function createOutlinedLabel(text, color)
    local shadows = {}
    for _, offset in ipairs(OUTLINE_OFFSETS) do
        local shadow = g_ui.createWidget('ItemTooltipLine', tooltipWindow)
        shadow:setText(text)
        shadow:setColor('#000000')
        shadows[#shadows + 1] = { widget = shadow, dx = offset[1], dy = offset[2] }
    end

    local label = g_ui.createWidget('ItemTooltipLine', tooltipWindow)
    label:setText(text)
    label:setColor(color)

    return { widget = label, shadows = shadows }
end

-- Anchored rather than absolutely positioned so lines follow the window as it
-- tracks the cursor. Anchors don't resize the parent, so there's no feedback
-- into the explicit setSize. width = nil leaves the label at its text width.
local function placeOutlinedLabel(entry, x, y, width)
    for _, shadow in ipairs(entry.shadows) do
        local w = shadow.widget
        if width then
            w:setWidth(width)
        end
        w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        w:addAnchor(AnchorTop, 'parent', AnchorTop)
        w:setMarginLeft(x + shadow.dx)
        w:setMarginTop(y + shadow.dy)
    end

    local label = entry.widget
    if width then
        label:setWidth(width)
    end
    label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    label:addAnchor(AnchorTop, 'parent', AnchorTop)
    label:setMarginLeft(x)
    label:setMarginTop(y)
end

-- Built in two passes: create-and-measure everything first, size the window
-- once, then place. Nothing here may resize the window from inside a layout
-- pass -- an auto-fitting layout plus an explicit setSize fed back into each
-- other and hung the client.
local function renderTooltip(payload, item)
    if not ensureWidget() then
        return
    end

    tooltipWindow:destroyChildren()

    local sections, rarityId, weight = parseSections(payload)
    local rarityColor = RARITY_COLORS[rarityId]

    local rows = {}
    local contentWidth = 0
    local contentHeight = 0

    for _, group in ipairs(SECTION_GROUPS) do
        local groupRows = {}
        for _, tag in ipairs(group) do
            for _, text in ipairs(sections[tag] or {}) do
                local color = SECTION_COLORS[tag]
                if (tag == 'N' or tag == 'R') and rarityColor then
                    color = rarityColor
                end

                local entry = createOutlinedLabel(text, color)
                contentWidth = math.max(contentWidth, entry.widget:getWidth())
                groupRows[#groupRows + 1] = entry
            end
        end

        if #groupRows > 0 then
            -- Only between groups, so no leading rule and none trailing.
            if #rows > 0 then
                rows[#rows + 1] = {
                    separator = g_ui.createWidget('ItemTooltipSeparator', tooltipWindow)
                }
                contentHeight = contentHeight + SEPARATOR_BLOCK
            end

            for _, entry in ipairs(groupRows) do
                rows[#rows + 1] = { entry = entry }
                contentHeight = contentHeight + entry.widget:getHeight()
            end
        end
    end

    -- Header: weight left, name between, sprite right.
    local weightEntry = weight and createOutlinedLabel(weight, WEIGHT_COLOR) or nil

    local nameText = (sections.N or {})[1]
    local nameEntry = nameText
        and createOutlinedLabel(nameText, rarityColor or SECTION_COLORS.N)
        or nil

    local sprite = nil
    if item then
        sprite = g_ui.createWidget('ItemTooltipSprite', tooltipWindow)
        -- A throwaway copy, not the live item: countOrSubType covers both
        -- stack size and subtype (fluid colour, rune charges), which
        -- setItemCount alone would get wrong for non-stackables.
        sprite:setItem(Item.create(item:getId(), item:getCountOrSubType()))
    end

    local leftWidth = weightEntry and weightEntry.widget:getWidth() or 0
    local nameWidth = nameEntry and nameEntry.widget:getWidth() or 0
    local rightWidth = sprite and SPRITE_SIZE or 0

    -- The sprite is NOT counted here. It's a corner ornament that overhangs
    -- the rows beneath it; letting its 32px drive the header height would
    -- reopen the gap between the name and the rarity line under it.
    local headerHeight = 0
    local headerWidth = leftWidth + nameWidth + rightWidth
    for _, present in ipairs({ leftWidth, nameWidth, rightWidth }) do
        if present > 0 then
            headerWidth = headerWidth + HEADER_GAP
        end
    end
    headerWidth = math.max(0, headerWidth - HEADER_GAP)

    if weightEntry then
        headerHeight = math.max(headerHeight, weightEntry.widget:getHeight())
    end
    if nameEntry then
        headerHeight = math.max(headerHeight, nameEntry.widget:getHeight())
    end

    -- Widened past what the text needs so lines aren't packed edge to edge.
    -- Applied before any placement maths so everything centres in the final
    -- width rather than in the measured one.
    contentWidth = math.floor(math.max(contentWidth, headerWidth) * WIDTH_SCALE)

    -- Header alone is still worth showing; nothing at all is not.
    if #rows == 0 and headerHeight == 0 then
        hideTooltip()
        return
    end

    -- The floor keeps the sprite from being clipped on a tooltip with only a
    -- line or two of body.
    local windowWidth = contentWidth + PADDING * 2
    local windowHeight = FRAME_INSET_Y + headerHeight + contentHeight + PADDING
    if sprite then
        windowHeight = math.max(windowHeight, FRAME_INSET_Y * 2 + SPRITE_SIZE)
    end

    tooltipWindow:setSize({ width = windowWidth, height = windowHeight })

    local y = FRAME_INSET_Y
    if weightEntry then
        placeOutlinedLabel(weightEntry, FRAME_INSET_X, y)
    end
    if nameEntry then
        -- Centred in the window, so it lines up with every body row. The
        -- weight and sprite are rarely the same width, so centring between
        -- them instead would sit the name off-centre by half their difference.
        -- Clamped only so a very long name can't run under either of them.
        local gapStart = weightEntry and (FRAME_INSET_X + leftWidth + HEADER_GAP) or PADDING
        local gapEnd = PADDING + contentWidth
        if sprite then
            gapEnd = windowWidth - FRAME_INSET_X - SPRITE_SIZE - HEADER_GAP
        end

        local centered = PADDING + math.floor((contentWidth - nameWidth) / 2)
        placeOutlinedLabel(nameEntry,
            math.max(gapStart, math.min(centered, gapEnd - nameWidth)), y)
    end
    if sprite then
        sprite:addAnchor(AnchorRight, 'parent', AnchorRight)
        sprite:addAnchor(AnchorTop, 'parent', AnchorTop)
        sprite:setMarginRight(FRAME_INSET_X)
        sprite:setMarginTop(FRAME_INSET_Y)
    end
    y = y + headerHeight

    for _, row in ipairs(rows) do
        if row.separator then
            local ruleWidth = math.floor(contentWidth * SEPARATOR_WIDTH_RATIO)
            row.separator:setWidth(ruleWidth)
            row.separator:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            row.separator:addAnchor(AnchorTop, 'parent', AnchorTop)
            row.separator:setMarginLeft(PADDING + math.floor((contentWidth - ruleWidth) / 2))
            row.separator:setMarginTop(y + SEPARATOR_GAP)
            y = y + SEPARATOR_BLOCK
        else
            placeOutlinedLabel(row.entry, PADDING, y, contentWidth)
            y = y + row.entry.widget:getHeight()
        end
    end

    tooltipWindow:show()
    tooltipWindow:raise()
    moveTooltip()
end

local function onTooltipData(_protocol, opcode, buffer)
    if opcode ~= TOOLTIP_OPCODE then
        return
    end

    local reqId, payload = buffer:match('^RES|(%d+)|(.*)$')
    if not reqId then
        return
    end

    local request = pending[tonumber(reqId)]
    pending[tonumber(reqId)] = nil
    if not request then
        return
    end

    -- The pointer may have moved on while the reply was in flight -- only
    -- show it if this is still the item under the cursor, otherwise a stale
    -- reply would describe the wrong slot.
    local widget = request.widget
    if not widget or widget:isDestroyed() or widget ~= hoveredWidget then
        return
    end

    if payload == '' then
        hideTooltip()
        return
    end

    renderTooltip(payload, widget:getItem())
end

-- Exposed so other windows paint rarity the same colour this tooltip does,
-- rather than keeping a second copy of the palette that can drift from it.
function getRarityColor(rarityId)
    return RARITY_COLORS[rarityId]
end

function requestTooltip(widget)
    hoveredWidget = widget
    if not widget or widget:isDestroyed() or widget:isVirtual() then
        return
    end

    local item = widget:getItem()
    if not item then
        return
    end

    local pos = item:getPosition()
    if not pos then
        return
    end

    local source, a, b = describeTarget(pos)
    if not source then
        -- Ground items aren't addressable by the server resolver; they still
        -- have right-click Look.
        return
    end

    local protocolGame = g_game.getProtocolGame()
    if not protocolGame then
        return
    end

    nextRequestId = nextRequestId + 1
    pending[nextRequestId] = { widget = widget, key = positionKey(pos) }
    protocolGame:sendExtendedOpcode(TOOLTIP_OPCODE,
        string.format('REQ|%d|%s|%d|%d', nextRequestId, source, a, b))
end

function clearHover(widget)
    if hoveredWidget == widget then
        hoveredWidget = nil
        hideTooltip()
    end
end

-- Everything below is built on FIRST USE, not at module load. An earlier
-- version did it in init() and the client froze during startup with an empty
-- log -- module load runs before the log is flushed, so anything slow or
-- fatal there is both invisible and unrecoverable. Doing it lazily means a
-- failure costs one missing tooltip and a log line instead of the client.
-- Runtime TTF stroking is DISABLED.
--
-- Assigns the forward-declared local above.
function ensureWidget()
    if tooltipWindow and not tooltipWindow:isDestroyed() then
        return true
    end

    local ok, err = pcall(function()
        -- The .otui defines styles only (no root widget to display), so it
        -- must be imported before createWidget can resolve them.
        g_ui.importStyle('itemtooltip')
        tooltipWindow = g_ui.createWidget('ItemTooltipWindow', rootWidget)
        tooltipWindow:hide()
        connect(rootWidget, { onMouseMove = moveTooltip })
    end)

    if not ok then
        g_logger.error('[ItemTooltip] failed to build tooltip widget: ' .. tostring(err))
        tooltipWindow = nil
        return false
    end

    return true
end

function init()
    ProtocolGame.registerExtendedOpcode(TOOLTIP_OPCODE, onTooltipData)
    connect(g_game, { onGameEnd = hideTooltip })
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(TOOLTIP_OPCODE)
    disconnect(g_game, { onGameEnd = hideTooltip })

    -- onMouseMove is only connected once the widget is built (lazily, on
    -- first tooltip), so only disconnect it if that actually happened.
    if tooltipWindow then
        disconnect(rootWidget, { onMouseMove = moveTooltip })
        if not tooltipWindow:isDestroyed() then
            tooltipWindow:destroy()
        end
        tooltipWindow = nil
    end
    pending = {}
    hoveredWidget = nil
end
