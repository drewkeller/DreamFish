local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local globalDB, profileDB, charDB
local function Initialize()
    globalDB = ns.FishingDB.global
    profileDB = ns.FishingDB.profile
    charDB = ns.FishingDB.char
end
ns.FishingInitializers = ns.FishingInitializers or {}
table.insert(ns.FishingInitializers, Initialize)

Fishing:RegisterTraceSource("precast")

local DUE_BUFF_CATEGORY_ORDER = { "fooddrink", "lure", "bait", "bobber", "other_consumable" }

function Fishing:ResolveBobberApplyAction()
    local selectedToyID = profileDB.bobberSelector and tonumber(DreamFish.addon.bobberSelector:GetText()) or nil
    if not selectedToyID or selectedToyID <= 0 then
        return nil, "Apply Bobber (none)", false
    end

    if DreamFish:IsItemReadyForUse(selectedToyID) then
        return selectedToyID, "Apply Bobber", true
    end

    local oversizedEnabled = profileDB.useOversizedBobber
    if oversizedEnabled
        and selectedToyID ~= ns.fishing.const.oversizedBobberItemID
        and DreamFish:IsToyOwned(ns.fishing.const.oversizedBobberItemID)
        and DreamFish:IsItemReadyForUse(ns.fishing.const.oversizedBobberItemID) then
        return ns.fishing.const.oversizedBobberItemID, "Oversize Bobber", true
    end

    return selectedToyID, "Apply Bobber", false
end

local function HasConfiguredBuffItems()
    if type(charDB.buffItems) ~= "table" then
        return false
    end
    for _, entry in ipairs(charDB.buffItems) do
        local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
        if itemID and itemID > 0 and not (type(entry) == "table" and entry.enabled == false) then
            return true
        end
    end
    return false
end

local function HasAnyActiveBaitAura()
    for _, known in pairs(ns.fishing.const.knownBuffItems) do
        local spellID = tonumber(known.spellID)
        if known.category == "bait" and spellID > 0 then
            local aura = Fishing:GetAuraBySpellID(spellID)
            if aura and aura.expirationTime and aura.expirationTime > 0 then
                return true
            end
        end
    end

    return false
end

-- local function GetNextReadyDueBuffItemForCategory(category, excludedBuffItemIDs)
--     local hadUnavailableDueBuff = false
--     while true do
--         local candidateItemID, dueStatus = GetNextDueBuffItem(true, excludedBuffItemIDs, category)
--         if not candidateItemID then
--             hadUnavailableDueBuff = (dueStatus == "due_unavailable") or hadUnavailableDueBuff
--             return nil, hadUnavailableDueBuff
--         end
--         if DreamFish:IsItemReadyForUse(candidateItemID) then
--             return candidateItemID, hadUnavailableDueBuff
--         end
--         -- DebugBuffMessage("Skipping due buff on cooldown this click: "
--         --     .. GetDebugItemLabel(candidateItemID) .. " " .. GetDebugCooldownText(candidateItemID))
--         excludedBuffItemIDs[candidateItemID] = true
--     end
-- end

GetNextReadyDueBuffItem = function(seedExcludedBuffItemIDs)
    if not HasConfiguredBuffItems() then
        return nil, false, nil
    end

    local excludedBuffItemIDs = seedExcludedBuffItemIDs or {}
    local hadUnavailableDueBuff = false

    -- for _, category in ipairs(DUE_BUFF_CATEGORY_ORDER) do
    --     if category == "bait" and HasAnyActiveBaitAura() then
    --         DreamFish:Trace("buffs", "Skipping bait category pass: active bait aura detected")
    --     else
    --         local candidateItemID, unavailableInCategory = GetNextReadyDueBuffItemForCategory(category, excludedBuffItemIDs)
    --         hadUnavailableDueBuff = hadUnavailableDueBuff or unavailableInCategory
    --         if candidateItemID then
    --             return candidateItemID, hadUnavailableDueBuff, category
    --         end
    --     end
    -- end

    return nil, hadUnavailableDueBuff, nil
end

