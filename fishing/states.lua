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
    START_LINGER = 8,
    CANCELLING = 9,
}

local FISHING_STATE_FLAGS = {
    [FISHING_STATES.IDLE]                    = { isFishing = false, isCastInProgress = false, isBobberActive = false, castActive = false, lootActive = false },
    [FISHING_STATES.PRECASTING]              = { isFishing = true,  isCastInProgress = true,  isBobberActive = true,  castActive = false, lootActive = false },
    [FISHING_STATES.CASTING]                 = { isFishing = true,  isCastInProgress = true,  isBobberActive = false, castActive = true,  lootActive = false },
    [FISHING_STATES.WAITING_FOR_BITE]        = { isFishing = true,  isCastInProgress = true,  isBobberActive = false, castActive = false, lootActive = false },
    [FISHING_STATES.BITE_DETECTED]           = { isFishing = true,  isCastInProgress = true,  isBobberActive = true,  castActive = false, lootActive = false },
    [FISHING_STATES.WAITING_FOR_LOOT_WINDOW] = { isFishing = true,  isCastInProgress = true,  isBobberActive = true,  castActive = false, lootActive = false },
    [FISHING_STATES.LOOTING]                 = { isFishing = true,  isCastInProgress = false, isBobberActive = false, castActive = false, lootActive = true  },
    [FISHING_STATES.START_LINGER]            = { isFishing = true,  isCastInProgress = false, isBobberActive = false, castActive = false, lootActive = false },
    [FISHING_STATES.CANCELLING]              = { isFishing = false, isCastInProgress = false, isBobberActive = false, castActive = false, lootActive = false },
}

--[[
    Ace Events:
    - FISHING_SESSION_STARTED
    - FISHING_SESSION_ENDED
    - FISHING_CAST_STARTED
    - FISHING_CAST_ENDED
]]

ns.fishing = ns.fishing or {}
ns.fishing.state = ns.fishing.state or {}
ns.fishing.states = FISHING_STATES

local function Trace(state, reason)
    if DreamFish.db.profile.debugMode then
        DreamFish:Print("|cFF999999[", tostring(state), "]|r ", tostring(reason))
    end
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
end

function Fishing:IsInFishingSession()
    return ns.fishing.state.isFishing
end

Fishing:SetFishingState(FISHING_STATES.IDLE)
