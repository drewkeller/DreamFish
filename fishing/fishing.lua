local addonName = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local Fishing = DreamFish:GetModule("Fishing")

function Fishing:OnModuleInitialize()
	self:Debug("Initializing")
    self.hotkey = self:GetProfileDB().castHotkeyKeybind
end
