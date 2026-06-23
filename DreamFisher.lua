local addonName = "DreamFisher"
local frame = CreateFrame("Frame", addonName .. "Frame")
local addon = _G[addonName] or {}
_G[addonName] = addon

addon.frame = frame

local defaults = {
    autoLoot = true,
    enhancedSounds = true,
    treasureAlerts = true,
    buffItem1 = nil,
    buffItem2 = nil,
    refreshSeconds = 180,
    lowBagThreshold = 2,
    audioFocusLinger = 10,
}

local savedAutoLoot = nil
local isFishing = false
local isBobberActive = false
local fishingStartTime = 0
local lastBagWarning = 0
local lastAlertTime = 0
local lastRightClickTime = 0
local lastSoundTime = 0
local doubleClickWindow = 0.25
local fishingStartGraceUntil = 0
local fishingExpireSeconds = 35
local patientlyRewardedSpellID = 1235378
local fishingSecureFrame = nil
local fishingTrackerFrame = nil
local originalAutoLootState = nil
local fishingStateFrame = nil
local savedFishingAudioCVars = nil
local audioLingerGeneration = 0
local audioRestoreFrame = nil
local audioRestoreAt = nil
local treasureAlertFrame = nil
local patientAuraActive = false
local fishingSpellID = 131474
local fishingLootInProgress = false

local function CopyDefaults(source, target)
    for k, v in pairs(source) do
        if target[k] == nil then
            target[k] = v
        end
    end
end

local function Clamp(value, min, max)
    if value == nil then
        return min
    end
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

local function PrintMessage(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF7FFFDADreamFisher|r " .. msg)
    end
end

local function CreateTreasureAlertFrame()
    if treasureAlertFrame then
        return treasureAlertFrame
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

    treasureAlertFrame = alert
    return treasureAlertFrame
end

local function ShowPatientTreasureAlert(subtext, force)
    if not force and (not addon.db or not addon.db.treasureAlerts) then
        return
    end

    local now = GetTime()
    if not force and now - lastAlertTime < 2 then
        return
    end
    lastAlertTime = now

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

local function CreateSecureFishingFrame()
    if fishingSecureFrame then
        return fishingSecureFrame
    end

    fishingSecureFrame = CreateFrame("Button", "DreamFisherSecureFishingButton", UIParent, "SecureActionButtonTemplate")
    fishingSecureFrame:SetAllPoints(UIParent)
    fishingSecureFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    fishingSecureFrame:SetAttribute("type", "spell")
    fishingSecureFrame:SetAttribute("spell", "Fishing")
    fishingSecureFrame:RegisterForClicks("AnyDown")
    fishingSecureFrame:Hide()
    fishingSecureFrame:HookScript("OnClick", function()
        if not InCombatLockdown() then
            ClearOverrideBindings(fishingSecureFrame)
        end
    end)

    return fishingSecureFrame
end

local function CreateTrackerFrame()
    if fishingTrackerFrame then
        return fishingTrackerFrame
    end

    fishingTrackerFrame = CreateFrame("Frame")
    fishingTrackerFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    fishingTrackerFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if fishingSecureFrame and not InCombatLockdown() then
                ClearOverrideBindings(fishingSecureFrame)
            end
        end
    end)

    return fishingTrackerFrame
end

-- Forward declarations so closures inside CreateFishingStateFrame can
-- reference functions that are defined later in the file.
local EnableTemporaryAutoLoot
local RestoreOriginalAutoLoot
local EnableFishingAudioFocus
local RestoreFishingAudioFocus
local RestoreFishingAudioFocusAfterLinger
local CheckBagSpace

