--[[
    register(id, name, thingId, thingType, config)
    config = {
        speed, disableWalkAnimation, shader, drawOnUI, opacity
        duration, loop, transform, hideOwner, followOwner, size{width, height}
        offset{x, y, onTop}, dirOffset[dir]{x, y, onTop},
        light { color, intensity}, drawOrder(only for tiles),
        bounce{minHeight, height, speed},
        pulse{minHeight, height, speed},
        fade{start, end, speed}

        onAttach, onDetach
    }
]]
--
AttachedEffectManager.register(1, 'Spoke Lighting', 12, ThingCategoryEffect, {
    speed = 0.5,
    onAttach = function(effect, owner)
        print('onAttach: ', effect:getId(), owner:getName())
    end,
    onDetach = function(effect, oldOwner)
        print('onDetach: ', effect:getId(), oldOwner:getName())
    end
})

-- Use the paperdoll system instead of attachedEffect for this kind of attachment, it’s more consistent.
AttachedEffectManager.register(2, 'Bat Wings', 307, ThingCategoryCreature, {
    speed = 5,
    disableWalkAnimation = true,
    shader = 'Outfit - Rainbow',
    followOwner = true,
    dirOffset = {
        [North] = { 0, -10, true },
        [East] = { 5, -5 },
        [South] = { -5, 0 },
        [West] = { -10, -5, true }
    },
    onAttach = function(effect, owner)
        owner:setBounce(0, 10, 5000)
    end,
    onDetach = function(effect, oldOwner)
        oldOwner:setBounce(0, 0)
    end
})

AttachedEffectManager.register(3, 'Angel Light', 50, ThingCategoryEffect, {
    opacity = 0.5,
    drawOnUI = false
})

AttachedEffectManager.register(4, 'Four Angel Light', 0, 0, {
    onAttach = function(effect, owner)
        local angelLight = g_attachedEffects.getById(3)
        local angelLight1 = angelLight:clone()
        local angelLight2 = angelLight:clone()
        local angelLight3 = angelLight:clone()
        local angelLight4 = angelLight:clone()

        angelLight1:setOffset(-50, 50, true)
        angelLight2:setOffset(50, 50, true)
        angelLight3:setOffset(50, -50, true)
        angelLight4:setOffset(-50, -50, true)

        effect:attachEffect(angelLight1)
        effect:attachEffect(angelLight2)
        effect:attachEffect(angelLight3)
        effect:attachEffect(angelLight4)
    end
})

AttachedEffectManager.register(5, 'Transform', 40, ThingCategoryCreature, {
    transform = true,
    duration = 5000,
    onAttach = function(effect, owner)
        local e = Effect.create()
        e:setId(7)
        owner:getTile():addThing(e)
    end,
    onDetach = function(effect, oldOwner)
        local e = Effect.create()
        e:setId(50)
        oldOwner:getTile():addThing(e)
    end
})

AttachedEffectManager.register(6, 'Lake Monster', 34, ThingCategoryEffect, {
    hideOwner = true,
    duration = 1500,
    -- loop = 1,
    onDetach = function(effect, oldOwner)
        local e = Effect.create()
        e:setId(54)
        oldOwner:getTile():addThing(e)
    end
})

AttachedEffectManager.register(7, 'Pentagram Aura', '/images/game/effects/pentagram', ThingExternalTexture, {
    size = { 128, 128 },
    offset = { 50, 45 }
})

AttachedEffectManager.register(8, 'Ki', '/images/game/effects/ki', ThingExternalTexture, {
    size = { 140, 110 },
    offset = { 60, 75, true },
    pulse = { 0, 50, 3000 },
    --fade = { 0, 100, 1000 },
})

AttachedEffectManager.register(9, 'Thunder', '/images/game/effects/thunder', ThingExternalTexture, {
    loop = 1,
    offset = { 215, 230 }
})

