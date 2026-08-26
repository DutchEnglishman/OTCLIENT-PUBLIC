-- @docclass

-- While an action owns the cursor -- the "use with" / trade crosshair -- nothing
-- may change it until the click that ends the action releases the lock. See
-- Mouse::lockCursor (framework/input/mouse.h) and setTargetCursor in
-- game_interface.
--
-- These two are wrapped rather than each caller being guarded because they are
-- the only way Lua can reach the window cursor, and unlike the g_mouse cursor
-- stack they overwrite it outright: one hover handler reaching for
-- restoreMouseCursor drops the item off the crosshair with nothing left to put
-- it back. Guarding handlers one at a time was tried first and kept missing
-- one -- buttons, then the trainer's fields, then the chat input.
local rawSetSystemCursor = g_window.setSystemCursor
local rawRestoreMouseCursor = g_window.restoreMouseCursor

-- Pure-Lua fallback for a binary older than these scripts.
--
-- lockCursor / unlockCursor / isCursorLocked are C++ bindings added alongside
-- this wrapper. Without this block, calling a missing one throws and aborts its
-- caller PART WAY THROUGH: setTargetCursor died after pushing the crosshair but
-- before setting targetCursorActive, so restoreTargetCursor then returned early
-- and could never pop it -- a crosshair no click could clear.
--
-- The lock is just a flag, so Lua can hold it perfectly well. The only thing
-- that needs the C++ side is UITextEdit, the single cursor caller that lives in
-- C++ and so cannot see this one; on an old binary a hovered text field still
-- takes the crosshair, but everything else behaves and clicks release normally.
if not g_mouse.lockCursor then
    local locked = false
    function g_mouse.lockCursor() locked = true end
    function g_mouse.unlockCursor() locked = false end
    function g_mouse.isCursorLocked() return locked end
end

-- isCursorActive needs the same treatment. The hover guards in UIButton,
-- UISplitter, UIResizeBorder and the console call it on every hover, and on an
-- older binary it is nil as well -- it threw 190 times in one logged session.
-- Lua cannot inspect the cursor stack, but every caller asks about 'target',
-- which is exactly what the lock already tracks.
if not g_mouse.isCursorActive then
    function g_mouse.isCursorActive(name)
        return name == 'target' and g_mouse.isCursorLocked()
    end
end

local function cursorLocked()
    return g_mouse.isCursorLocked()
end

function g_window.setSystemCursor(cursorName)
    if cursorLocked() then
        return
    end
    return rawSetSystemCursor(cursorName)
end

function g_window.restoreMouseCursor()
    if cursorLocked() then
        return
    end
    return rawRestoreMouseCursor()
end

function g_mouse.bindAutoPress(widget, callback, delay, button, interval)
    local button = button or MouseLeftButton
    local interval = interval or 30
    connect(widget, {
        onMousePress = function(widget, mousePos, mouseButton)
            if mouseButton ~= button then
                return false
            end
            local startTime = g_clock.millis()
            callback(widget, mousePos, mouseButton, 0)
            periodicalEvent(function()
                callback(widget, g_window.getMousePosition(), mouseButton, g_clock.millis() - startTime)
            end, function()
                return g_mouse.isPressed(mouseButton)
            end, interval, delay)
            return true
        end
    })
end

function g_mouse.bindPressMove(widget, callback)
    connect(widget, {
        onMouseMove = function(widget, mousePos, mouseMoved)
            if widget:isPressed() then
                callback(mousePos, mouseMoved)
                return true
            end
        end
    })
end

function g_mouse.bindMove(widget, callback)
    connect(widget, {
        onMouseMove = function(widget, mousePos, mouseMoved)
            callback(mousePos, mouseMoved)
            return true
        end
    })
end

function g_mouse.bindPress(widget, callback, button)
    connect(widget, {
        onMousePress = function(widget, mousePos, mouseButton)
            if not button or button == mouseButton then
                callback(mousePos, mouseButton)
                return true
            end
            return false
        end
    })
end

function g_mouse.bindOnDrop(widget, callback)
    connect(widget, {
        onDrop = function(widget, mousePos)
            callback(mousePos, mouseButton)
            return true
        end
    })
end
