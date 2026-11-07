-- Trainer: auto-eat, mana training and runemaking.
--
-- Runs entirely client-side. That is a deliberate limit rather than an
-- oversight: g_game.getContainers() only reports containers the player has
-- OPENED, so auto-eat cannot see a closed backpack. See
-- plans/2026-08-25-trainer-widget/plan.md for why that trade was accepted.

-- CLIENT ids, not the server ids you see in items.xml -- the two differ and
-- nothing here can translate between them. item:getId() returns the .dat client
-- id, and item:getServerId() is always 0 in this client because g_things.loadOtb
-- is bound but never called, so the OTB mapping is not loaded.
--
-- To add a food: look its server id up in the server's data/items/items.otb and
-- put the CLIENT id here. There is no fixed offset to apply -- it happens to be
-- +911 for meat and +883 for gold coin, so it must be looked up per item.
--
-- Every id the server registers to data/actions/scripts/other/food/food.lua,
-- valued with that script's food figure: eating one adds figure * 24 seconds of
-- regeneration (player:feed). Jean-Pierre's buff dishes are left out on purpose.
local FOOD_IDS = {
    [3606] = 6, -- egg (server 2695)
    [3250] = 5, -- carrot (server 2362)
    [3577] = 15, -- meat (server 2666)
    [3578] = 12, -- fish (server 2667)
    [3579] = 10, -- salmon (server 2668)
    [3580] = 17, -- northern pike (server 2669)
    [3581] = 4, -- shrimp (server 2670)
    [3582] = 30, -- ham (server 2671)
    [3583] = 60, -- dragon ham (server 2672)
    [3584] = 5, -- pear (server 2673)
    [3585] = 6, -- red apple (server 2674)
    [3586] = 13, -- orange (server 2675)
    [3587] = 8, -- banana (server 2676)
    [3588] = 1, -- blueberry (server 2677)
    [3589] = 18, -- coconut (server 2678)
    [3590] = 1, -- cherry (server 2679)
    [3591] = 2, -- strawberry (server 2680)
    [3592] = 9, -- grapes (server 2681)
    [3593] = 20, -- melon (server 2682)
    [3594] = 17, -- pumpkin (server 2683)
    [3595] = 5, -- carrot (server 2684)
    [3596] = 6, -- tomato (server 2685)
    [3597] = 9, -- corncob (server 2686)
    [130] = 2, -- cookie (server 2687)
    [3599] = 2, -- candy cane (server 2688)
    [3600] = 10, -- bread (server 2689)
    [8194] = 10, -- bread (server 9111)
    [3601] = 3, -- roll (server 2690)
    [3602] = 8, -- brown bread (server 2691)
    [169] = 9, -- cheese (server 2696)
    [3723] = 9, -- white mushroom (server 2787)
    [3724] = 4, -- red mushroom (server 2788)
    [3725] = 22, -- brown mushroom (server 2789)
    [3726] = 30, -- orange mushroom (server 2790)
    [3727] = 9, -- wood mushroom (server 2791)
    [3728] = 6, -- dark mushroom (server 2792)
    [3729] = 12, -- some mushrooms (server 2793)
    [3730] = 3, -- some mushrooms (server 2794)
    [3731] = 36, -- fire mushroom (server 2795)
    [3732] = 5, -- green mushroom (server 2796)
    [5096] = 4, -- mango (server 5097)
    [6125] = 8, -- tortoise egg (server 6125)
    [6277] = 10, -- cake (server 6278)
    [6278] = 15, -- decorated cake (server 6279)
    [6392] = 12, -- valentine's cake (server 6393)
    [904] = 15, -- cream cake (server 6394)
    [6500] = 20, -- gingerbread man (server 6501)
    [6541] = 6, -- coloured egg (yellow) (server 6541)
    [6542] = 6, -- coloured egg (red) (server 6542)
    [6543] = 6, -- coloured egg (blue) (server 6543)
    [6544] = 6, -- coloured egg (green) (server 6544)
    [6545] = 6, -- coloured egg (purple) (server 6545)
    [6569] = 1, -- candy (server 6569)
    [6574] = 5, -- bar of chocolate (server 6574)
    [7158] = 15, -- rainbow trout (server 7158)
    [7159] = 13, -- green perch (server 7159)
    [229] = 2, -- ice cream cone (crispy chocolate chips) (server 7372)
    [7373] = 2, -- ice cream cone (velvet vanilla) (server 7373)
    [7374] = 2, -- ice cream cone (sweet strawberry) (server 7374)
    [7375] = 2, -- ice cream cone (chilly cherry) (server 7375)
    [7376] = 2, -- ice cream cone (mellow melon) (server 7376)
    [7377] = 2, -- ice cream cone (blue-barian) (server 7377)
    [836] = 4, -- walnut (server 7909)
    [841] = 4, -- peanut (server 7910)
    [901] = 60, -- marlin (server 7963)
    [3607] = 9, -- scarab cheese (server 8112)
    [8010] = 10, -- potato (server 8838)
    [8011] = 5, -- plum (server 8839)
    [8012] = 1, -- raspberry (server 8840)
    [8013] = 1, -- lemon (server 8841)
    [8014] = 7, -- cucumber (server 8842)
    [8015] = 5, -- onion (server 8843)
    [8016] = 1, -- jalapeno pepper (server 8844)
    [8017] = 5, -- beetroot (server 8845)
    [8019] = 11, -- chocolate cake (server 8847)
    [8177] = 7, -- yummy gummy worm (server 9005)
    [8197] = 5, -- bulb of garlic (server 9114)
    [10329] = 15, -- rice ball (server 11246)
    [10453] = 3, -- terramite eggs (server 11370)
    [10219] = 10, -- crocodile steak (server 11429)
    [11459] = 20, -- pineapple (server 12415)
    [11460] = 10, -- aubergine (server 12416)
    [11461] = 8, -- broccoli (server 12417)
    [11462] = 9, -- cauliflower (server 12418)
    [11681] = 55, -- ectoplasmic sushi (server 12637)
    [11682] = 18, -- dragonfruit (server 12638)
    [11683] = 2, -- peas (server 12639)
    [19217] = 15, -- jade carp (server 20192)
    [19218] = 20, -- royal carp (server 20193)
    [19219] = 15, -- frost carp (server 20194)
    [19220] = 15, -- sunscale carp (server 20195)
    [19221] = 12, -- pond koi (server 20196)
    [19222] = 12, -- red koi (server 20197)
    [19223] = 15, -- brook koi (server 20198)
    [19224] = 15, -- sun koi (server 20199)
    [19225] = 15, -- mire squid (server 20200)
    [19226] = 12, -- blood squid (server 20201)
    [19227] = 15, -- abyssal squid (server 20202)
    [19228] = 20, -- tangerine squid (server 20203)
    [19229] = 30, -- ashfin shark (server 20204)
    [19230] = 30, -- rust shark (server 20205)
    [19231] = 30, -- glacier shark (server 20206)
    [19232] = 30, -- sandfin shark (server 20207)
    [19233] = 12, -- marsh perch (server 20208)
    [19234] = 10, -- tiger barb (server 20209)
    [19235] = 12, -- blue mackerel (server 20210)
    [19236] = 12, -- golden dorado (server 20211)
}

