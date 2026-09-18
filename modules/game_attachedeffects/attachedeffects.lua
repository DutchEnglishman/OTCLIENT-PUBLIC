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

-- "lunge,<creatureId>,<dx>,<dy>,<outMs>,<backMs>": the body leans dx,dy
-- sprite pixels over outMs and settles back over backMs, on this clock
-- from one message -- Lord Morvane putting his weight behind a throw, the
-- way the pulse is Annihilon rising for a stomp. Only the drawn outfit
-- moves (Creature::setSpriteShift): the creature, its tile and the tile's
-- effects stay where they are. Stepped every frame like the tether ball.
-- A client built without the binding shows nothing and is otherwise
-- unaffected.
local lunges = {} -- creature id -> event

local function lungeStep(creatureId, dx, dy, outMs, backMs, startedAt)
    local creature = g_map.getCreatureById(creatureId)
    if not creature then
        lunges[creatureId] = nil
        return
    end
    local elapsed = g_clock.millis() - startedAt
    local f
    if elapsed < outMs then
        f = elapsed / outMs
        f = 1 - (1 - f) * (1 - f) -- fast off the mark, easing into the lean
    elseif elapsed < outMs + backMs then
        f = 1 - (elapsed - outMs) / backMs
    else
        creature:setSpriteShift(0, 0)
        lunges[creatureId] = nil
        return
    end
    creature:setSpriteShift(math.floor(dx * f + 0.5), math.floor(dy * f + 0.5))
    lunges[creatureId] = scheduleEvent(function() lungeStep(creatureId, dx, dy, outMs, backMs, startedAt) end, 1)
end

local function lunge(creature, dx, dy, outMs, backMs)
    if not creature.setSpriteShift then
        return
    end
    local creatureId = creature:getId()
    if lunges[creatureId] then
        removeEvent(lunges[creatureId])
    end
    lungeStep(creatureId, dx, dy, math.max(1, outMs), math.max(1, backMs), g_clock.millis())
end

-- "hop,<creatureId>,<fromDx>,<fromDy>,<ms>,<height>": the body is drawn
-- fromDx,fromDy sprite pixels from where the creature now stands (the
-- tile it was just moved from, in pixels) and springs to its place over
-- ms in an arc height px high -- Lord Morvane leaping back before a
-- dagger burst. The server sends it right after moving him, so the move
-- itself is never seen and the leap is what shows. One shift animation per
-- creature: a hop cuts a lunge short and the other way round.
local function hopStep(creatureId, dx, dy, ms, height, startedAt)
    local creature = g_map.getCreatureById(creatureId)
    if not creature then
        lunges[creatureId] = nil
        return
    end
    local f = (g_clock.millis() - startedAt) / ms
    if f >= 1 then
        creature:setSpriteShift(0, 0)
        lunges[creatureId] = nil
        return
    end
    local eased = f * f * (3 - 2 * f)
    local x = dx * (1 - eased)
    local y = dy * (1 - eased) - height * math.sin(math.pi * f)
    creature:setSpriteShift(math.floor(x + 0.5), math.floor(y + 0.5))
    lunges[creatureId] = scheduleEvent(function() hopStep(creatureId, dx, dy, ms, height, startedAt) end, 1)
end

local function hop(creature, dx, dy, ms, height)
    if not creature.setSpriteShift then
        return
    end
    local creatureId = creature:getId()
    if lunges[creatureId] then
        removeEvent(lunges[creatureId])
    end
    hopStep(creatureId, dx, dy, math.max(1, ms), height, g_clock.millis())
end

