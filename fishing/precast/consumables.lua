local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

Fishing:RegisterTraceSource("buffs")

local globalDB, profileDB, charDB
local state
local function Initialize()
    globalDB = ns.FishingDB.global
    profileDB = ns.FishingDB.profile
    charDB = ns.FishingDB.char
    state = ns.fishing.state
end
ns.FishingInitializers = ns.FishingInitializers or {}
table.insert(ns.FishingInitializers, Initialize)

local function Trace(msg)
    Fishing:Trace("buffs", msg)
end

local function Item(itemID, category)
    if category then
        return DreamFish:GetDebugItemLabel(itemID) .. " (" .. tostring(category) .. ")"
    end
    return DreamFish:GetDebugItemLabel(itemID)
end

local function LastUseString(lastUse, duration)
    if not lastUse or lastUse <= 0 then
        return "never used"
    end
    local now = (type(GetTime) == "function") and GetTime() or 0
    local elapsed = now - lastUse
    if duration and duration > 0 then
        return string.format("last used %.1f seconds ago (duration %.1f seconds)", elapsed, duration)
    end
    return string.format("last used %.1f seconds ago", elapsed)
end

local function WarnMissingProfessionFishingPoleForLure()
    local now = (type(GetTime) == "function") and GetTime() or 0
    local cooldown = tonumber(state.buffMissingWarningCooldown) or 8
    local last = tonumber(state.lureMissingPoleWarningAt) or 0
    if (now - last) < cooldown then
        return
    end
    state.lureMissingPoleWarningAt = now

    local warningText = "Cannot apply lure: no fishing pole equipped in profession slot."
    DreamFish:Alert(warningText)
    DreamFish:Print(warningText)
end

local function GetNow()
    return (type(GetTime) == "function") and GetTime() or 0
end

local function GetKnownBuff(itemID)
    local known = ns.fishing.const and ns.fishing.const.knownBuffItems
    return type(known) == "table" and known[tonumber(itemID)] or nil
end

local function GetTrackedBuff(itemID)
    if not globalDB or type(globalDB.buffAuraByItem) ~= "table" then
        return nil
    end
    return globalDB.buffAuraByItem[tostring(tonumber(itemID))]
end

local function GetConfiguredCategory(entry, itemID)
    if type(entry.category) == "string" and entry.category ~= "" then
        return string.lower(entry.category)
    end
    local known = GetKnownBuff(itemID)
    if type(known) == "table" and type(known.category) == "string" then
        return string.lower(known.category)
    end
    return "other_consumable"
end

local function IsExcluded(itemID, entry)
    if entry.excluded == true or entry.exclude == true then
        return true
    end
    if not itemID then
        return false
    end
    local excluded = state and state.buffExcludedItems
    return type(excluded) == "table" and (excluded[itemID] == true or excluded[tostring(itemID)] == true)
end

local function GetKnownSpellAndDuration(itemID)
    local known = GetKnownBuff(itemID)
    local tracked = GetTrackedBuff(itemID)
    local spellID = type(known) == "table" and tonumber(known.spellID) or nil
    local duration = type(known) == "table" and tonumber(known.duration) or nil
    if not spellID and type(tracked) == "table" then
        spellID = tonumber(tracked.spellID)
    end
    if not duration and type(tracked) == "table" then
        duration = tonumber(tracked.duration)
    end
    return spellID, duration
end

