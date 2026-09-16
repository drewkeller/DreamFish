local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

local globalDB, profileDB, charDB
Fishing:RegisterOnModuleInitialize(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

Fishing:RegisterTraceSource("precast")

local function Trace(msg)
    Fishing:Trace("precast", msg)
end

local RAFT_SHAPESHIFT_ERROR = "Raft-like items cannot be cast on a shape-shifted target"
local lastRaftShapeshiftAlertAt

local function ShowRaftShapeshiftError()
    local now = (type(GetTime) == "function") and GetTime() or 0
    if lastRaftShapeshiftAlertAt and (now - lastRaftShapeshiftAlertAt) < 2 then
        return
    end
    lastRaftShapeshiftAlertAt = now
    Addon:Alert(ns.SystemColor.RED, RAFT_SHAPESHIFT_ERROR)
end

function Fishing:ApplyRaft()
    local toyID = tonumber(profileDB.selectedRaftToy)
    if toyID and toyID > 0 and ns.Utils.IsToyOwned(toyID) then
        if ns.precast.IsRaftBlockedByShapeshift() then
            ShowRaftShapeshiftError()
            return
        end
        UseToyByName(toyID)
    end
end

function Fishing:ApplyBobber()
    local toyID = tonumber(profileDB.selectedBobberToy)
    if toyID and toyID > 0 and ns.Utils.IsToyOwned(toyID) then
        UseToyByName(toyID)
    end
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
        -- Use [nochanneling] to dynamically block the fishing cast if casting a buff item
        if not raftExclusiveWhileSwimming then
            table.insert(macroLines, "/cast [nochanneling] Fishing")
        end
        fishingFrame:SetAttribute("type", "macro")
        fishingFrame:SetAttribute("macrotext", table.concat(macroLines, "\n"))
        fishingFrame:SetAttribute("spell", nil)
        fishingFrame:SetAttribute("dreamfish_precast_action", true)
        if raftExclusiveWhileSwimming then
            Trace("Configured as raft-only pre-cast")
        else
            Trace("Configured with pre-cast items on same-click cast")
        end
        return true
    end

    fishingFrame:SetAttribute("type", "spell")
    fishingFrame:SetAttribute("spell", "Fishing")
    fishingFrame:SetAttribute("macrotext", nil)
    fishingFrame:SetAttribute("dreamfish_precast_action", nil)
    return true
end

local function InsertUseItemMacroLine(macroLines, itemID)
    local line = "/use item:" .. tostring(itemID)
    -- Guard against the same item being queued twice in one macro (e.g. misconfigured across categories)
    for _, existing in ipairs(macroLines) do
        if existing == line then
            return false
        end
    end
    table.insert(macroLines, line)
    return true
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
        Trace("Armed raft: "
            .. ns.Utils.GetDebugItemLabel(raftDecision.toyID) .. " " .. ns.Utils.GetDebugCooldownText(raftDecision.toyID))
        if raftDecision.swimming then
            raftExclusive = true
            Trace("Raft needed while swimming; skipping other pre-cast items this click")
        end
    elseif raftDecision.blockedByShapeshift and raftDecision.swimming then
        ShowRaftShapeshiftError()
    end

    if not raftExclusive then
        -- Bobber
        local bobberDecision = ns.precast.GetBobberUseDecision()
        if (not hasItemUseAction) and bobberDecision.shouldApply then
            InsertUseItemMacroLine(macroLines, bobberDecision.toyID)
            hasItemUseAction = true
            Trace("Armed bobber: " .. ns.Utils.GetDebugItemLabel(bobberDecision.toyID))
        end

        -- Oversize bobber
        local oversizedDecision = ns.precast.GetOversizedBobberDecision()
        if (not hasItemUseAction) and oversizedDecision.shouldApply then
                InsertUseItemMacroLine(macroLines, oversizedDecision.toyID)
                hasItemUseAction = true
                Trace("Armed oversized bobber: " .. ns.Utils.GetDebugItemLabel(oversizedDecision.toyID))
        end

        -- Buff item
        -- If an instant background pole swap is actively loading, exit early and skip consumable queue loops!
        if self.state.isEquippingPrimaryPole then
            Trace("Pole swap in progress; skipping consumable pre-cast checks this click")
            local configured = FinalizeSecureFishingAction(Fishing.clickFrame, macroLines, raftExclusive, hasItemUseAction)
            return configured
        end

        local consumableDecision = ns.precast.GetConsumableUseDecision(self, hasItemUseAction)
        if consumableDecision.shouldApply then
            for _, consumable in ipairs(consumableDecision.items or {}) do
                if (InsertUseItemMacroLine(macroLines, consumable.itemID)) then
                    Trace("Armed due buff: " .. ns.Utils.GetDebugItemLabel(consumable.itemID) .. " (" .. tostring(consumable.category) .. ")")
                end
                hasItemUseAction = true
                if consumable.category == "lure" then
                    table.insert(macroLines, "/use 28")
                end
            end
        else
            Fishing.clickFrame:SetAttribute("dreamfisher_duebuff", "")
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
