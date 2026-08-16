local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local globalDB, profileDB, charDB
local function Initialize()
    globalDB = ns.FishingDB.global
    profileDB = ns.FishingDB.profile
    charDB = ns.FishingDB.char
end
ns.FishingInitializers = ns.FishingInitializers or {}
table.insert(ns.FishingInitializers, Initialize)


local lastClickTime = 0
local doubleClickDelay = 0.25
local hideTimerHandle = nil
local clickFrameName = "DreamFishSecureFishingFrame"
local cleanupEventFrame = CreateFrame("Frame")

cleanupEventFrame:SetScript("OnEvent", function()
    Fishing:RemoveClickFrame()
end)

function Fishing:CreateClickFrame()
    -- Create a secure frame to intercept clicks for fishing
    if not self.clickFrame then
        self.clickFrame = CreateFrame("Button", clickFrameName, UIParent, "SecureActionButtonTemplate")
    end

    -- if hotkey is enabled and no mouse interaction, we don't need the frame to cover the screen
    self.clickFrame:ClearAllPoints()
    self.clickFrame:SetAllPoints(UIParent)
    self.clickFrame:SetFrameStrata("BACKGROUND")
    self.clickFrame:SetAttribute("type", "spell")
    self.clickFrame:SetAttribute("spell", "Fishing")
    self.clickFrame:SetAttribute("macrotext", nil)
    self.clickFrame:RegisterForClicks("RightButtonDown", "RightButtonUp")
    self.clickFrame:SetPropagateMouseClicks(true)
    self.clickFrame:SetPropagateMouseMotion(true)
    self.clickFrame:Hide()
    self.clickFrame:EnableMouse(false)
    self.clickFrame:SetMouseClickEnabled(false)
    self.clickFrame:SetMouseMotionEnabled(false)

    Fishing:HookMouseDown()
    Fishing:HookPreClickWithHandler()
end

function Fishing:HookMouseDown()
    if not self:IsHooked(WorldFrame, "OnMouseDown") then
        self:SecureHookScript(WorldFrame, "OnMouseDown", "HandleMouseDown")
    end
end

-- Handle player right clicks
function Fishing:HandleMouseDown(_, button)
    if button ~= "RightButton" then return end
    if not self.clickFrame or InCombatLockdown() then return end

    if self:IsDoubleClick() then
        if not profileDB.castByDoubleRightClick then
            self:Debug("Double click detected but double right click casting is disabled")
            return
        end
        self:Debug("Double right click detected")
        self:OnCastStarted("Double right click")
    else
        self:Debug("Right click detected")
    end
end

-- Handle hotkey "pre-click"
function Fishing:HookPreClickWithHandler()
    if not self:IsHooked(self.clickFrame, "PreClick") then
        self.clickFrame:SetScript("PreClick", function(_, button, down)
            if InCombatLockdown() then return end
            if button ~= "RightButton" or not down then return end
            if not profileDB.castByHotkey then
                self:Debug("PreClick detected but hotkey casting is disabled")
                return
            end
            self:Debug("PreClick detected")
            self:OnCastStarted("hotkey")
        end)
    end
end

function Fishing:IsDoubleClick()
    local currentTime = GetTime()
    local isDoubleClick = false
    if (currentTime - lastClickTime) <= doubleClickDelay then
        -- Show the secure intercept frame to catch the up-click
        self.clickFrame:EnableMouse(true)
        self.clickFrame:SetMouseClickEnabled(true)
        self.clickFrame:SetMouseMotionEnabled(true)
        self.clickFrame:Show()

        isDoubleClick = true

        -- Queue the frame cleanup
        if hideTimerHandle then self:CancelTimer(hideTimerHandle) end
        hideTimerHandle = self:ScheduleTimer("HideClickFrame", 0.1)
    end

    lastClickTime = currentTime
    return isDoubleClick
end

function Fishing:HideClickFrame()
    if not InCombatLockdown() then
        if not profileDB.castBySingleRightClickWhenFishing or not self:IsInFishingSession() then
            ClearOverrideBindings(self.clickFrame)
        end
        self.clickFrame:Hide()
        self.clickFrame:SetMouseMotionEnabled(false)
    end
    hideTimerHandle = nil
end

function Fishing:ReleaseClickCapture()
    if not self.clickFrame or InCombatLockdown() then
        return
    end

    if hideTimerHandle then
        self:CancelTimer(hideTimerHandle)
        hideTimerHandle = nil
    end

    ClearOverrideBindings(self.clickFrame)
    self.clickFrame:Hide()
    self.clickFrame:SetMouseClickEnabled(false)
    self.clickFrame:SetMouseMotionEnabled(false)
    self.clickFrame:EnableMouse(false)
end

function Fishing:RemoveClickFrame()
    self:Unhook(WorldFrame, "OnMouseDown")

    if not self.clickFrame then return end

    if InCombatLockdown() then
        cleanupEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    if hideTimerHandle then
        self:CancelTimer(hideTimerHandle)
        hideTimerHandle = nil
    end

    ClearOverrideBindings(self.clickFrame)
    self.clickFrame:RegisterForClicks()
    self.clickFrame:SetScript("PreClick", nil)
    self.clickFrame:SetFrameStrata("BACKGROUND")
    self.clickFrame:SetAttribute("type", nil)
    self.clickFrame:SetAttribute("spell", nil)
    self.clickFrame:SetAttribute("macrotext", nil)
    self.clickFrame:SetPropagateMouseClicks(true)
    self.clickFrame:SetPropagateMouseMotion(true)
    self.clickFrame:SetMouseClickEnabled(false)
    self.clickFrame:SetMouseMotionEnabled(false)
    self.clickFrame:EnableMouse(false)
    self.clickFrame:Hide()
    self.clickFrame:ClearAllPoints()
    cleanupEventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

function Fishing:UpdateKeybindsAfterCombat()
    self:ApplyKeybinding()
end

function Fishing:ApplyKeybinding()
    if InCombatLockdown() then return end

    if self.hotkey then
        ClearOverrideBindings(self.clickFrame)

        SetBindingClick(self.hotkey, clickFrameName, "RightButton")
    end
end
