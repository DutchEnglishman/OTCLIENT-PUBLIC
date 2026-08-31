Cyclopedia = {}

trackerButton = nil
trackerMiniWindow = nil
trackerButtonBosstiary = nil
trackerMiniWindowBosstiary = nil
contentContainer = nil

local buttonSelection = nil
local items = nil
local bestiary = nil
local charms = nil
local map = nil
local houses = nil
local character = nil
local CyclopediaButton = nil
local bosstiary = nil
local bossSlot = nil
local ButtonBossSlot = nil
local ButtonBestiary = nil
local tabStack = {}
local previousType = nil
local windowTypes = {}
local magicalArchives = nil

-- Bridges the Bestiary/Bosstiary/Boss Slots tabs to real per-monster data on
-- this 860-locked client. The real wire protocol only ever sends numeric
-- raceIds + progress, never a monster's name/outfit -- real Tibia assumes
-- both sides share a client asset catalog (appearances.dat) for that.
-- OTCLIENT only loads that catalog for client version >= 1281
-- (modules/game_things/things.lua:47), so g_things.getRaceData/getRacesByName
-- are permanently empty here. The server pushes the missing raceId ->
-- name/outfit table once per connection over this extended opcode (see
-- ProtocolGame::sendBestiaryRaceCache in OTSERV's protocolgame.cpp); every
-- tab.lua file was patched to call Cyclopedia.getRaceData/getRacesByName
-- instead of the g_things ones directly.
local RACE_CACHE_OPCODE = 55
local raceCache = {}

-- Companion channel to RACE_CACHE_OPCODE: the real Bestiary overview packet
-- (0xD6) only carries stage-based progress (0-4), not the literal kill
-- count the "seen it at least once" tile shader needs -- see the comment on
-- OTSERV's ProtocolGame::sendBestiaryOverviewSearch. Sent fresh every time
-- the overview is requested (not a one-time push like the race cache),
-- since kill counts change during a session.
local KILL_COUNT_OPCODE = 56
local killCountCache = {}

-- Task points balance for the header panel, pushed alongside the overview
-- (see the comment on OTSERV's ProtocolGame::sendBestiaryOverviewSearch).
local TASK_POINTS_OPCODE = 57

-- Per-tier stage thresholds (incremental: 200, then 500 more, ...) and the
-- bestiary tracker's "last monsters you killed" list. Both pushed from
-- OTSERV's data/bestiary/task_system_core.lua -- see TIER_STAGES_OPCODE and
-- TRACKER_OPCODE there.
local TIER_STAGES_OPCODE = 58
local TRACKER_OPCODE = 59
local tierStages = {}
local recentKills = {}

-- Keyed by the tier's display name, which is what the native monster-data
-- packet carries as bestClass. Falls back to the regular-monster values if
-- the push hasn't arrived yet.
function Cyclopedia.getTierStages(bestClass)
    return tierStages[bestClass] or {200, 500, 1000, 2000}
end

function Cyclopedia.getRecentKills()
    return recentKills
end

-- Exact (case-insensitive) name lookup against the race cache. The recent-kill
-- feed is keyed by monster name rather than raceId -- the server side of it
-- lives in Lua (task_system_core.lua), which has no access to the C++ race
-- id table -- so the outfit has to be resolved back here.
function Cyclopedia.findRaceByName(name)
    if not name then
        return nil
    end

    name = name:lower()
    for raceId, race in pairs(raceCache) do
        if race.name:lower() == name then
            return raceId, race
        end
    end
    return nil
end

function Cyclopedia.getKillCount(raceId)
    raceId = tonumber(raceId)
    return (raceId and killCountCache[raceId]) or 0
end

-- Proper title case, applied once here so every consumer can use
-- raceData.name as-is. The tab scripts used to re-capitalize on top of this
-- with a "(%l)(%w*)" gsub, which matched from the SECOND letter of an
-- already-capitalized word and produced "CAve Rat" -- they now just read
-- the name straight.
local function capitalizeRaceName(name)
    return (name:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

function Cyclopedia.getRaceData(raceId)
    raceId = tonumber(raceId)
    local cached = raceId and raceCache[raceId]
    if cached then
        return cached
    end
    return g_things.getRaceData(raceId)
end

function Cyclopedia.getRacesByName(text)
    text = text:lower()
    local result = {}
    for raceId, race in pairs(raceCache) do
        if race.name:lower():find(text, 1, true) then
            result[#result + 1] = {raceId = raceId}
        end
    end
    return result
end

local function onBestiaryRaceCache(_protocol, opcode, buffer)
    if opcode ~= RACE_CACHE_OPCODE then
        return
    end

    for record in buffer:gmatch('[^;]+') do
        local raceId, name, lookType, lookHead, lookBody, lookLegs, lookFeet, lookAddons =
            record:match('^(%d+),([^,]*),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)$')
        if raceId then
            raceCache[tonumber(raceId)] = {
                name = capitalizeRaceName(name),
                outfit = {
                    type = tonumber(lookType),
                    head = tonumber(lookHead),
                    body = tonumber(lookBody),
                    legs = tonumber(lookLegs),
                    feet = tonumber(lookFeet),
                    addons = tonumber(lookAddons)
                }
            }
        end
    end

    -- The tracker may already be showing a login-restored list whose rows had
    -- no raceId to click through to. Now that the cache is here, redraw them.
    if Cyclopedia.refreshBestiaryTracker then
        Cyclopedia.refreshBestiaryTracker()
    end
end

local function onBestiaryKillCounts(_protocol, opcode, buffer)
    if opcode ~= KILL_COUNT_OPCODE then
        return
    end

    for record in buffer:gmatch('[^;]+') do
        local raceId, killCount = record:match('^(%d+),(%d+)$')
        if raceId then
            killCountCache[tonumber(raceId)] = tonumber(killCount)
        end
    end
end

local function onTierStages(_protocol, opcode, buffer)
    if opcode ~= TIER_STAGES_OPCODE then
        return
    end

    tierStages = {}
    for record in buffer:gmatch('[^;]+') do
        local parts = {}
        for field in record:gmatch('[^,]+') do
            parts[#parts + 1] = field
        end

        local displayName = table.remove(parts, 1)
        if displayName and #parts > 0 then
            local stages = {}
            for _, value in ipairs(parts) do
                stages[#stages + 1] = tonumber(value)
            end
            tierStages[displayName] = stages
        end
    end
end

local function onRecentKills(_protocol, opcode, buffer)
    if opcode ~= TRACKER_OPCODE then
        return
    end

    -- Two record shapes share this channel, told apart by field count:
    -- five fields is a monster's progress, seven is its outfit. They are
    -- separate records rather than one wide one so that an older client build,
    -- which matches every record against an anchored five-group pattern,
    -- skips the outfit rows instead of losing the whole list.
    local progress = {}
    local outfits = {}

    for record in buffer:gmatch('[^;]+') do
        local fields = {}
        for field in record:gmatch('[^,]+') do
            fields[#fields + 1] = field
        end

        if #fields == 5 then
            progress[#progress + 1] = {
                name = fields[1],
                current = tonumber(fields[2]),
                goal = tonumber(fields[3]),
                stageIndex = tonumber(fields[4]),
                totalStages = tonumber(fields[5])
            }
        elseif #fields == 7 then
            outfits[fields[1]] = {
                type = tonumber(fields[2]),
                head = tonumber(fields[3]),
                body = tonumber(fields[4]),
                legs = tonumber(fields[5]),
                feet = tonumber(fields[6]),
                addons = tonumber(fields[7])
            }
        end
    end

    -- The outfit is what lets the tracker draw a sprite before the race cache
    -- arrives -- that cache is only pushed once the cyclopedia is opened, so a
    -- list restored at login has nothing else to draw from. Absent when the
    -- server is a deploy behind, and the widget falls back to the cache then.
    for _, entry in ipairs(progress) do
        entry.outfit = outfits[entry.name]
    end

    recentKills = progress

    if Cyclopedia.refreshBestiaryTracker then
        Cyclopedia.refreshBestiaryTracker()
    end
end

local function onTaskPoints(_protocol, opcode, buffer)
    if opcode ~= TASK_POINTS_OPCODE then
        return
    end

    if controllerCyclopedia and controllerCyclopedia.ui and controllerCyclopedia.ui.TaskPointsBase then
        controllerCyclopedia.ui.TaskPointsBase.Value:setText(buffer)
    end
end

-- Strips a tracker's sort menu and its open-the-tab button, then closes the
-- gap. UIAnchorLayout resolves an anchor against the hooked widget's rect
-- without checking visibility (uianchorlayout.cpp:48), so hiding a button is
-- not enough on its own -- the lock button has to be re-pointed at minimize or
-- it stays parked two slots out over empty header.
local function hideTrackerHeaderButtons(window, contextMenuButton, newWindowButton, minimizeButton)
    if contextMenuButton then
        contextMenuButton:setVisible(false)
    end

    if newWindowButton then
        newWindowButton:setVisible(false)
    end

    -- Occupies the same slot as the sort button in the shared style and does
    -- nothing in a tracker, so it goes too rather than surfacing underneath.
    local toggleFilterButton = window:recursiveGetChildById('toggleFilterButton')
    if toggleFilterButton then
        toggleFilterButton:setVisible(false)
    end

    local lockButton = window:recursiveGetChildById('lockButton')
    if lockButton and minimizeButton then
        lockButton:breakAnchors()
        lockButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
        lockButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
        lockButton:setMarginRight(7)
        lockButton:setMarginTop(0)
    end
end

function toggle(defaultWindow)
    if not controllerCyclopedia.ui then
        return
    end
    if controllerCyclopedia.ui:isVisible() then
        return hide()
    end
    show(defaultWindow)
end

controllerCyclopedia = Controller:new()
controllerCyclopedia:setUI('game_cyclopedia')

function controllerCyclopedia:onInit()
    -- pre m_gameInitialized
    self:registerEvents(g_game, {
        onParseCyclopediaTracker = function(trackerType, data)
            if Cyclopedia.onParseCyclopediaTracker then
                Cyclopedia.onParseCyclopediaTracker(trackerType, data)
            end
        end
    })

    ProtocolGame.registerExtendedOpcode(RACE_CACHE_OPCODE, onBestiaryRaceCache)
    ProtocolGame.registerExtendedOpcode(KILL_COUNT_OPCODE, onBestiaryKillCounts)
    ProtocolGame.registerExtendedOpcode(TASK_POINTS_OPCODE, onTaskPoints)
    ProtocolGame.registerExtendedOpcode(TIER_STAGES_OPCODE, onTierStages)
    ProtocolGame.registerExtendedOpcode(TRACKER_OPCODE, onRecentKills)
end

function controllerCyclopedia:onGameStart()
    local versionClient = g_game.getClientVersion()
    if versionClient < 860 then
        controllerCyclopedia:scheduleEvent(function()
            g_modules.getModule("game_cyclopedia"):unload()
        end, 100, "unloadModule")
        return
    else
        CyclopediaButton = modules.game_mainpanel.addToggleButton('CyclopediaButton', tr('Cyclopedia'),
            '/images/options/cooldowns', function() toggle("map") end, false, 7)
        CyclopediaButton:setOn(false)
        -- "Open Bosstiary dialog" topbar button removed by request. The tab
        -- itself still exists and is reachable from the Cyclopedia window's
        -- own sidebar -- only the topbar shortcut is gone.

        contentContainer = controllerCyclopedia.ui:recursiveGetChildById('contentContainer')
        buttonSelection = controllerCyclopedia.ui:recursiveGetChildById('buttonSelection')
        items = buttonSelection:recursiveGetChildById('items')
        bestiary = buttonSelection:recursiveGetChildById('bestiary')
        map = buttonSelection:recursiveGetChildById('map')
        bosstiary = buttonSelection:recursiveGetChildById('bosstiary')
        bossSlot = buttonSelection:recursiveGetChildById('bossSlot')
        magicalArchives = buttonSelection:recursiveGetChildById('magicalArchives')

        -- Cut: Character, Charms, and Houses each need a whole server-side
        -- subsystem this project doesn't have (character info opcode,
        -- charm-points economy, house auctions) -- not fixable by bridging
        -- client-side data the way Bestiary/Bosstiary/Boss Slots were.
        -- Items and Boss Slot cut per explicit request. Destroyed, not
        -- hidden: the sidebar row is a chain of anchors.left: prev.right
        -- (game_cyclopedia.otui), resolved once at parse time to each
        -- widget's literal predecessor. Hiding leaves the (invisible)
        -- button still occupying its 34px slot in that chain, showing up
        -- as a gap -- destroying it removes the slot, but leaves its
        -- former successor's anchor dangling, so every survivor gets
        -- explicitly re-anchored below into the final order: Bestiary,
        -- Bosstiary, Magical Archives, Map (Map last, per request).
        charms = buttonSelection:recursiveGetChildById('charms')
        houses = buttonSelection:recursiveGetChildById('houses')
        character = buttonSelection:recursiveGetChildById('character')
        if charms then charms:destroy() end
        if houses then houses:destroy() end
        if character then character:destroy() end
        if items then items:destroy() end
        if bossSlot then bossSlot:destroy() end
        bossSlot = nil

        if bestiary then
            bestiary:breakAnchors()
            bestiary:addAnchor(AnchorTop, 'parent', AnchorTop)
            bestiary:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        end
        if bosstiary then
            bosstiary:breakAnchors()
            bosstiary:addAnchor(AnchorTop, 'bestiary', AnchorTop)
            bosstiary:addAnchor(AnchorLeft, 'bestiary', AnchorRight)
        end
        if magicalArchives then
            magicalArchives:breakAnchors()
            magicalArchives:addAnchor(AnchorTop, 'bosstiary', AnchorTop)
            magicalArchives:addAnchor(AnchorLeft, 'bosstiary', AnchorRight)
        end
        if map then
            map:breakAnchors()
            map:addAnchor(AnchorTop, 'magicalArchives', AnchorTop)
            map:addAnchor(AnchorLeft, 'magicalArchives', AnchorRight)
        end

        windowTypes = {
            bestiary = { obj = bestiary, func = showBestiary },
            map = { obj = map, func = showMap },
            bosstiary = { obj = bosstiary, func = showBosstiary },
            magicalArchives = { obj = magicalArchives, func = showMagicalArchives },
        }

        g_ui.importStyle("cyclopedia_widgets")
        g_ui.importStyle("cyclopedia_pages")

        controllerCyclopedia:registerEvents(g_game, {
            onResourcesBalanceChange = Cyclopedia.onResourcesBalanceChange,
            -- bestiary
            onParseBestiaryRaces = Cyclopedia.loadBestiaryCategories,
            onParseBestiaryOverview = Cyclopedia.loadBestiaryOverview,
            onUpdateBestiaryMonsterData = Cyclopedia.loadBestiarySelectedCreature,
            -- bosstiary
            onParseSendBosstiary = Cyclopedia.LoadBosstiaryCreatures,
            -- boss_slot
            onParseBosstiarySlots = Cyclopedia.loadBossSlots,
            -- character
            onParseCyclopediaCharacterGeneralStats = Cyclopedia.loadCharacterGeneralStats,
            onParseCyclopediaCharacterCombatStats = Cyclopedia.loadCharacterCombatStats,
            onParseCyclopediaCharacterBadges = Cyclopedia.loadCharacterBadges,
            onCyclopediaCharacterRecentDeaths = Cyclopedia.loadCharacterRecentDeaths,
            onCyclopediaCharacterRecentKills = Cyclopedia.loadCharacterRecentKills,
            onUpdateCyclopediaCharacterItemSummary = Cyclopedia.loadCharacterItems,
            onParseCyclopediaCharacterAppearances = Cyclopedia.loadCharacterAppearances,
            onParseCyclopediaStoreSummary = Cyclopedia.onParseCyclopediaStoreSummary,
            -- character 14.10
            onCyclopediaCharacterOffenceStats = Cyclopedia.onCyclopediaCharacterOffenceStats,
            onCyclopediaCharacterDefenceStats = Cyclopedia.onCyclopediaCharacterDefenceStats,
            onCyclopediaCharacterMiscStats = Cyclopedia.onCyclopediaCharacterMiscStats,


            -- charms
            onUpdateBestiaryCharmsData = Cyclopedia.loadCharms,
            -- items
            onParseItemDetail = Cyclopedia.loadItemDetail
        })

        --[[===================================================
    =               Tracker Bestiary                      =
    =================================================== ]] --

        -- Only create if it doesn't exist
        if not trackerButton then
            trackerButton = modules.game_mainpanel.addToggleButton("trackerButton", tr("Bestiary Tracker"),
                "/images/options/bestiaryTracker", Cyclopedia.toggleBestiaryTracker, false, 17)
        end
        
        trackerButton:setOn(false)
        
        -- Only create if it doesn't exist
        if not trackerMiniWindow then
            trackerMiniWindow = g_ui.createWidget('BestiaryTracker', modules.game_interface.getRightPanel())

            -- Set the title with length limit like in containers
            local titleWidget = trackerMiniWindow:getChildById('miniwindowTitle')
            if titleWidget then
                local title = tr('Bestiary Tracker')
                if title:len() > 12 then
                    title = title:sub(1, 12) .. "..."
                end
                titleWidget:setText(title)
            end

            -- Header buttons, both removed by request: the sort menu and the
            -- one that opened the Bestiary tab.
            local contextMenuButton = trackerMiniWindow:recursiveGetChildById('contextMenuButton')
            local newWindowButton = trackerMiniWindow:recursiveGetChildById('newWindowButton')
            local minimizeButton = trackerMiniWindow:recursiveGetChildById('minimizeButton')

            hideTrackerHeaderButtons(trackerMiniWindow, contextMenuButton, newWindowButton, minimizeButton)

            trackerMiniWindow.onOpen = function()
                trackerButton:setOn(true)
                Cyclopedia.refreshBestiaryTracker()
            end

            trackerMiniWindow.onClose = function()
                trackerButton:setOn(false)
            end

            trackerMiniWindow:setup()
            trackerMiniWindow:hide()
        end

        --[[===================================================
    =               Tracker Bosstiary                     =
    =================================================== ]] --

        -- "Bosstiary Tracker" topbar button removed by request. The tracker
        -- miniwindow below is still built and still works (the keybind under
        -- Windows > "Show/hide Bosstiary Tracker" still toggles it) -- only
        -- the topbar shortcut is gone, so every trackerButtonBosstiary use
        -- past this point is nil-guarded.
        
        -- Only create if it doesn't exist
        if not trackerMiniWindowBosstiary then
            trackerMiniWindowBosstiary = g_ui.createWidget('BestiaryTracker', modules.game_interface.getRightPanel())
            
            -- Set the title with length limit like in containers
            local titleWidgetBosstiary = trackerMiniWindowBosstiary:getChildById('miniwindowTitle')
            if titleWidgetBosstiary then
                local title = tr('Bosstiary Tracker')
                if title:len() > 12 then
                    title = title:sub(1, 12) .. "..."
                end
                titleWidgetBosstiary:setText(title)
            end

            -- Set the icon for Bosstiary Tracker
            local iconWidgetBosstiary = trackerMiniWindowBosstiary:getChildById('miniwindowIcon')
            if iconWidgetBosstiary then
                iconWidgetBosstiary:setImageSource('/images/icons/icon-bosstracker-widget')
            end

            -- Header buttons, both removed by request: the sort menu and the
            -- one that opened the Bosstiary tab. Hidden rather than deleted
            -- from 30-miniwindow.otui, which every miniwindow shares.
            local contextMenuButtonBosstiary = trackerMiniWindowBosstiary:recursiveGetChildById('contextMenuButton')
            local newWindowButtonBosstiary = trackerMiniWindowBosstiary:recursiveGetChildById('newWindowButton')
            local minimizeButtonBosstiary = trackerMiniWindowBosstiary:recursiveGetChildById('minimizeButton')

            hideTrackerHeaderButtons(trackerMiniWindowBosstiary, contextMenuButtonBosstiary,
                newWindowButtonBosstiary, minimizeButtonBosstiary)

            trackerMiniWindowBosstiary.onOpen = function()
                if trackerButtonBosstiary then
                    trackerButtonBosstiary:setOn(true)
                end
                if not Cyclopedia.BosstiaryTrackerPending then
                    if trackerMiniWindowBosstiary.contentsPanel then
                        trackerMiniWindowBosstiary.contentsPanel:destroyChildren()
                    end
                    Cyclopedia.refreshBosstiaryTracker()
                end
                Cyclopedia.scheduleBosstiaryTrackerRetry(1000)
            end

            trackerMiniWindowBosstiary.onClose = function()
                if trackerButtonBosstiary then
                    trackerButtonBosstiary:setOn(false)
                end
            end

            trackerMiniWindowBosstiary:setup()
            trackerMiniWindowBosstiary:hide()
        end
        trackerMiniWindow:setupOnStart()
        trackerMiniWindowBosstiary:setupOnStart()
        Cyclopedia.loadTrackerFilters("bestiary")
        Cyclopedia.loadTrackerFilters("bosstiary")

        if trackerMiniWindow:isVisible() then
            trackerButton:setOn(true)
        end
        if trackerMiniWindowBosstiary:isVisible() and trackerButtonBosstiary then
            trackerButtonBosstiary:setOn(true)
        end
        
        Cyclopedia.BossSlots.UnlockBosses = {}
        Keybind.new("Windows", "Show/hide Bosstiary Tracker", "", "")

        Keybind.bind("Windows", "Show/hide Bosstiary Tracker", {{
            type = KEY_DOWN,
            callback = Cyclopedia.toggleBosstiaryTracker
        }})

        Keybind.new("Windows", "Show/hide Bestiary Tracker", "", "")
        Keybind.bind("Windows", "Show/hide Bestiary Tracker", {{
            type = KEY_DOWN,
            callback = Cyclopedia.toggleBestiaryTracker
        }})
    end
    if versionClient >= 1410 then
        controllerCyclopedia.ui.CharmsBase.Icon:setImageSource("/game_cyclopedia/images/monster-icon-bonuspoints")
    end
end


function controllerCyclopedia:onGameEnd()
    hide()
    
    if Cyclopedia.saveTrackerFilters then
        Cyclopedia.saveTrackerFilters("bestiary")
        Cyclopedia.saveTrackerFilters("bosstiary")
    end

    if Cyclopedia.clearTrackerDataForCharacterChange then
        Cyclopedia.clearTrackerDataForCharacterChange()
    end

    Keybind.delete("Windows", "Show/hide Bosstiary Tracker")
    Keybind.delete("Windows", "Show/hide Bestiary Tracker")
end

function controllerCyclopedia:onTerminate()
    ProtocolGame.unregisterExtendedOpcode(RACE_CACHE_OPCODE)
    ProtocolGame.unregisterExtendedOpcode(KILL_COUNT_OPCODE)
    ProtocolGame.unregisterExtendedOpcode(TASK_POINTS_OPCODE)
    ProtocolGame.unregisterExtendedOpcode(TIER_STAGES_OPCODE)
    ProtocolGame.unregisterExtendedOpcode(TRACKER_OPCODE)

    if trackerButton then
        trackerButton:destroy()
        trackerButton = nil
    end

    if trackerMiniWindow then
        trackerMiniWindow:destroy()
        trackerMiniWindow = nil
    end

    if trackerButtonBosstiary then
        trackerButtonBosstiary:destroy()
        trackerButtonBosstiary = nil
    end

    if trackerMiniWindowBosstiary then
        trackerMiniWindowBosstiary:destroy()
        trackerMiniWindowBosstiary = nil
    end

    if CyclopediaButton then
        CyclopediaButton:destroy()
        CyclopediaButton = nil
    end
    if ButtonBossSlot then
        ButtonBossSlot:destroy()
        ButtonBossSlot = nil
    end
    if ButtonBestiary then
        ButtonBestiary:destroy()
        ButtonBestiary = nil
    end
    
    -- Save items data if available
    if Cyclopedia and Cyclopedia.Items and Cyclopedia.Items.terminate then
        Cyclopedia.Items.terminate()
    end
    
    onTerminateCharm()
end

function hide()
    if not controllerCyclopedia.ui then
        return
    end
    resetCyclopediaTabs()
    controllerCyclopedia.ui:hide()
    if CyclopediaButton then
        CyclopediaButton:setOn(false)
    end
    if ButtonBossSlot then
        ButtonBossSlot:setOn(false)
    end
    if ButtonBestiary then
        ButtonBestiary:setOn(false)
    end
end

function resetCyclopediaTabs()
    tabStack = {}
    controllerCyclopedia.ui.BackButton:setEnabled(false)
    if previousType then
        local previousWindow = windowTypes[previousType]
        previousWindow.obj:enable()
        previousWindow.obj:setOn(false)
        previousType = nil;
    end
end

function show(defaultWindow)
    if not controllerCyclopedia.ui then
        return
    end

    controllerCyclopedia.ui:show()
    controllerCyclopedia.ui:raise()
    controllerCyclopedia.ui:focus()
    SelectWindow(defaultWindow, false)
    controllerCyclopedia.ui.GoldBase.Value:setText(Cyclopedia.formatGold(g_game.getLocalPlayer():getTotalMoney()))
end

function Cyclopedia.openTab(tabName)
    if not controllerCyclopedia.ui then
        return false
    end

    if not controllerCyclopedia.ui:isVisible() then
        show(tabName)
        return true
    end

    if previousType ~= tabName then
        SelectWindow(tabName, false)
    end

    return true
end

function toggleBack()
    local previousTab = table.remove(tabStack, #tabStack)
    if #tabStack < 1 then
        controllerCyclopedia.ui.BackButton:setEnabled(false)
    end
    SelectWindow(previousTab, true)
end

function SelectWindow(type, isBackButtonPress)
    if previousType then
        local previousWindow = windowTypes[previousType]
        previousWindow.obj:enable()
        previousWindow.obj:setOn(false)
        if not isBackButtonPress then
            table.insert(tabStack, previousType)
            controllerCyclopedia.ui.BackButton:setEnabled(true)
        end
    end
    contentContainer:destroyChildren()

    local window = windowTypes[type]
    if window then
        window.obj:setOn(true)
        window.obj:disable()
        previousType = type
        if window.func then
            window.func(contentContainer)
        end
    end
    if CyclopediaButton then
        CyclopediaButton:setOn(type == "map" or type == "magicalArchives")
    end
    if ButtonBossSlot then
        ButtonBossSlot:setOn(type == "bossSlot")
    end
    if ButtonBestiary then
        ButtonBestiary:setOn(type == "bosstiary" or type == "bestiary")
    end
end

function Cyclopedia.onResourcesBalanceChange()
    if not controllerCyclopedia.ui or not controllerCyclopedia.ui:isVisible() then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    controllerCyclopedia.ui.GoldBase.Value:setText(Cyclopedia.formatGold(player:getTotalMoney()))

    local formatResourceBalance = function(resourceType, maxResourceType)
        return string.format("%d/%d", player:getResourceBalance(resourceType),
            player:getResourceBalance(maxResourceType))
    end

    controllerCyclopedia.ui.CharmsBase.Value:setText(formatResourceBalance(ResourceTypes.CHARM,
        ResourceTypes.MAX_CHARM))

    if controllerCyclopedia.ui.CharmsBase1410:isVisible() then
        controllerCyclopedia.ui.CharmsBase1410.Value:setText(formatResourceBalance(
            ResourceTypes.MINOR_CHARM, ResourceTypes.MAX_MINOR_CHARM))
    end
end

function isVisible()
    return controllerCyclopedia and controllerCyclopedia.ui and controllerCyclopedia.ui:isVisible()
end
