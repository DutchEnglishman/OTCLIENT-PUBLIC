-- to-do
-- change to ItemsDatabase.setTier(UIitem) to UIitem:setTier()
ItemsDatabase = {}

ItemsDatabase.rarityColors = {
    ["yellow"] = TextColors.yellow,
    ["purple"] = TextColors.purple,
    ["blue"] = TextColors.blue,
    ["green"] = TextColors.green,
    ["grey"] = TextColors.grey,
}

-- Frame sprite-sheet column per rarity id, matching the server's
-- upgrade-system constants (data/upgrade_system/upgrade_system_const.lua):
--   0 = none (no frame)   1 = COMMON    2 = RARE
--   3 = EPIC              4 = LEGENDARY
-- Each frame is 32x32 in a 160x32 sheet. Rarity is per-item-INSTANCE and
-- arrives on the wire with each item (see GameItemRarity) -- it deliberately
-- is NOT derived from the item id, since two identical items can differ.
local rarityClips = {
    [1] = "32 0 32 32",  -- common    -> green
    [2] = "64 0 32 32",  -- rare      -> blue
    [3] = "96 0 32 32",  -- epic      -> purple
    [4] = "128 0 32 32", -- legendary -> yellow
}

local function getColorForValue(value)
    if value >= 1000000 then
        return "yellow"
    elseif value >= 100000 then
        return "purple"
    elseif value >= 10000 then
        return "blue"
    elseif value >= 1000 then
        return "green"
    elseif value >= 50 then
        return "grey"
    else
        return "white"
    end
end

function ItemsDatabase.getClipAndImagePath(item)
    if not item then
        return nil, nil, nil
    end

    local frameOption = modules.client_options.getOption('framesRarity')
    if frameOption == "none" then
        return nil, nil, nil
    end
    local imagePath = '/images/ui/item'
    local clip = nil

    if type(item) == "number" then
        item = g_things.getThingType(item, ThingCategoryItem)
    end

    if not item then
        return nil, nil, nil
    end

    if item then
        -- Per-instance rarity is the ONLY source. The upstream price-based
        -- path is deliberately not used as a fallback: getMeanPrice reads
        -- 12.x appearances.dat NPC prices, which don't exist in this
        -- client's 8.6 assets, so the only values it could ever return are
        -- three hardcoded coin prices -- which framed platinum and crystal
        -- coins regardless of any real rarity. An item with rarity 0 (or a
        -- bare ThingType, which has no instance data) gets no frame.
        local rarity = item.getRarity and item:getRarity() or 0
        clip = rarityClips[rarity]

        if clip then
            if frameOption == "frames" then
                imagePath = "/images/ui/rarity_frames"
            elseif frameOption == "corners" then
                imagePath = "/images/ui/containerslot-coloredges"
            end
        end
    end

    local clipObject = nil
    if clip then
        local x, y, w, h = clip:match("(%d+) (%d+) (%d+) (%d+)")
        clipObject = { x = tonumber(x), y = tonumber(y), width = tonumber(w), height = tonumber(h) }
    end

    return clip, imagePath, clipObject
end

-- Frames in the player's own colors (modules/game_colors). One frame image per
-- frame type, made from rarity_frames / containerslot-coloredges: the slot
-- art with the frame cut out of it (transparent where the frame is solid,
-- see-through where it glows). The widget's background color shows through
-- that hole, so the frame takes any color while staying under the item,
-- exactly where the old fixed-color frames were drawn.
local TINT_FRAMES = {
    frames = '/images/ui/item-frame-tint',
    corners = '/images/ui/item-corner-tint',
}
local TINT_CLIP = '0 0 32 32'
local NO_BACKGROUND = '#00000000'
local FRAME_SOURCES = {
    ['/images/ui/rarity_frames'] = true,
    ['/images/ui/containerslot-coloredges'] = true,
    ['/images/ui/item-frame-tint'] = true,
    ['/images/ui/item-corner-tint'] = true,
}

-- Whether frames come from the Colors page. Without it (module not loaded)
-- the old rarity-only frames below are used.
local function colorFrames()
    local colors = modules.game_colors
    return colors and colors.frameColor ~= nil
end

-- The frame image and color an item gets on the Colors page, or nil: frames
-- off, an empty slot, or an item its loot line would not color.
function ItemsDatabase.getFrame(item)
    if not item or type(item) == "number" or not colorFrames() then
        return nil
    end
    local image = TINT_FRAMES[modules.client_options.getOption('framesRarity')]
    if not image then
        return nil
    end
    local color = modules.game_colors.frameColor(item)
    if not color then
        return nil
    end
    return image, color
end

-- Paints the frame, or clears one left by a previous item back to
-- `emptySource` (only when one is showing, unless `always`).
local function applyColorFrame(widget, item, emptySource, always)
    local image, color = ItemsDatabase.getFrame(item)
    if image then
        widget:setImageSource(image)
        widget:setImageClip(TINT_CLIP)
        widget:setBackgroundColor(color)
    elseif always or FRAME_SOURCES[widget:getImageSource()] then
        widget:setImageClip(nil)
        widget:setImageSource(emptySource)
        widget:setBackgroundColor(NO_BACKGROUND)
    end
end