local function clearLunges()
    for creatureId, event in pairs(lunges) do
        removeEvent(event)
        local creature = g_map.getCreatureById(creatureId)
        if creature and creature.setSpriteShift then
            creature:setSpriteShift(0, 0)
        end
    end
    lunges = {}
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
    local lungeId, dx, dy, outMs, backMs = buffer:match('^lunge,(%d+),(-?%d+),(-?%d+),(%d+),(%d+)$')
    if lungeId then
        local creature = g_map.getCreatureById(tonumber(lungeId))
        if creature then
            lunge(creature, tonumber(dx), tonumber(dy), tonumber(outMs), tonumber(backMs))
        end
        return
    end
    local hopId, fromDx, fromDy, hopMs, height = buffer:match('^hop,(%d+),(-?%d+),(-?%d+),(%d+),(%d+)$')
    if hopId then
        local creature = g_map.getCreatureById(tonumber(hopId))
        if creature then
            hop(creature, tonumber(fromDx), tonumber(fromDy), tonumber(hopMs), tonumber(height))
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
-- way and comes back with the next repeat if it was only out of view.
--
-- The shine is a fragment shader worn by the item itself
-- (game_shaders/shaders/fragment/rarity_shine_*.frag), not a texture laid over
-- the tile, and that is what makes it fit the weapon. The shader only ever
-- runs on the item's own sprite quad and discards where the sprite is
-- transparent, so it covers every pixel of the piece -- including the cells of
-- a 2x2 sprite that reach a tile up and left of the one it stands on
-- (ThingType::draw subtracts (m_size - 1) * 32) -- and not one pixel of the
-- bare tile around it. A 32x32 texture on the tile could do neither: it
-- painted the whole square and only ever the square, and needed the item's
-- long axis guessed from its silhouette to choose a sweep direction. The
-- shader is handed the silhouette by the hardware, so that guesswork is gone.
local RARITY_SHINE_OPCODE = 72
local SHINE_TTL_MS = 7000
-- rarity id (OTSERV upgrade_system_const.lua) -> the shader registered for it
-- in game_shaders (shaders.lua, ITEM_SHADERS). Common gets none.
local SHINE_SHADERS = {
    [2] = 'Item - Rarity Shine Rare',
    [3] = 'Item - Rarity Shine Epic',
    [4] = 'Item - Rarity Shine Legendary',
}
local shines = {}

-- The server names the tile and the client id of the piece lying on it, which
-- is as fine a grain as the 8.6 tile packet allows: two items of one id on a
-- tile are the same item as far as the client knows and both wear the shine.
-- The tile-wide texture lit everything on the tile regardless, so this is the
-- narrower of the two.
local function wearShine(tile, itemId, shader)
    for _, item in ipairs(tile:getItems()) do
        if not item:isGround() and item:getId() == itemId then
            item:setShader(shader)
        end
    end
end

-- An empty name is how Thing::setShader spells "none".
local function clearShine(tile, itemId)
    wearShine(tile, itemId, '')
end

local function onRarityShineOpcode(protocol, opcode, buffer)
    local action, x, y, z, rarity, itemId = buffer:match('^(%a+),(%d+),(%d+),(%d+),?(%d*),?(%d*)$')
    if not action then
        return
    end

    -- Whatever this tile was wearing comes off first, so a tile whose rarity
    -- or whose item changed does not keep the old shader on the old id. A
    -- plain repeat for an unchanged tile puts the same shader straight back
    -- below, within this call, so nothing is drawn in between.
    local key = x .. ',' .. y .. ',' .. z
    local previous = shines[key]
    if previous then
        local previousTile = g_map.getTile(previous.pos)
        if previousTile then
            clearShine(previousTile, previous.itemId)
        end
        shines[key] = nil
    end

    local shader = SHINE_SHADERS[tonumber(rarity)]
    itemId = tonumber(itemId)
    if action ~= 'on' or not shader or not itemId then
        return
    end

    local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    shines[key] = { pos = pos, itemId = itemId, shader = shader, seen = g_clock.millis() }

    local tile = g_map.getTile(pos)
    if tile then
        wearShine(tile, itemId, shader)
    end
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

-- Puts the shader back as well as dropping shines that stopped being
-- refreshed. Back, because a re-described tile is cleaned before its contents
-- are rebuilt, and the items come back as new objects wearing nothing
-- (ProtocolGame::setTileDescription calls Map::cleanTile first): that happens
-- to the row or column each step uncovers, and to everything in view on a
-- floor change or a teleport, so putting the shader on once is not enough.
-- Cheap to repeat -- only the few tiles the server named are visited, and
-- setShader is a name lookup and a byte -- which is why this rides the
-- expiry pass instead of hooking every route an item can arrive by.
local function refreshShines()
    local now = g_clock.millis()
    for key, shine in pairs(shines) do
        local tile = g_map.getTile(shine.pos)
        if now - shine.seen > SHINE_TTL_MS or (tile and not holdsAnItem(tile)) then
            if tile then
                clearShine(tile, shine.itemId)
            end
            shines[key] = nil
        elseif tile then
            wearShine(tile, shine.itemId, shine.shader)
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

