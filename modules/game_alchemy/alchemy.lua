-- The alchemy window. It opens only when the server says so -- when the player
-- uses an alchemy table (OTSERV data/scripts/alchemy/alchemy.lua) -- and the
-- server closes it again when they walk away. Everything is the server's: the
-- recipe book arrives once per opening (in parts, through JsonChunks), and the
-- counts of what the player holds, how many of each recipe that makes, their
-- gold and their alchemy level arrive whenever any of it could have changed.
local OPCODE = 89

local window = nil
local recipes = {}
local groups = {}
local owned = {}
local most = {}
local gold = 0
local level = 10
local selectedGroup = nil
local selectedIndex = nil
local groupButtons = {}

-- Debounced like game_crafting: emptying a corpse fires one container event per item.
local REFRESH_DELAY = 250
local refreshEvent = nil

local function send(message)
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(OPCODE, json.encode(message))
  end
end

local function requestRefresh()
  if refreshEvent or not window or not window:isVisible() then
    return
  end
  refreshEvent = scheduleEvent(function()
    refreshEvent = nil
    send({action = 'refresh'})
  end, REFRESH_DELAY)
end

local function formatGold(value)
  local text = tostring(value)
  while true do
    local replaced
    text, replaced = text:gsub('^(-?%d+)(%d%d%d)', '%1.%2')
    if replaced == 0 then
      return text
    end
  end
end

-- How many of a material the player holds; "any fruit" counts all four.
local function holding(material)
  local total = 0
  for _, id in ipairs(material.ids) do
    total = total + (owned[id] or 0)
  end
  return total
end

function init()
  connect(g_game, {onGameStart = create, onGameEnd = destroy})
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(LocalPlayer, {onInventoryChange = requestRefresh})
  connect(Container, {onAddItem = requestRefresh, onRemoveItem = requestRefresh, onUpdateItem = requestRefresh})
  if g_game.isOnline() then
    create()
  end
end

function terminate()
  disconnect(g_game, {onGameStart = create, onGameEnd = destroy})
  ProtocolGame.unregisterExtendedOpcode(OPCODE, onExtendedOpcode)
  disconnect(LocalPlayer, {onInventoryChange = requestRefresh})
  disconnect(Container, {onAddItem = requestRefresh, onRemoveItem = requestRefresh, onUpdateItem = requestRefresh})
  destroy()
end

function create()
  if window then
    return
  end
  window = g_ui.displayUI('alchemy')
  window:hide()
end

function destroy()
  removeEvent(refreshEvent)
  refreshEvent = nil
  if window then
    window:destroy()
    window = nil
  end
  recipes, groups, owned, most, groupButtons = {}, {}, {}, {}, {}
  selectedGroup, selectedIndex = nil, nil
end

function show()
  if not window then
    return
  end
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if not window then
    return
  end
  window:hide()
  send({action = 'close'})
end

function onExtendedOpcode(protocol, code, buffer)
  local ok, data = pcall(json.decode, buffer)
  if not ok or type(data) ~= 'table' or not window then
    return
  end

  if data.action == 'recipes' then
    data = JsonChunks.receive(OPCODE, data, 'recipes')
    if not data then
      return
    end
    recipes = data.recipes or {}
    groups = data.groups or {}
    buildGroups()
  elseif data.action == 'counts' then
    owned = {}
    for _, pair in ipairs(data.owned or {}) do
      owned[pair[1]] = pair[2]
    end
    most = data.most or {}
    gold = data.gold or 0
    level = data.level or level
    window:getChildById('levelLabel'):setText(tr('Alchemy level %d', level))
    local bar = window:getChildById('levelBar')
    bar:setPercent(data.percent or 0)
    bar:setTooltip(tr('%d%% to the next level', data.percent or 0))
    window:getChildById('goldLabel'):setText(tr('Gold (backpack and bank): %s', formatGold(gold)))
    rebuildList()
  elseif data.action == 'open' then
    show()
  elseif data.action == 'close' then
    window:hide()
  end
end

local function capitalize(text)
  return (text:gsub('^%l', string.upper))
end

function buildGroups()
  local panel = window:getChildById('groups')
  panel:destroyChildren()
  groupButtons = {}
  for _, group in ipairs(groups) do
    local button = g_ui.createWidget('GroupButton', panel)
    button:setText(group.name)
    button.onClick = function() selectGroup(group.id) end
    groupButtons[group.id] = button
  end
  selectGroup(selectedGroup or (groups[1] and groups[1].id))
end

function selectGroup(groupId)
  selectedGroup = groupId
  for id, button in pairs(groupButtons) do
    button:setOn(id == groupId)
  end
  selectedIndex = nil
  rebuildList()
end

