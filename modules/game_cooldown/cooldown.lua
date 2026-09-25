-- Spell exhausts above the chat: an Attack and a Healing tile for the two
-- shared lanes, then one tile per spell still cooling down. 8.60 has no
-- cooldown packet, so the server sends each cast's figures over this opcode
-- (Spell::sendCooldowns in OTSERV src/spells.cpp).
local SPELL_COOLDOWNS_OPCODE = 78
local TICK_MS = 50

cooldownWindow = nil
cooldownPanel = nil

local groups = {}
local spells = {}
local tickEvent = nil

local TIMER_FROM_MS = 3000

local function createTimer(parent, fillTarget)
    local label = g_ui.createWidget('SpellTimerLabel', parent)
    label:fill(fillTarget)
    return label
end

local function showProgress(entry, now)
    entry.rect:setPercent(math.min(100, (now - entry.startedAt) * 100 / entry.duration))
    if entry.duration > TIMER_FROM_MS then
        entry.timer:setText(math.ceil((entry.endsAt - now) / 1000))
    else
        entry.timer:setText('')
    end
end

local function hideProgress(entry)
    entry.rect:setPercent(100)
    entry.timer:setText('')
end

local function tick()
    tickEvent = nil
    local now = g_clock.millis()
    local busy = false

    for _, group in pairs(groups) do
        if group.endsAt then
            if now >= group.endsAt then
                group.endsAt = nil
                hideProgress(group)
                group.icon:setOn(false)
            else
                showProgress(group, now)
                busy = true
            end
        end
    end

    for key, entry in pairs(spells) do
        if now >= entry.endsAt then
            entry.icon:destroy()
            spells[key] = nil
        else
            showProgress(entry, now)
            busy = true
        end
    end

    if busy then
        tickEvent = scheduleEvent(tick, TICK_MS)
    end
end

local function ensureTicking()
    if not tickEvent then
        tickEvent = scheduleEvent(tick, TICK_MS)
    end
end

local function startGroup(name, ms)
    local group = groups[name]
    if ms <= 0 then
        return
    end
    local now = g_clock.millis()
    group.startedAt = now
    group.duration = ms
    group.endsAt = now + ms
    showProgress(group, now)
    group.icon:setOn(true)
end

local function initials(name)
    local letters = ''
    for word in name:gmatch('%S+') do
        letters = letters .. word:sub(1, 1):upper()
    end
    return letters:sub(1, 2)
end

local function createSpellIcon(runeClientId, words, name)
    if runeClientId > 0 then
        local icon = g_ui.createWidget('SpellRuneIcon', cooldownPanel)
        icon:setItemId(runeClientId)
        return icon
    end

    local spell, profile = Spells.getSpellByWords(words)
    if not spell then
        profile = Spells.getSpellProfileByName(name)
        spell = profile and SpellInfo[profile][name]
    end
    local settings = spell and SpelllistSettings[profile]
    if settings then
        local icon = g_ui.createWidget('SpellIcon', cooldownPanel)
        icon:setImageSource(settings.iconsForGameCooldown)
        icon:setImageClip(Spells.getImageClipCooldown(spell.clientId, profile))
        return icon
    end

    local icon = g_ui.createWidget('SpellTextIcon', cooldownPanel)
    icon:setText(initials(name))
    return icon
end

local function startSpell(ms, runeClientId, words, name)
    if ms <= 0 or name == '' then
        return
    end

    local entry = spells[name]
    if not entry then
        local icon = createSpellIcon(runeClientId, words, name)
        local rect = g_ui.createWidget('SpellProgressRect', icon)
        rect:fill('parent')
        entry = {icon = icon, rect = rect, timer = createTimer(icon, 'parent')}
        spells[name] = entry
    end

    local now = g_clock.millis()
    entry.startedAt = now
    entry.duration = ms
    entry.endsAt = now + ms
    showProgress(entry, now)
    entry.icon:setTooltip(string.format('%s (%.1f sec. cooldown)', name, ms / 1000))
end

local function onSpellCooldowns(protocol, opcode, buffer)
    local attack, heal, own, rune, words, name = buffer:match('^(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)|(.*)$')
    if not attack then
        return
    end

    startGroup('attack', tonumber(attack))
    startGroup('healing', tonumber(heal))
    startSpell(tonumber(own), tonumber(rune), words, name)
    ensureTicking()
end

local function clear()
    removeEvent(tickEvent)
    tickEvent = nil
    for _, group in pairs(groups) do
        group.endsAt = nil
        hideProgress(group)
        group.icon:setOn(false)
    end
    for _, entry in pairs(spells) do
        entry.icon:destroy()
    end
    spells = {}
end

local function online()
    local console = modules.game_console.consolePanel
    if console then
        console:addAnchor(AnchorTop, cooldownWindow:getId(), AnchorBottom)
    end
end

local function offline()
    clear()
    local console = modules.game_console.consolePanel
    if console then
        console:removeAnchor(AnchorTop)
        console:fill('parent')
    end
end

function init()
    cooldownWindow = g_ui.loadUI('cooldown', modules.game_interface.getBottomPanel())
    cooldownPanel = cooldownWindow:getChildById('cooldownPanel')
    groups.attack = {
        icon = cooldownWindow:getChildById('groupIconAttack'),
        rect = cooldownWindow:getChildById('progressRectAttack')
    }
    groups.healing = {
        icon = cooldownWindow:getChildById('groupIconHealing'),
        rect = cooldownWindow:getChildById('progressRectHealing')
    }
    for _, group in pairs(groups) do
        group.timer = createTimer(cooldownWindow, group.icon:getId())
    end

    for _, settings in pairs(SpelllistSettings) do
        g_textures.preload(settings.iconsForGameCooldown)
    end

    setSpellCooldownsVisible(modules.client_options.getOption('showSpellCooldowns'))
    ProtocolGame.registerExtendedOpcode(SPELL_COOLDOWNS_OPCODE, onSpellCooldowns)
    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline
    })

    if g_game.isOnline() then
        online()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline
    })
    ProtocolGame.unregisterExtendedOpcode(SPELL_COOLDOWNS_OPCODE)
    clear()
    cooldownWindow:destroy()
end

function setSpellCooldownsVisible(visible)
    cooldownWindow:setVisible(visible)
    cooldownWindow:setHeight(visible and 24 or 0)
end
