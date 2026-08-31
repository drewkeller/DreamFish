local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

local globalDB, profileDB, charDB
Fishing:RegisterInitializer(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

Fishing:RegisterTraceSource("pole")

local function Trace(msg)
    Fishing:Trace("pole", msg)
end

local function GetEquippedProfessionItemID()
    if type(GetInventoryItemID) ~= "function" then
        return nil
    end
    local ok, rawItemID = pcall(GetInventoryItemID, "player", 28)
    if not ok then
        return nil
    end
    local itemID = tonumber(rawItemID)
    if not itemID or itemID <= 0 then
        return nil
    end
    return itemID
end

local function IsUnderlightAnglerItemID(itemID)
    local underlightID = tonumber(ns.Fishing.const.underlightAnglerItemID)
    return tonumber(itemID) == underlightID
end

local function NormalizePoleSelection(value, validateItemID)
    local itemID = tonumber(type(value) == "table" and value.itemID or nil)
    local isChecked = type(value) == "table" and value.isChecked ~= false or false
    local isAvailable = false

    if not itemID or itemID <= 0 then
        itemID = nil
    end
    if itemID and validateItemID and (not validateItemID(itemID)) then
        itemID = nil
    end
    if itemID and isChecked == true then
        isAvailable = ns.Utils.IsItemAvailableForEquip(itemID)
    end
    if not itemID then
        isChecked = false
    end

    return {
        itemID = itemID,
        isChecked = isChecked and true or false,
        isAvailable = isAvailable,
    }
end

local function GetConfiguredPoleSelections()
    return {
        primary = NormalizePoleSelection(charDB.primaryPole),
        underlight = NormalizePoleSelection(charDB.underlightAngler, IsUnderlightAnglerItemID),
    }
end

local function GetWaterContextDiagnostics()
    local diagnostics = {
        isSwimming = false,
        isSubmerged = false,
        secureOption = nil,
        source = nil,
        result = false,
    }

    if type(IsSwimming) == "function" and IsSwimming() then
        diagnostics.isSwimming = true
        diagnostics.source = "IsSwimming"
        diagnostics.result = true
        return diagnostics
    end

    if type(IsSubmerged) == "function" and IsSubmerged() then
        diagnostics.isSubmerged = true
        diagnostics.source = "IsSubmerged"
        diagnostics.result = true
        return diagnostics
    end

    return diagnostics
end

local function IsPlayerInWaterContext()
    return GetWaterContextDiagnostics().result
end

local function GetSelectedFishingPoleDecision()
    local selections = GetConfiguredPoleSelections()
    local poleItemID = selections.primary.itemID
    local hasItem = ns.Utils.IsItemAvailableForEquip(poleItemID)
    local mounted = (type(IsMounted) == "function" and IsMounted()) or false
    local equippedItemID = GetEquippedProfessionItemID()
    local alreadyEquipped = poleItemID and equippedItemID and (poleItemID == equippedItemID) or false
    local shouldApply = hasItem
        and selections.primary.isChecked
        and Fishing:CanStartCast()
        and (not mounted)
        and (not alreadyEquipped)

    if shouldApply then
        Trace("Primary fishing poleItemID=" .. tostring(poleItemID) .. " is ready to be applied.")
    elseif not hasItem then
        Trace("Primary fishing poleItemID=" .. tostring(poleItemID) .. " is not available in bags or equipped.")
    elseif not selections.primary.isChecked then
        Trace("Primary fishing poleItemID=" .. tostring(poleItemID) .. " is not selected for application.")
    elseif mounted then
        Trace("Player is mounted; primary pole will not be applied.")
    elseif alreadyEquipped then
        Trace("Primary fishing poleItemID=" .. tostring(poleItemID) .. " is already equipped; no action needed.")
    end

    return {
        itemID = poleItemID,
        hasItem = hasItem,
        mounted = mounted,
        alreadyEquipped = alreadyEquipped,
        shouldApply = shouldApply,
    }
end

local function TryEquipItemToProfessionSlot(itemID)
    if not itemID or tonumber(itemID) <= 0 then
        return false
    end

    itemID = tonumber(itemID)
    local itemRef = "item:" .. tostring(itemID)
    local equipRequestDispatched = false
    local lastDispatchedMethod = nil

    local function IsNowEquipped()
        return GetEquippedProfessionItemID() == itemID
    end

    local function TryEquipFromBagCursor(targetSlot)
        local bag, slot = ns.Utils.FindItemInBags(itemID)
        if bag == nil or slot == nil then
            return false
        end

        local pickupFn = C_Container and C_Container.PickupContainerItem or nil

        local equipCursorFn = type(C_Item) == "table" and C_Item.EquipCursorItem or nil
        equipCursorFn = type(equipCursorFn) == "function" and equipCursorFn or EquipCursorItem
        if type(pickupFn) ~= "function" or type(equipCursorFn) ~= "function" then
            if type(C_Item.EquipItemByName) == "function" then
                local okFallback = pcall(C_Item.EquipItemByName, itemRef, targetSlot)
                equipRequestDispatched = equipRequestDispatched or okFallback
                if okFallback then
                    lastDispatchedMethod = "cursor-fallback:EquipItemByName:slot" .. tostring(targetSlot)
                    if IsNowEquipped() then
                        Trace("Pole equip succeeded via " .. tostring(lastDispatchedMethod)
                            .. " " .. ns.Utils.GetDebugItemLabel(itemID))
                        return true
                    end
                end
            end
            return false
        end

        local okPickup = pcall(pickupFn, bag, slot)
        if not okPickup then
            if type(ClearCursor) == "function" then
                pcall(ClearCursor)
            end
            return false
        end

        local okEquip = pcall(equipCursorFn, targetSlot)
        if not okEquip then
            if type(ClearCursor) == "function" then
                pcall(ClearCursor)
            end
            return false
        end
        equipRequestDispatched = true
        lastDispatchedMethod = "bag-cursor:slot" .. tostring(targetSlot)

        if type(ClearCursor) == "function" then
            pcall(ClearCursor)
        end

        if IsNowEquipped() then
            Trace("Pole equip succeeded via " .. tostring(lastDispatchedMethod)
                .. " " .. ns.Utils.GetDebugItemLabel(itemID))
            return true
        end

        return false
    end

    if TryEquipFromBagCursor(28) then
        return true
    end

    -- if TryEquipFromBagCursor(16) then
    --     return true
    -- end

    if equipRequestDispatched then
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.1, function()
                if IsNowEquipped() then
                    Trace("Pole equip completed on delayed verify via "
                        .. tostring(lastDispatchedMethod or "unknown") .. ": " .. ns.Utils.GetDebugItemLabel(itemID))
                    return
                end

                C_Timer.After(0.35, function()
                    if IsNowEquipped() then
                        Trace("Pole equip completed on extended verify via "
                            .. tostring(lastDispatchedMethod or "unknown") .. ": " .. ns.Utils.GetDebugItemLabel(itemID))
                    else
                        Trace("Failed to equip configured pole after delayed verify " .. ns.Utils.GetDebugItemLabel(itemID))
                    end
                end)
            end)
            Trace("Pole equip request dispatched via " .. tostring(lastDispatchedMethod or "unknown")
                .. "; awaiting delayed verification: " .. ns.Utils.GetDebugItemLabel(itemID))
        else
            Trace("Pole equip request dispatched; timer unavailable for delayed verification: " .. ns.Utils.GetDebugItemLabel(itemID))
        end
        return true
    end

    Trace("Failed to equip configured pole " .. ns.Utils.GetDebugItemLabel(itemID))
    return false
