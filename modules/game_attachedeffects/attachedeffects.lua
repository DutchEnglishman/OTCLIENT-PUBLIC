local function onAttach(effect, owner)
    local category, thingId = AttachedEffectManager.getDataThing(owner)
    local config = AttachedEffectManager.getConfig(effect:getId(), category, thingId)

    if not config then
        g_logger.debug(string.format("[AttachedEffect] onAttach: No config found for effect ID %d (category: %d, thingId: %d)", effect:getId(), category, thingId))
        return
    end

    if config.isThingConfig then
        AttachedEffectManager.executeThingConfig(effect, category, thingId)
    end

    if config.onAttach then
        config.onAttach(effect, owner, config.__onAttach)
    end
end

local function onDetach(effect, oldOwner)
    local category, thingId = AttachedEffectManager.getDataThing(oldOwner)
    local config = AttachedEffectManager.getConfig(effect:getId(), category, thingId)

    if not config then
        g_logger.debug(string.format("[AttachedEffect] onDetach: No config found for effect ID %d (category: %d, thingId: %d)", effect:getId(), category, thingId))
        return
    end

    if config.onDetach then
        config.onDetach(effect, oldOwner, config.__onDetach)
    end
end

local function onOutfitChange(creature, outfit, oldOutfit)
    for _i, effect in pairs(creature:getAttachedEffects()) do
        AttachedEffectManager.executeThingConfig(effect, ThingCategoryCreature, outfit.type)
    end
end

-- The server has no opcode for attached effects in this protocol, so they
-- arrive over an extended opcode as "attach,<creatureId>,<effectId>" or
-- "detach,<creatureId>,<effectId>". Attach is idempotent: the server repeats
-- it for everyone nearby every few seconds, which is how a player who walks
-- up to (or relogs next to) an already-decorated creature gets the effect.
-- A creature this client cannot see yet is simply skipped until the next
-- repeat.
local ATTACHED_EFFECT_OPCODE = 71

-- Bloodlust, Madareth's skill, rides the same opcode as a third verb:
-- "bloodlust,<creatureId>,1" while it runs and ",0" when it ends. Like attach,
-- the server repeats the 1 every second, so a player who walks in halfway
-- through sees him already grown; a repeat asking for the state he is already
-- in or already heading to is dropped. An optional fourth field is the scale
-- to grow to ("bloodlust,<creatureId>,1,1.0625" is the chained demons' faint
-- swell); without it the creature grows to BLOODLUST_SCALE. "pulse,<creature
-- Id>,<scale>,<upMs>,<downMs>" is the same growing with no tint and its own
-- timings, up and straight back down, for a stomp.
--
-- The growing is stepped here rather than handed to setScaleFactor's own ms
-- argument, because that ramp runs from ZERO to the target (Thing::
-- getScaleFactor, thing.h): passing 1.5 with a duration makes him vanish and
-- inflate instead of swelling. Stepping from whatever scale he is on also
-- means an end arriving mid-growth shrinks from there rather than snapping to
-- full size first.
local BLOODLUST_SHADER = 'Monster - Bloodlust'
-- A quarter of a tile bigger each way, not half: 1.25 on a 32px sprite is
-- 40px. The default when the server only says whether Bloodlust is running.
local BLOODLUST_SCALE = 1.25
local BLOODLUST_STEP_MS = 40
local BLOODLUST_GROW_MS = 1200
local BLOODLUST_SHRINK_MS = 900

-- creature id -> {scale, target, stepSize, event, shrink, shaded}
local bloodlust = {}

local function bloodlustStep(creatureId)
    local state = bloodlust[creatureId]
    if not state then
        return
    end

    local creature = g_map.getCreatureById(creatureId)
    if not creature then
        -- Out of view or gone. Nothing to scale and nothing to restore: the
        -- client rebuilds a creature at scale 1 when it comes back, and the
        -- server's repeats start this over if the skill is still running.
        bloodlust[creatureId] = nil
        return
    end

    local remaining = state.target - state.scale
    if math.abs(remaining) <= state.stepSize then
        state.scale = state.target
    else
        state.scale = state.scale + (remaining > 0 and state.stepSize or -state.stepSize)
    end
    creature:setScaleFactor(state.scale)

    if state.scale ~= state.target then
        state.event = scheduleEvent(function() bloodlustStep(creatureId) end, BLOODLUST_STEP_MS)
        return
    end

    state.event = nil
    if state.target == 1 then
        if state.shaded then
            creature:setShader('')
        end
        bloodlust[creatureId] = nil
    end
