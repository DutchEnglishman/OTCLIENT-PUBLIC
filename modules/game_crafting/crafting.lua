local CODE = 108

local window = nil
local categories = nil
local craftPanel = nil
local itemsList = nil
local refineInput = nil
local refineInputHint = nil
local refineInputPos = nil
local craftAmount = nil
local craftAmountLabel = nil

local selectedCategory = nil
local selectedCraftId = nil
local Crafts = {weaponsmith = {}, armorsmith = {}, alchemist = {}, enchanter = {}, jeweller = {}}
local money = 0
local craftingButton = nil

function init()
  connect(
    g_game,
    {
      onGameStart = create,
      onGameEnd = destroy
    }
  )

  ProtocolGame.registerExtendedOpcode(CODE, onExtendedOpcode)

  -- Fallback entry point until a crafting station (action id 38820, see
  -- data/scripts/crafting/crafting_registration.lua on the server) is placed
  -- on the map -- without it there would be no way to ever open this window.
  -- Uses the Keybind system (like game_hotkeys' own Ctrl+K toggle and
  -- game_tasksystem's Ctrl+Shift+K), not raw g_keyboard.bindKeyDown -- a
  -- panel-scoped binding stops firing once this window holds keyboard focus.
  Keybind.new("Windows", "Show/hide Crafting", "Ctrl+Shift+C", "")
  Keybind.bind("Windows", "Show/hide Crafting", {
    {
      type = KEY_DOWN,
      callback = toggleWindow,
    }
  })

  -- "Crafting" topbar button removed by request -- the window itself still
  -- works and is still reachable via its Ctrl+Shift+C keybind above (and via
  -- a crafting station once one is placed on the map).

  if g_game.isOnline() then
    create()
  end
end

function terminate()
  disconnect(
    g_game,
    {
      onGameStart = create,
      onGameEnd = destroy
    }
  )

  ProtocolGame.unregisterExtendedOpcode(CODE, onExtendedOpcode)

  Keybind.delete("Windows", "Show/hide Crafting")

  if craftingButton then
    craftingButton:destroy()
    craftingButton = nil
  end

  destroy()
end

function create()
  if window then
    return
  end

  window = g_ui.displayUI("crafting")
  window:hide()

  categories = window:getChildById("categories")
  craftPanel = window:getChildById("craftPanel")
  itemsList = window:getChildById("itemsList")

  refineInput = craftPanel:getChildById("refineInput")
  refineInputHint = craftPanel:getChildById("refineInputHint")

  craftAmount = craftPanel:getChildById("craftAmount")
  craftAmountLabel = craftPanel:getChildById("craftAmountLabel")
  craftAmount.onValueChange = function()
    renderCraftAmount()
  end

  -- Same shape game_actionbar uses for its slots: the drag manager offers the
  -- dragged widget, and currentDragThing is the Thing under it.
  refineInput.onDrop = function(self, draggedWidget, mousePos)
    if not draggedWidget or not draggedWidget.currentDragThing then
      return false
    end

    local thing = draggedWidget.currentDragThing
    if not thing:isItem() then
      return false
    end

    setRefineInput(thing)
    return true
  end

  refineInput.onMouseRelease = function(self, mousePos, mouseButton)
    if mouseButton == MouseRightButton then
      setRefineInput(nil)
      return true
    end
    return false
  end

  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(CODE, json.encode({action = "fetch"}))
  end
end

function destroy()
  if window then
    categories = nil
    craftPanel = nil
    itemsList = nil
    -- Cleared with the rest: these point into the window that is about to be
    -- destroyed, and selectCategory would touch them again on the next login.
    refineInput = nil
    refineInputHint = nil
    craftAmount = nil
    craftAmountLabel = nil

    selectedCategory = nil
    selectedCraftId = nil
    Crafts = {weaponsmith = {}, armorsmith = {}, alchemist = {}, enchanter = {}, jeweller = {}}

    window:destroy()
    window = nil
  end
end

function onExtendedOpcode(protocol, code, buffer)
  local status, json_data =
    pcall(
    function()
      return json.decode(buffer)
    end
  )

  if not status then
    g_logger.error("[Crafting] JSON error: " .. data)
    return false
  end

  local action = json_data.action
  local data = json_data.data
  if action == "fetch" then
    -- The refining list is re-sent every time the slot changes, so the server
    -- flags the first message of a set as a replacement. Without it each
    -- re-send would stack another copy of the same functions.
    if data.reset then
      Crafts[data.category] = {}
    end
    for i = 1, #data.crafts do
      table.insert(Crafts[data.category], data.crafts[i])
    end
    if data.category == selectedCategory then
      rebuildItemsList()
    end
    if data.category == "weaponsmith" and not selectedCategory then
      selectCategory("weaponsmith")
      selectItem(1)
    end
  elseif action == "materials" then
    for i = 1, #data.materials do
      local material = data.materials[i]
      for x = 1, #material do
        local mats = Crafts[data.category][data.from + i - 1].materials[x]
        if mats then
          mats.player = material[x]
        end
      end
    end
    if data.from == 1 and window:isVisible() and selectedCategory == data.category then
      selectItem(selectedCraftId)
    end
  elseif action == "money" then
    money = data
    craftPanel:recursiveGetChildById("playerMoney"):setText(comma_value(money))
  elseif action == "show" then
    selectItem(selectedCraftId)
    show()
  elseif action == "refineInput" then
    -- Authoritative slot state. The drop handler fills the slot optimistically,
    -- so this is what clears it when the server refused the item, and when an
    -- upgrade destroyed it. Anything else and the slot is simply re-pointed at
    -- the live item, which is how it survives a roll without being re-dropped.
    if data and (data.clientId or 0) == 0 then
      refineInputPos = nil
      setRefineItemInfo(nil, nil, nil)
    else
      -- Adopt the server's coordinates rather than keeping the ones sent at
      -- drop time. A craft consumes shards out of the same container, and if
      -- they sat ahead of the item everything after them shifts down a slot --
      -- the server re-finds the item by identity, and this is how that
      -- correction reaches the widget instead of it re-resolving a stale index
      -- and drawing the neighbour.
      if data.container and data.slot then
        refineInputPos = {x = 0xFFFF, y = data.container + 0x40, z = data.slot}
      end
      setRefineItemInfo(data.upgrade, data.rarityName, data.rarity)
    end
    refreshRefineInput()
  elseif action == "crafted" then
    onItemCrafted()
  end
end

function onItemCrafted()
  if selectedCategory and selectedCraftId then
    local craft = Crafts[selectedCategory][selectedCraftId]
    if craft then
      for i = 1, #craft.materials do
        local materialWidget = craftPanel:getChildById("craftLine" .. i)
        materialWidget:setImageSource("/images/crafting/craft_line" .. i .. "on")
        scheduleEvent(
          function()
            materialWidget:setImageSource("/images/crafting/craft_line" .. (i == 2 and 5 or i))
          end,
          850
        )
      end
      local button = craftPanel:getChildById("craftButton")
      button:disable()
      scheduleEvent(
        function()
          button:enable()
        end,
        860
      )
    end
  end
end

function onSearch()
  scheduleEvent(
    function()
      local searchInput = window:recursiveGetChildById("searchInput")
      local text = searchInput:getText():lower()
      if text:len() >= 1 then
        local children = itemsList:getChildCount()
        for i = children, 1, -1 do
          local child = itemsList:getChildByIndex(i)
          local name = child:getChildById("name"):getText():lower()
          if name:find(text) then
            child:show()
            child:focus()
            selectItem(i)
          else
            child:hide()
          end
        end
      else
        local children = itemsList:getChildCount()
        for i = children, 1, -1 do
          local child = itemsList:getChildByIndex(i)
          child:show()
          child:focus()
          selectItem(i)
        end
      end
    end,
    25
  )
end

-- Per-tab name for the list panel. Keyed on the internal category id, which is
-- unchanged -- only the tab labels in crafting.otui were renamed.
local DEFAULT_LIST_TITLE = "Craftable Items"
local LIST_TITLES = {
  weaponsmith = "Refining"
}

-- The tab that refines instead of crafting. Must match Refining.category on
-- the server (data/crafting/refining.lua).
local REFINE_CATEGORY = "weaponsmith"

-- The "Based on N" line beside the craft button. Only refining sends a basis;
-- every other tab leaves it blank.
function setRefineBasis(value)
  local label = craftPanel and craftPanel:recursiveGetChildById("refineBasis")
  if label then
    label:setText(value and ("Based on " .. value) or "")
  end
end

-- Points the slot at the item that is really in the backpack rather than at a
-- copy of its sprite.
--
-- setItem, not setItemId: the Item carries its own position, and that is what
-- lets hovering the slot fetch the server-side tooltip and show the item's real
-- (upgraded) stats -- UIItem:onHoverChange calls game_itemtooltip.requestTooltip
-- before it checks isVirtual, so a virtual slot still gets a tooltip as long as
-- it holds a real item.
--
-- Re-resolved from the container every time rather than held onto: refining
-- rewrites the item's attributes in place and the container re-sends that slot
-- afterwards, so the Item the drop handed over goes stale.
-- Upgrade level and rarity either side of the slot. The rarity colour comes
-- from game_itemtooltip so the word matches the colour the tooltip paints for
-- the same item.
function setRefineItemInfo(upgrade, rarityName, rarityId)
  if not craftPanel then
    return
  end

  local upgradeLabel = craftPanel:getChildById("refineUpgrade")
  if upgradeLabel then
    upgradeLabel:setText(upgrade and ("+" .. upgrade) or "")
  end

  local rarityLabel = craftPanel:getChildById("refineRarity")
  if rarityLabel then
    rarityLabel:setText(rarityName or "")
    local color = rarityId and modules.game_itemtooltip
      and modules.game_itemtooltip.getRarityColor(rarityId)
    rarityLabel:setColor(color or "#afafaf")
  end
end

function refreshRefineInput()
  if not refineInput then
    return
  end

  if not refineInputPos then
    refineInput:setItem(nil)
    return
  end

  local container = g_game.getContainers()[refineInputPos.y - 0x40]
  refineInput:setItem(container and container:getItem(refineInputPos.z) or nil)
end

-- Tells the server which item is slotted, or that the slot was cleared, and
-- remembers where it is so the slot can be re-pointed at the live item after a
-- roll. The position is the protocol one the client already keeps on every
-- item: a container item carries {0xFFFF, containerId | 0x40, slot}
-- (src/client/container.h:37), which is what the server decodes.
function setRefineInput(thing)
  if not refineInput then
    return
  end

  local protocolGame = g_game.getProtocolGame()
  if not protocolGame then
    return
  end

  if thing then
    refineInputPos = thing:getPosition()
    refreshRefineInput()

    protocolGame:sendExtendedOpcode(CODE, json.encode({
      action = "setInput",
      data = {
        position = {x = refineInputPos.x, y = refineInputPos.y, z = refineInputPos.z}
      }
    }))
  else
    refineInputPos = nil
    refreshRefineInput()
    protocolGame:sendExtendedOpcode(CODE, json.encode({action = "setInput"}))
  end
end

function selectCategory(category)
  if selectedCategory then
    local oldCatBtn = categories:getChildById(selectedCategory .. "Cat")
    if oldCatBtn then
      oldCatBtn:setOn(false)
    end
  end

  local newCatBtn = categories:getChildById(category .. "Cat")
  if newCatBtn then
    newCatBtn:setOn(true)
    selectedCategory = category

    -- The list panel carries one static title in crafting.otui, shared by every
    -- tab, so a per-tab name has to be set here.
    itemsList:setText(LIST_TITLES[category] or DEFAULT_LIST_TITLE)

    -- Leaving the tab drops the slot so the server is not still pricing an
    -- item nothing on screen refers to.
    local refining = (category == REFINE_CATEGORY)
    if refineInput then
      refineInput:setVisible(refining)
      refineInputHint:setVisible(refining)
      if not refining then
        setRefineInput(nil)
        setRefineItemInfo(nil, nil, nil)
      end
    end

    itemsList:destroyChildren()

    selectedCraftId = nil

    for i = 1, 6 do
      local materialWidget = craftPanel:getChildById("material" .. i)
      materialWidget:setItem(nil)
      craftPanel:getChildById("count" .. i):setText("")
    end

    craftPanel:getChildById("craftOutcome"):setItem(nil)
    craftPanel:recursiveGetChildById("totalCost"):setText("")
    setRefineBasis(nil)

    rebuildItemsList()
  end
end

-- Builds the rows for the selected category.
--
-- Split out of selectCategory so a fetch can refresh the list in place.
-- Refining re-sends its list every time the slot changes, and the rows used to
-- be built only inside selectCategory -- so after dropping an item you had to
-- click the tab again before anything appeared.
function rebuildItemsList()
  if not itemsList or not selectedCategory or not Crafts[selectedCategory] then
    return
  end

  itemsList:destroyChildren()

  local list = Crafts[selectedCategory]
  for i = 1, #list do
    local craft = list[i]
    local w = g_ui.createWidget("ItemListItem")
    w:setId(i)
    w:getChildById("item"):setItemId(craft.clientId)
    w:getChildById("name"):setText(craft.name)
    -- Refining rows carry their own second line ("Max ilvl N"). The other tabs
    -- send no subtitle and keep the required-level text.
    w:getChildById("level"):setText(craft.subtitle or ("Required Level " .. craft.level))
    -- Set on the row and on its icon: the icon is a child widget and swallows
    -- the hover, so a tooltip on the row alone never shows when the pointer is
    -- over the crystal itself.
    if craft.description then
      w:setTooltip(craft.description)
      w:getChildById("item"):setTooltip(craft.description)
    end
    itemsList:addChild(w)
  end

  -- Hold the current selection across a re-send where it still exists, so a
  -- reprice does not bounce the panel back to the first row.
  local keep = selectedCraftId
  if not (keep and list[keep]) then
    keep = (#list > 0) and 1 or nil
  end

  if keep then
    local w = itemsList:getChildByIndex(keep)
    if w then
      w:focus()
    end
  end
  selectItem(keep)
end

-- How many the slider is asking for. One whenever the recipe is single, so
-- every multiplication below is safe to apply unconditionally.
function getCraftAmount()
  local craft = Crafts[selectedCategory] and Crafts[selectedCategory][selectedCraftId]
  if not craft or (craft.maxBatch or 1) <= 1 or not craftAmount then
    return 1
  end

  return math.max(1, craftAmount:getValue())
end

-- Everything on the panel that scales with the batch. Called on selection and
-- again on every slider move, so the materials, the total and the outcome
-- stack all agree with the number being asked for.
function renderCraftAmount()
  local craft = Crafts[selectedCategory] and Crafts[selectedCategory][selectedCraftId]
  if not craft then
    return
  end

  local amount = getCraftAmount()

  for i = 1, 6 do
    craftPanel:getChildById("material" .. i):setItem(nil)
    craftPanel:getChildById("count" .. i):setText("")
  end

  for i = 1, #craft.materials do
    local material = craft.materials[i]
    local needed = material.count * amount
    craftPanel:getChildById("material" .. i):setItemId(material.id)

    local count = craftPanel:getChildById("count" .. i)
    count:setText(material.player .. "\n" .. needed)
    count:setColor(material.player >= needed and "#FFFFFF" or "#FF0000")
  end

  local outcome = craftPanel:getChildById("craftOutcome")
  outcome:setItemId(craft.clientId)
  outcome:setItemCount(craft.count * amount)
  outcome:setTooltip(craft.description or "")

  craftPanel:recursiveGetChildById("totalCost"):setText(comma_value(craft.cost * amount))
  setRefineBasis(craft.basedOn)

  if craftAmountLabel and craftAmountLabel:isVisible() then
    craftAmountLabel:setText("Amount: " .. amount)
  end
end

function selectItem(id)
  local craftId = tonumber(id)
  local craft = Crafts[selectedCategory] and Crafts[selectedCategory][craftId]

  for i = 1, 6 do
    local materialWidget = craftPanel:getChildById("material" .. i)
    materialWidget:setItem(nil)
    craftPanel:getChildById("count" .. i):setText("")
  end

  -- A category can legitimately have zero recipes configured yet (see
  -- data/crafting/<profession>.lua on the server -- only armorsmith ships
  -- with an example). onExtendedOpcode's "fetch" handler unconditionally
  -- calls selectItem(1) for weaponsmith on login regardless of whether it
  -- has any recipes, so this has to tolerate craft being nil rather than
  -- crash -- leave the panel cleared/no-selection instead.
  if not craft then
    selectedCraftId = nil
    craftPanel:getChildById("craftOutcome"):setItem(nil)
    craftPanel:recursiveGetChildById("totalCost"):setText("")
    setRefineBasis(nil)
    if craftAmount then
      craftAmount:setVisible(false)
      craftAmountLabel:setVisible(false)
    end
    return
  end

  selectedCraftId = craftId

  -- The slider covers 1..maxBatch and is hidden for anything single. Reset to
  -- 1 on every selection so a batch picked for one recipe is not silently
  -- carried into the next.
  local maxBatch = craft.maxBatch or 1
  if craftAmount then
    craftAmount:setVisible(maxBatch > 1)
    craftAmountLabel:setVisible(maxBatch > 1)
    if maxBatch > 1 then
      craftAmount:setMinimum(1)
      craftAmount:setMaximum(maxBatch)
      craftAmount:setValue(1)
    end
  end

  renderCraftAmount()

end

function craftItem()
  if selectedCategory and selectedCraftId then
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
      protocolGame:sendExtendedOpcode(CODE, json.encode({
        action = "craft",
        data = {
          category = selectedCategory,
          craftId = selectedCraftId,
          amount = getCraftAmount()
        }
      }))
    end
  end
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
end

function toggleWindow()
  if not window then
    return
  end

  if window:isVisible() then
    hide()
  else
    show()
  end
end

function comma_value(amount)
  local formatted = amount
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1.%2")
    if (k == 0) then
      break
    end
  end
  return formatted
end
