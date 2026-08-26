local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

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
    [FISHING_STATES.IDLE]                    = { isFishing = false, isCastInProgress = false, isBobberActive = false, castActive = false, lootActive = false },
    [FISHING_STATES.PRECASTING]              = { isFishing = true,  isCastInProgress = true,  isBobberActive = true,  castActive = false, lootActive = false },
    [FISHING_STATES.CASTING]                 = { isFishing = true,  isCastInProgress = true,  isBobberActive = false, castActive = true,  lootActive = false },
    [FISHING_STATES.WAITING_FOR_BITE]        = { isFishing = true,  isCastInProgress = true,  isBobberActive = false, castActive = false, lootActive = false },
    [FISHING_STATES.BITE_DETECTED]           = { isFishing = true,  isCastInProgress = true,  isBobberActive = true,  castActive = false, lootActive = false },
    [FISHING_STATES.WAITING_FOR_LOOT_WINDOW] = { isFishing = true,  isCastInProgress = true,  isBobberActive = true,  castActive = false, lootActive = false },
    [FISHING_STATES.LOOTING]                 = { isFishing = true,  isCastInProgress = false, isBobberActive = false, castActive = false, lootActive = true  },
    [FISHING_STATES.LINGERING]               = { isFishing = true,  isCastInProgress = false, isBobberActive = false, castActive = false, lootActive = false },
    [FISHING_STATES.CANCELLING]              = { isFishing = false, isCastInProgress = false, isBobberActive = false, castActive = false, lootActive = false },
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

ns.fishing = ns.fishing or {}
ns.fishing.state = ns.fishing.state or {}
ns.fishing.states = FISHING_STATES

Fishing:RegisterTraceSource("states")

local function Trace(state, reason)
    if Fishing.db and Fishing.db.profile and Fishing.db.profile.traceMode and Fishing.db.profile.traceMode["states"] then
        if DreamFish.db.profile.debugMode then
            DreamFish:Print("|cFF999999[", FISHING_STATE_NAMES[state] or tostring(state), "]|r ", tostring(reason))
        end
    end
end

function Fishing:IsFishingState(state)
    return ns.fishing.state.current == state
end

function Fishing:CurrentStateName()
    return FISHING_STATE_NAMES[ns.fishing.state.current] or tostring(ns.fishing.state.current)
end

function Fishing:SetFishingState(state, reason)
    assert(FISHING_STATE_FLAGS[state], "Unknown fishing state: " .. tostring(state))

    if reason then
        Trace(state, reason)
    end

    ns.fishing.state.current = state
    for key, value in pairs(FISHING_STATE_FLAGS[state]) do
        ns.fishing.state[key] = value
    end
    if state == FISHING_STATES.IDLE then
        assert(not ns.fishing.state.isFishing, "Fishing state IDLE should not be isFishing")
    end
end

function Fishing:IsInFishingSession()
    return ns.fishing.state.isFishing
end

function Fishing:CanStartCast()
    return ns.fishing.state.current == ns.fishing.states.IDLE
        or ns.fishing.state.current == ns.fishing.states.LINGERING
        or ns.fishing.state.current == ns.fishing.states.PRECASTING -- allow multiple stages to apply buffs, etc before cast
        or ns.fishing.state.current == ns.fishing.states.CASTING --recast for better placement, etc.
end

Fishing:SetFishingState(FISHING_STATES.IDLE)
