local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing
local LootTracker = ns.LootTracker

Addon:RegisterTraceSource("ui.dreamfishdialog")
local function Trace(msg)
    Addon:TraceCore("ui.dreamfishdialog", msg)
end

local function GetFishingCharDB()
    return Fishing.db and Fishing.db.char or {}
end

local layoutCounter = 0
local function AutoOrder(nodeTable)
    layoutCounter = layoutCounter + 1
    nodeTable.order = layoutCounter
    return nodeTable
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
    if not InCombatLockdown() then
        ns.precast.ApplySelectedFishingPole()
        --Fishing:PrepareFishingClickAction()
    end
end

local function IsUnderlightAnglerItemID(itemID)
    return tonumber(itemID) == tonumber(ns.Fishing.const.underlightAnglerItemID)
end

local function GetBuffItem(category, index)
    if Fishing.db and Fishing.db.char then
        Fishing.db.char.buffs = Fishing.db.char.buffs or {}
        Fishing.db.char.buffs[category] = Fishing.db.char.buffs[category] or {}
        Fishing.db.char.buffs[category][index] = Fishing.db.char.buffs[category][index] or { enabled = false, itemID = nil }

        local itemNode = Fishing.db.char.buffs[category][index]
        return {
            itemID = itemNode.itemID,
            isChecked = itemNode.enabled
        }
    end
    return { itemID = nil, isChecked = false }
end

local function SetBuffItem(category, index, itemID)
    if Fishing.db and Fishing.db.char then
        Fishing.db.char.buffs = Fishing.db.char.buffs or {}
        Fishing.db.char.buffs[category] = Fishing.db.char.buffs[category] or {}
        Fishing.db.char.buffs[category][index] = Fishing.db.char.buffs[category][index] or { enabled = false, itemID = nil }

        local cleanID = tonumber(itemID) or nil
        Fishing.db.char.buffs[category][index].itemID = cleanID

        if cleanID then
            Trace(tostring(category) .. "[" .. tostring(index) .. "] = " .. tostring(cleanID))
        else
            Trace(tostring(category) .. "[" .. tostring(index) .. "] = cleared")
        end
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
    local anglerID = tonumber(ns.Fishing.const.underlightAnglerItemID)
    if not anglerID then return false end

    if GetItemID("underlightAngler") == anglerID then
        return false
    end

    if ns.Utils.IsItemAvailableForEquip(anglerID) then
        SetItemID("underlightAngler", anglerID)
        return true
    end

    return false
end

local function GetEquipmentAvailableForSlot(slotID, validatorFunc)
    local items = {}
    local seen = {}

    local function AddItem(itemID, bag, slot)
        itemID = tonumber(itemID)
        if not itemID or seen[itemID] then return end
        if validatorFunc and not validatorFunc(itemID) then return end

        seen[itemID] = true
        local name = C_Item.GetItemInfo(itemID) or ("item:" .. itemID)

        local tooltipData = nil
        if bag and slot then
            tooltipData = C_TooltipInfo.GetBagItem(bag, slot)
        else
            tooltipData = C_TooltipInfo.GetInventoryItem("player", slotID)
        end

        local fishingBonus = 0
        local realItemLevel = 0

        if tooltipData and tooltipData.lines then
            for _, line in ipairs(tooltipData.lines) do
                if line.leftText then
                    local iLvl = line.leftText:match("^Item%s+Level%s+([0-9]+)")
                    if iLvl then realItemLevel = tonumber(iLvl) or 0 end

                    local bonus = line.leftText:match("%+([0-9]+)%s+[^%s]*%s*Fishing") or line.leftText:match("by%s+([0-9]+)")
                    if bonus then fishingBonus = tonumber(bonus) or fishingBonus end
                end
            end
        end

        local sortingWeight = realItemLevel > 0 and realItemLevel or fishingBonus

        table.insert(items, {
            itemID = itemID,
            name = name,
            itemLevel = sortingWeight,
            locationMarker = (bag and slot) and (bag .. "," .. slot) or "equipped"
        })
    end

    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then AddItem(itemID, bag, slot) end
        end
    end

    local equippedID = GetInventoryItemID("player", slotID)
    if equippedID then AddItem(equippedID, nil, nil) end

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
            listData[tostring(info.itemID)] = info.itemLevel .. ":" .. info.locationMarker .. ":" .. info.name
            hasItems = true
        end
    end

    if not hasItems then
        listData[""] = "0:none:No fishing poles found"
    end

    return listData
