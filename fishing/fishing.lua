local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local Fishing = DreamFish:GetModule("Fishing")

local ArmFishingRightClickAction

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
    ArmFishingRightClickAction(self.clickFrame)
end

ArmFishingRightClickAction = function(fishingFrame)
    if not fishingFrame then
        return false, false
    end
    local configured, castArmed = ns.precast.ConfigureFishingClickAction()
    if configured == false then
        return false, false
    end
    SetOverrideBindingClick(fishingFrame, true, "BUTTON2", fishingFrame:GetName(), "RightButton")
    -- Show the secure frame so the current click release can trigger the secure action.
    fishingFrame:Show()
    return true, castArmed and true or false
end

ns.precast.ConfigureFishingClickAction = ConfigureFishingClickAction
