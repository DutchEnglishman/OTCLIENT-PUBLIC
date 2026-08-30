-- Draws a dot and a name on the minimap for each party member.
--
-- The positions come from the server (data/scripts/party_tracker), not from
-- g_map: the client only ever knows about creatures inside its viewport, so a
-- party member one screen away has no Creature object here at all and there is
-- nothing local to place. Protocol 860 has no party-roster field either, hence
-- the extended opcode.
--
-- There is no cap on party size, and the names arrive already trimmed to four
-- characters -- the server does that so the payload, which grows linearly with
-- the party, stays small. Nothing here reconstructs the full name because
-- nothing can: it never leaves the server.

PARTY_TRACKER_OPCODE = 67

-- Dot colour by vocation, promoted ids folded onto their base. Keyed by the raw
-- id from the server's vocations.xml, so this table has to grow if new
-- vocations are added there.
--
-- Only the DOT takes the colour. The label stays a fixed readable tint on
-- purpose: a black name on the minimap's dark ground is unreadable, and it is
-- the marker that has to be identifiable at a glance, not the text.
local VOCATION_COLOR = {
    [0] = '#c0c0c0', -- None
    [1] = '#e03030', -- Sorcerer
    [2] = '#3a7fe0', -- Druid
    [3] = '#2fa84f', -- Paladin
    [4] = '#101010', -- Knight
    [5] = '#e03030', -- Master Sorcerer
    [6] = '#3a7fe0', -- Elder Druid
    [7] = '#2fa84f', -- Royal Paladin
    [8] = '#101010', -- Elite Knight
}

local DEFAULT_COLOR = VOCATION_COLOR[0]

-- Latest roster: { {x=, y=, z=, voc=, name=}, ... }, excluding self.
local members = {}

-- One dot and one label per member, keyed by the member's INDEX in the roster,
-- never by name: names arrive trimmed to four characters, so "Bubble" and
-- "Bubbles" both read "Bubb" and a name key would collapse them onto a single
-- dot. The label's text is re-set on every redraw, which is what lets a slot be
-- reused when the roster changes underneath it.
local widgets = {}

local function isEnabled()
    local options = modules.client_options
    if not options or not options.getOption then
        return true
    end

    local value = options.getOption('showPartyMembersOnMinimap')
    if value == nil then
        return true
    end
    return value
end

-- Resolved on every redraw rather than cached: game_minimap moves the widget
-- between the side panel and the fullscreen view (minimap.lua:186-209), so a
-- handle taken once goes stale the first time the map is opened full screen.
local function getMinimapWidget()
    local minimap = modules.game_minimap
    if not minimap or not minimap.mapController then
        return nil
    end

    local ui = minimap.mapController.ui
    if not ui or not ui.minimapBorder then
        return nil
    end

    return ui.minimapBorder.minimap
end

local function destroyWidgets(index)
    local entry = widgets[index]
    if not entry then
        return
    end

    if entry.dot then
        entry.dot:destroy()
    end
    if entry.label then
        entry.label:destroy()
    end
    widgets[index] = nil
end

local function clearAll()
    for index in pairs(widgets) do
        destroyWidgets(index)
    end
end

local function redraw()
    local minimapWidget = getMinimapWidget()
    if not minimapWidget then
        return
    end

    if not isEnabled() or not g_game.isOnline() then
        clearAll()
        return
    end

    for index, member in ipairs(members) do
        local entry = widgets[index]

        -- Rebuilt when the minimap widget was reparented (side panel <->
        -- fullscreen): the old anchors belong to the old layout.
        if entry and entry.dot:getParent() ~= minimapWidget then
            destroyWidgets(index)
            entry = nil
        end

        if not entry then
            entry = {
                dot = g_ui.createWidget('PartyTrackerDot', minimapWidget),
                label = g_ui.createWidget('PartyTrackerName', minimapWidget)
            }
            widgets[index] = entry
        end

        -- Re-applied every redraw, not only on creation: a slot is reused when
        -- the roster shifts underneath it -- someone leaves and everyone after
        -- them moves down an index -- so the widget at index 2 is not
        -- necessarily still showing the same person.
        entry.label:setText(member.name)
        entry.dot:setBackgroundColor(VOCATION_COLOR[member.voc] or DEFAULT_COLOR)

        -- Flattened onto the floor the minimap is showing, the same thing
        -- setCrossPosition does for the player's own marker (uiminimap.lua:138)
        -- -- otherwise a member one floor down simply vanishes.
        local pos = {
            x = member.x,
            y = member.y,
            z = minimapWidget:getCameraPosition().z
        }

        minimapWidget:centerInPosition(entry.dot, pos)

        -- Name sits directly above the dot, hooked to the tile's CENTRE rather
        -- than its top. A tile rect is spriteSize * scale (minimap.cpp:166), so
        -- at default zoom its top edge is 16px above the centre the dot is drawn
        -- on -- and further the more you zoom in. Hooking to the centre makes
        -- the gap the label's own margin-bottom, in pixels, at every zoom.
        minimapWidget:anchorPosition(entry.label, AnchorBottom, pos, AnchorVerticalCenter)
        minimapWidget:anchorPosition(entry.label, AnchorHorizontalCenter, pos, AnchorHorizontalCenter)
    end

    -- Slots past the end of the current roster: the party shrank.
    for index in pairs(widgets) do
        if index > #members then
            destroyWidgets(index)
        end
    end
end

-- "x,y,z,vocation,name" per entry, joined by ";". The name is last and taken as
-- the whole remainder, so a name containing a comma cannot split the entry.
local function parse(buffer)
    local parsed = {}

    if buffer and buffer ~= '' then
        for entry in buffer:gmatch('[^;]+') do
            local x, y, z, voc, name = entry:match('^(%-?%d+),(%-?%d+),(%-?%d+),(%d+),(.+)$')
            if x then
                parsed[#parsed + 1] = {
                    x = tonumber(x),
                    y = tonumber(y),
                    z = tonumber(z),
                    voc = tonumber(voc),
                    name = name
                }
            end
        end
    end

    return parsed
end

local function onOpcode(protocol, opcode, buffer)
    members = parse(buffer)
    redraw()
end

local function onGameEnd()
    members = {}
    clearAll()
end

-- Public so client_options can call it the moment the toggle flips, rather than
-- leaving stale dots on screen until the next redraw.
function refresh()
    redraw()
end

function init()
    g_ui.importStyle('partytracker')

    ProtocolGame.registerExtendedOpcode(PARTY_TRACKER_OPCODE, onOpcode)

    -- The roster arrives once a second, but the minimap camera follows the
    -- player every step, so the dots have to be re-anchored on our own movement
    -- too. This is the same signal game_minimap uses to move its own cross
    -- (minimap.lua:115) -- polling on a timer would re-run a full layout pass
    -- while standing still. Re-anchoring is free to repeat: UIAnchorGroup
    -- replaces an anchor with the same edge rather than stacking another one.
    connect(LocalPlayer, { onPositionChange = redraw })
    connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(PARTY_TRACKER_OPCODE)

    disconnect(LocalPlayer, { onPositionChange = redraw })
    disconnect(g_game, { onGameEnd = onGameEnd })

    clearAll()
    members = {}
end
