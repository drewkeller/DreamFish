-- DreamFisher: Fishing State Tracking

local addon = _G["DreamFisher"]
local PrintMessage = addon.PrintMessage
local DebugMessage = addon.DebugMessage

local function HasPatientlyRewardedAura()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(addon.const.patientlyRewardedSpellID) ~= nil
    end
    if AuraUtil and AuraUtil.FindAuraBySpellID then
        return AuraUtil.FindAuraBySpellID(addon.const.patientlyRewardedSpellID, "player", "HELPFUL") ~= nil
    end
    return false
end

local function IsFishingSpellByName()
    local castName = UnitCastingInfo and UnitCastingInfo("player")
    if castName and (castName == addon.const.fishingSpellName or castName == "Fishing") then
        return true
    end

    local channelName = UnitChannelInfo and UnitChannelInfo("player")
    if channelName and (channelName == addon.const.fishingSpellName or channelName == "Fishing") then
        return true
    end

    return false
end

local function EnableTemporaryAutoLoot()
    if addon.db and addon.db.autoLoot then
        local current = GetCVar("autoLootDefault")
        if addon.state.savedAutoLoot == nil then
            addon.state.savedAutoLoot = current
        end
        SetCVar("autoLootDefault", "1")
    end
end

local function RestoreOriginalAutoLoot()
    if addon.db and addon.db.autoLoot and addon.state.savedAutoLoot ~= nil then
        SetCVar("autoLootDefault", addon.state.savedAutoLoot)
        addon.state.savedAutoLoot = nil
    end
end

local function TryArmNativeInteractOverrideFromFishingState()
    if not addon.db or not addon.db.enableHookedLoot then
        return
    end
    if not addon.state or not addon.state.isFishing or addon.state.fishingLootInProgress then
        return
    end
    if addon.state.interactOverrideActive then
        return
    end
    if not addon.fishing or not addon.fishing.ArmNativeInteractOverride then
        return
    end

    local now = (type(GetTime) == "function") and GetTime() or 0
    local graceUntil = tonumber(addon.state.fishingStartGraceUntil) or 0
    if now < graceUntil then
        return
    end

    local armed = addon.fishing.ArmNativeInteractOverride()
    if armed then
        DebugMessage("Armed native interact override from fishing-state fallback")
    end
end