local EAT_INTERVAL = 60 * 1000
local TICK_INTERVAL = 500

-- Anti-idle, on exactly while the master switch is, whichever features are
-- checked: keeping the character logged in is part of what ON means.
--
-- The server kicks after kickIdlePlayerAfterMinutes with no packet that counts
-- as activity (OTSERV Player::onThink, the idleTime block), and a working
-- trainer easily goes that long without sending one: auto-eat fires once a
-- minute and only when it finds food, and both spell trainers hold fire below
-- their threshold.
--
-- A turn towards the direction the character already faces is the cheapest
-- signal that counts. OTSERV Game::playerTurn resets the idle timer BEFORE
-- calling internalCreatureTurn, which returns early on an unchanged direction
-- -- so nothing reaches other players and no state changes. Player:onTurn is
-- disabled in events.xml, so no script runs either. That is why this needs no
-- server-side counterpart.
--
-- 30s holds idleTime under half a minute whatever the config says, so this
-- keeps working if kickIdlePlayerAfterMinutes is ever lowered.
local ANTI_IDLE_INTERVAL = 30 * 1000

-- Spell cooldowns are modelled here because the server never reports them: this
-- fork sends no spell-cooldown opcode (there is no sendSpellCooldown in
-- src/protocolgame.cpp), and GameSpellList only switches on from protocol 870
-- (modules/game_features/features.lua:80) while this client runs 860.
--
-- 2000 is TFS's class default (src/spells.h:330). Conjure spells are
-- group="support", and Spell::configureSpell (src/spells.cpp:466) special-cases
-- only attack (1600) and healing (1000), so support keeps that 2000 default.
-- Spells that declare their own longer cooldown are found by backing off when a
-- cast is actually refused, rather than by keeping a table of every spell here.
local BASE_COOLDOWN = 2000
local MAX_COOLDOWN = 30000
local BACKOFF_STEP = 1000
-- A refusal is only credited to our cast if it arrives within this window.
local BLAME_WINDOW = 1500

