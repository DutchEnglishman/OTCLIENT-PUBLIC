-- Colors (Settings > Interface > Colors).
--
-- What a player can change here:
--
-- LOOT COLORS. The server decides which CATEGORY a looted item falls in and
-- sends it as a color code in the loot line: "{a sword, #4080FF}" (OTSERV
-- data/loot_colors/loot_colors.lua). Every category has its own code, so the
-- code is the category id. gamelib's ItemsDatabase.setColorLootMessage asks
-- mapColor() for each code and gets back the color this player picked (or
-- nil when they switched colored names off).
--
-- NAMES OVER MONSTERS. Tainted monsters' names are blue and Corrupted ones
-- red on the map, the same for everyone (MONSTER_NAME_COLORS, not on the page).
--
-- MONSTER NAMES AND CRITICAL HITS. The words "tainted" and "corrupted" in a
-- monster's name (Server Log lines and loot lines), and the number of a
-- critical hit, each have a color of their own. game_textmessage and
-- setColorLootMessage ask variantSpans() / colorLootHead() / colorFor('crit').
--
-- TEXT. The rest of a loot line ("Loot of a demon:", gold coins, items with no
-- color) and the white Server Log lines (damage, healing, experience, events)
-- are white by default; game_textmessage asks colorFor('lootText') /
-- colorFor('logText') for the console. The game screen keeps its own colors.
--
-- SETS. Two built-in sets that cannot be changed (Standard, Color-blind
-- friendly) plus one Custom set. Changing a color while on a built-in set
-- copies that set into Custom first and switches to it, so what you start from
-- is what you were looking at. Custom is kept when you switch back.
--
-- VALUE PRICES. The lowest NPC sell price of each value color (500, 3,000,
-- 10,000, 30,000, 60,000 gp by default). Players can add prices up to
-- MAX_STEPS or remove them down to one; each price is its own row with its
-- own color. The loot line carries no item ids or prices, so the client
-- cannot sort by price itself: the prices go to the server over OPCODE
-- ({"steps": [...]}) at login and on every change, and the server sorts this
-- player's loot with them (LootColors.setPlayerSteps, OTSERV
-- data/scripts/loot_colors/loot_colors.lua).
--
-- MESSAGE AND SPARKLE. Two ticks per loot row. Message: that kind of drop is
-- also shown in the middle of the screen (game_textmessage calls lootAlert()
-- for every loot line; client only). Sparkle: a corpse holding that kind
-- sparkles in its color for this player until opened (the ticked kinds go to
-- the server with the prices, LootColors.setPlayerSparkles). In the code the
-- Message ticks are still called "alerts".
--
-- ITEMS. Every price range has an Items button: items the player puts there
-- always read that range's color (and its alert), whatever they sell for --
-- unless they drop with a rare, epic or legendary roll, which still shows.
-- They are found by name in the autoloot item catalog (game_autoloot
-- items.lua, server and client ids), or loaded all at once from what a trader
-- buys (item_values.lua), and sent to the server with the prices
-- ({"items": [[serverId, range], ...]}, LootColors.setPlayerItems). An item in
-- a range the player removed waits there until the range comes back.
--
-- BACKPACK FRAMES. Items in containers and on the character get a frame in
-- the same color their loot line would have (frameColor(), used by gamelib's
-- ItemsDatabase.setRarityItem and game_inventory). The client works that out
-- itself from item_values.lua (NPC prices, materials and very rare items,
-- written by OTSERV tools/generate_item_values.js), so the server sends
-- nothing for it. The frame type (None / Frames / Corners) is the
-- client_options option 'framesRarity'.
--
-- CHAT COLORS. A player types a color name in braces in the Advertising
-- channel or Local Chat -- "{gold}selling {blue}golden armor" -- and the words
-- after it show in that color for everyone who reads it; "{/}" goes back to
-- the line's normal color. The tags travel inside the message itself, so the
-- server stores and sends nothing new. Only the names in CHAT_COLORS work, so
-- nobody can pick a color too dark to read. There is no red: an ad in red
-- would read like a warning or a gamemaster. Clicking a name on this page puts
-- its tag in the chat box (game_console insertTextEditText). game_console asks
-- chatColorsAllowed / chatMarkup / stripChatTags; anywhere else (private
-- messages, other channels, the text over a character's head) the tags are
-- taken out. Players can switch everyone's chat colors off on this page.
--
-- MARKERS. An option for anyone (it helps color-blind players most): a short
-- tag after each colored item in loot lines -- "a fire sword [R]", "golden
-- legs [60k]" -- so the kind of drop can be read without telling colors
-- apart. Every kind's marker can be changed (Edit markers: 1 to 4 letters,
-- digits or signs), or emptied for no marker on that kind.
-- ItemsDatabase.setColorLootMessage asks lootMarker() for each code.
--
-- ONLY COLORED ITEMS. An option: loot lines list only the colored items and
-- count the rest ("a fire axe, golden legs, +5 more"). filterLoot(), asked by
-- ItemsDatabase.setColorLootMessage before it colors the line.
--
-- "YOU SEE" LINES. Looking at an item shows its name in the color its loot
-- line would have (and its marker). The client remembers what was looked at
-- (g_game.look, wrapped in init) and game_textmessage asks lookMarkup().
--
-- PROFILES. Several named setups ("Hunting", "Trading"), each with all of the
-- above; a profile can be tied to a character so it is picked at login.
-- Saved in g_settings node "colorProfiles" next to the working copy.
--
-- SHARING. Copy code / Paste code put the colors and prices on the clipboard
-- as one line ("TSRCOL1:...") so players can swap them in chat.
--
-- Everything is saved per computer in the client's settings (g_settings node
-- "colorSettings"), not per character. Only new lines use a change; lines
-- already in the console keep theirs.

local SETTINGS_KEY = 'colorSettings'

-- Must match LootColors.OPCODE in OTSERV data/loot_colors/loot_colors.lua.
local OPCODE = 120

-- Must match LootColors.VALUE_STEPS' `min`s on the server, lowest first.
DEFAULT_STEPS = { 500, 3000, 10000, 30000, 60000 }
-- Must match LootColors.MAX_STEPS, MAX_STEP_PRICE and MAX_PINS on the server.
MAX_STEPS = 10
MAX_PINS = 600
local ITEM_SEARCH_MAX = 100
local MAX_STEP_PRICE = 1000000000

local SHARE_PREFIX = 'TSRCOL1'
local RECENT_MAX = 19 -- one row of the picker's grid

-- item_values.lua (generated) sets ITEM_VALUES; an empty one keeps every
-- frame on rarity rolls and the pins alone, and hides the trader list.
local VALUES = type(ITEM_VALUES) == 'table' and ITEM_VALUES or {}
VALUES.prices = VALUES.prices or {}
VALUES.veryRare = VALUES.veryRare or {}
VALUES.materials = VALUES.materials or {}
VALUES.traders = VALUES.traders or {}

-- One row per category. A loot row's `code` MUST match the server's color for
-- that category exactly (loot_colors.lua); a code the server stops sending
-- simply never gets used. A value row's `step` is its place in the player's
-- prices; rows past their count are hidden. The value codes must match
-- LootColors.VALUE_CODES on the server, in order.
-- `sample` is the item (or word) the previews show for it.
SLOTS = {
    -- noSparkle: common is any cheap item, so no Sparkle tick (Message stays).
    { key = 'common', group = 'rarity', code = '#A0A0A0', sample = 'a wand', noSparkle = true,
      tip = 'An item with a common roll worth less than the first value price. A common roll worth more shows its value color.' },
    { key = 'rare', group = 'rarity', label = 'Rare', code = '#4080FF', sample = 'a fire sword',
      tip = 'An item with a rare roll.' },
    { key = 'epic', group = 'rarity', label = 'Epic', code = '#A020F0', sample = 'a crown helmet',
      tip = 'An item with an epic roll.' },
    { key = 'legendary', group = 'rarity', label = 'Legendary', code = '#DF7010', sample = 'a magic plate armor',
      tip = 'An item with a legendary roll.' },

    { key = 'value1', group = 'value', step = 1, code = '#00C000', sample = 'a ring' },
    { key = 'value2', group = 'value', step = 2, code = '#4080FE', sample = 'a spike sword' },
    { key = 'value3', group = 'value', step = 3, code = '#A020F1', sample = 'a giant sword' },
    { key = 'value4', group = 'value', step = 4, code = '#DF7011', sample = 'a fire axe' },
    { key = 'value5', group = 'value', step = 5, code = '#FFF040', sample = 'golden legs' },
    { key = 'value6', group = 'value', step = 6, code = '#FFF041', sample = 'a war axe' },
    { key = 'value7', group = 'value', step = 7, code = '#FFF042', sample = 'a lich staff' },
    { key = 'value8', group = 'value', step = 8, code = '#FFF043', sample = 'a mace' },
    { key = 'value9', group = 'value', step = 9, code = '#FFF044', sample = 'a helmet' },
    { key = 'value10', group = 'value', step = 10, code = '#FFF045', sample = 'an amulet' },

    { key = 'material', group = 'special', label = 'Materials', code = '#00FFFF', sample = 'a cobalt fragment',
      tip = 'Quartz fragments, socket gems and the jewel box.' },
    { key = 'veryRare', group = 'special', label = 'Very rare', code = '#FF0000', sample = 'an aurelia ring',
      tip = 'The hand-picked very rare items, such as the Aurelia Ring.' },

    { key = 'tainted', group = 'names', label = 'Tainted', sample = 'tainted', noAlert = true,
      tip = 'The word "tainted" in a Tainted monster\'s name, in Server Log lines and loot lines.' },
    { key = 'corrupted', group = 'names', label = 'Corrupted', sample = 'corrupted', noAlert = true,
      tip = 'The word "corrupted" in a Corrupted monster\'s name, in Server Log lines and loot lines.' },
    { key = 'crit', group = 'combat', label = 'Critical hits', sample = '154', noAlert = true,
      tip = 'The damage number of a critical hit, in Server Log lines and on screen.' },

    { key = 'lootText', group = 'text', label = 'Loot lines', noAlert = true,
      tip = 'The rest of a loot line in the console: "Loot of a demon:", gold coins and items without a color. Item colors that look too much like it are shown a little lighter or darker.' },
    { key = 'logText', group = 'text', label = 'Server Log lines', noAlert = true,
      tip = 'The white lines in Server Log: damage, healing, experience and events. Green and red lines keep their colors. Word and crit colors that look too much like it are shown a little lighter or darker.' },
}

local VALUE_TIP = 'No rarity (or a common roll), by what one piece sells to an NPC for. ' ..
    'Type the lowest price for this color in the box; each price must be higher than the one above it.'

