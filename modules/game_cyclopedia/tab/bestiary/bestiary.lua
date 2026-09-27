local UI = nil

local STAGES = {
    CREATURES = 2,
    SEARCH = 4,
    CATEGORY = 1,
    CREATURE = 3
}

Cyclopedia.storedBosstiaryTrackerData = Cyclopedia.storedBosstiaryTrackerData or {}
local animusMasteryPoints = 0

function Cyclopedia.loadBestiaryOverview(name, creatures, animusMasteryPoints)
    if (name == "Result" or name == "") and #creatures > 0 then
        if #creatures == 1 then
            if Cyclopedia.pendingBestiaryDetailBackStage == STAGES.SEARCH then
                Cyclopedia.loadBestiarySearchCreatures(creatures)
            end

            Cyclopedia.openBestiaryCreatureDetail(creatures[1].id,
                Cyclopedia.pendingBestiaryDetailBackStage or Cyclopedia.Bestiary.Stage)
            Cyclopedia.pendingBestiaryDetailBackStage = nil
        else
        Cyclopedia.loadBestiarySearchCreatures(creatures)
        end
    else
        Cyclopedia.loadBestiaryCreatures(creatures)
    end

    if animusMasteryPoints and animusMasteryPoints > 0 then
        animusMasteryPoints = animusMasteryPoints
    end
end

function showBestiary()
    UI = g_ui.loadUI("bestiary", contentContainer)
    UI:show()

    -- No tier categories (Very Low/Low/Mid/High/Very High/Boss) -- just a
    -- flat, paginated list of every monster, reusing the same "search"
    -- request/render path BestiarySearch() already uses (STAGES.SEARCH),
    -- with an empty raceId list meaning "all of them" (see OTSERV's
    -- ProtocolGame::parseBestiaryRequestOverview). CategoryList/CATEGORY
    -- stage are never entered anymore -- left in place (dead) rather than
    -- ripped out, since Cyclopedia.changeBestiaryPage/onStageChange/etc.
    -- still branch on Stage and this keeps that branching intact.
    UI.ListBase.CategoryList:setVisible(false)
    UI.ListBase.CreatureList:setVisible(false)
    UI.ListBase.CreatureInfo:setVisible(false)

    Cyclopedia.Bestiary.Stage = STAGES.SEARCH
    -- Charms are cut from this server entirely (no charm-points economy
    -- exists) -- the window's shared charm-balance header stays hidden here
    -- the same way the Charms tab itself is.
    controllerCyclopedia.ui.CharmsBase:setVisible(false)
    controllerCyclopedia.ui.GoldBase:setVisible(true)
    controllerCyclopedia.ui.TaskPointsBase:setVisible(true)
    controllerCyclopedia.ui.BestiaryTrackerButton:setVisible(true)
    if g_game.getClientVersion() >= 1410 then
        controllerCyclopedia.ui.CharmsBase1410:hide()
    end

    Cyclopedia.initializeTrackerData()

    -- Bind Enter key to search when SearchEdit is focused
    g_keyboard.bindKeyDown('Enter', function()
        if UI and UI:isVisible() and UI.SearchEdit:getText() ~= "" then
            Cyclopedia.BestiarySearch()
        end
    end, UI.SearchEdit)

    Cyclopedia.Bestiary.Page = 1
    g_game.requestBestiaryOverview("Result", true, {})
end

Cyclopedia.Bestiary = {}
Cyclopedia.Bestiary.Stage = STAGES.CATEGORY
Cyclopedia.Bestiary.DetailBackStage = STAGES.CATEGORY

function Cyclopedia.SetBestiaryProgress(fit, firstBar, secondBar, thirdBar, killCount, firstGoal, secondGoal, thirdGoal)
    local function calculateWidth(value, max)
        return math.min(math.floor((value / max) * fit), fit)
    end

    local function setBarVisibility(bar, isVisible, width, isCompleted)
        isVisible = isVisible and width > 0
        bar:setVisible(isVisible)
        if isVisible then
            -- Use fill image only when bestiary is completed, otherwise use orange progress bar
            if isCompleted then
                bar:setImageRect({
                    height = 12,
                    x = 0,
                    y = 0,
                    width = width
                })
                bar:setImageSource("/game_cyclopedia/images/bestiary/fill")
            else
                -- For orange progress bar, set the widget width and use image as background
                bar:setWidth(width)
                bar:setImageSource("/game_cyclopedia/images/bestiary/progressbar-orange-small")
                -- Clear any image rect to use the full image as background
                bar:setImageRect({})
            end
        end
    end

    -- Check if bestiary is completed (reached final goal)
    local isCompleted = killCount >= thirdGoal

    local firstWidth = calculateWidth(math.min(killCount, firstGoal), firstGoal)
    setBarVisibility(firstBar, killCount > 0, firstWidth, isCompleted)

    local secondWidth = 0
    if killCount > firstGoal then
        secondWidth = calculateWidth(math.min(killCount - firstGoal, secondGoal - firstGoal), secondGoal - firstGoal)
    end
    setBarVisibility(secondBar, killCount > firstGoal, secondWidth, isCompleted)

    local thirdWidth = 0
    if killCount > secondGoal then
        thirdWidth = calculateWidth(math.min(killCount - secondGoal, thirdGoal - secondGoal), thirdGoal - secondGoal)
    end
    setBarVisibility(thirdBar, killCount > secondGoal, thirdWidth, isCompleted)
end

function Cyclopedia.SetBestiaryStars(value)
    UI.ListBase.CreatureInfo.StarFill:setWidth(value * 9)
end

function Cyclopedia.SetBestiaryDiamonds(value)
    UI.ListBase.CreatureInfo.DiamondFill:setWidth(value * 9)
end

-- The monster whose detail screen is open, lowercased to match the loot
-- channel's key. A payload that arrives for anything else is a stale answer to
-- a page the player has already left, and is dropped rather than drawn over
-- whatever is on screen now.
local openMonsterName = nil

