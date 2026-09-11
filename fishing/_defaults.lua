local addonName, ns = ...
local Addon = ns.Addon
ns.Fishing = Addon:NewModule("Fishing", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")
ns.Fishing.const = ns.moduleConstants["Fishing"]
ns.Fishing.state = {
    current = {},
    buffItemLastUseAt = {},
    pendingBuffObservation = {},
    buffUnknownDurationSuppressed = {},
}

ns.moduleDefaults["Fishing"] = {
    global = {
        buffAuraByItem = {
            ["238374"] = { spellID = 1237942, duration = 30, category="other_consumable", }, -- Tender Lumifin
        },
    },
    profile = {
        moduleEnabled = true,
        debug = false,
        traces = {},
        castByDoubleRightClick = true,
        castBySingleRightClickWhenFishing = false,
        castByHotkey = true,
        strikeByRightClick = false,
        strikeByHotkey = true,
        selectedRaftToy = 0,
        selectedBobberToy = 0,
        useOversizedBobber = false,
        showBuffNotes = true,
        -- other
        closeWindowOnEscape = true,
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