local GROUPS = {
    { id = 'rarity', title = 'Loot: rarity', alerts = true },
    { id = 'value', title = 'Loot: value (NPC sell price of one piece, from)', alerts = true },
    { id = 'special', title = 'Loot: special', alerts = true },
    { id = 'names', title = 'Monster names (Server Log and loot lines)' },
    { id = 'combat', title = 'Combat (Server Log and on screen)' },
    { id = 'text', title = 'Text (console)' },
}

-- The preview's lines. A loot line is a monster and the rows it shows; a
-- value row only shows while the player has that many prices, and a line left
-- with none is hidden (the second demon line only appears past five prices).
-- The wyvern is a Tainted one and the combat line names a Corrupted orc, so
-- both monster-name colors show too.
local PREVIEW = {
    { monster = 'a hydra', keys = { 'common', 'rare', 'epic', 'legendary' } },
    { monster = 'a demon', keys = { 'value1', 'value2', 'value3', 'value4', 'value5' } },
    { monster = 'a demon', keys = { 'value6', 'value7', 'value8', 'value9', 'value10' } },
    { monster = 'a tainted wyvern', coins = true, keys = { 'material', 'veryRare' } },
    { combat = true },
}

-- The built-in sets. Standard is exactly what the server sends, so a player
-- who never opens this page sees no change in loot lines at all.
PRESETS = {
    standard = {
        name = 'Standard',
        colors = {
            common = '#A0A0A0', rare = '#4080FF', epic = '#A020F0', legendary = '#DF7010',
            value1 = '#00C000', value2 = '#4080FF', value3 = '#A020F0', value4 = '#DF7010', value5 = '#FFF040',
            value6 = '#FF60A0', value7 = '#C0FF40', value8 = '#E0C0FF', value9 = '#FFC890', value10 = '#A0E0FF',
            material = '#00FFFF', veryRare = '#FF0000',
            tainted = '#55AAFF', corrupted = '#FF4040', crit = '#FF3030',
            lootText = '#FFFFFF', logText = '#FFFFFF',
        },
    },
    -- Picked by simulating red-weak, green-weak and blue-weak vision
    -- (Machado 2009, full strength) and measuring how far apart the colors
    -- stay (CAM02-UCS distance). For all four ways of seeing: the default
    -- loot colors stay at least 10 apart from each other and at least 20 from
    -- the white loot text (the old Okabe-Ito based set fell to 4), all loot
    -- colors including the extra prices at least 6.8, and every color keeps
    -- at least 3:1 contrast on the console's oak background. Very rare is a
    -- light red on purpose: a deep red turns almost black for red-weak
    -- players. The colors that share a line (monster-name word, crit number,
    -- white text) are kept apart too.
    colorblind = {
        name = 'Color-blind friendly',
        colors = {
            common = '#969696', rare = '#4BC3FF', epic = '#B478F0', legendary = '#FF8700',
            value1 = '#87FF87', value2 = '#4BC3FF', value3 = '#B478F0', value4 = '#FF8700', value5 = '#E1D22D',
            value6 = '#B4965A', value7 = '#B4C35A', value8 = '#87B4D2', value9 = '#A5D2FF', value10 = '#4BC32D',
            material = '#1EA5B4', veryRare = '#FFA596',
            tainted = '#56B4E9', corrupted = '#E69F00', crit = '#FF6EC8',
            lootText = '#FFFFFF', logText = '#FFFFFF',
        },
    },
}

local PRESET_ORDER = { 'standard', 'colorblind' }

-- client_options 'framesRarity'.
local FRAME_TYPES = { { 'None', 'none' }, { 'Frames', 'frames' }, { 'Corners', 'corners' } }

-- Item rarity ids (OTSERV upgrade_system_const.lua) -> rarity rows.
local RARITY_KEYS = { [1] = 'common', [2] = 'rare', [3] = 'epic', [4] = 'legendary' }

-- The words colored in monster names. The server builds those names
-- (Monster::setVariantDisplayName) from data/monster/variant_config.lua.
local VARIANT_WORDS = {
    { word = 'tainted', key = 'tainted' },
    { word = 'corrupted', key = 'corrupted' },
}

-- Chat color tags: name -> color, the same for everyone who reads the line.
-- Kept to colors that read well on the dark console, and no red (above).
CHAT_COLORS = {
    { name = 'white', color = '#FFFFFF' },
    { name = 'grey', color = '#A8A8A8' },
    { name = 'orange', color = '#FF9933' },
    { name = 'yellow', color = '#FFFF55' },
    { name = 'gold', color = '#E8C050' },
    { name = 'green', color = '#44DD44' },
    { name = 'lime', color = '#B0FF50' },
    { name = 'teal', color = '#33CCAA' },
    { name = 'cyan', color = '#55E5FF' },
    { name = 'blue', color = '#5A8CFF' },
    { name = 'purple', color = '#B266FF' },
    { name = 'pink', color = '#FF77CC' },
    { name = 'brown', color = '#C08850' },
}
local CHAT_RESET = '/'
local CHAT_COLOR_BY_NAME = { gray = '#A8A8A8' }
for _, entry in ipairs(CHAT_COLORS) do
    CHAT_COLOR_BY_NAME[entry.name] = entry.color
end

-- Server channel ids that take chat colors (OTSERV data/chatchannels/
-- chatchannels.xml): Advertising and Advertising-Rookgaard. Local Chat is
-- said / whispered / yelled text, told apart by its message mode.
local CHAT_CHANNEL_IDS = { [5] = true, [6] = true }

-- The names over Tainted and Corrupted monsters on the map: the same fixed
-- colors for everyone, not on this page. Drawn with Creature:setNameColor
-- (TSRclient C++, creature.h); a client built without it shows the usual
-- health color. The name starts with the variant word (OTSERV
-- Monster::setVariantDisplayName: "Corrupted Orc").
local MONSTER_NAME_COLORS = {
    { prefix = 'tainted ', color = '#55AAFF' },
    { prefix = 'corrupted ', color = '#FF4040' },
}

local SLOT_BY_KEY = {}
local KEY_BY_CODE = {}
for _, slot in ipairs(SLOTS) do
    SLOT_BY_KEY[slot.key] = slot
    if slot.code then
        KEY_BY_CODE[slot.code] = slot.key
    end
end

-- Helpers --------------------------------------------------------------------

local function copyList(list)
    local copy = {}
    for k, v in pairs(list) do
        copy[k] = v
    end
    return copy
end

-- '#4080ff', '4080FF' -> '#4080FF'; anything else -> nil.
local function normalize(color)
    if type(color) ~= 'string' then
        return nil
    end
    local hex = color:match('^%s*#?(%x%x%x%x%x%x)%s*$')
    return hex and ('#' .. hex:upper()) or nil
end

local function toHex(r, g, b)
    return string.format('#%02X%02X%02X', r, g, b)
end

-- The outfit window's 133 colors, by the client's own formula
-- (Outfit::getColor, src/client/outfit.cpp): 19 hues across, 7 rows of
-- saturation and brightness, the first column greys.
local function outfitColor(index)
    local H_STEPS, SI_VALUES = 19, 7
    local hue, sat, int = 0, 0, 0
    if index % H_STEPS ~= 0 then
        hue = (index % H_STEPS) / 18
        local row = math.floor(index / H_STEPS)
        local table_ = { { 0.25, 1.00 }, { 0.25, 0.75 }, { 0.50, 0.75 }, { 0.667, 0.75 },
            { 1.00, 1.00 }, { 1.00, 0.75 }, { 1.00, 0.50 } }
        sat, int = table_[row + 1][1], table_[row + 1][2]
    else
        int = 1 - index / H_STEPS / SI_VALUES
    end

    if int == 0 then
        return '#000000'
    end
    if sat == 0 then
        local v = math.floor(int * 255)
        return toHex(v, v, v)
    end

    local r, g, b
    if hue < 1 / 6 then
        r = int; b = int * (1 - sat); g = b + (int - b) * 6 * hue
    elseif hue < 2 / 6 then
        g = int; b = int * (1 - sat); r = g - (int - b) * (6 * hue - 1)
    elseif hue < 3 / 6 then
        g = int; r = int * (1 - sat); b = r + (int - r) * (6 * hue - 2)
    elseif hue < 4 / 6 then
        b = int; r = int * (1 - sat); g = b - (int - r) * (6 * hue - 3)
    elseif hue < 5 / 6 then
        b = int; g = int * (1 - sat); r = g + (int - g) * (6 * hue - 4)
    else
        r = int; g = int * (1 - sat); b = r - (int - g) * (6 * hue - 5)
    end
    return toHex(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-- Relative luminance (WCAG). Below this a color is hard to read on the
-- console's dark background (about 3:1 contrast or less).
local READABLE_LUMINANCE = 0.14

local function luminance(hex)
    local function channel(i)
        local c = tonumber(hex:sub(i, i + 1), 16) / 255
        return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * channel(2) + 0.7152 * channel(4) + 0.0722 * channel(6)
end

function isReadable(hex)
    return luminance(hex) >= READABLE_LUMINANCE
end

-- CIE Lab (D65) of '#RRGGBB', for how different two colors look.
local function toLab(hex)
    local function linear(i)
        local c = tonumber(hex:sub(i, i + 1), 16) / 255
        return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
    end
    local r, g, b = linear(2), linear(4), linear(6)
    local x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    local y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    local z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    local function f(v)
        return v > 0.008856 and v ^ (1 / 3) or 7.787 * v + 16 / 116
    end
    return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))
end

local function colorDistance(a, b)
    local l1, a1, b1 = toLab(a)
    local l2, a2, b2 = toLab(b)
    return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end

-- How far apart an item's (or word's) color and the text around it must look.
-- Every default color is at least 29 from white, so defaults never move.
local APART_MIN = 25

