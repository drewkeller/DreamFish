-- DreamFisher: Buff Item Management

local addon = _G["DreamFisher"]
local Clamp = addon.Clamp
local PrintMessage = addon.PrintMessage
local DebugMessage = addon.DebugMessage

local function GetItemInfoInstantSafe(itemID)
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        return C_Item.GetItemInfoInstant(itemID)
    end
    if type(GetItemInfoInstant) == "function" then
        return GetItemInfoInstant(itemID)
    end
    return nil
end

local function GetBuffItemCategory(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return "other_consumable"
    end

    local known = addon.const
        and type(addon.const.knownBuffItems) == "table"
        and addon.const.knownBuffItems[numeric]
        or nil
    if type(known) == "table" and type(known.category) == "string" and known.category ~= "" then
        return known.category
    end

    if addon.const and type(addon.const.bobberToyItemIDs) == "table" then
        for _, toyItemID in ipairs(addon.const.bobberToyItemIDs) do
            if tonumber(toyItemID) == numeric then
                return "bobber"
            end
        end
    end

    local _, itemType, itemSubType, _, _, classID = GetItemInfoInstantSafe(numeric)
    local consumableClassID = rawget(_G, "LE_ITEM_CLASS_CONSUMABLE")
    if classID and consumableClassID and classID ~= consumableClassID then
        return "other_consumable"
    end

    local itemTypeText = type(itemType) == "string" and string.lower(itemType) or ""
    local itemSubTypeText = type(itemSubType) == "string" and string.lower(itemSubType) or ""
    if itemTypeText:find("consumable", 1, true) ~= nil then
        if itemSubTypeText:find("food", 1, true) ~= nil or itemSubTypeText:find("drink", 1, true) ~= nil then
            return "food_drink"
        end
        if itemSubTypeText:find("item enhancement", 1, true) ~= nil
            or itemSubTypeText:find("enchant", 1, true) ~= nil
            or itemSubTypeText:find("weapon", 1, true) ~= nil then
            return "lure"
        end
    end

    return "other_consumable"
end

local function GetBuffItemLabel(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return "unknown"
    end
    local itemName = (type(GetItemInfo) == "function" and GetItemInfo(numeric)) or nil
    if itemName and itemName ~= "" then
        return tostring(itemName) .. " (" .. tostring(numeric) .. ")"
    end
    return "item:" .. tostring(numeric)
end

local function GetBuffTimingText(itemID)
    if not addon.db or type(addon.db.buffAuraByItem) ~= "table" then
        return "duration unknown (learning aura mapping)"
    end

    local tracked = addon.db.buffAuraByItem[tostring(itemID)]
    if type(tracked) ~= "table" or not tracked.spellID then
        return "duration unknown (learning aura mapping)"
    end

    local itemDuration = tracked.duration
    local aura = addon.buff.GetAuraBySpellID(tracked.spellID)
    if aura and aura.expirationTime and aura.expirationTime > 0 then
        local remaining = math.max(0, aura.expirationTime - GetTime())
        local activeTotal = aura.duration or remaining
        return "item=" .. addon.buff.FormatDuration(itemDuration) .. ", active=" .. addon.buff.FormatDuration(remaining) .. " remaining / " .. addon.buff.FormatDuration(activeTotal) .. " total"
    end

    if itemDuration then
        return "item=" .. addon.buff.FormatDuration(itemDuration) .. ", active aura not detected"
    end
    return "duration unknown (learning aura mapping)"
end

local function AnnounceBuffUse(itemID)
    local itemName = (type(GetItemInfo) == "function" and GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
    PrintMessage("Using buff: " .. tostring(itemName) .. " (" .. tostring(itemID) .. ") [" .. GetBuffTimingText(itemID) .. "]")
end

local function FindItemInBags(itemID)
    if not itemID then
        return nil, nil
    end

    local bagCount = NUM_BAG_SLOTS or 4
    for bag = 0, bagCount do
        local slots = addon.utils.ContainerNumSlots(bag)
        for slot = 1, slots do
            if addon.utils.ContainerItemID(bag, slot) == itemID then
                return bag, slot
            end
        end
    end

    local reagentSlots = addon.utils.ContainerNumSlots(5)
    if reagentSlots and reagentSlots > 0 then
        for slot = 1, reagentSlots do
            if addon.utils.ContainerItemID(5, slot) == itemID then
                return 5, slot
            end
        end
    end

    return nil, nil
end

local function LookupItemInBags(itemID)
    if addon.buff and addon.buff.FindItemInBags then
        return addon.buff.FindItemInBags(itemID)
    end
    return FindItemInBags(itemID)
end

local function WarnMissingBuffItem(itemID, reason)
    local now = GetTime()
    local last = addon.state.buffItemLastMissingWarningAt[itemID] or 0
    if (now - last) < addon.state.buffMissingWarningCooldown then
        return
    end
    addon.state.buffItemLastMissingWarningAt[itemID] = now

    local itemName = (type(GetItemInfo) == "function" and GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
    PrintMessage("Buff due but item missing in inventory: " .. tostring(itemName) .. " (" .. tostring(itemID) .. ").")
end

local function GetEntryExpectedDuration(entry)
    local expectedDuration = type(entry) == "table" and tonumber(entry.expectedDuration) or nil
    if not expectedDuration then
        expectedDuration = type(entry) == "table" and tonumber(entry.refreshSeconds) or nil
    end
    if not expectedDuration and addon.db and type(addon.db.buffAuraByItem) == "table" then
        local entryItemID = type(entry) == "table" and tonumber(entry.itemID) or nil
        local tracked = entryItemID and addon.db.buffAuraByItem[tostring(entryItemID)] or nil
        if type(tracked) == "table" then
            expectedDuration = tonumber(tracked.duration)
        end
    end
    if not expectedDuration and addon.const and type(addon.const.knownBuffItems) == "table" then
        local entryItemID = type(entry) == "table" and tonumber(entry.itemID) or nil
        local known = entryItemID and addon.const.knownBuffItems[entryItemID] or nil
        if type(known) == "table" then
            expectedDuration = tonumber(known.duration)
        end
    end
    return Clamp(expectedDuration or addon.db.refreshSeconds or addon.defaults.refreshSeconds, 30, 3600)
end

local function GetNextDueBuffItem(requireAuraForCast, excludedItemIDs, requestedCategory)
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return nil
    end

    local hasConfiguredBuffItems = false
    for _, entry in ipairs(addon.db.buffItems) do
        if type(entry) == "table" and tonumber(entry.itemID) and tonumber(entry.itemID) > 0 then
            hasConfiguredBuffItems = true
            break
        end
    end
    if not hasConfiguredBuffItems then
        if addon.db and addon.db.debugMode then
            DebugMessage("No configured buff items; skipping due buff selection")
        end
        return nil
    end

    local hadUnavailableDueBuff = false

    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 then
            local itemCategory = GetBuffItemCategory(itemID)
            if type(excludedItemIDs) == "table" and excludedItemIDs[itemID] then
                if addon.db and addon.db.debugMode then
                    DebugMessage("Skipping excluded due buff item: " .. tostring(itemID))
                end
            elseif requestedCategory and itemCategory ~= requestedCategory then
                if addon.db and addon.db.debugMode then
                    DebugMessage("Skipping due buff item for category pass: "
                        .. GetBuffItemLabel(itemID)
                        .. " category=" .. tostring(itemCategory)
                        .. " requested=" .. tostring(requestedCategory))
                end
            else
                local expectedDuration = GetEntryExpectedDuration(entry)
                local isDue, remaining, reason = addon.buff.IsBuffItemDue(itemID, expectedDuration, requireAuraForCast)

                if isDue then
                    local bag, slot = LookupItemInBags(itemID)
                    if bag and slot then
                        DebugMessage("Due buff item found: " .. GetBuffItemLabel(itemID)
                            .. " bag=" .. tostring(bag)
                            .. " slot=" .. tostring(slot)
                            .. " remaining=" .. tostring(remaining)
                            .. " reason=" .. tostring(reason))
                        return itemID, "usable"
                    elseif addon.db and addon.db.debugMode then
                        DebugMessage("Due buff item not in bags: " .. GetBuffItemLabel(itemID)
                            .. " reason=" .. tostring(reason))
                    end
                    hadUnavailableDueBuff = true
                    if requireAuraForCast then
                        WarnMissingBuffItem(itemID, reason)
                    end
                elseif addon.db and addon.db.debugMode then
                    DebugMessage("Buff item not due: " .. GetBuffItemLabel(itemID)
                        .. " remaining=" .. tostring(remaining)
                        .. " reason=" .. tostring(reason))
                end
            end
        end
    end

    if hadUnavailableDueBuff then
        return nil, "due_unavailable"
    end

    return nil
end

local function MaybeUseBuffItems()
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return
    end

    if GetTime() - addon.state.lastBuffCheckTime < addon.state.buffCheckInterval then
        return
    end
    addon.state.lastBuffCheckTime = GetTime()

    if not addon.state or not addon.state.isFishing then
        return
    end

    if InCombatLockdown() or addon.fishing.IsFishingCast() then
        return
    end

    addon.state.buffItemLastReminderCastAnchor = addon.state.buffItemLastReminderCastAnchor or {}

    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 then
            local expectedDuration = GetEntryExpectedDuration(entry)
            local shouldUse = addon.buff.IsBuffItemDue(itemID, expectedDuration, false)

            if shouldUse then
                local bag, slot = LookupItemInBags(itemID)
                if bag and slot then
                    local now = GetTime()
                    local lastReminder = addon.state.buffItemLastReminderAt[itemID] or 0
                    local castAnchor = tonumber(addon.state.fishingStartTime) or 0
                    local remindedForCast = addon.state.buffItemLastReminderCastAnchor[itemID]
                    if castAnchor > 0 and remindedForCast == castAnchor then
                        return
                    end
                    if (now - lastReminder) >= addon.state.buffReminderCooldown then
                        local itemName = (type(GetItemInfo) == "function" and GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
                        PrintMessage("Buff due: use " .. tostring(itemName) .. ". (Drag onto action bar or macro: /use item:" .. tostring(itemID) .. ")")
                        addon.state.buffItemLastReminderAt[itemID] = now
                        addon.state.buffItemLastReminderCastAnchor[itemID] = castAnchor
                        addon.state.buffItemLastUseAt[itemID] = now
                        addon.state.pendingBuffObservation = {
                            itemID = itemID,
                            before = addon.buff.BuildHelpfulAuraSnapshot(),
                            expiresAt = now + 20,
                        }
                    end
                end
                return
            end
        end
    end
end

local function NormalizeBuffConfig()
    if not addon.db then
        return
    end

    if type(addon.db.buffItems) ~= "table" then
        addon.db.buffItems = {}
    end
    if type(addon.db.buffAuraByItem) ~= "table" then
        addon.db.buffAuraByItem = {}
    end

    for i = 1, addon.const.maxBuffSlots do
        local entry = addon.db.buffItems[i]
        if type(entry) ~= "table" then
            entry = {}
        end

        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 then
            entry.itemID = itemID
            if addon.const and type(addon.const.knownBuffItems) == "table" and type(addon.db.buffAuraByItem) == "table" then
                local key = tostring(itemID)
                if type(addon.db.buffAuraByItem[key]) ~= "table" then
                    local known = addon.const.knownBuffItems[itemID]
                    if type(known) == "table" and known.spellID then
                        addon.db.buffAuraByItem[key] = {
                            spellID = known.spellID,
                            duration = tonumber(known.duration) or GetEntryExpectedDuration(entry),
                        }
                    end
                end
            end
        else
            entry.itemID = nil
        end

        entry.expectedDuration = GetEntryExpectedDuration(entry)
        entry.refreshSeconds = nil
        addon.db.buffItems[i] = entry
    end
end

-- Export to addon
addon.buff = addon.buff or {}
addon.buff.GetBuffTimingText = GetBuffTimingText
addon.buff.AnnounceBuffUse = AnnounceBuffUse
addon.buff.FindItemInBags = FindItemInBags
addon.buff.WarnMissingBuffItem = WarnMissingBuffItem
addon.buff.GetNextDueBuffItem = GetNextDueBuffItem
addon.buff.GetBuffItemCategory = GetBuffItemCategory
addon.buff.MaybeUseBuffItems = MaybeUseBuffItems
addon.buff.NormalizeBuffConfig = NormalizeBuffConfig

-- Test hooks
addon._test.GetNextDueBuffItem = function(requireAuraForCast)
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return nil, nil
    end
    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 then
            local expectedDuration = GetEntryExpectedDuration(entry)
            local isDue, remaining, reason = addon.buff.IsBuffItemDue(itemID, expectedDuration, requireAuraForCast)
            if isDue then
                return itemID, reason
            end
        end
    end
    return nil, nil
end
addon._test.SetBuffLastUseTime = function(itemID, time)
    addon.state.buffItemLastUseAt[itemID] = time
end
addon._test.GetBuffLastUseTime = function(itemID)
    return addon.state.buffItemLastUseAt[itemID]
end