AttachedEffectManager.register(10, 'Dynamic Effect', 0, 0, {
    duration = 500,
    onAttach = function(effect, owner)
        local spriteSize = g_gameConfig.getSpriteSize()
        local length = 3

        local missile = AttachedEffect.create(38, ThingCategoryMissile)
        missile:setDuration(effect:getDuration())
        missile:setDirection(5)
        missile:setOffset(spriteSize * length, 0)
        missile:setBounce(0, 15, 1000)
        missile:move(Position.translated(owner:getPosition(), -length, 0), owner:getPosition())
        effect:attachEffect(missile)

        missile = AttachedEffect.create(38, ThingCategoryMissile)
        missile:setDuration(effect:getDuration())
        missile:setDirection(3)
        missile:setOffset(-(spriteSize * length), 0)
        missile:setBounce(0, 15, 1000)
        missile:move(Position.translated(owner:getPosition(), length, 0), owner:getPosition())

        effect:attachEffect(missile)
    end,
    onDetach = function(effect, oldOwner)
        local e = Effect.create()
        e:setId(50)
        oldOwner:getTile():addThing(e)
    end
})

AttachedEffectManager.register(11, 'Bat', 307, ThingCategoryCreature, {
    speed = 0.5,
    offset = { 0, 0 },
    bounce = { 20, 20, 2000 }
})

-- Fireballs (effect 111) around an owner, drawn here because the server has
-- no sub-tile positions: every frame a ball's pixel offset is recomputed
-- around the creature's own draw point, which already carries the walk
-- offset, so it stays glued to a moving boss. The offset is subtracted at
-- draw time (AttachedEffect::draw), hence the negation. A ball on the lower
-- half is drawn in front of the owner and on the upper half behind it, which
-- is what makes it read as going around rather than across.
--
-- The orbit is squashed because the view is oblique: a true circle in pixels
-- reads as a hoop stood on edge. Distances measured in tiles are not.
--
-- Both effects below are turned on by the server over the attached-effect
-- opcode (attachedeffects.lua); which bosses wear which is decided in
-- data/scripts/boss_skills/attached_effects.lua.
local function placeBall(ball, angle, distance, squash)
    local x = math.cos(angle) * distance
    local y = math.sin(angle) * distance * squash
    ball:setOffset(-math.floor(x + 0.5), -math.floor(y + 0.5))
    ball:setOnTop(y > 0)
end

-- Parked, not worn by anyone: one ball orbiting, plus a ring of pushCount
-- balls pushed pushRadius out in every direction at once and pulled back
-- every pushEveryMs. Each pushed ball is a throwaway attached effect with a
-- duration, so the client detaches it by itself; this only moves it while
-- it lives.
AttachedEffectManager.register(12, 'Orbit_multi_proj', 111, ThingCategoryEffect, {
    speed = 1,
    onAttach = function(effect, owner)
        local radius, squash, lapMs = 24, 0.55, 2000
        local pushEveryMs, pushMs, pushRadius, pushCount = 10000, 3000, 5 * 32, 8
        local started = g_clock.millis()
        local lastPush = 0
        local push = nil

        effect.orbit = cycleEvent(function()
            local now = g_clock.millis()
            local elapsed = now - started
            placeBall(effect, (elapsed % lapMs) / lapMs * 2 * math.pi, radius, squash)

            local pushIndex = math.floor(elapsed / pushEveryMs)
            if pushIndex > lastPush then
                lastPush = pushIndex
                push = { started = now, balls = {} }
                for i = 1, pushCount do
                    local ball = AttachedEffect.create(111, ThingCategoryEffect)
                    ball:setDuration(pushMs)
                    owner:attachEffect(ball)
                    push.balls[i] = ball
                end
            end

            if push then
                local progress = (now - push.started) / pushMs
                if progress >= 1 then
                    push = nil
                else
                    local distance = math.sin(math.pi * progress) * pushRadius
                    for i, ball in ipairs(push.balls) do
                        placeBall(ball, (i - 1) / pushCount * 2 * math.pi, distance, 1)
                    end
                end
            end
        end, 16)
    end,
    onDetach = function(effect, oldOwner)
        removeEvent(effect.orbit)
        effect.orbit = nil
    end
})

