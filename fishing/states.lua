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
    [FISHING_STATES.IDLE]                    = { isFishing = false, isBobberActive = false, castActive = false, lootActive = false },
    [FISHING_STATES.PRECASTING]              = { isFishing = true,  isBobberActive = true,  castActive = false, lootActive = false },
    [FISHING_STATES.CASTING]                 = { isFishing = true,  isBobberActive = false, castActive = true,  lootActive = false },
    [FISHING_STATES.WAITING_FOR_BITE]        = { isFishing = true,  isBobberActive = false, castActive = false, lootActive = false },
    [FISHING_STATES.BITE_DETECTED]           = { isFishing = true,  isBobberActive = true,  castActive = false, lootActive = false },
    [FISHING_STATES.WAITING_FOR_LOOT_WINDOW] = { isFishing = true,  isBobberActive = true,  castActive = false, lootActive = false },
    [FISHING_STATES.LOOTING]                 = { isFishing = false, isBobberActive = false, castActive = false, lootActive = true  },
    [FISHING_STATES.START_LINGER]            = { isFishing = false, isBobberActive = false, castActive = false, lootActive = false },
    [FISHING_STATES.CANCELLING]              = { isFishing = false, isBobberActive = false, castActive = false, lootActive = false },
}

--[[
    Ace Events:
    - FISHING_SESSION_STARTED
    - FISHING_SESSION_ENDED
    - FISHING_CAST_STARTED
    - FISHING_CAST_ENDED
]]
