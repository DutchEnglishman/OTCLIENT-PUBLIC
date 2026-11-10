MessageSettings = {
    none = {},
    consoleYellow = {
        color = TextColors.yellow,
        consoleTab = 'Local Chat'
    },
    consoleRed = {
        color = TextColors.red,
        consoleTab = 'Local Chat'
    },
    consoleOrange = {
        color = TextColors.orange,
        consoleTab = 'Local Chat'
    },
    consoleBlue = {
        color = TextColors.blue,
        consoleTab = 'Local Chat'
    },
    centerRed = {
        color = TextColors.red,
        consoleTab = 'Server Log',
        screenTarget = 'lowCenterLabel'
    },
    -- Raids get their own label rather than one of the centre three: those sit
    -- in centerTextMessagePanel, which is centerIn: parent with fit-children,
    -- so a lone message in any of them lands on the middle of the map -- which
    -- is exactly where the character stands.
    raid = {
        color = TextColors.red,
        consoleTab = 'Server Log',
        screenTarget = 'raidLabel',
        consoleOption = 'showEventMessagesInConsole'
    },
    centerGreen = {
        color = TextColors.green,
        consoleTab = 'Server Log',
        screenTarget = 'highCenterLabel',
        consoleOption = 'showInfoMessagesInConsole'
    },
    hotkeyUse = {
        color = TextColors.green,
        consoleTab = 'Server Log',
        screenTarget = 'hotkeyLabel',
        consoleOption = 'showInfoMessagesInConsole'
    },
    centerWhite = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'middleCenterLabel',
        consoleOption = 'showEventMessagesInConsole'
    },
    bottomWhite = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showEventMessagesInConsole'
    },
    status = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showStatusMessagesInConsole'
    },
    statusOwn = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        consoleOption = 'showStatusMessagesInConsole'
    },
    statusBoosted = {
        color = TextColors.white,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showBoostedMessagesInConsole'
    },
    -- othersStatus sat here with an option and a checkbox of its own, and no
    -- message mode was ever mapped to it, so none of the three did anything.
    -- Other people's status lines are filtered by involvesLocalPlayer below
    -- instead, because on this protocol they cannot be told apart by mode.
    statusSmall = {
        color = TextColors.white,
        screenTarget = 'statusLabel'
    },
    -- OTSERV's MESSAGE_STATUS_CONSOLE_RED (18), which carries only "Your questlog
    -- has been updated." when the same action already put a message on the
    -- map centre (Player::addStorageValue, src/player.cpp).
    statusRed = {
        color = TextColors.red,
        consoleTab = 'Server Log',
        screenTarget = 'statusLabel',
        consoleOption = 'showEventMessagesInConsole'
    },
    private = {
        color = TextColors.lightblue,
        consoleTab = 'Local Chat',
        screenTarget = 'privateLabel'
    },
    privateRed = {
        color = TextColors.red,
        consoleTab = 'Local Chat',
        private = true
    },
    privatePlayerToPlayer = {
        color = TextColors.blue,
        consoleTab = 'Local Chat',
        private = true
    },
    privatePlayerToNpc = {
        color = TextColors.blue,
        consoleTab = 'Local Chat',
        private = true,
        npcChat = true
    },
    privateNpcToPlayer = {
        color = TextColors.lightblue,
        consoleTab = 'Local Chat',
        private = true,
        npcChat = true
    },
    channelYellow = {
        color = TextColors.yellow
    },
    channelWhite = {
        color = TextColors.white
    },
    channelRed = {
        color = TextColors.red
    },
    channelOrange = {
        color = TextColors.orange
    },
    monsterSay = {
        color = TextColors.orange,
        hideInConsole = true
    },
    monsterYell = {
        color = TextColors.orange,
        hideInConsole = true
    },
    potion = {
        color = TextColors.orange,
        hideInConsole = true
    },
    loot = {
        color = TextColors.white,
        consoleTab = 'Loot',
        screenTarget = 'highCenterLabel',
        consoleOption = 'showInfoMessagesInConsole',
        colored = true
    },
    valuableLoot = {
        color = TextColors.white,
        consoleTab = 'Loot',
        screenTarget = 'statusLabel',
        consoleOption = 'showInfoMessagesInConsole',
        colored = true
    }
}

