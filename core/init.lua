-- DreamFisher: Core Initialization
-- Addon setup, defaults, and global state

local addonName = "DreamFisher"
local frame = CreateFrame("Frame", addonName .. "Frame")
local addon = _G[addonName] or {}
_G[addonName] = addon

addon.frame = frame

-- Default configuration
addon.defaults = {
    -- Focus
    autoLoot = true,
    treasureAlerts = true,
    bagAlerts = true,
    bagAlertsThreshold = 2,
    reagentBagAlerts = true,
    reagentBagAlertsThreshold = 2,
    throwAwayJunk = false,
    focusedAudio = true,
    focusedAudioLinger = 10,
    focusedVisuals = false,
    focusedVisualsLinger = 10,
    -- Tackle
    selectedRaftToy = nil,
    selectedBobberToy = nil,
    useOversizedBobber = false,
    selectedFishingPole = { isChecked = false, itemID = nil },
    selectedUnderlightAngler = { isChecked = false, itemID = nil },
    -- Buffs
    buffItems = {
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
        { enabled = false, itemID = nil },
    },
    buffAuraByItem = {
        ["238374"] = { spellID = 1237942, duration = 30 }, -- Tender Lumifin
    },
    castingModes = {
        doubleRightClick = true,
        singleRightClick = false,
        castHotkey = false,
    },
    easyStrike = false,
    closeWindowOnEscape = true,
    -- General
    configWindowPosition = nil,
    debugMode = true,
    debugState = false,
    debugFade = false,
    debugBags = false,
    debugBuffs = false,
    debugLoot = false,
}

-- Global state variables
addon.state = {
    -- Auto-loot
    savedAutoLoot = nil,

    -- Fishing
    fishingSessionState = "IDLE",
    fishingStartTime = 0,

    -- Audio
    savedFishingAudioCVars = nil,
    audioLingerGeneration = 0,
    audioRestoreAt = nil,

    -- Right-click
    lastRightClickTime = 0,
    doubleClickWindow = 0.33,
    lastFishingSecureClickAt = 0,

    -- Alerts
    lastBagWarning = 0,
    lastAlertTime = 0,
    lastSoundTime = 0,
    patientAuraActive = false,

    -- Fishing tracking
    fishingStartGraceUntil = 0,
    lastFishingCastStopAt = 0,
    fishingExpireSeconds = 20,
    interactAcquireExpiresAt = 0,

    -- Buff management
    lastBuffCheckTime = 0,
    buffCheckInterval = 1,
    buffItemLastUseAt = {},
    buffReminderCooldown = 12,
    buffItemLastReminderAt = {},
    buffItemLastReminderCastAnchor = {},
    buffItemLastKnownCount = {},
    buffMissingWarningCooldown = 8,
    buffItemLastMissingWarningAt = {},
    buffItemTransientUntil = {},
    buffUnknownDurationSuppressed = {},
    lureMissingPoleWarningAt = 0,
    buffCastBlockWarningAt = 0,
    foodDrinkCastBlockWarningAt = 0,
    pendingBuffObservation = nil,
    uiBuffCursorDragState = nil,
}