-- A refused cast spends no mana and no cooldown (OTSERV
-- InstantSpell::playerCastInstant only runs postCastSpell on success), so a
-- runemaker with no blank rune would own every tick and mana training's adori
-- blank would never get its turn. A trainer refused for one of these steps
-- aside until the other one casts (which may be what makes the blank rune) or
-- this long passes (a rune put in by hand), so it keeps retrying without
-- saying the spell every tick.
local BLOCKED_RETRY = 10000
local BLOCKING_REFUSALS = {
    'you need a magic item', -- no blank rune (OTSERV Player.conjureItem)
    'you do not have enough soul',
    'you do not have enough mana', -- the threshold is below the spell's cost
}

-- Every successful cast puts the server's 1000 ms global cooldown on every
-- other spell (OTSERV Spell::postCastSpell, GLOBAL_COOLDOWN), so the other
-- trainer waits this long after any cast. Without it, the rune cast right
-- after an adori blank was refused as exhausted and ratcheted its backoff.
local CROSS_CAST_GAP = 1500

-- The text fields, as opposed to the toggles: these are the only widgets that
-- should hold the keyboard, so a click anywhere else hands it back.
local FIELD_IDS = { 'manaSpell', 'manaPercent', 'runeSpell', 'runePercent' }

-- The words this character can cast, lowercased, from the server
-- (OTSERV data/scripts/trainer_widget/trainer_spells.lua). Casting is by
-- talking, so a field holding anything else would be said aloud on every tick.
-- The client's own SpellInfo cannot stand in: it is stock Tibia and misses the
-- server's custom spells. nil until the list arrives, and nothing is cast
-- meanwhile.
local TRAINER_SPELLS_OPCODE = 82
local castableSpells = nil

local trainerWindow = nil
local trainerButton = nil
local contentsPanel = nil
local tickEvent = nil
local nextEatAt = 0
local lastAntiIdleTime = 0
local trainerEnabled = false

-- One cooldown model per trainer: they cast different spells with different
-- cooldowns, so a shared timer would let the slower one gate the faster.
local casters = {
    rune = { interval = BASE_COOLDOWN, nextCastAt = 0, blockedUntil = 0 },
    mana = { interval = BASE_COOLDOWN, nextCastAt = 0, blockedUntil = 0 },
}
local lastCaster = nil
local lastCastAt = 0

local controls = {}