MessageTypes = {
    [MessageModes.Say] = MessageSettings.consoleYellow,
    [MessageModes.Whisper] = MessageSettings.consoleYellow,
    [MessageModes.Yell] = MessageSettings.consoleYellow,
    [MessageModes.MonsterSay] = MessageSettings.monsterSay,
    [MessageModes.MonsterYell] = MessageSettings.monsterYell,
    [MessageModes.BarkLow] = MessageSettings.consoleOrange,
    [MessageModes.BarkLoud] = MessageSettings.consoleOrange,
    [MessageModes.Failure] = MessageSettings.statusSmall,
    [MessageModes.Login] = MessageSettings.bottomWhite,
    [MessageModes.Game] = MessageSettings.centerWhite,
    [MessageModes.Raid] = MessageSettings.raid,
    [MessageModes.Status] = MessageSettings.status,
    [MessageModes.Warning] = MessageSettings.centerRed,
    [MessageModes.Look] = MessageSettings.centerGreen,
    [MessageModes.Loot] = MessageSettings.loot,
    [MessageModes.Red] = MessageSettings.statusRed,
    [MessageModes.Blue] = MessageSettings.consoleBlue,
    [MessageModes.PrivateFrom] = MessageSettings.private,
    [MessageModes.PrivateTo] = MessageSettings.privatePlayerToPlayer,
    [MessageModes.GamemasterPrivateFrom] = MessageSettings.privateRed,
    [MessageModes.NpcTo] = MessageSettings.privatePlayerToNpc,
    [MessageModes.NpcFrom] = MessageSettings.privateNpcToPlayer,
    [MessageModes.NpcFromStartBlock] = MessageSettings.privateNpcToPlayer,
    [MessageModes.Channel] = MessageSettings.channelYellow,
    [MessageModes.ChannelManagement] = MessageSettings.channelWhite,
    [MessageModes.GamemasterChannel] = MessageSettings.channelRed,
    [MessageModes.ChannelHighlight] = MessageSettings.channelOrange,
    [MessageModes.Spell] = MessageSettings.consoleYellow,
    [MessageModes.RVRChannel] = MessageSettings.channelWhite,
    [MessageModes.RVRContinue] = MessageSettings.consoleYellow,

    [MessageModes.GamemasterBroadcast] = MessageSettings.consoleRed,

    [MessageModes.DamageDealed] = MessageSettings.statusOwn,
    [MessageModes.DamageReceived] = MessageSettings.statusOwn,
    [MessageModes.Heal] = MessageSettings.statusOwn,
    [MessageModes.Exp] = MessageSettings.statusOwn,

    [MessageModes.DamageOthers] = MessageSettings.statusOwn,
    [MessageModes.HealOthers] = MessageSettings.statusOwn,
    [MessageModes.ExpOthers] = MessageSettings.statusOwn,
    [MessageModes.Potion] = MessageSettings.potion,

    [MessageModes.TradeNpc] = MessageSettings.centerGreen,
    [MessageModes.Guild] = MessageSettings.statusOwn,
    [MessageModes.Party] = MessageSettings.statusOwn,
    [MessageModes.PartyManagement] = MessageSettings.centerGreen,
    [MessageModes.TutorialHint] = MessageSettings.statusSmall,
    [MessageModes.BeyondLast] = MessageSettings.centerWhite,
    [MessageModes.Report] = MessageSettings.centerWhite,
    [MessageModes.GameHighlight] = MessageSettings.centerRed,
    [MessageModes.HotkeyUse] = MessageSettings.hotkeyUse,
    [MessageModes.Attention] = MessageSettings.bottomWhite,
    [MessageModes.BoostedCreature] = MessageSettings.centerWhite,
    [MessageModes.OfflineTrainning] = MessageSettings.centerWhite,
    [MessageModes.Transaction] = MessageSettings.centerWhite,
    [MessageModes.ValuableLoot] = MessageSettings.valuableLoot,

    [254] = MessageSettings.private
}

