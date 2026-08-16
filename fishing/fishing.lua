local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local globalDB, profileDB, charDB
ns.FishingInitializers = ns.FishingInitializers or {}

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
    self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", "CancelFishingForMount")
    self:RegisterEvent("UNIT_SPELLCAST_START", "HandleFishingSpellcast")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "HandleFishingSpellcast")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "HandleFishingSpellcast")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "RefreshFishingClickAction")
    self:RegisterEvent("UNIT_AURA", "RefreshFishingClickAction")
    self:ApplyKeybinding()
    self:PrepareFishingClickAction()
end

function Fishing:OnModuleDisable()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("PLAYER_STARTED_MOVING")
    self:UnregisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    self:UnregisterEvent("UNIT_SPELLCAST_START")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
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

function Fishing:RefreshFishingClickAction(event, unit)
    if type(unit) == "string" and unit ~= "player" then
        return
    end
    if ns.fishing.state.current == ns.fishing.states.IDLE then
        self:PrepareFishingClickAction()
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        self:RefreshPoleBorders()
        self:Debug("Equipment changed")
    elseif event == "UNIT_AURA" then
        self:Debug("Auras changed")
    end
end

function Fishing:CancelFishingSession(reason)
    self:SetFishingState(ns.fishing.states.CANCELLING, reason)
    self:ReleaseClickCapture()
    self:SetFishingState(ns.fishing.states.IDLE, "After cancel: " .. tostring(reason))
end

function Fishing:CancelFishingForCombat()
    self:CancelFishingSession("combat")
end

function Fishing:CancelFishingForMovement()
    self:CancelFishingSession("movement")
end

function Fishing:CancelFishingForMount()
    if IsMounted() then
        self:CancelFishingSession("mounted")
    end
end

function Fishing:HandleFishingSpellcast(event, unit, ...)
    if unit ~= "player" then
        return
    end

    -- scan all arguments for a spell ID
    local spellID
    for index = select("#", ...), 1, -1 do
        local value = select(index, ...)
        if type(value) == "number" then
            spellID = value
            break
        end
    end

    if spellID ~= ns.fishing.const.fishingSpellID then
        return
    end

    --self:Debug(event .. " detected for Fishing")
    self:SetFishingState(ns.fishing.states.CASTING, "spellcast")
end

function Fishing:OnCastStarted(reason)
    self:SetFishingState(ns.fishing.states.PRECASTING, reason)
    self:SendMessage("FISHING_CAST_STARTED")
    self:PrepareFishingClickAction()
    self:Debug("OnCastStarted: " .. tostring(reason))

    -- Set the secure action to trigger on right-clicks of the secure frame.
    -- The secure frame is shown when the player right-clicks, so the current click release will trigger the secure action.
    SetOverrideBindingClick(self.clickFrame, true, "BUTTON2", self.clickFrame:GetName(), "RightButton")
    -- Show the secure frame so the current click release can trigger the secure action.
    self.clickFrame:Show()
end

ns.precast.ConfigureFishingClickAction = ConfigureFishingClickAction
