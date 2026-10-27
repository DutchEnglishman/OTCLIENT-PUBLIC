-- The guild window: bank, donating, upgrading, the ten passive picks, the leader's
-- spending rules, kicking and disbanding. Everything is decided by the server
-- (data/guild_upgrades/ in OTSERV); this only draws the last state it sent and sends one
-- action at a time over GUILD_OPCODE.
local GUILD_OPCODE = 87
local WAIVER_HEIGHT = 30
local ACTION_ANSWER_MS = 3000

-- Client ids of the decorative sprites; the passives' own icons come from the server.
local BANK_ICON = 3031
local NEXT_ICON = 3043
local DONATED_ICON = 3035
local CREST_ICON = 3419

local PAGES = { 'overview', 'passives', 'spending', 'members', 'log' }

local window = nil
local guildButton = nil
local state = nil
local currentPage = 'overview'
local lastActionAt = 0

local function send(message)
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
        if message.a ~= 'state' and message.a ~= 'log' then
            lastActionAt = g_clock.millis()
        end
        protocolGame:sendExtendedOpcode(GUILD_OPCODE, json.encode(message))
    end
end

local function formatGold(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    local formatted = text:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (formatted:gsub('^,', ''))
end

-- 1,200,000 as 1.2kk, which is how players read gold at a glance.
local function shortGold(value)
    value = tonumber(value) or 0
    if value >= 1000000 then
        return (('%.2f'):format(value / 1000000):gsub('%.?0+$', '')) .. 'kk'
    elseif value >= 1000 then
        return (('%.1f'):format(value / 1000):gsub('%.?0+$', '')) .. 'k'
    end
    return tostring(math.floor(value))
end

-- "50k" and "2.5kk" as well as plain digits, since that is how players write gold.
local function parseGold(text)
    text = (text or ''):lower():gsub('%s', ''):gsub(',', '')
    local number, suffix = text:match('^([%d%.]+)(k*)$')
    number = tonumber(number)
    if not number then
        return nil
    end
    return math.floor(number * 1000 ^ #suffix)
end

local function child(id)
    return window:recursiveGetChildById(id)
end

local function setStatus(text, ok)
    if not window then
        return
    end
    local label = child('statusLabel')
    label:setText(text or '')
    label:setColor(ok == false and '#e8857a' or '#a9d18e')
end

local function confirm(title, text, onYes)
    local box
    local function yes()
        box:destroy()
        onYes()
    end
    local function no()
        box:destroy()
    end
    box = displayGeneralBox(title, text, { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = no } }, yes, no)
end

-- An item sprite asked for before Tibia.dat is loaded crashes the client, so nothing is
-- drawn until it is (in game it always is).
local function setIcon(slot, clientId)
    local icon = slot:recursiveGetChildById('icon')
    if clientId and clientId > 0 and g_things.isDatLoaded() then
        icon:setItemId(clientId)
        icon:setVisible(true)
    else
        icon:setVisible(false)
    end
end

-- A bar `fill` inside `track`, filled to `fraction`; the fill's margins are the frame.
local function setBar(track, fill, fraction)
    fraction = math.max(0, math.min(1, fraction or 0))
    local inner = track:getWidth() - fill:getMarginLeft() - fill:getMarginRight()
    fill:setWidth(math.max(0, math.floor(inner * fraction)))
    fill:setVisible(fraction > 0)
end

local function canPick()
    return state and (state.rank == 'leader' or state.rank == 'vice')
end

local function isLeader()
    return state and state.member and state.rank == 'leader'
end

-- ------------------------------------------------------------------- Drawing

local RANK_NAMES = { leader = tr('Leader'), vice = tr('Vice-leader'), member = tr('Member') }

local function drawHeader()
    local member = state and state.member
    child('levelBadge'):setVisible(member == true)
    child('upgradeButton'):setVisible(member == true)
    child('progressTrack'):setVisible(member == true)
    child('progressCaption'):setVisible(member == true)

    if not member then
        child('guildName'):setText(tr('No guild'))
        child('guildSub'):setText('')
        return
    end

    setIcon(child('crestSlot'), CREST_ICON)
    child('guildName'):setText(state.guildName)
    child('guildSub'):setText(RANK_NAMES[state.rank] or state.rank)
    child('levelValue'):setText(tostring(state.level))
    child('levelMax'):setText(tr('of %d', state.maxLevel))

    local upgrade = child('upgradeButton')
    local track, fill = child('progressTrack'), child('progressFill')
    if state.nextCost > 0 then
        child('progressCaption'):setText(tr('Guild bank toward level %d', state.level + 1))
        child('progressText'):setText(tr('%s / %s gold', formatGold(state.balance), formatGold(state.nextCost)))
        setBar(track, fill, state.balance / state.nextCost)
        upgrade:setText(tr('Upgrade to level %d', state.level + 1))
        upgrade:setEnabled(state.balance >= state.nextCost and canPick())
        if not canPick() then
            upgrade:setTooltip(tr('Only the leader and vice-leaders can upgrade the guild.'))
        elseif state.balance < state.nextCost then
            upgrade:setTooltip(tr('The bank needs %s more gold.', formatGold(state.nextCost - state.balance)))
        else
            upgrade:removeTooltip()
        end
    else
        child('progressCaption'):setText(tr('The guild has reached its highest level'))
        child('progressText'):setText(tr('%s gold in the bank', formatGold(state.balance)))
        setBar(track, fill, 1)
        upgrade:setText(tr('Highest level'))
        upgrade:setEnabled(false)
        upgrade:removeTooltip()
    end
end

local function drawWaiver()
    local waiver = child('waiverPanel')
    if state and state.waiver then
        waiver:recursiveGetChildById('waiverText'):setText(tr('The leader of %s asks you to leave without your donations paid back.', state.waiver))
        waiver:setHeight(WAIVER_HEIGHT)
        waiver:setVisible(true)
    else
        waiver:setVisible(false)
        waiver:setHeight(0)
    end
end

local function statCard(id, icon, caption, value)
    local card = child(id)
    setIcon(card:recursiveGetChildById('slot'), icon)
    card:recursiveGetChildById('caption'):setText(caption)
    card:recursiveGetChildById('value'):setText(value)
end

local function drawOverview()
    statCard('bankCard', BANK_ICON, tr('GUILD BANK'), formatGold(state.balance) .. ' gold')
    statCard('nextCard', NEXT_ICON, state.nextCost > 0 and tr('NEXT LEVEL COSTS') or tr('NEXT LEVEL'),
        state.nextCost > 0 and (formatGold(state.nextCost) .. ' gold') or tr('highest reached'))
    statCard('donatedCard', DONATED_ICON, tr('YOU DONATED'), formatGold(state.myDonation) .. ' gold')

    child('yourBank'):setText(tr('Your bank: %s gold', formatGold(state.bank)))

    local grid = child('activeGrid')
    grid:destroyChildren()
    local count = 0
    for _, tier in ipairs(state.tiers or {}) do
        if tier.choice > 0 and state.level >= tier.tier then
            count = count + 1
            local row = g_ui.createWidget('GuildActivePassive', grid)
            setIcon(row:recursiveGetChildById('slot'), tier.icons and tier.icons[tier.choice])
            row:recursiveGetChildById('label'):setText(tier.options[tier.choice])
        end
    end
    child('activeCount'):setText(tr('%d of %d', count, #(state.tiers or {})))
    child('activeEmpty'):setVisible(count == 0)
end

local function pickOption(tier, index)
    local label = tier.options[index]
    local function go()
        send({ a = 'pick', tier = tier.tier, choice = index })
    end
    if tier.choice == 0 then
        confirm(tr('Choose passive'), tr('Choose "%s" for level %d?\nIts first change later is free.', label, tier.tier), go)
    elseif tier.changeCost > 0 then
        confirm(tr('Change passive'), tr('Change level %d to "%s" for %s gold from the guild bank?', tier.tier, label, formatGold(tier.changeCost)), go)
    else
        confirm(tr('Change passive'), tr('Change level %d to "%s"?\nThis uses its one free change; after that a change costs gold.', tier.tier, label), go)
    end
end

local function drawPassives()
    child('passivesHint'):setText(canPick()
        and tr('Every third guild level opens a choice of two. Every member carries what the guild picks. A pick\'s first change is free.')
        or tr('Every third guild level opens a choice of two, picked by the leader or a vice-leader.'))

    local list = child('passiveList')
    local scroll = child('passiveScroll'):getValue()
    list:destroyChildren()

    for _, tier in ipairs(state.tiers or {}) do
        local row = g_ui.createWidget('GuildPassiveRow', list)
        local reached = state.level >= tier.tier
        local badge = row:recursiveGetChildById('badge')
        badge:recursiveGetChildById('tier'):setText(tostring(tier.tier))
        badge:recursiveGetChildById('tier'):setColor(reached and '#eef2f6' or '#64686f')
        badge:setOpacity(reached and 1 or 0.6)

        for index = 1, 2 do
            local card = row:recursiveGetChildById('option' .. index)
            card:recursiveGetChildById('label'):setText(tier.options[index] or '')
            setIcon(card:recursiveGetChildById('slot'), tier.icons and tier.icons[index])
            card:setOn(tier.choice == index)
            card:recursiveGetChildById('active'):setVisible(tier.choice == index and reached)
            card:setEnabled(reached and canPick() and tier.choice ~= index)
            card.onClick = function()
                pickOption(tier, index)
            end
        end

        local cost = row:recursiveGetChildById('cost')
        if not reached then
            cost:setText(tr('opens at\nlevel %d', tier.tier))
            cost:setColor('#64686f')
        elseif tier.choice == 0 then
            cost:setText(tr('choose\none'))
            cost:setColor('#e2c27a')
        elseif tier.changeCost > 0 then
            cost:setText(tr('change:\n%s', shortGold(tier.changeCost)))
            cost:setColor('#8a8e95')
        else
            cost:setText(tr('first change\nis free'))
            cost:setColor('#a9d18e')
        end
    end
    child('passiveScroll'):setValue(scroll)
end

local function drawSpendCard(id, title, icon, on, cap, spent)
    local card = child(id)
    setIcon(card:recursiveGetChildById('slot'), icon)
    card:recursiveGetChildById('title'):setText(title)

    if on then
        card:recursiveGetChildById('status'):setText(tr('Paid by the guild, up to %s gold per member a day.', formatGold(cap)))
        card:recursiveGetChildById('status'):setColor('#a9d18e')
        card:recursiveGetChildById('trackText'):setText(tr('you used %s of %s today', formatGold(spent), formatGold(cap)))
        setBar(card:recursiveGetChildById('track'), card:recursiveGetChildById('fill'), cap > 0 and spent / cap or 1)
    else
        card:recursiveGetChildById('status'):setText(tr('Not paid by the guild.'))
        card:recursiveGetChildById('status'):setColor('#8a8e95')
        card:recursiveGetChildById('trackText'):setText(tr('switched off'))
        setBar(card:recursiveGetChildById('track'), card:recursiveGetChildById('fill'), 0)
    end

    local leader = isLeader()
    local enabled, cap_ = card:recursiveGetChildById('enabled'), card:recursiveGetChildById('cap')
    enabled:setVisible(leader)
    card:recursiveGetChildById('capCaption'):setVisible(leader)
    cap_:setVisible(leader)
    if leader then
        enabled:setChecked(on == true)
        cap_:setText(tostring(cap or 0))
    end
end

local function drawSpending()
    drawSpendCard('suppliesCard', tr('Potions and runes'), state.suppliesIcon, state.suppliesOn, state.suppliesCap, state.spentSupplies)
    drawSpendCard('blessingCard', tr('Blessings and amulets of loss'), state.blessingIcon, state.blessingOn, state.blessingCap, state.spentBlessing)
    child('saveSpending'):setVisible(isLeader() == true)
    child('leaderOnly'):setVisible(not isLeader())

    local useGuildGold = child('useGuildGold')
    useGuildGold.drawing = true
    useGuildGold:setChecked(state.useGuildGold == true)
    useGuildGold.drawing = nil
end

local function drawMembers()
    local list = child('memberList')
    list:destroyChildren()

    for index, entry in ipairs(state.members or {}) do
        local row = g_ui.createWidget('GuildMemberRow', list)
        if index % 2 == 0 then
            row:setBackgroundColor('#ffffff08')
        end
        row:recursiveGetChildById('name'):setText(entry.name)
        row:recursiveGetChildById('rank'):setText(RANK_NAMES[entry.rank] or entry.rank)
        row:recursiveGetChildById('donated'):setText(entry.net > 0 and (formatGold(entry.net) .. ' gold') or '-')

        local kick = row:recursiveGetChildById('kickButton')
        local covered = entry.net <= state.balance
        kick:setEnabled(covered)
        kick:setTooltip(covered
            and tr('Pays back %s gold from the guild bank.', formatGold(entry.net))
            or tr('%s donated %s gold and the bank holds %s. Ask them to leave instead.', entry.name, formatGold(entry.net), formatGold(state.balance)))
        kick.onClick = function()
            confirm(tr('Kick'), tr('Kick %s and pay back %s gold from the guild bank?', entry.name, formatGold(entry.net)),
                function() send({ a = 'kick', guid = entry.guid }) end)
        end

        row:recursiveGetChildById('waiverButton').onClick = function()
            confirm(tr('Ask to leave'), tr('Ask %s to accept a kick without their donations paid back?', entry.name),
                function() send({ a = 'kickWaiver', guid = entry.guid }) end)
        end
    end

    child('dangerText'):setText(tr('The %s gold in the bank is paid back to the members in proportion to what they donated. Levels and passives are lost for good.',
        formatGold(state.balance)))
end

local function drawLog(entries)
    local list = child('logList')
    list:destroyChildren()
    for index, entry in ipairs(entries or {}) do
        local row = g_ui.createWidget('GuildLogRow', list)
        if index % 2 == 0 then
            row:setBackgroundColor('#ffffff08')
        end
        row:recursiveGetChildById('when'):setText(os.date('%d %b, %H:%M', entry.time))
        local text = (entry.name ~= '' and entry.name .. ' ' or '') .. entry.what
        if entry.detail and entry.detail ~= '' then
            text = text .. ' - ' .. entry.detail
        end
        row:recursiveGetChildById('text'):setText(text)
        row:recursiveGetChildById('amount'):setText(entry.amount and entry.amount ~= 0 and (formatGold(entry.amount) .. ' gold') or '')
    end
end

local function showPage(page)
    local member = state and state.member
    if not member and page ~= 'overview' then
        page = 'overview'
    end
    if page == 'members' and not isLeader() then
        page = 'overview'
    end
    currentPage = page

    child('notInGuild'):setVisible(not member)
    for _, name in ipairs(PAGES) do
        local tab = child('tab' .. name:sub(1, 1):upper() .. name:sub(2))
        tab:setOn(name == page)
        child(name .. 'Page'):setVisible(member == true and name == page)
    end
    child('tabPassives'):setEnabled(member == true)
    child('tabSpending'):setEnabled(member == true)
    child('tabLog'):setEnabled(member == true)
    child('tabMembers'):setVisible(isLeader() == true)
end

local function draw()
    if not window then
        return
    end
    drawWaiver()
    drawHeader()
    if state and state.member then
        drawOverview()
        drawPassives()
        drawSpending()
        if isLeader() then
            drawMembers()
        end
    end
    showPage(currentPage)
end

-- ------------------------------------------------------------------ Protocol

function onExtendedOpcode(protocol, code, buffer)
    if code ~= GUILD_OPCODE then
        return
    end
    local ok, data = pcall(json.decode, buffer)
    if not ok or type(data) ~= 'table' then
        return
    end

    if data.a == 'state' then
        data = JsonChunks.receive(GUILD_OPCODE .. ':state', data, 'members')
        if data then
            state = data
            draw()
        end
    elseif data.a == 'log' then
        data = JsonChunks.receive(GUILD_OPCODE .. ':log', data, 'log')
        if data and window then
            drawLog(data.log)
        end
    end
end

-- -------------------------------------------------------------- Open / close

function open()
    if not g_game.isOnline() then
        return
    end
    window:show()
    window:raise()
    window:focus()
    setStatus('')
    if guildButton then
        guildButton:setOn(true)
    end
    send({ a = 'state' })
    send({ a = 'log' })
end

function close()
    if window then
        window:hide()
    end
    if guildButton then
        guildButton:setOn(false)
    end
end

function toggle()
    if window:isVisible() then
        close()
    else
        open()
    end
end

local function onGameEnd()
    close()
    state = nil
end

-- The server answers every action with a text message; the status line shows it, so a
-- refusal is visible without looking at the console. Only shortly after an action, or a
-- Look or a potion would land there too.
local function onTextMessage(mode, text)
    if window and window:isVisible() and g_clock.millis() - lastActionAt < ACTION_ANSWER_MS
            and (mode == MessageModes.Failure or mode == MessageModes.Look) then
        setStatus(text, mode ~= MessageModes.Failure)
    end
end

local function donate(amount)
    if not amount or amount <= 0 then
        setStatus(tr('Type how much gold to donate, e.g. 100000 or 100k.'), false)
        return
    end
    confirm(tr('Donate'), tr('Donate %s gold from your bank to %s?\nDonations are only paid back if you are kicked or the guild is disbanded.',
        formatGold(amount), state and state.guildName or ''), function()
        send({ a = 'donate', amount = amount })
        child('donateEdit'):setText('')
    end)
end

function init()
    window = g_ui.displayUI('guild')
    window:hide()

    for _, name in ipairs(PAGES) do
        child('tab' .. name:sub(1, 1):upper() .. name:sub(2)).onClick = function()
            showPage(name)
            if name == 'log' then
                send({ a = 'log' })
            end
        end
    end

    child('waiverAccept').onClick = function()
        confirm(tr('Leave guild'), tr('Leave %s without your donations paid back?', state and state.waiver or ''),
            function() send({ a = 'waiver', accept = true }) end)
    end
    child('waiverDecline').onClick = function()
        send({ a = 'waiver', accept = false })
    end

    child('upgradeButton').onClick = function()
        if state and state.nextCost > 0 then
            confirm(tr('Upgrade guild'), tr('Spend %s gold from the guild bank on level %d?', formatGold(state.nextCost), state.level + 1),
                function() send({ a = 'upgrade' }) end)
        end
    end

    child('donateButton').onClick = function()
        donate(parseGold(child('donateEdit'):getText()))
    end
    for id, amount in pairs({ quick100k = 100000, quick1kk = 1000000, quick10kk = 10000000 }) do
        child(id).onClick = function()
            child('donateEdit'):setText(formatGold(amount))
        end
    end

    child('useGuildGold').onCheckChange = function(widget, checked)
        if not widget.drawing then
            send({ a = 'useGuildGold', on = checked })
        end
    end

    child('saveSpending').onClick = function()
        local supplies, blessing = child('suppliesCard'), child('blessingCard')
        local suppliesCap = parseGold(supplies:recursiveGetChildById('cap'):getText())
        local blessingCap = parseGold(blessing:recursiveGetChildById('cap'):getText())
        if not suppliesCap or not blessingCap then
            setStatus(tr('The daily limits must be amounts of gold, e.g. 50000 or 50k.'), false)
            return
        end
        send({
            a = 'spending',
            suppliesOn = supplies:recursiveGetChildById('enabled'):isChecked(),
            blessingOn = blessing:recursiveGetChildById('enabled'):isChecked(),
            suppliesCap = suppliesCap,
            blessingCap = blessingCap,
        })
    end

    child('disbandButton').onClick = function()
        if state then
            confirm(tr('Disband guild'),
                tr('Disband %s for good?\nThe %s gold in the bank is paid back to the members in proportion to what they donated. Levels and passives are lost.',
                    state.guildName, formatGold(state.balance)),
                function() send({ a = 'disband' }) end)
        end
    end

    -- The bars are sized from their track's width, which is only known once laid out.
    child('progressTrack').onGeometryChange = function()
        if state and state.member then
            drawHeader()
        end
    end

    guildButton = modules.game_mainpanel.addToggleButton('guildButton', tr('Guild'),
        '/modules/game_guild/images/button_guild', toggle)
    guildButton:setOn(false)

    drawWaiver()
    drawHeader()
    showPage('overview')

    connect(g_game, { onGameEnd = onGameEnd, onTextMessage = onTextMessage })
    ProtocolGame.registerExtendedOpcode(GUILD_OPCODE, onExtendedOpcode)
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(GUILD_OPCODE, onExtendedOpcode)
    disconnect(g_game, { onGameEnd = onGameEnd, onTextMessage = onTextMessage })

    if guildButton then
        guildButton:destroy()
        guildButton = nil
    end
    if window then
        window:destroy()
        window = nil
    end
    state = nil
end
