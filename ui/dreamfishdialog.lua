local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

DreamFish:RegisterTraceSource("ui.dreamfishdialog")
local function Trace(msg)
    DreamFish:Trace("ui.dreamfishdialog", msg)
end

local function GetFishingCharDB()
    return Fishing.db and Fishing.db.char or {}
end

local function GetItemID(dbKey)
    local entry = GetFishingCharDB()[dbKey]
    return type(entry) == "table" and entry.itemID or nil
end

local function SetItemID(dbKey, itemID)
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

local function GetBuffItem(category, index)
    local charDB = GetFishingCharDB()
    charDB.buffs = charDB.buffs or {}
    charDB.buffs[category] = charDB.buffs[category] or {}
    charDB.buffs[category][index] = charDB.buffs[category][index] or {}
    return charDB.buffs[category][index]
end

local function SetBuffItem(category, index, itemID)
    local charDB = GetFishingCharDB()
    charDB.buffs = charDB.buffs or {}
    charDB.buffs[category] = charDB.buffs[category] or {}

    charDB.buffs[category][index] = charDB.buffs[category][index] or {}
    charDB.buffs[category][index].itemID = tonumber(itemID) or nil

    if itemID then
        Trace(tostring(category) .. "[" .. tostring(index) .. "] = " .. tostring(itemID))
    else
        Trace(tostring(category) .. "[" .. tostring(index) .. "] = cleared")
    end
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
        return true -- State changed!
    end

    return false
end

local function GetEquipmentAvailableForSlot(slotID, validatorFunc)
    local items = {}
    local seen = {}

    -- Helper to process an item using its live physical coordinates
    local function AddItem(itemID, bag, slot)
        itemID = tonumber(itemID)
        if not itemID or seen[itemID] then return end
        if validatorFunc and not validatorFunc(itemID) then return end

        seen[itemID] = true
        local name = C_Item.GetItemInfo(itemID) or ("item:" .. itemID)

        -- Fetch structural tooltip data directly from the physical container location
        local tooltipData = nil
        if bag and slot then
            -- Fetching a pole from your inventory bags
            tooltipData = C_TooltipInfo.GetBagItem(bag, slot)
        else
            -- Fetching the currently equipped pole from your player slot
            tooltipData = C_TooltipInfo.GetInventoryItem("player", slotID)
        end

        local fishingBonus = 0
        local realItemLevel = 0

        if tooltipData and tooltipData.lines then
            for _, line in ipairs(tooltipData.lines) do
                if line.leftText then
                    -- 1. Parse out your real scaled Item Level (e.g. 258)
                    local iLvl = line.leftText:match("^Item%s+Level%s+([0-9]+)")
                    if iLvl then realItemLevel = tonumber(iLvl) or 0 end

                    -- 2. Parse out your true localized Midnight Fishing or generic Fishing Skill modifier
                    local bonus = line.leftText:match("%+([0-9]+)%s+[^%s]*%s*Fishing") or line.leftText:match("by%s+([0-9]+)")
                    if bonus then fishingBonus = tonumber(bonus) or fishingBonus end
                end
            end
        end

        -- If the item level parsing missed, fall back to basic skill bonuses as a sorting engine backup
        local sortingWeight = realItemLevel > 0 and realItemLevel or fishingBonus

        table.insert(items, {
            itemID = itemID,
            name = name,
            itemLevel = sortingWeight, -- Prioritizes real level for dropdown sorting
            -- Save location markers so our widget menu can generate the exact tooltip later
            locationMarker = (bag and slot) and (bag .. "," .. slot) or "equipped"
        })
    end

    -- 1. Scan your player container bags safely
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then AddItem(itemID, bag, slot) end
        end
    end

    -- 2. Scan your player's equipped profession slot safely
    local equippedID = GetInventoryItemID("player", slotID)
    if equippedID then AddItem(equippedID, nil, nil) end

    -- Sort the data structures array cleanly (highest item level floats to top)
    table.sort(items, function(left, right)
        if left.itemLevel ~= right.itemLevel then
            return left.itemLevel > right.itemLevel
        end
        return left.name < right.name
    end)

    return items
