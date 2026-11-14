-- The depot notice boards (OTSERV data/scripts/notice_board/): using a board sends
-- what is going on as JSON on this opcode, and the window pins it up as paper notes.
-- The server only sends the board's own sections -- a Rookgaard board carries no
-- bounties -- so a section that did not arrive is not drawn.
--
-- Layout: every note is placed at an exact offset and measured as it is filled, top
-- to bottom, because a note's height is only known once its wrapped text is. Body
-- labels get their width before their text (NbText in the .otui), which makes the
-- wrap, and so the height, known at once.
local NOTICE_BOARD_OPCODE = 103

local BOARD_PAD_X, BOARD_PAD_TOP, BOARD_PAD_BOTTOM = 14, 18, 18
local SIDE_W, COLUMN_GAP, NOTE_GAP = 200, 18, 16
local NOTE_PAD = 12
local POSTERS_PER_ROW, POSTER_GAP_X, POSTER_GAP_Y = 5, 14, 18

local TILTS = {-1.1, 0.8, -0.5, 1.2, -0.9, 0.6, -1.3, 1.0, -0.4, 0.9, -0.7, 1.1, -1.0, 0.5}
local PAPERS = {'paper_a', 'paper_b', 'paper_c'}

local TIER_COLORS = {
    veryhigh = '#9a1a06', high = '#9a4a06', medium1 = '#4a5a10', medium2 = '#4a5a10',
    low1 = '#5a4630', low2 = '#5a4630', low3 = '#5a4630', rook = '#5a4630',
    variant = '#5a1a6a', boss = '#111111',
}

local window = nil
local noteCount = 0

local function formatLeft(seconds)
    local minutes = math.max(0, math.ceil((tonumber(seconds) or 0) / 60))
    if minutes >= 60 then
        return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
    end
    return string.format("%dm", minutes)
end