-- chance is out of 100000 (the server's MAX_LOOTCHANCE), so a percentage is
-- chance / 1000. It is the RAW items.xml figure -- rateLoot is deliberately
-- not folded in, so the number here can always be checked against the monster's
-- own xml. Precision follows the size of it: the rarest rows are a thousandth
-- of a percent and would every one of them read "0.00%" at two decimals.
local function formatDropChance(chance)
    local percent = chance / 1000
    if percent >= 0.01 then
        return string.format("%.2f%%", percent)
    end
    return string.format("%.3f%%", percent)
end

function Cyclopedia.onBestiaryUnlockClick(mode)
    if openMonsterName then
        Cyclopedia.buyBestiaryLoot(openMonsterName, mode)
    end
end

-- Called from the loot channel's parser, which is also how a purchase reports
-- back -- the server answers a BUY with a fresh loot table rather than an ack,
-- so this is the only redraw path and there is no optimistic state to unwind
-- when a purchase is refused.
function Cyclopedia.refreshBestiaryLoot(monsterName)
    if openMonsterName and monsterName == openMonsterName then
        Cyclopedia.CreateCreatureItems()
    end
end

-- One tile. Locked rows arrive as itemId 0 with no name, so there is nothing
-- to hide client-side -- the tile is empty because it is empty.
local function createLootTile(parent, row, gates)
    local widget = g_ui.createWidget("BestiaryLootTile", parent)

    if row.unlocked then
        widget.Sprite:setItemId(row.itemId)
        widget.Name:setText(row.name)
        widget.Percent:setText(formatDropChance(row.chance))
        widget:setTooltip(string.format("%s\n%s chance to drop", row.name, formatDropChance(row.chance)))

        -- The quick-loot menu the old rarity-row tiles carried. It hangs
        -- off the tile rather than the Item, which is phantom so the
        -- tooltip covers the whole row.
        widget.onMouseRelease = function(self, mousePosition, mouseButton)
            return onAddLootClick(self.Sprite, mousePosition, mouseButton)
        end
        return false
    end

    widget.Locked:setVisible(true)
    widget.Name:setText(tr("Unknown"))
    widget.Name:setColor("#6E706F")
    widget.Percent:setText("???")

    local gate = gates[row.gate]
    if gate then
        widget:setTooltip(string.format("Revealed at %d kills, or with task points.\nLooting one reveals it too.", gate))
    end
    return true
end

function Cyclopedia.CreateCreatureItems()
    local base = UI.ListBase.CreatureInfo.ItemsBase
    base.Itemlist:destroyChildren()

    local loot = openMonsterName and Cyclopedia.getBestiaryLoot(openMonsterName)
    if not loot then
        -- One frame at most in practice: the request goes out as the detail
        -- packet is parsed, so this is only ever seen if the server is a
        -- deploy behind and never answers.
        base.LootStatus:setText(tr("Loading loot table..."))
        base.UnlockStageButton:setEnabled(false)
        base.UnlockAllButton:setEnabled(false)
        return
    end

    base.UnlockStageButton:setText(string.format("Unlock Next (%d)", loot.stageCost))
    base.UnlockAllButton:setText(string.format("Unlock All (%d)", loot.allCost))

    -- Older servers send one row group and no sections; fall back to drawing
    -- that as the only list rather than an empty window.
    local sections = loot.sections or {{title = "Normal", rows = loot.rows}}

    local lockedCount = 0
    local totalRows = 0
    for _, section in ipairs(sections) do
        -- A variant with nothing of its own is skipped entirely: a heading
        -- over an empty grid reads as a bug rather than as "no drops".
        if #section.rows > 0 then
            local header = g_ui.createWidget("BestiaryLootHeader", base.Itemlist)
            header:setText(section.title)

            local grid = g_ui.createWidget("BestiaryLootGrid", base.Itemlist)
            for _, row in ipairs(section.rows) do
                if createLootTile(grid, row, loot.gates) then
                    lockedCount = lockedCount + 1
                end
                totalRows = totalRows + 1
            end
        end
    end

    local remaining = loot.gatesTotal - loot.gatesOpen

    if totalRows == 0 then
        base.LootStatus:setText(tr("This creature drops nothing."))
    elseif lockedCount == 0 then
        base.LootStatus:setText(string.format("All %d drops revealed.", totalRows))
    else
        local nextGate = loot.gates[loot.gatesOpen + 1]
        base.LootStatus:setText(string.format("%d of %d drops hidden%s", lockedCount, totalRows,
            nextGate and string.format(" - next reveal at %d kills.", nextGate) or "."))
    end

    base.UnlockStageButton:setEnabled(remaining > 0)
    -- Buying "all" with one gate left is the same reveal as buying "next" for
    -- half the points, so it is shut off rather than offered as a worse deal.
    base.UnlockAllButton:setEnabled(remaining > 1)
end

function Cyclopedia.loadBestiarySelectedCreature(data)
    local occurence = {
        [0] = 1,
        2,
        3,
        4
    }

    local raceData = Cyclopedia.getRaceData(data.id)

    -- Same "seen it at least once" gate as the tile grid: name and sprite
    -- both stay hidden until the first real kill (data.killCounter is the
    -- real, always-sent count -- see sendBestiaryMonsterData).
    local seenOnce = data.killCounter >= 1

    UI.ListBase.CreatureInfo:setText(seenOnce and raceData.name or "Unknown")
    Cyclopedia.SetBestiaryDiamonds(occurence[data.ocorrence])
    Cyclopedia.SetBestiaryStars(data.difficulty)
    UI.ListBase.CreatureInfo.LeftBase.Sprite:setOutfit(raceData.outfit)
    -- 0 cancels the walk-animation cycle event and resets to the idle frame
    -- (Creature::setStaticWalking) -- the sprite stands still.
    UI.ListBase.CreatureInfo.LeftBase.Sprite:getCreature():setStaticWalking(0)
    if seenOnce then
        UI.ListBase.CreatureInfo.LeftBase.Sprite:getCreature():setShader("")
    else
        UI.ListBase.CreatureInfo.LeftBase.Sprite:getCreature():setShader("Outfit - cyclopedia-black")
    end

    -- The three fields carry the bestiary's kill gates in bar order now --
    -- left, middle, right, ascending (1000 / 2000 / 4000 for every non-boss
    -- tier). Their wire names are Tibia's and no longer describe what is in
    -- them: OTSERV used to fill them with gates[2], gates[1] and "the gate
    -- most recently crossed", which is why the middle segment used to want
    -- fewer kills than the left one and the right one moved as you killed.
    -- See ProtocolGame::sendBestiaryMonsterData.
    Cyclopedia.SetBestiaryProgress(60, UI.ListBase.CreatureInfo.ProgressBack, UI.ListBase.CreatureInfo.ProgressBack33,
        UI.ListBase.CreatureInfo.ProgressBack55, data.killCounter, data.thirdDifficulty, data.secondUnlock,
        data.lastProgressKillCount)

    UI.ListBase.CreatureInfo.ProgressValue:setText(data.killCounter)

    local fullText = ""
    if data.killCounter >= data.lastProgressKillCount then
        fullText = "(fully unlocked)"
    end

    -- Each segment says what its own gate reveals, since that is the whole
    -- point of crossing it. Kept in step with bestiary_unlocks_config.lua's
    -- lootOneIn, which is what actually decides the split.
    local gateText = {"reveals drops down to 1 in 50", "reveals drops down to 1 in 100",
                      "reveals every remaining drop"}

    UI.ListBase.CreatureInfo.ProgressBorder1:setTooltip(string.format(" %d / %d %s\n %s", data.killCounter,
        data.thirdDifficulty, fullText, gateText[1]))
    UI.ListBase.CreatureInfo.ProgressBorder2:setTooltip(string.format(" %d / %d %s\n %s", data.killCounter,
        data.secondUnlock, fullText, gateText[2]))
    UI.ListBase.CreatureInfo.ProgressBorder3:setTooltip(string.format(" %d / %d %s\n %s", data.killCounter,
        data.lastProgressKillCount, fullText, gateText[3]))

    -- data.currentLevel is now just a wire-parse gate on OTSERV (always 2,
    -- see the comment on ProtocolGame::sendBestiaryMonsterData) -- it no
    -- longer reflects real progress. Two separate kill-count gates, both
    -- checked against data.killCounter (always sent, real):
    --   Name/sprite/HP/EXP -- unlock on the very first kill.
    --   Speed/Armor/Mitigation -- unlock at the tier's first kill-count
    --     stage in OTSERV's data/bestiary/task_system_config.lua (200 for
    --     every non-boss tier, 3 for Boss). That threshold isn't carried on
    --     the wire, so it's hardcoded against the tier name
    --     (data.bestClass), which is.
    -- "- Task -" panel: only ever the stage currently being worked on, one
    -- value at a time. Stage thresholds are INCREMENTAL (200, then 500 more,
    -- ...) and pushed per tier by the server (Cyclopedia.getTierStages), so
    -- Remaining counts down within the current stage and Total flips to the
    -- next stage's size once this one is cleared -- mirroring
    -- TaskSystem.getTaskProgress.
    local stages = Cyclopedia.getTierStages(data.bestClass)
    local currentGoal, currentRemaining, currentStage
    local previousBoundary = 0
    for stageIndex, amount in ipairs(stages) do
        local boundary = previousBoundary + amount
        if data.killCounter < boundary then
            currentStage = stageIndex
            currentGoal = amount
            currentRemaining = boundary - data.killCounter
            break
        end
        previousBoundary = boundary
    end

    if currentGoal then
        UI.ListBase.CreatureInfo.TaskTitle:setText(string.format("- Task %d/%d -", currentStage, #stages))
        UI.ListBase.CreatureInfo.TaskTotal:setText("Total: " .. currentGoal)
        UI.ListBase.CreatureInfo.TaskRemaining:setText("Remaining: " .. currentRemaining)
    else
        UI.ListBase.CreatureInfo.TaskTitle:setText(string.format("- Task %d/%d -", #stages, #stages))
        UI.ListBase.CreatureInfo.TaskTotal:setText("Total: -")
        UI.ListBase.CreatureInfo.TaskRemaining:setText("All stages complete")
    end

    local UNLOCK_KILLS = stages[1] or 200
    local statsUnlocked = data.killCounter >= UNLOCK_KILLS

    if seenOnce then
        UI.ListBase.CreatureInfo.Value1:setText(data.maxHealth)
        UI.ListBase.CreatureInfo.Value2:setText(data.experience)
    else
        UI.ListBase.CreatureInfo.Value1:setText("?")
        UI.ListBase.CreatureInfo.Value2:setText("?")
    end

    if statsUnlocked then
        UI.ListBase.CreatureInfo.Value3:setText(data.speed)
        UI.ListBase.CreatureInfo.Value4:setText(data.armor)
        UI.ListBase.CreatureInfo.Value5:setText(data.mitigation .. "%")
        UI.ListBase.CreatureInfo.UnlockHint:setText("")
    else
        UI.ListBase.CreatureInfo.Value3:setText("?")
        UI.ListBase.CreatureInfo.Value4:setText("?")
        UI.ListBase.CreatureInfo.Value5:setText("?")
        UI.ListBase.CreatureInfo.UnlockHint:setText(string.format("%d kills to unlock", UNLOCK_KILLS - data.killCounter))
    end

    if data.attackMode == 1 then
        local rect = {
            height = 9,
            x = 18,
            y = 0,
            width = 18
        }

        UI.ListBase.CreatureInfo.SubTextLabel:setImageSource("/images/icons/icons-skills")
        UI.ListBase.CreatureInfo.SubTextLabel:setImageClip(rect)
        UI.ListBase.CreatureInfo.SubTextLabel:setSize("18 9")
    else
        local rect = {
            height = 9,
            x = 0,
            y = 0,
            width = 18
        }
        UI.ListBase.CreatureInfo.SubTextLabel:setImageSource("/images/icons/icons-skills")
        UI.ListBase.CreatureInfo.SubTextLabel:setImageClip(rect)
        UI.ListBase.CreatureInfo.SubTextLabel:setSize("18 9")
    end

    local resists = {"PhysicalProgress", "FireProgress", "EarthProgress", "EnergyProgress", "IceProgress",
                     "HolyProgress", "DeathProgress", "HealingProgress"}

    if not table.empty(data.combat) then
        for i = 1, 8 do
            -- Defaulted, not assumed present. calculateCombatValues compares its
            -- argument with `< 100`, so a single missing element raises "attempt
            -- to compare nil with number" and takes the whole creature panel down
            -- with it -- loot table, stats, everything after this loop. A server
            -- that sends seven elements, or numbers them from the wrong base,
            -- should cost one bar and not the page. 100 is the neutral reading,
            -- which is what an absent resistance means anyway.
            local combat = Cyclopedia.calculateCombatValues(data.combat[i] or 100)
            UI.ListBase.CreatureInfo[resists[i]].Fill:setMarginRight(combat.margin)
            UI.ListBase.CreatureInfo[resists[i]].Fill:setBackgroundColor(combat.color)
            UI.ListBase.CreatureInfo[resists[i]]:setTooltip(string.format("Sensitive to %s : %s", string.gsub(
                resists[i], "Progress", ""):lower(), combat.tooltip))
        end
    else
        for i = 1, 8 do
            UI.ListBase.CreatureInfo[resists[i]].Fill:setMarginRight(65)
        end
    end

    -- data.loot (the native packet's loot block) is deliberately unread.
    -- OTSERV sends it empty -- a lootCount of 0 -- because its per-item fields
    -- are id/difficulty/specialEvent/name/amount with nowhere to carry a drop
    -- percentage or an unlocked flag. The real table comes over the loot
    -- channel instead (BESTIARY_LOOT_OPCODE in game_cyclopedia.lua).
    --
    -- Requested by NAME rather than raceId: the server side of that channel is
    -- Lua, which has no access to the C++ race id table. raceData.name is
    -- title-cased here and lowercased on the way out.
    openMonsterName = raceData.name and raceData.name:lower() or nil
    Cyclopedia.CreateCreatureItems()
    if openMonsterName then
        Cyclopedia.requestBestiaryLoot(openMonsterName)
    end
    -- The "Location(s)" panel was removed from bestiary.otui -- data.location
    -- is still parsed off the wire, it just has nowhere to render.

    if data.AnimusMasteryPoints and data.AnimusMasteryPoints > 1 then
        UI.ListBase.CreatureInfo.AnimusMastery:setTooltip("The Animus Mastery for this creature is unlocked.\nIt yields "..(data.AnimusMasteryBonus / 10).."% bonus experience points, plus an additional 0.1% for every 10 Animus Masteries unlocked, up to a maximum of 4%.\nYou currently benefit from "..(data.AnimusMasteryBonus / 10).."% bonus experience points due to having unlocked ".. data.AnimusMasteryPoints .." Animus Masteries.")
        UI.ListBase.CreatureInfo.AnimusMastery:setVisible(true)
    else
        UI.ListBase.CreatureInfo.AnimusMastery:removeTooltip()
        UI.ListBase.CreatureInfo.AnimusMastery:setVisible(false)
    end
end

function Cyclopedia.ShowBestiaryCreature()
    Cyclopedia.Bestiary.Stage = STAGES.CREATURE
    Cyclopedia.onStageChange()
end

function Cyclopedia.openBestiaryCreatureDetail(raceId, backStage)
    raceId = tonumber(raceId)
    if not raceId then
        return false
    end

    Cyclopedia.Bestiary.DetailBackStage = backStage or Cyclopedia.Bestiary.Stage or STAGES.CATEGORY
    g_game.requestBestiarySearch(raceId)
    Cyclopedia.ShowBestiaryCreature()
    return true
end

function Cyclopedia.ShowBestiaryCreatures(Category)
    UI.ListBase.CreatureList:destroyChildren()
    UI.ListBase.CategoryList:setVisible(false)
    UI.ListBase.CreatureInfo:setVisible(false)
    UI.ListBase.CreatureList:setVisible(true)
    g_game.requestBestiaryOverview(Category, false, {})
end

function Cyclopedia.CreateBestiaryCategoryItem(Data)
    local widget = g_ui.createWidget("BestiaryCategory", UI.ListBase.CategoryList)
    widget:setText(Data.name)
    widget.ClassIcon:setImageSource("/game_cyclopedia/images/bestiary/creatures/" .. Data.name:lower():gsub(" ", "_"))
    widget.Category = Data.name
    widget:setColor(g_ui.getVariable('textColor'))
    widget.TotalValue:setText(string.format("Total: %d", Data.amount))
    widget.KnownValue:setText(string.format("Known: %d", Data.know))

    function widget.ClassBase:onClick()
        UI.BackPageButton:setEnabled(true)
        Cyclopedia.ShowBestiaryCreatures(self:getParent().Category)
        Cyclopedia.Bestiary.Stage = STAGES.CREATURES
        Cyclopedia.onStageChange()
    end
end

function Cyclopedia.loadBestiarySearchCreatures(data)
    UI.ListBase.CategoryList:setVisible(false)
    UI.ListBase.CreatureInfo:setVisible(false)
    UI.ListBase.CreatureList:setVisible(true)
    UI.BackPageButton:setEnabled(true)

    Cyclopedia.Bestiary.Stage = STAGES.SEARCH
    Cyclopedia.onStageChange()
    Cyclopedia.Bestiary.Search = {}
    Cyclopedia.Bestiary.Page = Cyclopedia.Bestiary.Page or 1

    local maxCategoriesPerPage = 15
    Cyclopedia.Bestiary.TotalSearchPages = math.ceil(#data / maxCategoriesPerPage)

    if Cyclopedia.Bestiary.TotalSearchPages < 1 then
        Cyclopedia.Bestiary.TotalSearchPages = 1
    end

    if Cyclopedia.Bestiary.Page > Cyclopedia.Bestiary.TotalSearchPages then
        Cyclopedia.Bestiary.Page = Cyclopedia.Bestiary.TotalSearchPages
    end

    UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bestiary.Page, Cyclopedia.Bestiary.TotalSearchPages))

    local page = 1
    Cyclopedia.Bestiary.Search[page] = {}

    for i = 1, #data do
        if (i - 1) % maxCategoriesPerPage == 0 and i > 1 then
            page = page + 1
            Cyclopedia.Bestiary.Search[page] = {}
        end
        local creature = {
            id = data[i].id,
            currentLevel = data[i].currentLevel,
            AnimusMasteryBonus = data[i].creatureAnimusMasteryBonus or 0,
        }

        table.insert(Cyclopedia.Bestiary.Search[page], creature)
    end

    Cyclopedia.Bestiary.Stage = STAGES.SEARCH
    Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, true)
    Cyclopedia.verifyBestiaryButtons()
end

function Cyclopedia.loadBestiaryCreatures(data)
    Cyclopedia.Bestiary.Creatures = {}
    Cyclopedia.Bestiary.Page = Cyclopedia.Bestiary.Page or 1

    local maxCategoriesPerPage = 15
    Cyclopedia.Bestiary.TotalCreaturesPages = math.ceil(#data / maxCategoriesPerPage)

    if Cyclopedia.Bestiary.TotalCreaturesPages < 1 then
        Cyclopedia.Bestiary.TotalCreaturesPages = 1
    end

    if Cyclopedia.Bestiary.Page > Cyclopedia.Bestiary.TotalCreaturesPages then
        Cyclopedia.Bestiary.Page = Cyclopedia.Bestiary.TotalCreaturesPages
    end

    UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bestiary.Page, Cyclopedia.Bestiary.TotalCreaturesPages))

    local page = 1
    Cyclopedia.Bestiary.Creatures[page] = {}

    for i = 1, #data do
        if (i - 1) % maxCategoriesPerPage == 0 and i > 1 then
            page = page + 1
            Cyclopedia.Bestiary.Creatures[page] = {}
        end

        local creature = {
            id = data[i].id,
            currentLevel = data[i].currentLevel,
            AnimusMasteryBonus = data[i].creatureAnimusMasteryBonus,

        }

        table.insert(Cyclopedia.Bestiary.Creatures[page], creature)
    end

    Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, false)
    Cyclopedia.verifyBestiaryButtons()
end

-- note: this one needs refactor
-- expected result:
-- when a string is entered
-- the list should generate client-side
-- the list of search results that match the search string
-- looks identical to category view
function Cyclopedia.BestiarySearch()
    local text = UI.SearchEdit:getText()
    local raceList = Cyclopedia.getRacesByName(text)
    local list = {}
    for _, race in pairs(raceList) do
        -- Undiscovered monsters (0 kills) are excluded: their name isn't
        -- shown anywhere yet, so letting a name search surface them would
        -- leak exactly what the "Unknown" label and blacked-out sprite are
        -- hiding.
        if Cyclopedia.getKillCount(race.raceId) >= 1 then
            list[#list + 1] = race.raceId
        end
    end

    UI.SearchEdit:setText("")

    -- An empty raceId list means "send everything" to the server (see
    -- OTSERV's ProtocolGame::parseBestiaryRequestOverview), so a search that
    -- filtered down to nothing must NOT be sent -- it would show the full
    -- list instead of no results. Render an empty result set locally.
    if #list == 0 then
        Cyclopedia.loadBestiarySearchCreatures({})
        return
    end

    g_game.requestBestiaryOverview("Result", true, list)
end

function Cyclopedia.BestiarySearchText(text)
    if text ~= "" then
        UI.SearchButton:enable(true)
    else
        UI.SearchButton:disable(false)
    end
end

function Cyclopedia.CreateBestiaryCreaturesItem(data)
    local raceData = Cyclopedia.getRaceData(data.id)

    local function verify(name)
        if #name > 18 then
            return name:sub(1, 15) .. "..."
        else
            return name
        end
    end

    local widget = g_ui.createWidget("BestiaryCreature", UI.ListBase.CreatureList)
    widget:setId(data.id)

    -- Name and sprite both stay hidden until the first real kill.
    -- Cyclopedia.getKillCount reads the literal kill count pushed over its
    -- own side channel (see the comment on OTSERV's
    -- ProtocolGame::sendBestiaryOverviewSearch), not the stage-based
    -- currentLevel used for the "X / 3" label below.
    local seenOnce = Cyclopedia.getKillCount(data.id) >= 1

    widget.Name:setText(seenOnce and verify(raceData.name) or "Unknown")
    widget.Sprite:setOutfit(raceData.outfit)
    widget.Sprite:getCreature():setStaticWalking(0)

    if data.AnimusMasteryBonus > 0 then
        widget.AnimusMastery:setTooltip("The Animus Mastery for this creature is unlocked.\nIt yields ".. data.AnimusMasteryBonus.. "% bonus experience points, plus an additional 0.1% for every 10 Animus Masteries unlocked, up to a maximum of 4%.\nYou currently benefit from ".. data.AnimusMasteryBonus.. "% bonus experience points due to having unlocked ".. animusMasteryPoints.." Animus Masteries.")
        widget.AnimusMastery:setVisible(true)
    else
        widget.AnimusMastery:removeTooltip()
        widget.AnimusMastery:setVisible(false)
    end

    -- Every tile stays clickable regardless of kill count (the detail screen
    -- does its own per-field gating). currentLevel is the count of kill gates
    -- crossed, 0-3 -- it is read straight now, where it used to be offset by
    -- one against a four-threshold ladder that no longer exists (see
    -- Bestiary::TIERS in OTSERV's src/bestiary.cpp).
    if data.currentLevel >= 3 then
        widget.Finalized:setVisible(true)
        widget.KillsLabel:setVisible(false)
    else
        widget.Finalized:setVisible(false)
        widget.KillsLabel:setVisible(true)
        widget.KillsLabel:setText(string.format("%d / 3", math.max(0, data.currentLevel)))
    end

    if seenOnce then
        widget.Sprite:getCreature():setShader("")
    else
        widget.Sprite:getCreature():setShader("Outfit - cyclopedia-black")
    end

    function widget.ClassBase:onClick()
        UI.BackPageButton:setEnabled(true)
        Cyclopedia.openBestiaryCreatureDetail(widget:getId(), Cyclopedia.Bestiary.Stage)
    end
end

function Cyclopedia.loadBestiaryCreature(page, search)
    local state = "Creatures"
    if search then
        state = "Search"
    end

    if not Cyclopedia.Bestiary[state][page] then
        return
    end

    UI.ListBase.CreatureList:destroyChildren()

    for _, data in ipairs(Cyclopedia.Bestiary[state][page]) do
        Cyclopedia.CreateBestiaryCreaturesItem(data)
    end
end

function Cyclopedia.loadBestiaryCategories(data)
    Cyclopedia.Bestiary.Categories = {}
    Cyclopedia.Bestiary.Page = 1

    local maxCategoriesPerPage = 15
    Cyclopedia.Bestiary.TotalCategoriesPages = math.ceil(#data / maxCategoriesPerPage)

    if UI == nil or UI.PageValue == nil then -- I know, don't change it
        return
    end

    UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bestiary.Page, Cyclopedia.Bestiary.TotalCategoriesPages))

    local page = 1
    Cyclopedia.Bestiary.Categories[page] = {}

    for i = 1, #data do
        if (i - 1) % maxCategoriesPerPage == 0 and i > 1 then
            page = page + 1
            Cyclopedia.Bestiary.Categories[page] = {}
        end

        local category = {
            name = data[i].bestClass,
            amount = data[i].count,
            know = data[i].unlockedCount,
            AnimusMasteryBonus = data[i].AnimusMasteryBonus,
        }

        table.insert(Cyclopedia.Bestiary.Categories[page], category)
    end

    Cyclopedia.loadBestiaryCategory(Cyclopedia.Bestiary.Page)
    Cyclopedia.verifyBestiaryButtons()
end

function Cyclopedia.loadBestiaryCategory(page)
    if not Cyclopedia.Bestiary.Categories[page] then
        return
    end

    UI.ListBase.CategoryList:destroyChildren()

    for _, data in ipairs(Cyclopedia.Bestiary.Categories[page]) do
        Cyclopedia.CreateBestiaryCategoryItem(data)
    end
end

function Cyclopedia.onStageChange()
    Cyclopedia.Bestiary.Page = 1

    if Cyclopedia.Bestiary.Stage == STAGES.CATEGORY then
        UI.BackPageButton:setEnabled(false)
        UI.ListBase.CategoryList:setVisible(true)
        UI.ListBase.CreatureList:setVisible(false)
        UI.ListBase.CreatureInfo:setVisible(false)
    end

    if Cyclopedia.Bestiary.Stage == STAGES.CREATURES then
        UI.BackPageButton:setEnabled(true)
        UI.ListBase.CategoryList:setVisible(false)
        UI.ListBase.CreatureList:setVisible(true)
        UI.ListBase.CreatureInfo:setVisible(false)

        function UI.BackPageButton.onClick()
            Cyclopedia.Bestiary.Stage = STAGES.CATEGORY
            Cyclopedia.onStageChange()
        end
    end

    if Cyclopedia.Bestiary.Stage == STAGES.SEARCH then
        -- SEARCH is the top-level "all monsters" screen now (see
        -- showBestiary()) -- there's no CATEGORY screen above it to go back
        -- to, so the back button stays disabled here. It's re-enabled by
        -- the CREATURE branch below when viewing an individual monster's
        -- detail, and that back button already returns correctly to SEARCH
        -- via Cyclopedia.Bestiary.DetailBackStage.
        UI.BackPageButton:setEnabled(false)
        UI.ListBase.CategoryList:setVisible(false)
        UI.ListBase.CreatureList:setVisible(true)
        UI.ListBase.CreatureInfo:setVisible(false)
    end

    if Cyclopedia.Bestiary.Stage == STAGES.CREATURE then
        UI.BackPageButton:setEnabled(true)
        UI.ListBase.CategoryList:setVisible(false)
        UI.ListBase.CreatureList:setVisible(false)
        UI.ListBase.CreatureInfo:setVisible(true)

        function UI.BackPageButton.onClick()
            Cyclopedia.Bestiary.Stage = Cyclopedia.Bestiary.DetailBackStage or STAGES.CREATURES
            Cyclopedia.onStageChange()
        end
    end

    Cyclopedia.verifyBestiaryButtons()
end

function Cyclopedia.changeBestiaryPage(prev, next)
    if next then
        Cyclopedia.Bestiary.Page = Cyclopedia.Bestiary.Page + 1
    end

    if prev then
        Cyclopedia.Bestiary.Page = Cyclopedia.Bestiary.Page - 1
    end

    local stage = Cyclopedia.Bestiary.Stage
    if stage == STAGES.CATEGORY then
        Cyclopedia.loadBestiaryCategory(Cyclopedia.Bestiary.Page)
    elseif stage == STAGES.CREATURES then
        Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, false)
    elseif stage == STAGES.SEARCH then
        Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, true)
    end

    Cyclopedia.verifyBestiaryButtons()
end

function Cyclopedia.verifyBestiaryButtons()
    local function updateButtonState(button, condition)
        if condition then
            button:enable()
        else
            button:disable()
        end
    end

    local function updatePageValue(currentPage, totalPages)
        UI.PageValue:setText(string.format("%d / %d", currentPage, totalPages))
    end

    updateButtonState(UI.SearchButton, UI.SearchEdit:getText() ~= "")

    local stage = Cyclopedia.Bestiary.Stage
    local totalSearchPages = Cyclopedia.Bestiary.TotalSearchPages
    local page = Cyclopedia.Bestiary.Page
    if stage == STAGES.SEARCH and totalSearchPages then
        local totalPages = totalSearchPages
        updateButtonState(UI.PrevPageButton, page > 1)
        updateButtonState(UI.NextPageButton, page < totalPages)
        updatePageValue(page, totalPages)
        return
    end

    if stage == STAGES.CREATURE then
        UI.PrevPageButton:disable()
        UI.NextPageButton:disable()
        updatePageValue(1, 1)
        return
    end

    local totalCategoriesPages = Cyclopedia.Bestiary.TotalCategoriesPages
    local totalCreaturesPages = Cyclopedia.Bestiary.TotalCreaturesPages
    if stage == STAGES.CATEGORY and totalCategoriesPages or stage == STAGES.CREATURES and totalCreaturesPages then
        local totalPages = stage == STAGES.CATEGORY and totalCategoriesPages or totalCreaturesPages
        updateButtonState(UI.PrevPageButton, page > 1)
        updateButtonState(UI.NextPageButton, page < totalPages)
        updatePageValue(page, totalPages)
    end
end

--[[
===================================================
=                     Tracker                     =
===================================================
]]

-- The recent-kill feed carries names lowercase. The race cache holds
-- title-cased ones but only arrives once the cyclopedia has been opened, so
-- the tracker cannot lean on it for a list restored at login.
local function titleCaseMonsterName(name)
    return (name:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

-- Renders the last few monsters the player killed, most recent first, with
-- progress through the CURRENT task stage ("50 / 500"). This replaces real
-- Tibia's manually-pinned tracker: the list is pushed by the server on every
-- kill and on login (see TaskSystem.sendRecentKills), so it updates live and
-- survives a relog rather than needing a request. There is no pin/unpin path
-- into this panel any more -- the bestiary's "Track Kills" checkbox is gone.
function Cyclopedia.refreshBestiaryTracker()
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    if not trackerMiniWindow or not trackerMiniWindow.contentsPanel then
        return
    end

    local panel = trackerMiniWindow.contentsPanel
    panel:destroyChildren()

    for i, entry in ipairs(Cyclopedia.getRecentKills()) do
        local raceId, race = Cyclopedia.findRaceByName(entry.name)

        -- Between rows only, so no rule above the first or below the last. The
        -- panel is a verticalBox, so the separator just takes its turn in the
        -- flow; every iteration below creates a row, so "not the first" is the
        -- same test as "there is a row above this one".
        if i > 1 then
            g_ui.createWidget("BestiaryTrackerSeparator", panel)
        end

        local widget = g_ui.createWidget("BestiaryTrackerEntry", panel)
        widget:setId(raceId or 0)
        widget.trackerType = 0

        -- Prefer the outfit the feed carries: the race cache is only pushed
        -- once the cyclopedia has been opened, so on a fresh login the tracker
        -- would otherwise draw empty slots for a list it just restored.
        local outfit = entry.outfit or (race and race.outfit)
        if outfit and (outfit.type or 0) > 0 then
            widget.creature:setOutfit(outfit)
            widget.creature:getCreature():setStaticWalking(0)
        end

        -- Every stage cleared. The wire cannot say so with stageIndex alone:
        -- sendRecentKills clamps it to totalStages (task_system_core.lua), so a
        -- finished monster and one still on its last stage both arrive as
        -- totalStages. goal is what separates them -- getTaskProgress fills
        -- current/goal only for a stage still in progress, and no tier has a
        -- stage amount of 0, so goal == 0 means finished and nothing else.
        local allStagesDone = (entry.goal or 0) == 0

        local killsText = allStagesDone and "Complete" or
                              string.format("%d / %d", entry.current, entry.goal)
        widget.kills:setText(killsText)
        -- The count sits on its own line under the name now, so the name gets
        -- the whole column instead of whatever the count left of one line --
        -- 11 characters before, 15 now. The column is about 100px wide beside a
        -- 48px tile, measured at the narrower width the row has once the
        -- miniwindow shows its scrollbar (184 panel - 3 - 1 margins - 15
        -- scrollbar - 10 padding = 155), and verdana-11px averages a touch
        -- under 7px a character, so 15 keeps a caps-heavy name off the edge.
        widget.label:setTextOverflowLength(15)
        widget.label:setText(race and race.name or titleCaseMonsterName(entry.name))

        -- 100 rather than 0 when finished: the old expression fell to 0 for a
        -- goal of 0, which drew an empty bar beside a full row of gold stars.
        local percent = allStagesDone and 100 or
                            math.min(100, math.floor(entry.current / entry.goal * 100))
        widget.killsBar:setVisible(true)
        Cyclopedia.setBarPercent(widget, percent)

        -- One star per stage in this monster's tier, gold for the stages
        -- already behind it. stageIndex is the stage IN PROGRESS, so the number
        -- finished is one less than it.
        local totalStages = entry.totalStages or 0
        local stagesDone = allStagesDone and totalStages or
                               math.max(0, (entry.stageIndex or 1) - 1)
        widget.starBase:setWidth(totalStages * 9)
        widget.starFill:setWidth(math.min(stagesDone, totalStages) * 9)

        if raceId then
            bindTrackerWidgetClicks(widget.creature, widget)
            bindTrackerWidgetClicks(widget.spacer, widget)
            bindTrackerWidgetClicks(widget.label, widget)
            bindTrackerWidgetClicks(widget.kills, widget)
        end
    end
end

function Cyclopedia.refreshBosstiaryTracker()
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    Cyclopedia.initializeTrackerData()

    if trackerMiniWindowBosstiary and trackerMiniWindowBosstiary.contentsPanel then
        trackerMiniWindowBosstiary.contentsPanel:destroyChildren()
    end

    -- Bosstiary tracker state comes from BosstiaryInfo, not the bestiary request.
    Cyclopedia.BosstiaryTrackerPending = true
    g_game.requestBosstiaryInfo()
end

function Cyclopedia.openTrackedCreature(trackerType, raceId)
    raceId = tonumber(raceId)
    if not raceId then
        return false
    end

    if trackerType == 1 then
        Cyclopedia.pendingBosstiaryRaceId = raceId
        if not Cyclopedia.openTab or not Cyclopedia.openTab("bosstiary") then
            return false
        end

        if Cyclopedia.focusBosstiaryRace then
            Cyclopedia.focusBosstiaryRace(raceId)
        end
        return true
    end

    if not Cyclopedia.openTab or not Cyclopedia.openTab("bestiary") then
        return false
    end

    Cyclopedia.pendingBestiaryDetailBackStage = STAGES.SEARCH
    g_game.requestBestiaryOverview("Result", true, {raceId})
    return true
end

function Cyclopedia.scheduleBosstiaryTrackerRetry(delay)
    if Cyclopedia.BosstiaryTrackerRetryScheduled then
        return
    end

    Cyclopedia.BosstiaryTrackerRetryScheduled = true
    scheduleEvent(function()
        Cyclopedia.BosstiaryTrackerRetryScheduled = false

        if trackerMiniWindowBosstiary and trackerMiniWindowBosstiary:isVisible() and Cyclopedia.BosstiaryTrackerPending then
            Cyclopedia.refreshBosstiaryTracker()
        end
    end, delay or 1000)
end

function Cyclopedia.toggleBestiaryTracker()
    if not trackerMiniWindow then
        return
    end

    if trackerButton:isOn() then
        trackerMiniWindow:close()
        trackerButton:setOn(false)
    else
        if not trackerMiniWindow:getParent() then
            local panel = modules.game_interface.findContentPanelAvailable(trackerMiniWindow,
            trackerMiniWindow:getMinimumHeight())
            if not panel then
                return
            end
            panel:addChild(trackerMiniWindow)
        end

        trackerMiniWindow:open()
    end
end

function Cyclopedia.toggleBosstiaryTracker()
    if not trackerMiniWindowBosstiary then
        return
    end

    -- The topbar button was removed, so fall back to the window's own
    -- visibility when it isn't there (see game_cyclopedia.lua).
    if trackerButtonBosstiary and trackerButtonBosstiary:isOn() or
        (not trackerButtonBosstiary and trackerMiniWindowBosstiary:isVisible()) then
        trackerMiniWindowBosstiary:close()
        if trackerButtonBosstiary then
            trackerButtonBosstiary:setOn(false)
        end
    else
        if not trackerMiniWindowBosstiary:getParent() then
            local panel = modules.game_interface.findContentPanelAvailable(trackerMiniWindowBosstiary,
            trackerMiniWindowBosstiary:getMinimumHeight())
            if not panel then
                return
            end
            panel:addChild(trackerMiniWindowBosstiary)
        end

        trackerMiniWindowBosstiary:open()
    end
end

function Cyclopedia.onTrackerClose(temp)
end

function Cyclopedia.setBarPercent(widget, percent)
    if percent > 92 then
        widget.killsBar:setBackgroundColor("#00BC00")
    elseif percent > 60 then
        widget.killsBar:setBackgroundColor("#50A150")
    elseif percent > 30 then
        widget.killsBar:setBackgroundColor("#A1A100")
    elseif percent > 8 then
        widget.killsBar:setBackgroundColor("#BF0A0A")
    elseif percent > 3 then
        widget.killsBar:setBackgroundColor("#910F0F")
    else
        widget.killsBar:setBackgroundColor("#850C0C")
    end

    widget.killsBar:setPercent(percent)
end

function Cyclopedia.onParseCyclopediaTracker(trackerType, data)
    if not data then
        return
    end

    local isBoss = trackerType == 1

    -- The bestiary tracker panel is driven entirely by the server's recent-kill
    -- feed (Cyclopedia.refreshBestiaryTracker), so the native pin-a-monster
    -- path must never render over it. The bosstiary tracker still uses this
    -- normally.
    if not isBoss then
        return
    end

    local window = isBoss and trackerMiniWindowBosstiary or trackerMiniWindow

    if isBoss and Cyclopedia.mergeBosstiaryTrackerOverrides and not Cyclopedia.BosstiaryTrackerLocalRender then
        data = Cyclopedia.mergeBosstiaryTrackerOverrides(data)
    end

    Cyclopedia.BosstiaryTrackerPending = false
    Cyclopedia.storedBosstiaryTrackerData = data

    if #data == 0 then
        if window and window.contentsPanel then
            window.contentsPanel:destroyChildren()
        end
        return
    end

    if not window or not window.contentsPanel then
        return
    end

    window.contentsPanel:destroyChildren()

    local trackerTypeStr = isBoss and "bosstiary" or "bestiary"
    data = Cyclopedia.sortTrackerData(data, trackerTypeStr)

    for _, entry in ipairs(data) do
        local raceId, kills, uno, dos, maxKills = unpack(entry)
        
        local raceData = Cyclopedia.getRaceData(raceId)
        local name = raceData.name

        local widget = g_ui.createWidget("TrackerButton", window.contentsPanel)
        widget:setId(raceId)
        widget.trackerType = trackerType
        widget.creature:setOutfit(raceData.outfit)
        local killsText = kills .. "/" .. maxKills
        widget.kills:setText(killsText)

        local maxLen = math.max(11, 18 - string.len(killsText))
        widget.label:setTextOverflowLength(maxLen)
        widget.label:setText(name)

        bindTrackerWidgetClicks(widget.creature, widget)
        bindTrackerWidgetClicks(widget.spacer, widget)
        bindTrackerWidgetClicks(widget.label, widget)
        bindTrackerWidgetClicks(widget.kills, widget)

        Cyclopedia.SetBestiaryProgress(54,widget.killsBar2, widget.ProgressBack33, widget.ProgressBack55, kills, uno, dos, maxKills)
    end
end

local BESTIATYTRACKER_FILTERS = {
    ["sortByName"] = false,
    ["ShortByPercentage"] = false,
    ["sortByKills"] = true,
    ["sortByAscending"] = true,
    ["sortByDescending"] = false
}

local BOSSTIARYTRACKER_FILTERS = {
    ["sortByName"] = false,
    ["ShortByPercentage"] = false,
    ["sortByKills"] = true,
    ["sortByAscending"] = true,
    ["sortByDescending"] = false
}

function Cyclopedia.loadTrackerFilters(trackerType)
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        local defaultFilters = trackerType == "bosstiary" and BOSSTIARYTRACKER_FILTERS or BESTIATYTRACKER_FILTERS
        return defaultFilters
    end
    
    local filterKey = trackerType == "bosstiary" and "bosstiaryTracker" or "bestiaryTracker"
    local charFilterKey = string.format("%s_%s", filterKey, char)
    local defaultFilters = trackerType == "bosstiary" and BOSSTIARYTRACKER_FILTERS or BESTIATYTRACKER_FILTERS
    
    local settings = g_settings.getNode(charFilterKey)
    if not settings or not settings['filters'] then
        -- Save default filters for first time use
        g_settings.mergeNode(charFilterKey, {
            ['filters'] = defaultFilters,
            ['character'] = char
        })
        return defaultFilters
    end
    return settings['filters']
end

function Cyclopedia.saveTrackerFilters(trackerType)
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end
    
    local filterKey = trackerType == "bosstiary" and "bosstiaryTracker" or "bestiaryTracker"
    local charFilterKey = string.format("%s_%s", filterKey, char)
    
    g_settings.mergeNode(charFilterKey, {
        ['filters'] = Cyclopedia.loadTrackerFilters(trackerType),
        ['character'] = char
    })
end

function Cyclopedia.initializeTrackerData()
    Cyclopedia.storedBosstiaryTrackerData = Cyclopedia.storedBosstiaryTrackerData or {}
end

function Cyclopedia.clearTrackerDataForCharacterChange()
    Cyclopedia.storedBosstiaryTrackerData = {}
    Cyclopedia.BosstiaryTrackerPending = false
    Cyclopedia.BosstiaryTrackerRetryScheduled = false

    if trackerMiniWindow and trackerMiniWindow.contentsPanel then
        trackerMiniWindow.contentsPanel:destroyChildren()
    end
    if trackerMiniWindowBosstiary and trackerMiniWindowBosstiary.contentsPanel then
        trackerMiniWindowBosstiary.contentsPanel:destroyChildren()
    end
end

function Cyclopedia.getTrackerFilter(trackerType, filter)
    return Cyclopedia.loadTrackerFilters(trackerType)[filter] or false
end

function Cyclopedia.setTrackerFilter(trackerType, filter, value)
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end
    
    local filterKey = trackerType == "bosstiary" and "bosstiaryTracker" or "bestiaryTracker"
    local charFilterKey = string.format("%s_%s", filterKey, char)
    local filters = Cyclopedia.loadTrackerFilters(trackerType)
    
    -- Handle mutual exclusion for sorting methods
    if filter == "sortByName" or filter == "ShortByPercentage" or filter == "sortByKills" then
        filters["sortByName"] = false
        filters["ShortByPercentage"] = false
        filters["sortByKills"] = false
        filters[filter] = true
    -- Handle mutual exclusion for sorting direction
    elseif filter == "sortByAscending" or filter == "sortByDescending" then
        filters["sortByAscending"] = false
        filters["sortByDescending"] = false
        filters[filter] = true
    else
        filters[filter] = value
    end
    
    g_settings.mergeNode(charFilterKey, {
        ['filters'] = filters,
        ['character'] = char
    })
    
    -- Refresh the tracker display
    Cyclopedia.refreshTracker(trackerType)
end

function Cyclopedia.refreshTracker(trackerType)
    if trackerType == "bosstiary" then
        if trackerMiniWindowBosstiary and Cyclopedia.storedBosstiaryTrackerData and not Cyclopedia.BosstiaryTrackerPending then
            Cyclopedia.onParseCyclopediaTracker(1, Cyclopedia.storedBosstiaryTrackerData)
        end
    else
        -- The bestiary panel renders the server's recent-kill feed, not stored
        -- pin data, so a refresh means rebuilding it from that feed.
        Cyclopedia.refreshBestiaryTracker()
    end
end

function Cyclopedia.sortTrackerData(data, trackerType)
    local filters = Cyclopedia.loadTrackerFilters(trackerType)
    local isDescending = filters.sortByDescending
    
    -- Create a copy of the data to avoid modifying the original
    local sortedData = {}
    for i, v in ipairs(data) do
        sortedData[i] = v
    end
    
    if filters.sortByName then
        table.sort(sortedData, function(a, b)
            local nameA = Cyclopedia.getRaceData(a[1]).name:lower()
            local nameB = Cyclopedia.getRaceData(b[1]).name:lower()
            if isDescending then
                return nameA > nameB
            else
                return nameA < nameB
            end
        end)
    elseif filters.ShortByPercentage then
        table.sort(sortedData, function(a, b)
            local raceIdA, killsA, _, _, maxKillsA = unpack(a)
            local raceIdB, killsB, _, _, maxKillsB = unpack(b)
            local percentA = maxKillsA > 0 and (killsA / maxKillsA * 100) or 0
            local percentB = maxKillsB > 0 and (killsB / maxKillsB * 100) or 0
            if isDescending then
                return percentA > percentB
            else
                return percentA < percentB
            end
        end)
    elseif filters.sortByKills then
        table.sort(sortedData, function(a, b)
            local remainingA = a[5] - a[2] -- maxKills - kills
            local remainingB = b[5] - b[2] -- maxKills - kills
            if isDescending then
                return remainingA > remainingB
            else
                return remainingA < remainingB
            end
        end)
    end
    
    return sortedData
end

-- Shared function to create tracker context menu
function Cyclopedia.createTrackerContextMenu(trackerType, mousePos)
    local menu = g_ui.createWidget('bestiaryTrackerMenu')
    menu:setGameMenu(true)
    local shortCreature = UIRadioGroup.create()
    local shortAlphabets = UIRadioGroup.create()

    for i, choice in ipairs(menu:getChildren()) do
        if i >= 1 and i <= 3 then
            shortCreature:addWidget(choice)
        elseif i == 5 or i == 6 then
            shortAlphabets:addWidget(choice)
        end
    end

    -- Set default selections
    local filters = Cyclopedia.loadTrackerFilters(trackerType)
    
    -- Set sorting method (default: sortByKills)
    if filters.sortByName then
        menu:getChildById('sortByName'):setChecked(true)
    elseif filters.ShortByPercentage then
        menu:getChildById('ShortByPercentage'):setChecked(true)
    elseif filters.sortByKills then
        menu:getChildById('sortByKills'):setChecked(true)
    else
        menu:getChildById('sortByKills'):setChecked(true)
    end
    
    -- Set sorting direction (default: ascending)
    if filters.sortByDescending then
        menu:getChildById('sortByDescending'):setChecked(true)
    else
        menu:getChildById('sortByAscending'):setChecked(true)
    end

    -- Add click handlers for menu options
    menu:getChildById('sortByName').onClick = function() Cyclopedia.setTrackerFilter(trackerType, 'sortByName', true); menu:destroy() end
    menu:getChildById('ShortByPercentage').onClick = function() Cyclopedia.setTrackerFilter(trackerType, 'ShortByPercentage', true); menu:destroy() end
    menu:getChildById('sortByKills').onClick = function() Cyclopedia.setTrackerFilter(trackerType, 'sortByKills', true); menu:destroy() end
    menu:getChildById('sortByAscending').onClick = function() Cyclopedia.setTrackerFilter(trackerType, 'sortByAscending', true); menu:destroy() end
    menu:getChildById('sortByDescending').onClick = function() Cyclopedia.setTrackerFilter(trackerType, 'sortByDescending', true); menu:destroy() end

    menu:display(mousePos)
    return true
end

-- Legacy functions for backwards compatibility
function Cyclopedia.loadBestiaryTrackerFilters()
    return Cyclopedia.loadTrackerFilters("bestiary")
end

function Cyclopedia.saveBestiaryTrackerFilters()
    return Cyclopedia.saveTrackerFilters("bestiary")
end

function Cyclopedia.getBestiaryTrackerFilter(filter)
    return Cyclopedia.getTrackerFilter("bestiary", filter)
end

function Cyclopedia.setBestiaryTrackerFilter(filter, value)
    return Cyclopedia.setTrackerFilter("bestiary", filter, value)
end

-- trackerMiniWindow.contentsPanel:moveChildToIndex(battleButton, index)
-- TODO Add sort by name, kills, percentage, ascending, descending
function test(index)
    trackerMiniWindow.contentsPanel:moveChildToIndex(trackerMiniWindow.contentsPanel:getLastChild(), index)
end

function bindTrackerWidgetClicks(clickableWidget, trackerWidget)
    if not clickableWidget then
        return
    end

    clickableWidget.onMouseRelease = function(_, mousePosition, mouseButton)
        return onTrackerClick(trackerWidget, mousePosition, mouseButton)
    end
end

function onTrackerClick(widget, mousePosition, mouseButton)
    if mouseButton == MouseLeftButton then
        return Cyclopedia.openTrackedCreature(widget.trackerType, widget:getId())
    end

    if mouseButton ~= MouseRightButton then
        return false
    end

    -- Only the bosstiary tracker is a pinned list. The bestiary panel shows the
    -- server's recent kills, which nothing can un-pin, so a right-click there
    -- has nothing to offer.
    if widget.trackerType ~= 1 then
        return false
    end

    local taskId = tonumber(widget:getId())
    local menu = g_ui.createWidget("PopupMenu")

    menu:setGameMenu(true)
    menu:addOption("stop Tracking " .. widget.label:getText(), function()
        if Cyclopedia.setBosstiaryTrackerStatus then
            Cyclopedia.setBosstiaryTrackerStatus(taskId, false, true)
        else
            g_game.sendStatusTrackerBestiary(taskId, false)
        end
    end)
    menu:display(mousePosition)

    return true
end

function onAddLootClick(widget, mousePosition, mouseButton)
    local itemId = widget:getItemId()
    local quickLoot = modules.game_quickloot.QuickLoot
    local lootFilterValue = quickLoot.data.filter
    local menu = g_ui.createWidget("PopupMenu")

    menu:setGameMenu(true)

    if not quickLoot.lootExists(itemId, lootFilterValue) then
        menu:addOption("Add to Loot List",
        function()
            quickLoot.addLootList(itemId, lootFilterValue)
        end)
    else
        menu:addOption("Remove from Loot List", 
        function() 
            quickLoot.removeLootList(itemId, lootFilterValue)
        end)
    end

    menu:display(mousePosition)

    return true
end
