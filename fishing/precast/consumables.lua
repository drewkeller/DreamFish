local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing
local state = ns.Fishing.state

Fishing:RegisterTraceSource("buffs")
state.buffItemLastUseAt = state.buffItemLastUseAt or {}

local globalDB, profileDB, charDB
Fishing:RegisterOnModuleInitialize(function(self)
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
    Addon:Alert(ns.SystemColor.YELLOW, warningText)
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

local function NeedsLearning(itemID)
    local known = GetKnownBuff(itemID)
    if type(known) == "table" then
        return false
    end
    local tracked = GetTrackedBuff(itemID)
    local hasEffectData = type(tracked) == "table" and tonumber(tracked.spellID) and tonumber(tracked.duration)
    local hasCastClassification = type(tracked) == "table" and tracked.isInstant ~= nil
    return not hasEffectData or not hasCastClassification
end

local QueueBuffUse

local function GetSnapshotEffectSpellIDs()
    local snapshot = state.precastConsumableSnapshot
    if type(snapshot) ~= "table" then
        return nil
    end
    if type(snapshot.effectSpellIDs) ~= "table" then
        snapshot.effectSpellIDs = {}
    end
    return snapshot.effectSpellIDs
end

local function MarkPrecastEffectQueued(effectSpellID)
    if not effectSpellID then
        return
    end
    local snapshotEffectSpellIDs = GetSnapshotEffectSpellIDs()
    if snapshotEffectSpellIDs then
        snapshotEffectSpellIDs[effectSpellID] = true
    end
end

local function MarkPrecastConsumableDecisionMade()
    if type(state.precastConsumableSnapshot) == "table" then
        state.precastConsumableSnapshot.decisionMade = true
    end
end

function Fishing:IsPrecastConsumableDecisionMade()
    local snapshot = self.state.precastConsumableSnapshot
    return type(snapshot) == "table" and snapshot.decisionMade == true
end

function Fishing:StartPrecastConsumableSnapshot(reason)
    local generation = (tonumber(self.state.precastConsumableSnapshotGeneration) or 0) + 1
    self.state.precastConsumableSnapshotGeneration = generation
    self.state.precastConsumableSnapshot = {
        generation = generation,
        effectSpellIDs = {},
        decisionMade = false,
    }
    Trace("Started consumable precast snapshot generation=" .. tostring(generation)
        .. " reason=" .. tostring(reason))
end

function Fishing:ClearPrecastConsumableSnapshot(reason)
    if type(self.state.precastConsumableSnapshot) == "table" then
        Trace("Cleared consumable precast snapshot reason=" .. tostring(reason))
    end
    self.state.precastConsumableSnapshot = nil
end

function Fishing:IsBuffItemLearningRequired(itemID)
    return NeedsLearning(itemID)
end

local LEARNING_CATEGORY_ORDER = { "fooddrink", "lure", "bait", "bobber", "other_consumable" }

function Fishing:GetBuffLearningCandidates()
    local candidates = {}
    local configured = charDB and charDB.buffs
    if type(configured) ~= "table" then
        return candidates
    end

    for _, category in ipairs(LEARNING_CATEGORY_ORDER) do
        local items = configured[category]
        if type(items) == "table" then
            for slotIndex, entry in ipairs(items) do
                local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
                if itemID and itemID > 0 and entry.enabled == true and NeedsLearning(itemID) then
                    table.insert(candidates, {
                        itemID = itemID,
                        category = category,
                        slotIndex = slotIndex,
                        available = ns.Utils.IsItemAvailableForEquip(itemID) ~= nil,
                    })
                end
            end
        end
    end

    return candidates
end

function Fishing:GetBuffLearningCandidateCount()
    local count = 0
    for _, candidate in ipairs(self:GetBuffLearningCandidates()) do
        if candidate.available and candidate.category ~= "lure" then
            count = count + 1
        end
    end
    return count
end

function Fishing:GetBuffLearningStatus()
    if type(self.state.buffLearning) == "table" then
        return self.state.buffLearning
    end
    for _, candidate in ipairs(self:GetBuffLearningCandidates()) do
        if candidate.available and candidate.category ~= "lure" then
            return candidate
        end
    end
    return nil
end

function Fishing:NotifyBuffLearningChanged()
    if type(ns.RefreshBuffLearningWidgets) == "function" then
        ns.RefreshBuffLearningWidgets()
    end
    local registry = type(LibStub) == "function" and LibStub("AceConfigRegistry-3.0", true) or nil
    if registry then
        registry:NotifyChange("DreamFishDialog")
    end
end

function Fishing:BeginBuffLearning(candidate)
    if type(self.state.buffLearning) == "table" then
        return false
    end
    if type(candidate) ~= "table" or not candidate.available or candidate.category == "lure" then
        return false
    end
    local pending = self.state.pendingBuffUse
    if type(pending) == "table" and pending.executedAt then
        Trace("Cannot begin buff learning: consumable confirmation pending")
        return false
    end
    self.state.pendingBuffUse = nil
    self.state.precastConsumableSnapshot = nil
    self.state.buffLearning = {
        itemID = candidate.itemID,
        category = candidate.category,
        slotIndex = candidate.slotIndex,
        phase = "using",
    }
    Trace("Beginning buff learning for itemID=" .. tostring(candidate.itemID))
    QueueBuffUse(candidate.itemID, candidate.category)
    return true
end

function Fishing:MarkBuffLearningExecuted()
    local learning = self.state.buffLearning
    local pending = self.state.pendingBuffUse
    if type(learning) ~= "table" or type(pending) ~= "table" or pending.executedAt then
        Trace("Cannot execute buff learning: invalid state or already executed")
        return
    end
    Trace("Executing buff learning for itemID=" .. tostring(learning.itemID))
    pending.executedAt = GetNow()
    for _, use in ipairs(pending.uses or {}) do
        use.expiresAt = pending.executedAt + 5
    end
    learning.phase = "confirming"
    self:ScheduleTimer(function()
        if type(self.state.buffLearning) == "table" and self.state.buffLearning.phase == "confirming" then
            self:ConfirmPendingBuffUse()
        end
    end, 5.1)
end

function Fishing:FailBuffLearning(candidate, reason)
    if type(candidate) ~= "table" then
        return
    end
    local configured = charDB and charDB.buffs and charDB.buffs[candidate.category]
    local entry = type(configured) == "table" and configured[candidate.slotIndex] or nil
    if type(entry) == "table" and tonumber(entry.itemID) == tonumber(candidate.itemID) then
        entry.enabled = false
    end
    self.state.buffLearning = nil
    self.state.pendingBuffUse = nil
    self.state.pendingBuffObservation = nil
    Addon:Alert(ns.SystemColor.YELLOW, "Could not learn buff item: " .. Item(candidate.itemID)
        .. ". It has been disabled.")
    self:Trace("buffs", "Buff learning failed: " .. tostring(reason))
    if type(ns.RefreshBuffItemSlots) == "function" then
        ns.RefreshBuffItemSlots()
    end
    self:NotifyBuffLearningChanged()
end

local function IsFishingLureApplied()
    Trace("Checking pole for lure...")
    if not C_TooltipInfo or type(C_TooltipInfo.GetInventoryItem) ~= "function" then
        Trace("C_TooltipInfo.GetInventoryItem API not available")
        return true
    end

    -- Force the game client to refresh its internal server data cache instantly
    local hiddenScanner = EnsureCategoryTooltipFrame and EnsureCategoryTooltipFrame()
    if hiddenScanner and type(hiddenScanner.SetInventoryItem) == "function" then
        pcall(hiddenScanner.SetInventoryItem, hiddenScanner, "player", 28)
    end

    local function TooltipHasLure(tooltipData)
        if type(tooltipData) ~= "table" or type(tooltipData.lines) ~= "table" then
            Trace("Tooltip data block is incomplete or parsing failed")
            return true
        end

        -- Line-by-line text scan
        for _, line in ipairs(tooltipData.lines) do
            if type(line) == "table" then
                local leftText = line.leftText or line.text or ""
                if type(leftText) == "string" and leftText ~= "" then
                    local lowercaseText = string.lower(leftText)

                    if lowercaseText:find("fishing lure", 1, true) then
                        Trace("Detected lure: " .. leftText)
                        return true
                    end
                end
            end
        end

        Trace("Pole tooltip parsed successfully; no lure detected.")
        return false
    end

    -- Query the live character journal profession tool slot directly
    local ok, tooltipData = pcall(C_TooltipInfo.GetInventoryItem, "player", 28)
    if ok and tooltipData then
        return TooltipHasLure(tooltipData)
    end

    Trace("C_TooltipInfo lookup execution failed")
    return true
end

local function IsDue(itemID, category, now)
    if category == "lure" then
        local poleID = type(ns.precast.GetEquippedProfessionItemID) == "function" and ns.precast.GetEquippedProfessionItemID() or "nil"
        Trace(string.format("[PROBE: LURE_DUE_CHECK] itemID=%s | State=%s | EquippedPoleID=%s | isEquippingPrimaryPole=%s",
            tostring(itemID), Fishing:CurrentStateName(), tostring(poleID), tostring(Fishing.state and Fishing.state.isEquippingPrimaryPole)))

        if Fishing.state and Fishing.state.isEquippingPrimaryPole then
            Trace("Skipping lure due check: fishing pole weapon swap is actively in progress.")
            return false, "fishing_lure_pole_not_ready"
        elseif IsFishingLureApplied() then
            Trace("Lure is not due: lure is already applied to the active pole.")
            return false, "fishing_lure_already_applied"
        end

        local known = GetKnownBuff(itemID)
        local lastUse = tonumber(state.buffItemLastUseAt[itemID])
        local duration = type(known) == "table" and tonumber(known.duration) or nil
        if lastUse and duration and duration > 0 and now - lastUse < duration then
            Trace("Lure is not due: confirmed application remains within its known duration.")
            return false, "confirmed_lure_duration" .. LastUseString(lastUse, duration)
        end
    end

    local lastUse = tonumber(state.buffItemLastUseAt[itemID])
    if lastUse and now - lastUse < 5 then
        return false, "recently_used" .. LastUseString(lastUse, nil)
    end
    local pending = state.pendingBuffObservation
    if type(pending) == "table" and tonumber(pending.itemID) == itemID then
        local spellID, knownDuration = GetKnownSpellAndDuration(itemID)
        local isKnownDuration = spellID and knownDuration
        if not isKnownDuration then
            return false, "pending_observation" .. LastUseString(lastUse, nil)
        end
        state.pendingBuffObservation = nil
    end
    local pendingUse = state.pendingBuffUse
    if type(pendingUse) == "table" and type(pendingUse.uses) == "table" then
        for _, pending in ipairs(pendingUse.uses) do
            if tonumber(pending.itemID) == itemID then
                return false, "pending_use"
            end
        end
    end
    -- Update your suppression check loop so it cleanly handles temporary item blocks
    local suppressedUntil = state.buffUnknownDurationSuppressed
        and state.buffUnknownDurationSuppressed[itemID]
    if suppressedUntil then
        if type(suppressedUntil) == "number" and now > suppressedUntil then
            state.buffUnknownDurationSuppressed[itemID] = nil -- Suppression expired, clear it
        else
            return false, "zone_failure_suppressed_active" -- unknown or zone failure
        end
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

QueueBuffUse = function(itemID, category)
    local itemSpellID = nil
    if C_Item and type(C_Item.GetItemSpell) == "function" then
        local spellID = C_Item.GetItemSpell(itemID)
        itemSpellID = tonumber(spellID)
    end
    local knownSpellID = GetKnownSpellAndDuration(itemID)
    local pendingUse = state.pendingBuffUse
    if type(pendingUse) ~= "table" or type(pendingUse.uses) ~= "table" then
        pendingUse = { uses = {} }
        state.pendingBuffUse = pendingUse
    end
    table.insert(pendingUse.uses, {
        itemID = itemID,
        category = category,
        sessionGeneration = state.fishingSessionGeneration,
        precastGeneration = state.precastConsumableSnapshot
            and state.precastConsumableSnapshot.generation
            or nil,
        itemSpellID = itemSpellID or knownSpellID,
        knownSpellID = knownSpellID,
        castStarted = false,
        countBefore = ns.Utils.CountItemInBags(itemID),
        auraBefore = type(Fishing.BuildHelpfulAuraSnapshot) == "function"
            and Fishing:BuildHelpfulAuraSnapshot()
            or {},
        expiresAt = GetNow() + 5,
    })
    MarkPrecastEffectQueued(knownSpellID)
    Trace("Queued buff use for itemID=" .. tostring(itemID) .. " category=" .. tostring(category))
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
                    state.buffDepletionAlerted = true
                    Addon:Alert(ns.SystemColor.YELLOW, "Buff item depleted: " .. ns.Utils.ItemLink(itemID))
                    return
                end
            end
        end
    end
end

function Fishing:ConfirmPendingBuffUse(successSpellID)
    local pending = self.state.pendingBuffUse
    if type(pending) ~= "table" or type(pending.uses) ~= "table" then
        return
    end

    local now = GetNow()
    for index = #pending.uses, 1, -1 do
        local use = pending.uses[index]
        local itemID = tonumber(use.itemID)
        local countAfter = itemID and ns.Utils.CountItemInBags(itemID) or nil
        local confirmedBySpell = tonumber(successSpellID)
            and (tonumber(use.itemSpellID) == tonumber(successSpellID)
                or tonumber(use.knownSpellID) == tonumber(successSpellID))
        local confirmedByCount = #pending.uses == 1
            and countAfter and use.countBefore and countAfter < use.countBefore
        if confirmedBySpell or confirmedByCount then
            table.remove(pending.uses, index)
        local lastUses = type(self.state.buffItemLastUseAt) == "table" and self.state.buffItemLastUseAt or {}
        self.state.buffItemLastUseAt = lastUses
        rawset(lastUses, itemID, now)
        local known = GetKnownBuff(itemID)
        local spellID, trackedDuration = GetKnownSpellAndDuration(itemID)
        -- Built-in metadata is authoritative; only unknown items use learned fallback data.
        if globalDB and type(globalDB.buffAuraByItem) == "table"
            and type(known) ~= "table" then
            local trackedKey = tostring(itemID)
            local trackedEntry = globalDB.buffAuraByItem[trackedKey]
            local observedIsInstant = not use.castStarted
            if type(trackedEntry) == "table" then
                trackedEntry.isInstant = observedIsInstant
            else
                globalDB.buffAuraByItem[trackedKey] = { isInstant = observedIsInstant }
            end
        end
        local isKnownDuration = spellID and trackedDuration
        if not isKnownDuration then
            self.state.pendingBuffObservation = {
                itemID = itemID,
                before = type(Fishing.BuildHelpfulAuraSnapshot) == "function"
                    and Fishing:BuildHelpfulAuraSnapshot()
                    or {},
                expiresAt = now + 20,
            }
            if type(self.state.buffLearning) == "table"
                and tonumber(self.state.buffLearning.itemID) == itemID then
                self.state.pendingBuffObservation.learningCandidate = self.state.buffLearning
                self.state.buffLearning.phase = "observing"
            end
        else
            self.state.pendingBuffObservation = nil
            self.state.buffLearning = nil
            self:NotifyBuffLearningChanged()
        end
        if type(Fishing.AnnounceBuffUse) == "function" then
            Fishing:AnnounceBuffUse(itemID, spellID)
        end

        --self:CheckEnabledBuffItemsDepleted()
        if ns.Utils.CountItemInBags(itemID) == 0 then
            Addon:Alert(ns.SystemColor.YELLOW, ns.Utils.GetDebugItemLabel(itemID) .. " has been depleted.")
        end

        if type(self.PrepareFishingClickAction) == "function" then
            self:PrepareFishingClickAction()
        end
        elseif now >= (tonumber(use.expiresAt) or 0) then
            table.remove(pending.uses, index)

            -- Only an executed macro can establish that an item was rejected.
            local isCurrentSession = use.sessionGeneration == nil
                or use.sessionGeneration == state.fishingSessionGeneration
            if type(self.state.buffLearning) == "table"
                and tonumber(self.state.buffLearning.itemID) == itemID then
                self:FailBuffLearning(self.state.buffLearning, "use was not confirmed")
                return
            end
            if pending.executedAt and itemID and isCurrentSession
                and not state.suppressPendingBuffFailure then
                self.state.buffUnknownDurationSuppressed = self.state.buffUnknownDurationSuppressed or {}
                self.state.buffUnknownDurationSuppressed[itemID] = now + 10
                Addon:Alert(ns.SystemColor.YELLOW, "Consumable use failed: " .. ns.Utils.ItemName(itemID))
                ns.Utils.PrintNoLog("Consumable use failed: " .. ns.Utils.ItemLink(itemID))
            end
        end
    end
    if #pending.uses == 0 then
        self.state.pendingBuffUse = nil
    end
end

local function GetConsumableUseDecision(self, instantOnly)
    local decision = { shouldApply = false }
    if type(Fishing.ConfirmPendingBuffUse) == "function" then
        Fishing:ConfirmPendingBuffUse()
    end
    --Fishing:CheckEnabledBuffItemsDepleted()
    if type(Fishing.UpdatePendingBuffObservation) == "function" then
        Fishing:UpdatePendingBuffObservation()
    end
    if type(self.state.pendingBuffUse) == "table" and type(self.state.pendingBuffUse.uses) == "table" then
        MarkPrecastConsumableDecisionMade()
        Trace("Skipping consumable scan: use confirmation pending")
        return { shouldApply = #self.state.pendingBuffUse.uses > 0, items = self.state.pendingBuffUse.uses }
    end
    local configured = charDB and charDB.buffs
    MarkPrecastConsumableDecisionMade()
    if type(configured) ~= "table" then
        return decision
    end

    local itemsToApply = {}
    local queuedEffectSpellIDs = {}
    local snapshotEffectSpellIDs = GetSnapshotEffectSpellIDs()
    if snapshotEffectSpellIDs then
        for effectSpellID, queued in pairs(snapshotEffectSpellIDs) do
            if queued then
                queuedEffectSpellIDs[effectSpellID] = true
            end
        end
    end
    for _, category in ipairs(LEARNING_CATEGORY_ORDER) do
        local items = configured[category]
        if type(items) == "table" then
            for _, entry in ipairs(items) do

                if type(entry) == "table" and entry.enabled == true and not IsExcluded(tonumber(entry.itemID), entry) then
                    local itemID = tonumber(entry.itemID)
                    local known = GetKnownBuff(itemID)
                    local tracked = GetTrackedBuff(itemID)
                    local effectSpellID = GetKnownSpellAndDuration(itemID)
                    local isInstant = (type(known) == "table" and tonumber(known.castTime) == 0)
                        or (type(known) ~= "table" and type(tracked) == "table" and tracked.isInstant == true)
                    --Trace("Checking due consumable: " .. Item(itemID) .. " (" .. tostring(category) .. ")")
                    if not itemID or itemID <= 0 then
                        --Trace("Skipping due consumable: invalid itemID")
                    elseif instantOnly and not isInstant then
                        Trace("Skipping non-instant consumable while another pre-cast action is armed: "
                            .. Item(itemID, category))
                    elseif not ns.Utils.IsCooldownReady(itemID) then
                        Trace("Skipping due consumable: cooldown not ready " .. Item(itemID) .. " " .. ns.Utils.GetDebugCooldownText(itemID))
                    else
                        local isDue, reason = IsDue(itemID, category, GetNow())
                        if not isDue then
                            Trace("Skipping due consumable: not due " .. Item(itemID, category) .. " (" .. tostring(reason) .. ")")
                        elseif ns.Utils.FindItemInBags(itemID) == nil then
                            Trace("Skipping due consumable: not found in bags " .. Item(itemID, category))
                        elseif NeedsLearning(itemID) then
                            Trace("Skipping unlearned consumable outside Buff Items learning mode: " .. Item(itemID, category))
                        elseif effectSpellID and queuedEffectSpellIDs[effectSpellID] then
                            Trace("Skipping due consumable: equivalent effect already handled this precast " .. Item(itemID, category))
                        elseif category == "lure" then
                            local poleID = type(ns.precast.GetEquippedProfessionItemID) == "function"
                                and ns.precast.GetEquippedProfessionItemID()
                                or nil
                            if not poleID or poleID <= 0 then
                                WarnMissingProfessionFishingPoleForLure()
                            elseif #itemsToApply > 0 then
                                return { shouldApply = true, items = itemsToApply }
                            else
                                if effectSpellID then
                                    queuedEffectSpellIDs[effectSpellID] = true
                                    MarkPrecastEffectQueued(effectSpellID)
                                end
                                QueueBuffUse(itemID, category)
                                Trace("Lure is queued: " .. Item(itemID))
                                return { shouldApply = true, items = { { itemID = itemID, category = category } } }
                            end
                        else
                            if not isInstant and #itemsToApply > 0 then
                                return { shouldApply = true, items = itemsToApply }
                            end
                            Trace("Consumable is queued: " .. Item(itemID, category))
                            if effectSpellID then
                                queuedEffectSpellIDs[effectSpellID] = true
                                MarkPrecastEffectQueued(effectSpellID)
                            end
                            QueueBuffUse(itemID, category)
                            table.insert(itemsToApply, { itemID = itemID, category = category })
                            if not isInstant then
                                return { shouldApply = true, items = itemsToApply }
                            end
                        end
                    end
                end
            end
        end
    end
    if #itemsToApply > 0 then
        return { shouldApply = true, items = itemsToApply }
    end
    return decision
end

ns.precast.GetConsumableUseDecision = GetConsumableUseDecision