end

-- Steps the creature from wherever it is to target over durationMs. A
-- target it is already heading for is left alone; back to 1 for something
-- this client never saw grow is nothing to do.
local function scaleTo(creature, target, durationMs)
    local creatureId = creature:getId()
    local state = bloodlust[creatureId]
    if state and state.target == target then
        return
    end
    if not state then
        if target == 1 then
            return
        end
        state = {scale = creature:getScaleFactor()}
        bloodlust[creatureId] = state
    end

    if state.event then
        removeEvent(state.event)
        state.event = nil
    end
    if state.shrink then
        removeEvent(state.shrink)
        state.shrink = nil
    end

    state.target = target
    state.stepSize = math.abs(target - state.scale) / math.max(1, durationMs / BLOODLUST_STEP_MS)
    bloodlustStep(creatureId)
    return state
end

local function setBloodlust(creature, on, scale)
    if on then
        creature:setShader(BLOODLUST_SHADER)
        local state = scaleTo(creature, scale or BLOODLUST_SCALE, BLOODLUST_GROW_MS)
        if state then
            state.shaded = true -- so coming back to 1 takes the red off again
        end
    else
        scaleTo(creature, 1, BLOODLUST_SHRINK_MS)
    end
end

-- "pulse,<creatureId>,<scale>,<upMs>,<downMs>": a swell and back with no
-- tint, on the client's clock from one message -- Annihilon rising onto
-- his toes for a stomp. Whatever shader the creature wears is left alone.
local function pulse(creature, scale, upMs, downMs)
    local creatureId = creature:getId()
    local state = scaleTo(creature, scale, upMs)
    if not state then
        return
    end
    state.shrink = scheduleEvent(function()
        local now = g_map.getCreatureById(creatureId)
        if now then
            scaleTo(now, 1, downMs)
        end
    end, upMs)
end

-- Nothing survives a logout: the creature objects do not, and a timer left
-- running would fire against an id the next session hands to something else.
local function clearBloodlust()
    for creatureId, state in pairs(bloodlust) do
        if state.event then
            removeEvent(state.event)
        end
        if state.shrink then
            removeEvent(state.shrink)
        end
        local creature = g_map.getCreatureById(creatureId)
        if creature then
            creature:setScaleFactor(1)
            creature:setShader('')
        end
    end
    bloodlust = {}
end

local function onExtendedOpcode(protocol, opcode, buffer)
    local pulseId, pulseScale, upMs, downMs = buffer:match('^pulse,(%d+),([%d.]+),(%d+),(%d+)$')
    if pulseId then
        local creature = g_map.getCreatureById(tonumber(pulseId))
        if creature then
            pulse(creature, tonumber(pulseScale), tonumber(upMs), tonumber(downMs))
        end
        return
    end

    local action, creatureId, effectId, scale = buffer:match('^(%a+),(%d+),(%d+),?([%d.]*)$')
    if not action then
        return
    end

    local creature = g_map.getCreatureById(tonumber(creatureId))
    if not creature then
        return
    end

    effectId = tonumber(effectId)
    if action == 'attach' then
        if not creature:getAttachedEffectById(effectId) then
            creature:attachEffect(g_attachedEffects.getById(effectId))
        end
    elseif action == 'detach' then
        creature:detachEffectById(effectId)
    elseif action == 'bloodlust' then
        setBloodlust(creature, effectId == 1, tonumber(scale))
    end
end

