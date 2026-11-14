-- The boosted creatures window. The server owns the set (OTSERV data/boosted/) and sends
-- all of it over extended opcode 101 at login, on reconnect, every time it changes, and
-- when this window asks with "get":
--   {secondsLeft, picks = {{slot, label, name, outfit, exp, loot, variant, spawn}, ...}}
-- in parts when long (JsonChunks).

BOOSTED_OPCODE = 101

local window = nil
local toggleButton = nil
local protocol = nil
local countdownEvent = nil

local picks = {}
local endsAt = nil

local BONUSES = {
    {'exp', 'experience'}, {'loot', 'loot'}, {'variant', 'Tainted & Corrupted'}, {'spawn', 'monsters'},
}

local function bonusText(pick)
    local parts = {}
    for _, bonus in ipairs(BONUSES) do
        local value = tonumber(pick[bonus[1]]) or 0
        if value > 0 then
            parts[#parts + 1] = string.format('+%d%% %s', value, bonus[2])
        end
    end
    return table.concat(parts, ', ')
end

local function refreshCountdown()
    if not window then
        return
    end
    local label = window:getChildById('countdown')
    if not endsAt then
        label:setText('')
        return
    end
    local left = math.max(0, math.floor(endsAt - g_clock.seconds()))
    label:setText(string.format('Next change in %dh %02dm %02ds', math.floor(left / 3600),
        math.floor(left % 3600 / 60), left % 60))
end

local function refreshRows()
    local rows = window:getChildById('rows')
    rows:destroyChildren()
    for _, pick in ipairs(picks) do
        local row = g_ui.createWidget('BoostedRow', rows)
        local outfit = type(pick.outfit) == 'table' and pick.outfit or {}
        if (tonumber(outfit.type) or 0) > 0 then
            row:getChildById('creature'):setOutfit({
                type = tonumber(outfit.type), head = tonumber(outfit.head) or 0, body = tonumber(outfit.body) or 0,
                legs = tonumber(outfit.legs) or 0, feet = tonumber(outfit.feet) or 0, addons = tonumber(outfit.addons) or 0,
            })
        end
        row:getChildById('tier'):setText(pick.label or '')
        row:getChildById('name'):setText(pick.name or '?')
        row:getChildById('bonuses'):setText(bonusText(pick))
    end
end

local function startCountdown()
    if countdownEvent then
        removeEvent(countdownEvent)
    end
    countdownEvent = cycleEvent(refreshCountdown, 1000)
    refreshCountdown()
end

local function stopCountdown()
    if countdownEvent then
        removeEvent(countdownEvent)
        countdownEvent = nil
    end
end

function show()
    if not window then
        return
    end
    if protocol then
        protocol:sendExtendedOpcode(BOOSTED_OPCODE, 'get')
    end
    refreshRows()
    window:show()
    window:raise()
    window:focus()
    startCountdown()
    if toggleButton then
        toggleButton:setOn(true)
    end
end

function hide()
    if window then
        window:hide()
    end
    stopCountdown()
    if toggleButton then
        toggleButton:setOn(false)
    end
end

function toggle()
    if window and window:isVisible() then
        hide()
    else
        show()
    end
end

local function onOpcode(proto, code, buffer)
    protocol = proto
    local ok, payload = pcall(json.decode, buffer)
    if not ok or type(payload) ~= 'table' then
        return
    end
    payload = JsonChunks.receive(BOOSTED_OPCODE, payload, 'picks')
    if not payload then
        return
    end

    picks = type(payload.picks) == 'table' and payload.picks or {}
    endsAt = g_clock.seconds() + (tonumber(payload.secondsLeft) or 0)
    if window:isVisible() then
        refreshRows()
        refreshCountdown()
    end
end

local function onGameStart()
    protocol = g_game.getProtocolGame()
    if not toggleButton then
        toggleButton = modules.game_mainpanel.addToggleButton('boostedButton', tr('Boosted Creatures'),
            '/images/options/button_prey', toggle)
    end
end

local function onGameEnd()
    hide()
    picks = {}
    endsAt = nil
    protocol = nil
end

function init()
    g_ui.importStyle('boosted')
    window = g_ui.createWidget('BoostedWindow', modules.game_interface.getRootPanel())
    window:hide()

    ProtocolGame.registerExtendedOpcode(BOOSTED_OPCODE, onOpcode)
    connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(BOOSTED_OPCODE)
    disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
    stopCountdown()
    if toggleButton then
        toggleButton:destroy()
        toggleButton = nil
    end
    if window then
        window:destroy()
        window = nil
    end
    protocol = nil
end
