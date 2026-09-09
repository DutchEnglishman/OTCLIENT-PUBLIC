-- Shows the server-wide boosts that are currently running as a small row of
-- badges at the bottom-left of the map, directly above the chat window. The
-- server pushes the list on login, whenever a boost starts or ends, and on its
-- own tick; the countdown between those pushes runs locally so the numbers
-- move every second rather than in ten-second jumps.

local GLOBAL_BOOSTS_OPCODE = 202

local ICON_SIZE = 20
local ICON_SPACING = 4

local boostsBar = nil
local entries = {}
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

local function updateTimers()
    local now = os.time()

    for _, entry in pairs(entries) do
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

    return true
end

local function clearIcons()
    for _, entry in pairs(entries) do
        entry.icon:destroy()
    end
    entries = {}
end

local function rebuild(boosts)
    clearIcons()
    if not boostsBar then
        return
    end

    local now = os.time()
    local count = 0
    local previousId = nil

    for _, boost in ipairs(boosts) do
        local icon = g_ui.createWidget("BoostIcon", boostsBar)
        -- Id before the anchor: the next badge anchors to this one by id.
        local id = "boost" .. count
        icon:setId(id)
        icon:setImageSource("/game_globalboosts/images/hud_" .. boost.icon)
        icon:setTooltip(boost.name .. "\n" .. (boost.description or ""))

        -- Anchored one after another rather than laid out by a horizontalBox,
        -- which resizes its children to the container and left these stretched
        -- and squeezed together.
        icon:addAnchor(AnchorTop, 'parent', AnchorTop)
        if previousId then
            icon:addAnchor(AnchorLeft, previousId, AnchorRight)
            icon:setMarginLeft(ICON_SPACING)
        else
            icon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        end

        entries[boost.key] = {
            icon = icon,
            -- The label lives inside the dark strip, so it is a grandchild.
            timer = icon:recursiveGetChildById("timer"),
            expiresAt = now + (tonumber(boost.remaining) or 0),
        }

        previousId = id
        count = count + 1
    end

    boostsBar:setWidth(math.max(1, count * ICON_SIZE + math.max(0, count - 1) * ICON_SPACING))
    boostsBar:setHeight(ICON_SIZE)
    boostsBar:setVisible(count > 0)
    updateTimers()
end

function onExtendedOpcode(protocol, code, buffer)
    local status, data = pcall(function() return json.decode(buffer) end)
    if not status or type(data) ~= "table" then
        return false
    end

    local boosts = {}
    -- An empty list encodes as a JSON object rather than an array, so it
    -- arrives as a table with no numeric keys and ipairs simply yields nothing.
    if type(data.boosts) == "table" then
        for _, b in ipairs(data.boosts) do
            boosts[#boosts + 1] = b
        end
    end

    rebuild(boosts)
    return true
end

function create()
    if boostsBar then
        return
    end

    local mapPanel = modules.game_interface.getMapPanel()
    if not mapPanel then
        return
    end

    boostsBar = g_ui.loadUI("globalboosts", mapPanel)
    -- The map panel's bottom edge is the splitter above the chat, so its
    -- bottom-left corner is the strip of screen directly above the chat window.
    boostsBar:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    boostsBar:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    boostsBar:setMarginLeft(6)
    boostsBar:setMarginBottom(6)
    boostsBar:hide()

    if not tickEvent then
        tickEvent = cycleEvent(updateTimers, 1000)
    end
end

function destroy()
    if tickEvent then
        removeEvent(tickEvent)
        tickEvent = nil
    end
    clearIcons()
    if boostsBar then
        boostsBar:destroy()
        boostsBar = nil
    end
end

function init()
    connect(g_game, {onGameStart = create, onGameEnd = destroy})
    ProtocolGame.registerExtendedOpcode(GLOBAL_BOOSTS_OPCODE, onExtendedOpcode)

    if g_game.isOnline() then
        create()
    end
end

function terminate()
    disconnect(g_game, {onGameStart = create, onGameEnd = destroy})
    ProtocolGame.unregisterExtendedOpcode(GLOBAL_BOOSTS_OPCODE, onExtendedOpcode)
    destroy()
end
