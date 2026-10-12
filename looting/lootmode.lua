local addonName, ns = ...
local Addon = ns.Addon
local LootTracker = ns.LootTracker
local MessageSink = ns.MessageSink:new(LootTracker)

local charDB
local profileDB
local state = {
    savedAutoLootDefault = nil,
    cvarInterference = false,
    settingCVar = false,
    isFishing = false,
    lootWindowOpen = false,
    lootSlotItems = {},
    fishingCastCounted = false,
}

local LootMode = {}
for _, mode in ipairs(ns.LootTracker.const.LootModes) do
    LootMode[mode.id:upper()] = mode.id
end

local GetLootSituation
local UpdateNativeAutoLootSetting

LootTracker:RegisterTraceSource("iteminfo")
LootTracker:RegisterTraceSource("lootmode")

local function Trace(message)
    LootTracker:Trace("lootmode", message)
end

local function AutoLootToString(value)
    if type(value) == "string" then
        return value == "1" and "ON" or "OFF"
    end
    if type(value) == "boolean" then
        return value == true and "ON" or "OFF"
    end
    return "UNKNOWN (" .. tostring(value) .. ")"
end

local function SituationToString(situation)
    return situation and tostring(situation.lootMode) or "nil"
end

local function SaveNativeAutoLootSetting()
    state.savedAutoLootDefault = GetCVar("autoLootDefault") == "1"
    Trace("Saved original native auto loot setting as " .. AutoLootToString(state.savedAutoLootDefault))
end

local function RestoreNativeAutoLootSetting()
    if state.savedAutoLootDefault ~= nil then
        Trace("Restoring native auto loot setting to " .. AutoLootToString(state.savedAutoLootDefault))
        state.settingCVar = true
        SetCVar("autoLootDefault", state.savedAutoLootDefault and "1" or "0")
        state.settingCVar = false
    end
end

local function IsNativeAutoLootSettingExpected(situation)
    local value = GetCVar("autoLootDefault") == "1"
    local expected = state.savedAutoLootDefault

    if situation.lootMode == LootMode.NATIVE then
        expected = true
    elseif situation.lootMode == LootMode.MANUAL then
        expected = false
    elseif situation.lootMode == LootMode.MANAGED then
        expected = false
    end

    local doWeCare = situation.lootMode ~= LootMode.NONE

    if expected ~= value then
        Trace("Native auto loot setting is not as expected. Expected: " .. AutoLootToString(expected)
            .. " (" .. SituationToString(situation).. "), Actual: " .. AutoLootToString(value))
        if doWeCare then
            Addon:Warning(nil, "Native auto loot setting is not as expected. Another addon may be changing it.")
            return false
        end
    end

    return true
end

LootTracker:RegisterOnModuleInitialize(function(self)
    charDB = self.db.char
    profileDB = self.db.profile
    SaveNativeAutoLootSetting()
end)

LootTracker:RegisterOnModuleEnable(function(self)
    UpdateNativeAutoLootSetting(nil, GetLootSituation())
end)

LootTracker:RegisterOnModuleRegisterEvents(function(self)
    self:RegisterEvent("CVAR_UPDATE", "CVAR_UPDATE")
    self:RegisterEvent("LOOT_READY", "LOOT_READY")
    self:RegisterEvent("LOOT_CLOSED", "LOOT_CLOSED")
    self:RegisterEvent("LOOT_SLOT_CLEARED", "LOOT_SLOT_CLEARED")
    MessageSink:RegisterMessage("FISHING_SESSION_STARTED", function(...) self:OnFishingSessionStarted(...) end)
    MessageSink:RegisterMessage("FISHING_SESSION_ENDED",   function(...) self:OnFishingSessionEnded(...) end)
end)

LootTracker:RegisterOnModuleUnregisterEvents(function(self)
    self:UnregisterEvent("CVAR_UPDATE")
    self:UnregisterEvent("LOOT_READY")
    self:UnregisterEvent("LOOT_CLOSED")
    self:UnregisterEvent("LOOT_SLOT_CLEARED")
    MessageSink:UnregisterMessage("FISHING_SESSION_STARTED")
    MessageSink:UnregisterMessage("FISHING_SESSION_ENDED")
end)

LootTracker:RegisterOnModuleDisable(function(self)
    RestoreNativeAutoLootSetting()
end)

GetLootSituation = function()
    if state.isFishing then
        return profileDB.lootModeWhenFishing
    else
        return profileDB.lootModeWhenOther
    end
end

local function HasNativeAutoLootOverride(situation)
    return situation.lootMode ~= LootMode.NONE
end

