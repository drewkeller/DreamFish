-- DreamFisher: Buff Aura Tracking

local addon = _G["DreamFisher"]
local PrintMessage = addon.PrintMessage

local function GetAuraBySpellID(spellID)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    end

    if AuraUtil and AuraUtil.FindAuraBySpellID then
        local _, _, _, _, duration, expirationTime, _, _, _, auraSpellID = AuraUtil.FindAuraBySpellID(spellID, "player", "HELPFUL")
        if duration or expirationTime then
            return {
                spellId = auraSpellID or spellID,
                duration = duration,
                expirationTime = expirationTime,
            }
        end
    end

    return nil
end

local function BuildHelpfulAuraSnapshot()
    local snapshot = {}

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local index = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
            if not aura then
                break
            end
            if aura.spellId and aura.duration and aura.duration > 0 then
                snapshot[aura.spellId] = {
                    duration = aura.duration,
                    expirationTime = aura.expirationTime,
                }
            end
            index = index + 1
        end
    end

    return snapshot
end

local function GetConfiguredExpectedDuration(itemID)
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return nil
    end

    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return nil
    end

    for _, entry in ipairs(addon.db.buffItems) do
        local entryItemID = type(entry) == "table" and tonumber(entry.itemID) or nil
        if entryItemID and entryItemID == numeric then
            local expectedDuration = type(entry) == "table" and tonumber(entry.expectedDuration) or nil
            if not expectedDuration then
                expectedDuration = type(entry) == "table" and tonumber(entry.refreshSeconds) or nil
            end
            return expectedDuration
        end
    end

    return nil
end

local function UpdatePendingBuffObservation()
    if not addon.state.pendingBuffObservation or not addon.db then
        return
    end

    if type(addon.db.buffItems) ~= "table" then
        addon.state.pendingBuffObservation = nil
        return
    end

    local hasConfiguredBuffItems = false
    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
        if itemID and itemID > 0 then
            hasConfiguredBuffItems = true
            break
        end
    end
    if not hasConfiguredBuffItems then
        addon.state.pendingBuffObservation = nil
        return
    end

    if GetTime() > addon.state.pendingBuffObservation.expiresAt then
        addon.state.pendingBuffObservation = nil
        return
    end

    local before = addon.state.pendingBuffObservation.before or {}
    local current = BuildHelpfulAuraSnapshot()
    local bestSpellID = nil
    local bestDuration = 0
    local bestExpirationTime = nil

    for spellID, aura in pairs(current) do
        local previous = before[spellID]
        local isNewAura = previous == nil
        local refreshedAura = previous and aura.expirationTime and previous.expirationTime and aura.expirationTime > previous.expirationTime + 0.5
        if (isNewAura or refreshedAura) and aura.duration and aura.duration > bestDuration then
            bestSpellID = spellID
            bestDuration = aura.duration
            bestExpirationTime = aura.expirationTime
        end
    end

    if bestSpellID then
        local itemID = tonumber(addon.state.pendingBuffObservation.itemID)
        local key = tostring(itemID)
        local existingTracked = addon.db.buffAuraByItem[key]
        local existingDuration = type(existingTracked) == "table" and tonumber(existingTracked.duration) or 0
        local known = addon.const
            and type(addon.const.knownBuffItems) == "table"
            and addon.const.knownBuffItems[itemID]
            or nil
        local knownDuration = type(known) == "table" and tonumber(known.duration) or 0

        local category = nil
        if type(known) == "table" and type(known.category) == "string" and known.category ~= "" then
            category = known.category
        elseif addon.buff and type(addon.buff.GetBuffItemCategory) == "function" then
            category = addon.buff.GetBuffItemCategory(itemID)
        end

        local configuredExpectedDuration = tonumber(GetConfiguredExpectedDuration(itemID)) or 0
        local floorDuration = math.max(existingDuration or 0, knownDuration or 0)
        if category == "food_drink" then
            local foodDrinkExpected = math.max(configuredExpectedDuration, knownDuration or 0, existingDuration or 0)
            if foodDrinkExpected > 0 then
                floorDuration = math.max(floorDuration, foodDrinkExpected * 0.5)
            end
        end

        -- Do not overwrite a known/learned long-duration mapping with a shorter
        -- transient aura that appears during observation.
        if floorDuration > 0 and bestDuration < floorDuration then
            if category == "food_drink" and bestDuration > 0 and addon.state then
                addon.state.buffItemTransientUntil = addon.state.buffItemTransientUntil or {}
                local now = GetTime()
                local transientUntil = (bestExpirationTime and bestExpirationTime > now)
                    and bestExpirationTime
                    or (now + bestDuration)
                addon.state.buffItemTransientUntil[itemID] = transientUntil
            end
            addon.state.pendingBuffObservation = nil
            return
        end

        local auraName = (type(GetSpellInfo) == "function" and GetSpellInfo(bestSpellID)) or nil
        addon.db.buffAuraByItem[key] = {
            spellID = bestSpellID,
            duration = bestDuration,
        }
        if addon.state and addon.state.buffItemTransientUntil then
            addon.state.buffItemTransientUntil[itemID] = nil
        end
        PrintMessage("Buff tracked for item:" .. tostring(itemID)
            .. " [spellID=" .. tostring(bestSpellID)
            .. (auraName and (", aura=" .. tostring(auraName)) or "")
            .. ", item=" .. addon.buff.FormatDuration(bestDuration)
            .. ", active=" .. addon.buff.FormatDuration(bestDuration) .. " total]")
        addon.state.pendingBuffObservation = nil
    end
