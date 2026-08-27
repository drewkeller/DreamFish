local addonName, ns = ...
local Addon = ns.Addon
local Fishing = Addon:GetModule("Fishing")

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
    local selectedToyID = profileDB.bobberSelector and tonumber(Addon.addon.bobberSelector:GetText()) or nil
    if not selectedToyID or selectedToyID <= 0 then
        return nil, "Apply Bobber (none)", false
    end

    if Addon:IsCooldownReady(selectedToyID) then
        return selectedToyID, "Apply Bobber", true
    end

    local oversizedEnabled = profileDB.useOversizedBobber
    if oversizedEnabled
        and selectedToyID ~= ns.fishing.const.oversizedBobberItemID
        and Addon:IsToyOwned(ns.fishing.const.oversizedBobberItemID)
        and Addon:IsCooldownReady(ns.fishing.const.oversizedBobberItemID) then
        return ns.fishing.const.oversizedBobberItemID, "Oversize Bobber", true
    end

    return selectedToyID, "Apply Bobber", false
end

local function HasConfiguredBuffItems()
    if type(charDB.buffs) ~= "table" then
        return false
    end
    for _, items in pairs(charDB.buffs) do
        if type(items) ~= "table" then
            return false
        end
        for _, entry in ipairs(items) do
        local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
        if itemID and itemID > 0 and not (type(entry) == "table" and entry.enabled == false) then
            return true
        end
        end
    end
    return false
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
            .. Addon:GetDebugItemLabel(raftDecision.toyID) .. " " .. Addon:GetDebugCooldownText(raftDecision.toyID))
        if raftDecision.swimming then
            raftExclusive = true
            ns.Utils("precast", "Raft needed while swimming; skipping other pre-cast items this click")
        end
    end

    -- Pole
    if (not raftExclusive) and poleDecision.shouldApply then
        InsertEquipItemMacroLine(macroLines, poleDecision.itemID)
        Fishing:Trace("precast", "Configured fishing pole: "
            .. Addon:GetDebugItemLabel(poleDecision.itemID))
    end

    -- Underlight Angler
    if (not raftExclusive) and underlightDecision.shouldEquip then
        InsertEquipItemMacroLine(macroLines, underlightDecision.itemID)
        Fishing:Trace("precast", "Configured Underlight Angler: "
            .. Addon:GetDebugItemLabel(underlightDecision.itemID))
    end

    -- Bobber
    if (not raftExclusive) and (not hasItemUseAction) and bobberDecision.shouldApply then
        InsertUseItemMacroLine(macroLines, bobberDecision.toyID)
        hasItemUseAction = true
        Fishing:Trace("precast", "Configured bobber: "
            .. Addon:GetDebugItemLabel(bobberDecision.toyID) .. " " .. Addon:GetDebugCooldownText(bobberDecision.toyID))
    end

    -- Oversize bobber
    if (not raftExclusive) and (not hasItemUseAction) and oversizedDecision.shouldApply then
        InsertUseItemMacroLine(macroLines, oversizedDecision.toyID)
        hasItemUseAction = true
        Fishing:Trace("precast", "Configured oversized bobber")
    end

    -- Buff item
    if not hasItemUseAction then
        local consumableDecision = ns.precast.GetConsumableUseDecision()
        if consumableDecision.shouldApply then
            InsertUseItemMacroLine(macroLines, consumableDecision.itemID)
            hasItemUseAction = true
            if consumableDecision.category == "lure" then
                table.insert(macroLines, "/use 28") -- apply lure to fishing profession equipment slot
            end
            Fishing:Trace("precast", "Configured due buff (" .. tostring(consumableDecision.category) .. "): "
                .. Addon:GetDebugItemLabel(consumableDecision.itemID) .. " " .. Addon:GetDebugCooldownText(consumableDecision.itemID))
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
