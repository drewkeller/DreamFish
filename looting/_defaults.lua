local addonName, ns = ...
local Addon = ns.Addon
local LootTracker = ns.LootTracker

ns.moduleDefaults["LootTracker"] = {
    profile = {
        moduleEnabled = true,
        debug = false,
        -- loot mode situations
        lootModeWhenFishing = {
            lootMode = "none",
            ignoreJunk = false,
            stayOpenForJunk = true,
        },
        lootModeWhenOther = {
            lootMode = "none",
            ignoreJunk = false,
            stayOpenForJunk = true,
        },
        lootDelay = 150,
        -- alerts
        patientTreasureAlert = true,
        normalBagAlertEnabled = true,
        reagentBagAlertEnabled = true,
        normalBagAlertThreshold = 2,
        reagentBagAlertThreshold = 2,
        bagAlertOnlyWhenFishing = true,
        bagAlertPlaySound = true,
        bagAlertShowFullScreen = false,
        bagAlertThrottle = 60,
        -- tracker
        showTrackerAs = "window",
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