local function resetCooldowns()
    for _, caster in pairs(casters) do
        caster.interval = BASE_COOLDOWN
        caster.nextCastAt = 0
        caster.blockedUntil = 0
    end
    lastCaster = nil
end

local function settingsKey()
    -- Per character: two characters on one client rarely want the same spells.
    local name = g_game.getCharacterName()
    if not name or name == '' then
        return nil
    end
    return 'Trainer-' .. name
end

local function saveSettings()
    local key = settingsKey()
    if not key then
        return
    end

    g_settings.mergeNode(key, {
        enabled = trainerEnabled,
        autoEat = controls.autoEat:isChecked(),
        manaTraining = controls.manaTraining:isChecked(),
        manaSpell = controls.manaSpell:getText(),
        manaPercent = controls.manaPercent:getText(),
        runemaking = controls.runemaking:isChecked(),
        runeSpell = controls.runeSpell:getText(),
        runePercent = controls.runePercent:getText(),
    })
end

local function showMasterState()
    local button = controls.masterToggle
    if trainerEnabled then
        button:setText(tr('TRAINER: ON'))
        button:setColor('#55dd55')
    else
        button:setText(tr('TRAINER: OFF'))
        button:setColor('#ff5555')
    end
end

local function loadSettings()
    local key = settingsKey()
    local saved = key and g_settings.getNode(key) or {}

    -- Off for a character that never saved it, including everyone who had the
    -- trainer set up before the switch existed.
    trainerEnabled = saved.enabled == true
    showMasterState()
    controls.autoEat:setChecked(saved.autoEat or false)
    controls.manaTraining:setChecked(saved.manaTraining or false)
    controls.manaSpell:setText(saved.manaSpell or '')
    controls.manaPercent:setText(saved.manaPercent or '40')
    controls.runemaking:setChecked(saved.runemaking or false)
    controls.runeSpell:setText(saved.runeSpell or '')
    controls.runePercent:setText(saved.runePercent or '40')
end

-- Restores the keyboard focus chain for a widget inside a docked side panel.
--
-- Key events descend only into children that report isFocused()
-- (src/framework/ui/uiwidget.cpp:2081), so every link from rootWidget down to
-- the field has to be its parent's focused child. UIWidget::focus() cannot
-- build that chain here: it early-returns on a non-focusable widget and only
-- ever sets its IMMEDIATE parent's focused child, and side panels are created
-- with setFocusable(false) (corelib/ui/uiminiwindowcontainer.lua:7). The chain
-- therefore breaks at the panel, which is why typing worked only while the
-- window was floating -- floating parents it to rootWidget instead.
--
-- focusChild() carries no focusable check, so walking up by hand reconnects the
-- chain for this window alone, without changing focus policy for every docked
-- window in the client.
local function forceFocusChain(widget)
    local child = widget
    local parent = child:getParent()
    while parent do
        parent:focusChild(child, ActiveFocusReason)
        child = parent
        parent = child:getParent()
    end
end

-- Hands the keyboard back when a click lands anywhere but a text field.
--
-- forceFocusChain has no natural counterpart: normally clicking elsewhere moves
-- focus by focusing whatever was clicked, but gameMapPanel is focusable: false
-- (gameinterface.otui), so clicking the map focuses nothing and the field keeps
-- the keyboard. Arrow keys then move the text cursor instead of the character.
--
-- Clearing the parent's focused child is enough: propagateOnKeyText only
-- descends into focused children (src/framework/ui/uiwidget.cpp:2081), so with
-- no focused leaf the keys go unconsumed and reach the movement keybinds.
local function releaseFocus()
    for _, id in ipairs(FIELD_IDS) do
        local field = controls[id]
        if field and not field:isDestroyed() and field:isFocused() then
            local parent = field:getParent()
            if parent then
                parent:focusChild(nil, ActiveFocusReason)
            end
        end
    end
end

