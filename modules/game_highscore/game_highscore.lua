-- The website's highscores in game. The server ranks (OTSERV data/lib/core/highscores.lua)
-- and answers over extended opcode 86 (data/scripts/highscores/highscores.lua); this only
-- asks and draws. The stock module this replaced read Tibia 13's highscore packet, which
-- an 8.60 server never sends.

local HIGHSCORES_OPCODE = 86
local ONLINE_COLOR = '#60f860'
local OWN_ROW_COLOR = '#ffffff22'

local window = nil
local highscoreButton = nil
local filling = false

local state = {
    list = 'experience',
    vocation = -1,
    page = 1,
    pages = 1,
}

local function send(request)
    local protocolGame = g_game.isOnline() and g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedOpcode(HIGHSCORES_OPCODE, json.encode(request))
    end
end

local function setBusy(busy)
    window.prev:setEnabled(not busy and state.page > 1)
    window.next:setEnabled(not busy and state.page < state.pages)
    window.ownRankButton:setEnabled(not busy)
end

local function request(page, own)
    setBusy(true)
    send({ list = state.list, vocation = state.vocation, page = page, own = own or nil })
end

-- Filled from the server's answer, so the lists and vocations are named in one place.
local function fillFilters(data)
    filling = true
    if #window.listBox.options ~= #data.lists then
        window.listBox:clearOptions()
        for _, list in ipairs(data.lists) do
            window.listBox:addOption(list.label, list.key)
        end
    end
    if #window.vocationBox.options ~= #data.vocations + 1 then
        window.vocationBox:clearOptions()
        window.vocationBox:addOption(tr('All'), -1)
        for _, vocation in ipairs(data.vocations) do
            window.vocationBox:addOption(vocation.name, vocation.id)
        end
    end
    window.listBox:setCurrentOptionByData(data.list, true)
    window.vocationBox:setCurrentOptionByData(data.vocation, true)
    filling = false
end

local function setOutfit(widget, row)
    local creature = widget.creature
    if not creature then
        creature = Creature.create()
        widget.creature = creature
    end
    creature:setOutfit({ type = row[8], head = row[9], body = row[10], legs = row[11], feet = row[12], addons = row[13] })
    creature:setDirection(South)
    widget:setCreature(creature)
end

local function onHighscores(data)
    state.list, state.vocation = data.list, data.vocation
    state.page, state.pages = data.page, data.pages
    fillFilters(data)

    local isExperience = data.list == 'experience'
    local listLabel = window.listBox:getCurrentOption().text
    local vocationText = data.vocation >= 0 and (' (' .. window.vocationBox:getCurrentOption().text .. ')') or ''
    window.title:setText(tr('Ranking for %s%s', listLabel, vocationText))
    window.header.level:setText(isExperience and tr('Level') or listLabel)
    window.header.points:setText(isExperience and tr('Points') or '')

    local ownName = g_game.getCharacterName():lower()
    local rows = window.rows
    rows:getLayout():disableUpdates()
    rows:destroyChildren()
    local ownWidget
    for _, row in ipairs(data.rows) do
        local widget = g_ui.createWidget('HighscoreRow', rows)
        widget.rank:setText(row[1] .. '.')
        widget.name:setText(row[2])
        widget.vocation:setText(row[3])
        widget.level:setText(comma_value(row[5]))
        widget.points:setText(isExperience and comma_value(row[6]) or '')
        if row[7] == 1 then
            widget.name:setColor(ONLINE_COLOR)
        end
        setOutfit(widget.outfit, row)
        if row[2]:lower() == ownName then
            widget:setBackgroundColor(OWN_ROW_COLOR)
            ownWidget = widget
        end
    end
    rows:getLayout():enableUpdates()
    rows:getLayout():update()

    window.empty:setVisible(#data.rows == 0)
    window.page:setText(tr('Page %d / %d', state.page, state.pages))
    window.total:setText(tr('%d characters', data.total))
    setBusy(false)

    if ownWidget and data.own then
        addEvent(function()
            if not ownWidget:isDestroyed() then
                rows:ensureChildVisible(ownWidget)
            end
        end)
    elseif data.own == 0 then
        modules.game_textmessage.displayFailureMessage(tr('You are not on this list.'))
    else
        window.rowsScroll:setValue(0)
    end
end

local function onExtendedOpcode(protocol, opcode, buffer)
    local ok, data = pcall(json.decode, buffer)
    if not ok or type(data) ~= 'table' or type(data.rows) ~= 'table' then
        g_logger.error('[game_highscore] bad payload: ' .. tostring(data))
        return
    end
    if window then
        onHighscores(data)
    end
end

function onListChange(widget, text, data)
    if filling then
        return
    end
    state.list = data
    request(1)
end

function onVocationChange(widget, text, data)
    if filling then
        return
    end
    state.vocation = data
    request(1)
end

function nextPage()
    request(state.page + 1)
end

function prevPage()
    request(state.page - 1)
end

function showOwnRank()
    request(1, true)
end

function show()
    window:show()
    window:raise()
    window:focus()
    highscoreButton:setOn(true)
    request(state.page)
end

function hide()
    window:hide()
    highscoreButton:setOn(false)
end

function toggle()
    if window:isVisible() then
        hide()
    else
        show()
    end
end

local function onGameEnd()
    hide()
    state.page = 1
end

function init()
    window = g_ui.displayUI('game_highscore')
    window:hide()
    window.listBox.onOptionChange = onListChange
    window.vocationBox.onOptionChange = onVocationChange

    highscoreButton = modules.game_mainpanel.addToggleButton('highscoreButton', tr('Highscores'),
        '/images/options/highscores', toggle)
    highscoreButton:setOn(false)

    ProtocolGame.registerExtendedOpcode(HIGHSCORES_OPCODE, onExtendedOpcode)
    connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
    disconnect(g_game, { onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedOpcode(HIGHSCORES_OPCODE, onExtendedOpcode)

    if highscoreButton then
        highscoreButton:destroy()
        highscoreButton = nil
    end
    if window then
        window:destroy()
        window = nil
    end
end
