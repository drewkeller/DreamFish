local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local Fishing = DreamFish:GetModule("Fishing")

function Fishing:GetAuraBySpellID(spellID)
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

function Fishing:BuildHelpfulAuraSnapshot()
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

function Fishing:UpdatePendingBuffObservation()
    if not self.state.pendingBuffObservation or not self.db then
        return
    end

    if type(self.db.global.buffItems) ~= "table" then
        self.state.pendingBuffObservation = nil
        return
    end

    local hasConfiguredBuffItems = false
    for _, entry in ipairs(self.db.global.buffItems) do
        local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
        if itemID and itemID > 0 and not (type(entry) == "table" and entry.enabled == false) then
            hasConfiguredBuffItems = true
            break
        end
    end
    if not hasConfiguredBuffItems then
        self.state.pendingBuffObservation = nil
        return
    end

    if GetTime() > self.state.pendingBuffObservation.expiresAt then
        local unresolvedItemID = tonumber(self.state.pendingBuffObservation.itemID)
        if unresolvedItemID and unresolvedItemID > 0 and self.state then
            self.state.buffUnknownDurationSuppressed = self.state.buffUnknownDurationSuppressed or {}
            self.state.buffUnknownDurationSuppressed[unresolvedItemID] = true
        end
        self.state.pendingBuffObservation = nil
        return
    end

    local before = self.state.pendingBuffObservation.before or {}
    local current = self:BuildHelpfulAuraSnapshot()
    local pendingItemID = tonumber(self.state.pendingBuffObservation.itemID)
    local pendingKnown = pendingItemID
        and ns.Fishing.const
        and type(ns.Fishing.const.knownBuffItems) == "table"
        and ns.Fishing.const.knownBuffItems[pendingItemID]
        or nil
    local pendingKnownSpellID = type(pendingKnown) == "table" and tonumber(pendingKnown.spellID) or nil
    local bestSpellID = nil
    local bestDuration = 0
    local bestExpirationTime = nil

    if pendingKnownSpellID and current[pendingKnownSpellID] then
        local knownAura = current[pendingKnownSpellID]
        local previousKnownAura = before[pendingKnownSpellID]
        local isNewKnownAura = previousKnownAura == nil
        local refreshedKnownAura = previousKnownAura
            and knownAura.expirationTime
            and previousKnownAura.expirationTime
            and knownAura.expirationTime > previousKnownAura.expirationTime + 0.5
        if (isNewKnownAura or refreshedKnownAura) and knownAura.duration then
            bestSpellID = pendingKnownSpellID
            bestDuration = knownAura.duration
            bestExpirationTime = knownAura.expirationTime
        end
    end

    if not bestSpellID then
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
    end

    if bestSpellID then
        local itemID = pendingItemID
        local key = tostring(itemID)
        local existingTracked = self.db.global.buffAuraByItem[key]
        local existingDuration = type(existingTracked) == "table" and tonumber(existingTracked.duration) or 0
        local known = ns.Fishing.const
            and type(ns.Fishing.const.knownBuffItems) == "table"
            and ns.Fishing.const.knownBuffItems[itemID]
            or nil
        local knownDuration = type(known) == "table" and tonumber(known.duration) or 0

        if pendingKnownSpellID and bestSpellID ~= pendingKnownSpellID then
            self.state.pendingBuffObservation = nil
            return
        end

        local category = nil
        if type(known) == "table" and type(known.category) == "string" and known.category ~= "" then
            category = known.category
        elseif DreamFish.buff and type(DreamFish.buff.GetBuffItemCategory) == "function" then
            category = DreamFish.buff.GetBuffItemCategory(itemID)
        end

        local floorDuration = math.max(existingDuration or 0, knownDuration or 0)
        if category == "food_drink" then
            local foodDrinkExpected = math.max(knownDuration or 0, existingDuration or 0)
            if foodDrinkExpected > 0 then
                floorDuration = math.max(floorDuration, foodDrinkExpected * 0.5)
            end
        end

        if category == "food_drink" and floorDuration <= 0 and bestDuration > 0 and bestDuration < 60 then
            if self.state then
                self.state.buffItemTransientUntil = self.state.buffItemTransientUntil or {}
                local now = GetTime()
                local transientUntil = (bestExpirationTime and bestExpirationTime > now)
                    and bestExpirationTime
                    or (now + bestDuration)
                self.state.buffItemTransientUntil[itemID] = transientUntil
            end
            self.state.pendingBuffObservation = nil
            return
        end

        -- Do not overwrite a known/learned long-duration mapping with a shorter
        -- transient aura that appears during observation.
        if floorDuration > 0 and bestDuration < floorDuration then
            if category == "food_drink" and bestDuration > 0 and self.state then
                self.state.buffItemTransientUntil = self.state.buffItemTransientUntil or {}
                local now = GetTime()
                local transientUntil = (bestExpirationTime and bestExpirationTime > now)
                    and bestExpirationTime
                    or (now + bestDuration)
                self.state.buffItemTransientUntil[itemID] = transientUntil
            end
            self.state.pendingBuffObservation = nil
            return
        end

        local auraName = (type(GetSpellInfo) == "function" and GetSpellInfo(bestSpellID)) or nil
        self.db.global.buffAuraByItem[key] = {
            spellID = bestSpellID,
            duration = bestDuration,
        }
        if self.state and self.state.buffUnknownDurationSuppressed then
            self.state.buffUnknownDurationSuppressed[itemID] = nil
        end
        if self.state and self.state.buffItemTransientUntil then
            self.state.buffItemTransientUntil[itemID] = nil
        end
        DreamFish:Print("Buff tracked for item:" .. tostring(itemID)
            .. " [spellID=" .. tostring(bestSpellID)
            .. (auraName and (", aura=" .. tostring(auraName)) or "")
            .. ", item=" .. DreamFish.buff.FormatDuration(bestDuration)
            .. ", active=" .. DreamFish.buff.FormatDuration(bestDuration) .. " total]")
        self.state.pendingBuffObservation = nil
    end
end

function Fishing:GetTrackedBuffRemaining(itemID)
    local numericItemID = tonumber(itemID)
    if not numericItemID or numericItemID <= 0 then
        return nil
    end

    local knownSpellID = nil
    local knownDuration = nil
    if ns.Fishing.const and type(ns.Fishing.const.knownBuffItems) == "table" then
        local known = ns.Fishing.const.knownBuffItems[numericItemID]
        if type(known) == "table" and known.spellID then
            knownSpellID = tonumber(known.spellID)
            knownDuration = tonumber(known.duration)
        end
    end

    local trackedSpellID = nil
    local trackedDuration = nil
    if Fishing:GetProfileDB() and type(Fishing:GetProfileDB().buffAuraByItem) == "table" then
        local tracked = Fishing:GetProfileDB().buffAuraByItem[tostring(numericItemID)]
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
        local aura = self:GetAuraBySpellID(spellID)
        if aura and aura.expirationTime and aura.expirationTime > 0 then
            if spellID == knownSpellID
                and trackedSpellID
                and trackedSpellID > 0
                and trackedSpellID ~= knownSpellID
                and Fishing.db
                and type(Fishing:GetProfileDB().buffAuraByItem) == "table" then
                Fishing:GetProfileDB().buffAuraByItem[tostring(numericItemID)] = {
                    spellID = knownSpellID,
                    duration = knownDuration or trackedDuration or (tonumber(aura.duration) or 0),
                }
            end
            return math.max(0, aura.expirationTime - GetTime())
        end
    end

    return nil
end

ns.GetAuraBySpellID = function(spellID)
    return Fishing:GetAuraBySpellID(spellID)
end