-- Keyed on the fields rather than on the window, so clicking a toggle, a label
-- or the title bar releases the keyboard just as clicking outside does. Only a
-- click on a field itself keeps it.
local function releaseUnlessOnField(mousePos)
    if not trainerWindow or trainerWindow:isDestroyed() or not trainerWindow:isVisible() then
        return
    end

    for _, id in ipairs(FIELD_IDS) do
        local field = controls[id]
        if field and not field:isDestroyed() and field:containsPoint(mousePos) then
            return
        end
    end

    releaseFocus()
end

-- Two hooks are needed, not one. A mouse press is offered to the deepest widget
-- first and stops at whichever consumes it, so this rootWidget handler only
-- sees clicks nothing else claimed -- the game map, empty space. A click on a
-- toggle is consumed by the toggle and never arrives here, which is why the
-- window needs its own handler below.
local function onRootMousePress(_widget, mousePos)
    releaseUnlessOnField(mousePos)

    -- Never consumes the click; this only observes where it landed.
    return false
end

-- Height goes to 0 when hidden, not just visible=false: a hidden widget still
-- occupies its slot in the anchor chain, so leaving the height at 12 left a gap
-- between the auto-eat row and the one below it whenever there was no hint.
local function setHint(text)
    local shown = text ~= nil
    controls.autoEatHint:setText(text or '')
    controls.autoEatHint:setVisible(shown)
    controls.autoEatHint:setHeight(shown and 12 or 0)
end

-- Current mana as a percentage of maximum, or nil when it can't be read.
local function manaPercent()
    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end

    local maxMana = player:getMaxMana()
    if not maxMana or maxMana <= 0 then
        return nil
    end

    return player:getMana() / maxMana * 100
end

-- One trainer, ready to cast: toggle on, a spell to say, and a readable
-- threshold. nil for any trainer that is missing one of the three.
--
-- The % is a FLOOR: cast while mana is AT OR ABOVE it, leaving that
-- much in reserve. The rejected alternative was to wait until the threshold
-- then drain to empty.
local function normalizeSpell(text)
    return text:match('^%s*(.-)%s*$'):lower()
end

local function isCastable(text)
    return castableSpells ~= nil and castableSpells[normalizeSpell(text)] == true
end

local function requestCastableSpells()
    local protocolGame = g_game.isOnline() and g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedOpcode(TRAINER_SPELLS_OPCODE, 'list')
    end
end

-- Red with a tooltip while the field holds text that is not a spell, so a
-- trainer that never fires does not read as a broken toggle.
local function markSpellField(field)
    local text = field:getText()
    if not field.normalColor then
        field.normalColor = field:getColor()
    end

    if text == '' or isCastable(text) then
        field:setColor(field.normalColor)
        field:removeTooltip()
    else
        field:setColor('#ff5555')
        field:setTooltip(tr('Not a spell you can cast. The trainer will not say it.'))
    end
end

local function markSpellFields()
    markSpellField(controls.manaSpell)
    markSpellField(controls.runeSpell)
end

local function onCastableSpells(_protocol, _opcode, buffer)
    castableSpells = {}
    for words in buffer:gmatch('[^|]+') do
        castableSpells[words:lower()] = true
    end
    if controls.manaSpell then
        markSpellFields()
    end
end

local function activeTrainer(toggle, spellWidget, percentWidget, caster)
    if not toggle:isChecked() then
        return nil
    end

    local spell = normalizeSpell(spellWidget:getText())
    local threshold = tonumber(percentWidget:getText())
    if not isCastable(spell) or not threshold then
        return nil
    end

    return { spell = spell, threshold = threshold, caster = caster }
end

