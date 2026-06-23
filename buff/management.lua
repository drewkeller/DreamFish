-- DreamFisher: Buff Item Management

local addon = _G["DreamFisher"]
local Clamp = addon.Clamp
local PrintMessage = addon.PrintMessage
local DebugMessage = addon.DebugMessage

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
    PrintMessage("Using buff: " .. tostring(itemName) .. " [" .. GetBuffTimingText(itemID) .. "]")
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

local function WarnMissingBuffItem(itemID, reason)
    local now = GetTime()
    local last = addon.state.buffItemLastMissingWarningAt[itemID] or 0
    if (now - last) < addon.state.buffMissingWarningCooldown then
        return
    end
    addon.state.buffItemLastMissingWarningAt[itemID] = now

    local itemName = (type(GetItemInfo) == "function" and GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
    PrintMessage("Buff due but item missing in inventory: " .. tostring(itemName) .. ".")
    addon.audio.PlayBagFullCue()
end

local function GetNextDueBuffItem(requireAuraForCast)
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return nil
    end

    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 then
            local refreshSeconds = Clamp(tonumber(entry.refreshSeconds) or addon.db.refreshSeconds or addon.defaults.refreshSeconds, 30, 3600)
            local isDue, remaining, reason = addon.buff.IsBuffItemDue(itemID, refreshSeconds, requireAuraForCast)

            if isDue then
                local bag, slot = FindItemInBags(itemID)
                if bag and slot then
                    DebugMessage("Due buff item found: " .. tostring(itemID)
                        .. " bag=" .. tostring(bag)
                        .. " slot=" .. tostring(slot)
                        .. " remaining=" .. tostring(remaining)
                        .. " reason=" .. tostring(reason))
                    return itemID
                elseif addon.db and addon.db.debugMode then
                    DebugMessage("Due buff item not in bags: " .. tostring(itemID)
                        .. " reason=" .. tostring(reason))
                end
                if requireAuraForCast then
                    WarnMissingBuffItem(itemID, reason)
                end
            elseif addon.db and addon.db.debugMode then
                DebugMessage("Buff item not due: " .. tostring(itemID)
                    .. " remaining=" .. tostring(remaining)
                    .. " reason=" .. tostring(reason))
            end
        end
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

    if InCombatLockdown() or addon.fishing.IsFishingCast() then
        return
    end

    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = tonumber(entry.itemID)
        if itemID and itemID > 0 then
            local refreshSeconds = Clamp(tonumber(entry.refreshSeconds) or addon.db.refreshSeconds or addon.defaults.refreshSeconds, 30, 3600)
            local shouldUse = addon.buff.IsBuffItemDue(itemID, refreshSeconds, false)

            if shouldUse then
                local bag, slot = FindItemInBags(itemID)
                if bag and slot then
                    local now = GetTime()
                    local lastReminder = addon.state.buffItemLastReminderAt[itemID] or 0
                    if (now - lastReminder) >= addon.state.buffReminderCooldown then
                        local itemName = (type(GetItemInfo) == "function" and GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
                        PrintMessage("Buff due: use " .. tostring(itemName) .. ". (Drag onto action bar or macro: /use item:" .. tostring(itemID) .. ")")
                        addon.state.buffItemLastReminderAt[itemID] = now
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
        else
            entry.itemID = nil
        end

        entry.refreshSeconds = Clamp(tonumber(entry.refreshSeconds) or addon.db.refreshSeconds or addon.defaults.refreshSeconds, 30, 3600)
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
            local refreshSeconds = Clamp(tonumber(entry.refreshSeconds) or addon.db.refreshSeconds or addon.defaults.refreshSeconds, 30, 3600)
            local isDue, remaining, reason = addon.buff.IsBuffItemDue(itemID, refreshSeconds, requireAuraForCast)
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
