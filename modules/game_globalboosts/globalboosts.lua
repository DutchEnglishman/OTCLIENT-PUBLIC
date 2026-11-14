-- Shows the server-wide boosts that are currently running as a small row of
-- badges on the right of the spell cooldown strip above the chat, ending over
-- the chat's "Open new channel" button and growing leftwards from it. The
-- server pushes the list on login, whenever a boost starts or ends, and on its
-- own tick; the countdown between those pushes runs locally so the numbers
-- move every second rather than in ten-second jumps.
--
-- The regional weather running anywhere (OTSERV data/world_events/,
-- WorldEvents.sendBadges) uses the same badges, one per event, but sits after
-- the spell tiles in game_cooldown's weatherPanel, behind a small separator.

local GLOBAL_BOOSTS_OPCODE = 202
local WEATHER_OPCODE = 102

local ICON_SIZE = 20
local ICON_SPACING = 4

local boostsBar = nil
local entries = {}
local weatherEntries = {}
-- The last weather list, kept until the strip exists: a push can land before
-- onGameStart has built it.
local weatherList = {}
local tickEvent = nil

local function formatRemaining(seconds)
    if seconds >= 3600 then
        return string.format("%dh", math.ceil(seconds / 3600))
    end
    if seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    end
    return string.format("%ds", seconds)
end

local function formatLeft(seconds)
    local minutes = math.ceil(seconds / 60)
    if minutes >= 60 then
        return string.format("%dh %d min left", math.floor(minutes / 60), minutes % 60)
    end
    return string.format("%d min left", minutes)
end

local function updateTimers()
    local now = os.time()

    for _, list in ipairs({entries, weatherEntries}) do
        for _, entry in pairs(list) do
            -- An absolute expiry is held rather than a countdown, so a late or
            -- dropped push cannot make the clock drift.
            local left = entry.expiresAt - now
            if left > 0 then
                entry.timer:setText(formatRemaining(left))
            else
                -- The server's expiry push is authoritative; this only stops a
                -- stale number showing in the second before it lands.
                entry.timer:setText("")
            end
        end
    end

    return true
end

local function clearIcons(list)
    for _, entry in pairs(list) do
        entry.icon:destroy()
    end
end

-- Lays badges into parent left to right and answers how many. Anchored one after
-- another rather than laid out by a horizontalBox, which resizes its children to
-- the container and left these stretched and squeezed together.
local function placeBadges(parent, badges, idPrefix, tooltipOf, into)
    local now = os.time()
    local count = 0
    local previousId = nil

    for _, badge in ipairs(badges) do
        -- A badge with no key, icon or name is not drawable, and the key is a
        -- table index: a nil one would throw rather than skip the badge.
        if type(badge) == "table" and badge.key ~= nil and badge.icon ~= nil and badge.name ~= nil then
            local icon = g_ui.createWidget("BoostIcon", parent)
            -- Id before the anchor: the next badge anchors to this one by id.
            local id = idPrefix .. count
            icon:setId(id)
            icon:setImageSource("/game_globalboosts/images/hud_" .. badge.icon)
            icon:setTooltip(tooltipOf(badge))

            icon:addAnchor(AnchorTop, 'parent', AnchorTop)
            if previousId then
                icon:addAnchor(AnchorLeft, previousId, AnchorRight)
                icon:setMarginLeft(ICON_SPACING)
            else
                icon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            end

            into[badge.key] = {
                icon = icon,
                -- The label lives inside the dark strip, so it is a grandchild.
                timer = icon:recursiveGetChildById("timer"),
                expiresAt = now + (tonumber(badge.remaining) or 0),
            }

            previousId = id
            count = count + 1
        end
    end
    return count
end

local function widthOf(count)
    return math.max(0, count * ICON_SIZE + math.max(0, count - 1) * ICON_SPACING)
end

local function boostTooltip(boost)
    return boost.name .. "\n" .. (boost.description or "")
end