-- An empty Lua table encodes as a JSON object, which ipairs simply skips.
local function list(value)
    local items = {}
    if type(value) == "table" then
        for _, item in ipairs(value) do
            items[#items + 1] = item
        end
    end
    return items
end

local function place(widget, x, y)
    widget:setMarginLeft(x)
    widget:setMarginTop(y)
    return widget
end

local function make(style, parent, x, y)
    return place(g_ui.createWidget(style, parent), x, y)
end

-- A wrapped label of a fixed width; returns it and the height it took.
local function text(parent, style, value, x, y, width, align)
    local label = make(style, parent, x, y)
    label:setSize({width = width, height = 1})
    if align then
        label:setTextAlign(align)
    end
    label:setText(value)
    return label, label:getHeight()
end

local function outfitOf(look)
    if type(look) ~= "table" or (tonumber(look.type) or 0) <= 0 then
        return nil
    end
    return {
        type = tonumber(look.type), head = tonumber(look.head) or 0, body = tonumber(look.body) or 0,
        legs = tonumber(look.legs) or 0, feet = tonumber(look.feet) or 0, addons = tonumber(look.addons) or 0,
    }
end

local function portrait(parent, x, y, look)
    local frame = make('NbPortrait', parent, x, y)
    local outfit = outfitOf(look)
    if outfit then
        frame:getChildById('creature'):setOutfit(outfit)
    end
    return frame
end

-- A note: the tilted paper on the canvas, and over it an untilted panel of the same
-- size that holds the pin and every row. Only the paper turns because a rotated
-- widget turns its text with it, and the engine resamples the glyphs, which blurs
-- and clips them. Rows are added by moving `y` down; finish() gives the note its height.
local function newNote(canvas, x, y, width)
    noteCount = noteCount + 1
    local back = make('NbNote', canvas, x, y)
    back:setImageSource('/game_noticeboard/images/' .. PAPERS[(noteCount - 1) % #PAPERS + 1])
    back:setRotation(TILTS[(noteCount - 1) % #TILTS + 1])
    local paper = make('NbPlaced', canvas, x, y)
    make('NbPin', paper, math.floor(width / 2) - 7, -9)
    local note = {paper = paper, width = width, inner = width - 2 * NOTE_PAD, y = NOTE_PAD}
    function note.finish()
        local height = note.y + NOTE_PAD
        back:setSize({width = width, height = height})
        paper:setSize({width = width, height = height})
        return height
    end
    return note
end

local function title(note, value)
    local label = make('NbTitle', note.paper, NOTE_PAD, note.y)
    label:setSize({width = note.inner, height = 20})
    label:setText(value)
    make('NbRule', note.paper, NOTE_PAD, note.y + 20):setWidth(note.inner)
    note.y = note.y + 27
end

local function emptyLine(note, value)
    local _, height = text(note.paper, 'NbText', value, NOTE_PAD, note.y, note.inner, AlignCenter)
    note.y = note.y + height
end

local function drawRaid(canvas, x, y, width, raid)
    local note = newNote(canvas, x, y, width)
    title(note, "Raid")
    local name = make('NbBig', note.paper, NOTE_PAD, note.y)
    name:setSize({width = note.inner, height = 20})
    name:setText(tostring(raid.name))
    note.y = note.y + 20
    local _, height = text(note.paper, 'NbText', "is ravaging the land", NOTE_PAD, note.y, note.inner, AlignCenter)
    note.y = note.y + height
    return note.finish()
end

local function drawWeather(canvas, x, y, width, weather)
    local note = newNote(canvas, x, y, width)
    title(note, "Weather")
    if #weather == 0 then
        emptyLine(note, "The skies are calm.")
        return note.finish()
    end
    local textX, textW = NOTE_PAD + 26, note.inner - 26
    for i, event in ipairs(weather) do
        if i > 1 then
            note.y = note.y + 6
        end
        local top = note.y
        local icon = make('NbIcon', note.paper, NOTE_PAD, top)
        if event.icon then
            icon:setImageSource("/game_globalboosts/images/hud_" .. tostring(event.icon))
        end
        local time = make('NbTime', note.paper, textX + textW - 50, top)
        time:setWidth(50)
        time:setText(formatLeft(event.remaining))
        local _, height = text(note.paper, 'NbBold', tostring(event.name), textX, top, textW - 52)
        local rowY = top + height
        local lines = {string.format("%s, %s", tostring(event.intensity), tostring(event.zone))}
        for _, line in ipairs(list(event.lines)) do
            lines[#lines + 1] = tostring(line)
        end
        for _, line in ipairs(lines) do
            local _, lineHeight = text(note.paper, 'NbText', line, textX, rowY, textW)
            rowY = rowY + lineHeight
        end
        note.y = math.max(rowY, top + 20)
    end
    return note.finish()
end

local function drawBoosts(canvas, x, y, width, boosts)
    local note = newNote(canvas, x, y, width)
    title(note, "Server Boosts")
    if #boosts == 0 then
        emptyLine(note, "None running.\nBought in the store, they help everyone online.")
        return note.finish()
    end
    for _, boost in ipairs(boosts) do
        local row = make('NbHover', note.paper, NOTE_PAD, note.y)
        row:setSize({width = note.inner, height = 22})
        if boost.description and boost.description ~= "" then
            row:setTooltip(tostring(boost.description))
        end
        local icon = make('NbIcon', row, 0, 1)
        if boost.icon then
            icon:setImageSource("/game_globalboosts/images/hud_" .. tostring(boost.icon))
        end
        local name = make('NbLine', row, 25, 4)
        name:setWidth(note.inner - 25 - 52)
        name:setText(tostring(boost.name))
        local time = make('NbTime', row, note.inner - 50, 4)
        time:setWidth(50)
        time:setText(formatLeft(boost.remaining))
        note.y = note.y + 22
    end
    return note.finish()
end

local function bonusLines(creature)
    local lines = {}
    local function add(value, word)
        value = tonumber(value) or 0
        if value > 0 then
            lines[#lines + 1] = string.format("+%d%% %s", value, word)
        end
    end
    add(creature.exp, "exp")
    add(creature.loot, "loot")
    add(creature.variant, "variants")
    add(creature.spawn, "spawn")
    return table.concat(lines, "\n")
end

local function drawBoosted(canvas, x, y, width, boosted)
    local note = newNote(canvas, x, y, width)
    title(note, "Boosted Creatures")
    local creatures = list(boosted and boosted.creatures)
    if #creatures == 0 then
        -- A server from before the portraits sends only the text lines.
        local picks = list(boosted and boosted.picks)
        if #picks == 0 then
            emptyLine(note, "Nothing is boosted right now.")
        end
        for _, pick in ipairs(picks) do
            local _, height = text(note.paper, 'NbText', tostring(pick), NOTE_PAD, note.y, note.inner)
            note.y = note.y + height + 2
        end
    else
        local cellW = math.floor(note.inner / 3)
        local rowTop, rowBottom = note.y, note.y
        for i, creature in ipairs(creatures) do
            local col = (i - 1) % 3
            if col == 0 and i > 1 then
                rowTop = rowBottom + 8
            end
            local cx = NOTE_PAD + col * cellW
            portrait(note.paper, cx + math.floor((cellW - 66) / 2), rowTop, creature.outfit)
            local cy = rowTop + 68
            local _, h1 = text(note.paper, 'NbBold', tostring(creature.name), cx, cy, cellW, AlignCenter)
            cy = cy + h1
            local tier, h2 = text(note.paper, 'NbBold', tostring(creature.tier), cx, cy, cellW, AlignCenter)
            tier:setColor(TIER_COLORS[creature.slot] or '#5a4630')
            cy = cy + h2
            local bonuses = bonusLines(creature)
            if bonuses ~= "" then
                local _, h3 = text(note.paper, 'NbText', bonuses, cx, cy, cellW, AlignCenter)
                cy = cy + h3
            end
            rowBottom = math.max(rowBottom, cy)
        end
        note.y = rowBottom
    end
    note.y = note.y + 8
    local _, height = text(note.paper, 'NbText', "Next rotation in " .. formatLeft(boosted and boosted.remaining),
        NOTE_PAD, note.y, note.inner, AlignCenter)
    note.y = note.y + height
    return note.finish()
end

local function drawPoster(canvas, x, y, width, rank, bounty)
    local note = newNote(canvas, x, y, width)
    local wanted = make('NbWanted', note.paper, NOTE_PAD, note.y)
    wanted:setSize({width = note.inner, height = 20})
    wanted:setText("WANTED")
    if rank == 1 then
        wanted:setColor('#9a0a00')
    end
    note.y = note.y + 22
    portrait(note.paper, NOTE_PAD + math.floor((note.inner - 66) / 2), note.y, bounty.outfit)
    note.y = note.y + 70
    local _, h1 = text(note.paper, 'NbBold', tostring(bounty.name), NOTE_PAD, note.y, note.inner, AlignCenter)
    note.y = note.y + h1
    local _, h2 = text(note.paper, 'NbText', string.format("level %d", tonumber(bounty.level) or 0), NOTE_PAD, note.y,
        note.inner, AlignCenter)
    note.y = note.y + h2
    local reward, h3 = text(note.paper, 'NbBold', string.format("%d crystal coins", tonumber(bounty.crystals) or 0),
        NOTE_PAD, note.y, note.inner, AlignCenter)
    reward:setColor('#1d4a70')
    note.y = note.y + h3
    return note.finish()
end

local function drawBounties(canvas, y, usable, bounties)
    local head = make('NbBoardHead', canvas, BOARD_PAD_X, y)
    head:setSize({width = usable, height = 28})
    head:setText("W A N T E D")
    y = y + 40
    if #bounties == 0 then
        local empty = make('NbLine', canvas, BOARD_PAD_X, y)
        empty:setSize({width = usable, height = 14})
        empty:setTextAlign(AlignCenter)
        empty:setColor('#d9c8a6')
        empty:setText("Nobody has a price on their head.")
        return y + 14
    end
    local posterW = math.floor((usable - (POSTERS_PER_ROW - 1) * POSTER_GAP_X) / POSTERS_PER_ROW)
    local rowBottom = y
    for i, bounty in ipairs(bounties) do
        local col = (i - 1) % POSTERS_PER_ROW
        if col == 0 and i > 1 then
            y = rowBottom + POSTER_GAP_Y
        end
        local height = drawPoster(canvas, BOARD_PAD_X + col * (posterW + POSTER_GAP_X), y, posterW, i, bounty)
        rowBottom = math.max(rowBottom, y + height)
    end
    return rowBottom
end

local function draw(data)
    local board = window:getChildById('board')
    board:destroyChildren()
    noteCount = 0

    local canvasW = board:getPaddingRect().width
    if canvasW <= 0 then
        canvasW = 852
    end
    local usable = canvasW - 2 * BOARD_PAD_X
    local canvas = g_ui.createWidget('NbCanvas', board)
    canvas:setWidth(canvasW)

    window:setText(data.board == "rook" and tr('Rookgaard Notice Board') or tr('Notice Board'))

    local top = BOARD_PAD_TOP
    local middleX = BOARD_PAD_X + SIDE_W + COLUMN_GAP
    local middleW = usable - 2 * (SIDE_W + COLUMN_GAP)
    local rightX = middleX + middleW + COLUMN_GAP

    local leftY = top
    if type(data.raid) == "table" and data.raid.name then
        leftY = leftY + drawRaid(canvas, BOARD_PAD_X, leftY, SIDE_W, data.raid) + NOTE_GAP
    end
    leftY = leftY + drawWeather(canvas, BOARD_PAD_X, leftY, SIDE_W, list(data.weather))
    local middleY = top + drawBoosted(canvas, middleX, top, middleW, data.boosted)
    local rightY = top + drawBoosts(canvas, rightX, top, SIDE_W, list(data.boosts))

    local bottom = math.max(leftY, middleY, rightY)
    if data.bounties ~= nil then
        bottom = drawBounties(canvas, bottom + 22, usable, list(data.bounties))
    end
    canvas:setHeight(bottom + BOARD_PAD_BOTTOM)

    addEvent(function()
        if window and not board:isDestroyed() then
            board:updateScrollBars()
            window:getChildById('boardScroll'):setValue(0)
        end
    end)
end

local function onNoticeBoard(protocol, opcode, buffer)
    local ok, data = pcall(json.decode, buffer)
    if not ok or type(data) ~= "table" then
        return
    end
    show()
    draw(data)
end

function show()
    if window then
        window:show()
        window:raise()
        window:focus()
    end
end

function hide()
    if window then
        window:hide()
    end
end

function init()
    g_ui.importStyle('noticeboard')
    window = g_ui.createWidget('NoticeBoardWindow', modules.game_interface.getRootPanel())
    window:hide()
    ProtocolGame.registerExtendedOpcode(NOTICE_BOARD_OPCODE, onNoticeBoard)
    connect(g_game, {onGameEnd = hide})
end

function terminate()
    disconnect(g_game, {onGameEnd = hide})
    ProtocolGame.unregisterExtendedOpcode(NOTICE_BOARD_OPCODE)
    if window then
        window:destroy()
        window = nil
    end
end
