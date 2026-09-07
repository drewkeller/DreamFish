-- Tests for fishing/precast/underlightangler.lua, focused on the channeling gate that prevents
-- the delayed post-login safety pass from equipping the Underlight Angler mid-cast and
-- cancelling the fishing channel.

local equippedItemID = nil
local isChecked = true
local itemAvailable = true
local mounted = false
local inCombat = false
local channeling = false
local equipCalls = {}
local traceMessages = {}

local UNDERLIGHT_ITEM_ID = 133755

local function resetState()
    equippedItemID = nil
    isChecked = true
    itemAvailable = true
    mounted = false
    inCombat = false
    channeling = false
    equipCalls = {}
    traceMessages = {}
end

local function assertEquals(actual, expected, message)
    assert(actual == expected, message .. "; expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Minimal Fishing module that the underlight file attaches its methods to.
local Fishing = {
    const = {
        underlightAnglerItemID = UNDERLIGHT_ITEM_ID,
    },
}

function Fishing:RegisterOnModuleInitialize()
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
        FindItemInBags = function() return nil, nil end,
        GetDebugItemLabel = function(itemID) return "item:" .. tostring(itemID) end,
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

-- Globals the file references.
function IsMounted()
    return mounted
end

function InCombatLockdown()
    return inCombat
end

function UnitChannelInfo(unit)
    assert(unit == "player", "channel check must target the player")
    return channeling and "Fishing" or nil
end

C_Item = {
    EquipItemByName = function(ref)
        table.insert(equipCalls, ref)
        return true
    end,
}

assert(loadfile("fishing/precast/underlightangler.lua"))("DreamFish", namespace)

-- Not selected: never equips.
resetState()
isChecked = false
assertEquals(Fishing:CheckAndEquipUnderlightAngler("test"), false, "unchecked underlight must not equip")
assertEquals(#equipCalls, 0, "unchecked underlight must not dispatch an equip")

-- Already equipped: treated as satisfied, no equip.
resetState()
equippedItemID = UNDERLIGHT_ITEM_ID
assertEquals(Fishing:CheckAndEquipUnderlightAngler("test"), true, "already-equipped underlight must report success")
assertEquals(#equipCalls, 0, "already-equipped underlight must not dispatch an equip")

-- The channeling gate: mid-cast must skip the equip so the channel is not interrupted.
resetState()
channeling = true
assertEquals(Fishing:CheckAndEquipUnderlightAngler("addon loaded (delayed packet safety pass)"), false,
    "equip must be skipped while a channel is active")
assertEquals(#equipCalls, 0, "equip must not be dispatched while a channel is active")

-- Once the channel has finished, the same call equips normally.
resetState()
channeling = false
assertEquals(Fishing:CheckAndEquipUnderlightAngler("normally after linger"), true,
    "equip must proceed once the channel has finished")
assertEquals(#equipCalls, 1, "equip must be dispatched once the channel has finished")
assertEquals(equipCalls[1], "item:" .. tostring(UNDERLIGHT_ITEM_ID), "equip must target the underlight item")

-- Combat still blocks the equip regardless of channel state.
resetState()
inCombat = true
assertEquals(Fishing:CheckAndEquipUnderlightAngler("test"), false, "equip must be blocked in combat")
assertEquals(#equipCalls, 0, "equip must not be dispatched in combat")

-- Mounted still blocks the equip regardless of channel state.
resetState()
mounted = true
assertEquals(Fishing:CheckAndEquipUnderlightAngler("test"), false, "equip must be blocked while mounted")
assertEquals(#equipCalls, 0, "equip must not be dispatched while mounted")

print("fishing_underlightangler_test: passed")
