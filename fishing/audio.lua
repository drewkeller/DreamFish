local addonName, ns = ...
local Fishing = ns.Fishing or LibStub("AceAddon-3.0"):GetAddon("DreamFish"):GetModule("Fishing")
local AudioMessageSink = {}

function AudioMessageSink:StartFishingAudioFocus(...)
    Fishing:StartFishingAudioFocus(...)
end

function AudioMessageSink:RestoreFishingAudioFocus(...)
    Fishing:RestoreFishingAudioFocus(...)
end

local globalDB, profileDB, charDB

Fishing:RegisterTraceSource("audio")
local function Trace(msg, ...)
    Fishing:Trace("audio", msg, ...)
end

Fishing:RegisterOnModuleInitialize(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

Fishing:RegisterOnModuleEnable(function(self)
    profileDB = self.db.profile
end)

Fishing:RegisterOnModuleRegisterEvents(function(self)
    Trace("Registering events")
    self.RegisterMessage(AudioMessageSink, "FISHING_SESSION_STARTED", "StartFishingAudioFocus")
    self.RegisterMessage(AudioMessageSink, "FISHING_SESSION_ENDED",   "RestoreFishingAudioFocus")
    self:ResumePersistedAudioDuckingState()
end)

Fishing:RegisterOnModuleUnregisterEvents(function(self)
    self.UnregisterMessage(AudioMessageSink, "FISHING_SESSION_STARTED")
    self.UnregisterMessage(AudioMessageSink, "FISHING_SESSION_ENDED")
end)

Fishing:RegisterOnModuleDisable(function(self)
    self:RestoreFishingAudioFocus()
end)

local Clamp = ns.Utils.Clamp
local NearlyEqual = ns.Utils.NearlyEqual
local CloneAudioTriplet = ns.Utils.CloneAudioTriplet

local function PersistAudioDuckingRuntimeState()
    if not globalDB then
        return
    end

    if type(ns.state.audio.savedFishingAudioCVars) == "table" then
        globalDB.runtimeAudioDucking = {
            saved = ns.Utils.CloneAudioTriplet(ns.state.audio.savedFishingAudioCVars),
            lastDucked = ns.Utils.CloneAudioTriplet(ns.state.audio.lastFishingDuckedAudioCVars),
        }
    else
        globalDB.runtimeAudioDucking = nil
    end
end

function Fishing:ResumePersistedAudioDuckingState()
    if not globalDB or ns.state.audio.savedFishingAudioCVars ~= nil then
        return
    end

    local persisted = globalDB.runtimeAudioDucking
    if type(persisted) ~= "table" or type(persisted.saved) ~= "table" then
        return
    end

    if type(GetCVar) == "function" and type(persisted.lastDucked) == "table" then
        local currentAmbience = GetCVar("Sound_AmbienceVolume")
        local currentMusic = GetCVar("Sound_MusicVolume")
        local currentDialog = GetCVar("Sound_DialogVolume")
        if not (NearlyEqual(currentAmbience, persisted.lastDucked.ambience)
            and NearlyEqual(currentMusic, persisted.lastDucked.music)
            and NearlyEqual(currentDialog, persisted.lastDucked.dialog)) then
            Trace("Audio duck resume skipped: persisted baseline does not match current CVars")
            globalDB.runtimeAudioDucking = nil
            return
        end
    end

    ns.state.audio.savedFishingAudioCVars = CloneAudioTriplet(persisted.saved)
    ns.state.audio.lastFishingDuckedAudioCVars = CloneAudioTriplet(persisted.lastDucked)
    Trace("Audio duck resume: restored active ducking state after reload")
end

function Fishing:EnableFishingAudioFocus(force)
    profileDB = self.db and self.db.profile or profileDB
    if not force and (not profileDB or not profileDB.audioFocusEnabled) then
        Trace("Audio duck skip: audioFocus disabled")
        return
    end
    if ns.state.audio.savedFishingAudioCVars ~= nil then
        Trace("Audio duck skip: already tracking saved CVars")
        return
    end
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then
        Trace("Audio duck skip: CVar API unavailable")
        return
    end

    local currentAmbience = GetCVar("Sound_AmbienceVolume")
    local currentMusic = GetCVar("Sound_MusicVolume")
    local currentDialog = GetCVar("Sound_DialogVolume")

    local lastDucked = ns.state.audio.lastFishingDuckedAudioCVars
    Trace("Audio duck eval: force=" .. tostring(force)
        .. " current={amb=" .. tostring(currentAmbience)
        .. ", mus=" .. tostring(currentMusic)
        .. ", dlg=" .. tostring(currentDialog) .. "}"
        .. " hasLastDucked=" .. tostring(type(lastDucked) == "table"))
    if type(lastDucked) == "table" then
        Trace("Audio duck baseline: lastDucked={amb=" .. tostring(lastDucked.ambience)
            .. ", mus=" .. tostring(lastDucked.music)
            .. ", dlg=" .. tostring(lastDucked.dialog) .. "}")
    else
        Trace("Audio duck note: no in-session duck baseline (possible UI reload before this cast)")
    end

    if type(lastDucked) == "table"
        and NearlyEqual(currentAmbience, lastDucked.ambience)
        and NearlyEqual(currentMusic, lastDucked.music)
        and NearlyEqual(currentDialog, lastDucked.dialog) then
        ns.state.audio.savedFishingAudioCVars = {
            ambience = currentAmbience,
            music = currentMusic,
            dialog = currentDialog,
        }
        PersistAudioDuckingRuntimeState()
        Trace("Audio duck skip: current levels already ducked or lower than prior duck target")
        return
    end

    ns.state.audio.savedFishingAudioCVars = {
        ambience = currentAmbience,
        music = currentMusic,
        dialog = currentDialog,
    }

    local ambienceVolume = tonumber(ns.state.audio.savedFishingAudioCVars.ambience)
    local ambienceFactor = tonumber(profileDB.ambienceDuckingLevel) / 100
    if ambienceVolume then
        SetCVar("Sound_AmbienceVolume", tostring(Clamp(ambienceVolume * ambienceFactor, 0, 1)))
    end

    local musicVolume = tonumber(ns.state.audio.savedFishingAudioCVars.music)
    local musicFactor = tonumber(profileDB.musicDuckingLevel) / 100
    if musicVolume then
        SetCVar("Sound_MusicVolume", tostring(Clamp(musicVolume * musicFactor, 0, 1)))
    end

    local dialogVolume = tonumber(ns.state.audio.savedFishingAudioCVars.dialog)
    local dialogFactor = tonumber(profileDB.dialogDuckingLevel) / 100
    if dialogVolume then
        SetCVar("Sound_DialogVolume", tostring(Clamp(dialogVolume * dialogFactor, 0, 1)))
    end

    ns.state.audio.lastFishingDuckedAudioCVars = {
        ambience = GetCVar("Sound_AmbienceVolume"),
        music = GetCVar("Sound_MusicVolume"),
        dialog = GetCVar("Sound_DialogVolume"),
    }
    PersistAudioDuckingRuntimeState()
    Trace("Audio duck apply: new={amb=" .. tostring(ns.state.audio.lastFishingDuckedAudioCVars.ambience)
        .. ", mus=" .. tostring(ns.state.audio.lastFishingDuckedAudioCVars.music)
        .. ", dlg=" .. tostring(ns.state.audio.lastFishingDuckedAudioCVars.dialog) .. "}")
end

function Fishing:RestoreFishingAudioFocus()
    if ns.state.audio.savedFishingAudioCVars == nil then
        return
    end
    Trace("Audio restoring")
    if type(SetCVar) ~= "function" then
        ns.state.audio.savedFishingAudioCVars = nil
        if ns.frames.audioRestore then
            ns.frames.audioRestore:Hide()
        end
        return
    end

    if ns.state.audio.savedFishingAudioCVars.ambience ~= nil then
        SetCVar("Sound_AmbienceVolume", ns.state.audio.savedFishingAudioCVars.ambience)
    end
    if ns.state.audio.savedFishingAudioCVars.music ~= nil then
        SetCVar("Sound_MusicVolume", ns.state.audio.savedFishingAudioCVars.music)
    end
    if ns.state.audio.savedFishingAudioCVars.dialog ~= nil then
        SetCVar("Sound_DialogVolume", ns.state.audio.savedFishingAudioCVars.dialog)
    end

    ns.state.audio.savedFishingAudioCVars = nil
    PersistAudioDuckingRuntimeState()
    if ns.frames.audioRestore then
        ns.frames.audioRestore:Hide()
    end
end

function Fishing:StartFishingAudioFocus()
    if ns.frames.audioRestore then
        ns.frames.audioRestore:Hide()
    end
    Trace("Audio focus start")
    self:EnableFishingAudioFocus()
end
