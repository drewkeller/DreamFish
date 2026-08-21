local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local function GetFishingCharDB()
    return Fishing.db and Fishing.db.char or {}
end

local function GetItemID(dbKey)
    local entry = GetFishingCharDB()[dbKey]
    DreamFish:Debug("GetItemID for dbKey " .. tostring(dbKey) .. " returned " .. tostring(entry and entry.itemID))
    return type(entry) == "table" and entry.itemID or nil
end

local function SetItemID(dbKey, itemID)
    DreamFish:Debug("SetItemID for dbKey " .. tostring(dbKey) .. " to " .. tostring(itemID))
    local charDB = GetFishingCharDB()
    charDB[dbKey] = charDB[dbKey] or {}
    charDB[dbKey].itemID = tonumber(itemID) or nil
end

local function GetIsChecked(dbKey)
    local entry = GetFishingCharDB()[dbKey]
    return type(entry) == "table" and entry.isChecked or false
end

local function SetIsChecked(dbKey, isChecked)
    local charDB = GetFishingCharDB()
    charDB[dbKey] = charDB[dbKey] or {}
    charDB[dbKey].isChecked = isChecked and true or false
end

local IsUnderlightAnglerItemID
local IsFishingPoleItemIDAndNotUnderlightAngler
local GetEquipmentAvailableForSlot

local options = {
    type = "group",
    name = "DreamFish Settings",
    childGroups = "tab",
    args = {
        polesTab = {
            type = "group",
            name = "Poles & Rods", -- This text appears on the first tab
            order = 1,
            args = {
                polesNotes = {
                    type = "description",
                    name = "Modes:\n"
                        .. "• Auto-swap: Check both boxes \n"
                        .. "   (swap occurs when starting/stopping fishing)\n"
                        .. "• Single-pole: Only check one box.\n"
                        .. "• Manual: Leave both boxes unchecked.",
                    order = 1,
                    fontSize = "medium"
                },
                primaryPole = {
                    type = "input",
                    name = "Fishing Pole",
                    order = 2,
                    width = "normal",
                    dialogControl = "DreamFishCustomPreview",

                    get = function() return tostring(GetItemID("primaryPole") or "") end,
                    set = function(_, itemID) SetItemID("primaryPole", itemID) end,

                    -- NATIVE IMMUTABLE STORAGE: Instantly available as self.userdata
                    arg = {
                        slotID = 28,
                        validateItemIDFunc = IsFishingPoleItemIDAndNotUnderlightAngler,
                        getIsChecked = function() return GetIsChecked("primaryPole") end,
                        setIsChecked = function(value) SetIsChecked("primaryPole", value) end,
                    },
                },
                underlightAngler = {
                    type = "input",
                    name = "Underlight Angler",
                    order = 3,
                    width = "normal",
                    dialogControl = "DreamFishCustomPreview",

                    get = function() return tostring(GetItemID("underlightAngler") or "") end,
                    set = function(_, itemID) SetItemID("underlightAngler", itemID) end,

                    arg = {
                        slotID = 28,
                        validateItemIDFunc = IsUnderlightAnglerItemID,
                        getIsChecked = function() return GetIsChecked("underlightAngler") end,
                        setIsChecked = function(value) SetIsChecked("underlightAngler", value) end,
                    },
                }
            },
        },
        buffsTab = {
            type = "group",
            name = "Consumables",
            order = 2,
            args = {
                consumablesDescription = {
                    type = "description",
                    name = "Configure the different consumables.",
                    order = 1,
                    fontSize = "medium",
                }
            },
        },
    },
}

IsUnderlightAnglerItemID = function (itemID)
    return tonumber(itemID) == tonumber(ns.fishing.const.underlightAnglerItemID)
end

IsFishingPoleItemIDAndNotUnderlightAngler = function(itemID)
    if not itemID or IsUnderlightAnglerItemID(itemID) then
        return false
    end

    local _, itemType, itemSubtype, itemEquipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    local isLegacyFishingPole = (itemType == "Weapon" and itemSubtype == "Fishing Poles")
        or (classID == 2 and (subclassID == 20 or subclassID == 21))
    local isFishingProfessionTool = itemEquipLoc == "INVTYPE_PROFESSION_TOOL"
        and (itemType == "Fishing" or itemSubtype == "Fishing")

    return isLegacyFishingPole or isFishingProfessionTool
end

ns.DreamFishDialogOptions = options

GetEquipmentAvailableForSlot = function (slotID, validatorFunc)
    local items = {}
    local seen = {}

    local function AddItem(itemID)
        itemID = tonumber(itemID)
        if not itemID or seen[itemID] then
            return
        end
        if validatorFunc and not validatorFunc(itemID) then
            return
        end

        seen[itemID] = true
        local name = C_Item.GetItemInfo(itemID) or ("item:" .. itemID)
        table.insert(items, { itemID = itemID, name = name })
    end

    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            AddItem(C_Container.GetContainerItemID(bag, slot))
        end
    end

    AddItem(GetInventoryItemID("player", slotID))
    table.sort(items, function(left, right) return left.name < right.name end)
    return items
end
