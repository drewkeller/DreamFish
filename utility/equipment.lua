local addonName, ns = ...
local Addon = ns.Addon

Addon:RegisterTraceSource("equipment")

local function Trace(msg)
    Addon:TraceCore("equipment", msg)
end

function ns.Utils.TryEquipItemToProfessionSlot(itemID, equipSlot)
    if not itemID or tonumber(itemID) <= 0 then
        return false
    end

    if not equipSlot or tonumber(equipSlot) <= 0 then
        return false
    end

    itemID = tonumber(itemID)
    local itemRef = "item:" .. tostring(itemID)
    local equipRequestDispatched = false
    local lastDispatchedMethod = nil

    local function IsNowEquipped()
        return GetInventoryItemID("player", equipSlot) == itemID
    end

    if IsNowEquipped() then
        return true
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
                local okFallback = pcall(C_Item.EquipItemByName, itemRef)
                equipRequestDispatched = equipRequestDispatched or okFallback
                if okFallback then
                    lastDispatchedMethod = "cursor-fallback:EquipItemByName:slot" .. tostring(targetSlot)
                    if IsNowEquipped() then
                        Trace("Equip succeeded via " .. tostring(lastDispatchedMethod)
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
            Trace("Equip succeeded via " .. tostring(lastDispatchedMethod)
                .. " " .. ns.Utils.GetDebugItemLabel(itemID))
            return true
        end

        return false
    end

    if TryEquipFromBagCursor(equipSlot) then
        return true
    end

    if equipRequestDispatched then
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.1, function()
                if IsNowEquipped() then
                    Trace("Equip completed on delayed verify via "
                        .. tostring(lastDispatchedMethod or "unknown") .. ": " .. ns.Utils.GetDebugItemLabel(itemID))
                    return
                end

                C_Timer.After(0.35, function()
                    if IsNowEquipped() then
                        Trace("Equip completed on extended verify via "
                            .. tostring(lastDispatchedMethod or "unknown") .. ": " .. ns.Utils.GetDebugItemLabel(itemID))
                    else
                        Trace("Failed to equip item after delayed verify " .. ns.Utils.GetDebugItemLabel(itemID))
                    end
                end)
            end)
            Trace("Equip request dispatched via " .. tostring(lastDispatchedMethod or "unknown")
                .. "; awaiting delayed verification: " .. ns.Utils.GetDebugItemLabel(itemID))
        else
            Trace("Equip request dispatched; timer unavailable for delayed verification: " .. ns.Utils.GetDebugItemLabel(itemID))
        end
        return true
    end

    Trace("Failed to equip item " .. ns.Utils.GetDebugItemLabel(itemID))
    return false
end

function ns.Utils.TryUnequipProfessionSlot(equipmentSlot)
    if InCombatLockdown() then
        return
    end

    -- Look for an empty bag slot to put the pole into
    local bag, bagSlot = ns.Utils.GetFreeBagSlot()
    if not bag or not bagSlot then
        Addon:Alert(ns.SystemColor.INFO, "Your bags are full. Cannot unequip fishing pole.")
        return false
    end
    ClearCursor()
    PickupInventoryItem(equipmentSlot)
    C_Container.PickupContainerItem(bag, bagSlot)
    return true
end
