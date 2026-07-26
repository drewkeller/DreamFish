-- DreamFish: Buff Timing Logic

local addon = _G["DreamFish"]
local Clamp = addon.Clamp

local DebugBuffMessage = addon.buff.DebugBuffMessage or addon.DebugMessage

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
    local itemCategory = addon.buff.GetBuffItemCategory(itemID)
    if itemCategory == "food_drink" and addon.state and type(addon.state.buffItemTransientUntil) == "table" then
        local transientUntil = tonumber(addon.state.buffItemTransientUntil[tonumber(itemID)]) or 0
        if transientUntil > GetTime() then
            return false, (transientUntil - GetTime()), "food_drink_transient_active"
        end
    end

    local spellID = addon.buff.GetBuffItemSpellID(itemID)
    local aura = spellID and addon.buff.GetAuraBySpellID(spellID) or nil
    local itemLastUsed = addon.state.buffItemLastUseAt[itemID] or 0
    local auraLastAppliedByItem = addon.state.buffAuraLastAppliedAt[itemID] or 0
    local auraLastAppliedBySpell = (spellID and addon.state.buffAuraLastAppliedAt[spellID]) or 0
    local auraLastApplied = math.max(tonumber(auraLastAppliedByItem) or 0, tonumber(auraLastAppliedBySpell) or 0)
    local remaining = addon.buff.GetTrackedBuffRemaining(itemID)
    local elapsed = GetTime() - itemLastUsed
    if itemLastUsed > 0 and elapsed <= 5 then
        addon.buff.DebugBuffMessage("Buff item " .. tostring(itemID) .. " last used " .. tostring(elapsed) .. " ago; known duration=" .. tostring(knownDuration) .. "; remaining=" .. tostring(remaining))
        return false, remaining, "too_soon_to_use"
    end
    if auraLastApplied > 0 and (GetTime() - auraLastApplied) <= 5 then
        addon.buff.DebugBuffMessage("Buff item " .. tostring(itemID) .. " aura last applied " .. tostring(GetTime() - auraLastApplied) .. " ago; known duration=" .. tostring(knownDuration) .. "; remaining=" .. tostring(remaining))
        return false, remaining, "too_soon_to_use_aura"
    end
    if remaining ~= nil then
        if itemLastUsed == 0 then
            local numericKnownDuration = tonumber(knownDuration)
            if not numericKnownDuration then
                return false, remaining, "tracked_remaining_unknown_duration"
            end
            local assumedElapsed = numericKnownDuration - remaining
            itemLastUsed = GetTime() - assumedElapsed
            addon.buff.DebugBuffMessage("Buff item " .. tostring(itemID) .. " assumed last used " .. tostring(assumedElapsed) .. " ago; remaining=" .. tostring(remaining))
        else
            addon.buff.DebugBuffMessage("Buff item " .. tostring(itemID) .. " last used " .. tostring(elapsed) .. " ago; remaining=" .. tostring(remaining))
        end
        local lead = GetBuffRefreshLead(knownDuration)
        return remaining <= lead, remaining, "tracked_remaining"
    end

    if spellID then
        if not aura then
            if itemLastUsed > 0 and tonumber(knownDuration) and tonumber(knownDuration) > 0 then
                local elapsedTrackedFallback = GetTime() - itemLastUsed
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

    if not aura then
        if requireAuraForCast then
            local pending = addon.state and addon.state.pendingBuffObservation or nil
            if type(pending) == "table"
                and tonumber(pending.itemID) == tonumber(itemID)
                and tonumber(pending.expiresAt)
                and tonumber(pending.expiresAt) > GetTime() then
                return false, nil, "unknown_duration_observing"
            end

            if itemLastUsed <= 0 then
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

    local elapsed = GetTime() - itemLastUsed
    return elapsed >= numericKnownDuration, nil, "timer_elapsed=" .. string.format("%.1f", elapsed)
end

StartImmediateFoodDrinkTransient = function(itemID, now)
    local numericItemID = tonumber(itemID)
    if not numericItemID or numericItemID <= 0 or not addon.state then
        return
    end

    local category = nil
    local known = addon.const
        and type(addon.const.knownBuffItems) == "table"
        and addon.const.knownBuffItems[numericItemID]
        or nil
    if type(known) == "table" and type(known.category) == "string" and known.category ~= "" then
        category = known.category
    elseif addon.buff and type(addon.buff.GetBuffItemCategory) == "function" then
        category = addon.buff.GetBuffItemCategory(numericItemID)
    end

    if category ~= "food_drink" then
        return
    end

    addon.state.buffItemTransientUntil = addon.state.buffItemTransientUntil or {}
    addon.state.buffItemTransientUntil[numericItemID] = (tonumber(now) or 0) + 10
end

-- Export to addon
addon.buff = addon.buff or {}
addon.buff.GetBuffRefreshLead = GetBuffRefreshLead
addon.buff.IsBuffItemDue = IsBuffItemDue
addon.buff.StartImmediateFoodDrinkTransient = StartImmediateFoodDrinkTransient

-- Test hooks
addon._test.GetBuffRefreshLead = function(refreshSeconds)
    return GetBuffRefreshLead(refreshSeconds)
end
addon._test.IsBuffItemDue = IsBuffItemDue
