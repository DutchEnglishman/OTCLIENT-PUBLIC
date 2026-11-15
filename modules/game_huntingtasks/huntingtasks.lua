-- Hunting tasks: the task window and the Task Tracker, for two boards that
-- share this module -- Grizzly Adams' (opcode 98, data/hunting_tasks/ on
-- OTSERV) and Bram the Old Trapper's Paw and Fur Society on Rookgaard (opcode
-- 105, data/rook_hunting_tasks/).
--
-- The server owns all state. Every payload is complete, and every button only
-- asks and waits for the next payload, on the opcode of the board shown.
--   {action = 'window', open, level, maxActive, maxRuns, laterRewards, active, tasks}
--   {action = 'tracker', active = {{id, name, kills, required, outfit}, ...}}
-- Bram's adds `npc`, `marks` (spendable hunting marks), `repeatable` (a task
-- past its last stage can be started again) and per task `stages` (one reward
-- list per stage, in place of the shared `laterRewards`).

HUNTING_TASKS_OPCODE = 98
ROOK_HUNTING_TASKS_OPCODE = 105
local BOARD_OPCODES = {HUNTING_TASKS_OPCODE, ROOK_HUNTING_TASKS_OPCODE}

local window = nil
local tracker = nil
local trackerButton = nil
local protocol = nil

-- The board whose window is on screen, and its last payload.
local state = nil
local stateOpcode = HUNTING_TASKS_OPCODE
-- Last tracker payload per board, and the board the tracker shows.
local trackers = {}
local trackerOpcode = nil
local currentTab = 'active'
local selectedId = nil

local SORTS = {'Level', 'Name', 'Kills'}
local COLOR_DONE = '#6fae5c'
local COLOR_CURRENT = '#d39b3a'
local COLOR_EMPTY = '#2a2b2f'

local function send(request)
    if protocol then
        protocol:sendExtendedOpcode(stateOpcode, json.encode(request))
    end
end

-- "Bram the Old Trapper" -> "Bram"; Grizzly's board names no npc.
local function npcShortName(npc)
    return type(npc) == 'string' and npc:match('^%S+') or 'Grizzly'
end

local function canStartAgain(task)
    return task.runs < state.maxRuns or state.repeatable == true
end

local function emptyOutfit()
    return {type = 0, head = 0, body = 0, legs = 0, feet = 0, addons = 0}
end

local function activeEntry(id)
    for _, entry in ipairs(state and state.active or {}) do
        if entry.id == id then
            return entry
        end
    end
    return nil
end

local function taskById(id)
    for _, task in ipairs(state and state.tasks or {}) do
        if task.id == id then
            return task
        end
    end
    return nil
end

local function inTab(task, tab)
    if tab == 'active' then
        return activeEntry(task.id) ~= nil
    elseif tab == 'completed' then
        return task.runs > 0
    end
    return not activeEntry(task.id) and canStartAgain(task)
end

local function matches(task, query)
    if query == '' or task.name:lower():find(query, 1, true) then
        return true
    end
    for _, monster in ipairs(task.monsters or {}) do
        if monster:find(query, 1, true) then
            return true
        end
    end
    return false
end

local function countIn(tab)
    local n = 0
    for _, task in ipairs(state.tasks) do
        if inTab(task, tab) then
            n = n + 1
        end
    end
    return n
end

local function setPips(row, runs, maxRuns)
    for i = 1, 3 do
        local pip = row:recursiveGetChildById('pip' .. i)
        if i > maxRuns then
            pip:setVisible(false)
        elseif i <= runs then
            pip:setBackgroundColor(COLOR_DONE)
        elseif i == runs + 1 then
            pip:setBackgroundColor(COLOR_CURRENT)
        else
            pip:setBackgroundColor(COLOR_EMPTY)
        end
    end
end

