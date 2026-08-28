AutoLoot = AutoLoot or {}

AutoLoot.containers = AutoLoot.containers or {
    main = nil,
    stackables = nil,
    usables = nil
}

-- Roles a bag can actually be bound to. "usables" has a slot and a lock but no
-- routing rule yet, so it is deliberately not in here.
AutoLoot.CONTAINER_ROLES = {
    'main',
    'stackables'
}

local WIDGET_IDS = {
    main = 'mainContainer',
    stackables = 'stackablesContainer',
    usables = 'usablesContainer'
}

local ROLE_NAMES = {
    main = 'Main',
    stackables = 'Stackables',
    usables = 'Useable'
}

local function getRoleWidget(role)
    if not AutoLoot.window then
        return nil
    end

    local widgetId = WIDGET_IDS[role]

    if not widgetId then
        return nil
    end

    return AutoLoot.window:recursiveGetChildById(widgetId)
end

local function getStoredClientId(value)
    if type(value) == "number" then
        return value
    end
    if type(value) == "table" then
        return value.clientId
    end
    return nil
end

local function persist()
    if AutoLoot.saveCurrentPreset then
        AutoLoot.saveCurrentPreset()
    end

    if AutoLoot.saveCharacterSettings then
        AutoLoot.saveCharacterSettings()
    end
end

function AutoLoot.setContainer(role, item)
    if not AutoLoot.isContainerUnlocked(role) then
        print(string.format(
            '[AUTOLOOT] %s container is locked',
            ROLE_NAMES[role] or role
        ))

        return false
    end

    if not item or not item:isItem() then
        return false
    end

    if item.isContainer and not item:isContainer() then
        print(string.format(
            '[AUTOLOOT] %s destination must be a container',
            ROLE_NAMES[role] or role
        ))

        return false
    end

    local widget = getRoleWidget(role)

    if not widget then
        return false
    end

    AutoLoot.containers[role] = item:getId()
    widget:setItem(item)

    if AutoLoot.sendContainer then
        AutoLoot.sendContainer(role, item)
    end

    persist()

    print(string.format(
        '[AUTOLOOT] %s container saved: %d',
        ROLE_NAMES[role] or role,
        item:getId()
    ))

    return true
end

function AutoLoot.clearContainer(role)
    local widget = getRoleWidget(role)

    if not widget then
        return false
    end

    AutoLoot.containers[role] = nil
    widget:setItem(nil)

    if AutoLoot.clearContainerOnServer then
        AutoLoot.clearContainerOnServer(role)
    end

    persist()

    print(string.format(
        '[AUTOLOOT] %s container cleared and saved',
        ROLE_NAMES[role] or role
    ))

    return true
end

-- Drop the binding without telling the server, for when the server is the one
-- that dropped it (the same bag was bound to another slot).
function AutoLoot.forgetContainer(role)
    if not WIDGET_IDS[role] then
        return false
    end

    AutoLoot.containers[role] = nil

    local widget = getRoleWidget(role)

    if widget then
        widget:setItem(nil)
    end

    persist()

    print(string.format(
        '[AUTOLOOT] %s container was re-bound elsewhere and is now empty',
        ROLE_NAMES[role] or role
    ))

    return true
end

function AutoLoot.setMainContainer(item)
    return AutoLoot.setContainer('main', item)
end

function AutoLoot.clearMainContainer()
    return AutoLoot.clearContainer('main')
end

function AutoLoot.refreshContainerSlots()
    for role in pairs(WIDGET_IDS) do
        local widget = getRoleWidget(role)

        if widget then
            local clientId = getStoredClientId(
                AutoLoot.containers[role]
            )

            if clientId then
                widget:setItem(Item.create(clientId))
            else
                widget:setItem(nil)
            end
        end
    end
end

function AutoLoot.setupContainerSlots()
    for _, role in ipairs(AutoLoot.CONTAINER_ROLES) do
        local widget = getRoleWidget(role)

        if widget then
            local boundRole = role

            widget.onDrop = function(self, draggedWidget, mousePos)
                if not draggedWidget then
                    return false
                end

                local item = draggedWidget.currentDragThing

                if not item or not item:isItem() then
                    return false
                end

                return AutoLoot.setContainer(boundRole, item)
            end

            widget.onMouseRelease = function(self, mousePos, mouseButton)
                if mouseButton ~= MouseRightButton then
                    return false
                end

                if not AutoLoot.isContainerUnlocked(boundRole) then
                    return false
                end

                return AutoLoot.clearContainer(boundRole)
            end

            AutoLoot.updateContainerLockVisual(widget, role)
        else
            print(string.format(
                '[AUTOLOOT] Container widget missing for role %s',
                role
            ))
        end
    end

    -- The Useable slot locks and unlocks with Stackables but has no routing
    -- rule, so it stays inert rather than silently swallowing a bag.
    local usablesWidget = getRoleWidget('usables')

    if usablesWidget then
        AutoLoot.updateContainerLockVisual(usablesWidget, 'usables')

        usablesWidget.onDrop = function()
            return false
        end
    end

    AutoLoot.refreshContainerSlots()
end
