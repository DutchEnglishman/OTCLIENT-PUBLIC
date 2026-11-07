local UI = nil

-- The server's spell list (data/scripts/spell_archive/spell_archive.lua),
-- asked for every time the tab opens. The stock SpellInfo table is only used
-- to find an icon for a spell it happens to know.
SPELL_ARCHIVE_OPCODE = 97

local ARCHIVE_FILTER_VOCATION_ANY = -1

local archiveState = {
    vocationId = ARCHIVE_FILTER_VOCATION_ANY,
    search = ''
}

local archiveSpells = nil

MagicalArchive = MagicalArchive or {}

local function archiveContains(list, value)
    if not list then
        return false
    end
    for i = 1, #list do
        if list[i] == value then
            return true
        end
    end
    return false
end

-- promoted counterpart of a base vocation (server ids): 1-4 -> 5-8
local function archivePromotedId(vocationId)
    if vocationId >= 1 and vocationId <= 4 then
        return vocationId + 4
    end
    return nil
end

local function archiveInitials(name)
    local letters = ''
    for word in name:gmatch('%S+') do
        letters = letters .. word:sub(1, 1):upper()
    end
    return letters:sub(1, 2)
end

local function archiveSeconds(ms)
    return (ms / 1000) .. 's'
end

-- An empty vocation list means every vocation may cast it.
function MagicalArchive.matchesVocation(entry, vocationId)
    if vocationId == ARCHIVE_FILTER_VOCATION_ANY or #entry.vocations == 0 then
        return true
    end
    return archiveContains(entry.vocations, vocationId) or
        archiveContains(entry.vocations, archivePromotedId(vocationId))
end

function MagicalArchive.matchesSearch(entry, searchText)
    if not searchText or searchText == '' then
        return true
    end
    local needle = searchText:lower()
    return entry.name:lower():find(needle, 1, true) ~= nil or
        (entry.words or ''):lower():find(needle, 1, true) ~= nil
end

-- promoted vocations are hidden when their base vocation is also present ("Sorcerer" implies "Master Sorcerer")
function MagicalArchive.formatVocations(vocations, vocationNames)
    vocationNames = vocationNames or VocationNames
    if #vocations == 0 then
        return tr('All')
    end
    local baseOf = { [5] = 1, [6] = 2, [7] = 3, [8] = 4 }
    local result = ''
    for i = 1, #vocations do
        local vocationId = vocations[i]
        local base = baseOf[vocationId]
        if not base or not archiveContains(vocations, base) then
            result = result .. (result:len() == 0 and '' or ', ') .. (vocationNames[vocationId] or '?')
        end
    end
    return result
end

function MagicalArchive.formatMana(entry)
    local mana = entry.mana
    if mana == 0 and entry.manapercent > 0 then
        mana = entry.manapercent .. '%'
    end
    return mana .. ' / ' .. entry.soul
end

local function archiveSetDetailRow(rowId, value)
    local row = UI.spellAndRune.DetailPanel.DetailRows[rowId]
    row:setVisible(value ~= nil)
    row.value:setText(value or '')
end

local function archiveSetIcon(entry)
    local detail = UI.spellAndRune.DetailPanel
    detail.SpellIcon:setImageSource('')
    detail.SpellIcon:setText('')
    detail.RuneIcon:setVisible(false)

    if entry.rune then
        detail.RuneIcon:setItemId(entry.rune.clientId)
        detail.RuneIcon:setVisible(true)
        return
    end

    local spell, profile = Spells.getSpellByWords(entry.words)
    if not spell then
        profile = Spells.getSpellProfileByName(entry.name)
        spell = profile and SpellInfo[profile][entry.name]
    end
    local iconId = spell and tonumber(spell.clientId)
    if iconId then
        detail.SpellIcon:setImageSource(SpelllistSettings[profile].iconFile)
        detail.SpellIcon:setImageClip(Spells.getImageClip(iconId, profile))
    else
        detail.SpellIcon:setText(archiveInitials(entry.name))
    end
end

local function archiveSelectSpell(widget)
    local entry = widget.entry
    if not entry then
        return
    end

    local detail = UI.spellAndRune.DetailPanel
    UI.spellAndRune.PlaceholderLabel:setVisible(false)
    detail:setVisible(true)

    archiveSetIcon(entry)
    detail.NameLabel:setText(entry.name)
    detail.FormulaLabel:setText(entry.words and ('\'' .. entry.words .. '\'') or tr('Rune'))

    local isRune = entry.type == 'Rune'
    archiveSetDetailRow('RowVocation', MagicalArchive.formatVocations(entry.vocations))
    archiveSetDetailRow('RowGroup', entry.group)
    archiveSetDetailRow('RowType', entry.type)
    archiveSetDetailRow('RowCooldown', archiveSeconds(entry.cooldown))
    archiveSetDetailRow('RowLevel', tostring(entry.level))
    archiveSetDetailRow('RowMagicLevel', tostring(entry.mlevel))
    archiveSetDetailRow('RowMana', not isRune and MagicalArchive.formatMana(entry) or nil)
    archiveSetDetailRow('RowPremium', entry.premium and tr('yes') or tr('no'))
    archiveSetDetailRow('RowLearn', not isRune and (entry.learn and tr('must be learned') or tr('known')) or nil)

    local rune = entry.type == 'Conjure' and entry.rune
    archiveSetDetailRow('RowRune', rune and tr('level %d, magic level %d, %s, %s cooldown', rune.level, rune.mlevel,
        rune.group, archiveSeconds(rune.cooldown)) or nil)