-- The on-screen system messages end just above the character's name. The
-- name's top is Creature::drawInformation's: the point (-displacementY - 2)
-- drawn px above the tile's top, displacement 8 for a standard outfit, less
-- the 12 px name crop.
NAME_TILES_ABOVE_TILE_TOP = 10 / 32
-- The name is centred (16 - displacementX) drawn px right of the tile's left
-- edge, not on the tile's centre: a standard outfit is drawn 8 px up-left, so
-- the character and its name sit a quarter tile left of the tile centre.
NAME_TILES_LEFT_OF_TILE_CENTRE = 8 / 32
NAME_HEIGHT = 12
GAP_ABOVE_HEAD = 4
GAP_ABOVE_ARCS = 4

-- Top to bottom. A fixed order, so a line never swaps places with another
-- when one appears or expires.
local STACK_ORDER = { 'hotkeyLabel', 'lowCenterLabel', 'middleCenterLabel', 'highCenterLabel', 'raidLabel' }

-- Every label but the status line is parented to the map, not to a panel that
-- ends at the chat: anything laid out in such a panel -- anchored, or
-- unanchored and clamped back inside it by UIWidget::onGeometryChange -- moved
-- whenever the chat was resized. The map does not move with the chat and is
-- drawn under it, so the chat simply covers them. The status line is the one
-- meant to sit just above the chat, so it lives in messagesPanel.
local mapLabels = {}
messagesPanel = nil

function init()
    for messageMode, _ in pairs(MessageTypes) do
        registerMessageMode(messageMode, displayMessage)
    end

    connect(g_game, 'onGameEnd', clearMessages)
    messagesPanel = g_ui.loadUI('textmessage', modules.game_interface.getRootPanel())
    local map = modules.game_interface.getMapPanel()
    mapLabels = {}
    for _, id in ipairs(STACK_ORDER) do
        local label = g_ui.createWidget('ScreenMessageLabel', map)
        label:setId(id)
        mapLabels[id] = label
    end
    mapLabels.privateLabel = g_ui.createWidget('PrivateMessageLabel', map)
    -- The map itself does resize in windowed mode, where the chat takes its
    -- height; the character stays on its centre, so the labels follow it.
    connect(map, { onGeometryChange = placeMapLabels })
end

function terminate()
    for messageMode, _ in pairs(MessageTypes) do
        unregisterMessageMode(messageMode, displayMessage)
    end

    disconnect(g_game, 'onGameEnd', clearMessages)
    disconnect(modules.game_interface.getMapPanel(), { onGeometryChange = placeMapLabels })
    clearMessages()
    messagesPanel:destroy()
    messagesPanel = nil
    for _, label in pairs(mapLabels) do
        label:destroy()
    end
    mapLabels = {}
end

local function screenLabel(target)
    return mapLabels[target] or messagesPanel:recursiveGetChildById(target)
end

