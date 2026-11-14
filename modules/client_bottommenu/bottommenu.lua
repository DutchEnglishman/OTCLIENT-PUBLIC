local bottomMenu
local calendarWindow
local activeScheduleEvent
local upcomingScheduleEvent
local eventSchedulerYears
local calendarCurrentMonth
local calendarPrevButton
local calendarNextButton
local calendarCurrentDate
local showOffWindow

local eventSchedulerTimestamp
local eventSchedulerCalendar
local scheduleRefreshEvent
local eventSchedulerCalendarYearIndex
local eventSchedulerCalendarMonth

local boostedWindow

-- One is picked at random each time the login screen opens.
local default_info = {
    {
        image = "images/randomhint",
        Title = "Your Mailbox",
        description = "All mail you receive lands in the mailbox next to your depot chest. Coin shop items that don't fit in your backpack go there too."
    },
    {
        image = "images/randomhint",
        Title = "The Market",
        description = "Every depot locker has a market. Buy and sell items with other players for gold or coins."
    },
    {
        image = "images/randomhint",
        Title = "Spells Level Up",
        description = "Every spell you cast counts toward its next level, up to level 5. Each level makes the spell stronger."
    },
    {
        image = "images/randomhint",
        Title = "Daily, Weekly and Monthly Tasks",
        description = "The Task Master hands out daily, weekly and monthly hunting tasks. They pay out task points to spend in the task shop."
    },
    {
        image = "images/randomhint",
        Title = "Follow Your Quests",
        description = "Open the Quest channel (Open a new channel) to see every new quest and mission step as it happens. The Raid channel announces raids."
    },
    {
        image = "images/randomhint",
        Title = "Place a Bounty",
        description = "Say !hunt <name>, <crystals> to put a bounty on a player. Whoever kills them collects every open bounty at once."
    },
    {
        image = "images/randomhint",
        Title = "Boosted Creatures",
        description = "A new set of creatures is boosted every 6 hours. Hover one on the right for its bonuses, or open the Boosted window in game."
    },
}

function init()
    g_ui.importStyle('calendar')
    bottomMenu = g_ui.displayUI('bottommenu')

    calendarWindow = g_ui.createWidget('CalendarGrid', rootWidget)
    calendarCurrentMonth = calendarWindow:recursiveGetChildById('calendarCurrentMonth')
    calendarCurrentDate = calendarWindow:recursiveGetChildById('calendarCurrentDate')
    calendarPrevButton = calendarWindow:recursiveGetChildById('calendarPrevButton')
    calendarNextButton = calendarWindow:recursiveGetChildById('calendarNextButton')
    calendarWindow:hide()

    showOffWindow = bottomMenu:recursiveGetChildById('showOffWindow')
    showOffWindow.title = showOffWindow:recursiveGetChildById('showOffWindowText')
    activeScheduleEvent = bottomMenu:recursiveGetChildById('activeScheduleEvent')
    upcomingScheduleEvent = bottomMenu:recursiveGetChildById('upcomingScheduleEvent')
    upcomingScheduleEvent:recursiveGetChildById('fill'):setOn(false)
    eventSchedulerCalendarYearIndex = 1
    eventSchedulerCalendarMonth = tonumber(os.date("%m"))

    boostedWindow = bottomMenu:recursiveGetChildById('boostedWindow')

