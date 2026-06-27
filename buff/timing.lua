-- DreamFisher: Buff Timing Logic

local addon = _G["DreamFisher"]
local Clamp = addon.Clamp

local function GetBuffRefreshLead(refreshSeconds)
    local baseLead = Clamp(math.floor(refreshSeconds * 0.1), 3, 15)
    local castAwareLead = addon.const.maxFishingCastSeconds + addon.const.buffPreRefreshSafetySeconds
    return math.max(baseLead, castAwareLead)
end

local function IsBuffItemDue(itemID, refreshSeconds, requireAuraForCast)
    local lastUsed = addon.state.buffItemLastUseAt[itemID] or 0
    local remaining = addon.buff.GetTrackedBuffRemaining(itemID)
    if remaining ~= nil then
        local lead = GetBuffRefreshLead(refreshSeconds)
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
            if lastUsed > 0 then
                local elapsedTrackedFallback = GetTime() - lastUsed
                if elapsedTrackedFallback < refreshSeconds then
                    return false, nil, "tracked_missing_recent_use"
                end
            end
            return true, 0, "tracked_missing_aura"
        end
    end

    if requireAuraForCast and not hasTrackedAura then
        if lastUsed <= 0 then
            return true, nil, "untracked_no_history_due_cast"
        end
    end

    local elapsed = GetTime() - lastUsed
    return elapsed >= refreshSeconds, nil, "timer_elapsed=" .. string.format("%.1f", elapsed)
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