end

local function archiveRebuildList()
    if not UI then
        return
    end
    local list = UI.InformationBase.selectSpell.SpellListBase.questList
    list:destroyChildren()
    if not archiveSpells then
        return
    end
    for _, entry in ipairs(archiveSpells) do
        if MagicalArchive.matchesVocation(entry, archiveState.vocationId) and
            MagicalArchive.matchesSearch(entry, archiveState.search) then
            local row = g_ui.createWidget('ArchiveSpellLabel', list)
            row.entry = entry
            row:setText(entry.name)
            row.onClick = archiveSelectSpell
        end
    end
end

local function archiveSetPlaceholder()
    if UI and not UI.spellAndRune.DetailPanel:isVisible() then
        UI.spellAndRune.PlaceholderLabel:setText(archiveSpells and tr('select a spell to view detailed information.') or
            tr('Loading spells...'))
    end
end

function MagicalArchive.onSpellList(protocol, opcode, buffer)
    local ok, data = pcall(json.decode, buffer)
    if not ok or type(data) ~= 'table' then
        return
    end
    data = JsonChunks.receive(SPELL_ARCHIVE_OPCODE, data, 'spells')
    if not data then
        return
    end
    archiveSpells = data.spells or {}
    archiveRebuildList()
    archiveSetPlaceholder()
end

function showMagicalArchives()
    UI = g_ui.loadUI("magicalArchives", contentContainer)
    UI:show()
    controllerCyclopedia.ui.CharmsBase:setVisible(false)
    controllerCyclopedia.ui.GoldBase:setVisible(false)
    controllerCyclopedia.ui.TaskPointsBase:setVisible(false)
    controllerCyclopedia.ui.BestiaryTrackerButton:setVisible(false)
    if g_game.getClientVersion() >= 1410 then
        controllerCyclopedia.ui.CharmsBase1410:setVisible(false)
    end

    archiveState.vocationId = ARCHIVE_FILTER_VOCATION_ANY
    archiveState.search = ''

    local vocationFilter = UI.InformationBase.selectSpell.VocationFilter
    vocationFilter:addOption(tr('All Vocations'), ARCHIVE_FILTER_VOCATION_ANY)
    vocationFilter:addOption(tr('Sorcerer'), VocationsServer.Sorcerer)
    vocationFilter:addOption(tr('Druid'), VocationsServer.Druid)
    vocationFilter:addOption(tr('Paladin'), VocationsServer.Paladin)
    vocationFilter:addOption(tr('Knight'), VocationsServer.Knight)
    vocationFilter:addOption(tr('No Vocation'), 0)
    vocationFilter.onOptionChange = function(widget, text, data)
        archiveState.vocationId = data
        archiveRebuildList()
    end

    local searchEdit = UI.InformationBase.selectSpell.SearchBase.SearchEdit
    searchEdit.onTextChange = function(widget, text)
        archiveState.search = text
        archiveRebuildList()
    end

    local list = UI.InformationBase.selectSpell.SpellListBase.questList
    connect(list, {
        onChildFocusChange = function(self, focusedChild)
            if focusedChild then
                archiveSelectSpell(focusedChild)
            end
        end
    })

    local detailRows = UI.spellAndRune.DetailPanel.DetailRows
    local captions = {
        RowVocation = tr('Vocation') .. ':',
        RowGroup = tr('Group') .. ':',
        RowType = tr('Type') .. ':',
        RowCooldown = tr('Cooldown') .. ':',
        RowLevel = tr('Level') .. ':',
        RowMagicLevel = tr('Magic Level') .. ':',
        RowMana = tr('Mana / Soul') .. ':',
        RowPremium = tr('Premium') .. ':',
        RowLearn = tr('Learning') .. ':',
        RowRune = tr('Rune use') .. ':'
    }
    for rowId, caption in pairs(captions) do
        detailRows[rowId].caption:setText(caption)
    end

    archiveRebuildList()
    archiveSetPlaceholder()

    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(SPELL_ARCHIVE_OPCODE, 'list')
    end
end
