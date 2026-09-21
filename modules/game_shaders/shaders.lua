local HOTKEY = 'Ctrl+Y'
VARIANT_MONSTER_SHADER_CONFIG = {
    enabled = false,
    defaultShader = 'Outfit - Default',
    demonic = {
        skull = SkullWhite,
        name = 'Outfit - Demonic',
        frag = 'shaders/fragment/monster_tainted.frag'
    },
    diabolic = {
        skull = SkullRed,
        name = 'Outfit - Diabolic',
        frag = 'shaders/fragment/monster_corrupted.frag'
    }
}

local MAP_SHADERS = { {
    name = 'Map - Default',
    frag = nil
}, {
    name = 'Map - Fog',
    frag = 'shaders/fragment/fog.frag',
    tex1 = 'images/clouds'
}, {
    name = 'Map - Rain',
    frag = 'shaders/fragment/rain.frag'
}, {
    name = 'Map - Snow',
    frag = 'shaders/fragment/snow.frag',
    tex1 = 'images/snow'
}, {
    name = 'Map - Gray Scale',
    frag = 'shaders/fragment/grayscale.frag'
}, {
    name = 'Map - Bloom',
    frag = 'shaders/fragment/bloom.frag'
}, {
    name = 'Map - Sepia',
    frag = 'shaders/fragment/sepia.frag'
}, {
    name = 'Map - Pulse',
    frag = 'shaders/fragment/pulse.frag',
    drawViewportEdge = true
}, {
    name = 'Map - Old Tv',
    frag = 'shaders/fragment/oldtv.frag'
}, {
    name = 'Map - Party',
    frag = 'shaders/fragment/party.frag'
}, {
    name = 'Map - Radial Blur',
    frag = 'shaders/fragment/radialblur.frag',
    drawViewportEdge = true
}, {
    name = 'Map - Zomg',
    frag = 'shaders/fragment/zomg.frag',
    drawViewportEdge = true
}, {
    name = 'Map - Heat',
    frag = 'shaders/fragment/heat.frag',
    drawViewportEdge = true
}, {
    name = 'Map - Noise',
    frag = 'shaders/fragment/noise.frag'
}, {
    -- The brothers' tether, a tube drawn from body to body (attachedeffects.lua
    -- switches the map to it while a tether is held and back afterwards).
    name = 'Map - Tether',
    frag = 'shaders/fragment/tether.frag'
}, {
    -- Madareth's chains, iron links run from his body to each of his spikes.
    -- Switched in and out by attachedeffects.lua the way the tether is, and for
    -- the same reason: a line between two moving points cannot be built out of
    -- tile effects.
    name = 'Map - Hook Chain',
    frag = 'shaders/fragment/hook_chain.frag'
}, {
    -- Steady wind: litter blown across the world, purely additive over the map.
    -- One of the atmospheres below.
    name = 'Map - Wind',
    frag = 'shaders/fragment/wind.frag'
}, {
    -- Drifting ash and embers, with the colour washed out of the map behind it.
    -- One of the atmospheres below.
    name = 'Map - Burn',
    frag = 'shaders/fragment/burn.frag'
} }

-- Map atmospheres (OTSERV data/scripts/talkactions/atmosphere.lua, /wind and
-- /burn) arrive here as the key of the one to show, or 'off'. One channel for all
-- of them rather than an opcode each, because the map has ONE shader slot: showing
-- an atmosphere is always replacing whatever was there, never stacking.
--
-- 'off' goes back to NO map shader rather than to whatever the player had before:
-- this side cannot read back which shader is on. PainterShaderProgram is
-- registered as a Lua class with only addMultiTexture bound off it and has no
-- getName in C++ at all (luafunctions.cpp), so map:getShader() answers an object
-- that can say nothing about itself -- which is why the tether's own
-- `current.getName and current:getName()` always falls through to its default.
--
-- 'Map - Default' carries no frag, so registerShader skips it and it is never
-- registered; ShaderManager::getShader answers nullptr for a name it does not
-- know, and MapView::setShader takes that as "no shader". That is the same route
-- attachShaders uses with 'Default'.
--
-- An atmosphere ROLLS IN rather than snapping on: this side ramps 0..1 into the
-- shader's u_Anchor0.x (UIMap:setShaderPoint, raw floats in an anchor slot) and
-- each shader lerps its whole effect from the untouched map by it.
--
-- MapView's own fade arguments are NOT what does this. They drive
-- g_painter->setOpacity on the map draw itself (mapview.cpp), which fades the
-- WORLD to black and back -- a blackout, not an effect ramp.
--
-- Swapping straight between two atmospheres would cut, so a change fades the old
-- one out first and only then puts the new shader on the map, at 0, to fade in.
local ATMOSPHERE_OPCODE = 76
local ATMOSPHERE_SHADERS = {
    wind = 'Map - Wind',
    burn = 'Map - Burn'
}
local ATMOSPHERE_FADE_MS = 3000
local ATMOSPHERE_STEP_MS = 40

