local addonName, ns = ...
local Addon = ns.Addon
local LootTracker = ns.LootTracker

ns.moduleDefaults["LootTracker"] = {
    profile = {
        moduleEnabled = true,
        debug = false,
        -- loot mode situations
        lootModeWhenFishing = {
            lootMode = "managed",
            ignoreJunk = false,
            stayOpenForJunk = true,
        },
        lootModeWhenOther = {
            lootMode = "none",
            ignoreJunk = false,
            stayOpenForJunk = true,
        },
        limitLootDataRows = 100,
        lootDelay = 150,
        trackFishingLoot = true,
        trackNonFishingLoot = false,
        showCatchRate = true,
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
        windowVisible = false,
        windowPos = {
            point = "CENTER",
            xOfs = 0,
            yOfs = 0,
            width = 280,
            height = 340,
        }
    },
    char = {
        lootedItems = {},
        lootedCurrencies = {},
        castsLooted = 0,
    }
}
