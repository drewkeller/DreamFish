local equippedItemID = nil
local isChecked = true
local itemAvailable = true
local mounted = false
local channeling = false
local traceMessages = {}

local UNDERLIGHT_ITEM_ID = 133755

local function resetState()
    equippedItemID = nil
    isChecked = true
    itemAvailable = true
    mounted = false
    channeling = false
    traceMessages = {}
end

local function assertEquals(actual, expected, message)
    assert(actual == expected, message .. "; expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local Fishing = {
    const = {
        underlightAnglerItemID = UNDERLIGHT_ITEM_ID,
    },
    db = { global = {}, profile = {}, char = {} },
}

function Fishing:RegisterOnModuleInitialize(callback)
    callback(self)
end

function Fishing:RegisterTraceSource()
end

function Fishing:Trace(_, msg)
    table.insert(traceMessages, msg)
end

function Fishing:CanStartCast()
    return not channeling
end

local namespace = {
    Addon = {},
    Fishing = Fishing,
    Utils = {
        IsItemAvailableForEquip = function() return itemAvailable end,
    },
    precast = {
        GetConfiguredPoleSelections = function()
            return {
                underlight = {
                    isChecked = isChecked,
                    isAvailable = itemAvailable,
                    itemID = UNDERLIGHT_ITEM_ID,
                },
            }
        end,
        GetEquippedProfessionItemID = function() return equippedItemID end,
    },
}

function IsMounted()
    return mounted
end

assert(loadfile("fishing/precast/underlightangler.lua"))("DreamFish", namespace)

resetState()
isChecked = false
assertEquals(namespace.precast.GetUnderlightAnglerEquipDecision().shouldEquip, false,
    "unchecked underlight must not be selected for equip")

resetState()
equippedItemID = UNDERLIGHT_ITEM_ID
local equippedDecision = namespace.precast.GetUnderlightAnglerEquipDecision()
assertEquals(equippedDecision.alreadyEquipped, true, "already-equipped underlight must be detected")
assertEquals(equippedDecision.shouldEquip, false, "already-equipped underlight must not be selected again")

resetState()
channeling = true
assertEquals(namespace.precast.GetUnderlightAnglerEquipDecision().shouldEquip, true,
    "underlight should be eligible when casting cannot begin")

resetState()
channeling = false
assertEquals(namespace.precast.GetUnderlightAnglerEquipDecision().shouldEquip, false,
    "underlight decision should not request a swap when casting can begin")

resetState()
itemAvailable = false
channeling = true
local missingDecision = namespace.precast.GetUnderlightAnglerEquipDecision()
assertEquals(missingDecision.canEquip, false, "an unavailable underlight cannot be equipped")
assertEquals(missingDecision.shouldEquip, false, "an unavailable underlight must not be selected")

resetState()
mounted = true
channeling = true
assertEquals(namespace.precast.GetUnderlightAnglerEquipDecision().shouldEquip, false,
    "mounted players must not be selected for underlight equip")

print("fishing_underlightangler_test: passed")
