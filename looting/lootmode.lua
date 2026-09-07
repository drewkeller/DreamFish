local addonName, ns = ...
local Addon = ns.Addon
local LootTracker = ns.LootTracker

local profileDB
local state = {
    savedAutoLootDefault = nil,
    isFishing = false,
    originalAutoLootSetting = nil,
    lootWindowOpen = false,
}

local LootMode = {}
for _, mode in ipairs(ns.LootTracker.const.LootModes) do
    LootMode[mode.id:upper()] = mode.id
end

LootTracker:RegisterTraceSource("iteminfo")
LootTracker:RegisterTraceSource("lootmode")

local function Trace(message)
    LootTracker:Trace("lootmode", message)
end

local function RestoreNativeAutoLootSetting()
    if state.originalAutoLootSetting ~= nil then
        SetCVar("autoLootDefault", state.originalAutoLootSetting and "1" or "0")
    end
end

LootTracker:RegisterOnModuleInitialize(function(self)
    profileDB = self.db.profile
    state.originalAutoLootSetting = GetCVar("autoLootDefault") == "1"
end)

LootTracker:RegisterOnModuleEnable(function(self)
    profileDB = self.db.profile
    Addon:RegisterMessage("FISHING_SESSION_STARTED", function(...) self:OnFishingSessionStarted(...) end)
    Addon:RegisterMessage("FISHING_SESSION_ENDED",   function(...) self:OnFishingSessionEnded(...) end)
end)

LootTracker:RegisterOnModuleDisable(function(self)
    Addon:UnregisterMessage("FISHING_SESSION_STARTED")
    Addon:UnregisterMessage("FISHING_SESSION_ENDED")
    RestoreNativeAutoLootSetting()
end)

local function GetLootSituation()
    if state.isFishing then
        return profileDB.lootModeWhenFishing
    else
        return profileDB.lootModeWhenOther
    end
end

local function HasNativeAutoLootOverride(situation)
    return situation.lootMode ~= LootMode.NONE
end

local function UpdateNativeAutoLootSetting(previousSituation, currentSituation)
    if HasNativeAutoLootOverride(previousSituation) and not HasNativeAutoLootOverride(currentSituation) then
        RestoreNativeAutoLootSetting()
    elseif currentSituation.lootMode == LootMode.MANUAL or currentSituation.lootMode == LootMode.MANAGED then
        SetCVar("autoLootDefault", "0")
    elseif currentSituation.lootMode == LootMode.NATIVE then
        SetCVar("autoLootDefault", "1")
    end
end

function LootTracker:OnFishingSessionStarted()
    local previousSituation = GetLootSituation()
    state.isFishing = true
    local currentSituation = GetLootSituation()
    UpdateNativeAutoLootSetting(previousSituation, currentSituation)
end

function LootTracker:OnFishingSessionEnded()
    local previousSituation = GetLootSituation()
    state.isFishing = false
    local currentSituation = GetLootSituation()
    UpdateNativeAutoLootSetting(previousSituation, currentSituation)
end


local function CreateLootItemInfo(slot, icon, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin)
    -- Compatibility: some clients/mocks return quality as the 4th result for item slots.
    if quality == nil and type(currencyID) == "number" and currencyID >= 0 and currencyID <= 7 then
        quality = currencyID
        currencyID = nil
    end
    LootTracker:Trace("iteminfo", "Got loot info for slot " .. tostring(slot) .. ": name=" .. tostring(name)
        .. " quantity=" .. tostring(quantity)
        .. " currencyID=" .. tostring(currencyID)
        .. " quality=" .. tostring(quality)
        .. " locked=" .. tostring(locked)
        .. " isQuestItem=" .. tostring(isQuestItem)
        .. " questID=" .. tostring(questID)
        .. " isActive=" .. tostring(isActive)
        .. " isCoin=" .. tostring(isCoin))
    local info = {
        slot = slot,
        icon = icon,
        name = name,
        quantity = quantity,
        currencyID = currencyID,
        -- Modern clients may not return quality directly from GetLootSlotInfo.
        quality = tonumber(quality),
        locked = locked,
        isQuestItem = isQuestItem,
        questID = questID,
        isActive = isActive,
        isCoin = isCoin,
        itemID = nil,
        itemLink = nil,
    }

    return info
end

local function GetLootItemInfo(slot)
    if type(GetLootSlotInfo) ~= "function" then
        return nil
    end

    local icon, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin = GetLootSlotInfo(slot)
    if icon == nil then
        return nil
    end

    local info = CreateLootItemInfo(slot, icon, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin)

    -- Parse the itemID from the itemLink's tooltip
    -- currency does not have itemID or link
    if info and not info.currencyID and not info.isCoin then
        --local slotType = (type(GetLootSlotType) == "function") and tonumber(GetLootSlotType(slot)) or nil
        if type(GetLootSlotLink) == "function" then
            info.itemLink = GetLootSlotLink(slot)
            if info.itemLink then
                info.itemID = tonumber(string.match(info.itemLink, "item:(%d+)"))
            end
        end
    end

    return info
