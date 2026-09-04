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

local FISHING_STATE_FLAGS = {
    [FISHING_STATES.IDLE]                    = { isFishing = false, isCastInProgress = false, isBobberActive = false, isCastActive = false, lootActive = false },
    [FISHING_STATES.PRECASTING]              = { isFishing = true,  isCastInProgress = true,  isBobberActive = false, isCastActive = false, lootActive = false },
    [FISHING_STATES.CASTING]                 = { isFishing = true,  isCastInProgress = true,  isBobberActive = false, isCastActive = true,  lootActive = false },
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
        ns.Utils.Print("|cFF999999[" .. (FISHING_STATE_NAMES[state] or tostring(state)) .. "]|r ", reason)
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

    if reason then
        Trace(state, reason)
    end

    local currentFlags = FISHING_STATE_FLAGS[self.state.current]
    if currentFlags then
        local oldState = self.state.current
        local wasCastActive = currentFlags.isCastActive
        local isCastActive = FISHING_STATE_FLAGS[state].isCastActive
        if wasCastActive and not isCastActive then
            ns.Utils.Print("Fishing cast ended: " .. (reason or "unknown reason"))
            self:SendMessage("FISHING_CAST_ENDED", oldState, state)
        end
    end

    self.state.current = state
    for key, value in pairs(FISHING_STATE_FLAGS[state]) do
        self.state[key] = value
    end
    if state == FISHING_STATES.IDLE then
        assert(not self.state.isFishing, "Fishing state IDLE should not be isFishing")
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