function calculateVisibleTime(text)
    return math.max(#text * 50, 4000)
end

-- Whether a Server Log line is about the player reading it.
--
-- It has to be decided from the text, because the mode cannot tell: OTSERV's
-- Game::combatChangeHealth sends MESSAGE_STATUS_DEFAULT for all three views of
-- the same hit -- the attacker's, the victim's, and every bystander's -- so on
-- this protocol they arrive as one indistinguishable MessageModes.Status.
--
-- What separates them is person. The server writes the reader's own lines in
-- the second person ("You lose 40 hitpoints", "... due to your attack") and
-- everybody else's in the third ("Crodar loses 150 hitpoints due to an attack
-- by Malvenor"). So: my name, or a second-person pronoun, means it is mine.
--
-- Matched on word boundaries. Without them a monster called "Younger Bonelord"
-- contains "you" and every line naming it would look personal.
local function involvesLocalPlayer(text)
    local player = g_game.getLocalPlayer()
    if not player then
        return true
    end

    local lower = text:lower()
    local name = player:getName()
    if name and name ~= '' then
        -- Whole word, not a substring: a player called Bo otherwise matches
        -- "Bonelord" and "Boris" and never hides anything. Non-word characters
        -- are escaped because names carry apostrophes (Bo'Ques).
        local escaped = name:lower():gsub('(%W)', '%%%1')
        if lower:find('%f[%w]' .. escaped .. '%f[%W]') then
            return true
        end
    end

    return lower:find('%f[%a]you%f[%A]') ~= nil or lower:find('%f[%a]your%f[%A]') ~= nil
end

-- Only the status family is filtered. Those are the combat and experience lines
-- the option is about; info, event, loot and private messages are addressed to
-- the reader already and are left alone whatever the setting says.
function wantedInServerLog(msgtype, text)
    if msgtype ~= MessageSettings.status and msgtype ~= MessageSettings.statusOwn then
        return true
    end
    if not modules.client_options.getOption('hideOthersServerLogMessages') then
        return true
    end
    return involvesLocalPlayer(text)
end

-- A critical hit's number arrives wrapped in SO/SI bytes (OTSERV critDamageText,
-- src/game.cpp). Returns the line as setColoredText markup with that number in
-- red and the rest in the line's own colour, plus the line with the bytes
-- removed; nil when the line carries no crit.
local CRIT_OPEN, CRIT_CLOSE = '\14', '\15'
local CRIT_COLOR = '#ff3030'

local function critMarkup(text, color)
    if not text:find(CRIT_OPEN, 1, true) then
        return nil
    end

    local parts = {}
    local pos = 1
    while true do
        local open = text:find(CRIT_OPEN, pos, true)
        local close = open and text:find(CRIT_CLOSE, open + 1, true)
        if not close then
            break
        end
        if open > pos then
            parts[#parts + 1] = string.format('{%s, %s}', text:sub(pos, open - 1), color)
        end
        parts[#parts + 1] = string.format('{%s, %s}', text:sub(open + 1, close - 1), CRIT_COLOR)
        pos = close + 1
    end
    if pos <= #text then
        parts[#parts + 1] = string.format('{%s, %s}', text:sub(pos), color)
    end
    return table.concat(parts), (text:gsub('[' .. CRIT_OPEN .. CRIT_CLOSE .. ']', ''))
end

function displayMessage(mode, text)

    if not g_game.isOnline() then
        return
    end
    if g_game.getClientVersion() >= 1300 then
        MessageTypes[MessageModes.Loot] = MessageSettings.loot
        MessageTypes[MessageModes.ValuableLoot] = MessageSettings.valuableLoot
        MessageTypes[MessageModes.Guild] = MessageSettings.statusOwn
        MessageTypes[MessageModes.Party] = MessageSettings.statusOwn
    else
        MessageTypes[MessageModes.PrivateFrom] = MessageSettings.privateNpcToPlayer
        MessageTypes[MessageModes.Loot] = MessageSettings.centerGreen
        MessageTypes[MessageModes.ValuableLoot] = MessageSettings.centerGreen
        MessageTypes[MessageModes.Guild] = MessageSettings.centerGreen
        MessageTypes[MessageModes.Party] = MessageSettings.centerGreen
        MessageTypes[MessageModes.MonsterSay] = MessageSettings.consoleOrange
        MessageTypes[MessageModes.MonsterYell] = MessageSettings.consoleOrange
    end
    -- Loot goes to Server Log for everyone and also to the Loot tab for
    -- premium players. It flashes green on screen only for players who switch
    -- showLootOnScreen on (Settings > Interface > Console).
    --
    -- Matched on the text because protocol 860 has no loot message mode:
    -- MessageModes.Loot is a 10.x addition. The server
    -- (OTSERV Player.sendLootMessage, data/lib/core/player.lua) sends premium
    -- players MESSAGE_INFO_DESCR (MessageModes.Look here) and everyone else
    -- MESSAGE_STATUS_DEFAULT, so the mode carries premium and the text marks
    -- the line as loot. The Server Log copy skips wantedInServerLog: a loot line
    -- is always the player's own, and it names neither "you" nor the player.
    -- Autoloot that could not fit everything (OTSERV AutoLootServer.warnLeftBehind,
    -- data/lib/core/autoloot.lua, which sends this prefix): red on screen for
    -- players who watch loot there, red in the Loot tab for the rest.
    if text:find('^Autoloot: ') then
        if modules.client_options.getOption('showLootOnScreen') then
            showOnScreen(MessageSettings.centerRed, text)
        else
            modules.game_console.addTabText(text, MessageSettings.centerRed, modules.game_console.ensureLootTab())
        end
        return
    end

    if text:find('^Loot of ') then
        local coloredText = ItemsDatabase.setColorLootMessage(text)
        modules.game_console.addText(coloredText, MessageSettings.loot, tr('Server Log'))
        if mode == MessageModes.Look then
            local lootTab = modules.game_console.ensureLootTab()
            modules.game_console.addTabText(coloredText, MessageSettings.loot, lootTab)
        end
        if modules.client_options.getOption('showLootOnScreen') then
            showOnScreen(MessageSettings.centerGreen, text, coloredText)
        end
        return
    end

    local msgtype = MessageTypes[mode]
    -- Same story as loot: 8.60 has no hotkey mode, the server sends these as
    -- MESSAGE_INFO_DESCR (Actions::showUseHotkeyMessage), so only the text
    -- tells them apart from "You see ...".
    if text:find('^Using one of ') or text:find('^Using the last ') then
        msgtype = MessageSettings.hotkeyUse
    end
    if not msgtype then
        return
    end

    if msgtype == MessageSettings.none then
        return
    end

    local critText, plainText = critMarkup(text, msgtype.color or TextColors.white)
    if critText then
        text = plainText
    end

    if msgtype.consoleTab ~= nil and
        (msgtype.consoleOption == nil or modules.client_options.getOption(msgtype.consoleOption)) and
        wantedInServerLog(msgtype, text) then
        if msgtype == MessageSettings.loot or msgtype == MessageSettings.valuableLoot then
            local lootColoredText = ItemsDatabase.setColorLootMessage(text)
            local lootTabName = tr(msgtype.consoleTab)
            local targetTab = modules.game_console.getTab(lootTabName) and lootTabName or tr("Server Log")
            modules.game_console.addText(lootColoredText, msgtype, targetTab)
        elseif critText then
            local coloredType = setmetatable({ colored = true }, { __index = msgtype })
            modules.game_console.addText(critText, coloredType, tr(msgtype.consoleTab))
        else
            modules.game_console.addText(text, msgtype, tr(msgtype.consoleTab))
        end
    end

    -- The same line is also flashed above the chat, so it is filtered on the
    -- same test: hidden from the log but still shown on screen would not be
    -- hiding it at all.
    if msgtype.screenTarget and wantedInServerLog(msgtype, text) then
        if msgtype == MessageSettings.loot and not modules.client_options.getOption('showLootOnScreen') then
            return
        end
        showOnScreen(msgtype, text, critText)
    end
end

function showOnScreen(msgtype, text, critText)
    local label = screenLabel(msgtype.screenTarget)
    if msgtype == MessageSettings.loot or msgtype == MessageSettings.valuableLoot then
        label:setColoredText(ItemsDatabase.setColorLootMessage(text))
    elseif critText then
        label:setColor(msgtype.color)
        label:setColoredText(critText)
    else
        label:setText(text)
        label:setColor(msgtype.color)
    end

    label:setVisible(true)
    placeMapLabels()
    removeEvent(label.hideEvent)
    label.hideEvent = scheduleEvent(function()
        label:setVisible(false)
        placeMapLabels()
    end, calculateVisibleTime(text))
end

-- Placed from the map widget itself rather than anchored: the chat is drawn
-- over the map in extended view, so nothing that ends at the chat knows where
-- the character stands.
function placeMapLabels()
    local map = modules.game_interface.getMapPanel()
    if not map or not mapLabels.privateLabel then
        return
    end
    local rect = map:getRect()
    local centerX, centerY, tile = getPlayerScreenCenter(map)
    centerX = centerX - tile * NAME_TILES_LEFT_OF_TILE_CENTRE

    local bottom = centerY - tile / 2 - tile * NAME_TILES_ABOVE_TILE_TOP - NAME_HEIGHT - GAP_ABOVE_HEAD
    -- The health/mana arcs are centred on the character and reach higher than
    -- its name, so while any is shown the stack ends just above them instead.
    local healthcircle = modules.game_healthcircle
    local arcsTop = healthcircle and healthcircle.getArcsTop and healthcircle.getArcsTop()
    if arcsTop then
        bottom = math.min(bottom, arcsTop - GAP_ABOVE_ARCS)
    end

    local stackHeight = 0
    for _, id in ipairs(STACK_ORDER) do
        if mapLabels[id]:isVisible() then
            stackHeight = stackHeight + mapLabels[id]:getHeight() + 2
        end
    end
    local y = math.max(rect.y, bottom - stackHeight)
    for _, id in ipairs(STACK_ORDER) do
        local label = mapLabels[id]
        if label:isVisible() then
            label:setPosition({x = math.floor(centerX - label:getWidth() / 2), y = math.floor(y)})
            y = y + label:getHeight() + 2
        end
    end

    -- A private message is centred halfway between the top of the map and the
    -- character, where it sat before the chat could move it.
    local private = mapLabels.privateLabel
    if private:isVisible() then
        private:setPosition({
            x = math.floor(centerX - private:getWidth() / 2),
            y = math.floor((rect.y + centerY) / 2 - private:getHeight() / 2)
        })
    end
end

function displayPrivateMessage(text)
    if not g_game.isOnline() then
        return
    end
    
    local msgtype = MessageSettings.private
    if not msgtype or not msgtype.screenTarget then
        return
    end
    
    local label = screenLabel(msgtype.screenTarget)
    if not label then
        return
    end

    label:setColor(msgtype.color)

    -- An item link reaches here as its full "[Name#id]" token, because the
    -- rarity is the first digit of that id -- strip it earlier and the colour
    -- goes with it. buildScreenMarkup drops the id and paints the name, and
    -- returns nil when the line holds no link, which keeps this plain text.
    local itemshare = modules.game_itemshare
    local shareData = itemshare and itemshare.buildScreenMarkup(text, msgtype.color)

    if shareData then
        label:setColoredText(shareData.markup)
    else
        label:setText(text)
    end

    label:setVisible(true)
    placeMapLabels()
    removeEvent(label.hideEvent)
    label.hideEvent = scheduleEvent(function()
        label:setVisible(false)
    end, calculateVisibleTime(text))
end

function displayStatusMessage(text)
    displayMessage(MessageModes.Status, text)
end

function displayFailureMessage(text)
    displayMessage(MessageModes.Failure, text)
end

function displayGameMessage(text)
    displayMessage(MessageModes.Game, text)
end

function displayBroadcastMessage(text)
    displayMessage(MessageModes.Warning, text)
end

function clearMessages()
    local status = messagesPanel:getChildById('statusLabel')
    status:hide()
    removeEvent(status.hideEvent)
    for _, label in pairs(mapLabels) do
        label:hide()
        removeEvent(label.hideEvent)
    end
end

function LocalPlayer:onAutoWalkFail(player)
    modules.game_textmessage.displayFailureMessage(tr('There is no way.'))
end
