local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local globalDB, profileDB, charDB
local function Initialize()
    globalDB = ns.FishingDB.global
    profileDB = ns.FishingDB.profile
    charDB = ns.FishingDB.char
end
ns.FishingInitializers = ns.FishingInitializers or {}
table.insert(ns.FishingInitializers, Initialize)

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
    local underlightID = tonumber(ns.fishing.const.underlightAnglerItemID)
    return tonumber(itemID) == underlightID
end

local function NormalizePoleSelection(value, validateItemID)
    local itemID = tonumber(type(value) == "table" and value.itemID or nil)
    local isChecked = type(value) == "table" and value.isChecked ~= false or false

    if not itemID or itemID <= 0 then
        itemID = nil
    end
    if itemID and validateItemID and (not validateItemID(itemID)) then
        itemID = nil
    end
    if not itemID then
        isChecked = false
    end

    return {
        itemID = itemID,
        isChecked = isChecked and true or false,
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
    local hasItem = DreamFish:IsItemAvailableForEquip(poleItemID)
    local mounted = (type(IsMounted) == "function" and IsMounted()) or false
    local equippedItemID = GetEquippedProfessionItemID()
    local alreadyEquipped = poleItemID and equippedItemID and (poleItemID == equippedItemID) or false
    local shouldApply = hasItem
        and selections.primary.isChecked
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

ns.precast.GetSelectedFishingPoleDecision = GetSelectedFishingPoleDecision
ns.precast.GetEquippedProfessionItemID = GetEquippedProfessionItemID
ns.precast.GetConfiguredPoleSelections = GetConfiguredPoleSelections
ns.precast.IsItemAvailableForEquip = IsItemAvailableForEquip