-- `color` as shown inside text of color `base`: itself when they look
-- different enough, else mixed a little toward white or black (away from
-- the text's lightness first) until they do, staying readable. The player's
-- saved color never changes; only how it is drawn next to that text.
function apartFrom(color, base)
    color, base = normalize(color), normalize(base)
    if not color or not base or colorDistance(color, base) >= APART_MIN then
        return color
    end
    local r, g, b = tonumber(color:sub(2, 3), 16), tonumber(color:sub(4, 5), 16), tonumber(color:sub(6, 7), 16)
    local lighterFirst = (toLab(color)) >= (toLab(base))
    for step = 1, 10 do
        local t = step / 10
        local lighter = toHex(math.floor(r + (255 - r) * t), math.floor(g + (255 - g) * t), math.floor(b + (255 - b) * t))
        local darker = toHex(math.floor(r * (1 - t)), math.floor(g * (1 - t)), math.floor(b * (1 - t)))
        local first, second = darker, lighter
        if lighterFirst then
            first, second = lighter, darker
        end
        for _, candidate in ipairs({ first, second }) do
            if isReadable(candidate) and colorDistance(candidate, base) >= APART_MIN then
                return candidate
            end
        end
    end
    return color
end

-- 30000 -> '30,000'
local function gold(n)
    local text = tostring(math.floor(n))
    local formatted = text:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (formatted:gsub('^,', ''))
end

-- A list of 1 to MAX_STEPS whole, rising prices, or nil.
local function validSteps(steps)
    if type(steps) ~= 'table' or #steps < 1 or #steps > MAX_STEPS then
        return nil
    end
    local clean = {}
    for i = 1, #steps do
        local value = tonumber(steps[i])
        if not value or value ~= math.floor(value) or value < 1 or value > MAX_STEP_PRICE then
            return nil
        end
        if i > 1 and value <= clean[i - 1] then
            return nil
        end
        clean[i] = value
    end
    return clean
end

-- State ----------------------------------------------------------------------

local state = {
    set = 'standard',
    custom = {},
    steps = copyList(DEFAULT_STEPS),
    alerts = {},
    sparkles = {}, -- kinds whose corpses sparkle (sent to the server)
    colorNames = true,
    markers = false, -- "[R]" etc. after item names in loot lines
    markerText = {}, -- the player's own marker per row ('' = none)
    valueFrames = true,
    chatColors = true, -- show the chat color tags of every player
    onlyColored = false, -- loot lines: colored items only, the rest counted
    recent = {},
    pins = {}, -- server item id -> price range
}

local optionPanel = nil
local presetBox = nil
local framesBlock = nil
local extras = nil
local stepButtons = nil
local rows = {}
local settingAmounts = false
local settingFrameType = false
local sendEvent = nil
local statusEvent = nil
local framesEvent = nil

local picker = nil
local pickerKey = nil
local pickerColor = nil
local pickerGroup = nil
local pickerBoxes = {}
local pickerSettingText = false

local itemsWindow = nil
local itemsStep = nil

-- Client item id -> price range, built from state.pins through the autoloot
-- catalog the first time a frame needs it after a change.
local pinsByClientId = nil

local function slotLabel(slot)
    if slot.key == 'common' then
        return 'Common (under ' .. gold(state.steps[1]) .. ' gp)'
    end
    if slot.step then
        local from = state.steps[slot.step]
        local nextStep = state.steps[slot.step + 1]
        if nextStep then
            return gold(from) .. ' - ' .. gold(nextStep - 1) .. ' gp'
        end
        return gold(from) .. '+ gp'
    end
    return slot.label
end

-- The color this player has for a row right now.
-- The player's color for an item rarity id, or nil. The item tooltip
-- (game_itemtooltip) and chat item links (game_itemshare, through the
-- tooltip's getRarityColor) paint the name and rarity word with it, so they
-- match the loot lines.
function rarityColor(rarityId)
    local key = RARITY_KEYS[tonumber(rarityId) or 0]
    return key and colorFor(key) or nil
end

function colorFor(key)
    if state.set == 'custom' then
        local color = normalize(state.custom[key])
        if color then
            return color
        end
        return PRESETS.standard.colors[key]
    end
    local preset = PRESETS[state.set] or PRESETS.standard
    return preset.colors[key]
end

-- Called by ItemsDatabase.setColorLootMessage for every colored loot entry.
-- nil means "no color": the player switched colored names off.
function mapColor(code)
    if not state.colorNames then
        return nil
    end
    local key = KEY_BY_CODE[normalize(code) or '']
    if not key then
        return code
    end
    -- Kept apart from the player's loot text color (apartFrom).
    return apartFrom(colorFor(key), colorFor('lootText')) or code
end

function getSteps()
    return copyList(state.steps)
end

-- 500 -> '500', 3000 -> '3k', 1500000 -> '1.5m'
local function shortGold(n)
    local function trim(x)
        return (string.format('%.1f', x):gsub('%.0$', ''))
    end
    if n >= 1000000 then
        return trim(n / 1000000) .. 'm'
    end
    if n >= 1000 then
        return trim(n / 1000) .. 'k'
    end
    return tostring(n)
end

local MARKERS = { common = 'C', rare = 'R', epic = 'E', legendary = 'L', material = 'M', veryRare = '!' }
local MARKER_MAX = 4

-- 0 to MARKER_MAX letters, digits or signs. No braces or square brackets:
-- braces are setColoredText's markup and the marker sits in [ ].
function validMarker(text)
    return type(text) == 'string' and #text <= MARKER_MAX and
        text:match('^[%w!"#%$%%&\'%(%)%*%+,%-%./:;<=>%?@%^_`|~]*$') ~= nil
end

-- A row's marker text without the brackets: the player's own, else the
-- default (a letter, or the lowest price of that value range).
local function defaultMarker(key)
    if MARKERS[key] then
        return MARKERS[key]
    end
    local slot = SLOT_BY_KEY[key]
    if slot and slot.step and state.steps[slot.step] then
        return shortGold(state.steps[slot.step])
    end
    return ''
end

local function markerText(key)
    local own = state.markerText[key]
    if own then
        return own
    end
    return defaultMarker(key)
end

-- The marker for a row as it goes after a name: ' [R]', ' [30k]', or ''.
local function markerFor(key)
    local text = markerText(key)
    if text == '' then
        return ''
    end
    return ' [' .. text .. ']'
end

-- Called by ItemsDatabase.setColorLootMessage with the code the server sent
-- for an item: what goes after its name, '' when markers are off.
function lootMarker(code)
    if not state.markers then
        return ''
    end
    local key = KEY_BY_CODE[normalize(code) or '']
    return key and markerFor(key) or ''
end

-- With "only colored items" on: the loot line as the server sent it, cut to
-- its colored entries ({name, #code}) and a count of the rest:
-- "Loot of a demon: {a fire axe, #..}, +5 more." / "Loot of a rat: 2 items."
function filterLoot(text)
    if not state.onlyColored or type(text) ~= 'string' then
        return text
    end
    local head, list = text:match('^(Loot of [^:{}]-: )(.*)$')
    if not head or list == 'nothing' or list == 'nothing.' then
        return text
    end
    list = list:gsub('%.$', '')
    local kept, hidden, pos = {}, 0, 1
    while pos <= #list do
        local entry
        if list:sub(pos, pos) == '{' then
            local close = list:find('}', pos, true)
            if not close then
                return text
            end
            entry = list:sub(pos, close)
            pos = close + 1
        else
            local sep = list:find(', ', pos, true) or (#list + 1)
            entry = list:sub(pos, sep - 1)
            pos = sep
        end
        if list:sub(pos, pos + 1) == ', ' then
            pos = pos + 2
        end
        if entry:sub(1, 1) == '{' then
            kept[#kept + 1] = entry
        elseif entry ~= '' then
            hidden = hidden + 1
        end
    end
    if hidden == 0 then
        return text
    end
    if #kept == 0 then
        return head .. hidden .. ' ' .. (hidden == 1 and tr('item') or tr('items')) .. '.'
    end
    return head .. table.concat(kept, ', ') .. ', +' .. hidden .. ' ' .. tr('more') .. '.'
end

local itemKey -- defined with the frames below

-- What the player looked at last (g_game.look), for the "You see" line that
-- answers it.
local lastLook = nil
local originalLook = nil

-- The "You see ..." line as setColoredText markup with the item's name in its
-- loot color (and marker), the rest in `base`; nil when it is not about an
-- item that has a color, or colored names are off.
function lookMarkup(text, base)
    local look = lastLook
    if type(text) ~= 'string' or text:sub(1, 8) ~= 'You see ' then
        return nil
    end
    lastLook = nil
    if not state.colorNames or not look or g_clock.millis() - look.time > 3000 then
        return nil
    end
    local thing = look.thing
    if not thing or not thing.isItem or not thing:isItem() then
        return nil
    end
    local key = itemKey(thing, true)
    if not key then
        return nil
    end
    -- The name runs to the first " (", "." or line break.
    local stop = #text + 1
    for _, mark in ipairs({ ' (', '.', '\n' }) do
        local at = text:find(mark, 9, true)
        if at and at < stop then
            stop = at
        end
    end
    local name = text:sub(9, stop - 1)
    if name == '' then
        return nil
    end
    base = base or '#FFFFFF'
    local color = apartFrom(colorFor(key), base)
    local rest = text:sub(stop):gsub('[{}]', '')
    local shown = name:gsub('[{}]', '') .. (state.markers and markerFor(key) or '')
    local out = '{You see , ' .. base .. '}{' .. shown .. ', ' .. color .. '}'
    if rest ~= '' then
        out = out .. '{' .. rest .. ', ' .. base .. '}'
    end
    return out
end

-- Where "tainted" and "corrupted" stand in a line, as whole words in any case,
-- with the player's color for each: { { from, to, color }, ... } in order, or
-- nil when the line has neither. game_textmessage splits Server Log lines on
-- these. With `base` (the line's own color) each color is kept apart from it.
function variantSpans(text, base)
    if type(text) ~= 'string' then
        return nil
    end
    local lower = text:lower()
    local spans = {}
    for _, variant in ipairs(VARIANT_WORDS) do
        local pos = 1
        while true do
            local from, to = lower:find('%f[%a]' .. variant.word .. '%f[%A]', pos)
            if not from then
                break
            end
            local color = colorFor(variant.key)
            if base then
                color = apartFrom(color, base) or color
            end
            spans[#spans + 1] = { from = from, to = to, color = color }
            pos = to + 1
        end
    end
    if #spans == 0 then
        return nil
    end
    table.sort(spans, function(a, b) return a.from < b.from end)
    return spans
end

-- The same words colored inside text that is otherwise plain (no {...}).
local function markVariants(text)
    local spans = variantSpans(text, colorFor('lootText'))
    if not spans then
        return text
    end
    local parts, pos = {}, 1
    for _, span in ipairs(spans) do
        parts[#parts + 1] = text:sub(pos, span.from - 1)
        parts[#parts + 1] = '{' .. text:sub(span.from, span.to) .. ', ' .. span.color .. '}'
        pos = span.to + 1
    end
    parts[#parts + 1] = text:sub(pos)
    return table.concat(parts)
end

-- Called by ItemsDatabase.setColorLootMessage with the finished loot line:
-- colors the variant word in "Loot of a corrupted orc:" and nothing after
-- the colon (item names keep their loot colors).
function colorLootHead(text)
    local head, rest = text:match('^(Loot of [^:{}]-:)(.*)$')
    if not head then
        return text
    end
    return markVariants(head) .. rest
end

-- Called by game_textmessage for every "Loot of ..." line, with the text as
-- the server sent it. Returns nil, or the plain and colored alert text when
-- the line holds a kind of drop the player ticked Message on.
function lootAlert(text)
    if next(state.alerts) == nil then
        return nil
    end
    local monster = text:match('^Loot of (.-):') or 'a monster'
    local plain, colored = {}, {}
    for entry in text:gmatch('{(.-)}') do
        local name, code = entry:match('^(.*), (#%x%x%x%x%x%x)$')
        local key = code and KEY_BY_CODE[normalize(code)]
        if key and state.alerts[key] then
            name = name .. (state.markers and markerFor(key) or '')
            plain[#plain + 1] = name
            colored[#colored + 1] = '{' .. name .. ', ' .. (state.colorNames and apartFrom(colorFor(key), colorFor('lootText')) or colorFor('lootText')) .. '}'
        end
    end
    if #plain == 0 then
        return nil
    end
    local head = tr('Loot alert from') .. ' ' .. monster .. ': '
    return { plain = head .. table.concat(plain, ', '), colored = markVariants(head) .. table.concat(colored, ', ') }
end

-- Backpack frames ------------------------------------------------------------

local function catalog()
    local autoloot = modules.game_autoloot and modules.game_autoloot.AutoLoot
    if autoloot and autoloot.itemCatalog then
        return autoloot.itemCatalog, autoloot.itemByServerId or {}
    end
    return nil, {}
end

local function pinsForFrames()
    if pinsByClientId then
        return pinsByClientId
    end
    local list, byServerId = catalog()
    local map = {}
    for serverId, range in pairs(state.pins) do
        local data = byServerId[serverId]
        if data and range <= #state.steps then
            map[data.clientId] = range
        end
    end
    -- Without the catalog yet (autoloot loads after this module) try again
    -- next time rather than remembering an empty map.
    if list then
        pinsByClientId = map
    end
    return map
end

-- The price range an NPC price falls in with this player's prices, or nil.
local function stepFor(price)
    if not price then
        return nil
    end
    local step = nil
    for i, min in ipairs(state.steps) do
        if price >= min then
            step = i
        end
    end
    return step
end

-- The color an item's frame gets, or nil for none: the same choice the server
-- makes for its loot line (LootColors.describeItem, RARITY_FIRST), so a drop
-- reads the same in the loot line and in the backpack. With value frames
-- off, only rarity rolls get one.
-- The row an item falls in (its SLOTS key), or nil. `full` = everything;
-- otherwise rarity rolls only.
itemKey = function(item, full)
    if not item or not item.getId then
        return nil
    end
    local rarity = item.getRarity and item:getRarity() or 0
    rarity = RARITY_KEYS[rarity] and rarity or nil
    if not full then
        return rarity and RARITY_KEYS[rarity] or nil
    end

    local clientId = item:getId()
    local pinned = pinsForFrames()[clientId]
    if pinned then
        if not rarity or rarity == 1 then
            return 'value' .. pinned
        end
        return RARITY_KEYS[rarity]
    end
    if VALUES.veryRare[clientId] then
        return 'veryRare'
    end
    if VALUES.materials[clientId] then
        return 'material'
    end
    local step = stepFor(VALUES.prices[clientId])
    if rarity == 1 and step then
        return 'value' .. step
    end
    if rarity then
        return RARITY_KEYS[rarity]
    end
    if step then
        return 'value' .. step
    end
    return nil
end

function frameColor(item)
    local key = itemKey(item, state.valueFrames)
    return key and colorFor(key) or nil
end

-- Repaints the frames of every open container and the equipment slots.
local function refreshFrames()
    for _, container in pairs(g_game.getContainers()) do
        local panel = container.itemsPanel
        if panel then
            for _, widget in ipairs(panel:getChildren()) do
                if widget.getItem then
                    ItemsDatabase.setRarityItem(widget, widget:getItem())
                end
            end
        end
    end
    local inventory = modules.game_inventory
    if inventory and inventory.reloadInventory then
        inventory.reloadInventory()
    end
end

local function monsterNameColor(creature)
    if not creature.isMonster or not creature:isMonster() then
        return nil
    end
    local name = (creature:getName() or ''):lower()
    for _, entry in ipairs(MONSTER_NAME_COLORS) do
        if name:sub(1, #entry.prefix) == entry.prefix then
            return entry.color
        end
    end
    return nil
end

-- Creature onAppear: a Tainted or Corrupted monster gets its name color.
local function onCreatureAppear(creature)
    if not creature or not creature.setNameColor then
        return
    end
    local color = monsterNameColor(creature)
    if color then
        creature:setNameColor(color)
    end
end

-- Monsters already on screen when the module loads.
local function paintMonsterNames()
    local player = g_game.getLocalPlayer()
    if not player or not g_map.getSpectators then
        return
    end
    for _, creature in ipairs(g_map.getSpectators(player:getPosition(), true) or {}) do
        onCreatureAppear(creature)
    end
end

local function refreshFramesSoon()
    removeEvent(framesEvent)
    framesEvent = scheduleEvent(function()
        framesEvent = nil
        if g_game.isOnline() then
            refreshFrames()
        end
    end, 100)
end

-- client_options calls this when 'framesRarity' changes (data_options.lua),
-- so the box here follows it.
function onFramesOption(value)
    if framesBlock then
        settingFrameType = true
        framesBlock.typeRow.frameType:setCurrentOptionByData(value, true)
        settingFrameType = false
        framesBlock.valueRow.valueFrames:setEnabled(value ~= 'none')
    end
    refreshFramesSoon()
end

-- Settings -------------------------------------------------------------------

-- Corpses that sparkle for a new player: epic and legendary drops.
local DEFAULT_SPARKLES = { epic = true, legendary = true }

-- Back to a fresh player's settings (before a profile is loaded).
local function resetState()
    state.set = 'standard'
    state.custom = {}
    state.steps = copyList(DEFAULT_STEPS)
    state.alerts = {}
    state.sparkles = copyList(DEFAULT_SPARKLES)
    state.colorNames = true
    state.markers = false
    state.markerText = {}
    state.valueFrames = true
    state.chatColors = true
    state.onlyColored = false
    state.recent = {}
    state.pins = {}
end

local function loadSettings(saved)
    saved = saved or g_settings.getNode(SETTINGS_KEY)
    if type(saved) ~= 'table' then
        return
    end
    if saved.set == 'custom' or PRESETS[saved.set] then
        state.set = saved.set
    end
    if type(saved.custom) == 'table' then
        for key, color in pairs(saved.custom) do
            if SLOT_BY_KEY[key] and normalize(color) then
                state.custom[key] = normalize(color)
            end
        end
    end
    state.steps = validSteps(saved.steps) or state.steps
    -- sparklesChosen: saved once the page has been saved with these ticks, so
    -- a player who unticked epic and legendary does not get them back (an
    -- empty list may not come back from the settings file at all).
    if saved.sparklesChosen ~= nil then
        state.sparkles = {}
    end
    for field, ticks in pairs({ alerts = state.alerts, sparkles = state.sparkles }) do
        if type(saved[field]) == 'table' then
            for key, on in pairs(saved[field]) do
                local slot = SLOT_BY_KEY[key]
                if slot and not slot.noAlert and not (field == 'sparkles' and slot.noSparkle)
                    and (on == true or on == 'true') then
                    ticks[key] = true
                end
            end
        end
    end
    if saved.markers == true or saved.markers == 'true' then
        state.markers = true
    end
    if type(saved.markerText) == 'table' then
        for key, text in pairs(saved.markerText) do
            if SLOT_BY_KEY[key] and validMarker(tostring(text)) then
                state.markerText[key] = tostring(text)
            end
        end
    end
    if saved.colorNames == false or saved.colorNames == 'false' then
        state.colorNames = false
    end
    if saved.valueFrames == false or saved.valueFrames == 'false' then
        state.valueFrames = false
    end
    if saved.chatColors == false or saved.chatColors == 'false' then
        state.chatColors = false
    end
    if saved.onlyColored == true or saved.onlyColored == 'true' then
        state.onlyColored = true
    end
    if type(saved.recent) == 'table' then
        for _, color in ipairs(saved.recent) do
            if normalize(color) and #state.recent < RECENT_MAX then
                state.recent[#state.recent + 1] = normalize(color)
            end
        end
    end
    -- Saved as "serverId:range" strings: settings keys cannot be numbers.
    if type(saved.pins) == 'table' then
        local count = 0
        for _, entry in ipairs(saved.pins) do
            local id, range = tostring(entry):match('^(%d+):(%d+)$')
            id, range = tonumber(id), tonumber(range)
            if id and range and range >= 1 and range <= MAX_STEPS and count < MAX_PINS then
                state.pins[id] = range
                count = count + 1
            end
        end
    end
end

local function pinList()
    local list = {}
    for id, range in pairs(state.pins) do
        list[#list + 1] = { id, range }
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    return list
end

local function snapshot()
    local pins = {}
    for i, entry in ipairs(pinList()) do
        pins[i] = entry[1] .. ':' .. entry[2]
    end
    return {
        set = state.set,
        custom = copyList(state.custom),
        steps = copyList(state.steps),
        alerts = copyList(state.alerts),
        sparkles = copyList(state.sparkles),
        sparklesChosen = true,
        colorNames = state.colorNames,
        markers = state.markers,
        markerText = copyList(state.markerText),
        valueFrames = state.valueFrames,
        chatColors = state.chatColors,
        onlyColored = state.onlyColored,
        recent = copyList(state.recent),
        pins = pins,
    }
end

-- Profiles: { active = name, list = { { name =, settings = }, ... },
-- characters = { "Character|Profile", ... } }. Lists, not name keys: names
-- and character names can hold spaces, and settings keys cannot be numbers.
local PROFILES_KEY = 'colorProfiles'
local DEFAULT_PROFILE = 'Default'
local PROFILE_NAME_MAX = 20
local profiles = { active = DEFAULT_PROFILE, list = {}, characters = {} }

local function findProfile(name)
    for i, entry in ipairs(profiles.list) do
        if entry.name == name then
            return entry, i
        end
    end
    return nil
end

local function saveProfiles()
    local characters = {}
    for character, name in pairs(profiles.characters) do
        characters[#characters + 1] = character .. '|' .. name
    end
    table.sort(characters)
    local list = {}
    for i, entry in ipairs(profiles.list) do
        list[i] = { name = entry.name, settings = entry.settings }
    end
    g_settings.setNode(PROFILES_KEY, { active = profiles.active, list = list, characters = characters })
end

local function saveSettings()
    local current = snapshot()
    g_settings.setNode(SETTINGS_KEY, current)
    local entry = findProfile(profiles.active)
    if entry then
        entry.settings = current
        saveProfiles()
    end
    g_settings.save()
end

local function loadProfiles()
    local saved = g_settings.getNode(PROFILES_KEY)
    profiles = { active = DEFAULT_PROFILE, list = {}, characters = {} }
    if type(saved) == 'table' then
        for _, entry in ipairs(type(saved.list) == 'table' and saved.list or {}) do
            if type(entry) == 'table' and type(entry.name) == 'string' and not findProfile(entry.name) then
                profiles.list[#profiles.list + 1] = { name = entry.name, settings = entry.settings }
            end
        end
        for _, pair in ipairs(type(saved.characters) == 'table' and saved.characters or {}) do
            local character, name = tostring(pair):match('^(.-)|(.+)$')
            if character and character ~= '' then
                profiles.characters[character] = name
            end
        end
        if type(saved.active) == 'string' and findProfile(saved.active) then
            profiles.active = saved.active
        end
    end
    if not findProfile(DEFAULT_PROFILE) then
        table.insert(profiles.list, 1, { name = DEFAULT_PROFILE, settings = snapshot() })
    end
end

-- Server ---------------------------------------------------------------------

function sendSteps()
    if not g_game.isOnline() then
        return
    end
    local protocol = g_game.getProtocolGame()
    if protocol then
        -- sparkles: the kinds ticked Sparkle on, so the server can make those
        -- corpses sparkle for this player (LootColors.sparkle).
        local sparkles = {}
        for key in pairs(state.sparkles) do
            if SLOT_BY_KEY[key] and not SLOT_BY_KEY[key].noSparkle then
                sparkles[#sparkles + 1] = key
            end
        end
        table.sort(sparkles)
        protocol:sendExtendedOpcode(OPCODE, json.encode({ steps = state.steps, items = pinList(), sparkles = sparkles }))
    end
end

-- Typing a price would send on every valid keystroke otherwise.
local function sendStepsSoon()
    removeEvent(sendEvent)
    sendEvent = scheduleEvent(function()
        sendEvent = nil
        sendSteps()
    end, 600)
end

-- Page -----------------------------------------------------------------------

-- A Server Log line as the console shows it: the variant word, the crit
-- number and the rest of the line in the player's colors.
local function combatPreview()
    local text = colorFor('logText')
    return '{A , ' .. text .. '}{corrupted, ' .. apartFrom(colorFor('corrupted'), text) .. '}{ orc loses , ' .. text .. '}' ..
        '{' .. SLOT_BY_KEY.crit.sample .. ', ' .. apartFrom(colorFor('crit'), text) .. '}' ..
        '{ hitpoints due to your attack., ' .. text .. '}'
end

-- The line's text, or nil when none of its rows is in use.
local function previewLine(line)
    if line.combat then
        return combatPreview()
    end
    local parts = {}
    if line.coins then
        parts[#parts + 1] = '3 gold coins'
    end
    local shown = 0
    for _, key in ipairs(line.keys) do
        local slot = SLOT_BY_KEY[key]
        if slot.step and slot.step > #state.steps then
            break
        end
        shown = shown + 1
        local name = slot.sample .. (state.markers and markerFor(key) or '')
        if state.colorNames then
            parts[#parts + 1] = '{' .. name .. ', ' .. apartFrom(colorFor(key), colorFor('lootText')) .. '}'
        else
            parts[#parts + 1] = name
        end
    end
    if shown == 0 then
        return nil
    end
    return colorLootHead('Loot of ' .. line.monster .. ': ' .. table.concat(parts, ', ') .. '.')
end

-- The preview's lines as shown: PREVIEW's loot lines cut to the rows in use,
-- at most PREVIEW_PER_LINE items each (3 with markers on: five items with
-- markers no longer fit across the page).
local PREVIEW_LABELS = 8 -- line1 .. line8 in colors.otui
local function previewLines()
    local per = state.markers and 3 or 5
    local out = {}
    for _, line in ipairs(PREVIEW) do
        if line.combat then
            out[#out + 1] = line
        else
            local keys = {}
            for _, key in ipairs(line.keys) do
                local slot = SLOT_BY_KEY[key]
                if not slot.step or slot.step <= #state.steps then
                    keys[#keys + 1] = key
                end
            end
            for first = 1, #keys, per do
                local part = {}
                for i = first, math.min(first + per - 1, #keys) do
                    part[#part + 1] = keys[i]
                end
                out[#out + 1] = { monster = line.monster, coins = line.coins and first == 1, keys = part }
            end
        end
    end
    return out
end

local function refreshPreview()
    if not optionPanel then
        return
    end
    local lines = previewLines()
    local visible = 0
    for i = 1, PREVIEW_LABELS do
        local label = optionPanel.preview['line' .. i]
        local text = lines[i] and previewLine(lines[i])
        label:setVisible(text ~= nil)
        if text then
            -- The plain parts of a loot line take the label's color.
            label:setColor(colorFor('lootText'))
            label:setColoredText(text)
            visible = visible + 1
        end
    end
    -- 14 px per line plus the frame's 4 px top and bottom padding.
    optionPanel.preview:setHeight(visible * 14 + 8)
end

local function refreshStepButtons()
    if not stepButtons then
        return
    end
    local count = #state.steps
    stepButtons.addStep:setEnabled(count < MAX_STEPS and state.steps[count] < MAX_STEP_PRICE)
    stepButtons.removeStep:setEnabled(count > 1)
    stepButtons.count:setText(count .. ' / ' .. MAX_STEPS .. ' ' .. tr('prices'))
end

local function refreshRows()
    for key, row in pairs(rows) do
        local slot = SLOT_BY_KEY[key]
        if slot.step then
            row:setVisible(slot.step <= #state.steps)
        end
        local color = colorFor(key)
        row.swatch:setBackgroundColor(color)
        row.swatch:setTooltip(color)
        row.caption:setColor(color)
        if not slot.step or slot.step <= #state.steps then
            row.caption:setText(tr(slotLabel(slot)))
        end
        if slot.step then
            local count = 0
            for _, range in pairs(state.pins) do
                if range == slot.step then
                    count = count + 1
                end
            end
            row.items:setText(count > 0 and (tr('Items') .. ' (' .. count .. ')') or tr('Items'))
        end
    end
    if itemsStep and itemsStep > #state.steps then
        closeItems()
    end
    refreshStepButtons()
    refreshPreview()
    refreshFramesSoon()
end

local function refreshAmounts()
    settingAmounts = true
    for key, row in pairs(rows) do
        local slot = SLOT_BY_KEY[key]
        if slot.step and state.steps[slot.step] then
            row.amount:setText(tostring(state.steps[slot.step]))
            row.amount:setColor(g_ui.getVariable('textColor'))
        end
    end
    settingAmounts = false
end

local function showStatus(text, isError)
    if not extras then
        return
    end
    local status = extras.buttonsRow.status
    status:setText(text)
    status:setColor(isError and '#FF8060' or g_ui.getVariable('textDim'))
    removeEvent(statusEvent)
    statusEvent = scheduleEvent(function()
        statusEvent = nil
        if extras then
            extras.buttonsRow.status:setText('')
        end
    end, 4000)
end

local function selectSet(set)
    if set == 'custom' and next(state.custom) == nil then
        state.custom = copyList(PRESETS.standard.colors)
    end
    state.set = set
    saveSettings()
    refreshRows()
end

-- Changing one color always lands in Custom, starting from what was shown.
local function enterCustom()
    if state.set == 'custom' then
        return
    end
    local shown = {}
    for _, slot in ipairs(SLOTS) do
        shown[slot.key] = colorFor(slot.key)
    end
    state.custom = shown
    state.set = 'custom'
    if presetBox then
        presetBox:setCurrentOptionByData('custom', true)
    end
end

local function rememberRecent(color)
    for i = #state.recent, 1, -1 do
        if state.recent[i] == color then
            table.remove(state.recent, i)
        end
    end
    table.insert(state.recent, 1, color)
    while #state.recent > RECENT_MAX do
        table.remove(state.recent)
    end
end

local function setColor(key, color)
    enterCustom()
    state.custom[key] = color
    rememberRecent(color)
    saveSettings()
    refreshRows()
end

-- A price typed into a value row. Applied only while the whole list is still
-- valid; otherwise the box turns red and nothing changes until it is fixed.
local function onAmountChange(slot, text)
    if settingAmounts then
        return
    end
    local row = rows[slot.key]
    local steps = copyList(state.steps)
    local value = tonumber(text)
    steps[slot.step] = value
    local clean = value and validSteps(steps)
    if not clean or #clean ~= #state.steps then
        row.amount:setColor('#FF6060')
        return
    end
    row.amount:setColor(g_ui.getVariable('textColor'))
    state.steps = clean
    saveSettings()
    refreshRows()
    sendStepsSoon()
end

local function applySteps(steps)
    state.steps = steps
    pinsByClientId = nil -- pins in a removed range stop counting
    saveSettings()
    refreshAmounts()
    refreshRows()
    sendStepsSoon()
end

function resetSteps()
    applySteps(copyList(DEFAULT_STEPS))
end

-- A new top price, twice the current top one (the player can type another).
function addStep()
    local count = #state.steps
    if count >= MAX_STEPS then
        return
    end
    local steps = copyList(state.steps)
    steps[count + 1] = math.min(state.steps[count] * 2, MAX_STEP_PRICE)
    if steps[count + 1] <= state.steps[count] then
        return
    end
    applySteps(steps)
end

-- Drops the top price; its row and color come back if one is added again.
function removeStep()
    local count = #state.steps
    if count <= 1 then
        return
    end
    local steps = copyList(state.steps)
    steps[count] = nil
    applySteps(steps)
end

function setOnlyColored(on)
    if state.onlyColored == on then
        return
    end
    state.onlyColored = on
    saveSettings()
end

function setMarkers(on)
    if state.markers == on then
        return
    end
    state.markers = on
    saveSettings()
    refreshPreview()
end

function setColorNames(on)
    if state.colorNames == on then
        return
    end
    state.colorNames = on
    saveSettings()
    refreshPreview()
end

function setValueFrames(on)
    if state.valueFrames == on then
        return
    end
    state.valueFrames = on
    saveSettings()
    refreshFramesSoon()
end

local function setAlert(key, on)
    state.alerts[key] = on or nil
    saveSettings()
end

local function setSparkle(key, on)
    state.sparkles[key] = on or nil
    saveSettings()
    sendStepsSoon()
end

local function setFrameType(value)
    if settingFrameType then
        return
    end
    -- client_options keeps the option and calls onFramesOption back.
    modules.client_options.setOption('framesRarity', value)
end

-- Sharing --------------------------------------------------------------------

-- TSRCOL1:A0A0A0-4080FF-...(one per SLOTS row):500-3000-10000-30000-60000
function makeShareCode()
    local colors = {}
    for _, slot in ipairs(SLOTS) do
        colors[#colors + 1] = colorFor(slot.key):sub(2)
    end
    local prices = {}
    for i, price in ipairs(state.steps) do
        prices[i] = tostring(price)
    end
    return SHARE_PREFIX .. ':' .. table.concat(colors, '-') .. ':' .. table.concat(prices, '-')
end

-- The colors (by SLOTS key) and prices in a code, or nil.
function readShareCode(code)
    if type(code) ~= 'string' then
        return nil
    end
    local prefix, colorPart, pricePart = code:match('^%s*(%w+):([%x%-]+):([%d%-]+)%s*$')
    if prefix ~= SHARE_PREFIX then
        return nil
    end
    local colors, i = {}, 0
    for hex in colorPart:gmatch('[^%-]+') do
        i = i + 1
        local slot = SLOTS[i]
        local color = normalize(hex)
        if not slot or not color then
            return nil
        end
        colors[slot.key] = color
    end
    if i ~= #SLOTS then
        return nil
    end
    local prices = {}
    for price in pricePart:gmatch('[^%-]+') do
        prices[#prices + 1] = tonumber(price)
    end
    local steps = validSteps(prices)
    if not steps then
        return nil
    end
    return colors, steps
end

function copyCode()
    g_window.setClipboardText(makeShareCode())
    showStatus(tr('Code copied.'))
end

function pasteCode()
    local colors, steps = readShareCode(g_window.getClipboardText())
    if not colors then
        showStatus(tr('No color code on the clipboard.'), true)
        return
    end
    state.custom = colors
    state.set = 'custom'
    state.steps = steps
    pinsByClientId = nil
    if presetBox then
        presetBox:setCurrentOptionByData('custom', true)
    end
    saveSettings()
    refreshAmounts()
    refreshRows()
    sendStepsSoon()
    showStatus(tr('Code used: it is now your Custom set.'))
end

-- Picker ---------------------------------------------------------------------

-- Every color of the two built-in sets, in row order, each once.
local function setPalette()
    local list, seen = {}, {}
    for _, set in ipairs(PRESET_ORDER) do
        for _, slot in ipairs(SLOTS) do
            local color = PRESETS[set].colors[slot.key]
            if not seen[color] then
                seen[color] = true
                list[#list + 1] = color
            end
        end
    end
    return list
end

-- The picker's one-line preview for a row in a color.
local function pickerPreview(key, color)
    local slot = SLOT_BY_KEY[key]
    local lootText = colorFor('lootText')
    if key == 'tainted' or key == 'corrupted' then
        return 'Loot of a {' .. slot.sample .. ', ' .. apartFrom(color, lootText) .. '} dragon: 3 gold coins.'
    end
    if key == 'crit' then
        local text = colorFor('logText')
        return '{A dragon loses , ' .. text .. '}{' .. slot.sample .. ', ' .. apartFrom(color, text) .. '}{ hitpoints due to your attack., ' .. text .. '}'
    end
    if key == 'logText' then
        return '{A dragon loses 154 hitpoints due to your attack., ' .. color .. '}'
    end
    if key == 'lootText' then
        -- The plain parts here take the label's color (showPickerColor).
        return 'Loot of a dragon: 3 gold coins, {' .. SLOT_BY_KEY.value1.sample .. ', ' .. apartFrom(colorFor('value1'), color) .. '}.'
    end
    return 'Loot of a dragon: 3 gold coins, {' .. slot.sample .. ', ' .. apartFrom(color, lootText) .. '}.'
end

-- The picker's warning line: too dark, or (apartFrom) shown a little
-- different next to the text color. nil = no warning.
local function pickerWarning(key, color)
    if not isReadable(color) then
        return tr('Hard to read'), tr('This color is very dark against the console background')
    end
    if key == 'lootText' or key == 'logText' then
        local count = 0
        for _, slot in ipairs(SLOTS) do
            local onLoot = slot.code or slot.group == 'names'
            local onLog = slot.group == 'names' or slot.key == 'crit'
            if (key == 'lootText' and onLoot) or (key == 'logText' and onLog) then
                if slot.code == nil or not slot.step or slot.step <= #state.steps then
                    if apartFrom(colorFor(slot.key), color) ~= colorFor(slot.key) then
                        count = count + 1
                    end
                end
            end
        end
        if count > 0 then
            return count .. ' ' .. tr('close colors adjusted'),
                tr('Colors that look too much like this text are shown a little lighter or darker in your lines, so they stay easy to spot. Your own colors are not changed.')
        end
        return nil
    end
    local base = (key == 'crit') and colorFor('logText') or colorFor('lootText')
    if SLOT_BY_KEY[key].group ~= 'text' and apartFrom(color, base) ~= color then
        return tr('Shown a little different'),
            tr('This color looks too much like your text color, so it is shown a little lighter or darker in your lines to stay easy to spot.')
    end
    return nil
end

local function showPickerColor(color, fromEdit)
    if not picker then
        return
    end
    pickerColor = color
    picker.current:setBackgroundColor(color)
    local warning, warningTip = pickerWarning(pickerKey, color)
    picker.readability:setVisible(warning ~= nil)
    if warning then
        picker.readability:setText(warning)
        picker.readability:setTooltip(warningTip)
    end
    -- The plain parts of a loot line take the label's color.
    picker.preview.previewText:setColor(pickerKey == 'lootText' and color or colorFor('lootText'))
    picker.preview.previewText:setColoredText(pickerPreview(pickerKey, color))

    -- Mark the box that holds this color, if any; clicking a box already did.
    local box = nil
    for _, b in ipairs(pickerBoxes) do
        if b.hex == color then
            box = b
            break
        end
    end
    if box then
        pickerGroup:selectWidget(box, true)
    elseif pickerGroup:getSelectedWidget() then
        pickerGroup:getSelectedWidget():setChecked(false)
        pickerGroup.selectedWidget = nil
    end

    if not fromEdit and normalize(picker.hexEdit:getText()) ~= color then
        pickerSettingText = true
        picker.hexEdit:setText(color)
        pickerSettingText = false
    end
end

local function addPickerBox(grid, color)
    local box = g_ui.createWidget('ColorBox', grid)
    box:setBackgroundColor(color)
    box:setTooltip(color)
    box.hex = color
    pickerGroup:addWidget(box)
    pickerBoxes[#pickerBoxes + 1] = box
end

function closePicker()
    if pickerGroup then
        pickerGroup:destroy()
        pickerGroup = nil
    end
    pickerBoxes = {}
    if picker then
        picker:destroy()
        picker = nil
    end
    pickerKey = nil
    pickerColor = nil
end

function confirmPicker()
    if pickerKey and pickerColor then
        setColor(pickerKey, pickerColor)
    end
    closePicker()
end

function pickDefault()
    if pickerKey then
        showPickerColor(PRESETS.standard.colors[pickerKey])
    end
end

function openPicker(key)
    local slot = SLOT_BY_KEY[key]
    if not slot then
        return
    end
    closePicker()

    picker = g_ui.loadUI('picker', g_ui.getRootWidget())
    picker:setText(tr('Color') .. ': ' .. tr(slotLabel(slot)))
    pickerKey = key
    pickerGroup = UIRadioGroup.create()

    for index = 0, 19 * 7 - 1 do
        addPickerBox(picker.outfitGrid, outfitColor(index))
    end
    for _, color in ipairs(setPalette()) do
        addPickerBox(picker.lootGrid, color)
    end
    for _, color in ipairs(state.recent) do
        addPickerBox(picker.recentGrid, color)
    end
    picker.recentEmpty:setVisible(#state.recent == 0)

    pickerGroup.onSelectionChange = function(_, selected)
        if selected then
            showPickerColor(selected.hex)
        end
    end

    picker.hexEdit.onTextChange = function(_, text)
        if pickerSettingText then
            return
        end
        local color = normalize(text)
        if color then
            showPickerColor(color, true)
        end
    end

    showPickerColor(colorFor(key))
    picker:raise()
    picker:focus()
end

-- Opens Settings on this page (the Colors button in the autoloot window
-- calls this).
function open()
    modules.client_options.openOptionsCategory('Interface', 'Colors')
end

-- Items ----------------------------------------------------------------------

local function pinCount()
    local count = 0
    for _ in pairs(state.pins) do
        count = count + 1
    end
    return count
end

local function rangeLabel(range)
    for _, slot in ipairs(SLOTS) do
        if slot.step == range then
            return slotLabel(slot)
        end
    end
    return ''
end

local function itemWidget(parent, data, tooltip, onClick)
    local widget = g_ui.createWidget('Item', parent)
    widget:setSize({ width = 32, height = 32 })
    widget:setItem(Item.create(data.clientId, 1))
    widget:setTooltip(tooltip)
    widget.onMouseRelease = function(_, _, button)
        if button ~= MouseLeftButton then
            return false
        end
        onClick()
        return true
    end
    return widget
end

local refreshItemsWindow

local function setItemsCount(text, isError)
    if itemsWindow then
        itemsWindow.count:setText(text)
        itemsWindow.count:setColor(isError and '#FF8060' or g_ui.getVariable('textDim'))
    end
end

local function changedPins()
    pinsByClientId = nil
    saveSettings()
    refreshRows()
    sendStepsSoon()
    refreshItemsWindow()
end

local function pinItem(serverId)
    if not itemsStep then
        return
    end
    if not state.pins[serverId] and pinCount() >= MAX_PINS then
        setItemsCount(tr('Full: at most') .. ' ' .. MAX_PINS .. ' ' .. tr('items'), true)
        return
    end
    state.pins[serverId] = itemsStep
    changedPins()
end

local function unpinItem(serverId)
    state.pins[serverId] = nil
    changedPins()
end

-- Puts everything a trader buys (item_values.lua traders) in the open range.
-- Items in another range move here; new ones stop at MAX_PINS.
function loadTrader()
    if not itemsWindow or not itemsStep then
        return
    end
    local option = itemsWindow.traderRow.traderBox:getCurrentOption()
    local trader = option and VALUES.traders[option.data]
    if not trader then
        return
    end
    local count = pinCount()
    local added, moved, full = 0, 0, 0
    for _, serverId in ipairs(trader.items) do
        local range = state.pins[serverId]
        if range ~= itemsStep then
            if range then
                state.pins[serverId] = itemsStep
                moved = moved + 1
            elseif count < MAX_PINS then
                state.pins[serverId] = itemsStep
                added = added + 1
                count = count + 1
            else
                full = full + 1
            end
        end
    end
    changedPins()
    local text = trader.name .. ': ' .. added .. ' ' .. tr('added')
    if moved > 0 then
        text = text .. ', ' .. moved .. ' ' .. tr('moved here')
    end
    if full > 0 then
        text = text .. ', ' .. full .. ' ' .. tr('did not fit')
    end
    setItemsCount(text, full > 0)
end

local function runItemSearch(text)
    if not itemsWindow then
        return
    end
    local panel = itemsWindow.resultsPanel
    panel:destroyChildren()
    text = (text or ''):trim():lower()
    local list = catalog()
    itemsWindow.resultsHint:setVisible(text:len() < 2)
    if text:len() < 2 or not list then
        return
    end
    local shown = 0
    for _, data in ipairs(list) do
        if shown >= ITEM_SEARCH_MAX then
            break
        end
        if data.name:lower():find(text, 1, true) then
            -- Walls, floors and furniture share the catalog; only things that
            -- can lie in a corpse are worth listing.
            local thing = Item.create(data.clientId, 1)
            if thing and thing:isPickupable() then
                local tooltip = data.name
                local range = state.pins[data.serverId]
                if range == itemsStep then
                    tooltip = tooltip .. '\n' .. tr('Already in this color')
                elseif range then
                    tooltip = tooltip .. '\n' .. tr('Now in') .. ' ' .. rangeLabel(range) .. ': ' .. tr('click to move it here')
                end
                itemWidget(panel, data, tooltip, function()
                    pinItem(data.serverId)
                end)
                shown = shown + 1
            end
        end
    end
end

refreshItemsWindow = function()
    if not itemsWindow then
        return
    end
    local _, byServerId = catalog()
    local panel = itemsWindow.pinnedPanel
    panel:destroyChildren()
    local count = 0
    for _, entry in ipairs(pinList()) do
        local serverId, range = entry[1], entry[2]
        if range == itemsStep then
            local data = byServerId[serverId]
            if data then
                itemWidget(panel, data, data.name .. '\n' .. tr('Click to remove'), function()
                    unpinItem(serverId)
                end)
                count = count + 1
            end
        end
    end
    itemsWindow.pinnedEmpty:setVisible(count == 0)
    itemsWindow.clearButton:setEnabled(count > 0)
    itemsWindow:setText(tr('Loot items') .. ': ' .. tr(rangeLabel(itemsStep)))
    setItemsCount(count .. ' ' .. tr('here') .. ', ' .. pinCount() .. ' / ' .. MAX_PINS .. ' ' .. tr('in all'))
    runItemSearch(itemsWindow.searchEdit:getText())
end

-- Empties the open range (after a trader was loaded into the wrong one, say).
function clearRange()
    if not itemsStep then
        return
    end
    for serverId, range in pairs(state.pins) do
        if range == itemsStep then
            state.pins[serverId] = nil
        end
    end
    changedPins()
end

-- Markers window --------------------------------------------------------------

local markersWindow = nil

local function refreshMarkerRow(row, key)
    local slot = SLOT_BY_KEY[key]
    local sample = slot.sample or ''
    local marker = markerFor(key)
    row.example:setColoredText('{' .. sample .. marker .. ', ' .. colorFor(key) .. '}')
end

function closeMarkers()
    if markersWindow then
        markersWindow:destroy()
        markersWindow = nil
    end
end

-- Every loot row in use, each with its marker in a box. Typing changes it at
-- once (a wrong one turns red and is not used); an empty box = no marker.
function openMarkers()
    closeMarkers()
    markersWindow = g_ui.loadUI('markers', g_ui.getRootWidget())
    local list = markersWindow.list
    local rowsByKey = {}
    for _, slot in ipairs(SLOTS) do
        if slot.code and (not slot.step or slot.step <= #state.steps) then
            local row = g_ui.createWidget('ColorsMarkerRow', list)
            -- 'Common' alone: '(under 500 gp)' does not fit here.
            row.caption:setText(tr(slot.key == 'common' and 'Common' or slotLabel(slot)))
            row.caption:setColor(colorFor(slot.key))
            row.edit:setText(markerText(slot.key))
            row.edit.onTextChange = function(_, text)
                if not validMarker(text) then
                    row.edit:setColor('#FF6060')
                    return
                end
                row.edit:setColor(g_ui.getVariable('textColor'))
                if text == defaultMarker(slot.key) then
                    state.markerText[slot.key] = nil
                else
                    state.markerText[slot.key] = text
                end
                saveSettings()
                refreshMarkerRow(row, slot.key)
                refreshPreview()
            end
            refreshMarkerRow(row, slot.key)
            rowsByKey[slot.key] = row
        end
    end
    markersWindow.defaultButton.onClick = function()
        state.markerText = {}
        saveSettings()
        for key, row in pairs(rowsByKey) do
            row.edit:setText(defaultMarker(key))
        end
        refreshPreview()
    end
    -- 24 px per row plus the window's top, hint and buttons.
    markersWindow:setHeight(#list:getChildren() * 24 + 120)
    markersWindow:raise()
    markersWindow:focus()
end

function closeItems()
    if itemsWindow then
        itemsWindow:destroy()
        itemsWindow = nil
    end
    itemsStep = nil
end

function openItems(range)
    if not catalog() then
        showStatus(tr('The item list comes from Autoloot, which is not loaded.'), true)
        return
    end
    closePicker()
    closeItems()
    itemsStep = range
    itemsWindow = g_ui.loadUI('items', g_ui.getRootWidget())
    itemsWindow.searchEdit.onTextChange = function(_, text)
        runItemSearch(text)
    end

    local traderBox = itemsWindow.traderRow.traderBox
    for index, trader in ipairs(VALUES.traders) do
        traderBox:addOption(trader.name .. ' (' .. #trader.items .. ')', index)
    end
    itemsWindow.traderRow.loadButton:setEnabled(#VALUES.traders > 0)

    refreshItemsWindow()
    itemsWindow:raise()
    itemsWindow:focus()
    itemsWindow.searchEdit:focus()
end

-- Chat colors ----------------------------------------------------------------

local chatStatusEvent = nil

local function showChatStatus(block, text)
    block.showRow.chatStatus:setText(text)
    removeEvent(chatStatusEvent)
    chatStatusEvent = scheduleEvent(function()
        chatStatusEvent = nil
        if block.showRow then
            block.showRow.chatStatus:setText('')
        end
    end, 3000)
end

-- The tag at `pos` ("{red}", "{/}"), or nil: its color ('' for the reset) and
-- where it ends.
local function chatTagAt(text, pos)
    local from, to, name = text:find('^{([%a/]+)}', pos)
    if not from then
        return nil
    end
    name = name:lower()
    if name == CHAT_RESET then
        return '', to
    end
    local color = CHAT_COLOR_BY_NAME[name]
    if color then
        return color, to
    end
    return nil
end

-- Whether a line holds at least one working tag.
function hasChatTags(text)
    if type(text) ~= 'string' or not text:find('{', 1, true) then
        return false
    end
    local pos = 1
    while true do
        local open = text:find('{', pos, true)
        if not open then
            return false
        end
        if chatTagAt(text, open) then
            return true
        end
        pos = open + 1
    end
end

-- The line with its working tags taken out ("{lol}" stays: it is not a tag).
function stripChatTags(text)
    if not hasChatTags(text) then
        return text
    end
    return (text:gsub('{([%a/]+)}', function(name)
        name = name:lower()
        if name == CHAT_RESET or CHAT_COLOR_BY_NAME[name] then
            return ''
        end
    end))
end

-- Whether tags are drawn for a line in this mode and channel: the Advertising
-- channels and Local Chat (say, whisper, yell), while the player has chat
-- colors on.
function chatColorsAllowed(mode, channelId)
    if not state.chatColors then
        return false
    end
    if channelId and CHAT_CHANNEL_IDS[channelId] then
        return true
    end
    return mode == MessageModes.Say or mode == MessageModes.Whisper or mode == MessageModes.Yell
end

-- Braces delimit setColoredText's markup, so a stray one the player typed
-- would split the line in the wrong place.
local function chatChunk(chunk, color)
    chunk = chunk:gsub('[{}]', '')
    if chunk == '' then
        return ''
    end
    return '{' .. chunk .. ', ' .. color .. '}'
end

-- The line (with its "Name [level]: " in front) as setColoredText markup:
-- each part in its tag's color, the rest in `baseColor`. Item links
-- (game_itemshare) inside a colored part keep working. Returns
-- { markup, links } like itemshare's buildChatMarkup, or nil without tags.
function chatMarkup(text, baseColor)
    if not hasChatTags(text) then
        return nil
    end
    baseColor = baseColor or '#FFFFFF'
    local itemshare = modules.game_itemshare
    local parts, links = {}, {}
    local color = baseColor

    local function addChunk(chunk)
        if chunk == '' then
            return
        end
        local share = itemshare and itemshare.buildChatMarkup and itemshare.buildChatMarkup(chunk, color)
        if share then
            parts[#parts + 1] = share.markup
            for shown, id in pairs(share.links or {}) do
                links[shown] = id
            end
        else
            parts[#parts + 1] = chatChunk(chunk, color)
        end
    end

    local pos, chunkStart = 1, 1
    while true do
        local open = text:find('{', pos, true)
        if not open then
            break
        end
        local tagColor, tagEnd = chatTagAt(text, open)
        if tagColor then
            addChunk(text:sub(chunkStart, open - 1))
            color = tagColor ~= '' and tagColor or baseColor
            chunkStart = tagEnd + 1
            pos = tagEnd + 1
        else
            pos = open + 1
        end
    end
    addChunk(text:sub(chunkStart))
    return { markup = table.concat(parts), links = links }
end

function setChatColors(on)
    if state.chatColors == on then
        return
    end
    state.chatColors = on
    saveSettings()
end

-- Module ---------------------------------------------------------------------

local function buildFrames(list)
    framesBlock = g_ui.createWidget('ColorsFrames', list)
    local box = framesBlock.typeRow.frameType
    for _, entry in ipairs(FRAME_TYPES) do
        box:addOption(tr(entry[1]), entry[2])
    end
    local current = modules.client_options.getOption('framesRarity') or 'frames'
    settingFrameType = true
    box:setCurrentOptionByData(current, true)
    settingFrameType = false
    box.onOptionChange = function(_, _, data)
        setFrameType(data)
    end

    local valueFrames = framesBlock.valueRow.valueFrames
    valueFrames:setChecked(state.valueFrames)
    valueFrames:setEnabled(current ~= 'none')
    valueFrames.onCheckChange = function(_, checked)
        setValueFrames(checked)
    end
end

-- The tag list: each name in its own color, so players see what they get.
-- Clicking one puts its tag at the end of the chat box.
local function buildChat(list)
    local block = g_ui.createWidget('ColorsChat', list)
    for _, entry in ipairs(CHAT_COLORS) do
        local tag = g_ui.createWidget('ColorsChatTag', block.helpRow.tagGrid)
        local text = '{' .. entry.name .. '}'
        tag.swatch:setBackgroundColor(entry.color)
        tag.tagName:setText(text)
        tag.tagName:setColor(entry.color)
        tag:setTooltip(tr('Click to put') .. ' ' .. text .. ' ' .. tr('in the chat box'))
        tag.onClick = function()
            local console = modules.game_console
            if console and console.insertTextEditText and console.insertTextEditText(text) then
                showChatStatus(block, text .. ' ' .. tr('is in the chat box.'))
            else
                showChatStatus(block, tr('The chat box is not open.'))
            end
        end
    end
    block.showRow.chatColors:setChecked(state.chatColors)
    block.showRow.chatColors.onCheckChange = function(_, checked)
        setChatColors(checked)
    end
end

-- Profiles ---------------------------------------------------------------------

local profilesBlock = nil
local profileStatusEvent = nil
local rebuildPage

local function showProfileStatus(text, isError)
    if not profilesBlock then
        return
    end
    local status = profilesBlock.nameRow.status
    status:setText(text)
    status:setColor(isError and '#FF8060' or g_ui.getVariable('textDim'))
    removeEvent(profileStatusEvent)
    profileStatusEvent = scheduleEvent(function()
        profileStatusEvent = nil
        if profilesBlock then
            profilesBlock.nameRow.status:setText('')
        end
    end, 4000)
end

local function characterName()
    if g_game.isOnline() then
        local name = g_game.getCharacterName()
        if name and name ~= '' then
            return name
        end
    end
    return nil
end

-- Loads a profile into the page. The one left keeps what it had (it is saved
-- on every change already).
function switchProfile(name)
    local entry = findProfile(name)
    if not entry or name == profiles.active then
        return
    end
    saveSettings()
    profiles.active = name
    resetState()
    loadSettings(entry.settings or {})
    pinsByClientId = nil
    saveSettings()
    if rebuildPage then
        rebuildPage()
    end
    sendStepsSoon()
    refreshFramesSoon()
end

-- A name: 1 to PROFILE_NAME_MAX letters, digits, spaces, - or _, with at
-- least one letter, not already used.
local function checkProfileName(name)
    name = (name or ''):trim()
    if name == '' or #name > PROFILE_NAME_MAX or not name:match('^[%w _%-]+$') or not name:match('%a') then
        return nil, tr('Use 1 to 20 letters, digits or spaces.')
    end
    if findProfile(name) then
        return nil, tr('That name is already used.')
    end
    return name
end

-- A new profile starts as a copy of what is on the page now.
function newProfile()
    if not profilesBlock then
        return
    end
    local name, problem = checkProfileName(profilesBlock.nameRow.nameEdit:getText())
    if not name then
        showProfileStatus(problem, true)
        return
    end
    saveSettings()
    profiles.list[#profiles.list + 1] = { name = name, settings = snapshot() }
    profiles.active = name
    saveSettings()
    rebuildPage()
    showProfileStatus(tr('Saved as') .. ' ' .. name .. '.')
end

function deleteProfile()
    local name = profiles.active
    if name == DEFAULT_PROFILE then
        return
    end
    local _, index = findProfile(name)
    table.remove(profiles.list, index)
    for character, profile in pairs(profiles.characters) do
        if profile == name then
            profiles.characters[character] = nil
        end
    end
    profiles.active = DEFAULT_PROFILE
    resetState()
    loadSettings(findProfile(DEFAULT_PROFILE).settings or {})
    pinsByClientId = nil
    saveSettings()
    rebuildPage()
    sendStepsSoon()
    refreshFramesSoon()
    showProfileStatus(name .. ' ' .. tr('deleted.'))
end

-- Tick: this character gets this profile at every login.
local function setCharacterProfile(on)
    local character = characterName()
    if not character then
        return
    end
    profiles.characters[character] = on and profiles.active or nil
    saveProfiles()
    g_settings.save()
end

local function onGameStartProfile()
    local character = characterName()
    local name = character and profiles.characters[character]
    if name and findProfile(name) and name ~= profiles.active then
        switchProfile(name)
    end
    if profilesBlock then
        rebuildPage()
    end
end

function buildProfiles(list)
    profilesBlock = g_ui.createWidget('ColorsProfiles', list)
    local box = profilesBlock.pickRow.profileBox
    for _, entry in ipairs(profiles.list) do
        box:addOption(entry.name, entry.name)
    end
    box:setCurrentOptionByData(profiles.active, true)
    box.onOptionChange = function(_, _, data)
        scheduleEvent(function()
            switchProfile(data)
        end, 1)
    end
    profilesBlock.pickRow.deleteProfile:setEnabled(profiles.active ~= DEFAULT_PROFILE)
    profilesBlock.pickRow.deleteProfile.onClick = deleteProfile
    profilesBlock.nameRow.saveNew.onClick = newProfile

    local character = characterName()
    local tick = profilesBlock.characterRow.useForCharacter
    tick:setText(character and (tr('Use this profile for') .. ' ' .. character) or tr('Log in to tie this profile to a character'))
    tick:setEnabled(character ~= nil)
    tick:setChecked(character ~= nil and profiles.characters[character] == profiles.active)
    tick.onCheckChange = function(_, checked)
        setCharacterProfile(checked)
    end
end

local function buildRows(list)
    for _, group in ipairs(GROUPS) do
        local header = g_ui.createWidget('ColorsHeader', list)
        header.title:setText(tr(group.title))
        header.alertTitle:setVisible(group.alerts == true)
        header.sparkleTitle:setVisible(group.alerts == true)
        for _, slot in ipairs(SLOTS) do
            if slot.group == group.id then
                local row = g_ui.createWidget('ColorsRow', list)
                row:setTooltip(tr(slot.tip or VALUE_TIP))
                row.swatch.onClick = function()
                    openPicker(slot.key)
                end
                row.change.onClick = function()
                    openPicker(slot.key)
                end
                if slot.noAlert then
                    row.alert:setVisible(false)
                    row.sparkle:setVisible(false)
                else
                    row.alert:setChecked(state.alerts[slot.key] == true)
                    row.alert.onCheckChange = function(_, checked)
                        setAlert(slot.key, checked)
                    end
                    if slot.noSparkle then
                        row.sparkle:setVisible(false)
                    else
                        row.sparkle:setChecked(state.sparkles[slot.key] == true)
                        row.sparkle.onCheckChange = function(_, checked)
                            setSparkle(slot.key, checked)
                        end
                    end
                end
                if slot.step then
                    row.items:setVisible(true)
                    row.items.onClick = function()
                        openItems(slot.step)
                    end
                    row.amount:setVisible(true)
                    row.amount.onTextChange = function(_, text)
                        onAmountChange(slot, text)
                    end
                end
                rows[slot.key] = row
            end
        end
        if group.id == 'value' then
            stepButtons = g_ui.createWidget('ColorsStepButtons', list)
            stepButtons.addStep.onClick = addStep
            stepButtons.removeStep.onClick = removeStep
            stepButtons.resetSteps.onClick = resetSteps
        end
    end

    buildFrames(list)
    buildChat(list)

    extras = g_ui.createWidget('ColorsExtras', list)
    extras.markersRow.editMarkers.onClick = openMarkers
    extras.markersRow.markers:setChecked(state.markers)
    extras.markersRow.markers.onCheckChange = function(_, checked)
        setMarkers(checked)
    end
    extras.onlyRow.onlyColored:setChecked(state.onlyColored)
    extras.onlyRow.onlyColored.onCheckChange = function(_, checked)
        setOnlyColored(checked)
    end
    extras.namesRow.colorNames:setChecked(state.colorNames)
    extras.namesRow.colorNames.onCheckChange = function(_, checked)
        setColorNames(checked)
    end
    extras.buttonsRow.copyCode.onClick = copyCode
    extras.buttonsRow.pasteCode.onClick = pasteCode

    buildProfiles(list)
end

rebuildPage = function()
    if not optionPanel then
        return
    end
    closePicker()
    closeItems()
    closeMarkers()
    optionPanel.rows:destroyChildren()
    rows = {}
    stepButtons = nil
    framesBlock = nil
    extras = nil
    profilesBlock = nil
    buildRows(optionPanel.rows)
    presetBox:setCurrentOptionByData(state.set, true)
    refreshAmounts()
    refreshRows()
end

function init()
    resetState()
    loadSettings()
    loadProfiles()

    -- Remember what the player looks at, for the "You see" line that answers.
    originalLook = g_game.look
    g_game.look = function(thing, ...)
        lastLook = { thing = thing, time = g_clock.millis() }
        return originalLook(thing, ...)
    end

    optionPanel = g_ui.loadUI('colors', modules.client_options.getPanel())
    presetBox = optionPanel.presetRow.presetBox

    for _, set in ipairs(PRESET_ORDER) do
        presetBox:addOption(tr(PRESETS[set].name), set)
    end
    presetBox:addOption(tr('Custom'), 'custom')
    presetBox:setCurrentOptionByData(state.set, true)
    presetBox.onOptionChange = function(_, _, data)
        selectSet(data)
    end

    buildRows(optionPanel.rows)
    refreshAmounts()
    refreshRows()

    -- Leaving the page (another category, or closing Settings) closes the
    -- picker and the items window with it, so neither floats over the game
    -- on its own.
    optionPanel.onVisibilityChange = function(_, visible)
        if not visible then
            closePicker()
            closeItems()
            closeMarkers()
        end
    end

    modules.client_options.addButton('Interface', 'Colors', optionPanel)

    connect(g_game, { onGameStart = sendSteps })
    connect(g_game, { onGameStart = onGameStartProfile, onGameEnd = onGameStartProfile })
    connect(Creature, { onAppear = onCreatureAppear })
    if g_game.isOnline() then
        paintMonsterNames()
        sendSteps()
        refreshFramesSoon()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = sendSteps })
    disconnect(g_game, { onGameStart = onGameStartProfile, onGameEnd = onGameStartProfile })
    disconnect(Creature, { onAppear = onCreatureAppear })
    if originalLook then
        g_game.look = originalLook
        originalLook = nil
    end
    lastLook = nil
    removeEvent(profileStatusEvent)
    profileStatusEvent = nil
    profilesBlock = nil
    removeEvent(sendEvent)
    removeEvent(statusEvent)
    removeEvent(framesEvent)
    removeEvent(chatStatusEvent)
    chatStatusEvent = nil
    sendEvent = nil
    statusEvent = nil
    framesEvent = nil
    closePicker()
    closeItems()
    closeMarkers()
    modules.client_options.removeButton('Interface', 'Colors')
    if optionPanel then
        optionPanel:destroy()
        optionPanel = nil
    end
    presetBox = nil
    framesBlock = nil
    extras = nil
    stepButtons = nil
    rows = {}
    pinsByClientId = nil
end
