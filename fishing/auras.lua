local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing
local state = ns.Fishing.state

state.buffItemLastUseAt = state.buffItemLastUseAt or {}
state.buffItemTransientUntil = state.buffItemTransientUntil or {}

local globalDB, profileDB, charDB
Fishing:RegisterOnModuleInitialize(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

Fishing:RegisterTraceSource("auras")
local function Trace(msg)
    Fishing:Trace("auras", msg)
end

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

    local configured = self.db.char.buffs
    if type(configured) ~= "table" then
        self.state.pendingBuffObservation = nil
        return
    end

    local hasConfiguredBuffItems = false
    local configuredItemIDs = {}
    for _, items in pairs(configured) do
        if type(items) == "table" then
            for _, entry in ipairs(items) do
                local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
                if itemID and itemID > 0 and not (type(entry) == "table" and entry.enabled == false) then
                    hasConfiguredBuffItems = true
                    configuredItemIDs[itemID] = true
                end
            end
        end
    end
    if self.state.buffUnknownDurationSuppressed then
        for itemID in pairs(self.state.buffUnknownDurationSuppressed) do
            if not configuredItemIDs[tonumber(itemID)] then
                self.state.buffUnknownDurationSuppressed[itemID] = nil
            end
        end
    end
    if not hasConfiguredBuffItems then
        self.state.pendingBuffObservation = nil
        return
    end

    if self.state.pendingBuffObservation.expiresAt then
        if GetTime() > self.state.pendingBuffObservation.expiresAt then
            local learningCandidate = self.state.pendingBuffObservation.learningCandidate
            local unresolvedItemID = tonumber(self.state.pendingBuffObservation.itemID)
            if unresolvedItemID and unresolvedItemID > 0 and self.state then
                self.state.buffUnknownDurationSuppressed = self.state.buffUnknownDurationSuppressed or {}
                self.state.buffUnknownDurationSuppressed[unresolvedItemID] = GetTime() + 10
            end
            self.state.pendingBuffObservation = nil
            if learningCandidate and type(self.FailBuffLearning) == "function" then
                self:FailBuffLearning(learningCandidate, "aura data was not observed")
            end
            return
        end
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
        if isNewKnownAura and knownAura.duration then
            bestSpellID = pendingKnownSpellID
            bestDuration = knownAura.duration
            bestExpirationTime = knownAura.expirationTime
        elseif refreshedKnownAura then
            -- The aura can be extended by reapplication; this item only contributed the delta.
            bestSpellID = pendingKnownSpellID
            bestDuration = knownAura.expirationTime - previousKnownAura.expirationTime
            bestExpirationTime = knownAura.expirationTime
        end
    end

    if not bestSpellID then
        for spellID, aura in pairs(current) do
            local previous = before[spellID]
            local isNewAura = previous == nil
            local refreshedAura = previous and aura.expirationTime and previous.expirationTime and aura.expirationTime > previous.expirationTime + 0.5
            local candidateDuration = nil
            if isNewAura and aura.duration then
                candidateDuration = aura.duration
            elseif refreshedAura then
                candidateDuration = aura.expirationTime - previous.expirationTime
            end
            if candidateDuration and candidateDuration > bestDuration then
                bestSpellID = spellID
                bestDuration = candidateDuration
                bestExpirationTime = aura.expirationTime
            end
        end
    end

    if bestSpellID then
        local itemID = pendingItemID or 0

        -- Completely refuse to write tracking rules if itemID has dropped into a nil/0 fallback state!
        if not itemID or itemID <= 0 then
            self:Debug("Aborting aura database write: pendingItemID is invalid or zero.")
            self.state.pendingBuffObservation = nil
            return
        end

        -- If the item under observation is the Underlight Angler or a primary pole,
        -- clear the record and exit
        if itemID == ns.Fishing.const.underlightAnglerItemID or (ns.precast.GetSelectedFishingPoleDecision and itemID == ns.precast.GetSelectedFishingPoleDecision().itemID) then
            self.state.pendingBuffObservation = nil
            return
        end

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
        elseif Addon.buff and type(Addon.buff.GetBuffItemCategory) == "function" then
            category = Addon.buff.GetBuffItemCategory(itemID)
        end

        local floorDuration = math.max(existingDuration or 0, knownDuration or 0)
        if category == "fooddrink" then
            local foodDrinkExpected = math.max(knownDuration or 0, existingDuration or 0)
            if foodDrinkExpected > 0 then
                floorDuration = math.max(floorDuration, foodDrinkExpected * 0.5)
            end
        end

        if category == "fooddrink" and floorDuration <= 0 and bestDuration > 0 and bestDuration < 60 then
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
            if category == "fooddrink" and bestDuration > 0 and self.state then
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

        local spellInfo = (C_Spell and C_Spell.GetSpellInfo) and C_Spell.GetSpellInfo(bestSpellID) or nil
        local auraName = spellInfo and spellInfo.name or nil

        -- Once a duration is established, ignore small drift (timing jitter) and only
        -- accept a new observation if it's significantly larger than what's already known.
        local finalDuration = bestDuration
        if existingDuration > 0 then
            local significantMargin = math.max(2, existingDuration * 0.15)
            if bestDuration <= existingDuration + significantMargin then
                finalDuration = existingDuration
            end
        end

        local existingEntry = self.db.global.buffAuraByItem[key]
        self.db.global.buffAuraByItem[key] = {
            spellID = bestSpellID,
            duration = finalDuration,
            isInstant = type(existingEntry) == "table" and existingEntry.isInstant or nil,
        }
        if self.state and self.state.buffUnknownDurationSuppressed then
            self.state.buffUnknownDurationSuppressed[itemID] = nil
        end
        if self.state and self.state.buffItemTransientUntil then
            self.state.buffItemTransientUntil[itemID] = nil
        end
        if self.state and self.state.learningBuffItems then
            self.state.learningBuffItems[itemID] = nil
        end
        Addon:Print("Learned buff item: " .. ns.Utils.GetDebugItemLabel(itemID)
            .. " [isInstant=" .. tostring(type(existingEntry) == "table" and existingEntry.isInstant == true)
            .. ", spellID=" .. tostring(bestSpellID)
            .. (auraName and (", aura=" .. tostring(auraName)) or "")
            .. ", duration=" .. ns.Utils.FormatDuration(finalDuration) .. "]")
        self.state.pendingBuffObservation = nil
        if self.state.buffLearning and tonumber(self.state.buffLearning.itemID) == itemID then
            self.state.buffLearning = nil
            if type(ns.RefreshBuffItemSlots) == "function" then
                ns.RefreshBuffItemSlots()
            end
            if type(self.NotifyBuffLearningChanged) == "function" then
                self:NotifyBuffLearningChanged()
            end
        end
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
    if self.db.global and type(self.db.global.buffAuraByItem) == "table" then
        local tracked = self.db.global.buffAuraByItem[tostring(numericItemID)]
        if type(tracked) == "table" and tracked.spellID then
            trackedSpellID = tonumber(tracked.spellID)
            trackedDuration = tonumber(tracked.duration)
        end
    end

    if knownSpellID and knownDuration and self.db.global and type(self.db.global.buffAuraByItem) == "table" then
        local tracked = self.db.global.buffAuraByItem[tostring(numericItemID)]
        if type(tracked) == "table" and (tracked.spellID ~= knownSpellID or tracked.duration ~= knownDuration) then
            tracked.spellID = knownSpellID
            tracked.duration = knownDuration
            trackedSpellID = knownSpellID
            trackedDuration = knownDuration
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
                and self.db
                and type(self.db.global.buffAuraByItem) == "table" then
                self.db.global.buffAuraByItem[tostring(numericItemID)] = {
                    spellID = knownSpellID,
                    duration = knownDuration or trackedDuration or (tonumber(aura.duration) or 0),
                }
            end
            -- The aura's spellID can be shared across items, so its live duration may reflect
            -- another item's refresh; report this item's own known/tracked duration instead.
            return math.max(0, aura.expirationTime - GetTime()), (knownDuration or trackedDuration or tonumber(aura.duration))
        end
    end

    return nil
end

ns.GetAuraBySpellID = function(spellID)
    return Fishing:GetAuraBySpellID(spellID)
end

function Fishing:GetBuffTimingText(itemID)
    local numericItemID = tonumber(itemID)
    local known = numericItemID
        and ns.Fishing.const
        and type(ns.Fishing.const.knownBuffItems) == "table"
        and ns.Fishing.const.knownBuffItems[numericItemID]
        or nil
    local tracked = self.db.global
        and type(self.db.global.buffAuraByItem) == "table"
        and self.db.global.buffAuraByItem[tostring(itemID)]
        or nil
    local spellID = type(known) == "table" and tonumber(known.spellID)
        or type(tracked) == "table" and tonumber(tracked.spellID)
        or nil
    local itemDuration = type(known) == "table" and tonumber(known.duration)
        or type(tracked) == "table" and tonumber(tracked.duration)
        or nil
    if not spellID then
        return "duration unknown (learning aura spell mapping)"
    end

    local aura = ns.GetAuraBySpellID(spellID)
    if aura and aura.expirationTime and aura.expirationTime > 0 then
        local remaining = math.max(0, aura.expirationTime - GetTime())
        local activeTotal = itemDuration or aura.duration or remaining
        return "item=" .. ns.Utils.FormatDuration(itemDuration) .. ", active=" .. ns.Utils.FormatDuration(remaining) .. " remaining / " .. ns.Utils.FormatDuration(activeTotal) .. " total"
    end

    if itemDuration then
        return "item=" .. ns.Utils.FormatDuration(itemDuration) .. ", active aura not detected"
    end
    return "duration unknown (learning aura timings)"
end

function Fishing:AnnounceBuffUse(itemID, spellID)
    Trace("Used: " .. ns.Utils.ItemName(itemID) .. " (" .. tostring(itemID) .. ", spellID=" .. tostring(spellID) .. ") [" .. self:GetBuffTimingText(itemID) .. "]")
    self:Info("Used " .. ns.Utils.ItemLink(itemID))
end

local function EnsureCategoryTooltipFrame()
    if CategoryTooltipFrame then
        return CategoryTooltipFrame
    end
    if type(CreateFrame) ~= "function" then
        return nil
    end

    local ok, frame = pcall(CreateFrame, "GameTooltip", "DreamFishBuffCategoryTooltipFrame", nil, "GameTooltipTemplate")
    if not ok then
        return nil
    end
    CategoryTooltipFrame = frame
    if CategoryTooltipFrame and type(CategoryTooltipFrame.SetOwner) == "function" and WorldFrame then
        pcall(CategoryTooltipFrame.SetOwner, CategoryTooltipFrame, WorldFrame, "ANCHOR_NONE")
    end
    return CategoryTooltipFrame
end

local function TooltipTextSuggestsLure(text)
    if type(text) ~= "string" or text == "" then
        return false
    end

    local lower = string.lower(text)
    return lower:find("when applied to your fishing pole", 1, true)
        or lower:find("fishing lure", 1, true)
        or lower:find("increases .-fishing by %d+")
end

local function TooltipDataSuggestsLure(tooltipData)
    if type(tooltipData) ~= "table" or type(tooltipData.lines) ~= "table" then
        return false
    end

    for _, line in ipairs(tooltipData.lines) do
        if line and TooltipTextSuggestsLure(line.leftText) then
            return true
        end
    end

    return false
end

local function TooltipSuggestsLure(itemID, bag, slot)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return false
    end

    if bag and slot and C_TooltipInfo and type(C_TooltipInfo.GetBagItem) == "function" then
        local ok, tooltipData = pcall(C_TooltipInfo.GetBagItem, bag, slot)
        if ok and TooltipDataSuggestsLure(tooltipData) then
            return true
        end
    end

    local tooltip = EnsureCategoryTooltipFrame()
    if not tooltip then
        return false
    end

    if type(tooltip.ClearLines) == "function" then
        tooltip:ClearLines()
    end

    local bound = false
    if type(tooltip.SetItemByID) == "function" then
        local ok, result = pcall(tooltip.SetItemByID, tooltip, numeric)
        bound = ok and (result ~= false)
    end
    if (not bound) and type(tooltip.SetHyperlink) == "function" then
        local ok, result = pcall(tooltip.SetHyperlink, tooltip, "item:" .. tostring(numeric))
        bound = ok and (result ~= false)
    end
    if not bound then
        return false
    end

    local numLines = (type(tooltip.NumLines) == "function") and tonumber(tooltip:NumLines()) or 0
    if not numLines or numLines <= 0 then
        return false
    end

    for i = 1, numLines do
        local lineFrame = _G["DreamFishBuffCategoryTooltipFrameTextLeft" .. i]
        local text = lineFrame and type(lineFrame.GetText) == "function" and lineFrame:GetText() or nil
        if TooltipTextSuggestsLure(text) then
            return true
        end
    end

    return false
end

local function GetItemInfoInstantSafe(itemID)
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        return C_Item.GetItemInfoInstant(itemID)
    end
    return nil
end

-- Gets the category of a buff item, based on known mappings, tooltip analysis, and item type/subtype.
-- Bag and slot are optional, but are more efficient if parsing the tooltip is necessary to determine the category.
local function GetBuffItemCategory(itemID, bag, slot)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return "other_consumable"
    end

    if globalDB and type(globalDB.buffAuraByItem) == "table" then
        local normalized = globalDB.buffAuraByItem[tostring(itemID)]
        if type(normalized) == "table" and normalized.category then
            Trace("Category from buffAuraByItem: " .. tostring(normalized.category) .. " " .. ns.Utils.GetDebugItemLabel(itemID))
            return tostring(normalized.category)
        end
    end
    if ns.Fishing.const and type(ns.Fishing.const.knownBuffItems) == "table" then
        local known = ns.Fishing.const.knownBuffItems[tonumber(itemID)]
        if type(known) == "table" and known.category then
            Trace("Category from knownBuffItems: " .. tostring(known.category) .. " " .. ns.Utils.GetDebugItemLabel(itemID))
            return tostring(known.category)
        end
    end

    if ns.Fishing.const and type(ns.Fishing.const.bobberToyItemIDs) == "table" then
        for _, toy in ipairs(ns.Fishing.const.bobberToyItemIDs) do
            local toyItemID = tonumber(type(toy) == "table" and toy.id or toy)
            if toyItemID == numeric then
                return "bobber"
            end
        end
    end

    local result = nil
    local _, itemType, itemSubType, _, _, classID = GetItemInfoInstantSafe(numeric)
    local consumableClassID = rawget(_G, "LE_ITEM_CLASS_CONSUMABLE")
    if classID and consumableClassID and classID ~= consumableClassID then
        return "other_consumable"
    end

    local itemTypeText = type(itemType) == "string" and string.lower(itemType) or ""
    local itemSubTypeText = type(itemSubType) == "string" and string.lower(itemSubType) or ""
    if itemTypeText:find("consumable", 1, true) ~= nil then
        if itemSubTypeText:find("food", 1, true) ~= nil or itemSubTypeText:find("drink", 1, true) ~= nil then
            result = "fooddrink"
            Trace("Category suggested by item info: " .. result .. " " .. ns.Utils.GetDebugItemLabel(itemID))
        elseif itemSubTypeText:find("item enhancement", 1, true) ~= nil
            or itemSubTypeText:find("enchant", 1, true) ~= nil
            or itemSubTypeText:find("weapon", 1, true) ~= nil then
            result = "lure"
            Trace("Category suggested by item info: " .. result .. " " .. ns.Utils.GetDebugItemLabel(itemID))
        end
    end

    if not result and TooltipSuggestsLure(numeric, bag, slot) then
        Trace("Category suggested by tooltip: lure " .. ns.Utils.GetDebugItemLabel(itemID))
        result = "lure"
    end

    -- add to the buffAuraByItem table for future reference
    if result and globalDB and globalDB.buffAuraByItem then
        globalDB.buffAuraByItem = globalDB.buffAuraByItem or {}
        globalDB.buffAuraByItem[tostring(numeric)] = globalDB.buffAuraByItem[tostring(numeric)] or {}
        globalDB.buffAuraByItem[tostring(numeric)].category = result
        return result
    end

    return "other_consumable"
end

function Fishing:IsBuffItemCategory(category, itemID, bag, slot)
    local normalizedCategory = type(category) == "string" and string.lower(category) or nil
    if not normalizedCategory or normalizedCategory == "" then
        Trace("IsBuffItemCategory: invalid category provided: " .. tostring(category) .. " " .. ns.Utils.GetDebugItemLabel(itemID))
        return false
    end

    local itemCategory = GetBuffItemCategory(itemID, bag, slot)
    if not itemCategory or itemCategory == "" then
        Trace("IsBuffItemCategory: unable to determine category for item: " .. ns.Utils.GetDebugItemLabel(itemID))
        return false
    end

    return (normalizedCategory == itemCategory)
end

function Fishing:ResolveRecognizedCategory(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return nil, false
    end

    local known = ns.Fishing.const
        and type(ns.Fishing.const.knownBuffItems) == "table"
        and ns.Fishing.const.knownBuffItems[numeric]
        or nil
    if type(known) == "table" and type(known.category) == "string" and known.category ~= "" then
        return known.category, true
    end

    if ns.Fishing.buff and type(ns.Fishing.buff.GetBuffItemCategory) == "function" then
        local category = GetBuffItemCategory(numeric)
        if category and category ~= "" then
            return category, true
        end
    end

    return nil, false
end