end

local function GetTrackedBuffRemaining(itemID)
    local numericItemID = tonumber(itemID)
    if not numericItemID or numericItemID <= 0 then
        return nil
    end

    local knownSpellID = nil
    local knownDuration = nil
    if addon.const and type(addon.const.knownBuffItems) == "table" then
        local known = addon.const.knownBuffItems[numericItemID]
        if type(known) == "table" and known.spellID then
            knownSpellID = tonumber(known.spellID)
            knownDuration = tonumber(known.duration)
        end
    end

    local trackedSpellID = nil
    local trackedDuration = nil
    if addon.db and type(addon.db.buffAuraByItem) == "table" then
        local tracked = addon.db.buffAuraByItem[tostring(numericItemID)]
        if type(tracked) == "table" and tracked.spellID then
            trackedSpellID = tonumber(tracked.spellID)
            trackedDuration = tonumber(tracked.duration)
        end
    end

    local spellIDsToCheck = {}
    if knownSpellID and knownSpellID > 0 then
        table.insert(spellIDsToCheck, knownSpellID)
    end
    if trackedSpellID and trackedSpellID > 0 and trackedSpellID ~= knownSpellID then
        table.insert(spellIDsToCheck, trackedSpellID)
    end

    for _, spellID in ipairs(spellIDsToCheck) do
        local aura = GetAuraBySpellID(spellID)
        if aura and aura.expirationTime and aura.expirationTime > 0 then
            if spellID == knownSpellID
                and trackedSpellID
                and trackedSpellID > 0
                and trackedSpellID ~= knownSpellID
                and addon.db
                and type(addon.db.buffAuraByItem) == "table" then
                addon.db.buffAuraByItem[tostring(numericItemID)] = {
                    spellID = knownSpellID,
                    duration = knownDuration or trackedDuration or (tonumber(aura.duration) or 0),
                }
            end
            return math.max(0, aura.expirationTime - GetTime())
        end
    end

    return nil
end

local function FormatDuration(seconds)
    local n = tonumber(seconds)
    if not n or n < 0 then
        return "unknown"
    end
    local rounded = math.floor(n + 0.5)
    local minutes = math.floor(rounded / 60)
    local secs = rounded % 60
    if minutes > 0 then
        return tostring(minutes) .. "m " .. tostring(secs) .. "s"
    end
    return tostring(secs) .. "s"
end

-- Export to addon
addon.buff = addon.buff or {}
addon.buff.GetAuraBySpellID = GetAuraBySpellID
addon.buff.BuildHelpfulAuraSnapshot = BuildHelpfulAuraSnapshot
addon.buff.UpdatePendingBuffObservation = UpdatePendingBuffObservation
addon.buff.GetTrackedBuffRemaining = GetTrackedBuffRemaining
addon.buff.FormatDuration = FormatDuration

-- Test hooks
addon._test.GetTrackedBuffRemaining = GetTrackedBuffRemaining
