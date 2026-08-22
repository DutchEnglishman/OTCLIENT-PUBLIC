AutoLoot = AutoLoot or {}

AutoLoot.containers = AutoLoot.containers or {
    main = nil,
    stackables = nil,
    usables = nil
}

local function getMainWidget()
    if not AutoLoot.window then
        return nil
    end
    return AutoLoot.window:recursiveGetChildById("mainContainer")
end

local function getStackablesWidget()
    if not AutoLoot.window then
        return nil
    end

    return AutoLoot.window:recursiveGetChildById(
        'stackablesContainer'
    )
end

local function getUsablesWidget()
    if not AutoLoot.window then
        return nil
    end

    return AutoLoot.window:recursiveGetChildById(
        'usablesContainer'
    )
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

function AutoLoot.setMainContainer(item)
    if not item or not item:isItem() then
        return false
    end

    if item.isContainer and not item:isContainer() then
        print("[AUTOLOOT] Main destination must be a container")
        return false
    end

    local widget = getMainWidget()
    if not widget then
        return false
    end

    AutoLoot.containers.main = item:getId()
    widget:setItem(item)

    if AutoLoot.sendMainContainer then
        AutoLoot.sendMainContainer(item)
    end

    if AutoLoot.saveCurrentPreset then
        AutoLoot.saveCurrentPreset()
    end

    if AutoLoot.saveCharacterSettings then
        AutoLoot.saveCharacterSettings()
    end

    print(string.format(
        "[AUTOLOOT] Main container saved: %d",
        item:getId()
    ))

    return true
end

function AutoLoot.clearMainContainer()
    AutoLoot.containers.main = nil

    local widget = getMainWidget()
    if widget then
        widget:setItem(nil)
    end

    if AutoLoot.clearMainContainerOnServer then
        AutoLoot.clearMainContainerOnServer()
    end

    if AutoLoot.saveCurrentPreset then
        AutoLoot.saveCurrentPreset()
    end

    if AutoLoot.saveCharacterSettings then
        AutoLoot.saveCharacterSettings()
    end

    print("[AUTOLOOT] Main container cleared and saved")

    return true
end

function AutoLoot.refreshContainerSlots()
    local widget = getMainWidget()
    if not widget then
        return
    end

    local clientId = getStoredClientId(AutoLoot.containers.main)
    if clientId then
        widget:setItem(Item.create(clientId))
    else
        widget:setItem(nil)
    end
end

function AutoLoot.setupContainerSlots()
    local mainWidget = getMainWidget()
    local stackablesWidget = getStackablesWidget()
    local usablesWidget = getUsablesWidget()

    if not mainWidget then
        print("[AUTOLOOT] Main container widget not found")
        return
    end

    mainWidget.onDrop = function(self, draggedWidget, mousePos)
        if not AutoLoot.isContainerUnlocked('main') then
            print('[AUTOLOOT] Main container is locked')
            return false
        end

        if not draggedWidget then
            return false
        end

        local item = draggedWidget.currentDragThing
        if not item or not item:isItem() then
            return false
        end

        return AutoLoot.setMainContainer(item)
    end

    mainWidget.onMouseRelease = function(self, mousePos, mouseButton)
        if not AutoLoot.isContainerUnlocked('main') then
            return false
        end

        if mouseButton ~= MouseRightButton then
            return false
        end

        return AutoLoot.clearMainContainer()
    end

    if stackablesWidget then
        AutoLoot.updateContainerLockVisual(
            stackablesWidget,
            'stackables'
        )

        stackablesWidget.onDrop = function(
            self,
            draggedWidget,
            mousePos
        )
            if not AutoLoot.isContainerUnlocked('stackables') then
                print('[AUTOLOOT] Stackables container is locked')
                return false
            end

            return false
        end

        stackablesWidget.onMouseRelease = function(
            self,
            mousePos,
            mouseButton
        )
            if not AutoLoot.isContainerUnlocked('stackables') then
                return false
            end

            return false
        end
    end

    if usablesWidget then
        AutoLoot.updateContainerLockVisual(
            usablesWidget,
            'usables'
        )

        usablesWidget.onDrop = function(
            self,
            draggedWidget,
            mousePos
        )
            if not AutoLoot.isContainerUnlocked('usables') then
                print('[AUTOLOOT] Usables container is locked')
                return false
            end

            return false
        end

        usablesWidget.onMouseRelease = function(
            self,
            mousePos,
            mouseButton
        )
            if not AutoLoot.isContainerUnlocked('usables') then
                return false
            end

            return false
        end
    end

    AutoLoot.updateContainerLockVisual(
        mainWidget,
        'main'
    )

    AutoLoot.refreshContainerSlots()
end