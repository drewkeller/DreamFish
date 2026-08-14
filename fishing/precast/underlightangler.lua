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
        DreamFish:Print("|cFF999999[Bobber]|r ", msg)
    end
end

local function GetUnderlightAnglerEquipDecision()
    local selections = ns.precast.GetConfiguredPoleSelections()
    local isSelected = selections.underlight.isChecked
    local itemID = ns.fishing.const.underlightAnglerItemID or nil
    local hasItem = ns.precast.IsItemAvailableForEquip(itemID)
    local mounted = IsMounted()
    local equippedItemID = ns.precast.GetEquippedProfessionItemID()
    local alreadyEquipped = itemID
        and equippedItemID
        and (itemID == equippedItemID)
        or false
    local shouldEquip = selections.underlight.isChecked
        and (not selections.primary.isChecked)
        and hasItem
        and not mounted
        and not alreadyEquipped

    if shouldEquip then
        Trace("Underlight Angler can be equipped")
    elseif (not isSelected) then
        Trace("Underlight Angler is not selected for use")
    elseif not hasItem then
        Trace("Underlight Angler is not owned")
    elseif mounted then
        Trace("Player is mounted")
    else
        Trace("Underlight Angler will not be equipped for unknown reason")
    end

    return {
        itemID = itemID,
        hasItem = hasItem,
        shouldEquip = shouldEquip,
        mounted = mounted,
        alreadyEquipped = alreadyEquipped,
    }
end

ns.precast.GetUnderlightAnglerEquipDecision = GetUnderlightAnglerEquipDecision
