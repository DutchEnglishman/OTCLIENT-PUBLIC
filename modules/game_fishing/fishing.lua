-- The fishing timing bar. A cast at a whirlpool makes the server send the bar's zones
-- (OTSERV data/fishing/fishing_minigame.lua); this draws it over the whirlpool's tile,
-- runs the pointer to the right end and back, and the next click on the map sends where
-- it stopped.
-- The server decides what that position is worth and answers with the result, so nothing
-- here pays anything.
local OPCODE = 91
local BAR_SIZE = 1000
local TRACK_WIDTH = 130 -- inside the track's 1 px padding, see fishing.otui

local current = nil
local swallowRelease = false
local mapPanel = nil

local function send(message)
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(OPCODE, json.encode(message))
  end
end

local function toPixels(at)
  return math.floor(at * TRACK_WIDTH / BAR_SIZE)
end

-- Out to the right end and back, sweepMs each way; the same curve as the server's
-- pointerAt. Second value: the pointer is back at the start, so the bar is over.
local function pointerPosition()
  local sweep = current.sweepMs
  local elapsed = math.min(2 * sweep, g_clock.millis() - current.startedAt)
  local done = elapsed >= 2 * sweep
  if elapsed > sweep then
    elapsed = 2 * sweep - elapsed
  end
  return math.floor(elapsed * BAR_SIZE / sweep), done
end

local function close()
  if not current then
    return
  end
  if current.tick then
    removeEvent(current.tick)
  end
  if current.closing then
    removeEvent(current.closing)
  end
  if current.widget and not current.widget:isDestroyed() then
    current.widget:destroy()
  end
  current = nil
end

local function update()
  if not current or current.stopped then
    return
  end
  local at, done = pointerPosition()
  current.pointer:setMarginLeft(toPixels(at))
  if done then
    -- Back at the start without a click; the server times the bar out and answers "miss".
    current.stopped = true
  end
end

local function show(data)
  close()
  local tile = g_map.getTile({x = data.x, y = data.y, z = data.z})
  if not tile then
    return
  end

  local widget = g_ui.createWidget('FishingBar', mapPanel)
  local track = widget:getChildById('track')
  for _, zone in ipairs(data.zones or {}) do
    local from, to = toPixels(zone.from), toPixels(zone.to)
    local band = g_ui.createWidget('FishingZone', track)
    band:setMarginLeft(from)
    band:setWidth(math.max(1, to - from))

    local icon = g_ui.createWidget('FishingZoneIcon', widget)
    icon:setItemId(zone.icon)
    icon:setMarginLeft(1 + math.floor((from + to) / 2) - 8)
  end
  local pointer = widget:getChildById('pointer')
  pointer:raise()
  tile:attachWidget(widget)

  current = {
    id = data.id,
    sweepMs = data.sweepMs,
    startedAt = g_clock.millis(),
    widget = widget,
    track = track,
    pointer = pointer,
  }
  current.tick = cycleEvent(update, 16)
end

local function finish(data)
  if not current or current.id ~= data.id then
    return
  end
  current.stopped = true
  current.track:setBorderColor(data.result == 'miss' and '#c83232' or '#2fbf4a')
  current.closing = scheduleEvent(close, 700)
end

local function stop()
  if not current or current.stopped then
    return false
  end
  local at, done = pointerPosition()
  if done then
    return false
  end
  current.stopped = true
  current.pointer:setMarginLeft(toPixels(at))
  send({t = 'stop', id = current.id, at = at})
  return true
end

-- Pushed in front of the map's own handlers: while the pointer runs, a click stops it and
-- does nothing else (no walk, no use), and its release is swallowed with it.
local function onMapPress()
  if stop() then
    swallowRelease = true
    return true
  end
end

local function onMapRelease()
  if swallowRelease then
    swallowRelease = false
    return true
  end
end

function onExtendedOpcode(protocol, opcode, buffer)
  local ok, data = pcall(json.decode, buffer)
  if not ok or type(data) ~= 'table' then
    return
  end
  if data.t == 'start' then
    show(data)
  elseif data.t == 'end' then
    finish(data)
  end
end

function init()
  g_ui.importStyle('fishing')
  mapPanel = modules.game_interface.getMapPanel()
  connect(mapPanel, {onMousePress = onMapPress, onMouseRelease = onMapRelease}, true)
  connect(g_game, {onGameEnd = close})
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
end

function terminate()
  disconnect(mapPanel, {onMousePress = onMapPress, onMouseRelease = onMapRelease})
  disconnect(g_game, {onGameEnd = close})
  ProtocolGame.unregisterExtendedOpcode(OPCODE, onExtendedOpcode)
  close()
end