UpdateNativeAutoLootSetting = function(previousSituation, currentSituation)
    Trace("Updating native auto loot setting. Previous situation: " .. SituationToString(previousSituation) .. ", Current situation: " .. SituationToString(currentSituation))
    if previousSituation and not IsNativeAutoLootSettingExpected(previousSituation) then
        Trace("Native auto loot setting is not as expected. Aborting update.")
        state.cvarInterference = true
        return
    end
    if previousSituation and HasNativeAutoLootOverride(previousSituation) and not HasNativeAutoLootOverride(currentSituation) then
        RestoreNativeAutoLootSetting()
    elseif currentSituation.lootMode == LootMode.MANUAL or currentSituation.lootMode == LootMode.MANAGED then
        Trace("Setting native auto loot to OFF for " .. SituationToString(currentSituation) .. " loot mode")
        state.settingCVar = true
        SetCVar("autoLootDefault", "0")
        state.settingCVar = false
    elseif currentSituation.lootMode == LootMode.NATIVE then
        Trace("Setting native auto loot to ON for " .. SituationToString(currentSituation) .. " loot mode")
        state.settingCVar = true
        SetCVar("autoLootDefault", "1")
        state.settingCVar = false
    end
end

function LootTracker:OnFishingSessionStarted()
    if not state.isFishing then
        Trace("Fishing session started, isFishing=true")
        local previousSituation = GetLootSituation()
        state.isFishing = true
        local currentSituation = GetLootSituation()
        UpdateNativeAutoLootSetting(previousSituation, currentSituation)
    end
end

function LootTracker:OnFishingSessionEnded()
    Trace("Fishing session ended")
    if state.isFishing then
        local previousSituation = GetLootSituation()
        state.isFishing = false
        local currentSituation = GetLootSituation()
        UpdateNativeAutoLootSetting(previousSituation, currentSituation)
        return
    end
end

function LootTracker:CVAR_UPDATE(_, cvar, value)
    -- This detects if the player changes the value, but not if an addon changes it
    if cvar == "autoLootDefault" then
        if state.settingCVar then
            return
        end
        Trace("CVAR_UPDATE: autoLootDefault changed to " .. AutoLootToString(value))
        state.savedAutoLootDefault = value == "1"
    end
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
            Addon:PrintLootMessage("ignoring " .. (lootItemInfo.itemLink or lootItemInfo.name))
        end
    end

    Trace("Looted " .. tostring(itemsLooted) .. " of " .. tostring(lootCount) .. " items")

    if shouldCloseLootWindow and type(CloseLoot) == "function" then
        CloseLoot()
    end

    return true
end

function LootTracker:LOOT_READY(...)
    if state.lootWindowOpen then
        --Trace("LOOT_READY: ignoring duplicate event; the loot window is already open")
        return
    end
    state.lootWindowOpen = true
    state.lootSlotItems = {}
    state.fishingCastCounted = false

    -- Tracking settings only control recording; looting itself proceeds regardless
    local shouldTrack
    if state.isFishing then
        shouldTrack = profileDB.trackFishingLoot
    else
        shouldTrack = profileDB.trackNonFishingLoot
    end
    if not shouldTrack then
        Trace("Loot tracking is disabled for " .. (state.isFishing and "fishing" or "non-fishing") .. " loot; not recording")
    end

    local lootCount = (shouldTrack and type(GetNumLootItems) == "function") and (tonumber(GetNumLootItems()) or 0) or 0
    for slot = 1, lootCount do
        local lootItemInfo = GetLootItemInfo(slot)
        state.lootSlotItems[slot] = lootItemInfo and {
            itemID = lootItemInfo.itemID,
            quantity = lootItemInfo.quantity,
        } or false
    end

    local situation = GetLootSituation()
    if situation.lootMode ~= LootMode.MANAGED then
        return
    end

    -- Handle immediately if zero
    if profileDB.lootDelay == 0 then
        HandleLootWindow(situation)
    else
        C_Timer.After(profileDB.lootDelay / 1000, function()
            HandleLootWindow(situation)
        end)
    end
end

function LootTracker:LOOT_SLOT_CLEARED(_, slot)
    slot = tonumber(slot)
    if not slot then
        return
    end

    local lootItemInfo = state.lootSlotItems[slot]
    if type(lootItemInfo) == "table" then
        if lootItemInfo.itemID and type(LootTracker.RecordLootedItem) == "function" then
            LootTracker:RecordLootedItem(lootItemInfo.itemID, lootItemInfo.quantity)
        end
        if state.isFishing and not state.fishingCastCounted then
            state.fishingCastCounted = true
            if type(LootTracker.RecordSuccessfulCast) == "function" then
                LootTracker:RecordSuccessfulCast()
            end
        end
    end
    state.lootSlotItems[slot] = nil
end

function LootTracker:LOOT_CLOSED(...)
    if not state.lootWindowOpen then
        --Trace("LOOT_CLOSED: ignoring duplicate event; the loot window is not open")
        return
    end
    state.lootWindowOpen = false
    state.lootSlotItems = {}
    state.fishingCastCounted = false
    --Trace("Loot window closed")
end