local atmosphere = nil      -- the key the server last asked for
local atmosphereShown = nil -- the key whose shader is actually on the map
local atmosphereFade = 0.0
local atmosphereEvent = nil

local function pushAtmosphereFade()
    local map = modules.game_interface.getMapPanel()
    if map then
        map:setShaderPoint(0, atmosphereFade, 1.0)
    end
end

local function showAtmosphereShader(key)
    local map = modules.game_interface.getMapPanel()
    if not map then
        return
    end
    atmosphereShown = key
    map:setShader(key and ATMOSPHERE_SHADERS[key] or 'Map - Default', 0, 0)
end

local function atmosphereStep()
    atmosphereEvent = nil

    -- No map panel means nothing to drive, and rescheduling from here would spin
    -- every 40 ms for as long as the player stayed logged out. A game start
    -- resets and restarts the ramp.
    if not modules.game_interface.getMapPanel() then
        return
    end

    -- Heading for full while the shader on the map is the one wanted, and for
    -- nothing while it is on its way out.
    local target = (atmosphereShown ~= nil and atmosphereShown == atmosphere) and 1.0 or 0.0
    local step = ATMOSPHERE_STEP_MS / ATMOSPHERE_FADE_MS

    if atmosphereFade < target then
        atmosphereFade = math.min(target, atmosphereFade + step)
    else
        atmosphereFade = math.max(target, atmosphereFade - step)
    end
    pushAtmosphereFade()

    if atmosphereFade ~= target then
        atmosphereEvent = scheduleEvent(atmosphereStep, ATMOSPHERE_STEP_MS)
        return
    end

    if target == 0.0 then
        -- Faded out: either take the shader off, or put the next one on and let
        -- the next tick start raising it.
        showAtmosphereShader(atmosphere)
        if atmosphere then
            atmosphereEvent = scheduleEvent(atmosphereStep, ATMOSPHERE_STEP_MS)
        end
    end
end

local function setAtmosphere(key)
    if key == atmosphere then
        return
    end
    atmosphere = key

    -- Nothing showing: put the shader on at once, dark, and ramp it up. Anything
    -- else is handled by the step -- it fades out first, then swaps.
    if atmosphereShown == nil and key ~= nil then
        atmosphereFade = 0.0
        showAtmosphereShader(key)
        pushAtmosphereFade()
    end

    if not atmosphereEvent then
        atmosphereEvent = scheduleEvent(atmosphereStep, ATMOSPHERE_STEP_MS)
    end
end

local function resetAtmosphere()
    if atmosphereEvent then
        removeEvent(atmosphereEvent)
        atmosphereEvent = nil
    end
    atmosphere = nil
    atmosphereShown = nil
    atmosphereFade = 0.0
end

local function onAtmosphereOpcode(protocol, opcode, buffer)
    -- Anything this build does not know about reads as 'off', so an older client
    -- clears rather than sticking on whatever it was showing.
    setAtmosphere(ATMOSPHERE_SHADERS[buffer] and buffer or nil)
end