-- Floor rarity shine, opcode 72, one message per tile:
-- "on,x,y,z,<rarity>,<clientItemId>" while a rarity item lies there,
-- "off,x,y,z" once the tile is clear. The server repeats "on" every few
-- seconds for every shining tile in view (OTSERV
-- data/scripts/loot_shine/loot_shine.lua), so a shine that stops being
-- refreshed belongs to a tile the player walked away from or whose item
-- vanished without a move event; it is dropped after SHINE_TTL_MS either
-- way and comes back with the next repeat if it was only out of view. A
-- tile carrying an effect survives the map re-send that happens every step
-- (Tile::canErase), so attaching once is enough.
--
-- The glint runs along the item's long axis, read once per item id from
-- its sprite silhouette: a bow lying NE-SW gets a glint travelling NE to
-- SW, a blade lying flat gets one running west to east, and anything squat
-- gets the default NW to SE.
local RARITY_SHINE_OPCODE = 72
local SHINE_TTL_MS = 7000
-- rarity id (OTSERV upgrade_system_const.lua) -> the first of that rarity's
-- four effects; the axis is added to it (effects.lua registers 20-31).
local SHINE_EFFECT_BASE = { [2] = 20, [3] = 24, [4] = 28 }
local SHINE_AXIS_NWSE, SHINE_AXIS_NESW, SHINE_AXIS_WE, SHINE_AXIS_NS = 0, 1, 2, 3
local SHINE_EFFECT_IDS = {}
for id = 20, 31 do
    table.insert(SHINE_EFFECT_IDS, id)
end
local shines = {}
local shineAxisByItem = {}

-- Principal axis of the sprite's opaque pixels, binned to the four glint
-- directions. nil while the sprite has not loaded yet, so the caller does
-- not cache a guess.
local function readShineAxis(clientId)
    local thingType = g_things.getThingType(clientId, ThingCategoryItem)
    if not thingType then
        return SHINE_AXIS_NWSE
    end

    local sprites = thingType:getSprites()
    local width, height = thingType:getWidth(), thingType:getHeight()
    local side = g_gameConfig.getSpriteSize()
    local n, sx, sy, sxx, syy, sxy = 0, 0, 0, 0, 0, 0
    for h = 0, height - 1 do
        for w = 0, width - 1 do
            -- Sprite index for the first layer, pattern and phase; sprite 0
            -- is the bottom-right cell of a multi-cell item.
            local spriteId = sprites[h * width + w + 1]
            if spriteId and spriteId > 0 then
                local mask = g_sprites.getSpriteAlphaMask(spriteId)
                if mask == '' then
                    return nil
                end
                local ox, oy = (width - 1 - w) * side, (height - 1 - h) * side
                for i = 1, #mask do
                    if mask:byte(i) >= 128 then
                        local x = ox + (i - 1) % side
                        local y = oy + math.floor((i - 1) / side)
                        n = n + 1
                        sx, sy = sx + x, sy + y
                        sxx, syy, sxy = sxx + x * x, syy + y * y, sxy + x * y
                    end
                end
            end
        end
    end

    if n < 16 then
        return SHINE_AXIS_NWSE
    end
    local mx, my = sx / n, sy / n
    local cxx, cyy, cxy = sxx / n - mx * mx, syy / n - my * my, sxy / n - mx * my
    local half = (cxx + cyy) / 2
    local spread = math.sqrt(math.max(0, half * half - (cxx * cyy - cxy * cxy)))
    local major, minor = half + spread, half - spread
    if major < 1.6 * minor then
        return SHINE_AXIS_NWSE
    end

    -- Screen y grows downwards, so a positive angle leans NW-SE.
    local degrees = math.deg(0.5 * math.atan2(2 * cxy, cxx - cyy))
    if degrees > 67.5 or degrees < -67.5 then
        return SHINE_AXIS_NS
    elseif degrees > 22.5 then
        return SHINE_AXIS_NWSE
    elseif degrees < -22.5 then
        return SHINE_AXIS_NESW
    end
    return SHINE_AXIS_WE
end

local function shineAxisFor(clientId)
    local axis = shineAxisByItem[clientId]
    if axis == nil then
        axis = readShineAxis(clientId)
        if axis == nil then
            return SHINE_AXIS_NWSE
        end
        shineAxisByItem[clientId] = axis
    end
    return axis
end

local function clearShine(tile)
    for _, id in ipairs(SHINE_EFFECT_IDS) do
        tile:detachEffectById(id)
    end
end

