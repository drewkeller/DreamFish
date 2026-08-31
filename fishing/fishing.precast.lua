local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

local globalDB, profileDB, charDB
Fishing:RegisterInitializer(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

Fishing:RegisterTraceSource("precast")

local function Trace(msg)
    Fishing:Trace("precast", msg)
end

local DUE_BUFF_CATEGORY_ORDER = { "fooddrink", "lure", "bait", "bobber", "other_consumable" }

function Fishing:ResolveBobberApplyAction()
    local selectedToyID = profileDB.bobberSelector and tonumber(Addon.addon.bobberSelector:GetText()) or nil
    if not selectedToyID or selectedToyID <= 0 then
        return nil, "Apply Bobber (none)", false
    end

    if ns.Utils.IsCooldownReady(selectedToyID) then
        return selectedToyID, "Apply Bobber", true
    end

    local oversizedEnabled = profileDB.useOversizedBobber
    if oversizedEnabled
        and selectedToyID ~= ns.Fishing.const.oversizedBobberItemID
        and ns.Utils.IsToyOwned(ns.Fishing.const.oversizedBobberItemID)
        and ns.Utils.IsCooldownReady(ns.Fishing.const.oversizedBobberItemID) then
        return ns.Fishing.const.oversizedBobberItemID, "Oversize Bobber", true
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
            Trace("Configured as raft-only pre-cast")
        elseif not castArmed then
            Trace("Configured with pre-cast item usage; cast not armed yet")
        else
            Trace("Configured with pre-cast items on same-click cast")
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

local function ConfigureFishingClickAction(self)
    --local underlightDecision = ns.precast.GetUnderlightAnglerEquipDecision()
    local macroLines = {}

    local hasItemUseAction = false
    local raftExclusive = false

    -- Raft
    local raftDecision = ns.precast.GetRaftUseDecision(self)
    if raftDecision.shouldApply then
        InsertUseItemMacroLine(macroLines, raftDecision.toyID)
        hasItemUseAction = true
        Trace("Configured raft: "
            .. ns.Utils.GetDebugItemLabel(raftDecision.toyID) .. " " .. ns.Utils.GetDebugCooldownText(raftDecision.toyID))
        if raftDecision.swimming then
            raftExclusive = true
            Trace("Raft needed while swimming; skipping other pre-cast items this click")
        end
    end

    if not raftExclusive then
        -- Bobber
        local bobberDecision = ns.precast.GetBobberUseDecision()
        if (not hasItemUseAction) and bobberDecision.shouldApply then
            InsertUseItemMacroLine(macroLines, bobberDecision.toyID)
            hasItemUseAction = true
            Trace("Configured bobber: "
                .. ns.Utils.GetDebugItemLabel(bobberDecision.toyID) .. " " .. ns.Utils.GetDebugCooldownText(bobberDecision.toyID))
        end

        -- Oversize bobber
        local oversizedDecision = ns.precast.GetOversizedBobberDecision()
        if (not hasItemUseAction) and oversizedDecision.shouldApply then
                InsertUseItemMacroLine(macroLines, oversizedDecision.toyID)
                hasItemUseAction = true
                Trace("Configured oversized bobber: "
                    .. ns.Utils.GetDebugItemLabel(oversizedDecision.toyID) .. " " .. ns.Utils.GetDebugCooldownText(oversizedDecision.toyID))
        end

        -- Buff item
        if not hasItemUseAction then
            local consumableDecision = ns.precast.GetConsumableUseDecision(self)
            if consumableDecision.shouldApply then
                ns.Utils.Print("Applying due buff: " .. ns.Utils.GetDebugItemLabel(consumableDecision.itemID) .. " (" .. tostring(consumableDecision.category) .. ")")
                InsertUseItemMacroLine(macroLines, consumableDecision.itemID)
                hasItemUseAction = true
                if consumableDecision.category == "lure" then
                    table.insert(macroLines, "/use 28") -- apply lure to fishing profession equipment slot
                end
                Trace("Configured due buff (" .. tostring(consumableDecision.category) .. "): "
                    .. ns.Utils.GetDebugItemLabel(consumableDecision.itemID) .. " " .. ns.Utils.GetDebugCooldownText(consumableDecision.itemID))
            end
        else
            Fishing.clickFrame:SetAttribute("dreamfisher_duebuff", nil)
        end

        -- Pole
        if not hasItemUseAction then
            local poleDecision = ns.precast.GetSelectedFishingPoleDecision()
            if poleDecision.shouldApply then
                InsertEquipItemMacroLine(macroLines, poleDecision.itemID)
                Trace("Configured fishing pole: "
                    .. ns.Utils.GetDebugItemLabel(poleDecision.itemID))
            end
        end
    end

    local configured = FinalizeSecureFishingAction(
        Fishing.clickFrame,
        macroLines,
        raftExclusive,
        hasItemUseAction
    )

    return configured
end

ns.Fishing.ConfigureFishingClickAction = ConfigureFishingClickAction