-- One ball orbiting at radius; after every restMs it keeps turning while its
-- orbit widens to farRadius over outMs and narrows back over inMs, so on the
-- way out and back it sweeps every direction. outMs / lapMs is how many
-- times it goes round on the way out -- three, at these numbers -- which is
-- what keeps it from reading as a dash off to one side.
--
-- farRadius is in tiles, so the squash is eased out as the orbit widens:
-- hoop-shaped close to the body, a true five-tile circle at full reach.
AttachedEffectManager.register(13, 'Orbiting Fireball', 111, ThingCategoryEffect, {
    speed = 1,
    onAttach = function(effect, owner)
        local radius, farRadius, squash, lapMs = 24, 5 * 32, 0.55, 2000
        local restMs, outMs, inMs = 10000, 6000, 6000
        local cycleMs = restMs + outMs + inMs
        local started = g_clock.millis()

        effect.orbit = cycleEvent(function()
            local elapsed = g_clock.millis() - started
            local angle = (elapsed % lapMs) / lapMs * 2 * math.pi

            local phase = elapsed % cycleMs
            local reach = 0
            if phase >= restMs + outMs then
                reach = 1 - (phase - restMs - outMs) / inMs
            elseif phase >= restMs then
                reach = (phase - restMs) / outMs
            end

            local distance = radius + (farRadius - radius) * reach
            placeBall(effect, angle, distance, squash + (1 - squash) * reach)
        end, 16)
    end,
    onDetach = function(effect, oldOwner)
        removeEvent(effect.orbit)
        effect.orbit = nil
    end
})

-- Tainted and Corrupted spawn portals (attachedeffects.lua, opcode 73): the
-- dat effects 101 and 160 looped on the corpse tile at half speed until
-- the monster steps out. Ids match OTSERV variant_config.lua spawnEffects.
AttachedEffectManager.register(40, 'Tainted Spawn Portal', 101, ThingCategoryEffect, {
    speed = 0.5,
    offset = { 0, 0, true }
})

AttachedEffectManager.register(41, 'Corrupted Spawn Portal', 160, ThingCategoryEffect, {
    speed = 0.5,
    offset = { 0, 0, true }
})

-- Tether beam between Latrivan and Golgordan (attachedeffects.lua, opcode
-- 73, kept alive by the server's once-a-second refresh): one looping
-- segment per tile of the path, drawn under creatures so the brothers and
-- anyone in the beam stand on it. A segment is shaped by where the beam
-- enters the tile and where it leaves, so a stepped path still joins up:
-- id = 50 + 9 * entry + exit, directions 0 N, 1 NE, 2 E, 3 SE, 4 S, 5 SW,
-- 6 W, 7 NW and 8 for "starts/ends here" (OTSERV brothers_link.lua
-- computes the id). Energy flows entry to exit. Textures generated by
-- script, like the shine.
for entry = 0, 8 do
    for exit = 0, 8 do
        if entry ~= exit and not (entry == 8 and exit == 8) then
            AttachedEffectManager.register(50 + 9 * entry + exit, 'Tether Beam ' .. entry .. '>' .. exit,
                '/images/game/effects/tether_beam_' .. entry .. '_' .. exit, ThingExternalTexture, {
                    offset = { 0, 0, false }
                })
        end
    end
end

-- The ball riding the tether (attachedeffects.lua, opcode 73 "ballrun"):
-- one breathing orb that the client glides along the route with
-- AttachedEffect:move, drawn above creatures, unlike the beam.
AttachedEffectManager.register(131, 'Tether Ball', '/images/game/effects/tether_ball', ThingExternalTexture, {
    offset = { 0, 0, true }
})

-- Flamethrower jets from the pillar traps (attachedeffects.lua, opcode 73
-- held effects, OTSERV data/scripts/flamethrowers/flamethrowers.lua): a
-- narrow nozzle on the tile in front of the pillar, rolling body tiles and
-- a ragged tip on the newest tile, each looping without a seam and drawn
-- over whoever stands in the fire; a jet only one tile long is a spout,
-- nozzle and tip in one. id = 132 + 16 * palette + 4 * direction +
-- segment, palettes purple 0 / fire 1, directions n 0 / e 1 / s 2 / w 3,
-- segments nozzle 0 / body 1 / tip 2 / spout 3. Textures generated by
-- script.
for p, palette in ipairs({ 'purple', 'fire' }) do
    for d, dir in ipairs({ 'n', 'e', 's', 'w' }) do
        for s, segment in ipairs({ 'nozzle', 'body', 'tip', 'spout' }) do
            AttachedEffectManager.register(132 + 16 * (p - 1) + 4 * (d - 1) + (s - 1),
                'Flame ' .. palette .. ' ' .. dir .. ' ' .. segment,
                '/images/game/effects/flame_' .. palette .. '_' .. dir .. '_' .. segment, ThingExternalTexture, {
                    offset = { 0, 0, true }
                })
        end
    end
end

-- Blaze: the flamethrower's second look (OTSERV flamethrowers.lua, style
-- "blaze"), same four segments per direction at 164 + 16 * palette + 4 *
-- direction + segment.
for p, palette in ipairs({ 'purple', 'fire' }) do
    for d, dir in ipairs({ 'n', 'e', 's', 'w' }) do
        for s, segment in ipairs({ 'nozzle', 'body', 'tip', 'spout' }) do
            AttachedEffectManager.register(164 + 16 * (p - 1) + 4 * (d - 1) + (s - 1),
                'Blaze ' .. palette .. ' ' .. dir .. ' ' .. segment,
                '/images/game/effects/blaze_' .. palette .. '_' .. dir .. '_' .. segment, ThingExternalTexture, {
                    offset = { 0, 0, true }
                })
        end
    end
