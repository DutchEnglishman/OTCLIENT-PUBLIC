-- Where looted coins go (bank or loot bags) and the Convert gold toggle. The
-- server holds all three values per character and sends them as GOLD; the
-- window only mirrors them and asks for a change.
AutoLoot.goldToBag = AutoLoot.goldToBag or false
AutoLoot.convertUnlocked = AutoLoot.convertUnlocked or false
AutoLoot.convertGold = AutoLoot.convertGold or false

local CONVERT_TOOLTIP = 'Whenever autoloot puts coins in your bags, every 100 gold coins become a platinum coin and every 100 platinum coins a crystal coin.'
local CONVERT_LOCKED_TOOLTIP = 'Unlock Auto Convert Gold in the shop (Character tab).\n\n' .. CONVERT_TOOLTIP

function AutoLoot.refreshGoldUI()
    if not AutoLoot.window then
        return
    end

    local toBank = AutoLoot.window:recursiveGetChildById('goldToBank')
    local toBag = AutoLoot.window:recursiveGetChildById('goldToBag')
    local convert = AutoLoot.window:recursiveGetChildById('convertGold')

    AutoLoot.updatingGoldUI = true

    if toBank then
        toBank:setChecked(not AutoLoot.goldToBag)
    end

    if toBag then
        toBag:setChecked(AutoLoot.goldToBag)
    end

    if convert then
        convert:setChecked(AutoLoot.convertUnlocked and AutoLoot.convertGold)
        convert:setOpacity(AutoLoot.convertUnlocked and 1.0 or 0.55)
        convert:setTooltip(AutoLoot.convertUnlocked and CONVERT_TOOLTIP or CONVERT_LOCKED_TOOLTIP)
    end

    AutoLoot.updatingGoldUI = false
end

function AutoLoot.onGoldModeChange(mode, checked)
    if AutoLoot.updatingGoldUI then
        return
    end

    -- A radio pair: unchecking the selected one only redraws it as it was.
    if not checked then
        AutoLoot.refreshGoldUI()
        return
    end

    AutoLoot.goldToBag = mode == 'bag'
    AutoLoot.refreshGoldUI()
    AutoLoot.sendGoldMode(mode)
end

function AutoLoot.onConvertGoldChange(checked)
    if AutoLoot.updatingGoldUI then
        return
    end

    if not AutoLoot.convertUnlocked then
        AutoLoot.refreshGoldUI()
        return
    end

    AutoLoot.convertGold = checked
    AutoLoot.sendConvertGold(checked)
end