--  if not Services.status and default_info then
    if default_info then
        local scrollable = showOffWindow:recursiveGetChildById('contentsPanel')
        local widget = g_ui.createWidget('ShowOffWidget', scrollable)
        local description = widget:recursiveGetChildById('description')
        local image = widget:recursiveGetChildById('image')

        math.randomseed(os.time())
        local randomIndex = math.random(1, #default_info)
        local randomItem = default_info[randomIndex]
        showOffWindow.title:setText(tr(randomItem.Title))
        image:setImageSource(randomItem.image)
        description:setText(tr(randomItem.description))
        widget:resize(widget:getWidth(), description:getHeight())
    end
    if g_game.isOnline() then
        hide()
    end
end

function terminate()
    if scheduleRefreshEvent then
        removeEvent(scheduleRefreshEvent)
        scheduleRefreshEvent = nil
    end
    bottomMenu:destroy()
    boostedWindow = nil
    calendarWindow:destroy()
end

function hide()
    bottomMenu:hide()
    bottomMenu:lower()

    if not calendarWindow:isHidden() then
        onClickCloseCalendar()
    end
end

function show()
    bottomMenu:show()
    bottomMenu:raise()
    bottomMenu:focus()
end

-- @ Store showoff
function setShowOffData(data)
    local widget = g_ui.createWidget('ShowOffWidget', showOffWindow)
    local image = widget:recursiveGetChildById('image')

    if data.image and data.image:sub(1, 4):lower() == "http" then
        HTTP.downloadImage(data.image, function(path, err)
            if err then
                g_logger.warning("HTTP error: " .. err .. " - " .. data.image)
                return
            end
            image:setImageSource(path)
        end)
    else
        image:setImage(data.image)
    end

    local description = widget:recursiveGetChildById('description')

    showOffWindow.title:setText(tr(data.title))
    description:setText(tr(data.description))
end

-- @ Calendar/Events scheduler
function onClickOnCalendar()
    if eventSchedulerYears == nil or #eventSchedulerYears == 0 then
        return
    end

    calendarWindow:show()
    calendarWindow:raise()
    calendarWindow:centerIn('parent')
    calendarWindow:removeAnchor(AnchorHorizontalCenter)
    calendarWindow:removeAnchor(AnchorVerticalCenter)
    reloadEventsSchedulerCurrentPage()

    g_keyboard.bindKeyPress('Escape', onClickCloseCalendar)
end

function onClickCloseCalendar()
    calendarWindow:hide()
    calendarWindow:lower()

    g_keyboard.unbindKeyPress('Escape', onClickCloseCalendar)
end

function setEventsSchedulerTimestamp(time)
    eventSchedulerTimestamp = time
    calendarCurrentDate:setText(os.date("%Y-%m-%d, %H:%M CET", eventSchedulerTimestamp))
end

function getCalendarEventWidgetByDay(day, month, year, weekOffset, forceLine)
    local weekIndex = getDayOfWeek(day, month, year)
    local row = calendarWindow:recursiveGetChildById('row' .. weekIndex)
    if not row then
        return nil
    end

    local lineIndex = nil
    if forceLine ~= nil then
        lineIndex = forceLine
    else
        lineIndex = (math.floor(((weekOffset + day) - 1) / 7))
    end
    local line = row:recursiveGetChildById('line' .. lineIndex)
    if not line then
        return nil
    end

    return line
end

function reloadEventsSchedulerCurrentPage()
    local firstDayOffset = getDayOfWeek(1)
    if firstDayOffset == 0 then
        firstDayOffset = 7
    end
    local weekOffset = firstDayOffset - 1

    -- Days before the day 1 of this month
    if weekOffset > 0 then
        local previousYearIndex = eventSchedulerCalendarYearIndex
        local previousMonth = eventSchedulerCalendarMonth
        if previousMonth == 1 then
            previousYearIndex = previousYearIndex - 1
            previousMonth = 12
        else
            previousMonth = previousMonth - 1
        end
        if previousYearIndex >= 0 then
            local previousDays = eventSchedulerYears[previousYearIndex][previousMonth]
            local amountsLeft = weekOffset
            local i = #previousDays
            while (amountsLeft > 0) do
                local widget = getCalendarEventWidgetByDay(i, previousMonth, tonumber(os.date("%Y", os.time())) +
                    (previousYearIndex - 1), weekOffset, 0)
                if widget then
                    widget:clearEvents()
                    widget.dayOfTheWeek = i
                    widget:recursiveGetChildById('dayAndSeason'):setOn(true)
                    widget:recursiveGetChildById('day'):setText(i)
                    widget:recursiveGetChildById('day'):setWidth(string.len(
                        widget:recursiveGetChildById('day'):getText()) * 10)
                    widget:recursiveGetChildById('fill'):setOn(false)
                    for _, event in ipairs(previousDays[i]) do
                        widget:addScheduleEvent(event, false, nil)
                    end
                end
                amountsLeft = amountsLeft - 1
                i = i - 1
            end
        end
    end

    -- Days after the last day of this month
    local days = eventSchedulerYears[eventSchedulerCalendarYearIndex][eventSchedulerCalendarMonth]
    local lastDayOffset = getDayOfWeek(#days)
    if lastDayOffset == 0 then
        lastDayOffset = 7
    end
    local nextWeekOffset = 7 - lastDayOffset
    local nextYearIndex = eventSchedulerCalendarYearIndex
    local nextMonth = eventSchedulerCalendarMonth
    if nextMonth == 12 then
        nextYearIndex = nextYearIndex + 1
        nextMonth = 1
    else
        nextMonth = nextMonth + 1
    end
    if nextYearIndex <= 2 then
        local nextDays = eventSchedulerYears[nextYearIndex][nextMonth]
        local amountsLeft = nextWeekOffset
        local i = 1
        local forceLine = 4
        if firstDayOffset >= 5 then
            forceLine = 5
        end
        if firstDayOffset <= 5 then
            amountsLeft = amountsLeft + 7
        end
        while (amountsLeft > 0) do
            if forceLine == 4 and amountsLeft == 7 then
                forceLine = 5
            end
            local widget = getCalendarEventWidgetByDay(i, nextMonth,
                tonumber(os.date("%Y", os.time())) + (nextYearIndex - 1), nextWeekOffset, forceLine)
            if widget then
                widget:clearEvents()
                widget.dayOfTheWeek = i
                widget:recursiveGetChildById('dayAndSeason'):setOn(true)
                widget:recursiveGetChildById('day'):setText(i)
                widget:recursiveGetChildById('day'):setWidth(
                    string.len(widget:recursiveGetChildById('day'):getText()) * 10)
                widget:recursiveGetChildById('fill'):setOn(false)
                for _, event in ipairs(nextDays[i]) do
                    widget:addScheduleEvent(event, false, nil)
                end
            end
            amountsLeft = amountsLeft - 1
            i = i + 1
        end
    end

    for day, events in ipairs(days) do
        local widget = getCalendarEventWidgetByDay(day, nil, nil, weekOffset, nil)
        if widget then
            widget:clearEvents()
            widget.dayOfTheWeek = day
            widget:recursiveGetChildById('dayAndSeason'):setOn(true)
            widget:recursiveGetChildById('day'):setText(tr(day))
            widget:recursiveGetChildById('day'):setWidth(string.len(widget:recursiveGetChildById('day'):getText()) * 10)
            widget:recursiveGetChildById('fill'):setOn(true)
            for _, event in ipairs(events) do
                widget:addScheduleEvent(event, true, nil)
            end
        end
    end

    calendarCurrentMonth:setText(os.date("%B", os.time {
        year = 2023,
        month = eventSchedulerCalendarMonth,
        day = 1
    }) .. " " .. (tonumber(os.date("%Y", os.time())) + (eventSchedulerCalendarYearIndex - 1)))
end

function reloadEventsSchedulerCalender()
    eventSchedulerYears = {}
    table.insert(eventSchedulerYears, createCalendar(tonumber(os.date("%Y", os.time()))))
    table.insert(eventSchedulerYears, createCalendar(tonumber(os.date("%Y", os.time())) + 1))

    if eventSchedulerCalendar == nil or #eventSchedulerCalendar == 0 then
        return
    end

    for _, info in ipairs(eventSchedulerCalendar) do
        local days = getCalendarDays(info.startdate, info.enddate)
        for index, day in ipairs(days) do
            table.insert(day, {
                active = (info.colorlight .. "ff"),
                inactive = (info.colordark .. "ff"),
                description = info.description,
                priority = info.displaypriority,
                season = info.isseasonal,
                name = info.name,
                special = info.specialevent,
                firstDay = index == 1,
                lastDay = index == #days
            })
        end
    end

    refreshActiveAndUpcoming()
end

-- Active and Upcoming go by the events' own start and end times rather than by
-- calendar day, so an event starting at 21:00 is Upcoming until then and moves
-- to Active on the minute: the schedule is fetched once, at startup, so the
-- panel re-sorts itself at the next start or end it knows of.
function refreshActiveAndUpcoming()
    if scheduleRefreshEvent then
        removeEvent(scheduleRefreshEvent)
        scheduleRefreshEvent = nil
    end

    activeScheduleEvent:clearEvents()
    upcomingScheduleEvent:clearEvents()

    local now = os.time()
    local today = os.date('*t', now)
    -- Upcoming is anything starting before tomorrow ends, as it was by day.
    local upcomingUntil = os.time({year = today.year, month = today.month, day = today.day + 2, hour = 0})
    -- At midnight the next day's events come into that window.
    local nextChange = os.time({year = today.year, month = today.month, day = today.day + 1, hour = 0})

    for _, info in ipairs(eventSchedulerCalendar) do
        local event = {
            active = (info.colorlight .. "ff"),
            inactive = (info.colordark .. "ff"),
            description = info.description,
            priority = info.displaypriority,
            season = info.isseasonal,
            name = info.name,
            special = info.specialevent
        }
        if info.startdate <= now and now < info.enddate then
            activeScheduleEvent:addScheduleEvent(event, true, onClickOnCalendar)
            nextChange = math.min(nextChange, info.enddate)
        elseif info.startdate > now and info.startdate < upcomingUntil then
            upcomingScheduleEvent:addScheduleEvent(event, false, onClickOnCalendar)
        end
        if info.startdate > now then
            nextChange = math.min(nextChange, info.startdate)
        end
    end

    scheduleRefreshEvent = scheduleEvent(refreshActiveAndUpcoming, (nextChange - now) * 1000 + 1000)
end

function setEventsSchedulerCalender(calender)
    eventSchedulerCalendar = calender
    reloadEventsSchedulerCalender()
end

function createCalendar(year)
    local calendar = {}

    for month = 1, 12 do
        calendar[month] = {}
        local daysInMonth = 31
        if month == 2 then
            if (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0) then
                daysInMonth = 29
            else
                daysInMonth = 28
            end
        elseif month == 4 or month == 6 or month == 9 or month == 11 then
            daysInMonth = 30
        end

        for day = 1, daysInMonth do
            calendar[month][day] = {}
        end
    end

    return calendar
end

function getCalendarDays(startTimestamp, endTimestamp)
    local currentYear = tonumber(os.date("%Y", os.time()))
    local startYear = tonumber(os.date("%Y", startTimestamp))
    local endYear = tonumber(os.date("%Y", endTimestamp))
    local daysInRange = {}

    if startYear ~= currentYear and startYear ~= (currentYear + 1) then
        return daysInRange
    end

    if endYear ~= currentYear and endYear ~= (currentYear + 1) then
        return daysInRange
    end

    local startMonth = tonumber(os.date("%m", startTimestamp))
    local startDay = tonumber(os.date("%d", startTimestamp))
    local endMonth = tonumber(os.date("%m", endTimestamp))
    local endDay = tonumber(os.date("%d", endTimestamp))

    if startYear == currentYear then
        for month = startMonth, endMonth do
            local startLoop = 1
            local endLoop = 31

            if month == startMonth then
                startLoop = startDay
            end

            if month == endMonth then
                endLoop = endDay
            end

            if eventSchedulerYears[1][month] then
                for day = startLoop, endLoop do
                    if eventSchedulerYears[1][month][day] then
                        table.insert(daysInRange, eventSchedulerYears[1][month][day])
                    end
                end
            end
        end
    else
        for month = startMonth, 12 do
            local startLoop = 1
            local endLoop = 31

            if month == startMonth then
                startLoop = startDay
            end

            if month == endMonth then
                endLoop = endDay
            end

            if eventSchedulerYears[1][month] then
                for day = startLoop, endLoop do
                    if eventSchedulerYears[1][month][day] then
                        table.insert(daysInRange, eventSchedulerYears[1][month][day])
                    end
                end
            end
        end
        for month = 1, endMonth do
            local startLoop = 1
            local endLoop = 31

            if month == startMonth then
                startLoop = startDay
            end

            if month == endMonth then
                endLoop = endDay
            end

            if eventSchedulerYears[2][month] then
                for day = startLoop, endLoop do
                    if eventSchedulerYears[2][month][day] then
                        table.insert(daysInRange, eventSchedulerYears[2][month][day])
                    end
                end
            end
        end
    end

    return daysInRange
end

function getDayOfWeek(day, month, year)
    if not year then
        year = tonumber(os.date("%Y", os.time())) + (eventSchedulerCalendarYearIndex - 1)
    end
    if not month then
        month = eventSchedulerCalendarMonth
    end
    local timestamp = os.time {
        year = year,
        month = month,
        day = day
    }
    local weekday = tonumber(os.date("%w", timestamp))
    -- 0: Sunday
    -- 6: Saturday
    return weekday
end

function onClickOnPreviousCalendar()
    if eventSchedulerCalendarMonth == 1 then
        if eventSchedulerCalendarYearIndex == 1 then
            return
        end
        eventSchedulerCalendarMonth = 12
        eventSchedulerCalendarYearIndex = eventSchedulerCalendarYearIndex - 1
    else
        eventSchedulerCalendarMonth = eventSchedulerCalendarMonth - 1
    end

    calendarNextButton:setEnabled(true)
    if eventSchedulerCalendarYearIndex == 1 and eventSchedulerCalendarMonth == (tonumber(os.date("%m", os.time())) - 1) then
        calendarPrevButton:setEnabled(false)
    else
        calendarPrevButton:setEnabled(true)
    end

    reloadEventsSchedulerCurrentPage()
end

function onClickOnNextCalendar()
    if eventSchedulerCalendarMonth == 12 then
        if eventSchedulerCalendarYearIndex == 2 then
            return
        end
        eventSchedulerCalendarMonth = 1
        eventSchedulerCalendarYearIndex = eventSchedulerCalendarYearIndex + 1
    else
        eventSchedulerCalendarMonth = eventSchedulerCalendarMonth + 1
    end

    calendarPrevButton:setEnabled(true)
    if eventSchedulerCalendarYearIndex == 2 and eventSchedulerCalendarMonth == (tonumber(os.date("%m", os.time())) - 1) then
        calendarNextButton:setEnabled(false)
    else
        calendarNextButton:setEnabled(true)
    end

    reloadEventsSchedulerCurrentPage()
end

-- The Shattered Realms' login.php sends the running set as database rows, outfits included
-- (OTSERV website/patch_myaac.php): an 8.60 client has no race data to look a creature up by.
-- `boosted` is every slot in draw order; each gets a cell in the Boosted box, its slot under
-- the outfit and its name and bonuses in the tooltip.
local BOOSTED_BONUSES = {
    {'exp_bonus', 'experience'}, {'loot_bonus', 'loot'},
    {'variant_bonus', 'Tainted & Corrupted chance'}, {'spawn_bonus', 'monsters'},
}

-- What fits under a 50-pixel cell (a two-row login.php names its rows by kind instead);
-- any other slot shows its own label.
local BOOSTED_SHORT_LABELS = {variant = 'T & C', rook = 'Rook', creature = 'T & C', boss = 'Boss'}

-- Left to right on the login screen, by slot (or by kind from a two-row login.php).
local BOOSTED_ORDER = {
    rook = 1, low1 = 2, low2 = 3, low3 = 4, medium1 = 5, medium2 = 6,
    high = 7, veryhigh = 8, variant = 9, creature = 9, boss = 10,
}

local function boostedBonusText(row)
    local parts = {}
    for _, bonus in ipairs(BOOSTED_BONUSES) do
        local value = tonumber(row[bonus[1]]) or 0
        if value > 0 then
            parts[#parts + 1] = string.format('+%d%% %s', value, bonus[2])
        end
    end
    return table.concat(parts, '\n')
end

local function addBoostedSlot(list, row)
    if list:getChildCount() > 0 then
        g_ui.createWidget('BoostedSeparator', list)
    end
    local cell = g_ui.createWidget('BoostedSlot', list)
    local creature = cell:getChildById('creature')
    creature:setOutfit({
        type = tonumber(row.looktype),
        head = tonumber(row.lookhead) or 0,
        body = tonumber(row.lookbody) or 0,
        legs = tonumber(row.looklegs) or 0,
        feet = tonumber(row.lookfeet) or 0,
        addons = tonumber(row.lookaddons) or 0,
    })
    creature:getCreature():setStaticWalking(1000)
    cell:getChildById('label'):setText(BOOSTED_SHORT_LABELS[row.slot or row.kind] or row.label or '')
    cell:setTooltip(string.format('%s\nBoosted %s\n%s', row.name or 'Unknown', row.label or row.kind or '', boostedBonusText(row)))
end

-- Central European time for a UTC timestamp, by the EU rule rather than the PC's own zone:
-- summer time (CEST, UTC+2) from 01:00 UTC on March's last Sunday to 01:00 UTC on
-- October's, CET (UTC+1) otherwise.
local function daysFromCivil(y, m, d)
    if m <= 2 then
        y = y - 1
    end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
    return era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
end

local function euSummerSwitch(year, month)
    local last = daysFromCivil(year, month, 31)
    return (last - (last + 4) % 7) * 86400 + 3600
end

local function centralEuropeanTime(t)
    local year = os.date('!*t', t).year
    if t >= euSummerSwitch(year, 3) and t < euSummerSwitch(year, 10) then
        return os.date('!%H:%M', t + 7200), 'CEST'
    end
    return os.date('!%H:%M', t + 3600), 'CET'
end

function setBoostedCreatureAndBoss(data)
    if not modules.game_things.isLoaded() or not boostedWindow then
        return
    end

    -- A server whose login.php predates the full set still sends the two slots.
    local rows = type(data.boosted) == 'table' and data.boosted or {data.creature, data.boss}

    -- Weakest to strongest left to right, whatever order the server drew them in.
    local shown = {}
    for index, row in ipairs(rows) do
        if type(row) == 'table' and (tonumber(row.looktype) or 0) > 0 then
            shown[#shown + 1] = {row = row, index = index, rank = BOOSTED_ORDER[row.slot or row.kind] or 50}
        end
    end
    table.sort(shown, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.index < b.index
    end)

    local list = boostedWindow:recursiveGetChildById('boostedList')
    list:destroyChildren()
    local endsAt = 0
    for _, entry in ipairs(shown) do
        addBoostedSlot(list, entry.row)
        endsAt = math.max(endsAt, tonumber(entry.row.ends_at) or 0)
    end

    boostedWindow:recursiveGetChildById('boostedEmpty'):setVisible(list:getChildCount() == 0)
    local title = boostedWindow:recursiveGetChildById('boostedTitle')
    if endsAt > 0 then
        local cetTime, cetZone = centralEuropeanTime(endsAt)
        title:setText(tr('Boosted until %s UTC / %s %s', os.date('!%H:%M', endsAt), cetTime, cetZone))
    else
        title:setText(tr('Boosted'))
    end
end
