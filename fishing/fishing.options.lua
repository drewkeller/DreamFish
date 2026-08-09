local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

ns.Fishing = { Defaults = {
	profile = {
		fishing = {
			moduleEnabled = true,
			debug = false,
            castByDoubleRightClick = true,
		},
	},
	char = {
		fishing = {},
	},
} }

local Fishing = DreamFish:NewModule("Fishing", ns.ModulePrototype, "AceConsole-3.0", "AceEvent-3.0")
Fishing:Configure({
	displayName = "Fishing",
	dbKey = "fishing",
	defaults = ns.Fishing.Defaults,
})

function Fishing:GetModuleOptions()
	return {
        castByDoubleRightClick = {
            type = "toggle",
            name = "Cast by double right click",
            desc = "Double right click to begin fishing.",
        },
    }
end