local function CreateFishingStateFrame()
    if fishingStateFrame then
        return fishingStateFrame
    end

    fishingStateFrame = CreateFrame("Frame")
    fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_START")
    fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
    fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
    fishingStateFrame:RegisterEvent("PLAYER_STARTED_MOVING")
    fishingStateFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

    fishingStateFrame:SetScript("OnEvent", function(self, event, unit, ...)
        if event ~= "PLAYER_REGEN_DISABLED" and event ~= "PLAYER_STARTED_MOVING" and unit ~= "player" then
            return
        end

        -- Use spellID from event args for reliable detection (3rd arg after event, unit).
        -- UnitCastingInfo can return nil at the exact moment the event fires.
        local _, spellID = ...
        local isFishingSpell = (spellID == fishingSpellID)

        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            if isFishingSpell then
                -- Cancel any pending linger restore from a previous catch
                audioLingerGeneration = audioLingerGeneration + 1
                audioRestoreAt = nil
                if audioRestoreFrame then
                    audioRestoreFrame:Hide()
                end
                isFishing = true
                isBobberActive = false
                fishingStartTime = GetTime()
                fishingStartGraceUntil = fishingStartTime + 1.5
                EnableTemporaryAutoLoot()
                EnableFishingAudioFocus()
                -- Start periodic bag space monitoring
                fishingStateFrame:SetScript("OnUpdate", function()
                    CheckBagSpace()
                    if isBobberActive and savedFishingAudioCVars ~= nil and fishingStartTime > 0 and (GetTime() - fishingStartTime) > fishingExpireSeconds then
                        -- Cast expired with no loot/cancel event; restore immediately.
                        isFishing = false
                        isBobberActive = false
                        fishingLootInProgress = false
                        audioRestoreAt = nil
                        if audioRestoreFrame then
                            audioRestoreFrame:Hide()
                        end
                        RestoreFishingAudioFocus()
                        fishingStateFrame:SetScript("OnUpdate", nil)
                    end
                end)
            elseif (isFishing or isBobberActive) and savedFishingAudioCVars ~= nil and GetTime() > fishingStartGraceUntil then
                -- Any other player cast effectively cancels fishing.
                isFishing = false
                isBobberActive = false
                fishingLootInProgress = false
                audioRestoreAt = nil
                if audioRestoreFrame then
                    audioRestoreFrame:Hide()
                end
                RestoreFishingAudioFocus()
                fishingStateFrame:SetScript("OnUpdate", nil)
            end
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if (isFishingSpell and isFishing) or (savedFishingAudioCVars ~= nil and isFishing) then
                -- Cast bar ended; bobber is now in water. Keep fishing active.
                isFishing = true
                isBobberActive = true
                -- Audio stays low until loot closes + linger expires
                fishingStateFrame:SetScript("OnUpdate", function()
                    CheckBagSpace()
                    if isBobberActive and savedFishingAudioCVars ~= nil and fishingStartTime > 0 and (GetTime() - fishingStartTime) > fishingExpireSeconds then
                        -- Cast expired with no loot/cancel event; restore immediately.
                        isFishing = false
                        isBobberActive = false
                        fishingLootInProgress = false
                        audioRestoreAt = nil
                        if audioRestoreFrame then
                            audioRestoreFrame:Hide()
                        end
                        RestoreFishingAudioFocus()
                        fishingStateFrame:SetScript("OnUpdate", nil)
                    end
                end)
            end
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
            if (isFishingSpell and savedFishingAudioCVars ~= nil) or (savedFishingAudioCVars ~= nil and isFishing) then
                isFishing = false
                isBobberActive = false
                fishingLootInProgress = false
                audioRestoreAt = nil
                if audioRestoreFrame then
                    audioRestoreFrame:Hide()
                end
                RestoreFishingAudioFocus()
                fishingStateFrame:SetScript("OnUpdate", nil)
            end
        elseif event == "PLAYER_STARTED_MOVING" then
            -- Moving should always break the fishing audio focus immediately.
            if savedFishingAudioCVars ~= nil then
                isFishing = false
                isBobberActive = false
                fishingLootInProgress = false
                audioRestoreAt = nil
                if audioRestoreFrame then
                    audioRestoreFrame:Hide()
                end
                RestoreFishingAudioFocus()
                fishingStateFrame:SetScript("OnUpdate", nil)
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            -- Cancel fishing if combat starts
            if isFishing or savedFishingAudioCVars ~= nil then
                isFishing = false
                isBobberActive = false
                fishingLootInProgress = false
                RestoreOriginalAutoLoot()
                audioRestoreAt = nil
                if audioRestoreFrame then
                    audioRestoreFrame:Hide()
                end
                RestoreFishingAudioFocus()
                fishingStateFrame:SetScript("OnUpdate", nil)
            end
        end
    end)

    return fishingStateFrame
