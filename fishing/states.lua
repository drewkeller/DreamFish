local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

local FISHING_STATES = {
    IDLE = 1,
    PRECASTING = 2,
    CASTING = 3,
    WAITING_FOR_BITE = 4,
    BITE_DETECTED = 5,
    WAITING_FOR_LOOT_WINDOW = 6,
    LOOTING = 7,
    LINGERING = 8,
    CANCELLING = 9,
}

local FISHING_STATE_NAMES = {}
for name, value in pairs(FISHING_STATES) do
    FISHING_STATE_NAMES[value] = name
end

local sessionStarted = false

local FISHING_STATE_FLAGS = {
    [FISHING_STATES.IDLE]                    = { isFishing = false, isCastInProgress = false, isBobberActive = false, isCastActive = false, lootActive = false },
    [FISHING_STATES.PRECASTING]              = { isFishing = true,  isCastInProgress = true,  isBobberActive = false, isCastActive = false, lootActive = false },
    [FISHING_STATES.CASTING]                 = { isFishing = true,  isCastInProgress = true,  isBobberActive = false, isCastActive = false, lootActive = false },
    [FISHING_STATES.WAITING_FOR_BITE]        = { isFishing = true,  isCastInProgress = true,  isBobberActive = false, isCastActive = true,  lootActive = false },
    [FISHING_STATES.BITE_DETECTED]           = { isFishing = true,  isCastInProgress = true,  isBobberActive = true,  isCastActive = false, lootActive = false },
    [FISHING_STATES.WAITING_FOR_LOOT_WINDOW] = { isFishing = true,  isCastInProgress = true,  isBobberActive = true,  isCastActive = false, lootActive = false },
    [FISHING_STATES.LOOTING]                 = { isFishing = true,  isCastInProgress = false, isBobberActive = false, isCastActive = false, lootActive = true  },
    [FISHING_STATES.LINGERING]               = { isFishing = true,  isCastInProgress = false, isBobberActive = false, isCastActive = false, lootActive = false },
    [FISHING_STATES.CANCELLING]              = { isFishing = false, isCastInProgress = false, isBobberActive = false, isCastActive = false, lootActive = false },
}

--[[
    Ace Events:
    - FISHING_SESSION_STARTED
    - FISHING_SESSION_ENDED
    - FISHING_CAST_STARTED
    - FISHING_CAST_ENDED
    - FISHING_LOOT_READY
    - FISHING_LOOT_CLOSED
]]

Fishing.state = Fishing.state or {}
ns.Fishing.states = FISHING_STATES

Fishing:RegisterOnModuleInitialize(function(self)
    self.state.current = FISHING_STATES.IDLE
    for key, value in pairs(FISHING_STATE_FLAGS[FISHING_STATES.IDLE]) do
        self.state[key] = value
    end
end)

Fishing:RegisterTraceSource("states")

local function Trace(state, reason)
    if Fishing.db and Fishing.db.profile and Fishing.db.profile.traces and Fishing.db.profile.traces["states"] then
        ns.Utils.DebugModuleSource(ns.logLevel.DEBUG, Fishing, (FISHING_STATE_NAMES[state] or tostring(state)), (reason or "unknown reason"))
    end
end

function Fishing:IsFishingState(state)
    return self.state.current == state
end

function Fishing:CurrentStateName()
    return FISHING_STATE_NAMES[self.state.current] or tostring(self.state.current)
end

function Fishing:SetFishingState(state, reason)
    assert(FISHING_STATE_FLAGS[state], "Unknown fishing state: " .. tostring(state))
    local oldState = self.state.current

    if reason then
        Trace(state, reason)
    end

    local currentFlags = FISHING_STATE_FLAGS[self.state.current]
    if currentFlags then
        local wasFishing = currentFlags.isFishing
        local isFishing = FISHING_STATE_FLAGS[state].isFishing
        local wasCastActive = currentFlags.isCastActive
        local isCastActive = FISHING_STATE_FLAGS[state].isCastActive
        if not wasCastActive and isCastActive then
            -- Only start session if cast is successful, prevent misclick from fading out UI, etc.
            if not sessionStarted then
                Trace(state, "Fishing session started: " .. (reason or "unknown reason"))
                self:SendMessage("FISHING_SESSION_STARTED", oldState, state)
                sessionStarted = true
            end
            Trace(state, "Fishing cast started: " .. (reason or "unknown reason"))
            self:SendMessage("FISHING_CAST_STARTED", oldState, state)
        end
        if wasCastActive and not isCastActive then
            Trace(state, "Fishing cast ended: " .. (reason or "unknown reason"))
            self:SendMessage("FISHING_CAST_ENDED", oldState, state)
        end

        if wasFishing and not isFishing then
            Trace(state, "Fishing session ended: " .. (reason or "unknown reason"))
            sessionStarted = false
            self:SendMessage("FISHING_SESSION_ENDED", oldState, state)
        end
    end

    if oldState == FISHING_STATES.PRECASTING and state ~= FISHING_STATES.PRECASTING then
        self.state.precastArmedItemIDs = nil
        self.state.precastItemSpellStarted = nil
        if type(self.ClearPrecastConsumableSnapshot) == "function" then
            self:ClearPrecastConsumableSnapshot("leaving PRECAST")
        else
            self.state.precastConsumableSnapshot = nil
        end
        if type(self.ClearPrecastSwimmingWatch) == "function" then
            self:ClearPrecastSwimmingWatch()
        else
            self.state.precastSwimmingWatchTimer = nil
        end
    end

    self.state.current = state
    for key, value in pairs(FISHING_STATE_FLAGS[state]) do
        self.state[key] = value
    end
    if state == FISHING_STATES.IDLE then
        assert(not self.state.isFishing, "Fishing state IDLE should not be isFishing")
    end

    if currentFlags and currentFlags ~= FISHING_STATE_FLAGS[state] then
        local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
        if AceConfigRegistry then
            AceConfigRegistry:NotifyChange(addonName .. "Dialog")
        end
    end
end

function Fishing:IsInFishingSession()
    return self.state.isFishing
end

function Fishing:CanStartCast()
    return self.state.current == FISHING_STATES.IDLE
        or self.state.current == FISHING_STATES.LINGERING
        or self.state.current == FISHING_STATES.PRECASTING -- allow multiple stages to apply buffs, etc before cast
        or self.state.current == FISHING_STATES.CASTING --recast for better placement, etc.
end

Fishing:SetFishingState(FISHING_STATES.IDLE)