-- The rows of the selected group, or of every group while searching. Recipes
-- above the player's level stay listed, dimmed, with the level they need.
function rebuildList()
  if not window then
    return
  end
  local list = window:getChildById('recipeList')
  list:destroyChildren()

  local search = window:getChildById('searchInput'):getText():lower()
  local firstShown = nil
  for _, recipe in ipairs(recipes) do
    local matches = search ~= '' and recipe.name:lower():find(search, 1, true)
      or (search == '' and recipe.group == selectedGroup)
    if matches then
      local row = g_ui.createWidget('RecipeRow', list)
      row:getChildById('item'):setItemId(recipe.clientId)
      row:getChildById('name'):setText(recipe.name)
      local levelLabel = row:getChildById('level')
      if level >= recipe.level then
        local count = most[recipe.index] or 0
        levelLabel:setText(count > 0 and tr('Can brew %d', count) or tr('Missing ingredients'))
        levelLabel:setColor(count > 0 and '#44ad25' or '#afafaf')
      else
        levelLabel:setText(tr('Alchemy level %d', recipe.level))
        levelLabel:setColor('#f55e5e')
        row:setOpacity(0.6)
      end
      row.onClick = function() selectRecipe(recipe.index) end
      if recipe.index == selectedIndex then
        row:focus()
      end
      firstShown = firstShown or recipe.index
    end
  end

  -- A refresh of the recipe already on screen keeps the amount the player set.
  if selectedIndex and recipes[selectedIndex] and window:getChildById('brewPanel').shownIndex == selectedIndex then
    local amount = window:getChildById('brewPanel'):getChildById('amount')
    amount:setMaximum(math.max(1, most[selectedIndex] or 0))
    renderAmount()
    return
  end
  if not selectedIndex or not recipes[selectedIndex] then
    selectedIndex = firstShown
  end
  selectRecipe(selectedIndex)
end

function selectRecipe(index)
  selectedIndex = index
  local recipe = index and recipes[index]
  local panel = window:getChildById('brewPanel')
  panel.shownIndex = recipe and index or nil
  local ingredients = panel:getChildById('ingredients')
  ingredients:destroyChildren()
  if not recipe then
    panel:getChildById('product'):setItemId(0)
    panel:getChildById('productName'):setText('')
    panel:getChildById('productLevel'):setText('')
    panel:getChildById('productDescription'):setText('')
    panel:getChildById('costLabel'):setText('')
    panel:getChildById('brewButton'):setEnabled(false)
    return
  end

  panel:getChildById('product'):setItemId(recipe.clientId)
  panel:getChildById('productName'):setText(capitalize(recipe.name))
  local levelText = panel:getChildById('productLevel')
  levelText:setText(tr('Alchemy level %d, %d experience a brew', recipe.level, recipe.experience))
  levelText:setColor(level >= recipe.level and '#afafaf' or '#f55e5e')
  panel:getChildById('productDescription'):setText(recipe.description or '')

  for _, material in ipairs(recipe.materials) do
    local slot = g_ui.createWidget('IngredientSlot', ingredients)
    slot:getChildById('item'):setItemId(material.ids[1])
    slot:setTooltip(capitalize(material.name))
    slot.material = material
  end

  local amount = panel:getChildById('amount')
  local count = most[index] or 0
  amount:setMinimum(1)
  amount:setMaximum(math.max(1, count))
  amount:setValue(1)
  renderAmount()
end

function renderAmount()
  local recipe = selectedIndex and recipes[selectedIndex]
  if not window or not recipe then
    return
  end
  local panel = window:getChildById('brewPanel')
  local amount = panel:getChildById('amount'):getValue()
  local count = most[selectedIndex] or 0

  for _, slot in ipairs(panel:getChildById('ingredients'):getChildren()) do
    local need = slot.material.count * amount
    local have = holding(slot.material)
    local label = slot:getChildById('count')
    label:setText(have .. '/' .. need)
    label:setColor(have >= need and '#ffffff' or '#f55e5e')
  end

  panel:getChildById('amountLabel'):setText(tr('Amount: %d', amount))
  local costLabel = panel:getChildById('costLabel')
  costLabel:setText(tr('Cost: %s gold (%s a brew)', formatGold(recipe.gold * amount), formatGold(recipe.gold)))
  costLabel:setColor(gold >= recipe.gold * amount and '#ffffff' or '#f55e5e')
  panel:getChildById('brewButton'):setEnabled(level >= recipe.level and count >= 1)
end

function brew()
  if not selectedIndex then
    return
  end
  local amount = window:getChildById('brewPanel'):getChildById('amount'):getValue()
  send({action = 'brew', recipe = selectedIndex, amount = amount})
end
