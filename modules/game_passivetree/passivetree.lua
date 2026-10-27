-- Passive skill tree window (Ctrl+Shift+P). Talks JSON to the server over
-- extended opcode 83 (OTSERV data/scripts/passive_tree/passive_tree.lua): it
-- asks for the tree once per session, the state on every open, and sends the
-- whole allocation on Confirm. Picks are only held here until Confirm, and are
-- thrown away when the window closes; the server checks every confirmed build
-- itself, so nothing here is trusted.
PassiveTreeUI = {}

local OPCODE = 83
local IMAGES = '/game_passivetree/images/'
local NODE_SIZE = { small = 22, notable = 34, keystone = 48, start = 56 }
local MIN_ZOOM, MAX_ZOOM, DEFAULT_ZOOM = 0.12, 1.2, 0.45
local ZOOM_STEP = 1.15

local NODE_COLORS = {
    allocated = '#e8c060',
    pending = '#7fd67f',
    available = '#d8dce2',
    locked = '#4a4d53',
    otherStart = '#6a6d73',
}
-- A node that cannot be taken yet shows its icon faded, so the lit path reads
-- at a glance.
local ICON_OPACITY = {
    allocated = 1,
    pending = 1,
    available = 0.85,
    locked = 0.35,
    otherStart = 0.5,
}
local EDGE_COLORS = {
    allocated = '#c9a24a',
    pending = '#6fbf6f',
    available = '#5a5d63',
    locked = '#26282c',
}

-- Bare globals for the otui's @onClick/@onEscape, which resolve only to a
-- module's top-level names (the same reason game_dungeons carries them).
function toggle()
    PassiveTreeUI.toggle()
end

function confirm()
    PassiveTreeUI.confirm()
end

function undo()
    PassiveTreeUI.undo()
end

function reset()
    PassiveTreeUI.reset()
end

local window, canvas
local tree
local state
local pending = {}
local view = { x = 0, y = 0, zoom = DEFAULT_ZOOM }
local nodeWidgets, edgeWidgets = {}, {}
local treeRequested = false
local centerOnState = false
local drag
local resetBox

local function gold(amount)
    local text = tostring(amount)
    while true do
        local grouped, count = text:gsub('^(%d+)(%d%d%d)', '%1,%2')
        text = grouped
        if count == 0 then
            return text
        end
    end
end

local function send(message)
    if not g_game.isOnline() then
        return
    end
    local protocol = g_game.getProtocolGame()
    if protocol then
        protocol:sendExtendedOpcode(OPCODE, json.encode(message))
    end
end

local function isTaken(id)
    return (state and state.allocatedSet[id]) or pending[id] or false
end

local function pendingCount()
    local count = 0
    for _ in pairs(pending) do
        count = count + 1
    end
    return count
end

local function available()
    if not state then
        return 0
    end
    return state.points - #state.allocated - pendingCount()
end

local function touchesTaken(node)
    for _, other in ipairs(node.links) do
        if other == state.start or isTaken(other) then
            return true
        end
    end
    return false
end

local function canTake(id)
    local node = tree.nodes[id]
    return node and node.kind ~= 'start' and not isTaken(id) and available() > 0 and touchesTaken(node)
end

