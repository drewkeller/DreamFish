-- DreamFisher: Core Initialization
-- Addon setup, defaults, and global state

local addonName = "DreamFisher"
local frame = CreateFrame("Frame", addonName .. "Frame")
local addon = _G[addonName] or {}
_G[addonName] = addon

addon.frame = frame

-- Default configuration
addon.defaults = {
    autoLoot = true,
    enhancedSounds = true,
    treasureAlerts = true,
    bagAlerts = true,
    configCloseOnEscape = true,
    buffItems = {},
    buffAuraByItem = {
        ["238374"] = { spellID = 1237942, duration = 30 }, -- Tender Lumifin
    },
    selectedBobberToy = nil,
    selectedRaftToy = nil,
    useOversizedBobber = false,
    useUnderlightAngler = false,
    enableHookedLoot = false,
    castingModes = {
        doubleRightClick = true,
        singleRightClickConfig = false,
        singleRightClickDoubleStart = false,
        hotkey = false,
    },
    configWindowPosition = nil,
    refreshSeconds = 180,
    lowBagThreshold = 2,
    audioFocusLinger = 10,
    debugMode = true,
}

-- Global state variables
addon.state = {
    -- Auto-loot
    savedAutoLoot = nil,

    -- Fishing
    isFishing = false,
    isBobberActive = false,
    fishingStartTime = 0,
    fishingLootInProgress = false,

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
    fishingExpireSeconds = 35,
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
    pendingBuffObservation = nil,
    uiBuffCursorDragState = nil,
}

-- Constants
addon.const = {
    maxBuffSlots = 6,
    maxFishingCastSeconds = 20,
    buffPreRefreshSafetySeconds = 2,
    patientlyRewardedSpellID = 1235378,
    fishingSpellID = 131474,
    bobberToyItemIDs = {
        180993, -- Bat Visage
        142528, -- Can of Worms
        147307, -- Carved Wooden Helm
        142529, -- Cat Head
        147312, -- Demon Noggin
        147308, -- Enchanted Bobber
        147309, -- Face of the Forest
        147310, -- Floating Totem
        142532, -- Murloc Head
        147311, -- Replica Gondola
        142531, -- Squeaky Duck
        142530, -- Tugboat
        143662, -- Wooden Pepe
    },
    raftToyItemIDs = {
        85500, -- Angler's Fishing Raft
        198428, -- Tuskarr Dinghy
    },
    knownBuffItems = {
        [238374] = { spellID = 1237942, duration = 30, }, -- Tender Lumifin
        [238365] = { spellID = 1237942, duration = 30, }, -- Sin'dorei Swarmer
        [238371] = { spellID = 1237942, duration = 30, }, -- Arcane Wyrmfish
        [238382] = { spellID = 1237942, duration = 30, }, -- Gore Guppy
        [238366] = { spellID = 1237942, duration = 30, }, -- Lynxfish
        [238367] = { spellID = 1235216, duration = 30, }, -- Root Crab
        [238369] = { spellID = 1235216, duration = 30, }, -- Bloomtail Minnow
        [238370] = { spellID = 1237942, duration = 30, }, -- Shimmer Spinefish
        [238381] = { spellID = 1237942, duration = 30, }, -- Hollow Grouper
        [241316] = { spellID = 1236763, duration = 3600, }, -- Haranir Phial of Perception (2)
        [241317] = { spellID = 1236763, duration = 1800, }, -- Haranir Phial of Perception (1)
        [242298] = { spellID = 1269152, duration = 3600, }, -- Sanguithorn Tea
        [262651] = { spellID = 1284999, duration = 600, }, -- Pointed Spikesnail
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