end

local function FlattenToNameBagSlot(foundInventoryItems)
    local flatList = {}
    for _, info in ipairs(foundInventoryItems) do
        if info.itemID then
            local name = C_Item.GetItemNameByID(info.itemID) or "Unknown"
            flatList[tostring(info.itemID)] = name .. ":0:0"
        end
    end
    return flatList
end

local options = {
    type = "group",
    name = addonName .. " Tackle Box",
    childGroups = "tab",
    args = {
        polesTab = {
            type = "group",
            name = "Poles & Rods",
            order = 1,
            args = {
                onPolesShownTrigger = AutoOrder({
                    type = "description",
                    name = function()
                        local updated = AutoDetectUnderlightAngler()
                        if updated then
                            LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
                        end
                        return ""
                    end,
                }),
                polesNotes = AutoOrder({
                    type = "description",
                    name = "Modes:\n"
                        .. "• Auto-swap: |cFF999999Check both boxes|r\n"
                        .. "   |cFF999999(swap occurs when starting/stopping fishing)|r\n"
                        .. "• Single-pole: |cFF999999Only check one box.|r\n"
                        .. "• Manual: |cFF999999Leave both boxes unchecked.|r",
                    fontSize = "medium"
                }),
                spacer = AutoOrder({
                    type = "description",
                    name = " ",
                    fontSize = "small"
                }),
                primaryPole = AutoOrder({
                    type = "select",
                    name = "Fishing Pole",
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
                }),
                underlightAngler = AutoOrder({
                    type = "input",
                    name = "Underlight Angler",
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
                }),
                divider = AutoOrder({
                    type = "header",
                    name = "-----",
                }),
                raftSection = AutoOrder({
                    type = "group",
                    name = "  ",
                    desc = "Settings for auto-casting a raft when fishing.",
                    inline = true,
                    args = {
                        selectedRaftToy = AutoOrder({
                            type = "select",
                            name = "Raft",
                            desc = "Choose the raft to be used when fishing. Applied automatically when casting the fishing line.",
                            values = function()
                                return ns.Utils.BuildOwnedToyOptions(ns.Fishing.const.raftToyItemIDs, "No Raft")
                            end,
                            sorting = function()
                                return ns.Utils.BuildOwnedToySortingKeys(ns.Fishing.const.raftToyItemIDs, "No Raft")
                            end,
                            get = function()
                                return Fishing.db.profile.selectedRaftToy
                            end,
                            set = function(_, value)
                                Fishing.db.profile.selectedRaftToy = value
                            end,
                            width = "relative",
                            relWidth = 0.75,
                        }),
                        applyRaft = AutoOrder({
                            type = "execute",
                            name = "Apply",
                            desc = "Manually apply the selected raft now.",
                            func = function()
                                Fishing:ApplyRaft()
                            end,
                            width = "relative",
                            relWidth = 0.24,
                        }),
                    },
                }),
                bobberSection = AutoOrder({
                    type = "group",
                    name = "  ",
                    desc = "Settings for auto-casting a bobber when fishing.",
                    inline = true,
                    args = {
                        selectedBobberToy = AutoOrder({
                            type = "select",
                            name = "Bobber",
                            desc = "Choose the bobber to be used when fishing. Applied automatically when casting the fishing line.",
                            values = function()
                                return ns.Utils.BuildOwnedToyOptions(ns.Fishing.const.bobberToyItemIDs, "Standard Bobber")
                            end,
                            sorting = function()
                                return ns.Utils.BuildOwnedToySortingKeys(ns.Fishing.const.bobberToyItemIDs, "Standard Bobber")
                            end,
                            get = function()
                                return Fishing.db.profile.selectedBobberToy
                            end,
                            set = function(_, value)
                                Fishing.db.profile.selectedBobberToy = value
                            end,
                            width = "relative",
                            relWidth = 0.75,
                        }),
                        applyBobber = AutoOrder({
                            type = "execute",
                            name = "Apply",
                            desc = "Manually apply the selected bobber now.",
                            func = function()
                                Fishing:ApplyBobber()
                            end,
                            width = "relative",
                            relWidth = 0.24,
                        }),
                        useOversizedBobber = AutoOrder({
                            type = "toggle",
                            name = "Use Oversized Bobber",
                            desc = "Also apply the oversized bobber to your selected bobber (adds another click to apply it)",
                            get = function()
                                return Fishing.db.profile.useOversizedBobber
                            end,
                            set = function(_, value)
                                Fishing.db.profile.useOversizedBobber = value
                            end,
                            width = "full",
                        }),
                    } -- Bobber section
                }),
            },
        },
        buffsTab = {
            type = "group",
            name = "Consumables",
            order = 2,
            args = {
                notesSpacer = {
                    type = "description",
                    name = " ",
                    order = 900,
                    fontSize = "medium",
                },
                notesCollapser = {
                    type = "toggle",
                    name = "Notes",
                    order = 901,
                    width = "full",
                    get = function()
                        return Fishing.db.profile.showBuffNotes ~= false
                    end,
                    set = function(_, value)
                        Fishing.db.profile.showBuffNotes = value
                        --LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
                    end,
                },
                notesDescription = {
                    type = "description",
                    name = "|cFF999999Drag items from your bags into the boxes above"
                        .. " or click a box to select from your available items.|r\n\n"
                        .. "|cFF999999Buffs are automatically applied during fishing pre-casting.|r\n"
                        .. "|cFF999999  * Each category is processed in the order shown, top to bottom.|r\n"
                        .. "|cFF999999  * Items are applied left to right within each category.|r",
                    order = 902,
                    fontSize = "medium",
                    hidden = function() return Fishing.db.profile.showBuffNotes == false end,
                },
            },
        },
        lootTrackerTab = {
            type = "group",
            name = "Loot Tracker",
            order = 3,
            -- Only shown when the LootTracker "Show Tracker As" option is set to "tab".
            -- Guard every link in the chain: an error here would abort the whole tab bar's render.
            hidden = function()
                return not (LootTracker and LootTracker.db and LootTracker.db.profile
                    and LootTracker.db.profile.showTrackerAs == "tab")
            end,
            args = {
                panel = {
                    type = "execute",
                    name = " ",
                    dialogControl = "DreamFishLootTrackerPanel",
                    width = "full",
                    func = function() end,
                },
            },
        },
    },
}

