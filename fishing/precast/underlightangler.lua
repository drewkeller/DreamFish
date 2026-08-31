local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

local globalDB, profileDB, charDB
Fishing:RegisterInitializer(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

Fishing:RegisterTraceSource("underlight")

local function Trace(msg)
    Fishing:Trace("underlight", msg)
end

local function GetUnderlightAnglerEquipDecision()
    local selections = ns.precast.GetConfiguredPoleSelections()
    local isSelected = selections.underlight.isChecked
    local itemID = ns.Fishing.const.underlightAnglerItemID or nil
    local hasItem = ns.Utils.IsItemAvailableForEquip(itemID)
    local mounted = IsMounted()
    local equippedItemID = ns.precast.GetEquippedProfessionItemID()
    local alreadyEquipped = itemID
        and equippedItemID
        and (itemID == equippedItemID)
        or false
    local shouldEquip = selections.underlight.isChecked
        and hasItem
        and not mounted
        and not alreadyEquipped
        and not Fishing:CanStartCast()

    if shouldEquip then
        Trace("Underlight Angler can be equipped")
    elseif (not isSelected) then
        Trace("Underlight Angler is not selected for use")
    elseif not hasItem then
        Trace("Underlight Angler is not owned")
    elseif mounted then
        Trace("Player is mounted")
    elseif alreadyEquipped then
        Trace("Underlight Angler is already equipped")
    else
        Trace("Underlight Angler will not be equipped for unknown reason")
    end

    return {
        itemID = itemID,
        hasItem = hasItem,
        shouldEquip = shouldEquip,
        mounted = mounted,
        alreadyEquipped = alreadyEquipped,
    }
end

function Fishing:CheckAndEquipUnderlightAngler(reason)
    local selection = ns.precast.GetConfiguredPoleSelections().underlight
    local itemID = tonumber(ns.Fishing.const.underlightAnglerItemID)
    if not selection.isChecked or not itemID or itemID <= 0 or InCombatLockdown() or IsMounted() then
        return false
    end

    if ns.precast.GetEquippedProfessionItemID() == itemID then
        return true
    end

    local bag, slot = ns.Utils.FindItemInBags(itemID)
    if bag and slot and C_Container and C_Container.PickupContainerItem and EquipCursorItem then
        C_Container.PickupContainerItem(bag, slot)
        EquipCursorItem(28)
        if ClearCursor then
            ClearCursor()
        end
        Trace("Equipping Underlight Angler after fishing cancellation: " .. tostring(reason))
        return true
    end

    if C_Item.EquipItemByName then
        C_Item.EquipItemByName("item:" .. itemID, 28)
        Trace("Equipping Underlight Angler after fishing cancellation: " .. tostring(reason))
        return true
    end

    return false
end

function Fishing:OnFishingCastEnded(event, oldState, newState)
    ns.Utils.Print("Fishing cast ended message received; checking if Underlight Angler should be equipped.")
    if self:CheckAndEquipUnderlightAngler("cast ended event: " .. tostring(newState)) then
        ns.Utils.Print("Equipping Underlight Angler")
        Trace("Equipped Underlight Angler after fishing cast ended")
    end
end

ns.precast.GetUnderlightAnglerEquipDecision = GetUnderlightAnglerEquipDecision