end

EnableTemporaryAutoLoot = function()
    if addon.db and addon.db.autoLoot then
        local current = GetCVar("autoLootDefault")
        if savedAutoLoot == nil then
            savedAutoLoot = current
        end
        SetCVar("autoLootDefault", "1")
    end
end

RestoreOriginalAutoLoot = function()
    if addon.db and addon.db.autoLoot and savedAutoLoot ~= nil then
        SetCVar("autoLootDefault", savedAutoLoot)
        savedAutoLoot = nil
    end
end

EnableFishingAudioFocus = function(force)
    if not force and (not addon.db or not addon.db.enhancedSounds) then
        return
    end
    if savedFishingAudioCVars ~= nil then
        return
    end
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then
        return
    end

    savedFishingAudioCVars = {
        ambience = GetCVar("Sound_AmbienceVolume"),
        music = GetCVar("Sound_MusicVolume"),
        dialog = GetCVar("Sound_DialogVolume"),
    }

    local ambienceVolume = tonumber(savedFishingAudioCVars.ambience)
    if ambienceVolume then
        SetCVar("Sound_AmbienceVolume", tostring(Clamp(ambienceVolume * 0.35, 0, 1)))
    end

    local musicVolume = tonumber(savedFishingAudioCVars.music)
    if musicVolume then
        SetCVar("Sound_MusicVolume", tostring(Clamp(musicVolume * 0.2, 0, 1)))
    end

    local dialogVolume = tonumber(savedFishingAudioCVars.dialog)
    if dialogVolume then
        SetCVar("Sound_DialogVolume", tostring(Clamp(dialogVolume * 0.5, 0, 1)))
    end
end

RestoreFishingAudioFocus = function()
    if savedFishingAudioCVars == nil then
        return
    end
    if type(SetCVar) ~= "function" then
        savedFishingAudioCVars = nil
        audioRestoreAt = nil
        if audioRestoreFrame then
            audioRestoreFrame:Hide()
        end
        return
    end

    if savedFishingAudioCVars.ambience ~= nil then
        SetCVar("Sound_AmbienceVolume", savedFishingAudioCVars.ambience)
    end
    if savedFishingAudioCVars.music ~= nil then
        SetCVar("Sound_MusicVolume", savedFishingAudioCVars.music)
    end
    if savedFishingAudioCVars.dialog ~= nil then
        SetCVar("Sound_DialogVolume", savedFishingAudioCVars.dialog)
    end

    savedFishingAudioCVars = nil
    audioRestoreAt = nil
    if audioRestoreFrame then
        audioRestoreFrame:Hide()
    end
end

RestoreFishingAudioFocusAfterLinger = function()
    local linger = (addon.db and addon.db.audioFocusLinger) or defaults.audioFocusLinger
    if linger <= 0 then
        RestoreFishingAudioFocus()
        return
    end
    audioLingerGeneration = audioLingerGeneration + 1
    audioRestoreAt = GetTime() + linger
    if not audioRestoreFrame then
        audioRestoreFrame = CreateFrame("Frame")
        audioRestoreFrame:Hide()
        audioRestoreFrame:SetScript("OnUpdate", function(self)
            if not audioRestoreAt then
                self:Hide()
                return
            end
            if GetTime() >= audioRestoreAt then
                audioRestoreAt = nil
                self:Hide()
                RestoreFishingAudioFocus()
            end
        end)
    end
    audioRestoreFrame:Show()