end

local function ShouldAutoLootItem(lootItemInfo)
    local situation = GetLootSituation()
    -- Junk items have quality 0 or less; we want to auto-loot them if the user has disabled junk skipping,
    -- but skip them if the user has enabled junk skipping.
    local isJunk = lootItemInfo.quality ~= nil and lootItemInfo.quality <= 0
    if isJunk then
        Trace("Item in slot " .. tostring(lootItemInfo.slot) .. " is junk")
    end
    if isJunk and situation.ignoreJunk then
        return false
    end
    if lootItemInfo.locked then
        Trace("Item in slot " .. tostring(lootItemInfo.slot) .. " is locked")
        return false
    end
    return true
end

local function HandleLootWindow(situation)
    assert(situation.lootMode == LootMode.MANAGED, "Loot handling should only be invoked in managed loot mode")

    if type(GetNumLootItems) ~= "function" or type(LootSlot) ~= "function" then
        Addon:Warning("lootmode", "Required loot functions are not available; skipping loot handling")
        return false
    end

    local lootCount = tonumber(GetNumLootItems()) or 0
    local shouldCloseLootWindow = lootCount > 0

    Trace("Handling loot window with " .. tostring(lootCount) .. " items")
    local itemsLooted = 0
    -- LootSlot is asynchronous: it only sends the loot request to the server, and the window
    -- keeps reporting its pre-loot state (same slot count, same slot contents) until the
    -- server confirms a frame or more later. Iterate the snapshot of slots exactly once so
    -- every slot is looted exactly once and the loop can never spin on a not-yet-cleared slot.
    for slot = 1, lootCount do
        local lootItemInfo = GetLootItemInfo(slot)
        if not lootItemInfo then
            Trace("Failed to get info for loot slot " .. tostring(slot) .. "; skipping")
            -- in the future, we may want to go ahead and loot unknown items due to player having selected "nativeAutoLoot while fishing"
            shouldCloseLootWindow = false
            break
        end
        -- can't loot it if it is loot-locked, but we should keep the loot window open for the player
        if lootItemInfo.locked then
            Trace("Item in slot " .. tostring(slot) .. " is locked")
            shouldCloseLootWindow = false
            break
        end
        if ShouldAutoLootItem(lootItemInfo) then
            Trace("Looting " .. (lootItemInfo.itemLink or lootItemInfo.name) .. " in loot slot " .. tostring(slot) .. " with quality " .. tostring(lootItemInfo.quality))
            LootSlot(slot)
            itemsLooted = itemsLooted + 1
        elseif situation.stayOpenForJunk then
            Trace("Not looting " .. (lootItemInfo.itemLink or lootItemInfo.name) .. " in loot slot " .. tostring(slot) .. " with quality " .. tostring(lootItemInfo.quality))
            shouldCloseLootWindow = false
        else
            Trace("Ignoring " .. (lootItemInfo.itemLink or lootItemInfo.name) .. " in loot slot " .. tostring(slot) .. " with quality " .. tostring(lootItemInfo.quality))
        end
    end

    Trace("Looted " .. tostring(itemsLooted) .. " of " .. tostring(lootCount) .. " items")

    if shouldCloseLootWindow and type(CloseLoot) == "function" then
        CloseLoot()
    end

    return true
end

local lootTracker = CreateFrame("Frame")
lootTracker:RegisterEvent("LOOT_READY")
lootTracker:RegisterEvent("LOOT_CLOSED")
lootTracker:SetScript("OnEvent", function(_, event, ...)

    -- The client fires LOOT_READY and LOOT_CLOSED multiple times for a single loot window,
    -- so track the window state and ignore the duplicate events.
    if event == "LOOT_READY" then
        if state.lootWindowOpen then
            Trace("LOOT_READY: ignoring duplicate event; the loot window is already open")
            return
        end
        state.lootWindowOpen = true
    elseif event == "LOOT_CLOSED" then
        if not state.lootWindowOpen then
            Trace("LOOT_CLOSED: ignoring duplicate event; the loot window is not open")
            return
        end
        state.lootWindowOpen = false
    end

    local situation = GetLootSituation()

    if situation.lootMode ~= LootMode.MANAGED then
        Trace(tostring(event) .. ": Loot mode is '" .. tostring(situation.lootMode):upper() .. "' for this situation; skipping")
        return
    end

    if event == "LOOT_READY" then
        -- Handle immediately if zero
        if profileDB.lootDelay == 0 then
            HandleLootWindow(situation)
        else
            C_Timer.After(profileDB.lootDelay / 1000, function()
                HandleLootWindow(situation)
            end)
        end

    elseif event == "LOOT_CLOSED" then
        Trace("Loot window closed")
    end
end)