local function onRarityShineOpcode(protocol, opcode, buffer)
    local action, x, y, z, rarity, itemId = buffer:match('^(%a+),(%d+),(%d+),(%d+),?(%d*),?(%d*)$')
    if not action then
        return
    end

    local key = x .. ',' .. y .. ',' .. z
    local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    local tile = g_map.getTile(pos)
    if action ~= 'on' or not tile then
        if tile then
            clearShine(tile)
        end
        shines[key] = nil
        return
    end

    local base = SHINE_EFFECT_BASE[tonumber(rarity)]
    if not base then
        return
    end
    local effectId = base + shineAxisFor(tonumber(itemId) or 0)
    if not tile:getAttachedEffectById(effectId) then
        local effect = g_attachedEffects.getById(effectId)
        if not effect then
            return
        end
        clearShine(tile)
        tile:attachEffect(effect)
    end
    shines[key] = { pos = pos, seen = g_clock.millis() }
end

-- The client cannot tell a rare item from a common one, but it can tell an
-- item from bare ground, and a shine over nothing is wrong whatever the
-- server said.
local function holdsAnItem(tile)
    for _, item in ipairs(tile:getItems()) do
        if not item:isGround() then
            return true
        end
    end
    return false
end

local function expireShines()
    local now = g_clock.millis()
    for key, shine in pairs(shines) do
        local tile = g_map.getTile(shine.pos)
        local stale = now - shine.seen > SHINE_TTL_MS
        if stale or (tile and not holdsAnItem(tile)) then
            if tile then
                clearShine(tile)
            end
            shines[key] = nil
        end
    end
end

-- Timed effects on a tile, opcode 73: "on,x,y,z,<effectId>,<remainingMs>"
-- attaches the effect and lets it run out on its own after remainingMs;
-- "off,x,y,z,<effectId>" ends it early. Used for the Tainted and Corrupted
-- spawn portals (OTSERV global.lua, MonsterVariants.spawnWithEffect): a
-- looping attached effect has no seam, where the same dat effect replayed
-- as a magic effect goes dark between plays. The server repeats "on" every
-- second with the time left, so a player who walks up halfway through sees
-- the portal for the rest of its life; a repeat for an effect already on
-- the tile is ignored, its timer was set by the first one.
--
-- remainingMs 0 means "held": the effect stays for as long as the server
-- keeps repeating "on" and is dropped TILE_HOLD_TTL_MS after the last
-- repeat, the animation never restarting in between. The tether beam
-- between Latrivan and Golgordan (OTSERV brothers_link.lua) is laid this
-- way, re-sent every second along whatever line the two stand on now.
-- Effects in the same replace group are one-per-tile: laying a beam
-- segment flowing the other way takes the old one off first.
local TILE_EFFECT_OPCODE = 73
local TILE_HOLD_TTL_MS = 1200
local TILE_EFFECT_GROUPS = {
    { first = 50, last = 130 }, -- tether beam, one segment per entry/exit pair
    { first = 132, last = 163 }, -- flamethrower jet, one segment per tile (tip becomes body as it grows)
    { first = 164, last = 195 }, -- blaze jet, the same
}
-- "x,y,z:effectId" -> {pos, effectId, seen}
local heldTileEffects = {}

local function clearGroupMates(tile, effectId)
    for _, group in ipairs(TILE_EFFECT_GROUPS) do
        if effectId >= group.first and effectId <= group.last then
            for id = group.first, group.last do
                if id ~= effectId then
                    tile:detachEffectById(id)
                end
            end
        end
    end
end

-- The ball riding the Latrivan/Golgordan tether runs on THIS clock, not the
-- server's: "ballrun,<runId>,<msPerTile>,<startIndex>,<z>,<x:y:shape|...>"
-- hands over the whole route once. The route is split into straight runs
-- (tiles in one direction) and the orb is glided over each run in a single
-- AttachedEffect:move, which the engine interpolates every rendered frame,
-- so it moves as smoothly as the display allows; the only hand-offs are
-- where the route bends. A hand-off per tile from the server would carry
-- the network's jitter into every step, and per-tile sprite frames would
-- jump pixels. The server re-sends the same runId with a new route and
-- the index it has reached when the beam bends mid-flight;
-- "ballstop,<runId>" ends it early.
local BALL_EFFECT = 131
-- runId -> {event, pos}
local ballRuns = {}

