local addonName = "DreamFisher"
local frame = CreateFrame("Frame", addonName .. "Frame")
local addon = _G[addonName] or {}
_G[addonName] = addon

addon.frame = frame

local defaults = {
    autoLoot = true,
    enhancedSounds = true,
    treasureAlerts = true,
    bagAlerts = true,
    buffItems = {},
    buffAuraByItem = {},
    refreshSeconds = 180,
    lowBagThreshold = 2,
    audioFocusLinger = 10,
    debugMode = true,
    worldRightClickModifier = "NONE",
    worldRightClickModifierUserSet = false,
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
local fishingSpellName = (GetSpellInfo and GetSpellInfo(131474)) or "Fishing"
local fishingSecureFrame = nil
local fishingTrackerFrame = nil
local originalAutoLootState = nil
local fishingStateFrame = nil
local savedFishingAudioCVars = nil
local audioLingerGeneration = 0
local audioRestoreFrame = nil
local audioRestoreAt = nil
local treasureAlertFrame = nil
local bagFullAlertFrame = nil
local patientAuraActive = false
local fishingSpellID = 131474
local fishingLootInProgress = false
local maxBuffSlots = 6
local buffCheckInterval = 1
local lastBuffCheckTime = 0
local buffItemLastUseAt = {}
local buffReminderCooldown = 12
local buffItemLastReminderAt = {}
local buffItemLastKnownCount = {}
local buffMissingWarningCooldown = 8
local buffItemLastMissingWarningAt = {}
local maxFishingCastSeconds = 20
local buffPreRefreshSafetySeconds = 2
local pendingBuffObservation = nil
local buffSecureFrame = nil
local FindItemInBags
local IsFishingCast
local FormatDuration
local PlayBagFullCue
local WarnMissingBuffItem
local uiBuffCursorDragState = nil

local function GetBuffRefreshLead(refreshSeconds)
    local baseLead = Clamp(math.floor(refreshSeconds * 0.1), 3, 15)
    local castAwareLead = maxFishingCastSeconds + buffPreRefreshSafetySeconds
    return math.max(baseLead, castAwareLead)
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local clone = {}
    for k, v in pairs(value) do
        clone[k] = DeepCopy(v)
    end
    return clone
end

local function CopyDefaults(source, target)
    for k, v in pairs(source) do
        if target[k] == nil then
            target[k] = DeepCopy(v)
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

local function DebugMessage(msg)
    if addon.db and addon.db.debugMode then
        PrintMessage("|cFF9ACDFF[debug]|r " .. tostring(msg))
    end
end

local function NormalizeBuffConfig()
    if not addon.db then
        return
    end

    if type(addon.db.buffItems) ~= "table" then
        addon.db.buffItems = {}
    end
    if type(addon.db.buffAuraByItem) ~= "table" then
        addon.db.buffAuraByItem = {}
    end

    for i = 1, maxBuffSlots do
        local entry = addon.db.buffItems[i]
        if type(entry) ~= "table" then
            entry = {}
        end

        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 then
            entry.itemID = itemID
        else
            entry.itemID = nil
        end

        entry.refreshSeconds = Clamp(tonumber(entry.refreshSeconds) or addon.db.refreshSeconds or defaults.refreshSeconds, 30, 3600)
        addon.db.buffItems[i] = entry
    end
end

local function GetAuraBySpellID(spellID)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    end

    if AuraUtil and AuraUtil.FindAuraBySpellID then
        local _, _, _, _, duration, expirationTime, _, _, _, auraSpellID = AuraUtil.FindAuraBySpellID(spellID, "player", "HELPFUL")
        if duration or expirationTime then
            return {
                spellId = auraSpellID or spellID,
                duration = duration,
                expirationTime = expirationTime,
            }
        end
    end

    return nil
end

local function BuildHelpfulAuraSnapshot()
    local snapshot = {}

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local index = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
            if not aura then
                break
            end
            if aura.spellId and aura.duration and aura.duration > 0 then
                snapshot[aura.spellId] = {
                    duration = aura.duration,
                    expirationTime = aura.expirationTime,
                }
            end
            index = index + 1
        end
    end

    return snapshot
end

local function UpdatePendingBuffObservation()
    if not pendingBuffObservation or not addon.db then
        return
    end

    if GetTime() > pendingBuffObservation.expiresAt then
        pendingBuffObservation = nil
        return
    end

    local before = pendingBuffObservation.before or {}
    local current = BuildHelpfulAuraSnapshot()
    local bestSpellID = nil
    local bestDuration = 0

    for spellID, aura in pairs(current) do
        local previous = before[spellID]
        local isNewAura = previous == nil
        local refreshedAura = previous and aura.expirationTime and previous.expirationTime and aura.expirationTime > previous.expirationTime + 0.5
        if (isNewAura or refreshedAura) and aura.duration and aura.duration > bestDuration then
            bestSpellID = spellID
            bestDuration = aura.duration
        end
    end

    if bestSpellID then
        addon.db.buffAuraByItem[tostring(pendingBuffObservation.itemID)] = {
            spellID = bestSpellID,
            duration = bestDuration,
        }
        PrintMessage("Buff tracked for item:" .. tostring(pendingBuffObservation.itemID)
            .. " [item=" .. FormatDuration(bestDuration)
            .. ", active=" .. FormatDuration(bestDuration) .. " total]")
        pendingBuffObservation = nil
    end
end

local function GetTrackedBuffRemaining(itemID)
    if not addon.db or type(addon.db.buffAuraByItem) ~= "table" then
        return nil
    end

    local tracked = addon.db.buffAuraByItem[tostring(itemID)]
    if type(tracked) ~= "table" or not tracked.spellID then
        return nil
    end

    local aura = GetAuraBySpellID(tracked.spellID)
    if not aura then
        return 0
    end
    if not aura.expirationTime or aura.expirationTime <= 0 then
        return nil
    end

    return math.max(0, aura.expirationTime - GetTime())
end

FormatDuration = function(seconds)
    local n = tonumber(seconds)
    if not n or n < 0 then
        return "unknown"
    end
    local rounded = math.floor(n + 0.5)
    local minutes = math.floor(rounded / 60)
    local secs = rounded % 60
    if minutes > 0 then
        return tostring(minutes) .. "m " .. tostring(secs) .. "s"
    end
    return tostring(secs) .. "s"
end

local function GetBuffTimingText(itemID)
    if not addon.db or type(addon.db.buffAuraByItem) ~= "table" then
        return "duration unknown (learning aura mapping)"
    end

    local tracked = addon.db.buffAuraByItem[tostring(itemID)]
    if type(tracked) ~= "table" or not tracked.spellID then
        return "duration unknown (learning aura mapping)"
    end

    local itemDuration = tracked.duration
    local aura = GetAuraBySpellID(tracked.spellID)
    if aura and aura.expirationTime and aura.expirationTime > 0 then
        local remaining = math.max(0, aura.expirationTime - GetTime())
        local activeTotal = aura.duration or remaining
        return "item=" .. FormatDuration(itemDuration) .. ", active=" .. FormatDuration(remaining) .. " remaining / " .. FormatDuration(activeTotal) .. " total"
    end

    if itemDuration then
        return "item=" .. FormatDuration(itemDuration) .. ", active aura not detected"
    end
    return "duration unknown (learning aura mapping)"
end

local function AnnounceBuffUse(itemID)
    local itemName = (type(GetItemInfo) == "function" and GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
    PrintMessage("Using buff: " .. tostring(itemName) .. " [" .. GetBuffTimingText(itemID) .. "]")
end

local function IsBuffItemDue(itemID, refreshSeconds, requireAuraForCast)
    local remaining = GetTrackedBuffRemaining(itemID)
    if remaining ~= nil then
        local lead = GetBuffRefreshLead(refreshSeconds)
        return remaining <= lead, remaining, "tracked_remaining"
    end

    local hasTrackedAura = false
    if addon.db and type(addon.db.buffAuraByItem) == "table" then
        local tracked = addon.db.buffAuraByItem[tostring(itemID)]
        if type(tracked) == "table" and tracked.spellID then
            hasTrackedAura = true
            local aura = GetAuraBySpellID(tracked.spellID)
            if not aura then
                return true, 0, "tracked_missing_aura"
            end
        end
    end

    if requireAuraForCast and not hasTrackedAura then
        return true, nil, "untracked_assume_due_for_cast"
    end

    local lastUsed = buffItemLastUseAt[itemID] or 0
    local elapsed = GetTime() - lastUsed
    return elapsed >= refreshSeconds, nil, "timer_elapsed=" .. string.format("%.1f", elapsed)
end

local function MaybeUseBuffItems()
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return
    end

    if GetTime() - lastBuffCheckTime < buffCheckInterval then
        return
    end
    lastBuffCheckTime = GetTime()

    if InCombatLockdown() or IsFishingCast() then
        return
    end

    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 then
            local refreshSeconds = Clamp(tonumber(entry.refreshSeconds) or addon.db.refreshSeconds or defaults.refreshSeconds, 30, 3600)
            local shouldUse = IsBuffItemDue(itemID, refreshSeconds, false)

            if shouldUse then
                local bag, slot = FindItemInBags(itemID)
                if bag and slot then
                    local now = GetTime()
                    local lastReminder = buffItemLastReminderAt[itemID] or 0
                    if (now - lastReminder) >= buffReminderCooldown then
                        local itemName = (type(GetItemInfo) == "function" and GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
                        PrintMessage("Buff due: use " .. tostring(itemName) .. ". (Drag onto action bar or macro: /use item:" .. tostring(itemID) .. ")")
                        buffItemLastReminderAt[itemID] = now
                        buffItemLastUseAt[itemID] = now
                        pendingBuffObservation = {
                            itemID = itemID,
                            before = BuildHelpfulAuraSnapshot(),
                            expiresAt = now + 20,
                        }
                    end
                end
                return
            end
        end
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

local function CreateBagFullAlertFrame()
    if bagFullAlertFrame then
        return bagFullAlertFrame
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

    bagFullAlertFrame = alert
    return bagFullAlertFrame
end

local function ShowBagFullAlert(force)
    if not force and (not addon.db or not addon.db.bagAlerts) then
        return
    end

    local alert = CreateBagFullAlertFrame()
    alert.title:SetText("Bags Full")
    alert.subtext:SetText("No free bag slots remaining")
    alert:Show()

    alert.timeLeft = 2.2
    alert:SetScript("OnUpdate", function(self, elapsed)
        self.timeLeft = self.timeLeft - elapsed
        if self.timeLeft <= 0 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)

    PlayBagFullCue()
end

PlayBagFullCue = function()
    if type(PlaySound) == "function" and SOUNDKIT then
        local cue = SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.UI_RaidBossEmoteWarning
        if cue then
            PlaySound(cue, "Master")
        end
    end
end

WarnMissingBuffItem = function(itemID, reason)
    local now = GetTime()
    local last = buffItemLastMissingWarningAt[itemID] or 0
    if (now - last) < buffMissingWarningCooldown then
        return
    end
    buffItemLastMissingWarningAt[itemID] = now

    local itemName = (type(GetItemInfo) == "function" and GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
    PrintMessage("Buff due but item missing in inventory: " .. tostring(itemName) .. ".")
    PlayBagFullCue()
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

local function IsFishingSpellByName()
    local castName = UnitCastingInfo and UnitCastingInfo("player")
    if castName and (castName == fishingSpellName or castName == "Fishing") then
        return true
    end

    local channelName = UnitChannelInfo and UnitChannelInfo("player")
    if channelName and (channelName == fishingSpellName or channelName == "Fishing") then
        return true
    end

    return false
end

local function IsWorldRightClickActivationPressed()
    local modifier = string.upper(tostring((addon.db and addon.db.worldRightClickModifier) or defaults.worldRightClickModifier or "ALT"))
    if modifier == "NONE" then
        return true
    end
    if modifier == "ALT" then
        return IsAltKeyDown and IsAltKeyDown()
    end
    if modifier == "CTRL" or modifier == "CONTROL" then
        return IsControlKeyDown and IsControlKeyDown()
    end
    if modifier == "SHIFT" then
        return IsShiftKeyDown and IsShiftKeyDown()
    end
    return IsAltKeyDown and IsAltKeyDown()
end

local function GetNextDueBuffItem(requireAuraForCast)
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return nil
    end

    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 then
            local refreshSeconds = Clamp(tonumber(entry.refreshSeconds) or addon.db.refreshSeconds or defaults.refreshSeconds, 30, 3600)
            local isDue, remaining, reason = IsBuffItemDue(itemID, refreshSeconds, requireAuraForCast)

            if isDue then
                local bag, slot = FindItemInBags(itemID)
                if bag and slot then
                    DebugMessage("Due buff item found: " .. tostring(itemID)
                        .. " bag=" .. tostring(bag)
                        .. " slot=" .. tostring(slot)
                        .. " remaining=" .. tostring(remaining)
                        .. " reason=" .. tostring(reason))
                    return itemID
                elseif addon.db and addon.db.debugMode then
                    DebugMessage("Due buff item not in bags: " .. tostring(itemID)
                        .. " reason=" .. tostring(reason))
                end
                if requireAuraForCast then
                    WarnMissingBuffItem(itemID, reason)
                end
            elseif addon.db and addon.db.debugMode then
                DebugMessage("Buff item not due: " .. tostring(itemID)
                    .. " remaining=" .. tostring(remaining)
                    .. " reason=" .. tostring(reason))
            end
        end
    end

    return nil
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

local function CreateSecureBuffFrame()
    if buffSecureFrame then
        return buffSecureFrame
    end

    buffSecureFrame = CreateFrame("Button", "DreamFisherSecureBuffButton", UIParent, "SecureActionButtonTemplate")
    buffSecureFrame:SetAllPoints(UIParent)
    buffSecureFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    buffSecureFrame:EnableMouse(true)
    buffSecureFrame:SetAttribute("type", "item")
    buffSecureFrame:SetAttribute("type2", "item")
    buffSecureFrame:RegisterForClicks("AnyDown", "AnyUp")
    buffSecureFrame:Hide()
    buffSecureFrame:HookScript("OnClick", function(self)
        local itemID = tonumber(self:GetAttribute("dreamfisher_itemid"))
        DebugMessage("Secure buff click fired: itemID=" .. tostring(itemID)
            .. " item=" .. tostring(self:GetAttribute("item"))
            .. " item2=" .. tostring(self:GetAttribute("item2")))
        if itemID and itemID > 0 then
            local now = GetTime()
            buffItemLastUseAt[itemID] = now
            pendingBuffObservation = {
                itemID = itemID,
                before = BuildHelpfulAuraSnapshot(),
                expiresAt = now + 20,
            }
            AnnounceBuffUse(itemID)
        end
        self:Hide()
        if not InCombatLockdown() then
            ClearOverrideBindings(self)
        end
    end)

    return buffSecureFrame
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
        local isFishingSpell = (spellID == fishingSpellID) or IsFishingSpellByName()

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
                    MaybeUseBuffItems()
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
                local linger = (addon.db and addon.db.audioFocusLinger) or defaults.audioFocusLinger
                local elapsed = (fishingStartTime > 0) and (GetTime() - fishingStartTime) or 0
                if linger <= 0 then
                    -- When linger is disabled, the spell bar ending is the restore point.
                    isFishing = false
                    isBobberActive = false
                    fishingLootInProgress = false
                    RestoreFishingAudioFocus()
                    fishingStateFrame:SetScript("OnUpdate", nil)
                elseif elapsed >= fishingExpireSeconds and not fishingLootInProgress then
                    -- The fishing channel timed out; use the configured linger, or restore immediately when linger is zero.
                    isFishing = false
                    isBobberActive = false
                    fishingLootInProgress = false
                    RestoreFishingAudioFocusAfterLinger()
                    fishingStateFrame:SetScript("OnUpdate", nil)
                else
                    -- Cast bar ended; bobber is now in water. Keep fishing active.
                    isFishing = true
                    isBobberActive = true
                    -- Audio stays low until loot closes + linger expires
                    fishingStateFrame:SetScript("OnUpdate", function()
                        CheckBagSpace()
                        MaybeUseBuffItems()
                        if isBobberActive and savedFishingAudioCVars ~= nil and fishingStartTime > 0 and (GetTime() - fishingStartTime) > fishingExpireSeconds then
                            -- Cast expired with no loot/cancel event; use the configured linger before restoring.
                            isFishing = false
                            isBobberActive = false
                            fishingLootInProgress = false
                            RestoreFishingAudioFocusAfterLinger()
                            fishingStateFrame:SetScript("OnUpdate", nil)
                        end
                    end)
                end
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
addon._test.EnableFishingAudioFocus = function(force)
    EnableFishingAudioFocus(force)
end
addon._test.RestoreFishingAudioFocus = function()
    RestoreFishingAudioFocus()
end
addon._test.RestoreFishingAudioFocusAfterLinger = function()
    RestoreFishingAudioFocusAfterLinger()
end
addon._test.GetAudioDucked = function()
    return savedFishingAudioCVars ~= nil
end
addon._test.GetAudioRestoreAt = function()
    return audioRestoreAt
end
addon._test.SetFishingFlags = function(fishing, bobber, loot)
    isFishing = fishing and true or false
    isBobberActive = bobber and true or false
    fishingLootInProgress = loot and true or false
end
addon._test.GetFishingFlags = function()
    return isFishing, isBobberActive, fishingLootInProgress
end
addon._test.GetFishingStateFrame = function()
    return fishingStateFrame
end

local function HandleWorldRightClick()
    -- Allow recast unless blocked by combat; internal fishing state can lag
    -- behind in timeout/early-bobber-click cases.
    if InCombatLockdown() then
        DebugMessage("Right click ignored: in combat lockdown")
        return
    end

    local now = GetTime()
    DebugMessage("World right click: dt=" .. string.format("%.3f", now - lastRightClickTime))
    local allowSingleClick = addon.configFrame and addon.configFrame:IsShown()

    if buffSecureFrame and buffSecureFrame:IsShown() then
        DebugMessage("Buff secure frame already shown; awaiting secure click")
        return
    end

    if allowSingleClick or now - lastRightClickTime < doubleClickWindow then
        lastRightClickTime = 0
        local pendingBuffItemID = GetNextDueBuffItem(true)
        if pendingBuffItemID then
            -- Double-click with due buff: arm secure use now so this hardware click uses the item.
            if allowSingleClick then
                DebugMessage("Config window open: single right-click using due buff")
            end
            local buffFrame = CreateSecureBuffFrame()
            local bag, slot = FindItemInBags(pendingBuffItemID)
            if bag and slot then
                buffFrame:SetAttribute("item", tostring(bag) .. " " .. tostring(slot))
                buffFrame:SetAttribute("item2", tostring(bag) .. " " .. tostring(slot))
            else
                buffFrame:SetAttribute("item", "item:" .. tostring(pendingBuffItemID))
                buffFrame:SetAttribute("item2", "item:" .. tostring(pendingBuffItemID))
            end
            buffFrame:SetAttribute("dreamfisher_itemid", pendingBuffItemID)
            DebugMessage("Double-click arming due buff: itemID=" .. tostring(pendingBuffItemID)
                .. " item2=" .. tostring(buffFrame:GetAttribute("item2")))
            if not InCombatLockdown() then
                if fishingSecureFrame then
                    ClearOverrideBindings(fishingSecureFrame)
                end
                SetOverrideBindingClick(buffFrame, true, "BUTTON2", buffFrame:GetName())
            end
            buffFrame:Show()
            return
        end

        -- Double-click detected with no due buffs: initiate fishing
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
        DebugMessage("No due buffs; starting fishing cast")
        if allowSingleClick then
            DebugMessage("Config window open: single right-click starting fishing")
        end
        if not InCombatLockdown() then
            if buffSecureFrame then
                ClearOverrideBindings(buffSecureFrame)
            end
            SetOverrideBindingClick(fishingSecureFrame, true, "BUTTON2", fishingSecureFrame:GetName())
        end
    else
        lastRightClickTime = now
        DebugMessage("Single right-click: no addon action (awaiting second click)")
        if not InCombatLockdown() then
            if fishingSecureFrame then
                ClearOverrideBindings(fishingSecureFrame)
            end
            if buffSecureFrame then
                ClearOverrideBindings(buffSecureFrame)
            end
        end
    end
end

addon._test.HandleWorldRightClick = function()
    HandleWorldRightClick()
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

local function ContainerItemCount(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.stackCount or info.quantity or 1
        end
    end
    if GetContainerItemInfo then
        local info = GetContainerItemInfo(bag, slot)
        if type(info) == "table" then
            return info.stackCount or info.quantity or 1
        end
        local _, itemCount = GetContainerItemInfo(bag, slot)
        if itemCount then
            return itemCount
        end
    end
    return 0
end

local function CountItemInBags(itemID)
    if not itemID then
        return 0
    end

    local total = 0
    local bagCount = NUM_BAG_SLOTS or 4
    for bag = 0, bagCount do
        local slots = ContainerNumSlots(bag)
        for slot = 1, slots do
            if ContainerItemID(bag, slot) == itemID then
                total = total + math.max(1, ContainerItemCount(bag, slot))
            end
        end
    end

    local reagentSlots = ContainerNumSlots(5)
    if reagentSlots and reagentSlots > 0 then
        for slot = 1, reagentSlots do
            if ContainerItemID(5, slot) == itemID then
                total = total + math.max(1, ContainerItemCount(5, slot))
            end
        end
    end

    return total
end

local function CheckBuffItemStockWarnings()
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return
    end

    local seen = {}
    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 and not seen[itemID] then
            seen[itemID] = true
            local count = CountItemInBags(itemID)
            local previousCount = buffItemLastKnownCount[itemID]
            buffItemLastKnownCount[itemID] = count

            if previousCount and previousCount > 0 and count <= 0 then
                local itemName = (type(GetItemInfo) == "function" and GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
                PrintMessage("Buff item depleted: " .. tostring(itemName) .. " (0 left).")
            end
        end
    end
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

FindItemInBags = function(itemID)
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

    local reagentSlots = ContainerNumSlots(5)
    if reagentSlots and reagentSlots > 0 then
        for slot = 1, reagentSlots do
            if ContainerItemID(5, slot) == itemID then
                return 5, slot
            end
        end
    end

    return nil, nil
end

IsFishingCast = function()
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
    if not addon.db or not addon.db.bagAlerts then
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

-- Buff timing and logic test hooks
addon._test.GetBuffRefreshLead = function(refreshSeconds)
    local baseLead = Clamp(math.floor(refreshSeconds * 0.1), 3, 15)
    local castAwareLead = maxFishingCastSeconds + buffPreRefreshSafetySeconds
    return math.max(baseLead, castAwareLead)
end
addon._test.IsBuffItemDue = IsBuffItemDue
addon._test.GetNextDueBuffItem = function(requireAuraForCast)
    -- Returns the item ID and reason if due, otherwise nil
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return nil, nil
    end
    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 then
            local refreshSeconds = Clamp(tonumber(entry.refreshSeconds) or addon.db.refreshSeconds or defaults.refreshSeconds, 30, 3600)
            local isDue, remaining, reason = IsBuffItemDue(itemID, refreshSeconds, requireAuraForCast)
            if isDue then
                return itemID, reason
            end
        end
    end
    return nil, nil
end
addon._test.GetTrackedBuffRemaining = GetTrackedBuffRemaining
addon._test.SetBuffLastUseTime = function(itemID, time)
    buffItemLastUseAt[itemID] = time
end
addon._test.GetBuffLastUseTime = function(itemID)
    return buffItemLastUseAt[itemID]
end
addon._test.SetLastRightClickTime = function(time)
    lastRightClickTime = time
end
addon._test.GetLastRightClickTime = function()
    return lastRightClickTime
end
addon._test.GetDoubleClickWindow = function()
    return doubleClickWindow
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
    if addon.bagAlertsCheckbox then
        addon.bagAlertsCheckbox:SetChecked(addon.db.bagAlerts)
    end
    if addon.refreshBox then
        addon.refreshBox:SetText(tostring(addon.db.refreshSeconds or defaults.refreshSeconds))
    end
    if addon.lowBagBox then
        addon.lowBagBox:SetText(tostring(addon.db.lowBagThreshold or defaults.lowBagThreshold))
    end
    if addon.buffItemControls then
        for i, control in ipairs(addon.buffItemControls) do
            local entry = addon.db.buffItems and addon.db.buffItems[i] or nil
            local itemID = entry and entry.itemID or nil
            local refreshSeconds = entry and entry.refreshSeconds or addon.db.refreshSeconds or defaults.refreshSeconds
            control.itemBox:SetText(tostring(itemID or ""))
            control.refreshBox:SetText(tostring(refreshSeconds))
        end
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
    addon.db.bagAlerts = addon.bagAlertsCheckbox:GetChecked()

    if addon.buffItemControls then
        addon.db.buffItems = {}
        for i, control in ipairs(addon.buffItemControls) do
            local itemID = tonumber(control.itemBox:GetText())
            local refreshSeconds = Clamp(tonumber(control.refreshBox:GetText()) or addon.db.refreshSeconds or defaults.refreshSeconds, 30, 3600)
            addon.db.buffItems[i] = {
                itemID = (itemID and itemID > 0) and itemID or nil,
                refreshSeconds = refreshSeconds,
            }
        end
    end

    NormalizeBuffConfig()

    if savedFishingAudioCVars ~= nil and audioRestoreAt ~= nil then
        RestoreFishingAudioFocusAfterLinger()
    end

    UpdateConfigUI()
end

function addon:CreateConfigPanel()
    if addon.configFrame then
        return addon.configFrame
    end

    -- 1. Main Container Frame
    local panel = CreateFrame("Frame", addonName .. "ConfigFrame", UIParent, "BackdropTemplate")
    panel:SetSize(480, 700)
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

    local function CreateBuffItemDropBox(x, y, label)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", x, y)
        lbl:SetText(label)

        local box = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate,BackdropTemplate")
        box:SetSize(48, 48)
        box:SetPoint("TOPLEFT", x, y - 18)
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        box:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        box:SetBackdropBorderColor(0.9, 0.8, 0.2, 1)
        box.defaultBorderColor = { 0.9, 0.8, 0.2, 1 }
        box.dragHoverBorderColor = { 0.2, 1.0, 0.35, 1 }

        box.icon = box:CreateTexture(nil, "ARTWORK")
        box.icon:SetAllPoints(box)
        box.icon:SetTexture(nil)

        box.itemID = nil
        box.textValue = ""

        function box:SetItemID(itemID)
            local numeric = tonumber(itemID)
            if numeric and numeric > 0 then
                self.itemID = numeric
                self.textValue = tostring(numeric)
                if type(GetItemIcon) == "function" then
                    self.icon:SetTexture(GetItemIcon(numeric))
                else
                    self.icon:SetTexture(nil)
                end
                local bag, slot = FindItemInBags(numeric)
                self:SetAttribute("type2", "item")
                if bag and slot then
                    self:SetAttribute("item2", tostring(bag) .. " " .. tostring(slot))
                else
                    self:SetAttribute("item2", "item:" .. tostring(numeric))
                end
            else
                self.itemID = nil
                self.textValue = ""
                self.icon:SetTexture(nil)
                self:SetAttribute("type2", nil)
                self:SetAttribute("item2", nil)
            end
        end

        -- Preserve EditBox-like API so existing save/load logic keeps working.
        function box:SetText(value)
            self:SetItemID(value)
        end

        function box:GetText()
            return self.textValue or ""
        end

        local function TryAssignFromCursor(self)
            if type(GetCursorInfo) ~= "function" then
                return
            end
            local cursorType, itemID = GetCursorInfo()
            if cursorType == "item" and itemID then
                self:SetItemID(itemID)
                if type(ClearCursor) == "function" then
                    ClearCursor()
                end
            end
        end

        local function TryDropCursorItemToSlot(self)
            if type(GetCursorInfo) ~= "function" then
                return false
            end

            local cursorType, cursorItemID = GetCursorInfo()
            if cursorType ~= "item" or not cursorItemID then
                return false
            end

            local sourceState = uiBuffCursorDragState
            local source = sourceState and sourceState.source or nil
            local sourceRefresh = sourceState and sourceState.sourceRefresh or nil

            local targetItemID = self.itemID
            local targetRefresh = self.refreshBox and self.refreshBox:GetText() or tostring(addon.db and addon.db.refreshSeconds or defaults.refreshSeconds)

            self:SetItemID(cursorItemID)
            if sourceRefresh and self.refreshBox then
                self.refreshBox:SetText(sourceRefresh)
            end

            if source and source ~= self then
                source:SetItemID(targetItemID)
                if source.refreshBox then
                    source.refreshBox:SetText(targetRefresh)
                end
                SetDragHighlight(source, false)
            end

            if source and source == self and sourceRefresh and self.refreshBox then
                self.refreshBox:SetText(sourceRefresh)
            end

            if type(ClearCursor) == "function" then
                ClearCursor()
            end

            uiBuffCursorDragState = nil
            return true
        end

        local function SetDragHighlight(self, active)
            if active then
                self:SetBackdropBorderColor(self.dragHoverBorderColor[1], self.dragHoverBorderColor[2], self.dragHoverBorderColor[3], self.dragHoverBorderColor[4])
            else
                self:SetBackdropBorderColor(self.defaultBorderColor[1], self.defaultBorderColor[2], self.defaultBorderColor[3], self.defaultBorderColor[4])
            end
        end

        box:RegisterForClicks("AnyDown", "AnyUp")
        box:RegisterForDrag("LeftButton")
        box:SetScript("OnDragStart", function(self)
            if self.itemID and self.itemID > 0 then
                local sourceItemID = self.itemID
                local sourceRefresh = self.refreshBox and self.refreshBox:GetText() or tostring(addon.db and addon.db.refreshSeconds or defaults.refreshSeconds)

                if type(PickupItem) == "function" then
                    PickupItem(sourceItemID)
                end

                if type(GetCursorInfo) == "function" then
                    local cursorType, cursorItemID = GetCursorInfo()
                    if cursorType == "item" and tonumber(cursorItemID) == tonumber(sourceItemID) then
                        self:SetItemID(nil)
                        uiBuffCursorDragState = {
                            source = self,
                            sourceItemID = sourceItemID,
                            sourceRefresh = sourceRefresh,
                        }
                        SetDragHighlight(self, true)
                    else
                        uiBuffCursorDragState = nil
                    end
                else
                    uiBuffCursorDragState = nil
                end
            else
                uiBuffCursorDragState = nil
            end
        end)
        box:SetScript("OnDragStop", function(self)
            if uiBuffCursorDragState and uiBuffCursorDragState.source == self then
                -- Item stays attached to cursor if dropped outside another slot.
                uiBuffCursorDragState = nil
            end
            SetDragHighlight(self, false)
        end)
        box:SetScript("OnReceiveDrag", function(self)
            if TryDropCursorItemToSlot(self) then
                return
            end

            TryAssignFromCursor(self)
        end)
        box:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                if not TryDropCursorItemToSlot(self) then
                    TryAssignFromCursor(self)
                end
            elseif button == "RightButton" then
                if IsShiftKeyDown() then
                    self:SetItemID(nil)
                end
            end
        end)
        box:SetScript("OnEnter", function(self)
            if uiBuffCursorDragState and uiBuffCursorDragState.source ~= self then
                SetDragHighlight(self, true)
            end
            if not self.itemID or type(GameTooltip) ~= "table" then
                return
            end
            if type(GameTooltip.SetOwner) == "function" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            end
            if type(GameTooltip.SetItemByID) == "function" then
                GameTooltip:SetItemByID(self.itemID)
            elseif type(GameTooltip.SetHyperlink) == "function" then
                GameTooltip:SetHyperlink("item:" .. tostring(self.itemID))
            end
            if type(GameTooltip.Show) == "function" then
                GameTooltip:Show()
            end
        end)
        box:SetScript("OnLeave", function(self)
            SetDragHighlight(self, false)
            if type(GameTooltip) == "table" and type(GameTooltip.Hide) == "function" then
                GameTooltip:Hide()
            end
        end)

        -- Add count text overlay
        box.countText = box:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        box.countText:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        box.countText:SetTextColor(1, 1, 1, 1)
        box.countText:SetText("")

        -- Update count display
        local function UpdateCountDisplay()
            if box.itemID and box.itemID > 0 then
                local count = CountItemInBags(box.itemID)
                box.countText:SetText(tostring(math.max(0, count)))
                if buffItemLastKnownCount[box.itemID] == nil then
                    buffItemLastKnownCount[box.itemID] = math.max(0, count)
                end
            else
                box.countText:SetText("")
            end
        end
        box.UpdateCountDisplay = UpdateCountDisplay

        -- Update count when item changes
        local originalSetItemID = box.SetItemID
        function box:SetItemID(itemID)
            originalSetItemID(self, itemID)
            UpdateCountDisplay()
        end

        box:HookScript("OnClick", function(self, button)
            if button ~= "RightButton" or not self.itemID or self.itemID <= 0 then
                return
            end
            local now = GetTime()
            buffItemLastUseAt[self.itemID] = now
            pendingBuffObservation = {
                itemID = self.itemID,
                before = BuildHelpfulAuraSnapshot(),
                expiresAt = now + 20,
            }
            AnnounceBuffUse(self.itemID)
            self:UpdateCountDisplay()
        end)

        return box
    end

    local function CreateBuffRefreshBox(x, y)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", x, y)
        lbl:SetText("Refresh (s)")

        local eb = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        eb:SetSize(70, 20)
        eb:SetPoint("TOPLEFT", x, y - 12)
        eb:SetAutoFocus(false)
        return eb
    end

    -- Instantiate UI elements
    addon.autoLootCheckbox = CreateCheckbox(20, -50, "Temporary Auto-Loot")
    addon.enhancedSoundsCheckbox = CreateCheckbox(20, -85, "Fishing Focused Audio")
    addon.treasureAlertsCheckbox = CreateCheckbox(20, -120, "Patient Treasure Notification")
    addon.bagAlertsCheckbox = CreateCheckbox(20, -155, "Bag Monitor / Alert")

    addon.buffItemControls = {}
    for i = 1, maxBuffSlots do
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local baseX = 20 + (col * 220)
        local baseY = -205 - (row * 95)
        local itemBox = CreateBuffItemDropBox(baseX, baseY, "Buff " .. i)
        local refreshBox = CreateBuffRefreshBox(baseX + 65, baseY - 4)
        itemBox.refreshBox = refreshBox
        itemBox.slotIndex = i
        addon.buffItemControls[i] = {
            itemBox = itemBox,
            refreshBox = refreshBox,
        }
    end

    addon.refreshBox = CreateEditBox(20, -505, 100, "Default Refresh (s):")
    addon.lowBagBox = CreateEditBox(20, -555, 100, "Low Bag Threshold:")
    addon.audioLingerBox = CreateEditBox(20, -605, 100, "Audio Linger After Catch (s):")

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
    -- Migration: old builds defaulted to ALT. If user never explicitly chose a modifier,
    -- switch to NONE so right-click fishing works one-handed by default.
    if not addon.db.worldRightClickModifierUserSet then
        addon.db.worldRightClickModifier = "NONE"
    end
    NormalizeBuffConfig()
    CheckBuffItemStockWarnings()

    CreateSecureFishingFrame()
    CreateSecureBuffFrame()
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
        if command == "testbagsfull" or command == "tbf" then
            ShowBagFullAlert(true)
            PrintMessage("Triggered bags full alert test.")
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
        if command == "debug" or command == "dbg" then
            addon.db.debugMode = not addon.db.debugMode
            PrintMessage("Debug mode: " .. (addon.db.debugMode and "ON" or "OFF"))
            return
        end
        local modifierArg = command:match("^modifier%s+(%S+)$")
        if modifierArg then
            local value = string.upper(modifierArg)
            if value == "ALT" or value == "CTRL" or value == "SHIFT" or value == "NONE" then
                addon.db.worldRightClickModifier = value
                addon.db.worldRightClickModifierUserSet = true
                PrintMessage("World right-click modifier set to: " .. value)
            else
                PrintMessage("Invalid modifier. Use: ALT, CTRL, SHIFT, or NONE")
            end
            return
        end
        addon:ToggleUI()
    end

    PrintMessage("Loaded! Type /df to configure. Commands: testtreasure (tt), testbagsfull (tbf), testsound (ts), testaudio (ta), audiostate (as), restoreaudio (ra), debug (dbg), modifier <ALT|CTRL|SHIFT|NONE>.")
    self:UnregisterEvent("ADDON_LOADED")
end)

if WorldFrame then
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if button == "RightButton" and not InCombatLockdown() and IsWorldRightClickActivationPressed() then
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
            if GetFreeBagSlots() == 0 then
                ShowBagFullAlert()
            end
        end
        isBobberActive = false
        lastBagWarning = 0
    elseif event == "BAG_UPDATE" then
        -- Check bag space immediately when inventory changes
        if isFishing then
            CheckBagSpace()
        end
        CheckBuffItemStockWarnings()
        -- Refresh buff item counts in UI
        if addon.buffItemControls then
            for i, control in ipairs(addon.buffItemControls) do
                if control.itemBox and control.itemBox.UpdateCountDisplay then
                    control.itemBox:UpdateCountDisplay()
                end
            end
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

    UpdatePendingBuffObservation()

    local hasAura = HasPatientlyRewardedAura()
    if hasAura and not patientAuraActive then
        patientAuraActive = true
        ShowPatientTreasureAlert("Patiently Rewarded")
    elseif not hasAura then
        patientAuraActive = false
    end
end)

