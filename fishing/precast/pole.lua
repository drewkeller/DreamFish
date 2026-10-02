local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

local globalDB, profileDB, charDB
Fishing:RegisterOnModuleInitialize(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

Fishing:RegisterTraceSource("pole")

local FISHING_POLE_SLOT = 28

local function Trace(msg)
    Fishing:Trace("pole", msg)
end

local function GetEquippedProfessionItemID()
    if type(GetInventoryItemID) ~= "function" then
        return nil
    end
    local ok, rawItemID = pcall(GetInventoryItemID, "player", FISHING_POLE_SLOT)
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

local function GetSelectedFishingPoleDecision()
    local selections = GetConfiguredPoleSelections()
    local itemID = selections.primary.itemID
    local isSelected = selections.primary.isChecked
    local hasItem = ns.Utils.IsItemAvailableForEquip(itemID)
    local mounted = (type(IsMounted) == "function" and IsMounted()) or false
    local equippedItemID = GetEquippedProfessionItemID()
    local canEquip = itemID
        and isSelected
        and hasItem
    local alreadyEquipped = itemID and equippedItemID and (itemID == equippedItemID) or false
    local shouldApply = hasItem
        and selections.primary.isChecked
        and Fishing:CanStartCast()
        and (not mounted)
        and (not alreadyEquipped)

    if shouldApply then
        Trace("Primary fishing poleItemID=" .. tostring(itemID) .. " is ready to be applied.")
    elseif not hasItem then
        Trace("Primary fishing poleItemID=" .. tostring(itemID) .. " is not available in bags or equipped.")
    elseif not selections.primary.isChecked then
        Trace("Primary fishing poleItemID=" .. tostring(itemID) .. " is not selected for application.")
    elseif mounted then
        Trace("Player is mounted; primary pole will not be applied.")
    elseif alreadyEquipped then
        Trace("Primary fishing poleItemID=" .. tostring(itemID) .. " is already equipped; no action needed.")
    end

    return {
        itemID = itemID,
        hasItem = hasItem,
        mounted = mounted,
        canEquip = canEquip,
        alreadyEquipped = alreadyEquipped,
        shouldApply = shouldApply,
    }
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

    if(ns.Utils.TryEquipItemToProfessionSlot(itemToEquip, FISHING_POLE_SLOT)) then
        Trace("Successfully equipped selected pole: " .. ns.Utils.GetDebugItemLabel(itemToEquip))
    else
        Trace("Failed to equip selected pole: " .. ns.Utils.GetDebugItemLabel(itemToEquip))
    end
end

function Fishing:CheckAndHandlePoleSwapReset()
    -- Fetch the exact item ID currently sitting inside your actual live character profession journal
    local currentJournalPoleID = type(GetEquippedProfessionItemID) == "function" and GetEquippedProfessionItemID() or nil

    -- If your live slot tool shifts compared to our last checked pass, clear your tracking states instantly
    if currentJournalPoleID and self.state.lastKnownJournalPoleID and (currentJournalPoleID ~= self.state.lastKnownJournalPoleID) then
        self.state.lureAppliedUntil = nil
        if type(self.state.buffItemLastUseAt) == "table" and self.db and self.db.char.buffs then
            local configuredBuffs = self.db.char.buffs
            if type(configuredBuffs.lure) == "table" then
                for _, entry in pairs(configuredBuffs.lure) do
                    if type(entry) == "table" and entry.itemID then
                        local lureItemID = tonumber(entry.itemID)
                        if lureItemID and self.state.buffItemLastUseAt[lureItemID] then
                            self:Trace("underlight", "Pole swap detected in journal index! Clearing timer for item " .. lureItemID)
                            self.state.buffItemLastUseAt[lureItemID] = nil
                        end
                    end
                end
            end
        end
    end

    -- Keep our cached structural record updated for future comparisons
    if currentJournalPoleID then
        self.state.lastKnownJournalPoleID = currentJournalPoleID
    end
end

ns.precast.GetSelectedFishingPoleDecision = GetSelectedFishingPoleDecision
ns.precast.GetEquippedProfessionItemID = GetEquippedProfessionItemID
ns.precast.GetConfiguredPoleSelections = GetConfiguredPoleSelections
ns.precast.ApplySelectedFishingPole = ApplySelectedFishingPole
