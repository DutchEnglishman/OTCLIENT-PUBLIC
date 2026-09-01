-- The Task Master's window: three task slots side by side, each with its own
-- difficulty buttons.
--
-- The client holds no state. Every payload from the server is the complete
-- window, and every button press sends a request and waits for the next
-- payload, so there is nothing here that can drift out of step with the server.

PERIODIC_TASKS_OPCODE = 68

local window = nil
local protocol = nil

local COLUMN_WIDTH = 150
local COLUMN_SPACING = 8

local function send(request)
    if protocol then
        protocol:sendExtendedOpcode(PERIODIC_TASKS_OPCODE, json.encode(request))
    end
end

local function capitalize(text)
    return (text:gsub('^%l', string.upper))
end

-- "2d 4h" / "6h 12m" / "43m". Deliberately coarse: the deadline is measured in
-- days, and a ticking seconds counter would need a redraw cycle to stay honest.
local function formatRemaining(seconds)
    if not seconds or seconds <= 0 then
        return ''
    end

    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if days > 0 then
        return string.format('%dd %dh left', days, hours)
    end
    if hours > 0 then
        return string.format('%dh %dm left', hours, minutes)
    end
    return string.format('%dm left', minutes)
end

local function clearCreature(slotWidget)
    -- UICreature has no "clear": an outfit of type 0 is what renders as empty,
    -- which is what an unassigned slot has to look like.
    slotWidget:getChildById('creature'):setOutfit({type = 0, head = 0, body = 0, legs = 0, feet = 0, addons = 0})
end