-- ============================================================================
-- HIGH-PERFORMANCE DYNAMIC CANVASES MATRIX GENERATOR
-- ============================================================================
local gridMatrix = {
    { key = "fooddrink",        title = "Food/Drink", groupName = "Food & Drink", slots = 5,  order = 2 },
    { key = "lure",             title = "Lure",       groupName = "Lures",        slots = 5,  order = 3 },
    { key = "bait",             title = "Bait",       groupName = "Bait",         slots = 5,  order = 4 },
    { key = "other_consumable", title = "Buff",       groupName = "Other Buffs",  slots = 10, order = 5 },
}

-- Performance Cache Buffers: Prevents redundant bag scans from bottlenecking AceConfig
local cachedScanResults = {}
local lastScanTimestamp = 0

local function GetCachedInventoryList(categoryKey)
    local now = GetTime()

    if not cachedScanResults[categoryKey] or (now - lastScanTimestamp > 0.5) then
        cachedScanResults = {}
        lastScanTimestamp = now

        for _, config in ipairs(gridMatrix) do
            local foundItems = ns.Utils.FindItemsInBagsWhere(function(itemID, bag, slot)
                return Fishing:IsBuffItemCategory(config.key, itemID, bag, slot)
            end)
            cachedScanResults[config.key] = FlattenToNameBagSlot(foundItems)
        end
    end

    return cachedScanResults[categoryKey] or {}