end

local function GetPoleSelectorOptionsForDropDown()
    local availablePoles = GetEquipmentAvailableForSlot(28, IsFishingPoleItemIDAndNotUnderlightAngler)
    local listData = {}
    local hasItems = false

    for _, info in ipairs(availablePoles) do
        if info.itemID then
            -- Format: "itemLevel:locationMarker:itemName"
            listData[tostring(info.itemID)] = info.itemLevel .. ":" .. info.locationMarker .. ":" .. info.name
            hasItems = true
        end
    end

    if not hasItems then
        listData[""] = "0:none:No fishing poles found"
    end

    return listData
end

-- Flattens the items to: flatlist[itemID] = "name:bag:slot"
local function FlattenToNameBagSlot(foundInventoryItems)
    local flatList = {}
    for _, info in ipairs(foundInventoryItems) do
        if info.itemID then
            local name = C_Item.GetItemNameByID(info.itemID) or "Unknown"
            flatList[tostring(info.itemID)] = name .. ":" .. tostring(info.bag) .. ":" .. tostring(info.slot)
        end
    end
    return flatList
end


local options = {
    type = "group",
    name = "DreamFish Settings",
    childGroups = "tab",
    args = {
        polesTab = {
            type = "group",
            name = "Poles & Rods",
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
                        .. "• Auto-swap: |cFF999999Check both boxes|r\n"
                        .. "   |cFF999999(swap occurs when starting/stopping fishing)|r\n"
                        .. "• Single-pole: |cFF999999Only check one box.|r\n"
                        .. "• Manual: |cFF999999Leave both boxes unchecked.|r",
                    order = 1,
                    fontSize = "medium"
                },
                spacer = {
                    type = "description",
                    name = " ",
                    order = 1.5,
                    fontSize = "small"
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
                        desc = "The pole used for fishing. Click to select from your available fishing poles.",
                        slotID = 28,
                        validateItemIDFunc = function(itemID) return IsFishingPoleItemIDAndNotUnderlightAngler(itemID) end,
                        getIsChecked = function() return GetIsChecked("primaryPole") end,
                        setIsChecked = function(value) SetIsChecked("primaryPole", value) end,
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
                        desc = "Always shown here if it is available in your bags or equipped.",
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
                },
                consumablesSpacer = {
                    type = "description",
                    name = " ",
                    order = 1.5,
                    fontSize = "small",
                },
                -- case-matched to "fooddrink" category
                fooddrinkGroup = {
                    type = "group",
                    name = "Food & Drink",
                    order = 2,
                    inline = true,
                    args = {
                        fooddrink_1 = {
                            type = "select",
                            name = " ",
                            dialogControl = "DreamFishBuffItemDropBox",
                            width = "half",
                            get = function() return tostring(GetBuffItem("fooddrink", 1).itemID or "") end,
                            set = function(_, value)
                                    SetBuffItem("fooddrink", 1, value)
                                end,
                            values = function()
                                -- get items that match the category
                                local foundInventoryItems = DreamFish:FindItemsInBagsWhere(function(itemID, bag, slot)
                                    return Fishing:IsBuffItemCategory("fooddrink", itemID, bag, slot)
                                end)
                                return FlattenToNameBagSlot(foundInventoryItems)
                            end,
                            arg = {
                                validateItemIDFunc = function(itemID, bag, slot) return Fishing:IsBuffItemCategory("fooddrink", itemID, bag, slot) end,
                                getIsChecked = function() return GetBuffItem("fooddrink", 1).isChecked or false end,
                                setIsChecked = function(value)
                                    GetBuffItem("fooddrink", 1).isChecked = value
                                    Trace("fooddrink[1].isChecked = " .. tostring(value))
                                end,
                                categoryTitle = "Food/Drink",
                                category = "fooddrink",
                                index = 1,
                            }
                        },
                    }
                }, -- foodDrinkGroup
                lureGroup = {
                    type = "group",
                    name = "Lures",
                    order = 3,
                    inline = true,
                    args = {
                        lure_1 = {
                            type = "select",
                            name = " ",
                            dialogControl = "DreamFishBuffItemDropBox",
                            width = "half",
                            get = function() return tostring(GetBuffItem("lure", 1).itemID or "") end,
                            set = function(_, value) SetBuffItem("lure", 1, value) end,
                            values = function()
                                local foundInventoryItems = DreamFish:FindItemsInBagsWhere(function(itemID, bag, slot)
                                    return Fishing:IsBuffItemCategory("lure", itemID, bag, slot)
                                end)
                                return FlattenToNameBagSlot(foundInventoryItems)
                            end,
                            arg = {
                                validateItemIDFunc = function(itemID, bag, slot) return Fishing:IsBuffItemCategory("lure", itemID, bag, slot) end,
                                getIsChecked = function() return GetBuffItem("lure", 1).isChecked or false end,
                                setIsChecked = function(value)
                                    GetBuffItem("lure", 1).isChecked = value
                                    Trace("lure[1].isChecked = " .. tostring(value))
                                end,
                                categoryTitle = "Lure",
                                category = "lure",
                                index = 1,
                            }
                        },
                    }
                },
                baitGroup = {
                    type = "group",
                    name = "Bait",
                    order = 4,
                    inline = true,
                    args = {
                        bait_1 = {
                            type = "select",
                            name = " ",
                            dialogControl = "DreamFishBuffItemDropBox",
                            width = "half",
                            get = function() return tostring(GetBuffItem("bait", 1).itemID or "") end,
                            set = function(_, value) SetBuffItem("bait", 1, value) end,
                            values = function()
                                local foundInventoryItems = DreamFish:FindItemsInBagsWhere(function(itemID, bag, slot)
                                    return Fishing:IsBuffItemCategory("bait", itemID, bag, slot)
                                end)
                                return FlattenToNameBagSlot(foundInventoryItems)
                            end,
                            arg = {
                                validateItemIDFunc = function(itemID, bag, slot) return Fishing:IsBuffItemCategory("bait", itemID, bag, slot) end,
                                getIsChecked = function() return GetBuffItem("bait", 1).isChecked or false end,
                                setIsChecked = function(value)
                                    GetBuffItem("bait", 1).isChecked = value
                                    Trace("bait[1].isChecked = " .. tostring(value))
                                end,
                                categoryTitle = "Bait",
                                category = "bait",
                                index = 1,
                            }
                        },
                    },
                },
                -- match to "other_consumable" category
                other_consumableGroup = {
                    type = "group",
                    name = "Other Buffs",
                    order = 5,
                    inline = true,
                    args = {
                        otherBuffs_1 = {
                            type = "select",
                            name = " ",
                            dialogControl = "DreamFishBuffItemDropBox",
                            width = "half",
                            get = function() return tostring(GetBuffItem("other_consumable", 1).itemID or "") end,
                            set = function(_, value) SetBuffItem("other_consumable", 1, value) end,
                            values = function()
                                local foundInventoryItems = DreamFish:FindItemsInBagsWhere(function(itemID, bag, slot)
                                    return Fishing:IsBuffItemCategory("other_consumable", itemID, bag, slot)
                                end)
                                return FlattenToNameBagSlot(foundInventoryItems)
                            end,
                            arg = {
                                validateItemIDFunc = function(itemID, bag, slot) return Fishing:IsBuffItemCategory("other_consumable", itemID, bag, slot) end,
                                getIsChecked = function() return GetBuffItem("other_consumable", 1).isChecked or false end,
                                setIsChecked = function(value)
                                    GetBuffItem("other_consumable", 1).isChecked = value
                                    Trace("other_consumable[1].isChecked = " .. tostring(value))
                                end,
                                categoryTitle = "Buff",
                                category = "other_consumable",
                                index = 1,
                            }
                        },
                    },
                }
            },
        }, -- buffsTab
    },
}

ns.DreamFishDialogOptions = options
