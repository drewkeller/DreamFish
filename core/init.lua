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
    buffAuraByItem = {},
    configWindowPosition = nil,
    refreshSeconds = 180,
    lowBagThreshold = 2,
    audioFocusLinger = 10,
    debugMode = true,
    worldRightClickModifier = "NONE",
    worldRightClickModifierUserSet = false,
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
    doubleClickWindow = 0.25,

    -- Alerts
    lastBagWarning = 0,
    lastAlertTime = 0,
    lastSoundTime = 0,
    patientAuraActive = false,

    -- Fishing tracking
    fishingStartGraceUntil = 0,
    fishingExpireSeconds = 35,

    -- Buff management
    lastBuffCheckTime = 0,
    buffCheckInterval = 1,
    buffItemLastUseAt = {},
    buffReminderCooldown = 12,
    buffItemLastReminderAt = {},
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
