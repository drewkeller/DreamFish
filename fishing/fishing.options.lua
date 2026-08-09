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

local Fishing = DreamFish:NewModule("Fishing", ns.ModulePrototype, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")
Fishing:Configure({
	displayName = "Fishing",
	dbKey = "fishing",
	defaults = ns.Fishing.Defaults,
})

function Fishing:GetModuleOptions()
	return {
        castingTriggers = {
            type = "group",
            name = "Casting triggers",
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
    }
end