local function ballRunClear(run)
    if run.event then
        removeEvent(run.event)
        run.event = nil
    end
    if run.pos then
        local tile = g_map.getTile(run.pos)
        if tile then
            tile:detachEffectById(BALL_EFFECT)
        end
        run.pos = nil
    end
end

-- Glides the orb from tiles[index] to the end of the straight run it
-- starts, then schedules the next run from there.
local function ballRunStep(runId, tiles, index, msPerTile)
    local run = ballRuns[runId]
    if not run then
        return
    end
    ballRunClear(run)

    local from = tiles[index]
    if not from then
        ballRuns[runId] = nil
        return
    end

    local last, dx, dy = index, nil, nil
    while tiles[last + 1] do
        local ndx, ndy = tiles[last + 1].x - tiles[last].x, tiles[last + 1].y - tiles[last].y
        if dx and (ndx ~= dx or ndy ~= dy) then
            break
        end
        dx, dy, last = ndx, ndy, last + 1
    end
    local hops = last - index
    local duration = math.max(1, hops) * msPerTile

    local tile = g_map.getTile(from)
    if tile then
        local effect = g_attachedEffects.getById(BALL_EFFECT)
        if effect then
            effect:setDuration(duration)
            tile:attachEffect(effect)
            if hops > 0 then
                effect:move(from, tiles[last])
            end
            run.pos = from
        end
    end

    if hops == 0 then
        run.event = scheduleEvent(function() ballRunStep(runId, tiles, index + 1, msPerTile) end, duration)
        return
    end
    run.event = scheduleEvent(function() ballRunStep(runId, tiles, last, msPerTile) end, duration)
end

local function onBallRun(buffer)
    local runId, msPerTile, startIndex, z, route = buffer:match('^ballrun,([^,]+),(%d+),(%d+),(%d+),(.+)$')
    if not runId then
        return
    end
    local tiles = {}
    for x, y, shape in route:gmatch('(%d+):(%d+):(%d+)') do
        table.insert(tiles, { x = tonumber(x), y = tonumber(y), z = tonumber(z), shape = tonumber(shape) })
    end
    if ballRuns[runId] then
        ballRunClear(ballRuns[runId])
    end
    ballRuns[runId] = {}
    ballRunStep(runId, tiles, tonumber(startIndex), tonumber(msPerTile))
end

local function onBallStop(runId)
    local run = ballRuns[runId]
    if run then
        ballRunClear(run)
        ballRuns[runId] = nil
    end
end

local function clearBallRuns()
    for _, run in pairs(ballRuns) do
        ballRunClear(run)
    end
    ballRuns = {}
end

-- Puts a tile effect on and remembers it: remainingMs 0 is "held" until the
-- server stops repeating it (see TILE_HOLD_TTL_MS), anything else runs out
-- on its own. A repeat for an effect already on the tile only refreshes
-- the hold.
local function tileEffectKey(pos, effectId)
    return pos.x .. ',' .. pos.y .. ',' .. pos.z .. ':' .. effectId
end

local function holdTileEffect(pos, effectId, remainingMs)
    local tile = g_map.getTile(pos)
    if not tile then
        return
    end
    if remainingMs == 0 then
        heldTileEffects[tileEffectKey(pos, effectId)] = { pos = pos, effectId = effectId, seen = g_clock.millis() }
    end
    if tile:getAttachedEffectById(effectId) then
        return
    end

    local effect = g_attachedEffects.getById(effectId)
    if not effect then
        return
    end
    if remainingMs > 0 then
        effect:setDuration(remainingMs)
    end
    clearGroupMates(tile, effectId)
    tile:attachEffect(effect)
end

local function dropTileEffect(pos, effectId)
    local tile = g_map.getTile(pos)
    if tile then
        tile:detachEffectById(effectId)
    end
    heldTileEffects[tileEffectKey(pos, effectId)] = nil
end

