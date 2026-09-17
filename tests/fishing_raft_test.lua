local shapeshiftForm = 1
local now = 10
local swimming = true
local usedToyID
local alerts = {}
local prints = {}
local guidanceShown = false

function GetShapeshiftForm()
    return shapeshiftForm
end

function IsSwimming()
    return swimming
end

function GetTime()
    return now
end

function UseToyByName(toyID)
    usedToyID = toyID
end

C_Item = {
    GetItemSpell = function()
        return "Anglers Fishing Raft", 12345
    end,
}

local frameAttributes = {}
local Fishing = {
    db = {
        profile = {
            selectedRaftToy = 85500,
            selectedBobberToy = 0,
        },
        global = {},
        char = { buffs = {} },
    },
    const = {
        maxFishingCastSeconds = 30,
        buffPreRefreshSafetySeconds = 5,
        oversizedBobberItemID = 202207,
    },
    state = {
        isEquippingPrimaryPole = false,
        raftToyLastUseAt = {},
    },
    clickFrame = {
        SetAttribute = function(_, name, value)
            frameAttributes[name] = value
        end,
    },
}

function Fishing:RegisterTraceSource()
end

function Fishing:Trace()
end

function Fishing:RegisterOnModuleInitialize(callback)
    callback(self)
end

function Fishing:ShowPrecastSwimmingGuidance(options)
    guidanceShown = options and options.allowClimb == true
end

local Addon = {}

function Addon:Alert(_, message)
    table.insert(alerts, message)
end

function Addon:Print(message)
    table.insert(prints, message)
end

local namespace = {
    Addon = Addon,
    Fishing = Fishing,
    SystemColor = { RED = {} },
    Utils = {
        IsToyOwned = function()
            return true
        end,
        IsCooldownReady = function()
            return true
        end,
        GetDebugItemLabel = function(itemID)
            return tostring(itemID)
        end,
        GetDebugCooldownText = function()
            return "cooldown=ready"
        end,
    },
    GetAuraBySpellID = function()
        return nil
    end,
    precast = {},
}

assert(loadfile("fishing/precast/raft.lua"))("DreamFish", namespace)

local decision = namespace.precast.GetRaftUseDecision(Fishing)
assert(decision.blockedByShapeshift == true, "shapeshift should block raft application")
assert(decision.shouldApply == false, "blocked raft should not be armed")

namespace.precast.GetBobberUseDecision = function()
    return { shouldApply = false }
end
namespace.precast.GetOversizedBobberDecision = function()
    return { shouldApply = false }
end
namespace.precast.GetConsumableUseDecision = function(_, _, learningOnly)
    if learningOnly then
        return { shouldApply = false }
    end
    return {
        shouldApply = true,
        items = { { itemID = 274588, category = "other_consumable" } },
    }
end

assert(loadfile("fishing/fishing.precast.lua"))("DreamFish", namespace)

Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "",
    "shapeshifted swimming must wait instead of arming consumables")
assert(alerts[1] == "Raft-like items cannot be cast on a shape-shifted target",
    "automatic raft block should show the client-style error")

local consumableDecisionCalls = 0
namespace.precast.GetConsumableUseDecision = function()
    consumableDecisionCalls = consumableDecisionCalls + 1
    return { shouldApply = false }
end
namespace.precast.GetBobberUseDecision = function()
    return { shouldApply = true, toyID = 202207 }
end
frameAttributes.macrotext = nil
Fishing.state.pendingBuffUse = { uses = { { itemID = 238365, category = "other_consumable" } } }
swimming = false
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "/use item:202207\n/cast [nochanneling] Fishing",
    "normal fishing pre-cast should continue without automatic learning")
assert(consumableDecisionCalls == 0, "cast-time pre-cast actions must skip consumable selection")
assert(Fishing.state.pendingBuffUse == nil,
    "cast-time pre-cast actions should clear stale unexecuted pending consumables")

Fishing:ApplyRaft()
assert(usedToyID == nil, "manual raft apply must not activate while shapeshifted")

shapeshiftForm = 0
Fishing:ApplyRaft()
assert(usedToyID == 85500, "manual raft apply should use the supported toy API")

swimming = true
local freshRaftDecision = namespace.precast.GetRaftUseDecision(Fishing)
assert(freshRaftDecision.shouldApply == true, "ready raft should be applicable before recent-use protection")
namespace.precast.MarkRaftUse(85500)
local recentRaftDecision = namespace.precast.GetRaftUseDecision(Fishing)
assert(recentRaftDecision.shouldApply == false, "recently used raft must not be applied again immediately")
assert(recentRaftDecision.recentlyUsed == true, "raft decision should expose recent-use suppression")
now = now + 11
local settledRaftDecision = namespace.precast.GetRaftUseDecision(Fishing)
assert(settledRaftDecision.shouldApply == true, "raft recent-use protection should expire")

now = 30
frameAttributes.macrotext = nil
namespace.precast.MarkRaftUse(85500)
namespace.precast.GetBobberUseDecision = function()
    return { shouldApply = false }
end
Fishing.ConfigureFishingClickAction(Fishing, { skipConsumableDecision = true, showSwimmingGuidance = true })
assert(frameAttributes.macrotext == "", "recently used raft while still swimming should clear stale raft macro")
assert(frameAttributes.dreamfish_precast_action == true,
    "recently used raft while still swimming should remain a pre-cast wait action")
assert(guidanceShown == true,
    "player attempts while still swimming should show climb guidance from the no-op wait action")

now = 31
frameAttributes.macrotext = nil
namespace.precast.GetBobberUseDecision = function()
    return { shouldApply = true, toyID = 202207 }
end
Fishing.ConfigureFishingClickAction(Fishing, { skipConsumableDecision = true })
assert(frameAttributes.macrotext == "",
    "swimming after raft use must not arm bobbers or consumables until the player leaves swimming")

swimming = false
frameAttributes.macrotext = nil
namespace.precast.GetBobberUseDecision = function()
    return { shouldApply = false }
end
Fishing.state.pendingBuffUse = {
    executedAt = now,
    uses = {
        { itemID = 238365, category = "other_consumable" },
        { itemID = 262650, category = "lure" },
    },
}
Fishing.ConfigureFishingClickAction(Fishing, { skipConsumableDecision = true })
assert(frameAttributes.macrotext == "/use item:238365\n/use item:262650\n/use 28\n/cast [nochanneling] Fishing",
    "immutable consumable decision should re-arm pending consumables if no pending spell started")
assert(Fishing.state.pendingBuffUse.executedAt == nil,
    "re-armed pending consumables should wait for the next clicked macro before starting failure timers")

print("fishing_raft_test: ok")