local function FinalizeSecureFishingAction(fishingFrame, macroLines, raftExclusiveWhileSwimming, hasConsumableAction)
    if #macroLines > 0 then
        local castArmed = (not raftExclusiveWhileSwimming) and (not hasConsumableAction)
        if castArmed then
            table.insert(macroLines, "/cast Fishing")
        end
        fishingFrame:SetAttribute("type", "macro")
        fishingFrame:SetAttribute("macrotext", table.concat(macroLines, "\n"))
        fishingFrame:SetAttribute("spell", nil)
        if raftExclusiveWhileSwimming then
            Fishing:Trace("precast", "Configured as raft-only pre-cast")
        elseif not castArmed then
            Fishing:Trace("precast", "Configured with pre-cast item usage; cast not armed yet")
        else
            Fishing:Trace("precast", "Configured with pre-cast items on same-click cast")
        end
        return true
    end

    fishingFrame:SetAttribute("type", "spell")
    fishingFrame:SetAttribute("spell", "Fishing")
    fishingFrame:SetAttribute("macrotext", nil)
    return true
end

local function InsertUseItemMacroLine(macroLines, itemID)
    local line = "/use item:" .. tostring(itemID)
    table.insert(macroLines, line)
end

local function InsertEquipItemMacroLine(macroLines, itemID)
    local line = "/equip item:" .. tostring(itemID)
    table.insert(macroLines, line)
end

ConfigureFishingClickAction = function()
    local raftDecision = ns.precast.GetRaftUseDecision()
    local poleDecision = ns.precast.GetSelectedFishingPoleDecision()
    local underlightDecision = ns.precast.GetUnderlightAnglerEquipDecision()
    local bobberDecision = ns.precast.GetBobberUseDecision()
    local oversizedDecision = ns.precast.GetOversizedBobberDecision()
    local macroLines = {}

    local hasItemUseAction = false
    local raftExclusive = false

    -- Raft
    if raftDecision.shouldApply then
        InsertUseItemMacroLine(macroLines, raftDecision.toyID)
        hasItemUseAction = true
        Fishing:Trace("precast", "Configured raft: "
            .. DreamFish:GetDebugItemLabel(raftDecision.toyID) .. " " .. DreamFish:GetDebugCooldownText(raftDecision.toyID))
        if raftDecision.swimming then
            raftExclusive = true
            DreamFish:Trace("precast", "Raft needed while swimming; skipping other pre-cast items this click")
        end
    end

    -- Pole
    if (not raftExclusive) and poleDecision.shouldApply then
        InsertEquipItemMacroLine(macroLines, poleDecision.itemID)
        Fishing:Trace("precast", "Configured fishing pole: "
            .. DreamFish:GetDebugItemLabel(poleDecision.itemID))
    end

    -- Underlight Angler
    if (not raftExclusive) and underlightDecision.shouldEquip then
        InsertEquipItemMacroLine(macroLines, underlightDecision.itemID)
        Fishing:Trace("precast", "Configured Underlight Angler: "
            .. DreamFish:GetDebugItemLabel(underlightDecision.itemID))
    end

    -- Bobber
    if (not raftExclusive) and (not hasItemUseAction) and bobberDecision.shouldApply then
        InsertUseItemMacroLine(macroLines, bobberDecision.toyID)
        hasItemUseAction = true
        Fishing:Trace("precast", "Configured bobber: "
            .. DreamFish:GetDebugItemLabel(bobberDecision.toyID) .. " " .. DreamFish:GetDebugCooldownText(bobberDecision.toyID))
    end

    -- Oversize bobber
    if (not raftExclusive) and (not hasItemUseAction) and oversizedDecision.shouldApply then
        InsertUseItemMacroLine(macroLines, oversizedDecision.toyID)
        hasItemUseAction = true
        Fishing:Trace("precast", "Configured oversized bobber")
    end

    -- Buff item
    local dueBuffItemID, dueBuffCategory = nil, nil
    if not hasItemUseAction then
        dueBuffItemID, dueBuffCategory = GetNextCastableDueBuffItem()
        if dueBuffItemID then
            InsertUseItemMacroLine(macroLines, dueBuffItemID)
            hasItemUseAction = true
            if dueBuffCategory == "lure" then
                table.insert(macroLines, "/use 28") -- apply lure to fishing profession equipment slot
            end
            Fishing:Trace("precast", "Configured due buff (" .. tostring(dueBuffCategory) .. "): "
                .. DreamFish:GetDebugItemLabel(dueBuffItemID) .. " " .. DreamFish:GetDebugCooldownText(dueBuffItemID))
        end
    else
        Fishing.clickFrame:SetAttribute("dreamfisher_duebuff", nil)
    end

    local configured = FinalizeSecureFishingAction(
        Fishing.clickFrame,
        macroLines,
        raftExclusive,
        hasItemUseAction
    )

    return configured
end

ns.precast.ConfigureFishingClickAction = ConfigureFishingClickAction