local OUTFIT_SHADERS = {
    {
        name = 'Outfit - Default',
        frag = nil
    },
    {
        name = 'Outfit - Rainbow',
        frag = 'shaders/fragment/party.frag'
    },
    {
        name = 'Outfit - Ghost',
        frag = 'shaders/fragment/radialblur.frag',
        drawColor = false
    },
    {
        name = 'Outfit - Jelly',
        frag = 'shaders/fragment/heat.frag'
    },
    {
        name = 'Outfit - Fragmented',
        frag = 'shaders/fragment/noise.frag'
    },
    {
        name = 'Outfit - cyclopedia-black',
        frag = 'shaders/fragment/cyclopedia.frag'
    },
    {
        name = 'Outfit - Outline',
        useFramebuffer = true,
        frag = 'shaders/fragment/outline.frag'
    },
    {
        name = 'Outfit - ForgeDonor',
        useFramebuffer = true,
        frag = 'shaders/fragment/forge_donor.frag'
    },
    {
        name = 'Outfit - ForgeSuccess',
        useFramebuffer = true,
        frag = 'shaders/fragment/forge_success.frag'
    },
    {
        name = 'Outfit - ForgeFailed',
        useFramebuffer = true,
        frag = 'shaders/fragment/forge_failed.frag'
    },
    {
        name = 'Outfit - 3Line',
        vert = 'shaders/vertex/outfit_3line_vertex.frag',
        frag = 'shaders/fragment/outfit_3line_fragment.frag'
    },
    {
        name = 'Outfit - Circle',
        vert = 'shaders/vertex/outfit_circle_vertex.frag',
        frag = 'shaders/fragment/outfit_circle_fragment.frag'
    },
    {
        name = 'Outfit - Default Custom',
        vert = 'shaders/vertex/outfit_default_vertex.frag',
        frag = 'shaders/fragment/outfit_default_fragment.frag'
    },
    {
        name = 'Outfit - Line',
        vert = 'shaders/vertex/outfit_line_vertex.frag',
        frag = 'shaders/fragment/outfit_line_fragment.frag'
    },
    {
        name = 'Outfit - Rainbow Custom',
        vert = 'shaders/vertex/outfit_rainbow_vertex.frag',
        frag = 'shaders/fragment/outfit_rainbow_fragment.frag'
    },
    {
        name = 'Outfit - Shimmering',
        vert = 'shaders/vertex/outfit_shimmering_vertex.frag',
        frag = 'shaders/fragment/outfit_shimmering_fragment.frag'
    },
    {
        name = 'Outfit - Shine',
        vert = 'shaders/vertex/outfit_shine_vertex.frag',
        frag = 'shaders/fragment/outfit_shine_fragment.frag'
    },
    {
        name = 'Outfit - Blood',
        vert = 'shaders/vertex/outfit_blood_vertex.frag',
        frag = 'shaders/fragment/outfit_blood_fragment.frag',
        tex1 = 'images/blood'
    },
    {
        name = 'Outfit - Blue Energy',
        vert = 'shaders/vertex/outfit_blue_energy_vertex.frag',
        frag = 'shaders/fragment/outfit_blue_energy_fragment.frag',
        tex1 = 'images/blueenergy'
    },
    {
        name = 'Outfit - Gold',
        vert = 'shaders/vertex/outfit_gold_vertex.frag',
        frag = 'shaders/fragment/outfit_gold_fragment.frag',
        tex1 = 'images/gold'
    },
    {
        name = 'Outfit - Ice',
        vert = 'shaders/vertex/outfit_ice_vertex.frag',
        frag = 'shaders/fragment/outfit_ice_fragment.frag',
        tex1 = 'images/ice'
    },
    {
        name = 'Outfit - Stars',
        vert = 'shaders/vertex/outfit_stars_vertex.frag',
        frag = 'shaders/fragment/outfit_stars_fragment.frag',
        tex1 = 'images/stars'
    }, 
    {
        name = 'Monster - Corrupted',
        frag = 'shaders/fragment/monster_corrupted.frag'
    },
    -- Worn only for the few seconds Madareth's Bloodlust lasts. Put on and
    -- taken off by name from game_attachedeffects, on the server's word.
    -- Registered here rather than in VARIANT_MONSTER_SHADER_CONFIG because it
    -- is a boss skill, not a variant: nothing wears it permanently and no
    -- skull selects it.
    {
        name = 'Monster - Bloodlust',
        frag = 'shaders/fragment/bloodlust.frag'
    } }


if VARIANT_MONSTER_SHADER_CONFIG.enabled then
    table.insert(OUTFIT_SHADERS, {
        name = VARIANT_MONSTER_SHADER_CONFIG.demonic.name,
        useFramebuffer = true,
        frag = VARIANT_MONSTER_SHADER_CONFIG.demonic.frag
    })
    table.insert(OUTFIT_SHADERS, {
        name = VARIANT_MONSTER_SHADER_CONFIG.diabolic.name,
        useFramebuffer = true,
        frag = VARIANT_MONSTER_SHADER_CONFIG.diabolic.frag
    })
end

