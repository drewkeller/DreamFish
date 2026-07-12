-- DreamFisher - Modular Addon Loader
-- This file orchestrates loading of all addon modules

-- Initialize addon namespace
local addonName = "DreamFisher"
local addon = _G[addonName] or {}
_G[addonName] = addon

-- Create frame for event handling
local frame = CreateFrame("Frame", addonName .. "Frame")
addon.frame = frame
local requireFishingAPI = addon.RequireFishingAPI
local requireAudioAPI = addon.RequireAudioAPI
local requireAlertsAPI = addon.RequireAlertsAPI
local getUIFocusAPI = addon.GetUIFocusAPI

-- Module initialization - these will be populated as modules load
addon.state = addon.state or {}
addon.defaults = addon.defaults or {}
addon.const = addon.const or {}
addon.frames = addon.frames or {}
addon._test = addon._test or {}

-- Export common utilities that other modules need
local function Clamp(value, min, max)
    if value == nil then return min end
    if value < min then return min end
    if value > max then return max end
    return value
end

addon.Clamp = Clamp
addon.DeepCopy = function(value)
    if type(value) ~= "table" then return value end
    local clone = {}
    for k, v in pairs(value) do clone[k] = addon.DeepCopy(v) end
    return clone
end

addon.CopyDefaults = function(source, target)
    for k, v in pairs(source) do
        if target[k] == nil then target[k] = addon.DeepCopy(v) end
    end
end

addon.PrintMessage = function(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF7FFFDADreamFisher|r " .. msg)
    end
end

addon.DebugMessage = function(msg)
    if addon.db and addon.db.debugMode then
        addon.PrintMessage("|cFF9ACDFF[debug]|r " .. tostring(msg))
    end
end

local DebugStateMessage = addon.DebugStateMessage or addon.DebugMessage

local function DebugBagMessage(msg)
    if addon.db and addon.db.debugMode and addon.db.debugBags then
        addon.DebugMessage("[bags] " .. tostring(msg))
    end
end

local function FormatJunkCountsForDebug(counts)
    if type(counts) ~= "table" then
        return "none"
    end

    local entries = {}
    for itemID, count in pairs(counts) do
        if tonumber(count) and tonumber(count) > 0 then
            entries[#entries + 1] = tostring(itemID) .. "=" .. tostring(count)
        end
    end

    table.sort(entries)
    if #entries == 0 then
        return "none"
    end

    return table.concat(entries, ",")
end

_G.BINDING_HEADER_DREAMFISHER = "DreamFisher"
-- Label for CLICK DreamFisherSecureFishingButton:RightButton binding.
-- WoW normalizes click-binding token characters to underscores.
if not _G.BINDING_NAME_CLICK_DreamFisherSecureFishingButton_RightButton then
    _G.BINDING_NAME_CLICK_DreamFisherSecureFishingButton_RightButton = "Trigger Fishing Cast"
 end

-- NOTE: Due to WoW addon architecture, individual module files should be
-- listed in DreamFisher.toc in load order, rather than using dofile().
-- This file serves as a hub for cross-module communication.
--
-- Load order should be:
-- 1. core/init.lua - Initialization and constants
-- 2. core/utils.lua - Utility functions
-- 3. buff/tracking.lua - Aura tracking
-- 4. buff/timing.lua - Buff timing logic
-- 5. buff/management.lua - Buff item management
-- 6. fishing/helpers.lua - Bag/container utilities
-- 7. fishing/casting.lua - World click handler
-- 8. fishing/state.lua - Fishing state frame
-- 9. audio/ducking.lua - Audio focus
-- 10. audio/alerts.lua - Alert displays
-- 11. ui/commands.lua - Slash commands
-- 12. ui/config.lua - Config panel (when created)
--
-- This main file runs last and coordinates addon initialization

-- Addon initialization event
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, name)
    if event ~= "ADDON_LOADED" or name ~= addonName then return end
    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required during addon initialization")
    end
    if not requireAudioAPI then
        error("DreamFisher: RequireAudioAPI helper is required during addon initialization")
    end
    local fishing = requireFishingAPI()
    local audio = requireAudioAPI()
    -- Focus visuals are optional in reduced test/runtime bootstraps.
    local uiFocus = (getUIFocusAPI and getUIFocusAPI()) or addon.uiFocus

    -- Load saved data
    _G[addonName .. "DB"] = _G[addonName .. "DB"] or {}
    addon.db = _G[addonName .. "DB"]
    addon.CopyDefaults(addon.defaults, addon.db)

    if audio and audio.ResumePersistedAudioDuckingState then
        audio.ResumePersistedAudioDuckingState()
    end

    if uiFocus and uiFocus.CreateFocusFadeFrame then
        uiFocus.CreateFocusFadeFrame()
        if uiFocus.RefreshFocusFadeState then
            uiFocus.RefreshFocusFadeState()
        end
    end

    if fishing and fishing.MaybeEquipConfiguredUnderlight then
        fishing.MaybeEquipConfiguredUnderlight("addon-loaded")
    end

    -- Initialize buff config
    if addon.buff and addon.buff.NormalizeBuffConfig then
        addon.buff.NormalizeBuffConfig()
        addon.utils.CheckBuffItemStockWarnings()
    end

    -- Create secure frames
    if fishing then
        fishing.CreateSecureFishingFrame()
        fishing.CreateSecureBuffFrame()
        fishing.CreateFishingStateFrame()
    end

    -- Register slash commands
    if addon.commands then
        addon.commands.RegisterSlashCommands()
    end

    addon.PrintMessage("Loaded! Type /df to configure.")
    self:UnregisterEvent("ADDON_LOADED")
end)

    addon._test.SetDB = function(db)
        addon.db = db or {}
        if addon.CopyDefaults then
            addon.CopyDefaults(addon.defaults, addon.db)
        end
        if addon.buff and addon.buff.NormalizeBuffConfig then
            addon.buff.NormalizeBuffConfig()
        end
    end