end

-- Minimal test hooks for local unit tests with mocked WoW APIs.
addon._test = addon._test or {}
addon._test.EnableTemporaryAutoLoot = EnableTemporaryAutoLoot
addon._test.RestoreOriginalAutoLoot = RestoreOriginalAutoLoot
addon._test.SetDB = function(db)
    addon.db = db
end
addon._test.ResetAutoLootState = function()
    savedAutoLoot = nil
end

local function HandleWorldRightClick()
    -- Allow recast unless blocked by combat; internal fishing state can lag
    -- behind in timeout/early-bobber-click cases.
    if InCombatLockdown() then
        return
    end

    local now = GetTime()

    if now - lastRightClickTime < doubleClickWindow then
        lastRightClickTime = 0
        -- Double-click detected, initiate fishing
        audioLingerGeneration = audioLingerGeneration + 1
        fishingStartTime = now
        fishingStartGraceUntil = now + 1.5
        audioRestoreAt = nil
        if audioRestoreFrame then
            audioRestoreFrame:Hide()
        end
        EnableFishingAudioFocus()
        -- Fallback fishing session state in case spell events use a different fishing spellID.
        isFishing = true
        isBobberActive = true
        fishingLootInProgress = false
        EnableTemporaryAutoLoot()
        if not InCombatLockdown() then
            SetOverrideBindingClick(fishingSecureFrame, true, "BUTTON2", fishingSecureFrame:GetName())
        end
    else
        lastRightClickTime = now
        if not InCombatLockdown() then
            ClearOverrideBindings(fishingSecureFrame)
        end
    end
end

local function AttemptBobberInteraction()
    -- Click the bobber when it becomes active
    if not isBobberActive or isFishing then
        return
    end

    -- Look for the fishing bobber frame
    -- In WoW, the bobber is created as a frame when a cast is successful
    local bobber = _G["FishingLineIkonTooltip"]
    if bobber then
        bobber:Click()
        isBobberActive = false
    end
end

local function ContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    end
    if GetContainerNumSlots then
        return GetContainerNumSlots(bag)
    end
    return 0
end

local function ContainerItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bag, slot)
    end
    if GetContainerItemID then
        return GetContainerItemID(bag, slot)
    end
    return nil
end

local function GetFreeBagSlots()
    local free = 0
    local bagCount = NUM_BAG_SLOTS or 4
    -- Check main bags (0 is backpack, 1-4 are other bags)
    for bag = 0, bagCount do
        local slots = ContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                if not ContainerItemID(bag, slot) then
                    free = free + 1
                end
            end
        end
    end
    -- Check reagent bag (bag index 5 in retail WoW)
    local reagentSlots = ContainerNumSlots(5)
    if reagentSlots and reagentSlots > 0 then
        for slot = 1, reagentSlots do
            if not ContainerItemID(5, slot) then
                free = free + 1
            end
        end
    end
    return free
end

local function FindItemInBags(itemID)
    if not itemID then
        return nil, nil
    end

    local bagCount = NUM_BAG_SLOTS or 4
    for bag = 0, bagCount do
        local slots = ContainerNumSlots(bag)
        for slot = 1, slots do
            if ContainerItemID(bag, slot) == itemID then
                return bag, slot
            end
        end
    end

    return nil, nil
end

local function IsFishingCast()
    if UnitCastingInfo("player") == "Fishing" then
        return true
    end
    if UnitChannelInfo("player") == "Fishing" then
        return true
    end
    return false
end

local function IsTreasureItem(name)
    if not name then
        return false
    end
    local lower = string.lower(name)
    return lower:find("treasure") or lower:find("chest") or lower:find("cache") or lower:find("satchel") or lower:find("strongbox")
