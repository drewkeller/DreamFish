-- DreamFisher: Audio Ducking and Focus

local addon = _G["DreamFisher"]
local Clamp = addon.Clamp
local PrintMessage = addon.PrintMessage
local DebugMessage = addon.DebugMessage

local function GetFishingElapsedSeconds()
    if type(GetTime) ~= "function" then
        return 0
    end
    local startedAt = tonumber(addon.state and addon.state.fishingStartTime) or 0
    if startedAt <= 0 then
        return 0
    end
    return math.max(0, GetTime() - startedAt)
end

local function ToNumberOrNil(value)
    local n = tonumber(value)
    if not n then
        return nil
    end
    return n
end

local function NearlyEqual(a, b)
    local na = ToNumberOrNil(a)
    local nb = ToNumberOrNil(b)
    if not na or not nb then
        return false
    end
    return math.abs(na - nb) <= 0.0001
end

local function EnableFishingAudioFocus(force)
    if not force and (not addon.db or not addon.db.enhancedSounds) then
        return
    end
    if addon.state.savedFishingAudioCVars ~= nil then
        return
    end
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then
        return
    end

    local currentAmbience = GetCVar("Sound_AmbienceVolume")
    local currentMusic = GetCVar("Sound_MusicVolume")
    local currentDialog = GetCVar("Sound_DialogVolume")

    local lastDucked = addon.state.lastFishingDuckedAudioCVars
    if type(lastDucked) == "table"
        and NearlyEqual(currentAmbience, lastDucked.ambience)
        and NearlyEqual(currentMusic, lastDucked.music)
        and NearlyEqual(currentDialog, lastDucked.dialog) then
        addon.state.savedFishingAudioCVars = {
            ambience = currentAmbience,
            music = currentMusic,
            dialog = currentDialog,
        }
        return
    end

    addon.state.savedFishingAudioCVars = {
        ambience = currentAmbience,
        music = currentMusic,
        dialog = currentDialog,
    }

    local ambienceVolume = tonumber(addon.state.savedFishingAudioCVars.ambience)
    if ambienceVolume then
        SetCVar("Sound_AmbienceVolume", tostring(Clamp(ambienceVolume * 0.35, 0, 1)))
    end

    local musicVolume = tonumber(addon.state.savedFishingAudioCVars.music)
    if musicVolume then
        SetCVar("Sound_MusicVolume", tostring(Clamp(musicVolume * 0.2, 0, 1)))
    end

    local dialogVolume = tonumber(addon.state.savedFishingAudioCVars.dialog)
    if dialogVolume then
        SetCVar("Sound_DialogVolume", tostring(Clamp(dialogVolume * 0.5, 0, 1)))
    end

    addon.state.lastFishingDuckedAudioCVars = {
        ambience = GetCVar("Sound_AmbienceVolume"),
        music = GetCVar("Sound_MusicVolume"),
        dialog = GetCVar("Sound_DialogVolume"),
    }
end

local function RestoreFishingAudioFocus()
    if addon.state.savedFishingAudioCVars == nil then
        return
    end
    if addon.db and addon.db.debugMode and DebugMessage then
        DebugMessage("Audio restore now: elapsed=" .. string.format("%.3f", GetFishingElapsedSeconds())
            .. " isFishing=" .. tostring(addon.state and addon.state.isFishing)
            .. " isBobberActive=" .. tostring(addon.state and addon.state.isBobberActive)
            .. " lootInProgress=" .. tostring(addon.state and addon.state.fishingLootInProgress))
    end
    if type(SetCVar) ~= "function" then
        addon.state.savedFishingAudioCVars = nil
        addon.state.audioRestoreAt = nil
        if addon.frames.audioRestore then
            addon.frames.audioRestore:Hide()
        end
        return
    end

    if addon.state.savedFishingAudioCVars.ambience ~= nil then
        SetCVar("Sound_AmbienceVolume", addon.state.savedFishingAudioCVars.ambience)
    end
    if addon.state.savedFishingAudioCVars.music ~= nil then
        SetCVar("Sound_MusicVolume", addon.state.savedFishingAudioCVars.music)
    end
    if addon.state.savedFishingAudioCVars.dialog ~= nil then
        SetCVar("Sound_DialogVolume", addon.state.savedFishingAudioCVars.dialog)
    end

    addon.state.savedFishingAudioCVars = nil
    addon.state.audioRestoreAt = nil
    if addon.frames.audioRestore then
        addon.frames.audioRestore:Hide()
    end
end

local function RestoreFishingAudioFocusAfterLinger()
    local linger = (addon.db and addon.db.audioFocusLinger) or addon.defaults.audioFocusLinger
    if linger <= 0 then
        if addon.db and addon.db.debugMode and DebugMessage then
            DebugMessage("Audio restore linger skipped (linger<=0)")
        end
        RestoreFishingAudioFocus()
        return
    end
    addon.state.audioLingerGeneration = addon.state.audioLingerGeneration + 1
    addon.state.audioRestoreAt = GetTime() + linger
    if addon.db and addon.db.debugMode and DebugMessage then
        DebugMessage("Audio restore scheduled: in=" .. string.format("%.3f", linger)
            .. "s at=" .. string.format("%.3f", addon.state.audioRestoreAt)
            .. " elapsed=" .. string.format("%.3f", GetFishingElapsedSeconds()))
    end
    if not addon.frames.audioRestore then
        addon.frames.audioRestore = CreateFrame("Frame")
        addon.frames.audioRestore:Hide()
        addon.frames.audioRestore:SetScript("OnUpdate", function(self)
            if not addon.state.audioRestoreAt then
                self:Hide()
                return
            end
            if GetTime() >= addon.state.audioRestoreAt then
                addon.state.audioRestoreAt = nil
                self:Hide()
                RestoreFishingAudioFocus()
            end
        end)
    end
    addon.frames.audioRestore:Show()
end

local function StartFishingAudioFocus()
    addon.state.audioLingerGeneration = addon.state.audioLingerGeneration + 1
    addon.state.fishingStartTime = GetTime()
    addon.state.fishingStartGraceUntil = addon.state.fishingStartTime + 1.5
    addon.state.audioRestoreAt = nil
    if addon.frames.audioRestore then
        addon.frames.audioRestore:Hide()
    end
    if addon.db and addon.db.debugMode and DebugMessage then
        DebugMessage("Audio focus start: start=" .. string.format("%.3f", addon.state.fishingStartTime)
            .. " graceUntil=" .. string.format("%.3f", addon.state.fishingStartGraceUntil))
    end
    EnableFishingAudioFocus()
end

local function PlayWarningCue()
    if type(PlaySound) == "function" and SOUNDKIT then
        local cue = SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.UI_RaidBossEmoteWarning
        if cue then
            PlaySound(cue, "Master")
        end
    end
end

-- Export to addon
addon.audio = addon.audio or {}
addon.audio.EnableFishingAudioFocus = EnableFishingAudioFocus
addon.audio.RestoreFishingAudioFocus = RestoreFishingAudioFocus
addon.audio.RestoreFishingAudioFocusAfterLinger = RestoreFishingAudioFocusAfterLinger
addon.audio.StartFishingAudioFocus = StartFishingAudioFocus
addon.audio.PlayWarningCue = PlayWarningCue

-- Test hooks
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
    return addon.state.savedFishingAudioCVars ~= nil
end
addon._test.GetAudioRestoreAt = function()
    return addon.state.audioRestoreAt
end
