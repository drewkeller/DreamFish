-- DreamFisher: Fishing State Tracking

local addon = _G["DreamFisher"]
local PrintMessage = addon.PrintMessage
local DebugMessage = addon.DebugMessage
local DebugStateMessage = addon.DebugStateMessage or function() end
local ignoredFailureDebugAtBySpell = {}
local WATER_EXIT_SWAP_DELAY_SECONDS = 5.0

local function IsStrictFishingSpellID(spellID)
    local numeric = tonumber(spellID)
    if not numeric then
        return false
    end
    if addon.const and tonumber(addon.const.fishingSpellID) == numeric then
        return true
    end
    if addon.const and tonumber(addon.const.fishingChannelSpellID) == numeric then
        return true
    end
    return false
end

local function ShouldLogIgnoredFailure(spellID)
    local key = tostring(tonumber(spellID) or spellID or "unknown")
    local now = (type(GetTime) == "function") and GetTime() or 0
    local last = tonumber(ignoredFailureDebugAtBySpell[key]) or 0
    if last > 0 and (now - last) < 2 then
        return false
    end
    ignoredFailureDebugAtBySpell[key] = now
    return true
end

local function GetHookedInteractEvidence()
    local now = (type(GetTime) == "function") and GetTime() or 0
    local acquireExpiresAt = tonumber(addon.state and addon.state.interactAcquireExpiresAt) or 0
    local inAcquireWindow = acquireExpiresAt > now
    local hasAnyInteractUnit = false
    local hasSoftInteractNameOnly = false

    if addon.fishing and addon.fishing.GetInteractDiagnostics then
        local diag = addon.fishing.GetInteractDiagnostics()
        hasAnyInteractUnit = diag and (diag.softExists or diag.targetExists or diag.mouseoverExists) and true or false
        hasSoftInteractNameOnly = diag
            and (not hasAnyInteractUnit)
            and type(diag.softName) == "string"
            and diag.softName ~= ""
            and true or false
    end

    return hasAnyInteractUnit, hasSoftInteractNameOnly, inAcquireWindow
end

local function LogStateTransition(reason, event, spellID, isFishingSpell)
    if not (addon.db and addon.db.debugMode and addon.db.debugState) then
        return
    end
    local now = (type(GetTime) == "function") and GetTime() or 0
    local startedAt = tonumber(addon.state and addon.state.fishingStartTime) or 0
    local elapsed = (startedAt > 0 and now >= startedAt) and (now - startedAt) or 0
    local graceUntil = tonumber(addon.state and addon.state.fishingStartGraceUntil) or 0
    local graceRemaining = math.max(0, graceUntil - now)
    DebugStateMessage("State transition: " .. tostring(reason)
        .. " event=" .. tostring(event)
        .. " spellID=" .. tostring(spellID)
        .. " isFishingSpell=" .. tostring(isFishingSpell)
        .. " elapsed=" .. string.format("%.3f", elapsed)
        .. " graceRemaining=" .. string.format("%.3f", graceRemaining)
        .. " isFishing=" .. tostring(addon.state and addon.state.isFishing)
        .. " isBobberActive=" .. tostring(addon.state and addon.state.isBobberActive)
        .. " lootInProgress=" .. tostring(addon.state and addon.state.fishingLootInProgress)
        .. " audioDucked=" .. tostring(addon.state and addon.state.savedFishingAudioCVars ~= nil)
        .. " interactOverrideActive=" .. tostring(addon.state and addon.state.interactOverrideActive)
        .. " interactAcquireExpiresAt=" .. tostring(addon.state and addon.state.interactAcquireExpiresAt))
end

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

local function MaybeEquipConfiguredUnderlight(reason)
    if addon.fishing and addon.fishing.MaybeEquipConfiguredUnderlight then
        addon.fishing.MaybeEquipConfiguredUnderlight(reason)
    end
end

