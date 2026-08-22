AutoLoot = AutoLoot or {}

AutoLoot.MAX_SLOTS = 20
AutoLoot.DEFAULT_UNLOCKED_SLOTS = 6

AutoLoot.window = nil
AutoLoot.button = nil

AutoLoot.items = {}

AutoLoot.unlockedSlots = AutoLoot.DEFAULT_UNLOCKED_SLOTS

AutoLoot.containers = {
    main = nil,
    stackables = nil,
    usables = nil
}

AutoLoot.unlockedContainers = {
    main = true,
    stackables = false,
    usables = false
}

AutoLoot.filter = 'accept'
AutoLoot.updatingFilter = false

AutoLoot.currentPreset = 1
AutoLoot.MAX_PRESETS = 10
AutoLoot.presets = {}

AutoLoot.presetNames = {
    'Preset 1',
    'Preset 2',
    'Preset 3',
    'Preset 4',
    'Preset 5',
    'Preset 6',
    'Preset 7',
    'Preset 8',
    'Preset 9',
    'Preset 10'
}
AutoLoot.updatingPresetButtons = false