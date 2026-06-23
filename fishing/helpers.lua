-- DreamFisher: Fishing Helpers and Bag Management

local addon = _G["DreamFisher"]

local function ContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    end
    if GetContainerNumSlots then
        return GetContainerNumSlots(bag)
    end
    return 0
end

local function ContainerItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bag, slot)
    end
    if GetContainerItemID then
        return GetContainerItemID(bag, slot)
    end
    return nil
end

local function ContainerItemCount(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.stackCount or info.quantity or 1
        end
    end
    if GetContainerItemInfo then
        local info = GetContainerItemInfo(bag, slot)
        if type(info) == "table" then
            return info.stackCount or info.quantity or 1
        end
        local _, itemCount = GetContainerItemInfo(bag, slot)
        if itemCount then
            return itemCount
        end
    end
    return 0
end

local function CountItemInBags(itemID)
    if not itemID then
        return 0
    end

    local total = 0
    local bagCount = NUM_BAG_SLOTS or 4
    for bag = 0, bagCount do
        local slots = ContainerNumSlots(bag)
        for slot = 1, slots do
            if ContainerItemID(bag, slot) == itemID then
                total = total + math.max(1, ContainerItemCount(bag, slot))
            end
        end
    end

    local reagentSlots = ContainerNumSlots(5)
    if reagentSlots and reagentSlots > 0 then
        for slot = 1, reagentSlots do
            if ContainerItemID(5, slot) == itemID then
                total = total + math.max(1, ContainerItemCount(5, slot))
            end
        end
    end

    return total
end

local function GetFreeBagSlots()
    local free = 0
    local bagCount = NUM_BAG_SLOTS or 4
    for bag = 0, bagCount do
        local slots = ContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                if not ContainerItemID(bag, slot) then
                    free = free + 1
                end
            end
        end
    end
    local reagentSlots = ContainerNumSlots(5)
    if reagentSlots and reagentSlots > 0 then
        for slot = 1, reagentSlots do
            if not ContainerItemID(5, slot) then
                free = free + 1
            end
        end
    end
    return free
end

local function CheckBuffItemStockWarnings()
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return
    end

    local seen = {}
    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 and not seen[itemID] then
            seen[itemID] = true
            local count = CountItemInBags(itemID)
            local previousCount = addon.state.buffItemLastKnownCount[itemID]
            addon.state.buffItemLastKnownCount[itemID] = count

            if previousCount and previousCount > 0 and count <= 0 then
                local itemName = (type(GetItemInfo) == "function" and GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
                addon.PrintMessage("Buff item depleted: " .. tostring(itemName) .. " (0 left).")
            end
        end
    end
end

local function CheckBagSpace()
    if not addon.db or not addon.db.bagAlerts then
        return
    end

    local threshold = addon.db.lowBagThreshold or addon.defaults.lowBagThreshold
    local free = GetFreeBagSlots()

    if free <= threshold then
        local now = GetTime()
        if now - addon.state.lastBagWarning >= 10 then
            addon.state.lastBagWarning = now
            addon.PrintMessage("Low bag space! " .. free .. " slot(s) remaining (threshold: " .. threshold .. ").")
        end
    end
end

-- Export to addon
addon.utils = addon.utils or {}
addon.utils.ContainerNumSlots = ContainerNumSlots
addon.utils.ContainerItemID = ContainerItemID
addon.utils.ContainerItemCount = ContainerItemCount
addon.utils.CountItemInBags = CountItemInBags
addon.utils.GetFreeBagSlots = GetFreeBagSlots
addon.utils.CheckBuffItemStockWarnings = CheckBuffItemStockWarnings
addon.utils.CheckBagSpace = CheckBagSpace

-- Test hooks
addon._test.GetFreeBagSlots = GetFreeBagSlots
addon._test.CheckBagSpace = CheckBagSpace
addon._test.ResetBagWarningState = function()
    addon.state.lastBagWarning = 0
end
