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

local function IsUnderlightAnglerItemID(itemID)
    return tonumber(itemID) == tonumber(ns.fishing.const.underlightAnglerItemID)
end

local function IsFishingPoleItemIDAndNotUnderlightAngler(itemID)
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

local function AutoDetectUnderlightAngler()
    local anglerID = tonumber(ns.fishing.const.underlightAnglerItemID)
    if not anglerID then return false end

    -- Guard: If it's already configured in the database, don't execute updates or trigger reloads
    if GetItemID("underlightAngler") == anglerID then
        return false
    end

    if DreamFish:IsItemAvailableForEquip(anglerID) then
        SetItemID("underlightAngler", anglerID)
        DreamFish:Debug("Auto-populated Underlight Angler into settings.")
        return true -- State changed!
    end

    return false
end

local function GetEquipmentAvailableForSlot(slotID, validatorFunc)
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
        DreamFish:Debug("Found item for slot " .. tostring(slotID) .. ": " .. tostring(name) .. " (itemID: " .. tostring(itemID) .. ")")
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

local function GetPoleSelectorOptionsForDropDown()
    local availablePoles = GetEquipmentAvailableForSlot(28, IsFishingPoleItemIDAndNotUnderlightAngler)
    local listData = {}
    local hasItems = false

    for _, info in ipairs(availablePoles) do
        if info.itemID then
            listData[tostring(info.itemID)] = info.name
            hasItems = true
        end
    end

    if not hasItems then
        listData[""] = "No fishing poles found"
    end

    return listData
end


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
                -- using a description item to trigger "OnShown" updates
                onPolesShownTrigger = {
                    type = "description",
                    name = function()
                        local updated = AutoDetectUnderlightAngler()
                        if updated then
                            LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
                        end
                        return ""
                    end,
                    order = 0,
                },
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
                    type = "select",
                    name = "Fishing Pole",
                    order = 2,
                    width = "normal",
                    dialogControl = "DreamFishEquipmentPreview",

                    get = function()
                        local savedID = GetItemID("primaryPole")
                        return savedID and tostring(savedID) or ""
                    end,
                    set = function(_, itemID)
                        SetItemID("primaryPole", itemID)
                    end,
                    values = function()
                        return GetPoleSelectorOptionsForDropDown()
                    end,

                    arg = {
                        slotID = 28,
                        validateItemIDFunc = function(itemID) return IsFishingPoleItemIDAndNotUnderlightAngler(itemID) end,
                        getIsChecked = function() return GetIsChecked("primaryPole") end,
                        setIsChecked = function(value) SetIsChecked("primaryPole", value) end,

                        -- Safe, localized scanning hook preserved cleanly by AceConfig
                        --getAvailableOptions = function() return GetPoleSelectorOptionsForDropDown() end,
                    },
                },
                underlightAngler = {
                    type = "input",
                    name = "Underlight Angler",
                    order = 3,
                    width = "normal",
                    dialogControl = "DreamFishEquipmentPreview",

                    get = function() return tostring(GetItemID("underlightAngler") or "") end,
                    set = function(_, itemID) SetItemID("underlightAngler", itemID) end,

                    arg = {
                        slotID = 28,
                        canRemoveItem = false,
                        validateItemIDFunc = function(itemID) return IsUnderlightAnglerItemID(itemID) end,
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

ns.DreamFishDialogOptions = options
