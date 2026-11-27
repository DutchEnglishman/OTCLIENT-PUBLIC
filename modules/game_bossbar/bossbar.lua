-- Boss bar: the boss's name and HP at the top of the game screen while you are
-- in a private boss room. (The time left lies on the floor of the room itself:
-- the server puts it there as items, see OTSERV data/boss_rooms/boss_rooms.lua.)
--
-- The server sends JSON over extended opcode 109 to everyone standing in the arena:
--   {t = "show", name, hp, max, dead}  whenever it changes, and every 2 seconds anyway
--   {t = "hide"}                       when the run ends or you leave the room
-- hp and max are missing until the boss stands in the room; dead is set once he
-- is killed. Nothing comes once you are out of the arena (you died, or were
-- moved out some other way), so the bar also hides itself after HIDE_AFTER_MS
-- without a message.

local OPCODE = 109
local HIDE_AFTER_MS = 5000
-- The fill sits inside the frame's 1 px border with a 1 px margin: the track is
-- 312 wide, the frame 310, its inside 308, the fill at most 306.
local FILL_MAX = 306
local FILL_COLOR, SHINE_COLOR, SHADE_COLOR = '#a3201a', '#d0473a', '#6e120e'
local WAIT_COLOR = '#3a2a22'

local bar = nil
local hideEvent = nil

local function formatNumber(value)
  local text = tostring(math.floor(value))
  local grouped = text:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (grouped:gsub('^,', ''))
end

local function hide()
  if hideEvent then
    removeEvent(hideEvent)
    hideEvent = nil
  end
  if bar then
    bar:destroy()
    bar = nil
  end
end

local function paintFill(fill, width, waiting)
  fill:setWidth(width)
  fill:setBackgroundColor(waiting and WAIT_COLOR or FILL_COLOR)
  fill:getChildById('shine'):setBackgroundColor(waiting and WAIT_COLOR or SHINE_COLOR)
  fill:getChildById('shade'):setBackgroundColor(waiting and WAIT_COLOR or SHADE_COLOR)
end

local function setHealth(data)
  local frame = bar:getChildById('track'):getChildById('frame')
  local fill = frame:getChildById('fill')
  local text = frame:getChildById('text')

  if data.dead then
    paintFill(fill, 0, false)
    text:setText('Defeated')
    return
  end

  local hp, max = tonumber(data.hp), tonumber(data.max)
  if not hp or not max or max <= 0 then
    -- the group is in, the boss is not there yet
    paintFill(fill, FILL_MAX, true)
    text:setText('...')
    return
  end

  local share = math.max(0, math.min(1, hp / max))
  local percent = math.floor(share * 100)
  if hp > 0 and percent == 0 then
    percent = 1
  end
  paintFill(fill, math.floor(FILL_MAX * share + 0.5), false)
  text:setText(string.format('%s / %s (%d%%)', formatNumber(hp), formatNumber(max), percent))
end

local function show(data)
  local mapPanel = modules.game_interface.getMapPanel()
  if not mapPanel then
    return
  end
  if not bar then
    bar = g_ui.createWidget('BossBar', mapPanel)
  end
  bar:raise()
  bar:getChildById('name'):setText(data.name or '')
  setHealth(data)

  if hideEvent then
    removeEvent(hideEvent)
  end
  hideEvent = scheduleEvent(hide, HIDE_AFTER_MS)
end

function onExtendedOpcode(protocol, opcode, buffer)
  local ok, data = pcall(json.decode, buffer)
  if not ok or type(data) ~= 'table' then
    return
  end
  if data.t == 'show' then
    show(data)
  elseif data.t == 'hide' then
    hide()
  end
end

function init()
  g_ui.importStyle('bossbar')
  connect(g_game, {onGameEnd = hide})
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
end

function terminate()
  disconnect(g_game, {onGameEnd = hide})
  ProtocolGame.unregisterExtendedOpcode(OPCODE, onExtendedOpcode)
  hide()
end