end

CheckBagSpace = function()
    -- Alert if bag space falls below the configured threshold
    if not addon.db then
        return
    end

    local threshold = addon.db.lowBagThreshold or defaults.lowBagThreshold
    local free = GetFreeBagSlots()

    if free <= threshold then
        local now = GetTime()
        -- Only alert once per 10 seconds to avoid spam
        if now - lastBagWarning >= 10 then
            lastBagWarning = now
            PrintMessage("Low bag space! " .. free .. " slot(s) remaining (threshold: " .. threshold .. ").")
        end
    end
end

addon._test.GetFreeBagSlots = GetFreeBagSlots
addon._test.CheckBagSpace = CheckBagSpace
addon._test.ResetBagWarningState = function()
    lastBagWarning = 0
end

local function PlayFishingSound()
    if not addon.db or not addon.db.enhancedSounds then
        return
    end
    if GetTime() - lastSoundTime < 1.2 then
        return
    end
    lastSoundTime = GetTime()
    if type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.UI_BONUS_ROLL_START then
        PlaySound(SOUNDKIT.UI_BONUS_ROLL_START)
    end
end

local function UpdateConfigUI()
    if not addon.configFrame or not addon.db then
        return
    end

    if addon.autoLootCheckbox then
        addon.autoLootCheckbox:SetChecked(addon.db.autoLoot)
    end
    if addon.enhancedSoundsCheckbox then
        addon.enhancedSoundsCheckbox:SetChecked(addon.db.enhancedSounds)
    end
    if addon.treasureAlertsCheckbox then
        addon.treasureAlertsCheckbox:SetChecked(addon.db.treasureAlerts)
    end
    if addon.refreshBox then
        addon.refreshBox:SetText(tostring(addon.db.refreshSeconds or defaults.refreshSeconds))
    end
    if addon.lowBagBox then
        addon.lowBagBox:SetText(tostring(addon.db.lowBagThreshold or defaults.lowBagThreshold))
    end
    if addon.buffItem1Box then
        addon.buffItem1Box:SetText(tostring(addon.db.buffItem1 or ""))
    end
    if addon.buffItem2Box then
        addon.buffItem2Box:SetText(tostring(addon.db.buffItem2 or ""))
    end
    if addon.audioLingerBox then
        addon.audioLingerBox:SetText(tostring(addon.db.audioFocusLinger or defaults.audioFocusLinger))
    end
end

function addon:SaveConfig()
    if not addon.db then
        return
    end

    addon.db.refreshSeconds = Clamp(tonumber(addon.refreshBox:GetText()) or defaults.refreshSeconds, 30, 600)
    addon.db.lowBagThreshold = Clamp(tonumber(addon.lowBagBox:GetText()) or defaults.lowBagThreshold, 0, 20)
    addon.db.audioFocusLinger = Clamp(tonumber(addon.audioLingerBox:GetText()) or defaults.audioFocusLinger, 0, 60)
    addon.db.autoLoot = addon.autoLootCheckbox:GetChecked()
    addon.db.enhancedSounds = addon.enhancedSoundsCheckbox:GetChecked()
    addon.db.treasureAlerts = addon.treasureAlertsCheckbox:GetChecked()

    if addon.buffItem1Box then
        local item1 = tonumber(addon.buffItem1Box:GetText())
        addon.db.buffItem1 = item1 or nil
    end
    if addon.buffItem2Box then
        local item2 = tonumber(addon.buffItem2Box:GetText())
        addon.db.buffItem2 = item2 or nil
    end

    UpdateConfigUI()
end

