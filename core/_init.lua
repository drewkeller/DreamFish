local addonName, ns = ...
Addon = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
ns.Addon = Addon

ns.AddonInitializers = ns.AddonInitializers or {}

ns.logLevel = {}
ns.logLevelInfo = {
    { value = 1, name = "TRACE", color = "667788", },
    { value = 2, name = "DEBUG", color = "336699", },
    { value = 3, name = "INFO",  color = "60B6F6", },
    { value = 4, name = "WARN",  color = "FFA500", },
    { value = 5, name = "ERROR", color = "D83D65", },
}
for _, info in pairs(ns.logLevelInfo) do
    ns.logLevelInfo[info.name] = info   -- info: logLevelInfo["TRACE"]
    ns.logLevelInfo[info.value] = info  -- info: logLevelInfo[1]
    ns.logLevel[info.name] = info.value -- flat: logLevel.TRACE
end

ns.state = {
    audio ={
        lastFishingDuckedAudioCVars = nil,
        savedFishingAudioCVars = nil,
        audioLingerGeneration = 0,
        audioRestoreAt = nil,
        fishingStartTime = nil,
        fishingSessionState = nil,
        fishingStartGraceUntil = nil,
    }
}

ns.frames = {
    audioRestore = nil,
}

function Addon:InitializeTraceSources()
    if self.pendingCoreTraces then
        for _, source in ipairs(self.pendingCoreTraces) do
            --Addon:Print("Registering trace source: " .. tostring(source))
            self:RegisterTraceSource(source)
        end
        self.pendingCoreTraces = nil
    end
end

function Addon:RegisterTraceSource(source)
    if not self.db or not self.db.profile then
        -- Caches traces if registered at file-load time before OnInitialize runs
        self.pendingCoreTraces = self.pendingCoreTraces or {}
        table.insert(self.pendingCoreTraces, source)
        return
    end

    -- Ensure the tables exist in your main SavedVariables profile
    self.db.profile.traces = self.db.profile.traces or {}

    if self.db.profile.traces[source] == nil then
        --Addon:Print("Initializing trace source: " .. tostring(source))
        self.db.profile.traces[source] = false -- Disabled by default
    end
end

--ns.AddonInitializers = ns.AddonInitializers or {}