local function IsDue(itemID, category, now)
    state.buffItemLastUseAt = state.buffItemLastUseAt or {}
    state.buffItemTransientUntil = state.buffItemTransientUntil or {}

    if category == "fooddrink" and (tonumber(state.buffItemTransientUntil[itemID]) or 0) > now then
        return false, "transient_buff_active"
    end
    local lastUse = tonumber(state.buffItemLastUseAt[itemID])
    if lastUse and now - lastUse < 5 then
        return false, "recently_used" .. LastUseString(lastUse, nil)
    end
    local pending = state.pendingBuffObservation
    if type(pending) == "table" and tonumber(pending.itemID) == itemID then
        return false, "pending_observation" .. LastUseString(lastUse, nil)
    end
    if state.buffUnknownDurationSuppressed and (state.buffUnknownDurationSuppressed[itemID]
        or state.buffUnknownDurationSuppressed[tostring(itemID)]) then
        return false, "unknown_duration_suppressed"
    end

    local remaining = type(Fishing.GetTrackedBuffRemaining) == "function"
        and Fishing:GetTrackedBuffRemaining(itemID)
        or nil
    local spellID, knownDuration = GetKnownSpellAndDuration(itemID)
    local refreshLead = ns.fishing.const.maxFishingCastSeconds + ns.fishing.const.buffPreRefreshSafetySeconds
    if knownDuration and knownDuration > 0 then
        refreshLead = math.max(refreshLead, math.min(15, math.max(3, knownDuration * 0.10)))
    end
    if remaining ~= nil then
        return remaining <= refreshLead
    end

    local aura = spellID and type(Fishing.GetAuraBySpellID) == "function"
        and Fishing:GetAuraBySpellID(spellID)
        or nil
    if aura and knownDuration and knownDuration > 0 then
        if not lastUse or now - lastUse >= knownDuration then
            return true, "known_duration_aura_expired" .. LastUseString(lastUse, knownDuration)
        else
            return false, "known_duration_aura_active" .. LastUseString(lastUse, knownDuration)
        end
    end
    if spellID and not aura and knownDuration and knownDuration > 0 and lastUse then
        if now - lastUse >= knownDuration then
            return true, "known_duration_aura_missing" .. LastUseString(lastUse, knownDuration)
        else
            return false, "known_duration_aura_missing" .. LastUseString(lastUse, knownDuration)
        end
    end
    return true
end

local function RecordBuffUse(itemID)
    local now = GetNow()
    state.buffItemLastUseAt = state.buffItemLastUseAt or {}
    state.buffItemLastUseAt[itemID] = now
    if type(Fishing.BuildHelpfulAuraSnapshot) == "function" then
        state.pendingBuffObservation = {
            itemID = itemID,
            before = Fishing:BuildHelpfulAuraSnapshot(),
            expiresAt = now + 20,
        }
    end
end

local function GetConsumableUseDecision()
    local decision = { shouldApply = false }
    if type(Fishing.UpdatePendingBuffObservation) == "function" then
        Fishing:UpdatePendingBuffObservation()
    end
    local configured = charDB and charDB.buffs
    if type(configured) ~= "table" then
        return decision
    end

    local categoryOrder = { "fooddrink", "lure", "bait", "bobber", "other_consumable" }
    for _, category in ipairs(categoryOrder) do
        local items = configured[category]
        if type(items) == "table" then
            for _, entry in ipairs(items) do
                if type(entry) == "table" and entry.enabled ~= false and not IsExcluded(tonumber(entry.itemID), entry) then
                    local itemID = tonumber(entry.itemID)
                    --Trace("Checking due consumable: " .. Item(itemID) .. " (" .. tostring(category) .. ")")
                    if not itemID or itemID <= 0 then
                        --Trace("Skipping due consumable: invalid itemID")
                    elseif not DreamFish:FindItemInBags(itemID) then
                        Trace("Skipping due consumable: not found in bags " .. Item(itemID, category))
                    elseif not DreamFish:IsCooldownReady(itemID) then
                        Trace("Skipping due consumable: cooldown not ready " .. Item(itemID) .. " " .. DreamFish:GetDebugCooldownText(itemID))
                    else
                        local isDue, reason = IsDue(itemID, category, GetNow())
                        if not isDue then
                            Trace("Skipping due consumable: not due " .. Item(itemID, category) .. " (" .. tostring(reason) .. ")")
                        elseif category == "lure" then
                            local poleID = type(ns.precast.GetEquippedProfessionItemID) == "function"
                                and ns.precast.GetEquippedProfessionItemID()
                                or nil
                            if not poleID or poleID <= 0 then
                                WarnMissingProfessionFishingPoleForLure()
                            else
                                RecordBuffUse(itemID)
                                Trace("Lure is due for use: " .. Item(itemID))
                                return { shouldApply = true, itemID = itemID, category = category }
                            end
                        else
                            Trace("Consumable is due for use: " .. Item(itemID, category))
                            RecordBuffUse(itemID)
                            return { shouldApply = true, itemID = itemID, category = category }
                        end
                    end
                end
            end
        end
    end
    return decision
end

ns.precast.GetConsumableUseDecision = GetConsumableUseDecision

