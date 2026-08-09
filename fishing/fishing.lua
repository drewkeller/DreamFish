local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local Fishing = DreamFish:GetModule("Fishing")

function Fishing:OnModuleInitialize()
	self:Debug("Initializing")
    self.hotkey = self:GetProfileDB().castHotkeyKeybind
end

function Fishing:OnModuleEnable()
    self:CreateClickFrame()
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateKeybindsAfterCombat")
    self:ApplyKeybinding()
end

function Fishing:OnModuleDisable()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:Debug("Removing click frame (module disabled)")
    self:RemoveClickFrame()
end

function Fishing:OnCastStarted()
    self:Debug("OnCastStarted")
    self:SendMessage("FISHING_CAST_STARTED")
end
