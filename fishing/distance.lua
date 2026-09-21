local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

local MessageSink = ns.MessageSink:new(Fishing)

local state = {
    distance = 0,
    lastMapID = nil,
    lastX = nil,
    lastY = nil,
    lastFishingState = nil,
}

local globalDB, profileDB, charDB
Fishing:RegisterOnModuleInitialize(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

Fishing:RegisterTraceSource("distance")
local function Trace(msg)
    Fishing:Trace("distance", msg)
end

local SAMPLE_INTERVAL = 0.25
local ResetMovement, StopMonitoringMovement, OnDistanceReached

Fishing:RegisterOnModuleEnable(function(self)
end)

Fishing:RegisterOnModuleRegisterEvents(function(self)
    if profileDB.movementCancelsFishing == true then
        ResetMovement("Module enabled")
        MessageSink:RegisterEvent("PLAYER_ENTERING_WORLD", "PLAYER_ENTERING_WORLD")
        MessageSink:RegisterEvent("PLAYER_STARTED_MOVING", "PLAYER_STARTED_MOVING")
        MessageSink:RegisterMessage("FISHING_CAST_STARTED", "FISHING_CAST_STARTED")
        MessageSink:RegisterMessage("FISHING_SESSION_STARTED", "FISHING_SESSION_STARTED")
        MessageSink:RegisterMessage("FISHING_SESSION_ENDED", "FISHING_SESSION_ENDED")
    end
end)

function MessageSink:PLAYER_ENTERING_WORLD(...)
    ResetMovement("Player entering world")
end

Fishing:RegisterOnModuleUnregisterEvents(function(self)
    MessageSink:UnregisterEvent("PLAYER_ENTERING_WORLD")
    MessageSink:UnregisterEvent("PLAYER_STARTED_MOVING")
    MessageSink:UnregisterMessage("FISHING_CAST_STARTED")
    MessageSink:UnregisterMessage("FISHING_SESSION_STARTED")
    MessageSink:UnregisterMessage("FISHING_SESSION_ENDED")
end)

Fishing:RegisterOnModuleDisable(function(self)
    StopMonitoringMovement()
end)

ResetMovement = function(reason)
    state.distance = 0
    state.lastMapID = nil
    state.lastX = nil
    state.lastY = nil
    Trace(("Distance reset: %s"):format(reason or "unspecified"))
end

local function StartMonitoringMovement()
    -- prevent duplication of movement monitors
    if state.movementTimer then return end

    ResetMovement("Started monitor")
    state.movementTimer = Fishing:ScheduleRepeatingTimer(
        "AccumulateMovement",
        SAMPLE_INTERVAL
    )
end

StopMonitoringMovement = function()
    if state.movementTimer then
        Fishing:CancelTimer(state.movementTimer)
        state.movementTimer = nil
    end

    ResetMovement("Stopped monitor")
end

OnDistanceReached = function(distance)
    Trace(("Target distance reached: %.1f units"):format(distance))
    Fishing:EndFishingSession("cancelled by movement")
end

function MessageSink:FISHING_CAST_STARTED()
    ResetMovement("Fishing cast started")
end

function MessageSink:FISHING_SESSION_STARTED()
    if profileDB.movementCancelsFishing == true and profileDB.movementAmountToCancelFishing > 0 then
        StartMonitoringMovement()
    end
end

function MessageSink:FISHING_SESSION_ENDED()
    StopMonitoringMovement()
end

function MessageSink:PLAYER_STARTED_MOVING()
    if not Fishing:IsInFishingSession() then return end
    Trace("Player started moving")
    if profileDB.movementCancelsFishing == true and profileDB.movementAmountToCancelFishing == 0 then
        OnDistanceReached(state.distance)
    end
end

function Fishing:AccumulateMovement()
    local mapID = C_Map.GetBestMapForUnit("player")
    local x, y = UnitPosition("player")

    if not mapID or not x or not y then
        ResetMovement("Map or position unavailable")
        return
    end

    if not Fishing:IsInFishingSession() then return end

    -- Establish a new baseline after loading, zoning, phasing, or teleporting.
    if mapID ~= state.lastMapID then
        state.lastMapID = mapID
        state.lastX = x
        state.lastY = y
        return
    end

    if state.lastX and state.lastY then
        local dx = x - state.lastX
        local dy = y - state.lastY
        local delta = math.sqrt(dx * dx + dy * dy)

        state.distance = state.distance + delta
        if delta >= 10 then
            Trace(("Movement detected: %.1f units"):format(delta))
        end

        if state.distance >= profileDB.movementAmountToCancelFishing then
            OnDistanceReached(state.distance)

            -- Reset for another threshold interval.
            state.distance = 0
        end
    end

    state.lastX = x
    state.lastY = y
end