function addon:CreateConfigPanel()
    if addon.configFrame then
        return addon.configFrame
    end

    -- 1. Main Container Frame
    local panel = CreateFrame("Frame", addonName .. "ConfigFrame", UIParent, "BackdropTemplate")
    panel:SetSize(420, 440)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()

    -- Aesthetic Frame Styling (Makes it visible)
    panel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)

    addon.configFrame = panel

    -- 2. Title Text
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 20, -20)
    panel.title:SetText(addonName .. " Settings")

    -- 3. Close Button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -8, -8)

    -- 4. Checkbox Helper
    local function CreateCheckbox(x, y, label)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        cb.Text:SetText(label)
        cb.Text:SetTextColor(1, 1, 1, 1)
        return cb
    end

    -- 5. Input Box Helper
    local function CreateEditBox(x, y, width, label)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", x, y)
        lbl:SetText(label)

        local eb = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        eb:SetSize(width, 20)
        eb:SetPoint("TOPLEFT", x, y - 15)
        eb:SetAutoFocus(false)
        return eb
    end

    -- Instantiate UI elements
    addon.autoLootCheckbox = CreateCheckbox(20, -50, "Enable Temporary Auto-Loot")
    addon.enhancedSoundsCheckbox = CreateCheckbox(20, -85, "Enhanced Audio Alerts")
    addon.treasureAlertsCheckbox = CreateCheckbox(20, -120, "Treasure / Node Notifications")

    addon.buffItem1Box = CreateEditBox(20, -170, 100, "Buff Item ID 1:")
    addon.buffItem2Box = CreateEditBox(140, -170, 100, "Buff Item ID 2:")

    addon.refreshBox = CreateEditBox(20, -220, 100, "Refresh Frequency (s):")
    addon.lowBagBox = CreateEditBox(20, -270, 100, "Low Bag Threshold:")
    addon.audioLingerBox = CreateEditBox(20, -315, 100, "Audio Linger After Catch (s):")

    -- 6. Save Button
    local saveBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    saveBtn:SetSize(120, 25)
    saveBtn:SetPoint("BOTTOMRIGHT", -20, 20)
    saveBtn:SetText("Save & Close")
    saveBtn:SetScript("OnClick", function()
        addon:SaveConfig()
        panel:Hide()
        PrintMessage("Configuration Saved.")
    end)

    panel:SetScript("OnShow", function()
        UpdateConfigUI()
    end)

    return panel
end

