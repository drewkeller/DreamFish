local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local globalDB, profileDB, charDB

local ArmFishingRightClickAction

function Fishing:OnModuleInitialize()
	self:Debug("Initializing")
    -- access the database within "Fishing" functions using self.db
    -- In local functions, use ns.FishingDB
    self.db = DreamFish.db:RegisterNamespace("fishing", ns.Fishing.Defaults)
    ns.FishingDB = self.db

    globalDB = ns.FishingDB.global
    profileDB = ns.FishingDB.profile
    charDB = ns.FishingDB.char
    for _, initializerFunc in ipairs(ns.FishingInitializers) do
        initializerFunc(self)
    end

    self.hotkey = profileDB.castHotkeyKeybind
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
