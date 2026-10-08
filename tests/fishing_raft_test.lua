local shapeshiftForm = 1
local now = 10
local swimming = true
local alerts = {}
local prints = {}
local guidanceShown = false

function GetShapeshiftForm()
    return shapeshiftForm
end

function IsSwimmingOrSubmerged()
    return swimming
end

function GetTime()
    return now
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
        IsSwimmingOrSubmerged = IsSwimmingOrSubmerged,
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
local oversizedReady = false
namespace.precast.GetOversizedBobberDecision = function()
    return { shouldApply = oversizedReady, toyID = 202207 }
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

assert(loadfile("fishing/precast.lua"))("DreamFish", namespace)

Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "",
    "shapeshifted swimming must wait instead of arming consumables")

local consumableDecisionCalls = 0
local consumableItems
namespace.precast.GetConsumableUseDecision = function()
    consumableDecisionCalls = consumableDecisionCalls + 1
    return { shouldApply = consumableItems ~= nil, items = consumableItems }
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

shapeshiftForm = 0
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

local constantsNamespace = { Addon = Addon, moduleConstants = {} }
assert(loadfile("fishing/_constants.lua"))("DreamFish", constantsNamespace)
Fishing.const.knownBuffItems = constantsNamespace.moduleConstants.Fishing.knownBuffItems
Fishing.db.profile.useTrawlerTotem = true
Fishing.db.profile.useTuskarrSpear = true
Fishing.state.pendingBuffUse = nil
namespace.precast.GetRaftUseDecision = function(_)
    return { shouldApply = false, swimming = swimming }
end
consumableItems = { { itemID = 238365, category = "other_consumable" } }
local toyAuras = {}
local unownedToys = {}
local cooldownToys = {}
local mounted = false
local mainHandItemID
mainHandItemID = 88535
function GetInventoryItemID(_, slot)
    assert(slot == 16, "spear availability should check the main-hand slot")
    return mainHandItemID
end
function IsMounted()
    return mounted
end
namespace.GetAuraBySpellID = function(spellID)
    return toyAuras[spellID]
end
namespace.Utils.IsToyOwned = function(itemID)
    assert(itemID ~= 88535, "the spear must not be checked for toy ownership")
    return not unownedToys[itemID]
end
namespace.Utils.IsCooldownReady = function(itemID)
    return not cooldownToys[itemID]
end

Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "/use item:152556\n/use 16\n/use item:238365\n/cast [nochanneling] Fishing",
    "totem and equipped spear should be armed in order before consumables")
assert(Fishing.state.precastArmedItemIDs[1] == 152556 and Fishing.state.precastArmedItemIDs[2] == 88535,
    "buff toys should be included in armed-item tracking")

oversizedReady = true
local previousConsumableCalls = consumableDecisionCalls
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "/use item:202207\n/cast [nochanneling] Fishing",
    "oversized bobber should take priority over buff toys")
assert(consumableDecisionCalls == previousConsumableCalls,
    "oversized bobber should still skip consumables")
oversizedReady = false

toyAuras[128357] = { expirationTime = now + 36 }
toyAuras[125359] = { expirationTime = now + 35 }
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "/use 16\n/use item:238365\n/cast [nochanneling] Fishing",
    "only toys whose buffs cannot cover the next cast should refresh")
toyAuras[128357] = { expirationTime = 0 }
toyAuras[125359] = { expirationTime = now + 120 }
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "/use item:238365\n/cast [nochanneling] Fishing",
    "active permanent or sufficiently long buffs should not refresh")
toyAuras = {}

unownedToys[152556] = true
cooldownToys[88535] = true
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "/use item:238365\n/cast [nochanneling] Fishing",
    "unowned toys and toys on cooldown should not be armed")
unownedToys = {}
cooldownToys = {}
mainHandItemID = 12345
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "/use item:152556\n/use item:238365\n/cast [nochanneling] Fishing",
    "a spear not equipped in the main hand should not be used or automatically equipped")
mainHandItemID = nil
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "/use item:152556\n/use item:238365\n/cast [nochanneling] Fishing",
    "an empty main-hand slot should not arm the spear")
mainHandItemID = 88535
Fishing.db.profile.useTrawlerTotem = false
Fishing.db.profile.useTuskarrSpear = false
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "/use item:238365\n/cast [nochanneling] Fishing",
    "disabled buff toys should not be armed")
Fishing.db.profile.useTrawlerTotem = true
Fishing.db.profile.useTuskarrSpear = true

mounted = true
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "/use item:238365\n/cast [nochanneling] Fishing",
    "buff toys should not be armed while mounted")
mounted = false
swimming = true
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "", "swimming should continue to block buff toys")
swimming = false
Fishing.IsBuffLearningActive = function()
    return true
end
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.type == "spell" and frameAttributes.spell == "Fishing",
    "buff toys should not contaminate buff learning")
Fishing.IsBuffLearningActive = nil

Fishing.state.pendingBuffUse = { uses = { { itemID = 238365, category = "other_consumable" } } }
Fishing.ConfigureFishingClickAction(Fishing, { skipConsumableDecision = true })
assert(frameAttributes.macrotext == "/use item:152556\n/use 16\n/use item:238365\n/cast [nochanneling] Fishing",
    "buff toys should precede re-armed consumables too")

print("fishing_raft_test: ok")