end

-- The gliding pair of each look, per palette and direction, that
-- attachedeffects.lua slides along the jet with AttachedEffect:move while
-- it grows ("jetgrow") and back while it retracts ("jetretract"):
--   the TIP, the look's own tip image registered again at 212 + 4 *
--   palette + direction (flame) / 196 + ... (blaze), at the missile's draw
--   order so it paints over the body tiles behind it whatever order the
--   map draws them in;
--   the TAIL, id 8 higher, a body whose first third is clear, drawn one
--   tile BEHIND the anchor in the tile's bottom pass so the bodies come
--   after it and it only shows in the gap between the last lit body and
--   the tip. It cannot sit below the bodies by draw order: the next order
--   down is the ground borders', and a grass border on a neighbouring
--   tile then paints over it. So it stays at the bodies' order and is
--   submitted before them instead: the map draws tiles in coordinate
--   order, so attachedeffects.lua attaches it to the tile behind the
--   anchor for a jet flowing east or south (drawn before the anchor) and
--   to the anchor itself for west or north (the tile behind is drawn
--   after), and the offset here puts the image one tile behind in the
--   latter case.
for p, palette in ipairs({ 'purple', 'fire' }) do
    for d, dir in ipairs({ 'n', 'e', 's', 'w' }) do
        local tailOffset = ({ n = { 0, -32, false }, e = { 0, 0, false }, s = { 0, 0, false }, w = { -32, 0, false } })[dir]
        for _, look in ipairs({ { first = 212, name = 'flame' }, { first = 196, name = 'blaze' } }) do
            AttachedEffectManager.register(look.first + 4 * (p - 1) + (d - 1), look.name .. ' ' .. palette .. ' ' .. dir .. ' gliding tip',
                '/images/game/effects/' .. look.name .. '_' .. palette .. '_' .. dir .. '_tip', ThingExternalTexture, {
                    offset = { 0, 0, true },
                    drawOrder = 4 -- DrawOrder::FIFTH, above all, like a missile
                })
            AttachedEffectManager.register(look.first + 8 + 4 * (p - 1) + (d - 1), look.name .. ' ' .. palette .. ' ' .. dir .. ' gliding tail',
                '/images/game/effects/' .. look.name .. '_' .. palette .. '_' .. dir .. '_tail', ThingExternalTexture, {
                    offset = tailOffset
                })
        end
    end
end

