local addonName, ns = ...
local Addon = ns.Addon
ns.Fishing = Addon:NewModule("Fishing", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")
ns.Fishing.const = ns.moduleConstants["Fishing"]
ns.Fishing.state = {
    current = {},
    fishingSessionGeneration = 0,
    suppressPendingBuffFailure = false,
    learningBuffItems = {},
    buffLearning = nil,
    buffItemLastUseAt = {},
    buffUnknownDurationSuppressed = {},
    precastConsumableSnapshot = nil,
    precastConsumableSnapshotGeneration = 0,
    precastStartedSwimming = false,
    precastSwimmingWatchTimer = nil,
    precastSwimmingAlerted = false,
    precastSwimmingGuidanceKind = nil,
    raftToyLastUseAt = {},
    wasRecentlySwimming = nil,
}

ns.moduleDefaults["Fishing"] = {
    global = {
        buffAuraByItem = {},
    },
    profile = {
        moduleEnabled = true,
        debug = false,
        traces = {},
        castByDoubleRightClick = true,
        castBySingleRightClickWhenFishing = false,
        castByHotkey = true,
        strikeByRightClick = false,
        strikeByDoubleRightClick = true,
        strikeByHotkey = true,
        selectedRaftToy = 0,
        selectedBobberToy = 0,
        useOversizedBobber = false,
        showBuffNotes = true,
        -- other
        closeWindowOnEscape = true,
        movementCancelsFishing = true,
        movementAmountToCancelFishing = 0,
        lingerExpirationEnabled = true,
        lingerDuration = 10,
        -- audio
        audioFocusEnabled = true,
        ambienceDuckingLevel = 35,
        musicDuckingLevel = 20,
        dialogDuckingLevel = 50,
        -- frame
        frameFocusEnabled = true,
	},
	char = {
        -- Tackle
        primaryPole = { isChecked = false, itemID = nil },
        underlightAngler = { isChecked = false, itemID = nil },
        -- Buffs
        buffs = {
            fooddrink = {
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
            },
            lure = {
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
            },
            bait = {
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
            },
            other_consumable = {
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
            },
        }
	},
}

