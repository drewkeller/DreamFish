local addonName, ns = ...
local Addon = ns.Addon
local LootTracker = ns.LootTracker

local profileDB
local state = {
    isFishing = false,
    lastAlertTime = 0,
    patientAuraActive = false,
    lastBagWarning = 0,
}

local patientlyRewardedSpellID = 1235378

LootTracker:RegisterTraceSource("alerts")

local function Trace(message)
    LootTracker:Trace("alerts", message)
end

LootTracker:RegisterOnModuleInitialize(function(self)
    profileDB = self.db.profile
end)

LootTracker:RegisterOnModuleRegisterEvents(function(self)
    self:RegisterEvent("UNIT_AURA", "UNIT_AURA")
    Addon:RegisterMessage("FISHING_SESSION_STARTED", function(...) self:Alerts_FISHING_SESSION_STARTED(...) end)
    Addon:RegisterMessage("FISHING_SESSION_ENDED",   function(...) self:Alerts_FISHING_SESSION_ENDED(...) end)
end)

LootTracker:RegisterOnModuleUnregisterEvents(function(self)
    self:UnregisterEvent("UNIT_AURA")
    Addon:UnregisterMessage("FISHING_SESSION_STARTED")
    Addon:UnregisterMessage("FISHING_SESSION_ENDED")
end)

function LootTracker:Alerts_FISHING_SESSION_STARTED(...)
    Trace("Fishing session started.")
    state.isFishing = true
end

function LootTracker:Alerts_FISHING_SESSION_ENDED(...)
    Trace("Fishing session ended.")
    state.isFishing = false
end

local function CreateTreasureAlertFrame()
    if ns.frames.treasureAlert then
        return ns.frames.treasureAlert
    end

    local alert = CreateFrame("Frame", addonName .. "TreasureAlertFrame", UIParent, "BackdropTemplate")
    alert:SetAllPoints(UIParent)
    alert:SetFrameStrata("FULLSCREEN_DIALOG")
    alert:EnableMouse(false)
    alert:Hide()

    alert:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 36,
        insets = { left = 10, right = 10, top = 10, bottom = 10 },
    })
    alert:SetBackdropColor(0.12, 0.08, 0, 0.92)
    alert:SetBackdropBorderColor(1, 0.9, 0.15, 1)

    alert.flash = alert:CreateTexture(nil, "BACKGROUND")
    alert.flash:SetAllPoints(UIParent)
    alert.flash:SetColorTexture(1, 0.82, 0.2, 0.24)

    alert.icon = alert:CreateTexture(nil, "OVERLAY")
    alert.icon:SetSize(96, 96)
    alert.icon:SetPoint("CENTER", 0, 78)

    alert.title = alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    alert.title:SetPoint("CENTER", 0, -22)
    alert.title:SetTextColor(1, 0.94, 0.25, 1)

    alert.subtext = alert:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    alert.subtext:SetPoint("TOP", alert.title, "BOTTOM", 0, -10)
    alert.subtext:SetTextColor(1, 1, 1, 1)

    ns.frames.treasureAlert = alert
    return ns.frames.treasureAlert
end

local function ShowPatientTreasureAlert(subtext, force)
    if not force and (not profileDB or not profileDB.patientTreasureAlert) then
        return
    end

    local now = GetTime()
    if not force and now - state.lastAlertTime < 2 then
        return
    end
    state.lastAlertTime = now

    local alert = CreateTreasureAlertFrame()
    local icon = GetSpellTexture and GetSpellTexture(patientlyRewardedSpellID)
    if icon then
        alert.icon:SetTexture(icon)
    else
        alert.icon:SetTexture("Interface\\Icons\\INV_Misc_TreasureChest03a")
    end

    alert.title:SetText("Patient Treasure Caught!")
    alert.subtext:SetText(subtext or "Patiently Rewarded")
    alert:Show()

    alert.timeLeft = 2.5
    alert:SetScript("OnUpdate", function(self, elapsed)
        self.timeLeft = self.timeLeft - elapsed
        if self.timeLeft <= 0 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)

    if type(PlaySound) == "function" and SOUNDKIT then
        local primary = SOUNDKIT.READY_CHECK
            or SOUNDKIT.UI_EPICLOOT_TOAST
            or SOUNDKIT.IG_MAINMENU_OPEN
        local accent = SOUNDKIT.RAID_WARNING
            or SOUNDKIT.UI_RaidBossEmoteWarning
            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON

        if primary then
            PlaySound(primary, "Master")
            if C_Timer and C_Timer.After then
                C_Timer.After(0.55, function()
                    PlaySound(primary, "Master")
                end)
            end
        end
        if accent and C_Timer and C_Timer.After then
            C_Timer.After(1.10, function()
                PlaySound(accent, "Master")
            end)
        elseif accent then
            PlaySound(accent, "Master")
        end
    end