local function fillRun(widget, title, lines, status)
    widget:getChildById('title'):setText(title .. (status == 'done' and '  (done)' or ''))
    widget:getChildById('lines'):setText(#lines > 0 and ('- ' .. table.concat(lines, '\n- ')) or '-')
    widget:setBorderColor(status == 'current' and COLOR_CURRENT or '#0e0f11')
    widget:getChildById('title'):setColor(status == 'current' and COLOR_CURRENT or (status == 'done' and COLOR_DONE or '#8a8e95'))
    widget:setOpacity(status == 'done' and 0.6 or 1)
end

local function refreshDetail()
    local detail = window:getChildById('detail')
    local task = selectedId and taskById(selectedId)
    detail:setVisible(task ~= nil)
    if not task then
        return
    end

    local entry = activeEntry(task.id)
    detail:getChildById('creature'):setOutfit(task.outfit or emptyOutfit())
    detail:getChildById('name'):setText(task.name)
    detail:getChildById('counts'):setText('Counts: ' .. table.concat(task.monsters or {}, ', '))

    local function fact(id, title, value)
        local widget = detail:getChildById(id)
        widget:getChildById('title'):setText(title)
        widget:getChildById('value'):setText(value)
    end
    local repeating = state.repeatable == true and task.runs >= state.maxRuns
    fact('factKills', tr('Kills'), tostring(task.kills))
    if task.stages then
        -- Bram's tasks carry no recommended level; the slot shows the stage.
        fact('factLevel', tr('Next stage'), repeating and tr('Repeat') or string.format('%d / %d', task.runs + 1, state.maxRuns))
    else
        fact('factLevel', tr('Recommended level'), tostring(task.level))
    end
    fact('factRuns', tr('Completed'), string.format('%d / %d', task.runs, state.maxRuns))

    local progress = detail:getChildById('progress')
    progress:setVisible(entry ~= nil)
    progress:setHeight(entry and 16 or 0)
    progress:setMarginTop(entry and 8 or 0)
    if entry then
        local kills = math.min(entry.kills, task.kills)
        progress:setPercent(math.floor(100 * kills / math.max(task.kills, 1)))
        progress:setText(string.format('%d / %d', kills, task.kills))
    end

    for run = 1, 3 do
        local widget = detail:getChildById('run' .. run)
        widget:setVisible(run <= state.maxRuns)
        if task.stages then
            local lines = task.stages[run] or {}
            local status = run <= task.runs and 'done' or (run == task.runs + 1 and 'current' or nil)
            local title = tr('Stage %d', run)
            if repeating and run == state.maxRuns then
                -- A repeat pays the last stage's hunting marks and nothing else.
                status = 'current'
                title = tr('Stage %d - repeat: marks only', run)
            end
            fillRun(widget, title, lines, status)
        else
            local lines = run == 1 and (task.reward or {}) or (state.laterRewards[run - 1] or {})
            local status = run <= task.runs and 'done' or (run == task.runs + 1 and 'current' or nil)
            fillRun(widget, tr('Run %d', run), lines, status)
        end
    end

    local startButton = detail:getChildById('startButton')
    local cancelButton = detail:getChildById('cancelButton')
    local claimButton = detail:getChildById('claimButton')
    startButton:setVisible(entry == nil)
    cancelButton:setVisible(entry ~= nil)
    claimButton:setVisible(entry ~= nil)
    startButton:setEnabled(canStartAgain(task) and #state.active < state.maxActive)
    claimButton:setEnabled(entry ~= nil and entry.kills >= task.kills)
end

local function sortTasks(list)
    local sortBy = window:getChildById('sortBox'):getText()
    table.sort(list, function(a, b)
        if sortBy == 'Name' then
            return a.name < b.name
        elseif sortBy == 'Kills' then
            if a.kills ~= b.kills then return a.kills < b.kills end
        elseif a.level ~= b.level then
            return a.level < b.level
        end
        return a.name < b.name
    end)
end

function refreshList()
    if not window or not state then
        return
    end

    local query = window:getChildById('searchEdit'):getText():lower()
    local list = {}
    for _, task in ipairs(state.tasks) do
        if inTab(task, currentTab) and matches(task, query) then
            list[#list + 1] = task
        end
    end
    sortTasks(list)

    local taskList = window:getChildById('taskList')
    taskList:destroyChildren()

    local selectedRow = nil
    for _, task in ipairs(list) do
        local row = g_ui.createWidget('HuntingTaskRow', taskList)
        row.taskId = task.id
        row:getChildById('creature'):setOutfit(task.outfit or emptyOutfit())
        row:getChildById('name'):setText(task.name)
        local entry = activeEntry(task.id)
        local bar = row:getChildById('bar')
        if entry then
            row:getChildById('sub'):setText(string.format('%d / %d', math.min(entry.kills, task.kills), task.kills))
            bar:setPercent(math.floor(100 * math.min(entry.kills, task.kills) / math.max(task.kills, 1)))
        else
            if task.stages then
                row:getChildById('sub'):setText(string.format('%d kills', task.kills))
            else
                row:getChildById('sub'):setText(string.format('Lv %d  -  %d kills', task.level, task.kills))
            end
            bar:setVisible(false)
        end
        setPips(row, task.runs, state.maxRuns)
        if task.id == selectedId then
            selectedRow = row
        end
    end

    -- Keep the selection when it is still in the list, otherwise take the top.
    if not selectedRow then
        selectedRow = taskList:getFirstChild()
    end
    if selectedRow then
        selectedId = selectedRow.taskId
        taskList:focusChild(selectedRow, KeyboardFocusReason)
        taskList:ensureChildVisible(selectedRow)
    else
        selectedId = nil
    end

    local emptyText = ''
    if #list == 0 then
        emptyText = currentTab == 'active' and tr('No active tasks. Pick one under Available.') or tr('No tasks match.')
    end
    window:getChildById('emptyLabel'):setText(emptyText)

    refreshDetail()
end

local function refreshHeader()
    window:getChildById('tab_active'):setText(tr('Active') .. string.format(' %d/%d', #state.active, state.maxActive))
    window:getChildById('tab_available'):setText(tr('Available') .. ' ' .. countIn('available'))
    window:getChildById('tab_completed'):setText(tr('Completed') .. ' ' .. countIn('completed'))
    for _, tab in ipairs({'active', 'available', 'completed'}) do
        window:getChildById('tab_' .. tab):setOn(tab == currentTab)
    end

    local slots = window:recursiveGetChildById('slots')
    slots:destroyChildren()
    for i = 1, state.maxActive do
        local slot = g_ui.createWidget('HuntingTaskSlot', slots)
        if i <= #state.active then
            slot:setBackgroundColor(COLOR_CURRENT)
        end
    end
    window:recursiveGetChildById('levelLabel'):setText(tr('Your level: %d', state.level))
    local marksLabel = window:recursiveGetChildById('marksLabel')
    marksLabel:setVisible(state.marks ~= nil)
    if state.marks ~= nil then
        marksLabel:setText(tr('Hunting marks: %d', tonumber(state.marks) or 0))
    end
end

function selectTab(tab)
    currentTab = tab
    selectedId = nil
    if state then
        refreshHeader()
        refreshList()
    end
end

function onAction(action)
    if selectedId then
        send({action = action, id = selectedId})
    end
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

-- Task Tracker --------------------------------------------------------------

local function refreshTracker(active, maxActive, npc)
    if not tracker then
        return
    end
    local panel = tracker:getChildById('contentsPanel')
    panel:destroyChildren()
    local doneText = tr('Done: report to %s', npcShortName(npc))
    for _, entry in ipairs(active or {}) do
        local row = g_ui.createWidget('HuntingTrackerRow', panel)
        local kills = math.min(entry.kills, entry.required)
        local done = kills >= entry.required
        row:getChildById('creature'):setOutfit(entry.outfit or emptyOutfit())
        row:getChildById('name'):setText(entry.name)
        row:getChildById('name'):setColor(done and COLOR_DONE or '#eef2f6')
        local bar = row:getChildById('bar')
        bar:setPercent(math.floor(100 * kills / math.max(entry.required, 1)))
        bar:setText(done and doneText or string.format('%d / %d', kills, entry.required))
        bar:setBackgroundColor(done and COLOR_DONE or COLOR_CURRENT)
    end
    for _ = #(active or {}) + 1, maxActive or 5 do
        g_ui.createWidget('HuntingTrackerEmpty', panel)
    end
end

function toggleTracker()
    if not tracker then
        return
    end
    if tracker:isVisible() then
        tracker:close()
    else
        if not tracker:getParent() then
            local panel = modules.game_interface.findContentPanelAvailable(tracker, tracker:getMinimumHeight())
            if not panel then
                return
            end
            panel:addChild(tracker)
        end
        tracker:open()
    end
end

function onTrackerOpen()
    if trackerButton then
        trackerButton:setOn(true)
    end
end

function onTrackerClose()
    if trackerButton then
        trackerButton:setOn(false)
    end
end

-- Wiring --------------------------------------------------------------------

-- One tracker for both boards. A player only ever plays one of them (Bram's is
-- Rookgaard's, Grizzly's wants a vocation), so the tracker follows the board
-- that last reported running tasks, and an empty report from the other board
-- never clears it.
local function onTrackerPayload(code, payload)
    local active = type(payload.active) == 'table' and payload.active or {}
    trackers[code] = {active = active, npc = payload.npc}
    local shown = trackerOpcode and trackers[trackerOpcode]
    if #active > 0 or not shown or trackerOpcode == code or #shown.active == 0 then
        trackerOpcode = code
    end
    local current = trackers[trackerOpcode]
    local maxActive = state and stateOpcode == trackerOpcode and state.maxActive or nil
    refreshTracker(current.active, maxActive, current.npc)

    -- Kills arrive here only, so an open window takes its numbers from it too.
    if state and stateOpcode == code then
        state.active = active
        if window:isVisible() then
            refreshHeader()
            refreshList()
        end
    end
end

local function onOpcode(proto, code, buffer)
    protocol = proto
    local ok, payload = pcall(json.decode, buffer)
    if not ok or type(payload) ~= 'table' then
        return
    end

    if payload.action == 'tracker' then
        onTrackerPayload(code, payload)
        return
    end

    if payload.action ~= 'window' then
        return
    end
    payload = JsonChunks.receive(code, payload, 'tasks')
    if not payload then
        return
    end

    -- A refresh from the board not on screen is dropped; only "open" switches boards.
    if state and stateOpcode ~= code and not payload.open then
        return
    end
    stateOpcode = code
    state = payload
    state.tasks = type(state.tasks) == 'table' and state.tasks or {}
    state.active = type(state.active) == 'table' and state.active or {}
    state.laterRewards = type(state.laterRewards) == 'table' and state.laterRewards or {}

    if payload.open then
        currentTab = #state.active > 0 and 'active' or 'available'
        selectedId = nil
    end
    refreshHeader()
    refreshList()
    if payload.open then
        show()
    end
end

local function onGameStart()
    if not trackerButton then
        trackerButton = modules.game_mainpanel.addToggleButton('huntingTasksTrackerButton', tr('Task Tracker'),
            '/images/options/button_taskboard', toggleTracker)
    end
    tracker:setupOnStart()
    trackerButton:setOn(tracker:isVisible())
end

local function onGameEnd()
    hide()
    state = nil
    stateOpcode = HUNTING_TASKS_OPCODE
    trackers = {}
    trackerOpcode = nil
    protocol = nil
    if tracker then
        tracker:getChildById('contentsPanel'):destroyChildren()
    end
end

function init()
    g_ui.importStyle('huntingtasks')

    window = g_ui.createWidget('HuntingTasksWindow', modules.game_interface.getRootPanel())
    window:hide()

    local sortBox = window:getChildById('sortBox')
    for _, label in ipairs(SORTS) do
        sortBox:addOption(label)
    end
    sortBox.onOptionChange = function() refreshList() end

    window:getChildById('taskList').onChildFocusChange = function(_, focused)
        if focused and focused.taskId and focused.taskId ~= selectedId then
            selectedId = focused.taskId
            refreshDetail()
        end
    end

    tracker = g_ui.createWidget('HuntingTasksTracker', modules.game_interface.getRightPanel())
    tracker:setContentMinimumHeight(60)
    tracker:setup()
    tracker:hide()

    Keybind.new("Windows", "Show/hide task tracker", "Alt+T", "")
    Keybind.bind("Windows", "Show/hide task tracker", {{type = KEY_DOWN, callback = toggleTracker}})

    for _, code in ipairs(BOARD_OPCODES) do
        ProtocolGame.registerExtendedOpcode(code, onOpcode)
    end
    connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    for _, code in ipairs(BOARD_OPCODES) do
        ProtocolGame.unregisterExtendedOpcode(code)
    end
    disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
    Keybind.delete("Windows", "Show/hide task tracker")
    if trackerButton then
        trackerButton:destroy()
        trackerButton = nil
    end
    if tracker then
        tracker:destroy()
        tracker = nil
    end
    if window then
        window:destroy()
        window = nil
    end
    protocol = nil
end
