-- The depot notice boards (OTSERV data/scripts/notice_board/): using a board sends
-- what is going on as JSON on this opcode, and the window lists it, section by
-- section. The server only sends the board's own sections -- a Rookgaard board
-- carries no bounties -- so a section that did not arrive is not drawn.
local NOTICE_BOARD_OPCODE = 103

local window = nil

local function formatLeft(seconds)
    local minutes = math.max(0, math.ceil((tonumber(seconds) or 0) / 60))
    if minutes >= 60 then
        return string.format("%dh %d min", math.floor(minutes / 60), minutes % 60)
    end
    return string.format("%d min", minutes)
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

local function header(content, text)
    g_ui.createWidget('NoticeBoardHeader', content):setText(text)
end

local function row(content, text)
    g_ui.createWidget('NoticeBoardRow', content):setText(text)
end

local function empty(content, text)
    g_ui.createWidget('NoticeBoardEmpty', content):setText(text)
end

local function drawWeather(content, weather)
    header(content, "Weather")
    if #weather == 0 then
        empty(content, "The skies are calm.")
        return
    end
    for _, event in ipairs(weather) do
        local lines = {string.format("%s (%s) over %s, %s left", tostring(event.name), tostring(event.intensity),
            tostring(event.zone), formatLeft(event.remaining))}
        for _, line in ipairs(list(event.lines)) do
            lines[#lines + 1] = tostring(line)
        end
        local widget = g_ui.createWidget('NoticeBoardIconRow', content)
        widget:setText(table.concat(lines, "\n"))
        if event.icon then
            widget:getChildById('icon'):setImageSource("/game_globalboosts/images/hud_" .. tostring(event.icon))
        end
    end
end

local function drawBoosted(content, boosted)
    local picks = list(boosted and boosted.picks)
    header(content, string.format("Boosted creatures (next rotation in %s)", formatLeft(boosted and boosted.remaining)))
    if #picks == 0 then
        empty(content, "Nothing is boosted right now.")
        return
    end
    for _, pick in ipairs(picks) do
        row(content, tostring(pick))
    end
end

local function drawBoosts(content, boosts)
    header(content, "Server-wide boosts")
    if #boosts == 0 then
        empty(content, "None running. They are bought in the store and help everyone online.")
        return
    end
    for _, boost in ipairs(boosts) do
        local text = string.format("%s, %s left", tostring(boost.name), formatLeft(boost.remaining))
        if boost.description and boost.description ~= "" then
            text = text .. "\n" .. tostring(boost.description)
        end
        row(content, text)
    end
end

local function drawRaid(content, raid)
    header(content, "Raid")
    if type(raid) ~= "table" or not raid.name then
        empty(content, "No raid is underway.")
        return
    end
    row(content, string.format("%s is underway right now.", tostring(raid.name)))
end

local function drawBounties(content, bounties)
    header(content, "Open bounties")
    if #bounties == 0 then
        empty(content, "Nobody has a price on their head.")
        return
    end
    for i, bounty in ipairs(bounties) do
        row(content, string.format("%d. %s (level %d): %d crystals", i, tostring(bounty.name),
            tonumber(bounty.level) or 0, tonumber(bounty.crystals) or 0))
    end
end

local function draw(data)
    local content = window:getChildById('content')
    content:destroyChildren()

    window:setText(data.board == "rook" and tr('Rookgaard Notice Board') or tr('Notice Board'))
    drawWeather(content, list(data.weather))
    drawBoosted(content, data.boosted)
    drawBoosts(content, list(data.boosts))
    drawRaid(content, data.raid)
    if data.bounties ~= nil then
        drawBounties(content, list(data.bounties))
    end
end

local function onNoticeBoard(protocol, opcode, buffer)
    local ok, data = pcall(json.decode, buffer)
    if not ok or type(data) ~= "table" then
        return
    end
    draw(data)
    show()
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
