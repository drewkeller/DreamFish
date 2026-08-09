local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

ns.Fishing = { Defaults = {
	profile = {
		fishing = {
			moduleEnabled = true,
			debug = false,
            castByDoubleRightClick = true,
            castByHotkey = false,
            castHotkeyKeybind = nil,
		},
	},
	char = {
		fishing = {},
	},
} }

ns.const = {
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
    oversizedBobberItemID = 202207,
}

local Fishing = DreamFish:NewModule("Fishing", ns.ModulePrototype, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")
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
                            values = DreamFish:BuildOwnedToyOptions(ns.const.raftToyItemIDs, "No Raft"),
                            sorting = DreamFish:BuildOwnedToyOptionsKeys(ns.const.raftToyItemIDs, true),
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
                            values = DreamFish:BuildOwnedToyOptions(ns.const.bobberToyItemIDs, "Standard Bobber"),
                            sorting = DreamFish:BuildOwnedToyOptionsKeys(ns.const.bobberToyItemIDs, true),
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
