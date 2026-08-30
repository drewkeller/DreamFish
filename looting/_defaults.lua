local addonName, ns = ...
local Addon = ns.Addon
local LootTracker = Addon:NewModule("LootTracker", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")
ns.LootTracker = LootTracker

ns.moduleDefaults["LootTracker"] = {
    profile = {
        moduleEnabled = true,
        debug = false,
        -- start of non-prototype options
        minQualityFilter = 0,
        showWindowOnStartup = false,
        windowVisible = true,
        windowPos = {
            point = "CENTER",
            xOfs = 0,
            yOfs = 0,
            width = 280,
            height = 340,
        }
    },
    char = {
        itemsLooted = 0,
        lootedItems = {},
        lootedCurrencies = {},
    }
}