local function TryArmNativeInteractOverrideFromFishingState()
    if not addon.db or not addon.db.easyStrike then
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

    local lastAttemptAt = tonumber(addon.state.interactFallbackArmLastAttemptAt) or 0
    if lastAttemptAt > 0 and (now - lastAttemptAt) < 0.75 then
        return
    end
    addon.state.interactFallbackArmLastAttemptAt = now

    local graceUntil = tonumber(addon.state.fishingStartGraceUntil) or 0
    if now < graceUntil then
        return
    end

    local armed = addon.fishing.ArmNativeInteractOverride()
    if armed then
        local lastLogAt = tonumber(addon.state.interactFallbackArmLastLogAt) or 0
        if lastLogAt <= 0 or (now - lastLogAt) >= 4 then
            addon.state.interactFallbackArmLastLogAt = now
            DebugStateMessage("Armed native interact override from fishing-state fallback")
        end
    end
end

local function CreateSwimmingStateMonitor()
    if addon.frames.swimMonitor then
        return addon.frames.swimMonitor
    end

    local frame = CreateFrame("Frame")
    local elapsedSinceCheck = 0
    local lastSwimmingState = nil
    local pendingWaterExitSyncAt = nil

    local function ShouldDelayWaterExitSync()
        return false
    end

    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceCheck = elapsedSinceCheck + (tonumber(elapsed) or 0)
        if elapsedSinceCheck < 0.25 then
            return
        end
        elapsedSinceCheck = 0
        local now = (type(GetTime) == "function") and GetTime() or 0

        local waterContext = nil
        local swimming = false
        if addon.fishing and addon.fishing.GetWaterContextDiagnostics then
            waterContext = addon.fishing.GetWaterContextDiagnostics()
            swimming = waterContext and waterContext.result and true or false
        elseif addon.fishing and addon.fishing.IsPlayerInWaterContext then
            swimming = addon.fishing.IsPlayerInWaterContext() and true or false
        elseif type(IsSwimming) == "function" then
            swimming = IsSwimming() and true or false
        end

        if pendingWaterExitSyncAt then
            local isFishingSession = addon.state and (addon.state.isFishing or addon.state.isBobberActive)
            if isFishingSession then
                pendingWaterExitSyncAt = nil
                if addon.db and addon.db.debugMode and addon.db.debugState then
                    DebugStateMessage("Water exit swap canceled: fishing session active")
                end
            elseif swimming then
                pendingWaterExitSyncAt = nil
                if addon.db and addon.db.debugMode and addon.db.debugState then
                    DebugStateMessage("Water exit swap canceled: player still in water context")
                end
            elseif now >= pendingWaterExitSyncAt then
                pendingWaterExitSyncAt = nil
                MaybeEquipConfiguredUnderlight("state-left-water-delayed")
            end
        end

        if lastSwimmingState == nil then
            lastSwimmingState = swimming
            return
        end

        if swimming == lastSwimmingState then
            return
        end

        lastSwimmingState = swimming

        if addon.db and addon.db.debugMode and addon.db.debugState then
            DebugStateMessage("Water state changed: inWater=" .. tostring(swimming))
            if waterContext then
                DebugStateMessage("Water state details: source=" .. tostring(waterContext.source or "none")
                    .. " isSwimming=" .. tostring(waterContext.isSwimming)
                    .. " isSubmerged=" .. tostring(waterContext.isSubmerged)
                    .. " secureOption=" .. tostring(waterContext.secureOption))
            else
                DebugStateMessage("Water state details: source=none isSwimming=false isSubmerged=false secureOption=nil")
            end
        end

        if swimming then
            pendingWaterExitSyncAt = nil
            MaybeEquipConfiguredUnderlight("state-entered-water")
        else
            if ShouldDelayWaterExitSync() then
                pendingWaterExitSyncAt = now + WATER_EXIT_SWAP_DELAY_SECONDS
                if addon.db and addon.db.debugMode and addon.db.debugState then
                    DebugStateMessage("Delaying left-water pole sync by "
                        .. tostring(WATER_EXIT_SWAP_DELAY_SECONDS) .. "s")
                end
            else
                MaybeEquipConfiguredUnderlight("state-left-water")
            end
        end
    end)

    addon.frames.swimMonitor = frame
    return addon.frames.swimMonitor
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
        local isFishingSpellStrict = IsStrictFishingSpellID(spellID)
        local isFishingSpell = isFishingSpellStrict or IsFishingSpellByName()
        local stopLooksFishing = isFishingSpellStrict or IsFishingSpellByName()

        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            if isFishingSpell then
                LogStateTransition("cast-start-fishing", event, spellID, isFishingSpell)
                addon.state.audioLingerGeneration = addon.state.audioLingerGeneration + 1
                addon.state.audioRestoreAt = nil
                if addon.frames.audioRestore then
                    addon.frames.audioRestore:Hide()
                end
                addon.state.isFishing = true
                addon.state.isBobberActive = false
                addon.state.fishingCastActive = true
                addon.state.fishingStartTime = GetTime()
                addon.state.fishingStartGraceUntil = addon.state.fishingStartTime + 1.5
                addon.state.lastFishingCastStopAt = 0
                EnableTemporaryAutoLoot()
                addon.audio.EnableFishingAudioFocus()
                frame:SetScript("OnUpdate", function()
                    TryArmNativeInteractOverrideFromFishingState()
                    addon.utils.CheckBagSpace()
                    addon.buff.MaybeUseBuffItems()
                    if addon.state.isBobberActive and addon.state.savedFishingAudioCVars ~= nil and addon.state.fishingStartTime > 0 and (GetTime() - addon.state.fishingStartTime) > addon.state.fishingExpireSeconds then
                        LogStateTransition("onupdate-expired-while-bobber", event, spellID, isFishingSpell)
                        addon.state.isFishing = false
                        addon.state.isBobberActive = false
                        addon.state.fishingCastActive = false
                        addon.state.fishingLootInProgress = false
                        addon.state.lastFishingCastStopAt = 0
                        addon.state.audioRestoreAt = nil
                        if addon.frames.audioRestore then
                            addon.frames.audioRestore:Hide()
                        end
                        addon.audio.RestoreFishingAudioFocus()
                        MaybeEquipConfiguredUnderlight("state-onupdate-expired-while-bobber")
                        frame:SetScript("OnUpdate", nil)
                    end
                end)
            elseif (addon.state.isFishing or addon.state.isBobberActive) and addon.state.savedFishingAudioCVars ~= nil and GetTime() > addon.state.fishingStartGraceUntil then
                LogStateTransition("cast-start-nonfishing-clears-session", event, spellID, isFishingSpell)
                addon.state.isFishing = false
                addon.state.isBobberActive = false
                addon.state.fishingCastActive = false
                addon.state.fishingLootInProgress = false
                addon.state.lastFishingCastStopAt = 0
                addon.state.audioRestoreAt = nil
                if addon.frames.audioRestore then
                    addon.frames.audioRestore:Hide()
                end
                addon.audio.RestoreFishingAudioFocus()
                MaybeEquipConfiguredUnderlight("state-cast-start-nonfishing", true)
                frame:SetScript("OnUpdate", nil)
            end
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if stopLooksFishing and addon.state.isFishing and addon.state.savedFishingAudioCVars ~= nil then
                addon.state.fishingCastActive = false
                local linger = (addon.db and addon.db.focusedAudioLinger) or addon.defaults.focusedAudioLinger
                local elapsed = (addon.state.fishingStartTime > 0) and (GetTime() - addon.state.fishingStartTime) or 0
                LogStateTransition("cast-stop-evaluating", event, spellID, isFishingSpell)
                if linger <= 0 then
                    LogStateTransition("cast-stop-restore-immediate-linger-zero", event, spellID, isFishingSpell)
                    addon.state.isFishing = false
                    addon.state.isBobberActive = false
                    addon.state.fishingCastActive = false
                    addon.state.fishingLootInProgress = false
                    addon.state.lastFishingCastStopAt = 0
                    addon.audio.RestoreFishingAudioFocus()
                    MaybeEquipConfiguredUnderlight("state-cast-stop-linger-zero", true)
                    frame:SetScript("OnUpdate", nil)
                elseif elapsed >= addon.state.fishingExpireSeconds and not addon.state.fishingLootInProgress then
                    LogStateTransition("cast-stop-restore-linger-after-expire", event, spellID, isFishingSpell)
                    addon.state.isFishing = false
                    addon.state.isBobberActive = false
                    addon.state.fishingCastActive = false
                    addon.state.fishingLootInProgress = false
                    addon.state.lastFishingCastStopAt = 0
                    addon.audio.RestoreFishingAudioFocusAfterLinger()
                    MaybeEquipConfiguredUnderlight("state-cast-stop-after-expire", true)
                    frame:SetScript("OnUpdate", nil)
                else
                    LogStateTransition("cast-stop-enter-bobber-window", event, spellID, isFishingSpell)
                    addon.state.isFishing = true
                    addon.state.isBobberActive = true
                    addon.state.lastFishingCastStopAt = GetTime()
                    if addon.fishing and addon.fishing.ArmNativeInteractOverride then
                        addon.fishing.ArmNativeInteractOverride()
                    end
                    frame:SetScript("OnUpdate", function()
                        TryArmNativeInteractOverrideFromFishingState()
                        addon.utils.CheckBagSpace()
                        addon.buff.MaybeUseBuffItems()
                        local now = GetTime()
                        local confirmSeconds = (addon.const and tonumber(addon.const.hookedEvidenceConfirmSeconds)) or 4
                        local lastStopAt = tonumber(addon.state.lastFishingCastStopAt) or 0
                        if addon.state.isBobberActive
                            and addon.state.savedFishingAudioCVars ~= nil
                            and lastStopAt > 0
                            and (now - lastStopAt) >= confirmSeconds
                            and not addon.state.fishingLootInProgress then
                            local hasAnyInteractUnit, hasSoftInteractNameOnly, inAcquireWindow = GetHookedInteractEvidence()
                            if (not hasAnyInteractUnit) and (not hasSoftInteractNameOnly) and (not inAcquireWindow) then
                                LogStateTransition("post-stop-no-hooked-evidence-cancel", event, spellID, isFishingSpell)
                                addon.state.isFishing = false
                                addon.state.isBobberActive = false
                                addon.state.fishingCastActive = false
                                addon.state.fishingLootInProgress = false
                                addon.state.lastFishingCastStopAt = 0
                                addon.state.interactAcquireExpiresAt = 0
                                addon.state.audioRestoreAt = nil
                                if addon.fishing and addon.fishing.ClearNativeInteractOverride then
                                    addon.fishing.ClearNativeInteractOverride()
                                end
                                addon.state.interactOverrideActive = false
                                addon.state.interactOverrideExpiresAt = 0
                                if addon.frames.audioRestore then
                                    addon.frames.audioRestore:Hide()
                                end
                                addon.audio.RestoreFishingAudioFocus()
                                MaybeEquipConfiguredUnderlight("state-post-stop-no-hooked-evidence", true)
                                frame:SetScript("OnUpdate", nil)
                                return
                            end
                        end
                        if addon.state.isBobberActive and addon.state.savedFishingAudioCVars ~= nil and addon.state.fishingStartTime > 0 and (GetTime() - addon.state.fishingStartTime) > addon.state.fishingExpireSeconds then
                            LogStateTransition("onupdate-expired-after-cast-stop", event, spellID, isFishingSpell)
                            addon.state.isFishing = false
                            addon.state.isBobberActive = false
                            addon.state.fishingCastActive = false
                            addon.state.fishingLootInProgress = false
                            addon.state.lastFishingCastStopAt = 0
                            addon.audio.RestoreFishingAudioFocusAfterLinger()
                            MaybeEquipConfiguredUnderlight("state-onupdate-expired-after-stop", true)
                            frame:SetScript("OnUpdate", nil)
                        end
                    end)
                end
            end
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
            local shouldCancelFishingSession = false
            if addon.state.savedFishingAudioCVars ~= nil then
                if event == "UNIT_SPELLCAST_INTERRUPTED" then
                    shouldCancelFishingSession = isFishingSpellStrict
                        or (addon.state.fishingCastActive and IsFishingSpellByName())
                else
                    -- FAILED/FAILED_QUIET are noisy in many contexts; only trust strict fishing spell IDs.
                    shouldCancelFishingSession = isFishingSpellStrict
                end
            end

            if shouldCancelFishingSession then
                LogStateTransition("cast-failed-or-interrupted", event, spellID, isFishingSpell)
                addon.state.isFishing = false
                addon.state.isBobberActive = false
                addon.state.fishingCastActive = false
                addon.state.fishingLootInProgress = false
                addon.state.lastFishingCastStopAt = 0
                addon.state.interactAcquireExpiresAt = 0
                addon.state.audioRestoreAt = nil
                if addon.fishing and addon.fishing.ClearNativeInteractOverride then
                    addon.fishing.ClearNativeInteractOverride()
                end
                addon.state.interactOverrideActive = false
                addon.state.interactOverrideExpiresAt = 0
                if addon.frames.audioRestore then
                    addon.frames.audioRestore:Hide()
                end
                addon.audio.RestoreFishingAudioFocus()
                MaybeEquipConfiguredUnderlight("state-cast-failed", true)
                frame:SetScript("OnUpdate", nil)
            elseif addon.db and addon.db.debugMode and addon.db.debugState and addon.state.savedFishingAudioCVars ~= nil and ShouldLogIgnoredFailure(spellID) then
                DebugStateMessage("Ignoring non-fishing cast failure event while fishing session active:"
                    .. " event=" .. tostring(event)
                    .. " spellID=" .. tostring(spellID)
                    .. " strictFishing=" .. tostring(isFishingSpellStrict)
                    .. " byName=" .. tostring(IsFishingSpellByName())
                    .. " interactOverrideActive=" .. tostring(addon.state and addon.state.interactOverrideActive))
            end
        elseif event == "PLAYER_STARTED_MOVING" then
            if addon.fishing and addon.fishing.ClearNativeInteractOverride then
                local acquireExpiresAt = tonumber(addon.state.interactAcquireExpiresAt) or 0
                if addon.state.interactOverrideActive or acquireExpiresAt > GetTime() then
                    LogStateTransition("movement-clears-interact-override", event, spellID, isFishingSpell)
                    addon.fishing.ClearNativeInteractOverride()
                    addon.state.interactAcquireExpiresAt = 0
                    DebugStateMessage("Movement detected: cleared interact override")
                end
            end
            if addon.state.savedFishingAudioCVars ~= nil then
                LogStateTransition("movement-clears-fishing-session", event, spellID, isFishingSpell)
                addon.state.isFishing = false
                addon.state.isBobberActive = false
                addon.state.fishingCastActive = false
                addon.state.fishingLootInProgress = false
                addon.state.lastFishingCastStopAt = 0
                addon.state.interactAcquireExpiresAt = 0
                addon.state.audioRestoreAt = nil
                if addon.fishing and addon.fishing.ClearNativeInteractOverride then
                    addon.fishing.ClearNativeInteractOverride()
                end
                if addon.frames.audioRestore then
                    addon.frames.audioRestore:Hide()
                end
                addon.audio.RestoreFishingAudioFocus()
                MaybeEquipConfiguredUnderlight("state-player-moving", true)
                frame:SetScript("OnUpdate", nil)
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            if addon.state.isFishing or addon.state.savedFishingAudioCVars ~= nil then
                LogStateTransition("combat-start-clears-fishing-session", event, spellID, isFishingSpell)
                addon.state.isFishing = false
                addon.state.isBobberActive = false
                addon.state.fishingCastActive = false
                addon.state.fishingLootInProgress = false
                addon.state.lastFishingCastStopAt = 0
                addon.state.interactAcquireExpiresAt = 0
                RestoreOriginalAutoLoot()
                addon.state.audioRestoreAt = nil
                if addon.fishing and addon.fishing.ClearNativeInteractOverride then
                    addon.fishing.ClearNativeInteractOverride()
                end
                if addon.frames.audioRestore then
                    addon.frames.audioRestore:Hide()
                end
                addon.audio.RestoreFishingAudioFocus()
                MaybeEquipConfiguredUnderlight("state-combat-start")
                frame:SetScript("OnUpdate", nil)
            end
        end
    end)

    addon.frames.state = frame
    CreateSwimmingStateMonitor()
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
    addon.state.fishingCastActive = (fishing and (not bobber)) and true or false
    addon.state.fishingLootInProgress = loot and true or false
end
addon._test.GetFishingFlags = function()
    return addon.state.isFishing, addon.state.isBobberActive, addon.state.fishingLootInProgress
end
addon._test.GetFishingStateFrame = function()
    return addon.frames.state
end