local function tryEat()
    local containers = g_game.getContainers()
    local sawContainer = false

    for _, container in pairs(containers) do
        sawContainer = true
        for _, item in ipairs(container:getItems()) do
            local food = FOOD_IDS[item:getId()]
            if food then
                g_game.use(item)
                -- A cherry lasts 24 s, so a once-a-minute bite would let the
                -- regeneration run out between bites.
                nextEatAt = g_clock.millis() + math.min(EAT_INTERVAL, food * 24 * 1000)
                setHint(nil)
                return
            end
        end
    end

    -- Reported rather than swallowed: with no open container the eater can do
    -- nothing, and silence there reads as a broken toggle.
    -- Kept to one line: the hint row is 12px, so a longer string would wrap and
    -- be clipped rather than widening the window.
    if not sawContainer then
        setHint(tr('Open a backpack to auto-eat.'))
    else
        setHint(tr('No food in open containers.'))
    end
end

local function castSpell(caster, spell)
    local now = g_clock.millis()
    if now < caster.nextCastAt then
        return
    end

    g_game.talk(spell)
    for _, other in pairs(casters) do
        if other ~= caster then
            other.blockedUntil = 0
            other.nextCastAt = math.max(other.nextCastAt, now + CROSS_CAST_GAP)
        end
    end
    caster.nextCastAt = now + caster.interval
    lastCaster = caster
    lastCastAt = now
end

-- The server's refusal is the only cooldown signal available, so it is what
-- calibrates the interval. Each refusal pushes this caster's spacing out a
-- second until casts stop bouncing; the spacing resets whenever the spell or
-- the toggle changes, so a slow spell's backoff is not inherited by a fast one.
local function onTextMessage(_mode, text)
    if not lastCaster or not text then
        return
    end

    -- Only blame our own cast. Manual casting or another source producing this
    -- message would otherwise ratchet the interval up for no reason.
    local now = g_clock.millis()
    if now - lastCastAt > BLAME_WINDOW then
        return
    end

    local lower = text:lower()
    for _, refusal in ipairs(BLOCKING_REFUSALS) do
        if lower:find(refusal, 1, true) then
            lastCaster.blockedUntil = now + BLOCKED_RETRY
            return
        end
    end

    if not lower:find('exhausted', 1, true) then
        return
    end

    lastCaster.interval = math.min(lastCaster.interval + BACKOFF_STEP, MAX_COOLDOWN)
    lastCaster.nextCastAt = now + lastCaster.interval
end

-- A diagonal step leaves the CLIENT facing NorthEast..NorthWest -- Creature::walk
-- stores the raw step direction -- while the server ends on East or West, because
-- Map::moveCreature (src/map.cpp:268) applies its y test first and then lets the x
-- test overwrite it. That is also the sprite drawn here, since Creature::setDirection
-- folds the pattern the same way, so the two agree on screen and the turn stays a
-- no-op. Sending the raw diagonal would be worse than wrong: Game::turn has no case
-- for one and drops the packet without a word, so anti-idle would silently stop for
-- anyone whose last step was diagonal.
local DIAGONAL_CARDINAL = {
    [Directions.NorthEast] = Directions.East,
    [Directions.SouthEast] = Directions.East,
    [Directions.SouthWest] = Directions.West,
    [Directions.NorthWest] = Directions.West
}

local function keepAwake()
    local now = g_clock.millis()
    if now - lastAntiIdleTime < ANTI_IDLE_INTERVAL then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local direction = player:getDirection()
    lastAntiIdleTime = now
    g_game.turn(DIAGONAL_CARDINAL[direction] or direction)
end

local function tick()
    if not g_game.isOnline() or not trainerEnabled then
        return
    end

    keepAwake()

    if controls.autoEat:isChecked() and g_clock.millis() >= nextEatAt then
        tryEat()
    end

    -- Both trainers spend the same mana, so at most one casts per tick, and
    -- runemaking has priority: while it is usable and not blocked it owns the
    -- tick, below its threshold and on cooldown included, so mana training
    -- never spends mana runemaking is saving up for. Mana training gets the
    -- tick only while runemaking is off, unusable or blocked on a refusal
    -- (BLOCKED_RETRY) -- which is how a runemaker out of blank runes lets an
    -- adori blank in the mana training field make the next one.
    local rune = activeTrainer(controls.runemaking, controls.runeSpell, controls.runePercent, casters.rune)
    local mana = activeTrainer(controls.manaTraining, controls.manaSpell, controls.manaPercent, casters.mana)

    local current = manaPercent()
    if not current then
        return
    end

    local now = g_clock.millis()
    local trainer = mana
    if rune and now >= rune.caster.blockedUntil then
        trainer = rune
    end

    if trainer and current >= trainer.threshold and now >= trainer.caster.blockedUntil then
        castSpell(trainer.caster, trainer.spell)
    end
