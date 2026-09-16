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

function Fishing:RegisterOnModuleInitialize(callback)
    callback(self)
end

function Fishing:Trace()
end

function Fishing:Debug()
end

function Fishing:Print()
end

function Fishing:Info()
end

function Fishing:PrepareFishingClickAction()
end

function Fishing:ScheduleTimer()
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
        Print = function()
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
        FormatDuration = function(duration)
            return tostring(duration)
        end,
    },
    precast = {},
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
assert(Fishing.db.global.buffAuraByItem["274588"].isInstant == true,
    "confirming an unconfigured consumable with no observed cast bar should learn it as instant-use")
Fishing:UpdatePendingBuffObservation()
assert(Fishing.db.global.buffAuraByItem["274588"].spellID == nil,
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
Fishing.state.pendingBuffUse = {
    uses = {
        { itemID = 274588, countBefore = 1, expiresAt = now + 5 },
    },
}
bagCount = 0
Fishing:ConfirmPendingBuffUse()
assert(Fishing.db.global.buffAuraByItem["274588"].isInstant == nil,
    "learned metadata must not override an authoritative known item")
Fishing:GetTrackedBuffRemaining(274588)
assert(Fishing.db.global.buffAuraByItem["274588"].duration == 30,
    "known aura duration must replace a stale learned duration")

Fishing.state.fishingSessionGeneration = 2
local alertsBeforeStaleFailure = alertCount
Fishing.state.pendingBuffUse = {
    executedAt = now,
    uses = {
        { itemID = 274588, expiresAt = now, sessionGeneration = 1 },
    },
}
Fishing:ConfirmPendingBuffUse()
assert(alertCount == alertsBeforeStaleFailure,
    "a stale consumable failure after cast cancellation must be silent")

Fishing.db.char.buffs.other_consumable = {
    { itemID = 238365, enabled = true },
    { itemID = 274588, enabled = true },
    { itemID = 238367, enabled = true },
    { itemID = 274587, enabled = true },
}
namespace.Fishing.const.knownBuffItems = {
    [238365] = { spellID = 1303623, duration = 30, castTime = 0, category = "other_consumable" },
    [274588] = { spellID = 1303623, duration = 30, castTime = 0, category = "other_consumable" },
    [238367] = { spellID = 1303624, duration = 30, castTime = 0, category = "other_consumable" },
    [274587] = { spellID = 1303624, duration = 30, castTime = 0, category = "other_consumable" },
}
namespace.Fishing.const.maxFishingCastSeconds = 30
namespace.Fishing.const.buffPreRefreshSafetySeconds = 5
local rootCrabTiming = Fishing:GetBuffTimingText(238367)
assert(not rootCrabTiming:find("learning", 1, true),
    "Root Crab has built-in spell metadata and must not be marked as learning")
assert(rootCrabTiming:find("item=30", 1, true),
    "Root Crab timing should use its built-in duration")
namespace.Utils.IsCooldownReady = function()
    return true
end
namespace.Utils.FindItemInBags = function()
    return true
end
Fishing.state.pendingBuffUse = nil
Fishing.state.pendingBuffObservation = nil
Fishing.state.buffItemLastUseAt = {}

local learningCandidates = Fishing:GetBuffLearningCandidates()
assert(#learningCandidates == 0, "built-in consumables must not be selected for learning")

namespace.Fishing.const.knownBuffItems = {}
Fishing.db.global.buffAuraByItem = {}
Fishing.db.char.buffs.other_consumable = { { itemID = 274588, enabled = true } }
local candidate = Fishing:GetBuffLearningStatus()
assert(candidate and candidate.itemID == 274588, "an enabled unknown item should be the next learning candidate")
assert(Fishing:BeginBuffLearning(candidate), "learning should start for the selected candidate")
assert(Fishing.state.buffLearning.itemID == 274588, "learning state should retain the selected item")
Fishing:MarkBuffLearningExecuted()
assert(Fishing.state.pendingBuffUse.executedAt == now, "learning click should mark the pending use executed")
now = now + 6
Fishing:ConfirmPendingBuffUse()
assert(Fishing.db.char.buffs.other_consumable[1].enabled == false,
    "an unconfirmed learning item should be disabled")
Fishing.state.buffLearning = nil
Fishing.state.pendingBuffUse = nil
now = 100
namespace.Fishing.const.knownBuffItems = {
    [238365] = { spellID = 1303623, duration = 30, castTime = 0, category = "other_consumable" },
    [274588] = { spellID = 1303623, duration = 30, castTime = 0, category = "other_consumable" },
    [238367] = { spellID = 1303624, duration = 30, castTime = 0, category = "other_consumable" },
    [274587] = { spellID = 1303624, duration = 30, castTime = 0, category = "other_consumable" },
}
Fishing.db.char.buffs.other_consumable = {
    { itemID = 238365, enabled = true },
    { itemID = 274588, enabled = true },
    { itemID = 238367, enabled = true },
    { itemID = 274587, enabled = true },
}

Fishing.state.buffUnknownDurationSuppressed = { [274588] = true }
local permanentlySuppressedDecision = namespace.precast.GetConsumableUseDecision(Fishing, false)
assert(permanentlySuppressedDecision.shouldApply == true,
    "a permanently suppressed item should not prevent other configured consumables")
for _, item in ipairs(permanentlySuppressedDecision.items) do
    assert(item.itemID ~= 274588, "a boolean-suppressed consumable must not be queued")
end

Fishing.state.pendingBuffUse = nil
Fishing.state.buffUnknownDurationSuppressed = { [274588] = now - 1 }
namespace.precast.GetConsumableUseDecision(Fishing, false)
assert(Fishing.state.buffUnknownDurationSuppressed[274588] == nil,
    "an expired numeric consumable suppression should be cleared")

Fishing.state.pendingBuffUse = nil
Fishing.state.buffUnknownDurationSuppressed = {}

local decision = namespace.precast.GetConsumableUseDecision(Fishing, false)
assert(decision.shouldApply == true, "due consumables should be selected")
assert(#decision.items == 2, "only one consumable per shared effect spell should be queued")
local queuedSpellIDs = {}
for _, item in ipairs(decision.items) do
    queuedSpellIDs[namespace.Fishing.const.knownBuffItems[item.itemID].spellID] = true
end
assert(queuedSpellIDs[1303623] and queuedSpellIDs[1303624],
    "one consumable from each distinct effect spell should be queued")

print("fishing_consumables_learning_test: passed")