-- World right-click handler
local lastRightClickDisabledDebugAt = 0
if WorldFrame then
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if not requireFishingAPI then
            error("DreamFisher: RequireFishingAPI helper is required for world right-click handling")
        end
        local fishing = requireFishingAPI()
        if button == "RightButton" and not InCombatLockdown() then
            if fishing and fishing.IsWorldRightClickActivationPressed then
                if fishing.IsWorldRightClickActivationPressed() then
                    fishing.HandleWorldRightClick()
                elseif addon.db and addon.db.debugMode and addon.db.debugState then
                    local now = (type(GetTime) == "function") and GetTime() or 0
                    if (now - lastRightClickDisabledDebugAt) >= 1.0 then
                        lastRightClickDisabledDebugAt = now
                        if DebugStateMessage then
                            DebugStateMessage("World right click detected but ignored: right-click trigger modes are disabled")
                        end
                    end
                end
            end
        end
    end)

end

-- Loot tracking
local fishingLootBagCheckPendingUntil = 0
local fishingJunkBaselineCounts = nil

local function ContainerNumSlotsCompat(bag)
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    if type(GetContainerNumSlots) == "function" then
        return GetContainerNumSlots(bag) or 0
    end
    return 0
end

local function ContainerItemIDCompat(bag, slot)
    if C_Container and type(C_Container.GetContainerItemID) == "function" then
        return C_Container.GetContainerItemID(bag, slot)
    end
    if type(GetContainerItemID) == "function" then
        return GetContainerItemID(bag, slot)
    end
    return nil
end

local function ContainerItemQualityCompat(bag, slot, itemID)
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if type(info) == "table" and info.quality ~= nil then
            return tonumber(info.quality)
        end
    end

    if type(GetContainerItemInfo) == "function" then
        local info = GetContainerItemInfo(bag, slot)
        if type(info) == "table" and info.quality ~= nil then
            return tonumber(info.quality)
        end
        if type(info) ~= "table" then
            local _, _, _, quality = GetContainerItemInfo(bag, slot)
            if quality ~= nil then
                return tonumber(quality)
            end
        end
    end

    if type(GetItemInfo) == "function" and itemID then
        local _, _, quality = GetItemInfo(itemID)
        if quality ~= nil then
            return tonumber(quality)
        end
    end

    return nil