end

-- Off stops every feature and the anti-idle turn at once, since tick() checks
-- the switch before anything else. On starts eating and casting afresh rather
-- than waiting out timers left from before it was switched off.
local function setTrainerEnabled(enabled)
    trainerEnabled = enabled
    showMasterState()
    saveSettings()
    if enabled then
        nextEatAt = 0
        lastAntiIdleTime = 0
        resetCooldowns()
    else
        setHint(nil)
    end
end

local function startTicking()
    if not tickEvent then
        tickEvent = cycleEvent(tick, TICK_INTERVAL)
    end
end

local function stopTicking()
    if tickEvent then
        tickEvent:cancel()
        tickEvent = nil
    end
end

function toggle()
    if not trainerWindow then
        return
    end

    if trainerWindow:isVisible() then
        trainerWindow:close()
    else
        trainerWindow:open()
    end
end

function onMiniWindowOpen()
    if trainerButton then
        trainerButton:setOn(true)
    end
end

function onMiniWindowClose()
    if trainerButton then
        trainerButton:setOn(false)
    end
end

function online()
    -- Back in the panel, slot and open state this character left it in. Detached
    -- first because UIMiniWindowContainer:scheduleInsert ignores the saved index
    -- for a window already in that panel.
    trainerWindow:setParent(nil, true)
    trainerWindow:setupOnStart()
    trainerButton:setOn(trainerWindow:isExplicitlyVisible())

    -- Collapsed the first time a character sees it, their own choice after that.
    -- Here rather than in init() because the saved state is per character and
    -- there is no character name until login.
    trainerWindow:applyMinimizedPreference(true)

    loadSettings()
    markSpellFields()
    requestCastableSpells()
    setHint(nil)
    nextEatAt = 0
    lastAntiIdleTime = g_clock.millis()
    resetCooldowns()
    startTicking()
end

function offline()
    saveSettings()
    stopTicking()
    setHint(nil)
    castableSpells = nil
end