-- Constants
addon.const = {
    maxBuffSlots = 25,
    maxFishingCastSeconds = 20,
    buffPreRefreshSafetySeconds = 2,
    patientlyRewardedSpellID = 1235378,
    fishingSpellID = 131474,
    fishingChannelSpellID = 131476,
    hookedEvidenceConfirmSeconds = 4,
    bobberToyItemIDs = {
        { id = 180993, name = "Bat Visage" },
        { id = 142528, name = "Can of Worms" },
        { id = 147307, name = "Carved Wooden Helm" },
        { id = 142529, name = "Cat Head" },
        { id = 147312, name = "Demon Noggin" },
        { id = 147308, name = "Enchanted Bobber" },
        { id = 147309, name = "Face of the Forest" },
        { id = 147310, name = "Floating Totem" },
        { id = 142532, name = "Murloc Head" },
        { id = 147311, name = "Replica Gondola" },
        { id = 142531, name = "Squeaky Duck" },
        { id = 142530, name = "Tugboat" },
        { id = 143662, name = "Wooden Pepe" },
    },
    raftToyItemIDs = {
        { id = 85500, name = "Angler's Fishing Raft" },
        { id = 198428, name = "Tuskarr Dinghy" },
    },
    underlightAnglerItemID = 133755,
    underlightAnglerModes = {
        disabled = "Keep the fishing pole equipped",
        always_except_fishing = "Auto-swap for fishing/not fishing",
        lock_underlight = "Keep the Underlight Angler equipped",
    },
    -- These are items that provide fishing-related buffs (auras) that we can track
    -- Exception: "lure" category items are not auras and can't be tracked directly
    knownBuffItems = {
        -- Boobber toys
        [202207] = { spellID = 397827, duration = 3600, category = "bobber", }, -- Reusable Oversized Bobber (Bobber toy aura)
        [180993] = { spellID = 335484, duration = 3600, category = "bobber", }, -- Bat Visage (Bobber toy aura)
        [142528] = { spellID = 231291, duration = 3600, category = "bobber", }, -- Can of Worms (Bobber toy aura)
        [147307] = { spellID = 240803, duration = 3600, category = "bobber", }, -- Carved Wooden Helm (Bobber toy aura)
        [142529] = { spellID = 231319, duration = 3600, category = "bobber", }, -- Cat Head (Bobber toy aura)
        [147312] = { spellID = 240801, duration = 3600, category = "bobber", }, -- Demon Noggin (Bobber toy aura)
        [147308] = { spellID = 240800, duration = 3600, category = "bobber", }, -- Enchanted Bobber (Bobber toy aura)
        [147309] = { spellID = 240806, duration = 3600, category = "bobber", }, -- Face of the Forest (Bobber toy aura)
        [147310] = { spellID = 240802, duration = 3600, category = "bobber", }, -- Floating Totem (Bobber toy aura)
        [142532] = { spellID = 231349, duration = 3600, category = "bobber", }, -- Murloc Head (Bobber toy aura)
        [147311] = { spellID = 240804, duration = 3600, category = "bobber", }, -- Replica Gondola (Bobber toy aura)
        [142531] = { spellID = 231341, duration = 3600, category = "bobber", }, -- Squeaky Duck (Bobber toy aura)
        [142530] = { spellID = 231338, duration = 3600, category = "bobber", }, -- Tugboat (Bobber toy aura)
        [143662] = { spellID = 232613, duration = 3600, category = "bobber", }, -- Wooden Pepe (Bobber toy aura)
        -- Midnight fishing consumables
        [238374] = { spellID = 1237942, duration = 30, category = "other_consumable", }, -- Tender Lumifin
        [238365] = { spellID = 1237942, duration = 30, category = "other_consumable", }, -- Sin'dorei Swarmer
        [238371] = { spellID = 1237942, duration = 30, category = "other_consumable", }, -- Arcane Wyrmfish
        [238382] = { spellID = 1237942, duration = 30, category = "other_consumable", }, -- Gore Guppy
        [238366] = { spellID = 1237942, duration = 30, category = "other_consumable", }, -- Lynxfish
        [238367] = { spellID = 1235216, duration = 30, category = "other_consumable", }, -- Root Crab
        [238369] = { spellID = 1235216, duration = 30, category = "other_consumable", }, -- Bloomtail Minnow
        [238370] = { spellID = 1237942, duration = 30, category = "other_consumable", }, -- Shimmer Spinefish
        [238381] = { spellID = 1237942, duration = 30, category = "other_consumable", }, -- Hollow Grouper
        [241316] = { spellID = 1236763, duration = 3600, category = "other_consumable", }, -- Haranir Phial of Perception (2)
        [241317] = { spellID = 1236763, duration = 1800, category = "other_consumable", }, -- Haranir Phial of Perception (1)
        [242299] = { spellID = 1269152, duration = 3600, category = "food_drink", }, -- Sanguithorn Tea
        [262651] = { spellID = 1284999, duration = 600, category = "lure", }, -- Pointed Spikesnail
        [241145] = { spellID = 1237964, duration = 1800, category = "bait", }, -- Lucky Loa Lure
        [241147] = { spellID = 1237974, duration = 1800, category = "bait", }, -- Blood Hunter Lure
        [241149] = { spellID = 1237965, duration = 1800, category = "bait", }, -- Ominous Octopus Lure
        -- War Within fishing consumables
        [220137] = { spellID = 456156, duration = 30, category = "other_consumable", }, -- Bismuth Bitterling
        [220135] = { spellID = 456157, duration = 30, category = "other_consumable", }, -- Bloody Perch
        [220136] = { spellID = 444786, duration = 30, category = "other_consumable", }, -- Crystalline Sturgeon
        [220134] = { spellID = 456156, duration = 30, category = "other_consumable", }, -- Dilly-Dally Dace
        [222533] = { spellID = 444790, duration = 30, category = "other_consumable", }, -- Goldengill Trout
        [220138] = { spellID = 444788, duration = 30, category = "other_consumable", }, -- Nibbling Minnow
        [220139] = { spellID = 456595, duration = 30, category = "other_consumable", }, -- Whispering Stargazer
        [220152] = { spellID = 444802, duration = 30, category = "other_consumable", }, -- Cursed Ghoulfish
        [220146] = { spellID = 456587, duration = 30, category = "other_consumable", }, -- Regal Dottyback
        -- Dragonflight bait
        [198401] = { spellID = 383093, duration = 1800, category = "bait", }, -- Aileron Seamoth Lure
        [193896] = { spellID = 375787, duration = 1800, category = "bait", }, -- Cerulean Spinefish Lure
        [198043] = { spellID = 383095, duration = 1800, category = "bait", }, -- Islefin Dorado Lure
        [193893] = { spellID = 375779, duration = 1800, category = "bait", }, -- Scalebelly Mackerel Lure
        [193895] = { spellID = 375784, duration = 1800, category = "bait", }, -- Temporal Dragonhead Lure
        [193894] = { spellID = 375781, duration = 1800, category = "bait", }, -- Thousandbite Piranha Lure
        -- Shadowlands bait
        [173038] = { spellID = 331688, duration = 1800, category = "bait", }, -- Lost Sole Bait
        [173043] = { spellID = 331698, duration = 1800, category = "bait", }, -- Elysian Thade Bait
        [173040] = { spellID = 310665, duration = 1800, category = "bait", }, -- Silvergill Pike Bait
        [173041] = { spellID = 331695, duration = 1800, category = "bait", }, -- Pocked Bonefish Bait
        [173039] = { spellID = 331692, duration = 1800, category = "bait", }, -- Iridescent Amberjack Bait
        [173042] = { spellID = 331699, duration = 1800, category = "bait", }, -- Spinefin Piranha Bait
        -- Legion bait (these all have special requirements, but we can understant them as bait)
        [133702] = { spellID = 201805, duration = 600, category = "bait", }, -- Aromatic Murloc Slime
        [133703] = { spellID = 201806, duration = 600, category = "bait", }, -- Pearlescent Conch
        [133704] = { spellID = 201807, duration = 600, category = "bait", }, -- Rusty Queenfish Brooch
        [133710] = { spellID = 201813, duration = 600, category = "bait", }, -- Salmon Lure
        [133712] = { spellID = 201815, duration = 600, category = "bait", }, -- Frost Worm
        [133711] = { spellID = 201814, duration = 600, category = "bait", }, -- Swollen Murloc Egg
        [133713] = { spellID = 201816, duration = 600, category = "bait", }, -- Moosehorn Hook
        [133714] = { spellID = 201817, duration = 600, category = "bait", }, -- Silverscale Minnow
        [133715] = { spellID = 201818, duration = 600, category = "bait", }, -- Ancient Vrykul Ring
        [133716] = { spellID = 201819, duration = 600, category = "bait", }, -- Soggy Drakescale
        [133705] = { spellID = 201808, duration = 600, category = "bait", }, -- Rotten Fishbone
        [133707] = { spellID = 201810, duration = 600, category = "bait", }, -- Nightmare Nightcrawler
        [133708] = { spellID = 201811, duration = 600, category = "bait", }, -- Drowned Thistleleaf
        [133720] = { spellID = 201822, duration = 600, category = "bait", }, -- Demonic Detritus
        [133717] = { spellID = 201820, duration = 600, category = "bait", }, -- Enchanted Lure
        [133722] = { spellID = 201823, duration = 600, category = "bait", }, -- Axefish Lure
        [133795] = { spellID = 202131, duration = 600, category = "bait", }, -- Ravenous Fly
        -- Classic lures
        [67404] = { spellID = 98849, duration = 600, category = "lure", }, -- Glass Fishing Bobber
        [6529] = { spellID = 8087, duration = 600, category = "lure", }, -- Shiny Bauble
        [6530] = { spellID = 8088, duration = 600, category = "lure", }, -- Nightcrawlers
        [6811] = { spellID = 8532, duration = 600, category = "lure", }, -- Aquadynamic Fish Lens
        [6532] = { spellID = 8090, duration = 600, category = "lure", }, -- Bright Baubles
        [7307] = { spellID = 9092, duration = 600, category = "lure", }, -- Flesh Eating Worm
        [6533] = { spellID = 8089, duration = 600, category = "lure", }, -- Aquadynamic Fish Attractor
        [3486] = { spellID = 45731, duration = 600, category = "lure", }, -- Sharpened Fish Hook
        [6267] = { spellID = 87646, duration = 600, category = "lure", }, -- Feathered Lure
        [4600] = { spellID = 64401, duration = 3600, category = "lure", }, -- Glow Worm
        [6804] = { spellID = 95244, duration = 900, category = "lure", }, -- Heat-Treated Spinning Lure
        [124674] = { spellID = 185587, duration = 600, category = "lure", }, -- Day-Old Darkmoon Doughnut
        [118391] = { spellID = 174471, duration = 600, category = "lure", }, -- Worm Supreme
    },
}

-- Spell names
addon.const.fishingSpellName = (GetSpellInfo and GetSpellInfo(131474)) or "Fishing"

-- Frame references
addon.frames = {
    fishing = nil,
    buff = nil,
    tracker = nil,
    state = nil,
    config = nil,
    treasureAlert = nil,
    bagFullAlert = nil,
    audioRestore = nil,
}

-- Test API
addon._test = addon._test or {}
