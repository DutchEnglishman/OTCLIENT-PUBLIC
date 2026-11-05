-- The cooking window. It opens only when the server says so -- when the player uses a
-- cast iron oven (OTSERV data/scripts/cooking/cooking.lua) -- and the server closes it
-- again when they walk away. Everything is the server's: the recipe book arrives once
-- per opening (in parts, through JsonChunks), and what the player holds, how many of each
-- recipe that makes, which recipes they know and have cooked, and their cooking level
-- arrive whenever any of it could have changed.
local OPCODE = 96

-- The scroll art of a recipe's tier, the ribbon on its recipe scroll (green 25, blue 45,
-- red 65, gold 85). Level 10 has no scroll, so it shows the bare parchment.
local TIER_SCROLLS = {[25] = '/game_cooking/images/scroll_green', [45] = '/game_cooking/images/scroll_blue', [65] = '/game_cooking/images/scroll_red', [85] = '/game_cooking/images/scroll_gold'}
local BARE_SCROLL = '/game_cooking/images/parchment_blank'

local window = nil
local recipes = {}
local tabs = {}
local owned = {}
local most = {}
local learned = {}
local cooked = {}
local belowLevel = {}
local level = 10
local failChance = 0
local selectedTab = nil
local selectedIndex = nil
local amount = 0
local tabButtons = {}

-- Debounced like game_alchemy: emptying a corpse fires one container event per item.
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

-- How many of a material the player holds; "any level 40 fish" counts every one.
local function holding(material)
  local total = 0
  for _, id in ipairs(material.ids) do
    total = total + (owned[id] or 0)
  end
  return total
end

local function capitalize(text)
  return (text:gsub('^%l', string.upper))
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
  window = g_ui.displayUI('cooking')
  window:hide()
end

function destroy()
  removeEvent(refreshEvent)
  refreshEvent = nil
  if window then
    window:destroy()
    window = nil
  end
  recipes, tabs, owned, most, learned, cooked, belowLevel, tabButtons = {}, {}, {}, {}, {}, {}, {}, {}
  selectedTab, selectedIndex, amount = nil, nil, 0
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
    tabs = data.tabs or {}
    buildTabs()
  elseif data.action == 'counts' then
    owned = {}
    for _, pair in ipairs(data.owned or {}) do
      owned[pair[1]] = pair[2]
    end
    most = data.most or {}
    learned = data.learned or {}
    cooked = data.cooked or {}
    belowLevel = data.belowLevel or {}
    level = data.level or level
    failChance = data.failChance or failChance
    window:getChildById('levelLabel'):setText(tr('Cooking level %d', level))
    local bar = window:getChildById('levelBar')
    bar:setPercent(data.percent or 0)
    bar:setText((data.percent or 0) .. '%')
    window:getChildById('nextLevelLabel'):setText(level < 100 and tr('to %d', level + 1) or '')
    rebuildList()
  elseif data.action == 'open' then
    show()
  elseif data.action == 'close' then
    window:hide()
  end
end

function buildTabs()
  local panel = window:getChildById('tabs')
  panel:destroyChildren()
  tabButtons = {}
  for _, tab in ipairs(tabs) do
    local button = g_ui.createWidget('CookingTab', panel)
    button:setText(tab.name)
    for _, recipe in ipairs(recipes) do
      if recipe.tab == tab.id then
        button:getChildById('icon'):setItemId(recipe.clientId)
        break
      end
    end
    button.onClick = function() selectTab(tab.id) end
    tabButtons[tab.id] = button
  end
  selectTab(selectedTab or (tabs[1] and tabs[1].id))
end

function selectTab(tabId)
  selectedTab = tabId
  for id, button in pairs(tabButtons) do
    button:setOn(id == tabId)
  end
  selectedIndex = nil
  rebuildList()
end