-- The equipment slots (game_inventory). Their item widget is a bare UIItem
-- with no image, so the slot's own art shows through: cleared back to
-- nothing rather than to /images/ui/item.
function ItemsDatabase.setInventoryFrame(widget, item)
    if not widget then
        return
    end
    if colorFrames() then
        applyColorFrame(widget, item, '', true)
        return
    end
    local rarityClip, rarityImage = ItemsDatabase.getClipAndImagePath(item)
    if rarityClip and rarityImage and rarityImage ~= '/images/ui/item' then
        widget:setImageClip(rarityClip)
        widget:setImageSource(rarityImage)
    else
        widget:setImageClip(nil)
        widget:setImageSource('')
    end
end

function ItemsDatabase.setRarityItem(widget, item, style)
    if not g_game.getFeature(GameColorizedLootValue) or not widget then
        return
    end

    -- Real items (containers) use the Colors page; the cyclopedia passes
    -- prices here, which keep the old path below.
    if type(item) ~= "number" and colorFrames() then
        applyColorFrame(widget, item, '/images/ui/item', false)
        if style then
            widget:setStyle(style)
        end
        return
    end

    local clip, imagePath = ItemsDatabase.getClipAndImagePath(item)

    if not imagePath then
        -- no frame applies (empty slot or frames disabled): clear a frame left by a previous item,
        -- but only if this widget is currently showing one, to avoid clobbering custom backgrounds
        local currentSource = widget:getImageSource()
        if currentSource == "/images/ui/rarity_frames" or currentSource == "/images/ui/containerslot-coloredges" then
            widget:setImageClip(nil)
            widget:setImageSource('/images/ui/item')
        end
        return
    end

    widget:setImageClip(clip)
    widget:setImageSource(imagePath)
    if style then
        widget:setStyle(style)
    end
end

function ItemsDatabase.getColorForRarity(rarity)
    return ItemsDatabase.rarityColors[rarity] or TextColors.white
end

function ItemsDatabase.setColorLootMessage(text)
    local colors = modules.game_colors
    -- "Only show colored items" (Colors page): the rest is counted, not listed.
    if colors and colors.filterLoot then
        text = colors.filterLoot(text)
    end
    local function coloringLootName(match)
        -- The server already colored this entry ({a sword, #4080FF}, OTSERV
        -- data/loot_colors/loot_colors.lua). Each code there is a category, and
        -- the player's Colors page (modules/game_colors) swaps in the color
        -- they picked for it. A code it does not know comes back unchanged;
        -- nil means the player switched colored names off, and the name is
        -- left plain.
        local entryName, code = match:match("^(.*), (#%x%x%x%x%x%x)$")
        if entryName then
            -- Optional marker after the name ("a fire sword [R]").
            if colors and colors.lootMarker then
                entryName = entryName .. colors.lootMarker(code)
            end
            if colors and colors.mapColor then
                code = colors.mapColor(code)
            end
            if not code then
                return entryName
            end
            return "{" .. entryName .. ", " .. code .. "}"
        end

        local id, itemName = match:match("(%d+)|(.+)")
        if not id or not itemName then
            -- If pattern doesn't match itemId|itemName format, return the original match with braces
            return "{" .. match .. "}"
        end

        local itemId = tonumber(id)
        if not itemId then
            return itemName or match
        end

        local thingType = g_things.getThingType(itemId, ThingCategoryItem)
        if not thingType then
            return itemName
        end

        local itemInfo = thingType:getMeanPrice()
        if itemInfo then
            local color = ItemsDatabase.getColorForRarity(getColorForValue(itemInfo))
            return "{" .. itemName .. ", " .. color .. "}"
        else
            return itemName
        end
    end
    local colored = text:gsub("{(.-)}", coloringLootName)
    -- "tainted" / "corrupted" in the monster's name, in the player's colors.
    if colors and colors.colorLootHead then
        colored = colors.colorLootHead(colored)
    end
    return colored
end

function ItemsDatabase.getTierClip(tier)
    local xOffset = (math.min(math.max(tier, 1), 10) - 1) * 9
    return {
        x = xOffset,
        y = 0,
        width = 10,
        height = 9
    }
end

function ItemsDatabase.setTier(widget, item, isSmall)
    if not g_game.getFeature(GameThingUpgradeClassification) or not widget or not widget.tier then
        return
    end
    if isSmall == nil then
        isSmall = true
    end
    local tier = type(item) == "number" and item or (item and item:getTier()) or 0
    if tier <= 0 then
        widget.tier:setVisible(false)
        return
    end
    local config
    if isSmall then
        local normalizedTier = math.min(math.max(tier, 1), 10)
        config = {
            xOffset = (normalizedTier - 1) * 9,
            width = 10,
            height = 9,
            size = "10 9",
            source = '/images/inventory/tiers-strip'
        }
    else
        local normalizedTier = math.min(math.max(tier, 1), 18)
        local xOffset = (normalizedTier - 1) * 18 + 1
        config = {
            xOffset = xOffset,
            width = 18,
            height = 16,
            size = "18 16",
            source = '/images/inventory/tiers-strip-big'
        }
    end

    widget.tier:setImageClip({
        x = config.xOffset,
        y = 0,
        width = config.width,
        height = config.height
    })
    widget.tier:setSize(config.size)
    widget.tier:setImageSource(config.source)
    widget.tier:setImageSize(config.size)
    widget.tier:setVisible(true)
end


