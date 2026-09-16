local shapeshiftForm = 1
local usedToyID
local alerts = {}
local prints = {}

function GetShapeshiftForm()
    return shapeshiftForm
end

function IsSwimming()
    return true
end

function GetTime()
    return 10
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
assert(frameAttributes.macrotext == "/use item:274588\n/cast [nochanneling] Fishing",
    "shapeshifted raft must not prevent other buffs from being armed")
assert(alerts[1] == "Raft-like items cannot be cast on a shape-shifted target",
    "automatic raft block should show the client-style error")

local consumableDecisionCalls = 0
namespace.precast.GetConsumableUseDecision = function(_, _, learningOnly)
    consumableDecisionCalls = consumableDecisionCalls + 1
    if learningOnly then
        return {
            shouldApply = true,
            items = { { itemID = 274588, category = "other_consumable" } },
        }
    end
    error("a learning consumable must prevent the normal pre-cast pass")
end
namespace.precast.GetBobberUseDecision = function()
    return { shouldApply = true, toyID = 202207 }
end
frameAttributes.macrotext = nil
Fishing.ConfigureFishingClickAction(Fishing)
assert(frameAttributes.macrotext == "/use item:274588\n/cast [nochanneling] Fishing",
    "a learning consumable must be the only item use in its macro")
assert(consumableDecisionCalls == 1, "only the learning pre-cast pass should run")
assert(prints[1] == "Learning buff item: 274588",
    "a learning consumable should announce that its data is being learned")
Fishing.ConfigureFishingClickAction(Fishing)
assert(#prints == 1, "rebuilding the same pending learning action must not repeat its announcement")

Fishing:ApplyRaft()
assert(usedToyID == nil, "manual raft apply must not activate while shapeshifted")

shapeshiftForm = 0
Fishing:ApplyRaft()
assert(usedToyID == 85500, "manual raft apply should use the supported toy API")

print("fishing_raft_test: ok")