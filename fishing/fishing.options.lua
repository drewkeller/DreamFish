local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

ns.Fishing.Defaults = {
    global = {
        buffAuraByItem = {
            ["238374"] = { spellID = 1237942, duration = 30, category="other_consumable", }, -- Tender Lumifin
        },
    },
    profile = {
		fishing = {
			moduleEnabled = true,
			debug = false,
            castByDoubleRightClick = true,
            castByHotkey = false,
            castHotkeyKeybind = nil,
        selectedRaftToy = 0,
        selectedBobberToy = 0,
        useOversizedBobber = false,
            -- other
            easyStrike = false,
            closeWindowOnEscape = true,
		},
	},
	char = {
		fishing = {
            -- Tackle
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
        },
	},
}

Fishing:Configure({
	displayName = "Fishing",
	dbKey = "fishing",
	defaults = ns.Fishing.Defaults,
	childGroups = "tab",
})

function Fishing:GetModuleOptions()
	return {
        modesTab = self:AddTab({
            type = "group",
            name = "Modes",
            args = {
                castingTriggers = {
                    type = "group",
                    name = "Casting triggers",
                    inline = true,
                    args = {
                        castByDoubleRightClick = self:AddOption({
                            type = "toggle",
                            name = "Double right click",
                            desc = "Double right click to begin fishing.",
                            width = "full",
                        }),
                        castByHotkey = self:AddOption({
                            type = "toggle",
                            name = "Hotkey",
                            desc = "Use a hotkey to begin fishing.",
                            width = "full",
                        }),
                        castHotkeyKeybind = self:AddOption({
                            type = "keybinding",
                            name = "",
                            desc = "Set the keybinding for the hotkey casting mode.",
                            width = 1.0,
                        }),
                    },
                },
            },
        }),
        tackleTab = self:AddTab({
            type = "group",
            name = "Tackle",
            args = {
                raftSection = {
                    type = "group",
                    name = "  ",
                    desc = "Settings for auto-casting a raft when fishing.",
                    inline = true,
                    order = 1,
                    args = {
                        selectedRaftToy = {
                            type = "select",
                            name = "Raft",
                            desc = "Choose the raft to be used when fishing. Applied automatically when casting the fishing line.",
                            order = 1,
                            values = function()
                                return DreamFish:BuildOwnedToyOptions(ns.Fishing.const.raftToyItemIDs, "No Raft")
                            end,
                            sorting = function()
                                return DreamFish:BuildOwnedToySortingKeys(ns.Fishing.const.raftToyItemIDs, "No Raft")
                            end,
                            width = 1.5,
                        },
                        applyRaft = {
                            type = "execute",
                            name = "Apply Raft",
                            desc = "Manually apply the selected raft now.",
                            order = 2,
                            func = "ApplyRaft",
                            width = 0.85,
                        },
                    },
                },
                bobberSection = {
                    type = "group",
                    name = "  ",
                    desc = "Settings for auto-casting a bobber when fishing.",
                    inline = true,
                    order = 2,
                    args = {
                        -- divider = {
                        --     type = "header",
                        --     name = "-----",
                        --     order = 0,
                        -- },
                        selectedBobberToy = {
                            type = "select",
                            name = "Bobber",
                            desc = "Choose the bobber to be used when fishing. Applied automatically when casting the fishing line.",
                            order = 1,
                            values = function()
                                return DreamFish:BuildOwnedToyOptions(ns.Fishing.const.bobberToyItemIDs, "Standard Bobber")
                            end,
                            sorting = function()
                                return DreamFish:BuildOwnedToySortingKeys(ns.Fishing.const.bobberToyItemIDs, "Standard Bobber")
                            end,
                            width = 1.5,
                        },
                        applyBobber = {
                            type = "execute",
                            name = "Apply Bobber",
                            desc = "Manually apply the selected bobber now.",
                            order = 2,
                            func = "ApplyBobber",
                            width = 0.85,
                        },
                        useOversizedBobber = {
                            type = "toggle",
                            name = "Use Oversized Bobber",
                            desc = "Also apply the oversized bobber to your selected bobber (adds another click to apply it)",
                            order = 3,
                            width = "full",
                        }
                    } -- Bobber section
                },
            },
        }), -- Tackle tab
    }
end
