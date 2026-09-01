-- Item protection. The server owns the rule; this module owns the way in and
-- the little lock drawn in the corner of a protected slot.
--
-- No state is invented here. The cache below is only ever filled from what the
-- server sent, so a client that never gets a reply draws no locks rather than
-- drawing wrong ones.

PROTECT_OPCODE = 70

local protocol = nil

-- key -> { [slot] = true }, where key is a container id or INVENTORY_KEY.
local protectedSlots = {}

-- The inventory shares this cache under a key no container can have, so one
-- lookup answers for an equipped item and a bagged one alike.
local INVENTORY_KEY = -1

local CONTAINER_POSITION_X = 65535
local FIRST_CONTAINER_Y = 64

-- Falls back to the live protocol rather than waiting for one to arrive: the
-- first thing this module does is ask a question, which is before any answer
-- could have set `protocol`.
local function send(request)
    local proto = protocol or g_game.getProtocolGame()
    if proto then
        proto:sendExtendedOpcode(PROTECT_OPCODE, json.encode(request))
    end
end

function isProtected(key, slot)
    local slots = protectedSlots[key]
    return slots ~= nil and slots[slot] == true
end

function isInventoryProtected(slot)
    return isProtected(INVENTORY_KEY, slot)
end

-- Asks the server which slots of a container are protected. Called whenever a
-- container's contents change: protection travels with the item, so moving one
-- between bags moves its lock too, and only the server knows where it landed.
function requestContainer(containerId)
    if containerId then
        send({a = 'q', c = containerId})
    end
end

function requestInventory()
    send({a = 'q', c = INVENTORY_KEY})
end

-- Flips the lock on one slot widget. The widget itself is declared in the Item
-- style (data/styles/10-items.otui) exactly like the tier badge, so there is
-- nothing to create here and nothing that can fail to anchor.
function updateSlotIcon(itemWidget, key, slot)
    if not itemWidget or not itemWidget.protectIcon then
        return
    end

    itemWidget.protectIcon:setVisible(itemWidget:getItem() ~= nil and isProtected(key, slot))
end

function updateInventoryIcons()
    if not modules.game_inventory or not modules.game_inventory.refreshProtectIcons then
        return
    end

    modules.game_inventory.refreshProtectIcons()
end

-- Where an item lives, in the terms the server can resolve it by. Returns the
-- cache key and slot, or nil for something on the ground -- the map has no slot
-- and the client is not told about protection out there.
local function locate(thing)
    local position = thing:getPosition()
    if not position or position.x ~= CONTAINER_POSITION_X then
        return nil
    end

    if thing:getParentContainer() then
        return position.y - FIRST_CONTAINER_Y, position.z
    end

    -- An equipped item never gets a slot position -- LocalPlayer::
    -- setInventoryItem does not set one -- so its getPosition() is the invalid
    -- default. The slot has to be found by asking who is wearing what.
    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end

    for slot = InventorySlotFirst, InventorySlotLast do
        if player:getInventoryItem(slot) == thing then
            return INVENTORY_KEY, slot
        end
    end

    return nil
end

function toggle(thing)
    if not thing or not thing:isItem() then
        return
    end

    local key, slot = locate(thing)

    if key == INVENTORY_KEY then
        send({a = 't', p = {x = CONTAINER_POSITION_X, y = slot, z = 0}, s = 0})
        return
    end

    local position = thing:getPosition()
    if not position then
        return
    end

    send({
        a = 't',
        p = {x = position.x, y = position.y, z = position.z},
        s = thing:getStackPos()
    })
end

-- "Protect" or "Remove protect", chosen from what the server last told us.
-- An item on the ground has no cached state, so it gets the neutral wording
-- rather than a claim that might be backwards.
function getMenuLabel(thing)
    local key, slot = locate(thing)
    if not key then
        return tr('Protect / Remove protect')
    end

    if isProtected(key, slot) then
        return tr('Remove protect')
    end

    return tr('Protect')
end

local function onOpcode(proto, code, buffer)
    protocol = proto

    local ok, payload = pcall(json.decode, buffer)
    if not ok or type(payload) ~= 'table' or type(payload.c) ~= 'number' then
        return
    end

    local slots = {}
    for _, slot in ipairs(payload.s or {}) do
        slots[slot] = true
    end
    protectedSlots[payload.c] = slots

    if payload.c == INVENTORY_KEY then
        updateInventoryIcons()
    elseif modules.game_containers and modules.game_containers.refreshProtectIcons then
        modules.game_containers.refreshProtectIcons(payload.c)
    end
end

local function onGameStart()
    -- Nothing has asked yet at this point, and an equipped item is protected
    -- from the moment you log in, so the inventory has to be pulled once.
    requestInventory()
end

-- Equipping or unequipping moves a lock in or out of a slot, and the server is
-- the only one who knows which.
local function onInventoryChange()
    requestInventory()
end

local function onGameEnd()
    protocol = nil
    protectedSlots = {}
end

function init()
    ProtocolGame.registerExtendedOpcode(PROTECT_OPCODE, onOpcode)
    connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
    connect(LocalPlayer, {onInventoryChange = onInventoryChange})
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(PROTECT_OPCODE)
    disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
    disconnect(LocalPlayer, {onInventoryChange = onInventoryChange})

    protocol = nil
    protectedSlots = {}
end