-- Flamethrower jets (OTSERV flamethrowers.lua, the textured styles) grow
-- and retract on THIS clock. "jetgrow,<runId>,<msPerTile>,<z>,<nozzle
-- id>,<head id>,<x:y|x:y|...>" hands over the whole jet, nearest tile
-- first, once: the first tile becomes the nozzle, and a gliding tip (the
-- look's tip image, drawn above all) and a tail (a body, one tile behind
-- it, drawn below the bodies) are glided together from the SECOND tile to
-- the last in one AttachedEffect:move each,
-- and each tile is lit as a held body when the anchor is JET_HEAD_LEAD
-- past the tile's near edge, which is when the tile's flat far edge has
-- come under the tip's full-width start; until then the gap between the
-- last body and the tip is the tail showing through. The held tip takes
-- the gliding pair's place on arrival. "jetretract,..." is the same
-- backwards: the held tip comes off, the pair glides from the last tile
-- back to the second, each body coming off as the anchor passes back to
-- the same point over it, and the spout takes over the first tile at the
-- end. Everything lit by a run is held the way the server's own "on"
-- holds it, and the run refreshes those holds itself while it lasts,
-- since the server says nothing per tile during a run. A jet of one tile
-- is never sent: the spout is the whole burst.
local BLAZE_BODY, BLAZE_TIP, BLAZE_SPOUT = 1, 2, 3
-- 0.5 leaves margin both ways for a scheduled event landing a frame or
-- two late: the tail reaches 0.85 tile back, so the tile is still covered
-- until 0.85, and the tip's full-width start covers the tile's far edge
-- from 0.65, with only its fray showing a sliver of that edge before.
local JET_HEAD_LEAD = 0.5
local JET_TAIL_OFFSET = 8
local BLAZE_REFRESH_MS = 500
-- runId -> {events, frontId, frontPos, tailPos, lit}
local blazeRuns = {}

local function blazeClear(run)
    for _, event in ipairs(run.events) do
        removeEvent(event)
    end
    run.events = {}
    if run.frontPos then
        local tile = g_map.getTile(run.frontPos)
        if tile then
            tile:detachEffectById(run.frontId)
        end
        run.frontPos = nil
    end
    if run.tailPos then
        local tile = g_map.getTile(run.tailPos)
        if tile then
            tile:detachEffectById(run.frontId + JET_TAIL_OFFSET)
        end
        run.tailPos = nil
    end
end

local function clearBlazeRuns()
    for _, run in pairs(blazeRuns) do
        blazeClear(run)
    end
    blazeRuns = {}
end

local function blazeAt(run, ms, fn)
    if ms <= 0 then
        fn()
        return
    end
    table.insert(run.events, scheduleEvent(fn, ms))
end

-- Attaches one gliding effect to `at` and sends it along the same path as
-- the anchor. Returns the tile position it went on.
local function blazeGlide(id, at, from, to, durationMs)
    local tile = g_map.getTile(at)
    local effect = tile and g_attachedEffects.getById(id)
    if not effect then
        return nil
    end
    effect:setDuration(math.max(1, durationMs))
    tile:attachEffect(effect)
    if durationMs > 0 then
        effect:move(from, to)
    end
    return at
end

-- The tip rides on the anchor tile. The tail is drawn one tile behind it
-- and has to be submitted before the bodies it overlaps (effects.lua
-- explains why it cannot simply sit below them): the map draws tiles in
-- coordinate order, so for a jet flowing east or south it goes on the tile
-- behind the anchor, drawn earlier, and for west or north on the anchor
-- itself, its registered offset drawing it one tile behind.
local function blazeFront(run, from, to, durationMs, step)
    run.frontPos = blazeGlide(run.frontId, from, from, to, durationMs)
    local tailAt = from
    if step.x > 0 or step.y > 0 then
        tailAt = { x = from.x - step.x, y = from.y - step.y, z = from.z }
    end
    run.tailPos = blazeGlide(run.frontId + JET_TAIL_OFFSET, tailAt, from, to, durationMs)
end

local function jetStep(tiles)
    return { x = tiles[2].x - tiles[1].x, y = tiles[2].y - tiles[1].y }
end

local function blazeLight(run, pos, effectId)
    holdTileEffect(pos, effectId, 0)
    run.lit[tileEffectKey(pos, effectId)] = true
end

local function blazeRefresh(runId, run)
    if blazeRuns[runId] ~= run then
        return
    end
    local now = g_clock.millis()
    for key in pairs(run.lit) do
        local held = heldTileEffects[key]
        if held then
            held.seen = now
        end
    end
    blazeAt(run, BLAZE_REFRESH_MS, function() blazeRefresh(runId, run) end)
