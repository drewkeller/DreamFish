local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

function DreamFish:ContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    end
    return 0
end

function DreamFish:FindItemInBags(itemID)
    if not itemID then
        return nil, nil
    end

    local bagCount = NUM_BAG_SLOTS or 4
    for bag = 0, bagCount do
        local slots = DreamFish:ContainerNumSlots(bag)
        for slot = 1, slots do
            if C_Container.GetContainerItemID(bag, slot) == itemID then
                return bag, slot
            end
        end
    end

    local reagentSlots = DreamFish:ContainerNumSlots(5)
    if reagentSlots and reagentSlots > 0 then
        for slot = 1, reagentSlots do
            if C_Container.GetContainerItemID(5, slot) == itemID then
                return 5, slot
            end
        end
    end

    return nil, nil
end

function DreamFish:FindItemsInBagsWhere(predicate)
    if type(predicate) ~= "function" then
        return {}
    end

    local foundItems = {}
    local bagCount = NUM_BAG_SLOTS or 4
    for bag = 0, bagCount do
        local slots = DreamFish:ContainerNumSlots(bag)
        for slot = 1, slots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and predicate(itemID, bag, slot) then
                table.insert(foundItems, {bag = bag, slot = slot, itemID = itemID})
            end
        end
    end

    local reagentSlots = DreamFish:ContainerNumSlots(5)
    if reagentSlots and reagentSlots > 0 then
        for slot = 1, reagentSlots do
            local itemID = C_Container.GetContainerItemID(5, slot)
            if itemID and predicate(itemID, 5, slot) then
                table.insert(foundItems, {bag = 5, slot = slot, itemID = itemID})
            end
        end
    end

    return foundItems
end

function DreamFish:CountItemInBags(itemID)
    local count = 0
    local bagCount = NUM_BAG_SLOTS or 4
    for bag = 0, bagCount do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            if C_Container.GetContainerItemID(bag, slot) == itemID then
                local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
                count = count + (itemInfo and itemInfo.stackCount or 0)
            end
        end
    end
    return count
end

function DreamFish:IsItemEquippedInAnyTrackedSlot(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 or type(GetInventoryItemID) ~= "function" then
        return false
    end

    local maxSlot = (type(INVSLOT_LAST_EQUIPPED) == "number" and INVSLOT_LAST_EQUIPPED) or 19
    if maxSlot < 40 then
        maxSlot = 40
    end
    for slot = 1, maxSlot do
        local ok, rawItemID = pcall(GetInventoryItemID, "player", slot)
        if ok and tonumber(rawItemID) == numeric then
            return true
        end
    end

    return false
end

function DreamFish:IsItemAvailableForEquip(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return false
    end

    if DreamFish:IsItemEquippedInAnyTrackedSlot(numeric) then
        return true
    end

    local bag, slot = DreamFish:FindItemInBags(numeric)
    if bag and slot then
        return true
    end

    return false
end
