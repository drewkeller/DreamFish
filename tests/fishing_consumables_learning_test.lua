local now = 100
local bagCount = 1
local alertCount = 0

local Fishing = {
    state = {},
    db = {
        char = { buffs = { other_consumable = { { itemID = 274588, enabled = true } } } },
        global = { buffAuraByItem = {} },
    },
}

function Fishing:RegisterTraceSource()
end

function Fishing:RegisterOnModuleInitialize()
end

function Fishing:Trace()
end

function Fishing:Debug()
end

function Fishing:Print()
end

function Fishing:PrepareFishingClickAction()
end

local namespace = {
    SystemColor = {},
    Addon = {
        buff = {},
        SystemColor = {},
        GetDebugItemLabel = function(itemID)
            return tostring(itemID)
        end,
        Alert = function()
            alertCount = alertCount + 1
        end,
    },
    Fishing = Fishing,
    Utils = {
        CountItemInBags = function()
            return bagCount
        end,
        GetDebugItemLabel = function(_, itemID)
            return tostring(itemID)
        end,
        FormatDuration = function(_, duration)
            return tostring(duration)
        end,
    },
    precast = {},
    Fishing = Fishing,
}
namespace.Fishing.const = { knownBuffItems = {} }

function GetTime()
    return now
end

C_Item = {
    GetItemInfo = function(itemID)
        return tostring(itemID)
    end,
}

C_UnitAuras = {
    GetAuraDataByIndex = function(_, index)
        if index == 1 then
            return { spellId = 397827, duration = 3600, expirationTime = 3700 }
        end
        return nil
    end,
}

assert(loadfile("fishing/auras.lua"))("DreamFish", namespace)
assert(loadfile("fishing/precast/consumables.lua"))("DreamFish", namespace)

Fishing.state.pendingBuffUse = {
    uses = {
        {
            itemID = 274588,
            countBefore = 1,
            auraBefore = {},
            expiresAt = now + 5,
        },
    },
}
bagCount = 0
Fishing:ConfirmPendingBuffUse()

assert(Fishing.state.pendingBuffObservation, "confirmed unknown consumable should enter learning mode")
Fishing:UpdatePendingBuffObservation()
assert(Fishing.db.global.buffAuraByItem["274588"] == nil,
    "an aura already active at consumable confirmation must not be learned for the item")

namespace.Fishing.const.knownBuffItems[274588] = {
    spellID = 1303623,
    duration = 30,
    category = "other_consumable",
}
Fishing.db.global.buffAuraByItem["274588"] = {
    spellID = 1303623,
    duration = 43.72,
}
Fishing:GetTrackedBuffRemaining(274588)
assert(Fishing.db.global.buffAuraByItem["274588"].duration == 30,
    "known aura duration must replace a stale learned duration")

Fishing.state.fishingSessionGeneration = 2
local alertsBeforeStaleFailure = alertCount
Fishing.state.pendingBuffUse = {
    executedAt = now,
    uses = {
        { itemID = 274588, expiresAt = now },
    },
    sessionGeneration = 1,
}
Fishing:ConfirmPendingBuffUse()
assert(alertCount == alertsBeforeStaleFailure,
    "a stale consumable failure after cast cancellation must be silent")

print("fishing_consumables_learning_test: passed")
