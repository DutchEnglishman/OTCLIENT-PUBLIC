-- @docclass
UIPopupMenu = extends(UIWidget, 'UIPopupMenu')

local currentMenu

function UIPopupMenu.create()
    local menu = UIPopupMenu.internalCreate()
    local layout = UIVerticalLayout.create(menu)
    layout:setFitChildren(true)
    menu:setLayout(layout)
    menu.isGameMenu = false
    return menu
end

function UIPopupMenu:display(pos)
    -- don't display if not options was added
    if self:getChildCount() == 0 then
        self:destroy()
        return
    end

    if g_ui.isMouseGrabbed() then
        self:destroy()
        return
    end

    if currentMenu then
        currentMenu:destroy()
    end

    if pos == nil then
        pos = g_window.getMousePosition()
    end

    rootWidget:addChild(self)
    self.displayPos = pos
    self:setPosition(pos)
    self:grabMouse()
    self:focus()
    -- self:grabKeyboard()
    currentMenu = self
end

function UIPopupMenu:onGeometryChange(newRect, oldRect)
    local parent = self:getParent()
    if not parent then
        return
    end

    -- A menu is positioned before its real size is known: the vertical layout only
    -- fits it to its options a frame later, so until then it still carries the size
    -- of its border image (256px tall on the slate skin). Re-apply the position it
    -- was opened at on every geometry change, so it is pulled back on screen against
    -- the size it actually has rather than against that placeholder.
    local pos = self.displayPos
    if pos then
        local rect = self:getRect()
        local x = math.max(parent:getX(), math.min(pos.x, parent:getX() + parent:getWidth() - rect.width))
        local y = math.max(parent:getY(), math.min(pos.y, parent:getY() + parent:getHeight() - rect.height))
        if x ~= rect.x or y ~= rect.y then
            self:setPosition({ x = x, y = y })
            return
        end
    end

    self:bindRectToParent()
end

function UIPopupMenu:addOption(optionName, optionCallback, shortcut, disabled)
    local optionWidget = g_ui.createWidget(self:getStyleName() .. 'Button', self)
    optionWidget.onClick = function(widget)
        self:destroy()
        optionCallback(self:getPosition())
    end
    optionWidget:setText(optionName)
    local width = optionWidget:getTextSize().width + optionWidget:getMarginLeft() + optionWidget:getMarginRight() + 15

    if shortcut then
        local shortcutLabel = g_ui.createWidget(self:getStyleName() .. 'ShortcutLabel', optionWidget)
        shortcutLabel:setText(shortcut)
        width = width + shortcutLabel:getTextSize().width + shortcutLabel:getMarginLeft() +
                    shortcutLabel:getMarginRight()
    end
    optionWidget:setEnabled(not disabled)
    self:setWidth(math.max(190, math.max(self:getWidth(), width)))
end

function UIPopupMenu:addSeparator()
    g_ui.createWidget('HorizontalSeparator', self)
end

function UIPopupMenu:addText(text)
    local optionWidget = g_ui.createWidget("PopupScrollMenuShortcutLabel", self)
    optionWidget:setText(text)
    local width = optionWidget:getTextSize().width + optionWidget:getMarginLeft() + optionWidget:getMarginRight() + 15
    self:setWidth(math.max(self:getWidth(), width))
end

function UIPopupMenu:addCheckBox(text, checked, callback)
    local checkBox = g_ui.createWidget(self:getStyleName() .. 'CheckBox', self)
    checkBox:setText(text)
    checkBox:setChecked(checked or false)
    checkBox.onClick = function()
        checkBox:setChecked(not checkBox:isChecked())
        self:destroy()
        callback(checkBox, checkBox:isChecked())
    end
    local width = checkBox:getTextSize().width + checkBox:getMarginLeft() + checkBox:getMarginRight() + 30
    self:setWidth(math.max(self:getWidth(), width))
    return checkBox
end

function UIPopupMenu:setGameMenu(state)
    self.isGameMenu = state
end

function UIPopupMenu:onDestroy()
    if currentMenu == self then
        currentMenu = nil
    end
    self:ungrabMouse()
end

function UIPopupMenu:onMousePress(mousePos, mouseButton)
    -- clicks outside menu area destroys the menu
    if not self:containsPoint(mousePos) then
        self:destroy()
    end
    return true
end

function UIPopupMenu:onKeyPress(keyCode, keyboardModifiers)
    if keyCode == KeyEscape then
        self:destroy()
        return true
    end
    return false
end

-- close all menus when the window is resized
local function onRootGeometryUpdate()
    if currentMenu then
        currentMenu:destroy()
    end
end

local function onGameEnd()
    if currentMenu and currentMenu.isGameMenu then
        currentMenu:destroy()
    end
end

connect(rootWidget, {
    onGeometryChange = onRootGeometryUpdate
})
connect(g_game, {
    onGameEnd = onGameEnd
})