end

local expandedStates = {}

for _, config in ipairs(gridMatrix) do
    local headerKey = config.key .. "HeaderToggle"
    local canvasKey = config.key .. "CanvasSlot"

    if expandedStates[config.key] == nil then
        expandedStates[config.key] = true
    end

    -- Inject the flat Interactive "Header"
    options.args.buffsTab.args[headerKey] = {
        type = "toggle",
        name = function() return config.groupName .. "|c66999999 (show/hide)|r" end,
        desc = "Click to toggle display visibility of the " .. config.groupName .. " items.",
        order = config.order * 2,
        width = "full",
        get = function()
            return expandedStates[config.key]
        end,
        set = function(_, value)
            expandedStates[config.key] = value
            LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
        end,
    }

    -- Inject the Grid DropBox Canvas
    options.args.buffsTab.args[canvasKey] = {
        type = "execute",
        name = " ",
        dialogControl = "DreamFishBuffItemDropBox",
        width = "normal",
        order = (config.order * 2) + 1,
        hidden = function()
            return expandedStates[config.key] == false
        end,
        get = function() return config.key end,
        func = function() end,
        control = config.key,
        arg = {
            category = config.key,
            slots = config.slots,
            categoryTitle = config.title,
            dropdownMenuData = function() return GetCachedInventoryList(config.key) end,

            GetItemValue = function(idx)
                local entry = GetBuffItem(config.key, idx)
                return entry and entry.itemID and tostring(entry.itemID) or ""
            end,
            SetItemValue = function(idx, val)
                if Fishing.db and Fishing.db.char then
                    Fishing.db.char.buffs = Fishing.db.char.buffs or {}
                    Fishing.db.char.buffs[config.key] = Fishing.db.char.buffs[config.key] or {}
                    Fishing.db.char.buffs[config.key][idx] = Fishing.db.char.buffs[config.key][idx] or { enabled = false, itemID = nil }
                    Fishing.db.char.buffs[config.key][idx].itemID = tonumber(val) or nil
                else
                    Trace("SetItemValue: ABORTED, Fishing.db.char unavailable for " .. config.key .. "[" .. tostring(idx) .. "]")
                end
            end,
            GetCheckedValue = function(idx)
                if Fishing.db and Fishing.db.char and Fishing.db.char.buffs and Fishing.db.char.buffs[config.key] and Fishing.db.char.buffs[config.key][idx] then
                    return Fishing.db.char.buffs[config.key][idx].enabled or false
                end
                return false
            end,
            SetCheckedValue = function(idx, val)
                if Fishing.db and Fishing.db.char then
                    Fishing.db.char.buffs = Fishing.db.char.buffs or {}
                    Fishing.db.char.buffs[config.key] = Fishing.db.char.buffs[config.key] or {}
                    Fishing.db.char.buffs[config.key][idx] = Fishing.db.char.buffs[config.key][idx] or { enabled = false, itemID = nil }
                    Fishing.db.char.buffs[config.key][idx].enabled = val and true or false
                    Trace(config.key .. "[" .. idx .. "].enabled = " .. tostring(val))
                end
            end,
            validateItemIDFunc = function(itemID, bag, slot)
                return Fishing:IsBuffItemCategory(config.key, itemID, bag, slot)
            end,
        }
    }
end

local buffArgs = options.args.buffsTab.args
buffArgs.fooddrinkHeaderToggle.desc = "Toggle the display of food and drink buffs."
buffArgs.lureHeaderToggle.desc = "Toggle the display of lure buffs. Lures are applied to the primary fishing pole. Only one lure can be active on the pole at a time."
buffArgs.baitHeaderToggle.desc = "Toggle the display of bait buffs. Only one bait aura can be active at a time. Many are zone-specific."
buffArgs.other_consumableHeaderToggle.desc = "Toggle the display of other consumables."

ns.DialogOptions = options
