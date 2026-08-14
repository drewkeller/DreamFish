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

local function Trace(msg)
    if DreamFish.db.profile.debugMode then
        DreamFish:Print("|cFF999999[Pole]|r ", msg)
    end
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

local function IsItemAvailableForEquip(itemID)
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

local function IsUnderlightAnglerItemID(itemID)
    local underlightID = tonumber(ns.fishing.const.underlightAnglerItemID)
    return tonumber(itemID) == underlightID
end

local function NormalizeLegacyPoleMode(mode)
    local modeText = type(mode) == "string" and mode or ""
    if modeText == "disabled" or modeText == "always_except_fishing" or modeText == "lock_underlight" then
        return modeText
    end
    return "disabled"
end

local function NormalizePoleSelection(value, validateItemID)
    local itemID = nil
    local isChecked = false

    if type(value) == "table" then
        itemID = tonumber(value.itemID)
        isChecked = value.isChecked ~= false
    else
        itemID = tonumber(value)
        isChecked = itemID ~= nil
    end

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
    local primary = NormalizePoleSelection(profileDB.selectedFishingPole)
    local underlight = NormalizePoleSelection(profileDB.selectedUnderlightAngler, IsUnderlightAnglerItemID)

    local hasStructuredPrimary = type(profileDB.selectedFishingPole) == "table"
    local hasStructuredUnderlight = type(profileDB.selectedUnderlightAngler) == "table"
    if (not hasStructuredPrimary) and (not hasStructuredUnderlight) then
        -- Legacy/scalar selections should remain opt-in when explicitly provided,
        -- even if underlightAnglerMode is absent.
        if primary.itemID == nil and underlight.itemID ~= nil then
            primary.isChecked = false
            underlight.isChecked = true
            return {
                primary = primary,
                underlight = underlight,
            }
        end

        local legacyMode = NormalizeLegacyPoleMode(profileDB.underlightAnglerMode)
        if legacyMode == "lock_underlight" then
            primary.isChecked = false
            underlight.isChecked = underlight.itemID ~= nil
        elseif legacyMode == "always_except_fishing" then
            primary.isChecked = primary.itemID ~= nil
            underlight.isChecked = underlight.itemID ~= nil
        else
            primary.isChecked = primary.itemID ~= nil
            underlight.isChecked = false
        end
    end

    return {
        primary = primary,
        underlight = underlight,
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
    local hasItem = IsItemAvailableForEquip(poleItemID)
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
