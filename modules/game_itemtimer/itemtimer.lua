-- Countdown overlay for items that expire (time ring, life ring, ...).
--
-- UIItem::draw already renders the text and Item already ticks a countdown down
-- from an absolute end stamp. The only thing protocol 860 cannot do is tell the
-- client how much time is left: the stock field is read in
-- ProtocolGame::parseThing behind GameThingClock *and* the 12.x appearance
-- flags hasClockExpire/hasExpire/hasExpireStop, which an 8.60 .dat never sets.
-- Enabling that feature here would risk the parser consuming five bytes that
-- the server never wrote, so the number comes over an extended opcode instead
-- and is applied to the Item objects directly.

ITEM_TIMER_OPCODE = 62

-- Latest snapshot from the server, plus when it landed. Re-applying has to
-- subtract the elapsed time or every re-apply would restart the countdown and
-- the number on screen would sit still.
local snapshot = {}
local snapshotAt = 0
local applyEvent = nil

local function clear(item)
    item:setCharges(0)
    item:setDecaying(false)
    item:setDurationTime(0)
end

local function applyTo(item, entry, seconds, decaying, charges)
    if not item then
        return
    end

    -- While an item is dragged, the widget for a slot is rebuilt before the
    -- next snapshot arrives, so a slot-keyed entry can briefly describe an item
    -- that is no longer there. Refuse a mismatched entry rather than flashing
    -- another item's number.
    --
    -- Compared on CLIENT id (Thing::getId, src/client/thing.h:45), never the
    -- server id: this client and the server ship different items.otb files, so
    -- their server ids disagree and comparing those blanked the overlay
    -- entirely. The client id is what the server sends to render the item, so
    -- both sides agree on it. A 0 or missing id means "unknown", so apply.
    if entry and entry.id and entry.id > 0 then
        local clientId = item:getId()
        if clientId and clientId > 0 and clientId ~= entry.id then
            clear(item)
            return
        end
    end

    item:setCharges(charges or 0)

    if not seconds or seconds <= 0 then
        item:setDecaying(false)
        item:setDurationTime(0)
        return
    end

    -- Order matters: setDurationTime only converts to an absolute end time when
    -- the item is already decaying (src/client/item.cpp:444). A ring in a
    -- backpack is not counting down, so it gets the number without the clock.
    item:setDecaying(decaying)
    item:setDurationTime(seconds)
end

-- Only a decaying item has moved on since the snapshot landed; a static one --
-- and a charge count -- still reads exactly what the server said.
local function currentValue(entry, elapsed)
    if not entry then
        return nil, false, 0
    end
    if not entry.decaying then
        return entry.seconds, false, entry.charges
    end
    return entry.seconds - elapsed, true, entry.charges
end

local function apply()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local elapsed = math.floor((g_clock.millis() - snapshotAt) / 1000)

    for slot = InventorySlotFirst, InventorySlotLast do
        local entry = snapshot['i' .. slot]
        applyTo(player:getInventoryItem(slot), entry, currentValue(entry, elapsed))
    end

    for containerId, container in pairs(g_game.getContainers()) do
        for index, item in ipairs(container:getItems()) do
            -- getItems is 1-based in Lua; the server counts slots from 0.
            local entry = snapshot['c' .. containerId .. '.' .. (index - 1)]
            applyTo(item, entry, currentValue(entry, elapsed))
        end
    end
end

-- Container and inventory widgets are rebuilt around a move, and a rebuilt
-- widget points at a fresh Item with no duration on it. The snapshot can
-- easily arrive BEFORE that rebuild, so applying it on arrival alone leaves
-- the overlay blank until the next cycle.
--
-- addEvent rather than calling apply() straight from the signal: the rebuild
-- is still in progress while these fire, so this runs once the current batch
-- of container/inventory events has finished. The flag collapses a burst of
-- them -- a single move emits several -- into one pass.
local applyQueued = false
local function requestApply()
    if applyQueued then
        return
    end

    applyQueued = true
    addEvent(function()
        applyQueued = false
        apply()
    end)
end

-- "i5=512:1:0:2171;c0.3=0:0:14:2260" -- seconds, decaying, charges, server id.
-- Inventory slot 5 counting down with no charges; container 0 slot 3 holding 14
-- charges and no timer. An empty buffer is a valid snapshot meaning "nothing to
-- show", which clears the overlay once the last such item is gone.
local function onOpcode(protocol, opcode, buffer)
    snapshot = {}
    snapshotAt = g_clock.millis()

    for entry in string.gmatch(buffer, '[^;]+') do
        local ref, seconds, decaying, charges, id =
            string.match(entry, '^([^=]+)=(%d+):([01]):(%d+):(%d+)$')

        -- The trailing id is optional on purpose. It only sharpens the
        -- drag case, so a server still running the older three-field script
        -- has to keep working rather than having every entry silently fail to
        -- parse and the overlay vanish entirely.
        if not ref then
            ref, seconds, decaying, charges = string.match(entry, '^([^=]+)=(%d+):([01]):(%d+)$')
        end

        if ref then
            snapshot[ref] = {
                seconds = tonumber(seconds),
                decaying = decaying == '1',
                charges = tonumber(charges),
                id = tonumber(id)
            }
        end
    end

    apply()
end

function init()
    ProtocolGame.registerExtendedOpcode(ITEM_TIMER_OPCODE, onOpcode)

    -- Container and inventory widgets are rebuilt on every refresh, and a
    -- rebuilt widget points at a fresh Item with no duration on it. Rather than
    -- hooking each of those paths, re-apply the cached snapshot on a cycle --
    -- it is idempotent thanks to the elapsed-time subtraction above, and it
    -- self-heals whatever the refresh dropped.
    applyEvent = cycleEvent(apply, 1000)

    connect(Container, {
        onOpen = requestApply,
        onSizeChange = requestApply,
        onUpdateItem = requestApply
    })

    connect(g_game, {
        onInventoryChange = requestApply
    })
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(ITEM_TIMER_OPCODE)

    disconnect(Container, {
        onOpen = requestApply,
        onSizeChange = requestApply,
        onUpdateItem = requestApply
    })

    disconnect(g_game, {
        onInventoryChange = requestApply
    })

    if applyEvent then
        removeEvent(applyEvent)
        applyEvent = nil
    end

    snapshot = {}
    snapshotAt = 0
end
