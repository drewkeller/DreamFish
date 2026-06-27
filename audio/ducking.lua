-- DreamFisher: Audio Ducking and Focus

local addon = _G["DreamFisher"]
local Clamp = addon.Clamp
local PrintMessage = addon.PrintMessage

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

    addon.state.savedFishingAudioCVars = {
        ambience = GetCVar("Sound_AmbienceVolume"),
        music = GetCVar("Sound_MusicVolume"),
        dialog = GetCVar("Sound_DialogVolume"),
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
end

local function RestoreFishingAudioFocus()
    if addon.state.savedFishingAudioCVars == nil then
        return
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
        RestoreFishingAudioFocus()
        return
    end
    addon.state.audioLingerGeneration = addon.state.audioLingerGeneration + 1
    addon.state.audioRestoreAt = GetTime() + linger
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