end

local function blazeStart(buffer, verb)
    local runId, msPerTile, z, base, front, route = buffer:match('^' .. verb .. ',([^,]+),(%d+),(%d+),(%d+),(%d+),(.+)$')
    if not runId then
        return
    end
    local tiles = {}
    for x, y in route:gmatch('(%d+):(%d+)') do
        table.insert(tiles, { x = tonumber(x), y = tonumber(y), z = tonumber(z) })
    end
    if blazeRuns[runId] then
        blazeClear(blazeRuns[runId])
    end
    local run = { events = {}, frontId = tonumber(front), lit = {} }
    blazeRuns[runId] = run
    blazeRefresh(runId, run)
    return run, runId, tiles, tonumber(msPerTile), tonumber(base)
end

local function blazeEnd(runId, run)
    blazeClear(run)
    if blazeRuns[runId] == run then
        blazeRuns[runId] = nil
    end
end

local function onJetGrow(buffer)
    local run, runId, tiles, msPerTile, base = blazeStart(buffer, 'jetgrow')
    if not run then
        return
    end
    local n = #tiles
    if n < 2 then
        blazeEnd(runId, run)
        return
    end

    -- The warning tile becomes the nozzle and the tip sets off from the
    -- tile after it, never from over the nozzle.
    blazeLight(run, tiles[1], base)
    blazeFront(run, tiles[2], tiles[n], (n - 2) * msPerTile, jetStep(tiles))
    for k = 2, n - 1 do
        blazeAt(run, (k - 2 + JET_HEAD_LEAD) * msPerTile, function() blazeLight(run, tiles[k], base + BLAZE_BODY) end)
    end
    blazeAt(run, (n - 2) * msPerTile, function()
        blazeEnd(runId, run)
        holdTileEffect(tiles[n], base + BLAZE_TIP, 0)
    end)
end

local function onJetRetract(buffer)
    local run, runId, tiles, msPerTile, base = blazeStart(buffer, 'jetretract')
    if not run then
        return
    end
    local n = #tiles
    if n < 2 then
        blazeEnd(runId, run)
        holdTileEffect(tiles[1], base + BLAZE_SPOUT, 0)
        return
    end

    for k = 1, n - 1 do
        run.lit[tileEffectKey(tiles[k], base + (k == 1 and 0 or BLAZE_BODY))] = true
    end
    -- Back to the tile after the nozzle, then the spout takes the nozzle's
    -- place; the tip never rides over the first tile.
    dropTileEffect(tiles[n], base + BLAZE_TIP)
    blazeFront(run, tiles[n], tiles[2], (n - 2) * msPerTile, jetStep(tiles))
    for k = n - 1, 2, -1 do
        blazeAt(run, (n - k - JET_HEAD_LEAD) * msPerTile, function() dropTileEffect(tiles[k], base + BLAZE_BODY) end)
    end
    blazeAt(run, (n - 2) * msPerTile, function()
        blazeEnd(runId, run)
        holdTileEffect(tiles[1], base + BLAZE_SPOUT, 0)
    end)
end