end

local function HasPatientlyRewardedAura()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(patientlyRewardedSpellID) ~= nil
    end
    if AuraUtil and AuraUtil.FindAuraBySpellID then
        return AuraUtil.FindAuraBySpellID(patientlyRewardedSpellID, "player", "HELPFUL") ~= nil
    end
    return false
end

function LootTracker:UNIT_AURA(_, event, ...)
    local arg1, arg2 = ...
    if type(arg1) ~= "string" or arg1 ~= "player" then return end

    local hasAura = HasPatientlyRewardedAura()
    if hasAura and not state.patientAuraActive then
        state.patientAuraActive = true
            ShowPatientTreasureAlert("Patiently Rewarded")
    elseif not hasAura then
        state.patientAuraActive = false
    end
end

local function CreateBagFullAlertFrame()
    if ns.frames.bagFullAlert then
        return ns.frames.bagFullAlert
    end

    local alert = CreateFrame("Frame", addonName .. "BagFullAlertFrame", UIParent, "BackdropTemplate")
    alert:SetAllPoints(UIParent)
    alert:SetFrameStrata("FULLSCREEN_DIALOG")
    alert:EnableMouse(false)
    alert:Hide()

    alert:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 28,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    alert:SetBackdropColor(0.08, 0.08, 0.08, 0.88)
    alert:SetBackdropBorderColor(0.72, 0.72, 0.72, 1)

    alert.title = alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    alert.title:SetPoint("CENTER", 0, 6)
    alert.title:SetTextColor(0.95, 0.95, 0.95, 1)

    alert.subtext = alert:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    alert.subtext:SetPoint("TOP", alert.title, "BOTTOM", 0, -10)
    alert.subtext:SetTextColor(0.86, 0.86, 0.86, 1)

    ns.frames.bagFullAlert = alert
    return ns.frames.bagFullAlert
end

local function ShowBagFullAlert()
    local alert = CreateBagFullAlertFrame()
    local regularFree = ns.Utils.GetFreeBagSlots(false)
    local reagentFree = ns.Utils.GetFreeReagentBagSlots()
    alert.title:SetText("Bag space is low!")
    alert.subtext:SetText("Regular slots: " .. tostring(regularFree) .. "\nReagent slots: " .. tostring(reagentFree))
    alert:Show()

    alert.timeLeft = 2.2
    alert:SetScript("OnUpdate", function(self, elapsed)
        self.timeLeft = self.timeLeft - elapsed
        if self.timeLeft <= 0 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)
end

local function CheckBagSpace()
    local shouldCheckRegular = profileDB.normalBagAlertEnabled
    local shouldCheckReagent = profileDB.reagentBagAlertEnabled
    if not shouldCheckRegular and not shouldCheckReagent then
        return
    end

    local threshold = tonumber(profileDB.normalBagAlertThreshold)
    local reagentThreshold = tonumber(profileDB.reagentBagAlertThreshold)
    local regularFree = shouldCheckRegular and ns.Utils.GetFreeBagSlots(false) or nil
    local reagentFree = shouldCheckReagent and ns.Utils.GetFreeReagentBagSlots() or nil
    local isRegularLow = regularFree ~= nil and regularFree <= threshold
    local isReagentLow = reagentFree ~= nil and reagentFree <= reagentThreshold

    if isRegularLow or isReagentLow then
        local now = GetTime()
        if now - state.lastBagWarning >= tonumber(profileDB.bagAlertThrottle) then
            state.lastBagWarning = now

            Addon:Alert(ns.SystemColor.YELLOW,
            string.format("Low bag space! Bags: %s free, Reagent: %s free",
                tostring(regularFree or "n/a"), tostring(reagentFree or "n/a"))
            )

            if profileDB.bagAlertPlaySound then
                ns.Utils.PlayWarningCue()
            end

            if profileDB.bagAlertShowFullScreen then
                ShowBagFullAlert()
            end
        end
    else
        Trace("Bag space is sufficient. Regular free: " .. tostring(regularFree or "n/a") .. ", Reagent free: " .. tostring(reagentFree or "n/a"))
    end
end

function LootTracker:Alerts_BAG_UPDATE_DELAYED(...)
    if profileDB.bagAlertOnlyWhenFishing and not state.isFishing then
        return
    end
    Trace("Alerts_BAG_UPDATE_DELAYED called")
    CheckBagSpace()
end
