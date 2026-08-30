local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing
local state = ns.Fishing.state

Fishing:RegisterTraceSource("buffs")
state.buffItemLastUseAt = state.buffItemLastUseAt or {}
state.buffItemTransientUntil = state.buffItemTransientUntil or {}

local globalDB, profileDB, charDB
ns.moduleInitializers["Fishing"].RegisterInitializer(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

local function Trace(msg)
    Fishing:Trace("buffs", msg)
end

local function Item(itemID, category)
    if category then
        return ns.Utils.GetDebugItemLabel(itemID) .. " (" .. tostring(category) .. ")"
    end
    return ns.Utils.GetDebugItemLabel(itemID)
end

local function LastUseString(lastUse, duration)
    if not lastUse or lastUse <= 0 then
        return "never used"
    end
    local now = (type(GetTime) == "function") and GetTime() or 0
    local elapsed = now - lastUse
    if duration and duration > 0 then
        return string.format("last used %.1f seconds ago (%.1f seconds remaining)", elapsed, math.max(0, duration - elapsed))
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
    ns.Utils.Alert(warningText)
    ns.Utils.Print(warningText)
end

local function GetNow()
    return (type(GetTime) == "function") and GetTime() or 0
end

local function GetKnownBuff(itemID)
    local known = ns.Fishing.const and ns.Fishing.const.knownBuffItems
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

local function IsFishingLureApplied()
    if not C_TooltipInfo then
        return false
    end

    local function TooltipHasLure(tooltipData)
        if type(tooltipData) ~= "table" or type(tooltipData.lines) ~= "table" then
            return false
        end
        for _, line in ipairs(tooltipData.lines) do
            if type(line) == "table" then
                local text = string.lower(table.concat({
                    tostring(line.leftText or ""),
                    tostring(line.rightText or ""),
                    tostring(line.text or ""),
                }, " "))
                if text:find("fishing lure", 1, true) then
                    return true
                end
            end
        end
        return false
    end

    if type(C_TooltipInfo.GetInventoryItem) == "function" then
        local ok, tooltipData = pcall(C_TooltipInfo.GetInventoryItem, "player", 28)
        if ok and TooltipHasLure(tooltipData) then
            return true
        end
    end

    if type(GetInventoryItemLink) == "function"
        and type(C_TooltipInfo.GetHyperlink) == "function" then
        local itemLink = GetInventoryItemLink("player", 28)
        if itemLink then
            local ok, tooltipData = pcall(C_TooltipInfo.GetHyperlink, itemLink)
            if ok and TooltipHasLure(tooltipData) then
                return true
            end
        end
    end

    return false
end

local function IsDue(itemID, category, now)
    if category == "lure" and IsFishingLureApplied() then
        return false, "fishing_lure_already_applied"
    end

    if category == "fooddrink" and (tonumber(state.buffItemTransientUntil[itemID]) or 0) > now then
        return false, "transient_buff_active"
    end
    local lastUse = tonumber(state.buffItemLastUseAt[itemID])
    if lastUse and now - lastUse < 5 then
        return false, "recently_used" .. LastUseString(lastUse, nil)
    end
    local pending = state.pendingBuffObservation
    if type(pending) == "table" and tonumber(pending.itemID) == itemID then
        local known = GetKnownBuff(itemID)
        local isKnownDuration = type(known) == "table"
            and tonumber(known.spellID)
            and tonumber(known.duration)
        if not isKnownDuration then
            return false, "pending_observation" .. LastUseString(lastUse, nil)
        end
        state.pendingBuffObservation = nil
    end
    local pendingUse = state.pendingBuffUse
    if type(pendingUse) == "table" and tonumber(pendingUse.itemID) == itemID then
        return false, "pending_use"
    end
    if state.buffUnknownDurationSuppressed and (state.buffUnknownDurationSuppressed[itemID]
        or state.buffUnknownDurationSuppressed[tostring(itemID)]) then
        return false, "unknown_duration_suppressed"
    end

    local remaining, auraDuration = nil, nil
    if type(Fishing.GetTrackedBuffRemaining) == "function" then
        remaining, auraDuration = Fishing:GetTrackedBuffRemaining(itemID)
    end
    local spellID, knownDuration = GetKnownSpellAndDuration(itemID)
    local activeDuration = auraDuration and auraDuration > 0 and auraDuration or knownDuration
    local refreshLead = ns.Fishing.const.maxFishingCastSeconds + ns.Fishing.const.buffPreRefreshSafetySeconds
    if activeDuration and activeDuration > 0 then
        refreshLead = math.max(refreshLead, math.min(15, math.max(3, activeDuration * 0.10)))
    end
    if remaining ~= nil then
        if remaining <= refreshLead then
            return true, "remaining_duration_due " .. LastUseString(lastUse, activeDuration)
        else
            return false, "remaining_duration_not_due " .. LastUseString(lastUse, activeDuration)
        end
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
    return true, "unknown_duration_no_aura " .. LastUseString(lastUse, knownDuration)
end

local function QueueBuffUse(itemID, category)
    local itemSpellID = nil
    if C_Item and type(C_Item.GetItemSpell) == "function" then
        local spellID = C_Item.GetItemSpell(itemID)
        itemSpellID = tonumber(spellID)
    end
    local known = GetKnownBuff(itemID)
    local knownSpellID = type(known) == "table" and tonumber(known.spellID) or nil
    state.pendingBuffUse = {
        itemID = itemID,
        category = category,
        itemSpellID = itemSpellID or knownSpellID,
        knownSpellID = knownSpellID,
        countBefore = ns.Utils.CountItemInBags(itemID),
        auraBefore = type(Fishing.BuildHelpfulAuraSnapshot) == "function"
            and Fishing:BuildHelpfulAuraSnapshot()
            or {},
        expiresAt = GetNow() + 5,
    }
end

function Fishing:IsFoodDrinkTransientActive()
    local transientUntil = type(state.buffItemTransientUntil) == "table"
        and state.buffItemTransientUntil
        or nil
    if not transientUntil then
        return false
    end

    local now = GetNow()
    local activeUntil = nil
    for itemID, expiresAt in pairs(transientUntil) do
        if tonumber(expiresAt) and tonumber(expiresAt) > now then
            local known = GetKnownBuff(itemID)
            if type(known) == "table" and known.category == "fooddrink" then
                activeUntil = math.max(activeUntil or 0, tonumber(expiresAt))
            end
        end
    end
    return activeUntil ~= nil, activeUntil
end

function Fishing:CheckEnabledBuffItemsDepleted()
    if not self:IsInFishingSession() or state.buffDepletionAlerted then
        return
    end

    local configured = charDB and charDB.buffs
    if type(configured) ~= "table" then
        return
    end

    for _, items in pairs(configured) do
        if type(items) == "table" then
            for _, entry in ipairs(items) do
                local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
                if itemID and itemID > 0 and entry.enabled ~= false
                    and ns.Utils.CountItemInBags(itemID) == 0 then
                    local itemName = (C_Item and type(C_Item.GetItemInfo) == "function" and C_Item.GetItemInfo(itemID))
                        or "Unknown buff item"
                    state.buffDepletionAlerted = true
                    ns.Utils.Alert("Buff item depleted: " .. tostring(itemName) .. " (" .. tostring(itemID) .. ")")
                    return
                end
            end
        end
    end
end

function Fishing:ConfirmPendingBuffUse(successSpellID)
    local pending = self.state.pendingBuffUse
    if type(pending) ~= "table" then
        return
    end

    local now = GetNow()
    local itemID = tonumber(pending.itemID)
    local countAfter = itemID and ns.Utils.CountItemInBags(itemID) or nil
    local confirmedBySpell = tonumber(successSpellID)
        and (tonumber(pending.itemSpellID) == tonumber(successSpellID)
            or tonumber(pending.knownSpellID) == tonumber(successSpellID))
    local confirmedByCount = countAfter and pending.countBefore and countAfter < pending.countBefore
    if confirmedBySpell or confirmedByCount then
        self.state.pendingBuffUse = nil
        local lastUses = type(self.state.buffItemLastUseAt) == "table" and self.state.buffItemLastUseAt or {}
        self.state.buffItemLastUseAt = lastUses
        rawset(lastUses, itemID, now)
        local known = GetKnownBuff(itemID)
        local spellID = type(known) == "table" and tonumber(known.spellID) or nil
        if pending.category == "fooddrink" then
            local transientUntil = type(self.state.buffItemTransientUntil) == "table"
                and self.state.buffItemTransientUntil
                or {}
            self.state.buffItemTransientUntil = transientUntil
            rawset(transientUntil, itemID, now + 10)
        end
        local isKnownDuration = type(known) == "table"
            and tonumber(known.spellID)
            and tonumber(known.duration)
        if not isKnownDuration then
            self.state.pendingBuffObservation = {
                itemID = itemID,
                before = pending.auraBefore or {},
                expiresAt = now + 20,
            }
        else
            self.state.pendingBuffObservation = nil
        end
        if type(Fishing.AnnounceBuffUse) == "function" then
            Fishing:AnnounceBuffUse(itemID, spellID)
        end
        self:CheckEnabledBuffItemsDepleted()
        Trace("Confirmed consumable use: " .. Item(itemID))
    elseif now >= (tonumber(pending.expiresAt) or 0) then
        self.state.pendingBuffUse = nil
        Trace("Consumable use not confirmed; leaving due state unchanged: " .. Item(itemID))
    end
end

local function GetConsumableUseDecision(self)
    local decision = { shouldApply = false }
    if type(Fishing.ConfirmPendingBuffUse) == "function" then
        Fishing:ConfirmPendingBuffUse()
    end
    Fishing:CheckEnabledBuffItemsDepleted()
    if type(Fishing.UpdatePendingBuffObservation) == "function" then
        Fishing:UpdatePendingBuffObservation()
    end
    local foodDrinkTransientActive, transientUntil = Fishing:IsFoodDrinkTransientActive()
    if foodDrinkTransientActive then
        local warningUntil = tonumber(self.state.buffTransientWarningUntil) or 0
        if warningUntil < transientUntil then
            self.state.buffTransientWarningUntil = transientUntil
            ns.Utils.Alert("A buff is still being applied. Wait before casting.")
        end
        Trace("Skipping consumable scan: food/drink transient block active")
        return decision
    end
    if type(self.state.pendingBuffUse) == "table" then
        Trace("Skipping consumable scan: use confirmation pending for "
            .. Item(self.state.pendingBuffUse.itemID))
        local pendingItemID = tonumber(self.state.pendingBuffUse.itemID)
        local pendingKnown = GetKnownBuff(pendingItemID)
        local pendingCategory = type(pendingKnown) == "table" and pendingKnown.category or "other_consumable"
        return {
            shouldApply = pendingItemID and pendingItemID > 0 or false,
            itemID = pendingItemID,
            category = pendingCategory,
        }
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
                    elseif not ns.Utils.IsCooldownReady(itemID) then
                        Trace("Skipping due consumable: cooldown not ready " .. Item(itemID) .. " " .. ns.Utils.GetDebugCooldownText(itemID))
                    else
                        local isDue, reason = IsDue(itemID, category, GetNow())
                        if not isDue then
                            Trace("Skipping due consumable: not due " .. Item(itemID, category) .. " (" .. tostring(reason) .. ")")
                        elseif not ns.Utils.FindItemInBags(itemID) then
                            Trace("Skipping due consumable: not found in bags " .. Item(itemID, category))
                        elseif category == "lure" then
                            local poleID = type(ns.precast.GetEquippedProfessionItemID) == "function"
                                and ns.precast.GetEquippedProfessionItemID()
                                or nil
                            if not poleID or poleID <= 0 then
                                WarnMissingProfessionFishingPoleForLure()
                            else
                                QueueBuffUse(itemID, category)
                                Trace("Lure is queued: " .. Item(itemID))
                                return { shouldApply = true, itemID = itemID, category = category }
                            end
                        else
                            Trace("Consumable is queued: " .. Item(itemID, category))
                            QueueBuffUse(itemID, category)
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

