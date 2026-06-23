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

local function UpdatePendingBuffObservation()
    if not addon.state.pendingBuffObservation or not addon.db then
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

    for spellID, aura in pairs(current) do
        local previous = before[spellID]
        local isNewAura = previous == nil
        local refreshedAura = previous and aura.expirationTime and previous.expirationTime and aura.expirationTime > previous.expirationTime + 0.5
        if (isNewAura or refreshedAura) and aura.duration and aura.duration > bestDuration then
            bestSpellID = spellID
            bestDuration = aura.duration
        end
    end

    if bestSpellID then
        addon.db.buffAuraByItem[tostring(addon.state.pendingBuffObservation.itemID)] = {
            spellID = bestSpellID,
            duration = bestDuration,
        }
        PrintMessage("Buff tracked for item:" .. tostring(addon.state.pendingBuffObservation.itemID)
            .. " [item=" .. addon.buff.FormatDuration(bestDuration)
            .. ", active=" .. addon.buff.FormatDuration(bestDuration) .. " total]")
        addon.state.pendingBuffObservation = nil
    end
end

local function GetTrackedBuffRemaining(itemID)
    if not addon.db or type(addon.db.buffAuraByItem) ~= "table" then
        return nil
    end

    local tracked = addon.db.buffAuraByItem[tostring(itemID)]
    if type(tracked) ~= "table" or not tracked.spellID then
        return nil
    end

    local aura = GetAuraBySpellID(tracked.spellID)
    if not aura then
        return 0
    end
    if not aura.expirationTime or aura.expirationTime <= 0 then
        return nil
    end

    return math.max(0, aura.expirationTime - GetTime())
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
