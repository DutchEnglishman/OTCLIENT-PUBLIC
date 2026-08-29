-- Unbound by default: Ctrl+Z is reserved for undo in text edits. Assignable in Options > Controls.
HOTKEY = ''

bugReportWindow = nil
bugTextEdit = nil

function init()
    g_ui.importStyle('bugreport')

    bugReportWindow = g_ui.createWidget('BugReportWindow', rootWidget)
    bugReportWindow:hide()

    bugTextEdit = bugReportWindow:getChildById('bugTextEdit')

    Keybind.new("Dialogs", "Open Bugreport", HOTKEY, "")
    Keybind.bind("Dialogs", "Open Bugreport", {
      {
        type = KEY_DOWN,
        callback = show,
      }
    }, modules.game_interface.getRootPanel())
end

function terminate()
    Keybind.delete("Dialogs", "Open Bugreport")
    bugReportWindow:destroy()
end

function doReport()
    g_game.reportBug(bugTextEdit:getText())
    bugReportWindow:hide()
    modules.game_textmessage.displayGameMessage(tr('Bug report sent.'))
end

function show()
    if g_game.isOnline() then
        bugTextEdit:setText('')
        bugReportWindow:show()
        bugReportWindow:raise()
        bugReportWindow:focus()
    end
end