-- "Sandstorm (Severe)", the zone and time left, then one line per boosted group.
local function weatherTooltip(weather)
    local lines = {string.format("%s (%s)", weather.name, weather.intensity or ""),
        string.format("%s, %s", weather.zone or "", formatLeft(tonumber(weather.remaining) or 0))}
    if type(weather.lines) == "table" then
        for _, line in ipairs(weather.lines) do
            lines[#lines + 1] = tostring(line)
        end
    end
    return table.concat(lines, "\n")
end

local function rebuild(boosts)
    clearIcons(entries)
    entries = {}
    if not boostsBar then
        return
    end

    local count = placeBadges(boostsBar, boosts, "boost", boostTooltip, entries)
    boostsBar:setWidth(math.max(1, widthOf(count)))
    boostsBar:setHeight(ICON_SIZE)
    boostsBar:setVisible(count > 0)
    modules.game_cooldown.setBoostsShown(count > 0)
    updateTimers()
end

local function rebuildWeather()
    clearIcons(weatherEntries)
    weatherEntries = {}
    local panel = modules.game_cooldown.weatherPanel
    if not boostsBar or not panel then
        return
    end

    local count = placeBadges(panel, weatherList, "weather", weatherTooltip, weatherEntries)
    panel:setWidth(widthOf(count))
    modules.game_cooldown.setWeatherShown(count > 0)
    updateTimers()
end

local function getChannelsButton()
    local console = modules.game_console.consolePanel
    return console and console:getChildById('channelsButton')
end

-- The button lives in the console panel, not in the strip, so it cannot be an
-- anchor target; its right edge is copied over as a margin whenever either moves.
local function alignToChannelsButton()
    local button = getChannelsButton()
    if not boostsBar or not button then
        return
    end
    local strip = boostsBar:getParent():getRect()
    local rect = button:getRect()
    boostsBar:setMarginRight(math.max(0, (strip.x + strip.width) - (rect.x + rect.width)))
end

-- An empty list encodes as a JSON object rather than an array, so it arrives as
-- a table with no numeric keys and ipairs simply yields nothing.
local function decodeList(buffer, field)
    local status, data = pcall(function() return json.decode(buffer) end)
    if not status or type(data) ~= "table" then
        return nil
    end
    local list = {}
    if type(data[field]) == "table" then
        for _, item in ipairs(data[field]) do
            list[#list + 1] = item
        end
    end
    return list
end

function onExtendedOpcode(protocol, code, buffer)
    local boosts = decodeList(buffer, "boosts")
    if not boosts then
        return false
    end
    rebuild(boosts)
    return true
end

function onWeatherOpcode(protocol, code, buffer)
    local weather = decodeList(buffer, "weather")
    if not weather then
        return false
    end
    weatherList = weather
    rebuildWeather()
    return true
end

function create()
    if boostsBar then
        return
    end

    local strip = modules.game_cooldown.cooldownWindow
    if not strip then
        return
    end

    boostsBar = g_ui.loadUI("globalboosts", strip)
    boostsBar:addAnchor(AnchorTop, 'parent', AnchorTop)
    boostsBar:addAnchor(AnchorRight, 'parent', AnchorRight)
    boostsBar:setMarginTop(2)
    boostsBar:hide()

    connect(strip, {onGeometryChange = alignToChannelsButton})
    local button = getChannelsButton()
    if button then
        connect(button, {onGeometryChange = alignToChannelsButton})
    end
    alignToChannelsButton()

    -- The BoostIcon style is loaded with the bar, so a weather list that came
    -- first is drawn now.
    rebuildWeather()

    if not tickEvent then
        tickEvent = cycleEvent(updateTimers, 1000)
    end
end

function destroy()
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
    clearIcons(entries)
    entries = {}
    clearIcons(weatherEntries)
    weatherEntries = {}
    weatherList = {}
    modules.game_cooldown.setWeatherShown(false)
    if boostsBar then
        local strip = boostsBar:getParent()
        disconnect(strip, {onGeometryChange = alignToChannelsButton})
        local button = getChannelsButton()
        if button then
            disconnect(button, {onGeometryChange = alignToChannelsButton})
        end
        boostsBar:destroy()
        boostsBar = nil
        modules.game_cooldown.setBoostsShown(false)
    end
end

function init()
    connect(g_game, {onGameStart = create, onGameEnd = destroy})
    ProtocolGame.registerExtendedOpcode(GLOBAL_BOOSTS_OPCODE, onExtendedOpcode)
    ProtocolGame.registerExtendedOpcode(WEATHER_OPCODE, onWeatherOpcode)

    if g_game.isOnline() then
        create()
    end
end

function terminate()
    disconnect(g_game, {onGameStart = create, onGameEnd = destroy})
    ProtocolGame.unregisterExtendedOpcode(GLOBAL_BOOSTS_OPCODE, onExtendedOpcode)
    ProtocolGame.unregisterExtendedOpcode(WEATHER_OPCODE, onWeatherOpcode)
    destroy()
end