end

local function ContainerItemCountCompat(bag, slot)
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if type(info) == "table" then
            return tonumber(info.stackCount or info.quantity or 1) or 1
        end
    end

    if type(GetContainerItemInfo) == "function" then
        local info = GetContainerItemInfo(bag, slot)
        if type(info) == "table" then
            return tonumber(info.stackCount or info.quantity or 1) or 1
        end
        if type(info) ~= "table" then
            local _, itemCount = GetContainerItemInfo(bag, slot)
            return tonumber(itemCount) or 1
        end
    end

    return 1
end

local function ContainerPickupItemCompat(bag, slot)
    if C_Container and type(C_Container.PickupContainerItem) == "function" then
        return pcall(C_Container.PickupContainerItem, bag, slot)
    end
    if type(PickupContainerItem) == "function" then
        return pcall(PickupContainerItem, bag, slot)
    end
    return false
end

local function ContainerSplitItemCompat(bag, slot, count)
    if C_Container and type(C_Container.SplitContainerItem) == "function" then
        return pcall(C_Container.SplitContainerItem, bag, slot, count)
    end
    if type(SplitContainerItem) == "function" then
        return pcall(SplitContainerItem, bag, slot, count)
    end
    return false
end

local function GetTrackedBagIDs()
    local ids = {}
    local bagCount = tonumber(NUM_BAG_SLOTS) or 4
    for bag = 0, bagCount do
        ids[#ids + 1] = bag
    end
    if ContainerNumSlotsCompat(5) > 0 then
        ids[#ids + 1] = 5
    end
    return ids
end

local function GetJunkCountsByItemID()
    local counts = {}
    for _, bag in ipairs(GetTrackedBagIDs()) do
        local slotCount = ContainerNumSlotsCompat(bag)
        for slot = 1, slotCount do
            local itemID = ContainerItemIDCompat(bag, slot)
            if itemID then
                local quality = ContainerItemQualityCompat(bag, slot, itemID)
                if quality == 0 then
                    local stackCount = math.max(1, ContainerItemCountCompat(bag, slot))
                    counts[itemID] = (counts[itemID] or 0) + stackCount
                end
            end
        end
    end
    return counts
end

local function CaptureFishingJunkBaseline()
    if addon.db and addon.db.throwAwayJunk then
        fishingJunkBaselineCounts = GetJunkCountsByItemID()
        DebugBagMessage("Captured fishing junk baseline: " .. FormatJunkCountsForDebug(fishingJunkBaselineCounts))
    else
        fishingJunkBaselineCounts = nil
        DebugBagMessage("Skipped fishing junk baseline capture: throwAwayJunk disabled")
    end
end

local function ClearFishingJunkBaseline()
    if fishingJunkBaselineCounts then
        DebugBagMessage("Clearing fishing junk baseline: " .. FormatJunkCountsForDebug(fishingJunkBaselineCounts))
    end
    fishingJunkBaselineCounts = nil
end

addon.CaptureFishingJunkBaseline = CaptureFishingJunkBaseline
addon.ClearFishingJunkBaseline = ClearFishingJunkBaseline
addon._test.GetFishingJunkBaselineCounts = function()
    if not fishingJunkBaselineCounts then
        return nil
    end
    return addon.DeepCopy(fishingJunkBaselineCounts)
end

local function TryDiscardNewlyLootedJunkFromBags()
    if not (addon.db and addon.db.throwAwayJunk) then
        DebugBagMessage("Skipping junk discard: throwAwayJunk disabled")
        return false
    end
    if not fishingJunkBaselineCounts then
        DebugBagMessage("Skipping junk discard: no fishing junk baseline recorded")
        return false
    end

    local currentCounts = GetJunkCountsByItemID()
    local excessByItemID = {}
    local hasExcess = false
    for itemID, currentCount in pairs(currentCounts) do
        local baseline = tonumber(fishingJunkBaselineCounts[itemID]) or 0
        local excess = (tonumber(currentCount) or 0) - baseline
        if excess > 0 then
            excessByItemID[itemID] = excess
            hasExcess = true
        end
    end

    DebugBagMessage("Junk discard counts: baseline=" .. FormatJunkCountsForDebug(fishingJunkBaselineCounts)
        .. " current=" .. FormatJunkCountsForDebug(currentCounts)
        .. " excess=" .. FormatJunkCountsForDebug(excessByItemID))

    if not hasExcess then
        DebugBagMessage("No newly looted junk detected during pending discard window")
        return false
    end

    DebugBagMessage("Junk discard would be attempted, but DeleteCursorItem is protected outside a secure hardware event; skipping actual delete")
    DebugBagMessage("Junk discard counts: baseline=" .. FormatJunkCountsForDebug(fishingJunkBaselineCounts)
        .. " current=" .. FormatJunkCountsForDebug(currentCounts)
        .. " excess=" .. FormatJunkCountsForDebug(excessByItemID))

    return false
end

local function IsPendingLootBagWindow()
    local now = (type(GetTime) == "function") and GetTime() or 0
    return fishingLootBagCheckPendingUntil > 0 and now <= fishingLootBagCheckPendingUntil
end

local function ClearPendingLootBagWindow()
    fishingLootBagCheckPendingUntil = 0
    ClearFishingJunkBaseline()
end

local function QueuePendingLootBagWindow(seconds)
    local now = (type(GetTime) == "function") and GetTime() or 0
    fishingLootBagCheckPendingUntil = now + (seconds or 2)
end

local function ExpirePendingLootBagWindowIfNeeded()
    local now = (type(GetTime) == "function") and GetTime() or 0
    if fishingLootBagCheckPendingUntil > 0 and now > fishingLootBagCheckPendingUntil then
        fishingLootBagCheckPendingUntil = 0
    end
end

local function TryHandlePostLootJunkDiscard()
    ExpirePendingLootBagWindowIfNeeded()
    if not IsPendingLootBagWindow() then
        DebugBagMessage("Skipping post-loot junk discard: pending window inactive")
        ClearFishingJunkBaseline()
        return
    end
    local didDiscard = TryDiscardNewlyLootedJunkFromBags()
    if didDiscard then
        ClearPendingLootBagWindow()
    else
        DebugBagMessage("Post-loot junk discard deferred: pending window remains active")
    end
end

local junkBaselineTracker = CreateFrame("Frame")
junkBaselineTracker:RegisterEvent("UNIT_SPELLCAST_START")
junkBaselineTracker:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
junkBaselineTracker:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if unit ~= "player" then
        return
    end
    local numericSpellID = tonumber(spellID)
    local fishingSpellID = addon.const and tonumber(addon.const.fishingSpellID) or nil
    local fishingChannelSpellID = addon.const and tonumber(addon.const.fishingChannelSpellID) or nil
    if numericSpellID ~= fishingSpellID and numericSpellID ~= fishingChannelSpellID then
        return
    end
    CaptureFishingJunkBaseline()
end)

local lootTracker = CreateFrame("Frame")
lootTracker:RegisterEvent("LOOT_READY")
lootTracker:RegisterEvent("LOOT_CLOSED")
lootTracker:RegisterEvent("BAG_UPDATE")
lootTracker:RegisterEvent("UI_INFO_MESSAGE")
lootTracker:SetScript("OnEvent", function(_, event, ...)
    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for loot tracker")
    end
    local fishing = requireFishingAPI()

    if event == "LOOT_READY" then
        if not (fishing and fishing.ApplySessionState and fishing.IsLootReadySessionState) then
            error("DreamFisher: ApplySessionState and IsLootReadySessionState are required for loot-ready handling")
        end
        local isLootReadySession = fishing.IsLootReadySessionState()
        if isLootReadySession and not fishingJunkBaselineCounts then
            DebugBagMessage("LOOT_READY fallback baseline capture triggered")
            CaptureFishingJunkBaseline()
        elseif isLootReadySession then
            DebugBagMessage("LOOT_READY preserving earlier junk baseline")
        end
        if isLootReadySession and not (fishing.IsSessionState and fishing.IsSessionState("LOOTING")) then
            fishing.ApplySessionState("LOOTING", "loot-ready")
        end
    elseif event == "LOOT_CLOSED" then
        if not (fishing and fishing.IsSessionState) then
            error("DreamFisher: IsSessionState is required for loot-close handling")
        end
        if fishing.IsSessionState("LOOTING") then
            DebugBagMessage("Fishing loot in progress ended")
            if not (fishing and fishing.StartLingerThenCloseSession) then
                error("DreamFisher: StartLingerThenCloseSession is required for loot close handling")
            end
            fishing.StartLingerThenCloseSession(
                "loot-closed-starting-linger",
                "loot-closed",
                {
                restoreAutoLoot = true,
                poleReason = "loot-closed",
                }
            )
            QueuePendingLootBagWindow(2)
            DebugBagMessage("Queued bag-threshold check for BAG_UPDATE_DELAYED")
        end
        addon.state.lastBagWarning = 0
    elseif event == "BAG_UPDATE" then
        TryHandlePostLootJunkDiscard()
        if not (fishing and fishing.IsFishingActiveSessionState) then
            error("DreamFisher: IsFishingActiveSessionState is required for bag-update handling")
        end
        if fishing.IsFishingActiveSessionState() and addon.utils then
            addon.utils.CheckBagSpace()
        end
        if addon.utils then addon.utils.CheckBuffItemStockWarnings() end
        if addon.frames.config and addon.frames.config.buffItemControls then
            for i, control in ipairs(addon.frames.config.buffItemControls) do
                if control.itemBox and control.itemBox.UpdateCountDisplay then
                    control.itemBox:UpdateCountDisplay()
                end
            end
        end
    elseif event == "UI_INFO_MESSAGE" then
        local arg1, arg2 = ...
        local errType = arg1
        local msg = nil
        if type(arg2) == "string" and arg2 ~= "" then
            msg = arg2
        elseif type(arg1) == "string" and arg1 ~= "" then
            msg = arg1
        else
            msg = ""
        end

        local noFishHooked = (tonumber(errType) == 413)

        if noFishHooked then
            local now = (type(GetTime) == "function") and GetTime() or 0
            local startedAt = tonumber(addon.state.fishingStartTime) or 0
            local elapsed = (startedAt > 0 and now >= startedAt) and (now - startedAt) or 0
            if not (fishing and fishing.StartLingerThenCloseSession) then
                error("DreamFisher: StartLingerThenCloseSession is required for no-fish-hooked handling")
            end
            fishing.StartLingerThenCloseSession(
                "ui-info-no-fish-hooked-starting-linger",
                "ui-info-no-fish-hooked-close",
                { restoreAutoLoot = true, poleReason = "ui-info-no-fish-hooked" }
            )
            if DebugStateMessage then
                DebugStateMessage("Detected fish-hook info message (413); cleared fishing/hooked state"
                    .. " elapsed=" .. string.format("%.3f", elapsed)
                    .. " msg=" .. tostring(msg)
                    .. " audioDucked=" .. tostring(addon.state.savedFishingAudioCVars ~= nil)
                    .. " interactOverrideActive=" .. tostring(addon.state.interactOverrideActive))
            end
        end
    end
end)

-- Bag monitoring
local bagMonitor = CreateFrame("Frame")
bagMonitor:RegisterEvent("PLAYER_ENTERING_WORLD")
bagMonitor:RegisterEvent("BAG_UPDATE_DELAYED")
bagMonitor:SetScript("OnEvent", function(_, event)
    if addon.utils then addon.utils.CheckBagSpace() end
    if event == "BAG_UPDATE_DELAYED" and addon.utils and addon.alerts then
        if not requireAlertsAPI then
            error("DreamFisher: RequireAlertsAPI helper is required for bag monitoring")
        end
        local alerts = requireAlertsAPI()
        local now = (type(GetTime) == "function") and GetTime() or 0
        if fishingLootBagCheckPendingUntil > 0 then
            if now <= fishingLootBagCheckPendingUntil then
                TryHandlePostLootJunkDiscard()
                local shouldCheckRegular = addon.db and addon.db.bagAlerts
                local shouldCheckReagent = addon.db and addon.db.reagentBagAlerts
                local threshold = (addon.db and addon.db.bagAlertsThreshold) or addon.defaults.bagAlertsThreshold
                local reagentThreshold = (addon.db and addon.db.reagentBagAlertsThreshold) or addon.defaults.reagentBagAlertsThreshold
                local regularFree = shouldCheckRegular and addon.utils.GetFreeBagSlots(false) or nil
                local reagentFree = shouldCheckReagent and addon.utils.GetFreeReagentBagSlots() or nil
                local isRegularLow = regularFree ~= nil and regularFree <= threshold
                local isReagentLow = reagentFree ~= nil and reagentFree <= reagentThreshold
                DebugBagMessage("Low bag threshold set to bags=" .. tostring(threshold)
                    .. " reagent=" .. tostring(reagentThreshold))
                DebugBagMessage("BAG_UPDATE_DELAYED slots: regularFree=" .. tostring(regularFree) .. ", reagentFree=" .. tostring(reagentFree))
                if isRegularLow or isReagentLow then
                    DebugBagMessage("Bag space low after loot close: regularFree=" .. tostring(regularFree) .. ", reagentFree=" .. tostring(reagentFree))
                    if alerts and alerts.ShowBagFullAlert then
                        alerts.ShowBagFullAlert()
                    end
                    ClearPendingLootBagWindow()
                else
                    DebugBagMessage("Bag space not low yet; waiting for next BAG_UPDATE_DELAYED")
                end
            else
                DebugBagMessage("Bag-threshold check window expired")
                ClearPendingLootBagWindow()
            end
        end
    end
end)

-- Aura tracking
local auraTracker = CreateFrame("Frame")
auraTracker:RegisterEvent("UNIT_AURA")
auraTracker:SetScript("OnEvent", function(_, _, unit)
    if unit ~= "player" then return end
    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for aura tracking")
    end
    if not requireAlertsAPI then
        error("DreamFisher: RequireAlertsAPI helper is required for aura tracking")
    end
    local fishing = requireFishingAPI()
    local alerts = requireAlertsAPI()

    if addon.buff then addon.buff.UpdatePendingBuffObservation() end

    if fishing and fishing.HasPatientlyRewardedAura then
        local hasAura = fishing.HasPatientlyRewardedAura()
        if hasAura and not addon.state.patientAuraActive then
            addon.state.patientAuraActive = true
            if alerts and alerts.ShowPatientTreasureAlert then
                alerts.ShowPatientTreasureAlert("Patiently Rewarded")
            end
        elseif not hasAura then
            addon.state.patientAuraActive = false
        end
    end
end)

-- UI management
function addon:ToggleUI()
    if not addon.frames.config then
        if addon.config and addon.config.CreateConfigPanel then
            addon.frames.config = addon.config.CreateConfigPanel()
        else
            return
        end
    end
    if addon.frames.config:IsShown() then
        addon.frames.config:Hide()
    else
        if addon.config and addon.config.UpdateConfigUI then
            addon.config.UpdateConfigUI()
        end
        addon.frames.config:Show()
    end
end

function addon:SaveConfig()
    if addon.config and addon.config.SaveConfig then
        addon.config.SaveConfig()
    end
end
