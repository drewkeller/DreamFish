local addonName, ns = ...
local Addon = ns.Addon
ns.LootTracker = Addon:NewModule("LootTracker", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")
ns.LootTracker.const = ns.moduleConstants["LootTracker"]

ns.LootTracker.const = {
    LootModes = {
        { id = "none",    name = "Use native auto-loot setting", order = 1, value = 1 },
        { id = "manual",  name = "Manual looting",               order = 2, value = 2 },
        { id = "native",  name = "Native auto-loot",             order = 3, value = 3 },
        { id = "managed", name = "Managed auto-loot",            order = 4, value = 4 },
    }
}