local function CreateFishingStateFrame()
    if addon.frames.state then
        return addon.frames.state
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("UNIT_SPELLCAST_START")
    frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    frame:RegisterEvent("UNIT_SPELLCAST_STOP")
    frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
    frame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
    frame:RegisterEvent("PLAYER_STARTED_MOVING")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")

    frame:SetScript("OnEvent", function(self, event, unit, ...)
        if event ~= "PLAYER_REGEN_DISABLED" and event ~= "PLAYER_STARTED_MOVING" and unit ~= "player" then
            return
        end

        local _, spellID = ...
        local isFishingSpell = (spellID == addon.const.fishingSpellID) or IsFishingSpellByName()

        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            if isFishingSpell then
                addon.state.audioLingerGeneration = addon.state.audioLingerGeneration + 1
                addon.state.audioRestoreAt = nil
                if addon.frames.audioRestore then
                    addon.frames.audioRestore:Hide()
                end
                addon.state.isFishing = true
                addon.state.isBobberActive = false
                addon.state.fishingStartTime = GetTime()
                addon.state.fishingStartGraceUntil = addon.state.fishingStartTime + 1.5
                EnableTemporaryAutoLoot()
                addon.audio.EnableFishingAudioFocus()
                frame:SetScript("OnUpdate", function()
                    TryArmNativeInteractOverrideFromFishingState()
                    addon.utils.CheckBagSpace()
                    addon.buff.MaybeUseBuffItems()
                    if addon.state.isBobberActive and addon.state.savedFishingAudioCVars ~= nil and addon.state.fishingStartTime > 0 and (GetTime() - addon.state.fishingStartTime) > addon.state.fishingExpireSeconds then
                        addon.state.isFishing = false
                        addon.state.isBobberActive = false
                        addon.state.fishingLootInProgress = false
                        addon.state.audioRestoreAt = nil
                        if addon.frames.audioRestore then
                            addon.frames.audioRestore:Hide()
                        end
                        addon.audio.RestoreFishingAudioFocus()
                        frame:SetScript("OnUpdate", nil)
                    end
                end)
            elseif (addon.state.isFishing or addon.state.isBobberActive) and addon.state.savedFishingAudioCVars ~= nil and GetTime() > addon.state.fishingStartGraceUntil then
                addon.state.isFishing = false
                addon.state.isBobberActive = false
                addon.state.fishingLootInProgress = false
                addon.state.audioRestoreAt = nil
                if addon.frames.audioRestore then
                    addon.frames.audioRestore:Hide()
                end
                addon.audio.RestoreFishingAudioFocus()
                frame:SetScript("OnUpdate", nil)
            end
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if (isFishingSpell and addon.state.isFishing) or (addon.state.savedFishingAudioCVars ~= nil and addon.state.isFishing) then
                local linger = (addon.db and addon.db.audioFocusLinger) or addon.defaults.audioFocusLinger
                local elapsed = (addon.state.fishingStartTime > 0) and (GetTime() - addon.state.fishingStartTime) or 0
                if linger <= 0 then
                    addon.state.isFishing = false
                    addon.state.isBobberActive = false
                    addon.state.fishingLootInProgress = false
                    addon.audio.RestoreFishingAudioFocus()
                    frame:SetScript("OnUpdate", nil)
                elseif elapsed >= addon.state.fishingExpireSeconds and not addon.state.fishingLootInProgress then
                    addon.state.isFishing = false
                    addon.state.isBobberActive = false
                    addon.state.fishingLootInProgress = false
                    addon.audio.RestoreFishingAudioFocusAfterLinger()
                    frame:SetScript("OnUpdate", nil)
                else
                    addon.state.isFishing = true
                    addon.state.isBobberActive = true
                    if addon.fishing and addon.fishing.ArmNativeInteractOverride then
                        addon.fishing.ArmNativeInteractOverride()
                    end
                    frame:SetScript("OnUpdate", function()
                        TryArmNativeInteractOverrideFromFishingState()
                        addon.utils.CheckBagSpace()
                        addon.buff.MaybeUseBuffItems()
                        if addon.state.isBobberActive and addon.state.savedFishingAudioCVars ~= nil and addon.state.fishingStartTime > 0 and (GetTime() - addon.state.fishingStartTime) > addon.state.fishingExpireSeconds then
                            addon.state.isFishing = false
                            addon.state.isBobberActive = false
                            addon.state.fishingLootInProgress = false
                            addon.audio.RestoreFishingAudioFocusAfterLinger()
                            frame:SetScript("OnUpdate", nil)
                        end
                    end)
                end
            end
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
            if (isFishingSpell and addon.state.savedFishingAudioCVars ~= nil) or (addon.state.savedFishingAudioCVars ~= nil and addon.state.isFishing) then
                addon.state.isFishing = false
                addon.state.isBobberActive = false
                addon.state.fishingLootInProgress = false
                addon.state.audioRestoreAt = nil
                if addon.fishing and addon.fishing.ClearNativeInteractOverride then
                    addon.fishing.ClearNativeInteractOverride()
                end
                if addon.frames.audioRestore then
                    addon.frames.audioRestore:Hide()
                end
                addon.audio.RestoreFishingAudioFocus()
                frame:SetScript("OnUpdate", nil)
            end
        elseif event == "PLAYER_STARTED_MOVING" then
            if addon.state.savedFishingAudioCVars ~= nil then
                addon.state.isFishing = false
                addon.state.isBobberActive = false
                addon.state.fishingLootInProgress = false
                addon.state.audioRestoreAt = nil
                if addon.fishing and addon.fishing.ClearNativeInteractOverride then
                    addon.fishing.ClearNativeInteractOverride()
                end
                if addon.frames.audioRestore then
                    addon.frames.audioRestore:Hide()
                end
                addon.audio.RestoreFishingAudioFocus()
                frame:SetScript("OnUpdate", nil)
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            if addon.state.isFishing or addon.state.savedFishingAudioCVars ~= nil then
                addon.state.isFishing = false
                addon.state.isBobberActive = false
                addon.state.fishingLootInProgress = false
                RestoreOriginalAutoLoot()
                addon.state.audioRestoreAt = nil
                if addon.fishing and addon.fishing.ClearNativeInteractOverride then
                    addon.fishing.ClearNativeInteractOverride()
                end
                if addon.frames.audioRestore then
                    addon.frames.audioRestore:Hide()
                end
                addon.audio.RestoreFishingAudioFocus()
                frame:SetScript("OnUpdate", nil)
            end
        end
    end)

    addon.frames.state = frame
    return addon.frames.state
end

-- Export to addon
addon.fishing = addon.fishing or {}
addon.fishing.HasPatientlyRewardedAura = HasPatientlyRewardedAura
addon.fishing.IsFishingSpellByName = IsFishingSpellByName
addon.fishing.EnableTemporaryAutoLoot = EnableTemporaryAutoLoot
addon.fishing.RestoreOriginalAutoLoot = RestoreOriginalAutoLoot
addon.fishing.CreateFishingStateFrame = CreateFishingStateFrame

-- Test hooks
addon._test.EnableTemporaryAutoLoot = EnableTemporaryAutoLoot
addon._test.RestoreOriginalAutoLoot = RestoreOriginalAutoLoot
addon._test.ResetAutoLootState = function()
    addon.state.savedAutoLoot = nil
end
addon._test.SetFishingFlags = function(fishing, bobber, loot)
    addon.state.isFishing = fishing and true or false
    addon.state.isBobberActive = bobber and true or false
    addon.state.fishingLootInProgress = loot and true or false
end
addon._test.GetFishingFlags = function()
    return addon.state.isFishing, addon.state.isBobberActive, addon.state.fishingLootInProgress
end
addon._test.GetFishingStateFrame = function()
    return addon.frames.state
end