-- Lord Morvane's throws (OTSERV data/scripts/boss_skills/morvane_throws.lua)
-- run on THIS clock from one message each, like the tether ball, the
-- server stepping the damage along the same figures on its own.
--
-- "axes,<runId>,<x>,<y>,<z>,<angle>,<reach>,<halfWidth>,<flightMs>": two
-- axes leave the tile x,y,z together and fly a figure of eight lying
-- along <angle> (centidegrees in screen sense: 0 east, 9000 south),
-- <reach> centitiles long and <halfWidth> centitiles to either side at
-- the widest, one on each mirror image of the curve, so they cross at the
-- waist, meet again at the far end and come back to the thrower. Each is
-- an effect on the throw tile whose offset is recomputed every frame from
-- the curve; lemniscate() below is a copy of the server's, and the two
-- must stay the same or the warning and the damage part company with the
-- picture. A shadow rides the ground under each axe, the axe itself
-- AXE_LIFT_PX above it.
local AXE_EFFECTS = { 288, 289 }
local AXE_SHADOW_EFFECTS = { 299, 300 }
local AXE_LIFT_PX = 9
local AXE_SAMPLES = 600
local axeRuns = {} -- runId -> {event, pos, startedAt, flightMs, points, axes}

-- The curve as points at equal steps of ARC LENGTH, in tiles from the
-- throw tile's centre, each with its mirror image (mx, my). Bernoulli's
-- lemniscate with its near end on the thrower, the far lobe reaching
-- `reach`, scaled sideways so the lobes are halfWidth wide.
local function lemniscate(angle, reach, halfWidth, samples)
    local a = reach / 2
    local k = halfWidth / (a * 0.35355)
    local cosA, sinA = math.cos(angle), math.sin(angle)
    local raw = {}
    local n = 720
    for i = 0, n do
        local t = math.pi + 2 * math.pi * i / n
        local d = 1 + math.sin(t) ^ 2
        raw[#raw + 1] = { x = a * math.cos(t) / d + a, y = a * k * math.sin(t) * math.cos(t) / d }
    end
    local lengths = { 0 }
    for i = 2, #raw do
        local dx, dy = raw[i].x - raw[i - 1].x, raw[i].y - raw[i - 1].y
        lengths[i] = lengths[i - 1] + math.sqrt(dx * dx + dy * dy)
    end
    local total = lengths[#raw]
    local points = {}
    local j = 2
    for s = 0, samples do
        local target = total * s / samples
        while j < #raw and lengths[j] < target do
            j = j + 1
        end
        local span = lengths[j] - lengths[j - 1]
        local f = span > 0 and (target - lengths[j - 1]) / span or 0
        local x = raw[j - 1].x + (raw[j].x - raw[j - 1].x) * f
        local y = raw[j - 1].y + (raw[j].y - raw[j - 1].y) * f
        points[s + 1] = { x = x * cosA - y * sinA, y = x * sinA + y * cosA, mx = x * cosA + y * sinA, my = x * sinA - y * cosA }
    end
    return points
end

local function axeRunClear(run)
    if run.event then
        removeEvent(run.event)
        run.event = nil
    end
    local tile = g_map.getTile(run.pos)
    if tile then
        for _, axe in ipairs(run.axes) do
            tile:detachEffect(axe.blade)
            tile:detachEffect(axe.shadow)
        end
    end
    run.axes = {}
end

local function axeRunStep(runId)
    local run = axeRuns[runId]
    if not run then
        return
    end
    local elapsed = g_clock.millis() - run.startedAt
    if elapsed >= run.flightMs then
        axeRunClear(run)
        axeRuns[runId] = nil
        return
    end
    local s = elapsed / run.flightMs * (#run.points - 1)
    local i = math.floor(s)
    local f = s - i
    local p, q = run.points[i + 1], run.points[math.min(i + 2, #run.points)]
    for n, axe in ipairs(run.axes) do
        local x, y
        if n == 1 then
            x, y = p.x + (q.x - p.x) * f, p.y + (q.y - p.y) * f
        else
            x, y = p.mx + (q.mx - p.mx) * f, p.my + (q.my - p.my) * f
        end
        local px, py = math.floor(x * 32 + 0.5), math.floor(y * 32 + 0.5)
        axe.blade:setOffset(-px, -py + AXE_LIFT_PX)
        axe.shadow:setOffset(-px, -py)
    end
    run.event = scheduleEvent(function() axeRunStep(runId) end, 1)
end

local function onAxes(buffer)
    local runId, x, y, z, angle, reach, halfWidth, flightMs = buffer:match('^axes,([^,]+),(%d+),(%d+),(%d+),(-?%d+),(%d+),(%d+),(%d+)$')
    if not runId then
        return
    end
    local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    local tile = g_map.getTile(pos)
    if not tile then
        return
    end
    if axeRuns[runId] then
        axeRunClear(axeRuns[runId])
    end
    local run = {
        pos = pos, startedAt = g_clock.millis(), flightMs = tonumber(flightMs), axes = {},
        points = lemniscate(math.rad(tonumber(angle) / 100), tonumber(reach) / 100, tonumber(halfWidth) / 100, AXE_SAMPLES)
    }
    for n = 1, 2 do
        local blade = g_attachedEffects.getById(AXE_EFFECTS[n])
        local shadow = g_attachedEffects.getById(AXE_SHADOW_EFFECTS[n])
        if not blade or not shadow then
            return
        end
        -- the engine's own timer takes them off if the stepping ever stops
        blade:setDuration(run.flightMs + 200)
        shadow:setDuration(run.flightMs + 200)
        tile:attachEffect(shadow)
        tile:attachEffect(blade)
        run.axes[n] = { blade = blade, shadow = shadow }
    end
    axeRuns[runId] = run
    axeRunStep(runId)
end

local function clearAxeRuns()
    for _, run in pairs(axeRuns) do
        axeRunClear(run)
    end
    axeRuns = {}
end

-- "daggers,<runId>,<x>,<y>,<z>,<angle>,<spread>,<msPerTile>,<staggerMs>,
-- <landMs>,<lane>|<lane>|<lane>": one salvo of three daggers from the
-- tile x,y,z, at <angle> - <spread>, <angle> and <angle> + <spread>
-- (centidegrees, screen sense; a spread of 0 sends all three down one
-- line, in file). Each <lane> is "<len>:<stuck>:<lx>:<ly>": the dagger
-- flies straight for <len> centitiles at <msPerTile> and ends on tile
-- lx,ly, in the wall beyond it when <stuck> is 1. The three leave
-- <staggerMs> apart. The server sends one message per salvo, each aimed
-- afresh. A dagger is a tile effect on
-- the throw tile moved by offset every frame, drawn at the nearest of 24
-- rotations (DAGGER_FLIGHT_FIRST + r for r * 15 degrees); where it stops
-- it is left for <landMs> either lying on its tile (DAGGER_LAND_FIRST + r,
-- under creatures) or stuck head-first in the wall it ran into
-- (DAGGER_STUCK_FIRST + r, the tip reaching into the wall tile the way the
-- spear's does). The server steps the damage down the same lanes.
local DAGGER_FLIGHT_FIRST, DAGGER_LAND_FIRST, DAGGER_STUCK_FIRST = 301, 325, 357
local DAGGER_LIFT_PX = 5
local daggerRuns = {} -- runId -> {event, pos, daggers}

local function daggerRotation(angleDeg)
    return math.floor((angleDeg % 360) / 15 + 0.5) % 24
end

local function daggerRunClear(run)
    if run.event then
        removeEvent(run.event)
        run.event = nil
    end
    local tile = g_map.getTile(run.pos)
    if tile then
        for _, dagger in ipairs(run.daggers) do
            if dagger.effect then
                tile:detachEffect(dagger.effect)
                dagger.effect = nil
            end
        end
    end
end

local function daggerRunStep(runId)
    local run = daggerRuns[runId]
    if not run then
        return
    end
    local elapsed = g_clock.millis() - run.startedAt
    local tile = g_map.getTile(run.pos)
    local flying = false
    for _, dagger in ipairs(run.daggers) do
        if not dagger.done then
            local f = (elapsed - dagger.startMs) / dagger.flightMs
            if f >= 1 then
                dagger.done = true
                if tile and dagger.effect then
                    tile:detachEffect(dagger.effect)
                    dagger.effect = nil
                end
                holdTileEffect(dagger.landPos, (dagger.stuck and DAGGER_STUCK_FIRST or DAGGER_LAND_FIRST) + dagger.rotation, run.landMs)
            elseif f >= 0 then
                flying = true
                if not dagger.effect and tile then
                    local effect = g_attachedEffects.getById(DAGGER_FLIGHT_FIRST + dagger.rotation)
                    if effect then
                        effect:setDuration(dagger.flightMs + 200)
                        tile:attachEffect(effect)
                        dagger.effect = effect
                    end
                end
                if dagger.effect then
                    local px = math.floor(dagger.dirX * f * dagger.len * 32 + 0.5)
                    local py = math.floor(dagger.dirY * f * dagger.len * 32 + 0.5)
                    dagger.effect:setOffset(-px, -py + DAGGER_LIFT_PX)
                end
            else
                flying = true -- not launched yet
            end
        end
    end
    if not flying then
        daggerRuns[runId] = nil
        return
    end
    run.event = scheduleEvent(function() daggerRunStep(runId) end, 1)
end

local function onDaggers(buffer)
    local runId, x, y, z, angle, spread, msPerTile, staggerMs, landMs, lanes =
        buffer:match('^daggers,([^,]+),(%d+),(%d+),(%d+),(-?%d+),(%d+),(%d+),(%d+),(%d+),([%d:|]+)$')
    if not runId then
        return
    end
    local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    if daggerRuns[runId] then
        daggerRunClear(daggerRuns[runId])
    end
    angle, spread, msPerTile, staggerMs = tonumber(angle) / 100, tonumber(spread) / 100, tonumber(msPerTile), tonumber(staggerMs)
    local run = { pos = pos, startedAt = g_clock.millis(), landMs = tonumber(landMs), daggers = {} }
    local lane = 0
    for len, stuck, lx, ly in lanes:gmatch('(%d+):([01]):(%d+):(%d+)') do
        local laneAngle = angle + (lane - 1) * spread
        local rad = math.rad(laneAngle)
        len = tonumber(len) / 100
        run.daggers[#run.daggers + 1] = {
            startMs = lane * staggerMs,
            flightMs = math.max(1, len * msPerTile),
            len = len, dirX = math.cos(rad), dirY = math.sin(rad),
            rotation = daggerRotation(laneAngle), stuck = stuck == '1',
            landPos = { x = tonumber(lx), y = tonumber(ly), z = pos.z },
        }
        lane = lane + 1
    end
    daggerRuns[runId] = run
    daggerRunStep(runId)
end

local function clearDaggerRuns()
    for _, run in pairs(daggerRuns) do
        daggerRunClear(run)
    end
    daggerRuns = {}
end

-- "spear,<runId>,<x>,<y>,<z>,<dir>,<tiles>,<msPerTile>,<stuck>,<holdMs>":
-- a spear leaves x,y,z along <dir> (the server's numbering: 0 north, 1
-- east, 2 south, 3 west, 4 south-west, 5 south-east, 6 north-west, 7
-- north-east) in one AttachedEffect:move over <tiles> tiles at
-- <msPerTile> each, and on arrival either sticks in the wall beyond the
-- last tile (<stuck> 1: the stuck image, its head reaching into the wall
-- tile, held <holdMs>) or lies on the ground there (0). Zero tiles is a
-- wall right in front of the thrower: no flight, the spear sticks from
-- his own tile. One flying and one stuck image per direction.
local SPEAR_DROP_EFFECT = 298
local SPEAR_DROP_MS = 1500
local SPEAR_STEPS = { [0] = { 0, -1 }, [1] = { 1, 0 }, [2] = { 0, 1 }, [3] = { -1, 0 }, [4] = { -1, 1 }, [5] = { 1, 1 }, [6] = { -1, -1 }, [7] = { 1, -1 } }
local SPEAR_FLY = { [0] = 290, [1] = 291, [2] = 292, [3] = 293, [4] = 349, [5] = 350, [6] = 351, [7] = 352 }
local SPEAR_STUCK = { [0] = 294, [1] = 295, [2] = 296, [3] = 297, [4] = 353, [5] = 354, [6] = 355, [7] = 356 }
local spearRuns = {} -- runId -> {event, pos, effectId}

local function spearRunClear(run)
    if run.event then
        removeEvent(run.event)
        run.event = nil
    end
    if run.pos then
        local tile = g_map.getTile(run.pos)
        if tile then
            tile:detachEffectById(run.effectId)
        end
        run.pos = nil
    end
end

local function onSpear(buffer)
    local runId, x, y, z, dir, tiles, msPerTile, stuck, holdMs = buffer:match('^spear,([^,]+),(%d+),(%d+),(%d+),([0-7]),(%d+),(%d+),([01]),(%d+)$')
    if not runId then
        return
    end
    dir, tiles, msPerTile = tonumber(dir), tonumber(tiles), tonumber(msPerTile)
    local from = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    local step = SPEAR_STEPS[dir]
    local to = { x = from.x + step[1] * tiles, y = from.y + step[2] * tiles, z = from.z }
    local function land()
        if stuck == '1' then
            holdTileEffect(to, SPEAR_STUCK[dir], tonumber(holdMs))
        else
            holdTileEffect(to, SPEAR_DROP_EFFECT, SPEAR_DROP_MS)
        end
    end
    if spearRuns[runId] then
        spearRunClear(spearRuns[runId])
        spearRuns[runId] = nil
    end
    local tile = g_map.getTile(from)
    local effect = tile and g_attachedEffects.getById(SPEAR_FLY[dir])
    if tiles == 0 or not effect then
        land()
        return
    end
    local flightMs = tiles * msPerTile
    effect:setDuration(flightMs)
    tile:attachEffect(effect)
    effect:move(from, to)
    local run = { pos = from, effectId = SPEAR_FLY[dir] }
    run.event = scheduleEvent(function()
        spearRunClear(run)
        spearRuns[runId] = nil
        land()
    end, flightMs)
    spearRuns[runId] = run
end

local function clearSpearRuns()
    for _, run in pairs(spearRuns) do
        spearRunClear(run)
    end
    spearRuns = {}
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
        -- A route that parsed to no tile at all has no nozzle to put the spout
        -- on, and holdTileEffect would hand g_map.getTile a nil position.
        if n == 1 then
            holdTileEffect(tiles[1], base + BLAZE_SPOUT, 0)
        end
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

-- The brothers' tether as a tube (OTSERV brothers_link.lua, TETHER_LOOK
-- "tube"), opcode 73 "tether,<idA>,<idB>,<ox>,<oy>": the map is switched
-- to the 'Map - Tether' shader, which draws one continuous lit tube
-- between the two creatures' body centres (UIMap:setShaderAnchor hands
-- the shader where each is DRAWN every frame, walk offset included;
-- tether.frag does the rest), ox,oy being where on the body it aims.
-- Held like a tile effect: the server repeats it every half second and
-- it is dropped TETHER_TTL_MS after the last repeat, or at once on
-- "tetheroff". The shader the player had is put back when it ends.
local TETHER_SHADER = 'Map - Tether'
local TETHER_TTL_MS = 1500
local tether = nil

-- The ball riding the tube, "tetherball,<runId>,<startPermille>,<remainingMs>":
-- the server says where along the tube it is now and how long it has left to
-- reach the far body; this side glides it there on its own frame clock, as
-- u_Anchor2 (progress 0..1, and a flag that a ball is in flight). A re-send
-- with the same runId is a re-sync after a bend; "ballstop" or the tether
-- ending takes it off.
local tetherBall = nil

local function tetherBallStep()
    if not tetherBall or not tether then
        return
    end
    local map = modules.game_interface.getMapPanel()
    if not map then
        -- The run is still live, so a missing panel is a frame to skip, not a
        -- reason to park the ball: tetherBallOn would refuse to restart it.
        scheduleEvent(tetherBallStep, 1)
        return
    end
    local elapsed = g_clock.millis() - tetherBall.startedAt
    local progress = tetherBall.startProgress + (1 - tetherBall.startProgress) * math.min(1, elapsed / math.max(1, tetherBall.durationMs))
    -- progress runs from the flow's start; the shader counts from Latrivan
    if tetherBall.flow < 0 then
        progress = 1 - progress
    end
    map:setShaderPoint(2, progress, 1)
    if elapsed >= tetherBall.durationMs then
        tetherBall = nil
        map:setShaderPoint(2, -1, -1)
        return
    end
    -- Every frame, not every 16 ms: the dispatcher runs a due event once per
    -- frame, and at 150+ fps a 16 ms step held the ball still for two or
    -- three frames at a time.
    scheduleEvent(tetherBallStep, 1)
end

local function tetherBallOff()
    tetherBall = nil
    local map = modules.game_interface.getMapPanel()
    if map then
        map:setShaderPoint(2, -1, -1)
    end
end

local function tetherBallOn(runId, startPermille, remainingMs)
    if not tether then
        return
    end
    -- A re-send of the ball already in flight (the server repeats it when the
    -- line bends) is ignored: its figure is the tile the ball is ON, a step
    -- behind the glide, and taking it snapped the ball back a tile every time
    -- a brother walked. The tube's ends are the anchors, so a bend needs no
    -- re-sync here; the glide runs out on its original clock.
    if tetherBall and tetherBall.runId == runId then
        return
    end
    local running = tetherBall ~= nil
    tetherBall = { runId = runId, startProgress = startPermille / 1000, durationMs = remainingMs, startedAt = g_clock.millis(), flow = tether.flow or 1 }
    if not running then
        tetherBallStep()
    end
end

local function tetherOff()
    if not tether then
        return
    end
    tetherBallOff()
    local map = modules.game_interface.getMapPanel()
    if map then
        map:clearShaderAnchors()
        map:setShader(tether.previousShader, 0, 0)
    end
    tether = nil
end

-- idA is always Latrivan and idB Golgordan (the colours are theirs); flow
-- is +1 while the energy runs from A to B and -1 the other way, and is what
-- the ball's progress (sent from the flow's own start) is converted with.
local function tetherOn(idA, idB, ox, oy, flow)
    local a, b = g_map.getCreatureById(idA), g_map.getCreatureById(idB)
    local map = modules.game_interface.getMapPanel()
    if not a or not b or not map then
        return
    end
    if not tether then
        local current = map:getShader()
        tether = { previousShader = (current and current.getName and current:getName()) or 'Map - Default' }
        map:setShader(TETHER_SHADER, 0, 0)
    end
    tether.seen = g_clock.millis()
    tether.flow = flow
    map:setShaderAnchor(0, a, ox, oy)
    map:setShaderAnchor(1, b, ox, oy)
    map:setShaderPoint(3, flow, 1)
end

local function onTileEffectOpcode(protocol, opcode, buffer)
    local idA, idB, ox, oy, flow = buffer:match('^tether,(%d+),(%d+),(-?%d+),(-?%d+),(-?1)$')
    if idA then
        tetherOn(tonumber(idA), tonumber(idB), tonumber(ox), tonumber(oy), tonumber(flow))
        return
    end
    if buffer == 'tetheroff' then
        tetherOff()
        return
    end
    local ballId, startPermille, remainingMs = buffer:match('^tetherball,([^,]+),(%d+),(%d+)$')
    if ballId then
        tetherBallOn(ballId, tonumber(startPermille), tonumber(remainingMs))
        return
    end
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
    if buffer:sub(1, 5) == 'axes,' then
        onAxes(buffer)
        return
    end
    if buffer:sub(1, 6) == 'spear,' then
        onSpear(buffer)
        return
    end
    if buffer:sub(1, 8) == 'daggers,' then
        onDaggers(buffer)
        return
    end
    local stopId = buffer:match('^ballstop,([^,]+)$')
    if stopId then
        onBallStop(stopId)
        if tetherBall and tetherBall.runId == stopId then
            tetherBallOff()
        end
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
    if tether and now - tether.seen > TETHER_TTL_MS then
        tetherOff()
    end
end

controller = Controller:new()

function controller:onGameStart()
    ProtocolGame.registerExtendedOpcode(ATTACHED_EFFECT_OPCODE, onExtendedOpcode)
    ProtocolGame.registerExtendedOpcode(RARITY_SHINE_OPCODE, onRarityShineOpcode)
    ProtocolGame.registerExtendedOpcode(TILE_EFFECT_OPCODE, onTileEffectOpcode)
    shines = {}
    heldTileEffects = {}
    controller:cycleEvent(refreshShines, 250)
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
    tetherOff()
    clearBallRuns()
    clearBlazeRuns()
    clearAxeRuns()
    clearSpearRuns()
    clearDaggerRuns()
    clearBloodlust()
    clearLunges()
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