-- The Shackled Demon's chains (OTSERV data/scripts/shackled_demon/,
-- opcode 73 held/timed effects on the demon's TILE, not on the creature,
-- so the bloodlust pulse that scales the creature leaves them alone): a
-- 64x64 image over the 2x2 demon sprite, offset 32,32 so it covers the
-- same square the sprite is drawn in from the tile's point. 228 loops
-- while it is chained, 229 is the one-shot break sent with a duration so
-- it runs out by itself. Drawn by make_shackles.js.
AttachedEffectManager.register(228, 'Shackles', '/images/game/effects/shackles', ThingExternalTexture, {
    offset = { 32, 32, true }
})
AttachedEffectManager.register(229, 'Shackles break', '/images/game/effects/shackles_break', ThingExternalTexture, {
    offset = { 32, 32, true }
})
-- The Impaled Demon's wall chains: spikes in its back chained to rings in
-- the wall three tiles behind. 160x160 on the tile, drawn in the tile's
-- bottom pass (onTop false), before the creature, so the chains rise from
-- the back rather than over the face; offset 80,128 puts the sprite's
-- square in the bottom 64 rows, 48 px in from each side so the freed
-- chains can whip sideways without touching the edge, and the rings 84 px
-- above the spikes. 230 loops, 231 is the one-shot break (16 frames,
-- 1.6 s). Drawn by make_wallchains.js.
AttachedEffectManager.register(230, 'Wall chains', '/images/game/effects/wallchains', ThingExternalTexture, {
    offset = { 80, 128, false }
})
AttachedEffectManager.register(231, 'Wall chains break', '/images/game/effects/wallchains_break', ThingExternalTexture, {
    offset = { 80, 128, false }
})

-- Annihilon's Stomp (OTSERV data/spells/scripts/bosses/annihilon_stomp.lua):
-- the ground shattering across the 7x7 circle around him, one 224x224
-- animation cut into 49 tile pieces, because a single image on his tile
-- would be painted over by the ground of every tile drawn after it. Piece
-- (row, col) of the square is 232 + row * 7 + col, laid on its own tile
-- in the bottom pass (over the ground, under items and creatures) by the
-- "area" verb of opcode 73 (attachedeffects.lua), all 49 in one message.
-- Drawn by make_shatter.js; the corner pieces are empty.
for row = 0, 6 do
    for col = 0, 6 do
        AttachedEffectManager.register(232 + row * 7 + col, 'Shatter ' .. row .. ',' .. col, '/images/game/effects/shatter/shatter_' .. row .. '_' .. col, ThingExternalTexture, {
            offset = { 0, 0, false }
        })
    end
end
-- The stone rain's warning: a target on the tile a stone is about to hit,
-- its inner ring closing over the 1.2 s the server holds it, sent timed
-- so it closes as the stone lands. Under creatures. Drawn by
-- make_warning.js.
AttachedEffectManager.register(281, 'Stone warning', '/images/game/effects/stone_warning', ThingExternalTexture, {
    offset = { 0, 0, false }
})
-- The stones themselves, three sizes the server picks from at random:
-- 32x96, the bottom 32 rows on the tile and the 64 above it the air the
-- rock falls through, so offset 0,64; over creatures, since it lands on
-- them. 16 frames at 60 ms: a 300 ms fall, then the impact, the pieces
-- and the dust. The server sends it 300 ms before the damage so the
-- impact frame is the hit. Drawn by make_stone.js.
for variant = 1, 3 do
    AttachedEffectManager.register(281 + variant, 'Falling stone ' .. variant, '/images/game/effects/stone_' .. variant, ThingExternalTexture, {
        offset = { 0, 64, true }
    })
end

-- Floor rarity shine (attachedeffects.lua, opcode 72): a glint sweeping the
-- tile along the item's long axis, drawn over the items. Four axes per
-- rarity: id = 20 + 4 * (rare 0 / epic 1 / legendary 2) + axis, axes in the
-- order NW-SE, NE-SW, W-E, N-S (SHINE_AXIS_* in attachedeffects.lua).
-- Colours are the tooltip's; Common gets none.
for r, rarity in ipairs({ 'rare', 'epic', 'legendary' }) do
    for a, axis in ipairs({ 'nwse', 'nesw', 'we', 'ns' }) do
        AttachedEffectManager.register(20 + 4 * (r - 1) + (a - 1), 'Rarity Shine ' .. rarity .. ' ' .. axis,
            '/images/game/effects/rarity_shine_' .. rarity .. '_' .. axis, ThingExternalTexture, {
                offset = { 0, 0, true }
            })
    end
end
