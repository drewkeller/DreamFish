local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local globalDB, profileDB, charDB
ns.FishingInitializers = ns.FishingInitializers or {}

local ArmFishingRightClickAction

function Fishing:OnModuleInitialize()
	self:Debug("Initializing")
    -- access the database within "Fishing" functions using self.db
    -- In local functions, use ns.FishingDB
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
    self:RegisterTackleWindowTab()
    self:CreateClickFrame()
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateKeybindsAfterCombat")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "CancelFishingForCombat")
    self:RegisterEvent("PLAYER_STARTED_MOVING", "CancelFishingForMovement")
    self:RegisterEvent("UNIT_SPELLCAST_START", "HandleFishingSpellcast")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "HandleFishingSpellcast")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "RefreshFishingClickAction")
    self:RegisterEvent("UNIT_AURA", "RefreshFishingClickAction")
    self:ApplyKeybinding()
    self:PrepareFishingClickAction()
end

function Fishing:OnModuleDisable()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("PLAYER_STARTED_MOVING")
    self:UnregisterEvent("UNIT_SPELLCAST_START")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self:UnregisterEvent("UNIT_AURA")
    self:Debug("Removing click frame (module disabled)")
    self:RemoveClickFrame()
end

function Fishing:PrepareFishingClickAction()
    if not self.clickFrame or InCombatLockdown() then
        return
    end
    ns.precast.ConfigureFishingClickAction()
end

function Fishing:RefreshFishingClickAction(_, unit)
    if type(unit) == "string" and unit ~= "player" then
        return
    end
    self:PrepareFishingClickAction()
end

function Fishing:CancelFishingSession(reason)
    self:SetFishingState(ns.fishing.states.CANCELLING, reason)
    if self.clickFrame and not InCombatLockdown() then
        ClearOverrideBindings(self.clickFrame)
    end
end

function Fishing:CancelFishingForCombat()
    self:CancelFishingSession("combat")
end

function Fishing:CancelFishingForMovement()
    self:CancelFishingSession("movement")
end

function Fishing:HandleFishingSpellcast(_, unit, _, spellID)
    if unit ~= "player" or spellID ~= ns.fishing.const.fishingSpellID then
        return
    end
    self:SetFishingState(ns.fishing.states.CASTING, "spellcast")
end

function Fishing:OnCastStarted(reason)
    self:SetFishingState(ns.fishing.states.PRECASTING, reason)
    self:SendMessage("FISHING_CAST_STARTED")
    ArmFishingRightClickAction(self.clickFrame)
end

ArmFishingRightClickAction = function(fishingFrame)
    if not fishingFrame then
        return
    end
    ns.precast.ConfigureFishingClickAction()
    SetOverrideBindingClick(fishingFrame, true, "BUTTON2", fishingFrame:GetName(), "RightButton")
    -- Show the secure frame so the current click release can trigger the secure action.
    fishingFrame:Show()
end

ns.precast.ConfigureFishingClickAction = ConfigureFishingClickAction