function init()
    trainerWindow = g_ui.loadUI('trainer', modules.game_interface.getRightPanel())
    -- Drag the bottom border to resize. The minimum sits just under the natural
    -- content height so there is room to shrink as well as grow.
    trainerWindow:enableResize()
    trainerWindow:setContentMinimumHeight(146)
    trainerWindow:setContentMaximumHeight(420)
    trainerWindow:setup()

    contentsPanel = trainerWindow:getChildById('contentsPanel')
    for _, id in ipairs({ 'masterToggle', 'autoEat', 'autoEatHint', 'manaTraining', 'manaSpell', 'manaPercent',
                          'runemaking', 'runeSpell', 'runePercent' }) do
        controls[id] = contentsPanel:getChildById(id)
    end

    -- A button consumes its own click like a toggle does, so it releases the
    -- keyboard itself.
    controls.masterToggle.onClick = function()
        setTrainerEnabled(not trainerEnabled)
        releaseFocus()
    end
    showMasterState()

    -- Digits only, three of them: the percent fields are parsed with tonumber
    -- and a stray letter would silently switch that trainer off.
    for _, id in ipairs({ 'manaPercent', 'runePercent' }) do
        controls[id]:setValidCharacters('0123456789')
        controls[id]:setMaxLength(3)

        -- Hover and scroll to nudge the threshold, one point per notch, the way
        -- the client's own spin boxes behave (corelib/ui/uispinbox.lua:29).
        -- Overriding on the instance loses nothing: UITextEdit's handler only
        -- drives scrollbars, and a single-line field has none.
        --
        -- Consuming the wheel matters as much as handling it -- unconsumed it
        -- reaches the right panel underneath and scrolls the whole column while
        -- you are aiming at the field.
        --
        -- setText is what saves: it fires onTextChange, which is already wired
        -- to onSettingChanged below.
        controls[id].onMouseWheel = function(widget, _mousePos, direction)
            local step = direction == MouseWheelUp and 1 or -1
            local current = tonumber(widget:getText()) or 0
            widget:setText(tostring(math.min(100, math.max(0, current + step))))
            return true
        end
    end

    -- Returning false leaves UITextEdit's own C++ mouse handling (cursor
    -- placement, selection) to run as normal -- this only reconnects focus.
    for _, id in ipairs(FIELD_IDS) do
        controls[id].onMousePress = function(widget)
            forceFocusChain(widget)
            return false
        end
    end

    -- Catches clicks inside the window that never reach rootWidget, either
    -- because this window consumed them (chrome, empty space) or because a
    -- toggle did. Returning false leaves the click to its normal handling.
    trainerWindow.onMousePress = function(_widget, mousePos)
        releaseUnlessOnField(mousePos)
        return false
    end

    trainerWindow:getChildById('miniwindowTitle'):setText(tr('Trainer'))
    trainerWindow:getChildById('miniwindowIcon'):setImageSource('/images/icons/icon-prey-widget')


    -- Every control writes through on change, so a crash or a kill can't lose
    -- settings that were only going to be flushed at logout. Changing any of
    -- them also clears the learned backoff, so a slow spell's spacing is not
    -- inherited by the one that replaces it.
    local function onSettingChanged()
        saveSettings()
        resetCooldowns()
    end

    -- Toggling also drops the keyboard. A checkbox consumes its own click, so
    -- neither the window nor rootWidget handler ever sees it -- this is the
    -- only place a toggle press can be observed.
    for _, id in ipairs({ 'autoEat', 'manaTraining', 'runemaking' }) do
        controls[id].onCheckChange = function()
            onSettingChanged()
            releaseFocus()
        end
    end

    -- Deliberately NOT releasing here: onTextChange fires on every keystroke,
    -- so releasing would drop focus as soon as you typed a character.
    for _, id in ipairs(FIELD_IDS) do
        controls[id].onTextChange = onSettingChanged
    end

    -- A spell learned since login is missing from the list until it is asked
    -- for again, so typing something the list does not know asks.
    for _, id in ipairs({ 'manaSpell', 'runeSpell' }) do
        controls[id].onTextChange = function(widget, text)
            onSettingChanged()
            markSpellField(widget)
            if castableSpells and text ~= '' and not isCastable(text) then
                requestCastableSpells()
            end
        end
    end

    trainerButton = modules.game_mainpanel.addToggleButton('trainerButton', tr('Trainer'),
        '/images/options/button_frags', toggle)
    trainerButton:setOn(trainerWindow:isVisible())

    connect(g_game, { onGameStart = online, onGameEnd = offline, onTextMessage = onTextMessage })
    connect(rootWidget, { onMousePress = onRootMousePress })
    ProtocolGame.registerExtendedOpcode(TRAINER_SPELLS_OPCODE, onCastableSpells)

    if g_game.isOnline() then
        online()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = online, onGameEnd = offline, onTextMessage = onTextMessage })
    disconnect(rootWidget, { onMousePress = onRootMousePress })
    ProtocolGame.unregisterExtendedOpcode(TRAINER_SPELLS_OPCODE)
    stopTicking()

    if g_game.isOnline() then
        saveSettings()
    end

    if trainerButton then
        trainerButton:destroy()
        trainerButton = nil
    end

    if trainerWindow then
        trainerWindow:destroy()
        trainerWindow = nil
    end

    contentsPanel = nil
    controls = {}
end