-- The rows of the selected tab, or of every tab while searching. Recipes the player has
-- not learned stay listed, greyed out, as "Scroll needed".
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
      or (search == '' and recipe.tab == selectedTab)
    if matches then
      local row = g_ui.createWidget('CookingRecipeRow', list)
      row:getChildById('item'):setItemId(recipe.clientId)
      row:getChildById('name'):setText(capitalize(recipe.name))
      local levelLabel = row:getChildById('level')
      if not learned[recipe.index] then
        levelLabel:setText(tr('Scroll needed'))
        row:setOpacity(0.5)
      else
        levelLabel:setText(tr('Required level %d', recipe.level))
        levelLabel:setColor(level >= recipe.level and '#afafaf' or '#f55e5e')
        row:getChildById('star'):setVisible(not cooked[recipe.index])
      end
      row.onClick = function() selectRecipe(recipe.index) end
      if recipe.index == selectedIndex then
        row:focus()
      end
      firstShown = firstShown or recipe.index
    end
  end

  -- A refresh of the recipe already on screen keeps the amount the player set.
  if selectedIndex and recipes[selectedIndex] and window:getChildById('recipePanel').shownIndex == selectedIndex then
    amount = math.min(amount, most[selectedIndex] or 0)
    if amount == 0 and (most[selectedIndex] or 0) > 0 then
      amount = 1
    end
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
  local panel = window:getChildById('recipePanel')
  local scroll = panel:getChildById('scroll')
  local parchment = scroll:getChildById('parchment')
  panel.shownIndex = recipe and index or nil
  local ingredients = parchment:getChildById('ingredients')
  ingredients:destroyChildren()

  scroll:setImageSource(recipe and TIER_SCROLLS[recipe.level] or BARE_SCROLL)

  if not recipe then
    parchment:getChildById('dish'):setItemId(0)
    parchment:getChildById('dishName'):setText('')
    parchment:getChildById('dishEffect'):setText('')
    parchment:getChildById('steps'):setText('')
    amount = 0
    renderAmount()
    return
  end

  parchment:getChildById('dish'):setItemId(recipe.clientId)
  parchment:getChildById('dishName'):setText(capitalize(recipe.name))
  parchment:getChildById('dishEffect'):setText(recipe.description or '')

  for _, material in ipairs(recipe.materials) do
    local row = g_ui.createWidget('CookingIngredient', ingredients)
    row:getChildById('item'):setItemId(material.ids[1])
    row:getChildById('name'):setText(capitalize(material.name))
    row.material = material
  end

  local lines = {}
  for number, step in ipairs(recipe.steps or {}) do
    lines[#lines + 1] = number .. '. ' .. step
  end
  parchment:getChildById('steps'):setText(table.concat(lines, '\n'))

  amount = (most[index] or 0) > 0 and 1 or 0
  renderAmount()
end

local function canCook(recipe)
  return learned[recipe.index] and (level >= recipe.level or belowLevel[recipe.index]) and (most[recipe.index] or 0) >= 1
end

function renderAmount()
  local recipe = selectedIndex and recipes[selectedIndex]
  if not window then
    return
  end
  local panel = window:getChildById('recipePanel')
  local cookPanel = panel:getChildById('cookPanel')
  cookPanel:getChildById('amountLabel'):setText(amount)
  if not recipe then
    cookPanel:getChildById('cookButton'):setEnabled(false)
    cookPanel:getChildById('failLabel'):setText('')
    cookPanel:getChildById('experienceLabel'):setText('')
    cookPanel:getChildById('missingLabel'):setText('')
    return
  end

  -- Have / need for one dish, or for the amount chosen when that is more.
  local dishes = math.max(1, amount)
  local missing = nil
  for _, row in ipairs(panel:getChildById('scroll'):getChildById('parchment'):getChildById('ingredients'):getChildren()) do
    local need = row.material.count * dishes
    local have = holding(row.material)
    local short = have < need
    row:getChildById('count'):setText(have .. ' / ' .. need)
    row:getChildById('count'):setColor(short and '#a8281c' or '#2f5a1c')
    row:getChildById('name'):setColor(short and '#a8281c' or '#3a2a18')
    if short and not missing then
      missing = tr('Missing %d %s', need - have, row.material.name)
    end
  end

  cookPanel:getChildById('failLabel'):setText(tr('Fail chance %s%%', string.format('%g', failChance)))
  local experience = tr('Experience %d each', recipe.experience)
  if learned[recipe.index] and not cooked[recipe.index] then
    experience = experience .. tr(' (x4 first)')
  end
  cookPanel:getChildById('experienceLabel'):setText(experience)

  local reason = nil
  if not learned[recipe.index] then
    reason = tr('Scroll needed')
  elseif level < recipe.level and not belowLevel[recipe.index] then
    reason = tr('Requires cooking level %d', recipe.level)
  else
    reason = missing
  end
  cookPanel:getChildById('missingLabel'):setText(reason or '')
  cookPanel:getChildById('cookButton'):setEnabled(canCook(recipe) and amount >= 1)
end

function changeAmount(delta)
  local count = selectedIndex and most[selectedIndex] or 0
  amount = math.max(count > 0 and 1 or 0, math.min(count, amount + delta))
  renderAmount()
end

function setMaxAmount()
  amount = selectedIndex and most[selectedIndex] or 0
  renderAmount()
end

function cook()
  if not selectedIndex or amount < 1 then
    return
  end
  send({action = 'cook', recipe = selectedIndex, amount = amount})
end
