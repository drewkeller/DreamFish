-- DreamFisher: Buff Timing Logic

local addon = _G["DreamFisher"]
local Clamp = addon.Clamp

local function GetBuffItemCategoryForDue(itemID)
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

    if addon.buff and type(addon.buff.GetBuffItemCategory) == "function" then
        return addon.buff.GetBuffItemCategory(numeric)
    end

    return "other_consumable"
end

local function GetBuffRefreshLead(refreshSeconds)
    local castAwareLead = addon.const.maxFishingCastSeconds + addon.const.buffPreRefreshSafetySeconds
    local numeric = tonumber(refreshSeconds)
    if not numeric or numeric <= 0 then
        return castAwareLead
    end
    local baseLead = Clamp(math.floor(numeric * 0.1), 3, 15)
    return math.max(baseLead, castAwareLead)
end

local function IsBuffItemDue(itemID, knownDuration, requireAuraForCast)
    local itemCategory = GetBuffItemCategoryForDue(itemID)
    if itemCategory == "food_drink" and addon.state and type(addon.state.buffItemTransientUntil) == "table" then
        local transientUntil = tonumber(addon.state.buffItemTransientUntil[tonumber(itemID)]) or 0
        if transientUntil > GetTime() then
            return false, (transientUntil - GetTime()), "food_drink_transient_active"
        end
    end

    local lastUsed = addon.state.buffItemLastUseAt[itemID] or 0
    local remaining = addon.buff.GetTrackedBuffRemaining(itemID)
    if remaining ~= nil then
        local lead = GetBuffRefreshLead(knownDuration)
        return remaining <= lead, remaining, "tracked_remaining"
    end

    local hasTrackedAura = false
    local trackedSpellID = nil
    if addon.db and type(addon.db.buffAuraByItem) == "table" then
        local tracked = addon.db.buffAuraByItem[tostring(itemID)]
        if type(tracked) == "table" and tracked.spellID then
            hasTrackedAura = true
            trackedSpellID = tracked.spellID
        end
    end

    if (not hasTrackedAura) and addon.const and type(addon.const.knownBuffItems) == "table" then
        local known = addon.const.knownBuffItems[tonumber(itemID)]
        if type(known) == "table" and known.spellID then
            hasTrackedAura = true
            trackedSpellID = known.spellID
        end
    end

    if hasTrackedAura and trackedSpellID then
        local aura = addon.buff.GetAuraBySpellID(trackedSpellID)
        if not aura then
            if lastUsed > 0 and tonumber(knownDuration) and tonumber(knownDuration) > 0 then
                local elapsedTrackedFallback = GetTime() - lastUsed
                if elapsedTrackedFallback < tonumber(knownDuration) then
                    return false, nil, "tracked_missing_recent_use"
                end
            end
            return true, 0, "tracked_missing_aura"
        end
    end

    if addon.state and type(addon.state.buffUnknownDurationSuppressed) == "table" and addon.state.buffUnknownDurationSuppressed[itemID] then
        return false, nil, "unknown_duration_suppressed"
    end

    if not hasTrackedAura then
        if requireAuraForCast then
            local pending = addon.state and addon.state.pendingBuffObservation or nil
            if type(pending) == "table"
                and tonumber(pending.itemID) == tonumber(itemID)
                and tonumber(pending.expiresAt)
                and tonumber(pending.expiresAt) > GetTime() then
                return false, nil, "unknown_duration_observing"
            end

            if lastUsed <= 0 then
                return true, nil, "untracked_no_history_due_cast"
            end

            return true, nil, "unknown_duration_probe"
        end

        return false, nil, "unknown_duration_no_reapply"
    end

    local numericKnownDuration = tonumber(knownDuration)
    if not numericKnownDuration or numericKnownDuration <= 0 then
        return false, nil, "known_aura_unknown_duration"
    end

    local elapsed = GetTime() - lastUsed
    return elapsed >= numericKnownDuration, nil, "timer_elapsed=" .. string.format("%.1f", elapsed)
end

-- Export to addon
addon.buff = addon.buff or {}
addon.buff.GetBuffRefreshLead = GetBuffRefreshLead
addon.buff.IsBuffItemDue = IsBuffItemDue

-- Test hooks
addon._test.GetBuffRefreshLead = function(refreshSeconds)
    return GetBuffRefreshLead(refreshSeconds)
end
addon._test.IsBuffItemDue = IsBuffItemDue
