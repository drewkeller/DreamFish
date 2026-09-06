local addonName, ns = ...
local Fishing = ns.Fishing or LibStub("AceAddon-3.0"):GetAddon("DreamFish"):GetModule("Fishing")

local globalDB, profileDB, charDB
Fishing:RegisterOnModuleInitialize(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

Fishing:RegisterOnModuleEnable(function(self)
    profileDB = self.db.profile
    self:RegisterMessage("FISHING_SESSION_STARTED", "StartFishingAudioFocus")
    self:RegisterMessage("FISHING_SESSION_ENDED", "RestoreFishingAudioFocus")
    self:ResumePersistedAudioDuckingState()
end)

function Fishing:OnModuleDisable()
    self:UnregisterMessage("FISHING_SESSION_STARTED")
    self:UnregisterMessage("FISHING_SESSION_ENDED")
end

Fishing:RegisterTraceSource("audio")

local function Trace(msg, ...)
    Fishing:Trace("audio", msg, ...)
end

local Clamp = ns.Utils.Clamp
local NearlyEqual = ns.Utils.NearlyEqual
local CloneAudioTriplet = ns.Utils.CloneAudioTriplet

-- local function GetFishingElapsedSeconds()
--     if type(GetTime) ~= "function" then
--         return 0
--     end
--     local startedAt = tonumber(ns.audio.state and ns.state.audio.fishingStartTime) or 0
--     if startedAt <= 0 then
--         return 0
--     end
--     return math.max(0, GetTime() - startedAt)
-- end

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
    if ambienceVolume then
        SetCVar("Sound_AmbienceVolume", tostring(Clamp(ambienceVolume * 0.35, 0, 1)))
    end

    local musicVolume = tonumber(ns.state.audio.savedFishingAudioCVars.music)
    if musicVolume then
        SetCVar("Sound_MusicVolume", tostring(Clamp(musicVolume * 0.2, 0, 1)))
    end

    local dialogVolume = tonumber(ns.state.audio.savedFishingAudioCVars.dialog)
    if dialogVolume then
        SetCVar("Sound_DialogVolume", tostring(Clamp(dialogVolume * 0.5, 0, 1)))
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
    Trace("Audio restore now: " .. " sessionState=" .. tostring(ns.state.audio.fishingSessionState))
    if type(SetCVar) ~= "function" then
        ns.state.audio.savedFishingAudioCVars = nil
        ns.state.audio.audioRestoreAt = nil
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
    ns.state.audio.audioRestoreAt = nil
    PersistAudioDuckingRuntimeState()
    if ns.frames.audioRestore then
        ns.frames.audioRestore:Hide()
    end
end

function Fishing:ScheduleRestoreFishingAudioFocus()
    local linger = profileDB and profileDB.focusedAudioLinger
    if linger <= 0 then
        Trace("Audio restore linger skipped (linger<=0)")
        self:RestoreFishingAudioFocus()
        return
    end
    ns.state.audio.audioLingerGeneration = ns.state.audio.audioLingerGeneration + 1
    ns.state.audio.audioRestoreAt = GetTime() + linger
    Trace("Audio restore scheduled: in=" .. string.format("%.3f", linger)
        .. "s at=" .. string.format("%.3f", ns.state.audio.audioRestoreAt))
    if not ns.frames.audioRestore then
        ns.frames.audioRestore = CreateFrame("Frame")
        ns.frames.audioRestore:Hide()
        ns.frames.audioRestore:SetScript("OnUpdate", function(self)
            if not ns.state.audio.audioRestoreAt then
                self:Hide()
                return
            end
            if GetTime() >= ns.state.audio.audioRestoreAt then
                ns.state.audio.audioRestoreAt = nil
                self:Hide()
                self:RestoreFishingAudioFocus()
            end
        end)
    end
    ns.frames.audioRestore:Show()
end

function Fishing:StartFishingAudioFocus()
    ns.state.audio.audioLingerGeneration = ns.state.audio.audioLingerGeneration + 1
    ns.state.audio.fishingStartTime = GetTime()
    ns.state.audio.fishingStartGraceUntil = ns.state.audio.fishingStartTime + 1.5
    ns.state.audio.audioRestoreAt = nil
    if ns.frames.audioRestore then
        ns.frames.audioRestore:Hide()
    end
    Trace("Audio focus start: start=" .. string.format("%.3f", ns.state.audio.fishingStartTime)
        .. " graceUntil=" .. string.format("%.3f", ns.state.audio.fishingStartGraceUntil))
    self:EnableFishingAudioFocus()
end