local function onTileEffectOpcode(protocol, opcode, buffer)
    if buffer:sub(1, 8) == 'jetgrow,' then
        onJetGrow(buffer)
        return
    end
    if buffer:sub(1, 11) == 'jetretract,' then
        onJetRetract(buffer)
        return
    end
    if buffer:sub(1, 8) == 'ballrun,' then
        onBallRun(buffer)
        return
    end
    local stopId = buffer:match('^ballstop,([^,]+)$')
    if stopId then
        onBallStop(stopId)
        return
    end

    -- "area,x,y,z,<firstId>,<radius>,<ms>[,<mask>]": a square of timed
    -- tile effects centred on x,y, piece (row, col) of the square being
    -- firstId + row * side + col, the way Annihilon's shatter (effects.lua)
    -- is cut up. The mask, one '1' or '0' per tile row by row, says which
    -- tiles get their piece (the server leaves out walls and what is behind
    -- them); without it every tile does. A tile outside what this client
    -- has loaded is skipped.
    local ax, ay, az, firstId, radius, areaMs, mask = buffer:match('^area,(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),?([01]*)$')
    if ax then
        ax, ay, az, firstId, radius, areaMs = tonumber(ax), tonumber(ay), tonumber(az), tonumber(firstId), tonumber(radius), tonumber(areaMs)
        local side = radius * 2 + 1
        for row = 0, side - 1 do
            for col = 0, side - 1 do
                local index = row * side + col
                if mask == '' or mask:sub(index + 1, index + 1) == '1' then
                    holdTileEffect({ x = ax + col - radius, y = ay + row - radius, z = az }, firstId + index, areaMs)
                end
            end
        end
        return
    end

    local action, x, y, z, effectId, remainingMs = buffer:match('^(%a+),(%d+),(%d+),(%d+),(%d+),?(%d*)$')
    if not action then
        return
    end

    local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    if action == 'off' then
        dropTileEffect(pos, tonumber(effectId))
    elseif action == 'on' then
        holdTileEffect(pos, tonumber(effectId), tonumber(remainingMs) or 0)
    end
end

local function expireHeldTileEffects()
    local now = g_clock.millis()
    for key, held in pairs(heldTileEffects) do
        if now - held.seen > TILE_HOLD_TTL_MS then
            local tile = g_map.getTile(held.pos)
            if tile then
                tile:detachEffectById(held.effectId)
            end
            heldTileEffects[key] = nil
        end
    end
end

controller = Controller:new()

function controller:onGameStart()
    ProtocolGame.registerExtendedOpcode(ATTACHED_EFFECT_OPCODE, onExtendedOpcode)
    ProtocolGame.registerExtendedOpcode(RARITY_SHINE_OPCODE, onRarityShineOpcode)
    ProtocolGame.registerExtendedOpcode(TILE_EFFECT_OPCODE, onTileEffectOpcode)
    shines = {}
    heldTileEffects = {}
    controller:cycleEvent(expireShines, 250)
    controller:cycleEvent(expireHeldTileEffects, 250)

    controller:registerEvents(LocalPlayer, {
        onOutfitChange = onOutfitChange
    })

    controller:registerEvents(Creature, {
        onOutfitChange = onOutfitChange
    })

    controller:registerEvents(AttachedEffect, {
        onAttach = onAttach,
        onDetach = onDetach
    })

    -- uncomment this line to apply an effect on the local player, just for testing purposes.
    --[[g_game.getLocalPlayer():attachEffect(g_attachedEffects.getById(1))
    g_game.getLocalPlayer():attachEffect(g_attachedEffects.getById(2))
    g_game.getLocalPlayer():attachEffect(g_attachedEffects.getById(3))
    g_game.getLocalPlayer():getTile():attachEffect(g_attachedEffects.getById(1))
    g_game.getLocalPlayer():attachParticleEffect("creature-effect")]]
end

function controller:onGameEnd()
    ProtocolGame.unregisterExtendedOpcode(ATTACHED_EFFECT_OPCODE)
    ProtocolGame.unregisterExtendedOpcode(RARITY_SHINE_OPCODE)
    ProtocolGame.unregisterExtendedOpcode(TILE_EFFECT_OPCODE)
    shines = {}
    heldTileEffects = {}
    clearBallRuns()
    clearBlazeRuns()
    clearBloodlust()
    -- g_game.getLocalPlayer():clearAttachedEffects()
end

function controller:onTerminate()
    g_attachedEffects.clear()
end

function getCategory(id)
    local effect = AttachedEffectManager.get(id)
    if effect then
        return effect.thingCategory
    end
    return nil
end

function getTexture(id)
    local effect = AttachedEffectManager.get(id)
    if effect and effect.thingCategory == 5 then
        return effect.thingId
    end
end

function getName(id)
    if type(id) == "number" then
        local effect = AttachedEffectManager.get(id)
        if effect then
            return effect.name
        else
            return "None"
        end
    else
        return "None"
    end
end

function thingId(id)
    if type(id) == "number" then
        local effect = AttachedEffectManager.get(id)
        if effect then
            return effect.thingId
        else
            return "None"
        end
    else
        return "None"
    end
end
