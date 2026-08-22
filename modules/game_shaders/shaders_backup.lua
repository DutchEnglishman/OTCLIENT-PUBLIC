local HOTKEY = 'Ctrl+Y'
VARIANT_MONSTER_SHADER_CONFIG = {
    enabled = false,
    defaultShader = 'Outfit - Default',
    demonic = {
        skull = SkullWhite,
        name = 'Outfit - Demonic',
        frag = 'shaders/fragment/tainted.frag'
    },
    diabolic = {
        skull = SkullRed,
        name = 'Outfit - Diabolic',
        frag = 'shaders/fragment/corrupted.frag'
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
} }

local OUTFIT_SHADERS = { {
    name = 'Outfit - Default',
    frag = nil
}, {
    name = 'Outfit - Rainbow',
    frag = 'shaders/fragment/party.frag'
}, {
    name = 'Outfit - Ghost',
    frag = 'shaders/fragment/radialblur.frag',
    drawColor = false
}, {
    name = 'Outfit - Jelly',
    frag = 'shaders/fragment/heat.frag'
}, {
    name = 'Outfit - Fragmented',
    frag = 'shaders/fragment/noise.frag'
}, {
    name = 'Outfit - cyclopedia-black',
    frag = 'shaders/fragment/cyclopedia.frag'
}, {
    name = 'Outfit - Outline',
    useFramebuffer = true,
    frag = 'shaders/fragment/outline.frag'
}, {
    name = 'Outfit - ForgeDonor',
    useFramebuffer = true,
    frag = 'shaders/fragment/forge_donor.frag'
}, {
    name = 'Outfit - ForgeSuccess',
    useFramebuffer = true,
    frag = 'shaders/fragment/forge_success.frag'
}, {
    name = 'Outfit - ForgeFailed',
    useFramebuffer = true,
    frag = 'shaders/fragment/forge_failed.frag'
},{
    name = 'Outfit - Shine',
    vert = 'shaders/vertex/outfit_shine_vertex.frag',
    frag = 'shaders/fragment/outfit_shine_fragment.frag'
},
{
    name = 'Outfit - Stars',
    vert = 'shaders/vertex/outfit_stars_vertex.frag',
    frag = 'shaders/fragment/outfit_stars_fragment.frag'
},
{
    name = 'Outfit - Gold',
    vert = 'shaders/vertex/outfit_gold_vertex.frag',
    frag = 'shaders/fragment/outfit_gold_fragment.frag'
},
{
    name = 'Outfit - Ice',
    vert = 'shaders/vertex/outfit_ice_vertex.frag',
    frag = 'shaders/fragment/outfit_ice_fragment.frag'
},
{
    name = 'Monster - Tainted',
    frag = 'shaders/fragment/monster_tainted.frag'
},
{
    name = 'Monster - Corrupted',
    frag = 'shaders/fragment/monster_corrupted.frag'
},
}


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
        g_shaders.addMultiTexture(
            opts.name,
            opts.tex1
        )
    end

    if opts.tex2 then
        g_shaders.addMultiTexture(
            opts.name,
            opts.tex2
        )
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
        return 'Outfit - Shine'
    end

    if normalizedName:find('^corrupted ') then
        return 'Outfit - Ice'
    end

    return nil
end

function ShaderController:applyMonsterShader(creature)
    local shaderName = self:getMonsterShaderName(creature)
    if not shaderName then
        return
    end

    local shader = g_shaders.getShader(shaderName)

    print(
        '[SHADER DEBUG] creature=' ..
        creature:getName() ..
        ' shader=' ..
        shaderName ..
        ' exists=' ..
        tostring(shader ~= nil)
    )

    if not shader then
        print('[SHADER ERROR] Shader is not registered: ' .. shaderName)
        return
    end

    creature:setShader(shaderName)

    print(
        '[SHADER DEBUG] setShader executed for ' ..
        creature:getName()
    )
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

    for _, opts in pairs(TEXT_SHADERS) do
        registerShader(opts, 'setupTextShader')
    end

    connect(Creature, {
        onAppear = onMonsterShaderCreatureAppear
    })
    
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
    variantShaderCreatures = {}
    g_shaders.clear()
    Keybind.delete('Windows', 'show/hide Shader Windows')
end

function ShaderController:onGameStart()
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

