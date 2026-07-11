-- DreamFisher: Audio and Visual Alerts

local addonName = "DreamFisher"
local addon = _G["DreamFisher"]
local PrintMessage = addon.PrintMessage

local function CreateTreasureAlertFrame()
    if addon.frames.treasureAlert then
        return addon.frames.treasureAlert
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

    addon.frames.treasureAlert = alert
    return addon.frames.treasureAlert
end

local function ShowPatientTreasureAlert(subtext, force)
    if not force and (not addon.db or not addon.db.treasureAlerts) then
        return
    end

    local now = GetTime()
    if not force and now - addon.state.lastAlertTime < 2 then
        return
    end
    addon.state.lastAlertTime = now

    local alert = CreateTreasureAlertFrame()
    local icon = GetSpellTexture and GetSpellTexture(addon.const.patientlyRewardedSpellID)
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

local function CreateBagFullAlertFrame()
    if addon.frames.bagFullAlert then
        return addon.frames.bagFullAlert
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

    addon.frames.bagFullAlert = alert
    return addon.frames.bagFullAlert
end

local function ShowBagFullAlert(force)
    local shouldShowBagAlert = force or (addon.db and addon.db.bagAlerts)
    local shouldShowReagentBagAlert = force or (addon.db and addon.db.reagentBagAlerts)
    if not shouldShowBagAlert and not shouldShowReagentBagAlert then
        return
    end

    local alert = CreateBagFullAlertFrame()
    local regularFree = addon.utils.GetFreeBagSlots(false)
    local reagentFree = addon.utils.GetFreeReagentBagSlots()
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

    addon.audio.PlayWarningCue()
end

-- Export to addon
addon.alerts = addon.alerts or {}
addon.alerts.CreateTreasureAlertFrame = CreateTreasureAlertFrame
addon.alerts.ShowPatientTreasureAlert = ShowPatientTreasureAlert
addon.alerts.CreateBagFullAlertFrame = CreateBagFullAlertFrame
addon.alerts.ShowBagFullAlert = ShowBagFullAlert