function addon:ToggleUI()
    local panel = addon.configFrame or addon:CreateConfigPanel()
    if panel:IsShown() then
        panel:Hide()
    else
        UpdateConfigUI()
        panel:Show()
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if event ~= "ADDON_LOADED" or name ~= addonName then
        return
    end

    _G[addonName .. "DB"] = _G[addonName .. "DB"] or {}
    addon.db = _G[addonName .. "DB"]
    CopyDefaults(defaults, addon.db)

    CreateSecureFishingFrame()
    CreateTrackerFrame()
    CreateFishingStateFrame()

    SLASH_DREAMFISHER1 = "/df"
    SLASH_DREAMFISHER2 = "/dreamfisher"
    SlashCmdList["DREAMFISHER"] = function(msg)
        local command = string.lower(strtrim(msg or ""))
        if command == "testtreasure" or command == "tt" then
            ShowPatientTreasureAlert("Test Trigger", true)
            PrintMessage("Triggered Patient Treasure alert test.")
            return
        end
        if command == "testsound" or command == "ts" then
            ShowPatientTreasureAlert("Audio Test", true)
            PrintMessage("Triggered treasure alert audio test.")
            return
        end
        if command == "testaudio" or command == "ta" then
            local amb = GetCVar("Sound_AmbienceVolume")
            local mus = GetCVar("Sound_MusicVolume")
            local dia = GetCVar("Sound_DialogVolume")
            PrintMessage("Audio before duck: Ambience=" .. tostring(amb) .. " Music=" .. tostring(mus) .. " Dialog=" .. tostring(dia))
            EnableFishingAudioFocus(true)
            local amb2 = GetCVar("Sound_AmbienceVolume")
            local mus2 = GetCVar("Sound_MusicVolume")
            local dia2 = GetCVar("Sound_DialogVolume")
            PrintMessage("Audio after duck:  Ambience=" .. tostring(amb2) .. " Music=" .. tostring(mus2) .. " Dialog=" .. tostring(dia2))
            return
        end
        if command == "audiostate" or command == "as" then
            local amb = GetCVar("Sound_AmbienceVolume")
            local mus = GetCVar("Sound_MusicVolume")
            local dia = GetCVar("Sound_DialogVolume")
            local remaining = 0
            if audioRestoreAt then
                remaining = math.max(0, audioRestoreAt - GetTime())
            end
            PrintMessage("Audio state: ducked=" .. tostring(savedFishingAudioCVars ~= nil)
                .. " isFishing=" .. tostring(isFishing)
                .. " bobberActive=" .. tostring(isBobberActive)
                .. " lootInProgress=" .. tostring(fishingLootInProgress)
                .. " restoreIn=" .. string.format("%.1f", remaining) .. "s")
            PrintMessage("CVars: Ambience=" .. tostring(amb) .. " Music=" .. tostring(mus) .. " Dialog=" .. tostring(dia))
            return
        end
        if command == "restoreaudio" or command == "ra" then
            RestoreFishingAudioFocus()
            local amb = GetCVar("Sound_AmbienceVolume")
            local mus = GetCVar("Sound_MusicVolume")
            local dia = GetCVar("Sound_DialogVolume")
            PrintMessage("Audio restored: Ambience=" .. tostring(amb) .. " Music=" .. tostring(mus) .. " Dialog=" .. tostring(dia))
            return
        end
        addon:ToggleUI()
    end

    PrintMessage("Loaded! Type /df to configure. Commands: testtreasure (tt), testsound (ts), testaudio (ta), audiostate (as), restoreaudio (ra).")
    self:UnregisterEvent("ADDON_LOADED")
end)

if WorldFrame then
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if button == "RightButton" and not InCombatLockdown() then
            HandleWorldRightClick()
        end
    end)
end

local lootTracker = CreateFrame("Frame")
lootTracker:RegisterEvent("LOOT_READY")
lootTracker:RegisterEvent("LOOT_CLOSED")
lootTracker:RegisterEvent("BAG_UPDATE")
lootTracker:SetScript("OnEvent", function(_, event)
    if event == "LOOT_READY" then
        -- Loot opened after a fishing catch
        if isBobberActive or savedFishingAudioCVars ~= nil then
            fishingLootInProgress = true
            isBobberActive = false
            isFishing = false
        end
    elseif event == "LOOT_CLOSED" then
        RestoreOriginalAutoLoot()
        -- Only start audio linger restore if this loot was from fishing
        if fishingLootInProgress then
            fishingLootInProgress = false
            RestoreFishingAudioFocusAfterLinger()
        end
        isBobberActive = false
        lastBagWarning = 0
    elseif event == "BAG_UPDATE" then
        -- Check bag space immediately when inventory changes
        if isFishing then
            CheckBagSpace()
        end
    end
end)

local bagMonitor = CreateFrame("Frame")
bagMonitor:RegisterEvent("PLAYER_ENTERING_WORLD")
bagMonitor:RegisterEvent("BAG_UPDATE_DELAYED")
bagMonitor:SetScript("OnEvent", function()
    CheckBagSpace()
end)

local auraTracker = CreateFrame("Frame")
auraTracker:RegisterEvent("UNIT_AURA")
auraTracker:SetScript("OnEvent", function(_, _, unit)
    if unit ~= "player" then
        return
    end

    local hasAura = HasPatientlyRewardedAura()
    if hasAura and not patientAuraActive then
        patientAuraActive = true
        ShowPatientTreasureAlert("Patiently Rewarded")
    elseif not hasAura then
        patientAuraActive = false
    end
end)