local MOUNT_SHADERS = { {
    name = 'Mount - Default',
    frag = nil
}, {
    name = 'Mount - Rainbow',
    frag = 'shaders/fragment/party.frag'
} }

-- Worn by a floor item whose upgrade-system rarity is Rare or better, put on
-- and taken off by game_attachedeffects on the server's word (opcode 72) --
-- the same arrangement as Monster - Bloodlust above, and for the same reason:
-- nothing picks these from the combo boxes, so there is no Default entry.
-- One shader per rarity because the colour has to be baked in: the only
-- per-item uniform the draw path offers is u_ItemId, and Item::internalDraw
-- leaves it unset.
local ITEM_SHADERS = { {
    name = 'Item - Rarity Shine Rare',
    frag = 'shaders/fragment/rarity_shine_rare.frag'
}, {
    name = 'Item - Rarity Shine Epic',
    frag = 'shaders/fragment/rarity_shine_epic.frag'
}, {
    name = 'Item - Rarity Shine Legendary',
    frag = 'shaders/fragment/rarity_shine_legendary.frag'
} }

-- Text shaders for improved readability and visual effects
-- All shaders use multi-sample circular sampling for smooth outlines
local TEXT_SHADERS = { {
    name = 'Text - Default',
    frag = nil -- No shader, standard text rendering
}, {
    name = 'Text - Gold Outline',
    frag = 'shaders/fragment/text_golden_shadow_bold_fragment.frag' -- Smooth gold (#ee8413) outline
}, {
    name = 'Text - Black Outline',
    frag = 'shaders/fragment/text_black_outline.frag' -- Classic black outline, max readability
}, {
    name = 'Text - Glow',
    frag = 'shaders/fragment/text_glow.frag' -- Soft glow effect (higher GPU cost)
} }

local function attachShaders()
    local map = modules.game_interface.getMapPanel()
    map:setShader('Default')

    local player = g_game.getLocalPlayer()
    if player then
        player:setShader('Default')
        player:setMountShader('Default')
    end
end

local variantShaderCreatures = {}

local function updateVariantMonsterShader(creature, skullId)
    if not creature:isMonster() then
        return
    end

    local config = VARIANT_MONSTER_SHADER_CONFIG
    local shader
    if config.enabled and skullId == config.demonic.skull then
        shader = config.demonic.name
    elseif config.enabled and skullId == config.diabolic.skull then
        shader = config.diabolic.name
    end

    local creatureId = creature:getId()
    if shader then
        creature:setShader(shader)
        variantShaderCreatures[creatureId] = true
    elseif variantShaderCreatures[creatureId] then
        creature:setShader(config.defaultShader)
        variantShaderCreatures[creatureId] = nil
    end
end

local function updateVisibleVariantMonsterShaders()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    for _, creature in pairs(g_map.getSpectators(player:getPosition(), false, true) or {}) do
        updateVariantMonsterShader(creature, creature:getSkull())
    end
end

local registerShader = function(opts, method)
    local fragmentShaderPath = resolvepath(opts.frag)

    if fragmentShaderPath == nil then
        return
    end

    if opts.vert then
        local vertexShaderPath = resolvepath(opts.vert)

        if vertexShaderPath == nil then
            print(
                '[SHADER ERROR] Vertex shader not found: ' ..
                tostring(opts.vert)
            )
            return
        end

        g_shaders.createVertexFragmentShader(
            opts.name,
            opts.vert,
            opts.frag,
            opts.useFramebuffer or false
        )
    else
        g_shaders.createFragmentShader(
            opts.name,
            opts.frag,
            opts.useFramebuffer or false
        )
    end

    if opts.tex1 then
        g_shaders.addMultiTexture(opts.name, opts.tex1)
    end

    if opts.tex2 then
        g_shaders.addMultiTexture(opts.name, opts.tex2)
    end

    g_shaders[method](opts.name)
end

ShaderController = Controller:new()

function ShaderController:getMonsterShaderName(creature)
    if not creature or not creature:isMonster() then
        return nil
    end

    local monsterName = creature:getName()
    if not monsterName or monsterName == '' then
        return nil
    end

    local normalizedName = monsterName:lower()

    if normalizedName:find('^tainted ') then
        return 'Outfit - Shimmering'
    end

    if normalizedName:find('^corrupted ') then
        return 'Outfit - Stars'
    end

    return nil
end

function ShaderController:applyMonsterShader(creature)
    local shaderName = self:getMonsterShaderName(creature)
    if not shaderName then
        return
    end

    creature:setShader(shaderName)
end

function ShaderController:updateVisibleMonsterShaders()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local spectators = g_map.getSpectators(
        player:getPosition(),
        false,
        true
    ) or {}

    for _, creature in pairs(spectators) do
        self:applyMonsterShader(creature)
    end
end

function onMonsterShaderCreatureAppear(creature)
    ShaderController:onCreatureAppear(creature)
end

function ShaderController:onInit()
    for _, opts in pairs(MAP_SHADERS) do
        registerShader(opts, 'setupMapShader')
    end

    for _, opts in pairs(OUTFIT_SHADERS) do
        registerShader(opts, 'setupOutfitShader')
    end

    for _, opts in pairs(MOUNT_SHADERS) do
        registerShader(opts, 'setupMountShader')
    end

    for _, opts in pairs(ITEM_SHADERS) do
        registerShader(opts, 'setupItemShader')
    end

    for _, opts in pairs(TEXT_SHADERS) do
        registerShader(opts, 'setupTextShader')
    end

    connect(Creature, {
        onAppear = onMonsterShaderCreatureAppear
    })
    
    ProtocolGame.registerExtendedOpcode(ATMOSPHERE_OPCODE, onAtmosphereOpcode)

    Keybind.new('Windows', 'show/hide Shader Windows', HOTKEY, '')
    Keybind.bind('Windows', 'show/hide Shader Windows', {
        {
            type = KEY_DOWN,
            callback = function()
                if ShaderController.ui then
                    ShaderController:unloadHtml()
                else
                    ShaderController:open()
                end
            end,
        }
    })
end

function ShaderController:onTerminate()
    disconnect(Creature, {
        onAppear = onMonsterShaderCreatureAppear
    })
    ProtocolGame.unregisterExtendedOpcode(ATMOSPHERE_OPCODE)
    resetAtmosphere()
    variantShaderCreatures = {}
    g_shaders.clear()
    Keybind.delete('Windows', 'show/hide Shader Windows')
end

function ShaderController:onGameStart()
    -- attachShaders puts the map back to no shader, so no atmosphere survives the
    -- end of the last game; any ramp still running has to go with it.
    resetAtmosphere()
    attachShaders()

    scheduleEvent(function()
        ShaderController:updateVisibleMonsterShaders()
    end, 100)
end

function ShaderController:onCreatureAppear(creature)
    scheduleEvent(function()
        if creature then
            ShaderController:applyMonsterShader(creature)
        end
    end, 50)
end

function ShaderController:onMapComboBoxChange(event)
    local map = modules.game_interface.getMapPanel()
    map:setShader(event.text)

    local data = event.target:getCurrentOption().data
    map:setDrawViewportEdge(data.drawViewportEdge == true)
end

function ShaderController:onOutfitComboBoxChange(event)
    local player = g_game.getLocalPlayer()
    if player then
        player:setShader(event.text)
        local data = event.target:getCurrentOption().data
        player:setDrawOutfitColor(data.drawColor ~= false)
    end
end

function ShaderController:onMountComboBoxChange(event)
    local player = g_game.getLocalPlayer()
    if player then
        player:setMountShader(event.text)
    end
end

function ShaderController:open()
    self:loadHtml('shaders.html', modules.game_interface.getMapPanel())

    for _, opts in pairs(MAP_SHADERS) do
        self.ui.mapComboBox:addOption(opts.name, opts)
    end

    for _, opts in pairs(OUTFIT_SHADERS) do
        self.ui.outfitComboBox:addOption(opts.name, opts)
    end

    for _, opts in pairs(MOUNT_SHADERS) do
        self.ui.mountComboBox:addOption(opts.name, opts)
    end
    for _, opts in pairs(TEXT_SHADERS) do
        self.ui.textComboBox:addOption(opts.name, opts)
    end
end

function ShaderController:onTextComboBoxChange(event)
    -- Apply text shader to local player's name
    -- This affects how the player's name is rendered above their character
    local player = g_game.getLocalPlayer()
    if player then
        -- If using widget-based name rendering
        local infoWidget = player:getWidgetInformation()
        if infoWidget then
            infoWidget:setShader(event.text)
        end
        -- Apply to engine-level name rendering (requires C++ support)
        if player.setNameShader then
            player:setNameShader(event.text)
        end
    end
end