-- Un-picking a node drops every pick that no longer reaches the start.
local function prunePending()
    local seen = { [state.start] = true }
    local queue, head = { state.start }, 1
    while queue[head] do
        local id = queue[head]
        head = head + 1
        for _, other in ipairs(tree.nodes[id].links) do
            if not seen[other] and isTaken(other) then
                seen[other] = true
                queue[#queue + 1] = other
            end
        end
    end
    for id in pairs(pending) do
        if not seen[id] then
            pending[id] = nil
        end
    end
end

local function nodeStatus(node)
    if node.kind == 'start' then
        return node.id == state.start and 'allocated' or 'otherStart'
    end
    if state.allocatedSet[node.id] then
        return 'allocated'
    end
    if pending[node.id] then
        return 'pending'
    end
    if available() > 0 and touchesTaken(node) then
        return 'available'
    end
    return 'locked'
end

local function edgeStatus(a, b)
    local sa, sb = nodeStatus(a), nodeStatus(b)
    local function taken(status)
        return status == 'allocated' or status == 'pending'
    end
    if taken(sa) and taken(sb) then
        return (sa == 'pending' or sb == 'pending') and 'pending' or 'allocated'
    end
    if (taken(sa) and sb == 'available') or (taken(sb) and sa == 'available') then
        return 'available'
    end
    return 'locked'
end

local function tooltipFor(node, status)
    local lines = { node.name }
    if node.kind == 'keystone' then
        lines[#lines + 1] = '(Keystone)'
    elseif node.kind == 'notable' then
        lines[#lines + 1] = '(Notable)'
    end
    for _, line in ipairs(node.lines) do
        lines[#lines + 1] = line
    end
    if status == 'available' then
        lines[#lines + 1] = 'Click to pick.'
    elseif status == 'pending' then
        lines[#lines + 1] = 'Picked - press Confirm to keep it, click to drop it.'
    elseif status == 'locked' and node.kind ~= 'start' then
        lines[#lines + 1] = available() > 0 and 'Not connected to your tree yet.' or 'No passive points left.'
    end
    return table.concat(lines, '\n')
end

local function refresh()
    if not window or not tree or not state then
        return
    end

    for id, widget in pairs(nodeWidgets) do
        local node = tree.nodes[id]
        local status = nodeStatus(node)
        widget:setImageColor(NODE_COLORS[status])
        widget:setTooltip(tooltipFor(node, status))
        if widget.icon then
            widget.icon:setOpacity(ICON_OPACITY[status])
        end
    end
    for _, entry in ipairs(edgeWidgets) do
        entry.widget:setBackgroundColor(EDGE_COLORS[edgeStatus(tree.nodes[entry.a], tree.nodes[entry.b])])
    end

    local free = available()
    local label = window:getChildById('pointsLabel')
    if free < 0 then
        label:setText(string.format('Passive points: %d spent, %d owned (%d over after losing a level)',
            #state.allocated, state.points, -free))
        label:setColor('#d07070')
    else
        label:setText(string.format('Passive points: %d available (%d of %d spent%s)', free,
            #state.allocated, state.points, pendingCount() > 0 and (', ' .. pendingCount() .. ' picked') or ''))
        label:setColor('#eef2f6')
    end

    window:getChildById('confirmButton'):setEnabled(state.enabled and pendingCount() > 0)
    window:getChildById('cancelButton'):setEnabled(pendingCount() > 0)
    local resetButton = window:getChildById('resetButton')
    resetButton:setEnabled(state.enabled and #state.allocated > 0)
    resetButton:setTooltip(string.format('Refunds every point for %s gold.', gold(state.resetCost)))
    window:getChildById('disabledLabel'):setVisible(not state.enabled)
end

-- Every margin set on a child re-runs the canvas's whole anchor layout
-- (UIWidget::setMarginLeft -> updateParentLayout), so moving ~2,000 widgets
-- one at a time is ~2,000 full passes over ~2,000 children. Paused, they all
-- move in one pass. The canvas declares its layout in the otui so it exists
-- before the first child is added.
local function batched(fn)
    local anchors = canvas:getLayout()
    anchors:disableUpdates()
    fn()
    anchors:enableUpdates()
    anchors:update()
end

-- Places every widget for the current pan and zoom; widgets off the canvas are
-- hidden so they cost nothing to draw.
local function placeAll()
    local width, height = canvas:getWidth(), canvas:getHeight()
    local halfW, halfH = width / 2, height / 2
    local zoom = view.zoom
    local scale = math.max(zoom, 0.35)

    local function toCanvas(x, y)
        return (x - view.x) * zoom + halfW, (y - view.y) * zoom + halfH
    end

    for _, entry in ipairs(edgeWidgets) do
        local a, b = tree.nodes[entry.a], tree.nodes[entry.b]
        local ax, ay = toCanvas(a.x, a.y)
        local bx, by = toCanvas(b.x, b.y)
        local cx, cy = (ax + bx) / 2, (ay + by) / 2
        local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        local reach = length / 2
        local onScreen = cx + reach > 0 and cx - reach < width and cy + reach > 0 and cy - reach < height
        entry.widget:setVisible(onScreen)
        if onScreen then
            local thickness = math.max(2, math.floor(5 * scale + 0.5))
            entry.widget:setSize({ width = math.max(1, math.floor(length + 0.5)), height = thickness })
            entry.widget:setMarginLeft(math.floor(cx - length / 2 + 0.5))
            entry.widget:setMarginTop(math.floor(cy - thickness / 2 + 0.5))
            entry.widget:setRotation(math.deg(math.atan2(by - ay, bx - ax)))
        end
    end

    for id, widget in pairs(nodeWidgets) do
        local node = tree.nodes[id]
        local x, y = toCanvas(node.x, node.y)
        local size = math.max(6, math.floor(NODE_SIZE[node.kind] * scale + 0.5))
        local onScreen = x + size > 0 and x - size < width and y + size > 0 and y - size < height
        widget:setVisible(onScreen)
        if onScreen then
            widget:setSize({ width = size, height = size })
            widget:setMarginLeft(math.floor(x - size / 2 + 0.5))
            widget:setMarginTop(math.floor(y - size / 2 + 0.5))
            if widget.icon then
                local iconSize = math.floor(size * 0.72 + 0.5)
                widget.icon:setSize({ width = iconSize, height = iconSize })
            end
            local glowSize = math.floor(size * 1.6 + 0.5)
            widget.glow:setSize({ width = glowSize, height = glowSize })
        end
    end
end

local function layout()
    if tree and canvas then
        batched(placeAll)
    end
end

-- Lights every node whose name, stat lines or kind contain ALL the typed words
-- ("fire prot" finds Fire Protection, not Fire Damage; "keystone" finds every
-- keystone).
local function applySearch()
    if not tree or not window then
        return
    end
    local text = window:getChildById('searchEdit'):getText():lower()
    local words = {}
    for word in text:gmatch('%S+') do
        words[#words + 1] = word
    end

    local matches = 0
    for id, widget in pairs(nodeWidgets) do
        local node = tree.nodes[id]
        if not node.searchText then
            node.searchText = (node.name .. '\n' .. node.kind .. '\n' .. table.concat(node.lines, '\n')):lower()
        end
        local match = #words > 0
        for _, word in ipairs(words) do
            if not node.searchText:find(word, 1, true) then
                match = false
                break
            end
        end
        widget.glow:setVisible(match)
        if match then
            matches = matches + 1
        end
    end
    window:getChildById('matchLabel'):setText(#words > 0 and (matches .. (matches == 1 and ' match' or ' matches')) or '')
end

local function onNodeClick(id)
    if not state or not state.enabled then
        return
    end
    if pending[id] then
        pending[id] = nil
        prunePending()
    elseif canTake(id) then
        pending[id] = true
    else
        return
    end
    refresh()
end

local function anchorToCanvas(widget)
    widget:addAnchor(AnchorTop, 'parent', AnchorTop)
    widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
end

local function createWidgets(list)
    canvas:destroyChildren()
    nodeWidgets, edgeWidgets = {}, {}
    -- Lines first, so every node is drawn over them.
    for _, entry in ipairs(list) do
        for _, other in ipairs(entry.l or {}) do
            local a, b = tree.nodes[entry.i], tree.nodes[other]
            if a and b then
                a.links[#a.links + 1] = b.id
                b.links[#b.links + 1] = a.id
                local widget = g_ui.createWidget('UIWidget', canvas)
                widget:setPhantom(true)
                widget:setFocusable(false)
                anchorToCanvas(widget)
                edgeWidgets[#edgeWidgets + 1] = { a = a.id, b = b.id, widget = widget }
            end
        end
    end
    for id, node in pairs(tree.nodes) do
        local widget = g_ui.createWidget('UIWidget', canvas)
        widget:setImageSource(IMAGES .. 'node_' .. node.kind)
        widget:setFocusable(false)
        anchorToCanvas(widget)
        widget.onClick = function()
            onNodeClick(id)
        end
        -- The node's icon: an item sprite inside the ring, phantom so the
        -- node keeps the clicks and the tooltip.
        if node.icon and node.icon > 0 then
            local icon = g_ui.createWidget('UIItem', widget)
            icon:setVirtual(true)
            icon:setItemId(node.icon)
            icon:setPhantom(true)
            icon:setFocusable(false)
            icon:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
            icon:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
            widget.icon = icon
        end
        -- The search glow: a soft white ring just outside the node's own,
        -- shown only while the node matches what is typed in the search box.
        local glow = g_ui.createWidget('UIWidget', widget)
        glow:setImageSource(IMAGES .. 'node_glow')
        glow:setPhantom(true)
        glow:setFocusable(false)
        glow:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        glow:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        glow:setVisible(false)
        widget.glow = glow
        nodeWidgets[id] = widget
    end
end

local function buildTree(list)
    tree = { nodes = {} }
    for _, entry in ipairs(list) do
        tree.nodes[entry.i] = {
            id = entry.i, kind = entry.k, name = entry.n, x = entry.x, y = entry.y,
            lines = entry.s or {}, links = {}, icon = entry.c,
        }
    end
    batched(function()
        createWidgets(list)
    end)
    applySearch()
end

local function centerOnStart()
    local start = tree and state and tree.nodes[state.start]
    if start then
        view.x, view.y, view.zoom = start.x, start.y, DEFAULT_ZOOM
    end
end

function PassiveTreeUI.onExtendedOpcode(_protocol, _opcode, buffer)
    local ok, message = pcall(json.decode, buffer)
    if not ok or type(message) ~= 'table' or not window then
        return
    end

    if message.t == 'tree' then
        local assembled = JsonChunks.receive(OPCODE, message, 'nodes')
        if assembled then
            buildTree(assembled.nodes or {})
            centerOnState = true
        end
    elseif message.t == 'state' then
        state = message
        state.allocated = state.allocated or {}
        state.allocatedSet = {}
        for _, id in ipairs(state.allocated) do
            state.allocatedSet[id] = true
            pending[id] = nil
        end
        if tree then
            if centerOnState then
                centerOnState = false
                centerOnStart()
            end
            layout()
            refresh()
        end
    end
end

local function onCanvasPress(_, mousePos, button)
    if button ~= MouseLeftButton then
        return false
    end
    drag = { x = mousePos.x, y = mousePos.y, viewX = view.x, viewY = view.y }
    return true
end

local function onCanvasMove(widget, mousePos)
    if not drag or not widget:isPressed() then
        return false
    end
    view.x = drag.viewX - (mousePos.x - drag.x) / view.zoom
    view.y = drag.viewY - (mousePos.y - drag.y) / view.zoom
    layout()
    return true
end

local function onCanvasRelease()
    drag = nil
    return false
end

local function onCanvasWheel(widget, mousePos, direction)
    local centerX = widget:getX() + widget:getWidth() / 2
    local centerY = widget:getY() + widget:getHeight() / 2
    -- Zoom about the pointer: the world point under it stays under it.
    local worldX = view.x + (mousePos.x - centerX) / view.zoom
    local worldY = view.y + (mousePos.y - centerY) / view.zoom
    local zoom = direction == MouseWheelUp and view.zoom * ZOOM_STEP or view.zoom / ZOOM_STEP
    view.zoom = math.min(MAX_ZOOM, math.max(MIN_ZOOM, zoom))
    view.x = worldX - (mousePos.x - centerX) / view.zoom
    view.y = worldY - (mousePos.y - centerY) / view.zoom
    layout()
    return true
end

function PassiveTreeUI.init()
    window = g_ui.displayUI('passivetree')
    window:hide()
    canvas = window:getChildById('canvas')
    canvas.onMousePress = onCanvasPress
    canvas.onMouseMove = onCanvasMove
    canvas.onMouseRelease = onCanvasRelease
    canvas.onMouseWheel = onCanvasWheel
    canvas.onGeometryChange = layout
    window:getChildById('searchEdit').onTextChange = applySearch

    ProtocolGame.registerExtendedOpcode(OPCODE, PassiveTreeUI.onExtendedOpcode)
    connect(g_game, { onGameEnd = PassiveTreeUI.onGameEnd })

    -- A Keybind rather than a panel-scoped bindKeyDown, for the reason
    -- game_dungeons gives: a panel binding stops firing while this window holds
    -- focus, so it would open but never close.
    Keybind.new('Windows', 'Show/hide Passive Tree', 'Ctrl+Shift+P', '')
    Keybind.bind('Windows', 'Show/hide Passive Tree', {
        {
            type = KEY_DOWN,
            callback = PassiveTreeUI.toggle,
        }
    })
end

function PassiveTreeUI.terminate()
    disconnect(g_game, { onGameEnd = PassiveTreeUI.onGameEnd })
    ProtocolGame.unregisterExtendedOpcode(OPCODE)
    Keybind.delete('Windows', 'Show/hide Passive Tree')
    if resetBox then
        resetBox:destroy()
        resetBox = nil
    end
    if window then
        window:destroy()
        window = nil
        canvas = nil
    end
end

local function close()
    -- Picks that were never confirmed are not kept.
    pending = {}
    if resetBox then
        resetBox:destroy()
        resetBox = nil
    end
    window:hide()
end

function PassiveTreeUI.onGameEnd()
    if window then
        close()
    end
    tree, state, treeRequested = nil, nil, false
    nodeWidgets, edgeWidgets = {}, {}
    if canvas then
        batched(function()
            canvas:destroyChildren()
        end)
    end
end

function PassiveTreeUI.toggle()
    if not window then
        return
    end
    if window:isVisible() then
        close()
        return
    end
    if not g_game.isOnline() then
        return
    end

    window:show()
    window:raise()
    window:focus()
    if not treeRequested then
        treeRequested = true
        send({ a = 'tree' })
    else
        centerOnState = true
        send({ a = 'state' })
    end
    refresh()
end

function PassiveTreeUI.confirm()
    if not state or pendingCount() == 0 then
        return
    end
    local nodes = {}
    for _, id in ipairs(state.allocated) do
        nodes[#nodes + 1] = id
    end
    for id in pairs(pending) do
        nodes[#nodes + 1] = id
    end
    send({ a = 'confirm', nodes = nodes })
end

function PassiveTreeUI.undo()
    pending = {}
    refresh()
end

function PassiveTreeUI.reset()
    if not state or #state.allocated == 0 or resetBox then
        return
    end
    local function closeBox()
        if resetBox then
            resetBox:destroy()
            resetBox = nil
        end
    end
    local function yes()
        closeBox()
        pending = {}
        send({ a = 'reset' })
    end
    resetBox = displayGeneralBox(tr('Reset passive tree'),
        string.format('Refund all %d passive points for %s gold?', #state.allocated, gold(state.resetCost)), {
            { text = tr('Yes'), callback = yes },
            { text = tr('No'), callback = closeBox },
            anchor = AnchorHorizontalCenter,
        }, yes, closeBox)
end