end


local function ApplySelectedFishingPole()
    local selections = GetConfiguredPoleSelections()
    local primary = selections.primary
    local underlight = selections.underlight
    local itemToEquip = nil

    local canEquipPrimary = primary.isChecked and primary.isAvailable
    local canEquipUnderlight = underlight.isChecked and underlight.isAvailable

    if not canEquipPrimary and not canEquipUnderlight then
        Trace("Pole to equip is: none")
        itemToEquip = nil
    elseif canEquipPrimary and (Fishing:IsInFishingSession() or not canEquipUnderlight) then
        Trace("Pole to equip is: " .. ns.Utils.GetDebugItemLabel(primary.itemID))
        itemToEquip = primary.itemID
    elseif canEquipUnderlight then
        Trace("Pole to equip is: " .. ns.Utils.GetDebugItemLabel(underlight.itemID))
        itemToEquip = underlight.itemID
    end

    if(TryEquipItemToProfessionSlot(itemToEquip)) then
        Trace("Successfully equipped selected pole: " .. ns.Utils.GetDebugItemLabel(itemToEquip))
    else
        Trace("Failed to equip selected pole: " .. ns.Utils.GetDebugItemLabel(itemToEquip))
    end
end

ns.precast.GetSelectedFishingPoleDecision = GetSelectedFishingPoleDecision
ns.precast.GetEquippedProfessionItemID = GetEquippedProfessionItemID
ns.precast.GetConfiguredPoleSelections = GetConfiguredPoleSelections
ns.precast.TryEquipItemToProfessionSlot = TryEquipItemToProfessionSlot
ns.precast.ApplySelectedFishingPole = ApplySelectedFishingPole