local function buildColumn(parent, entry, difficulties, previous)
    local column = g_ui.createWidget('PeriodicTaskColumn', parent)
    column:setId(entry.key)
    column:setWidth(COLUMN_WIDTH)

    column:addAnchor(AnchorTop, 'parent', AnchorTop)
    column:addAnchor(AnchorBottom, 'parent', AnchorBottom)

    if previous then
        -- The vertical border the brief asks for, between each pair of columns.
        local separator = g_ui.createWidget('VerticalSeparator', parent)
        separator:addAnchor(AnchorTop, 'parent', AnchorTop)
        separator:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        separator:addAnchor(AnchorLeft, previous:getId(), AnchorRight)
        separator:setMarginLeft(COLUMN_SPACING / 2)

        column:addAnchor(AnchorLeft, previous:getId(), AnchorRight)
        column:setMarginLeft(COLUMN_SPACING)
    else
        column:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    end

    column:getChildById('title'):setText(entry.label)

    local bossSlot = column:getChildById('bossSlot')
    local hasBoss = (entry.bossRequired or 0) > 0
    bossSlot:setVisible(hasBoss)
    bossSlot:setHeight(hasBoss and 52 or 0)
    if not hasBoss then
        bossSlot:setMarginTop(0)
    end

    local monsterSlot = column:getChildById('monsterSlot')
    local nameLabel = column:getChildById('monsterName')
    local progressLabel = column:getChildById('progress')
    local bossLineLabel = column:getChildById('bossLine')
    local expiryLabel = column:getChildById('expiry')
    local rewardTitleLabel = column:getChildById('rewardTitle')
    local rewardLabel = column:getChildById('reward')
    local buttons = column:getChildById('buttons')
    local reroll = column:getChildById('reroll')
    local changeDifficulty = column:getChildById('changeDifficulty')

    buttons:destroyChildren()

    -- Shown in both states: the whole point is to be able to compare what the
    -- three slots pay before committing to one.
    --
    -- The payload sends one line per reward, so the monthly's task points and
    -- crystal coins stack instead of running together on one line.
    --
    -- A plain string is accepted as well as a list. The two repos deploy
    -- separately, so a client running ahead of the server WILL meet the old
    -- single-string shape -- and table.concat on a string throws, which aborted
    -- this function and took the rest of the column down with it.
    local reward = entry.reward
    local rewardLines

    if type(reward) == 'table' then
        rewardLines = reward
    elseif type(reward) == 'string' and reward ~= '' then
        rewardLines = {reward}
    else
        rewardLines = {}
    end

    local LINE_HEIGHT = 14

    rewardTitleLabel:setText(#rewardLines > 0 and 'Reward' or '')
    rewardLabel:setText(table.concat(rewardLines, '\n'))
    rewardLabel:setHeight(math.max(1, #rewardLines) * LINE_HEIGHT)

    if entry.assigned then
        monsterSlot:getChildById('creature'):setOutfit(entry.outfit)
        nameLabel:setText(capitalize(entry.monster))
        progressLabel:setText(string.format('%d / %d', entry.progress, entry.required))
        expiryLabel:setText(formatRemaining(entry.secondsLeft))

        if hasBoss and entry.boss then
            bossSlot:getChildById('creature'):setOutfit(entry.bossOutfit)
            bossLineLabel:setText(string.format('%s  %d / %d',
                capitalize(entry.boss), entry.bossProgress or 0, entry.bossRequired))
        else
            bossLineLabel:setText('')
        end

        reroll:setVisible(true)
        reroll:setText(string.format('Reroll (%d)', entry.rerollsLeft or 0))
        reroll:setEnabled((entry.rerollsLeft or 0) > 0)

        -- One per assignment. Hidden rather than disabled once spent, so the
        -- corner does not carry a button that can never do anything again.
        changeDifficulty:setVisible(entry.undoAvailable == true)
    else
        clearCreature(monsterSlot)
        if hasBoss then
            clearCreature(bossSlot)
        end

        nameLabel:setText('')
        progressLabel:setText(string.format('%d kills', entry.required))
        bossLineLabel:setText(hasBoss and string.format('+ %d boss kills', entry.bossRequired) or '')
        expiryLabel:setText('')

        reroll:setVisible(false)
        changeDifficulty:setVisible(false)

        -- Built from the payload rather than the style, so the labels and the
        -- level hints stay owned by the server config.
        local previousButton = nil
        for _, difficulty in ipairs(difficulties) do
            local button = g_ui.createWidget('PeriodicTaskDifficultyButton', buttons)
            button:setText(string.format('%s (%s)', difficulty.label, difficulty.hint))
            button:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            button:addAnchor(AnchorRight, 'parent', AnchorRight)

            if previousButton then
                button:addAnchor(AnchorTop, previousButton:getId(), AnchorBottom)
                button:setMarginTop(3)
            else
                button:addAnchor(AnchorTop, 'parent', AnchorTop)
            end

            button:setId(entry.key .. '_' .. difficulty.key)
            button.slotKey = entry.key
            button.difficultyKey = difficulty.key
            button.onClick = function(self)
                send({action = 'assign', slot = self.slotKey, difficulty = self.difficultyKey})
            end

            previousButton = button
        end
    end

    return column
end

local function rebuild(payload)
    if not window then
        return
    end

    local container = window:getChildById('columns')
    container:destroyChildren()

    local previous = nil
    for _, entry in ipairs(payload.slots or {}) do
        previous = buildColumn(container, entry, payload.difficulties or {}, previous)
    end
end

function onReroll(slotKey)
    send({action = 'reroll', slot = slotKey})
end

-- Throws the task away and hands the slot back to the difficulty buttons. The
-- server enforces the one-per-assignment cap; this only asks.
function onChangeDifficulty(slotKey)
    send({action = 'undo', slot = slotKey})
end

function show()
    if window then
        window:show()
        window:raise()
        window:focus()
    end
end

function hide()
    if window then
        window:hide()
    end
end

local function onOpcode(proto, code, buffer)
    protocol = proto

    local ok, payload = pcall(json.decode, buffer)
    if not ok or type(payload) ~= 'table' or payload.action ~= 'tasks' then
        return
    end

    rebuild(payload)

    -- Only the Task Master's payload carries open, so only it puts the window on
    -- screen -- still one round trip, no separate "open the window" message.
    -- Arrival used to be the open signal on its own, which meant every refresh
    -- popped the window: the server sends one after each credited kill to keep
    -- the progress numbers live, and one at login.
    if payload.open then
        show()
    end
end

local function onGameEnd()
    hide()
    protocol = nil
end

function init()
    g_ui.importStyle('periodictasks')

    window = g_ui.createWidget('PeriodicTasksWindow', modules.game_interface.getRootPanel())
    window:hide()

    ProtocolGame.registerExtendedOpcode(PERIODIC_TASKS_OPCODE, onOpcode)
    connect(g_game, {onGameEnd = onGameEnd})
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(PERIODIC_TASKS_OPCODE)
    disconnect(g_game, {onGameEnd = onGameEnd})

    if window then
        window:destroy()
        window = nil
    end

    protocol = nil
end
