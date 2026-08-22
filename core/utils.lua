local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

function DreamFish:Alert(msg, ...)
    DreamFish:PlayWarningCue()
    RaidWarningUtil.AddMessage(msg, ChatTypeInfo["SYSTEM"])
end

function DreamFish:Debug(msg, ...)
    if self.db.profile.debugMode then
        self:Print("|cFF9ACDFF[Debug]|r ", msg, ...)
    end
end

function DreamFish:FormatDuration(seconds)
    local n = tonumber(seconds)
    if not n or n < 0 then
        return "unknown"
    end
    local rounded = math.floor(n + 0.5)
    local minutes = math.floor(rounded / 60)
    local secs = rounded % 60
    if minutes > 0 then
        return tostring(minutes) .. "m " .. tostring(secs) .. "s"
    end
    return tostring(secs) .. "s"
end

function DreamFish:GetDebugItemLabel(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return "unknown"
    end
    local name = C_Item.GetItemInfo(numeric)
    if name and name ~= "" then
        return tostring(name) .. " (" .. tostring(numeric) .. ")"
    end
    return "item:" .. tostring(numeric)
end

function DreamFish:GetDebugCooldownText(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return "cooldown=unknown"
    end

    local start, duration, enabled = C_Item.GetItemCooldown(numeric)
    if not enabled or enabled == 0 then
        return "cooldown=disabled"
    end
    if not start or not duration or duration <= 0 then
        return "cooldown=ready"
    end

    local remaining = math.max(0, (start + duration) - GetTime())
    return "cooldownRemaining=" .. string.format("%.1fs", remaining)
end

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

local function IsItemEquippedInAnyTrackedSlot(itemID)
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

    if IsItemEquippedInAnyTrackedSlot(numeric) then
        return true
    end

    local bag, slot = DreamFish:FindItemInBags(numeric)
    if bag and slot then
        return true
    end

    return false
end

