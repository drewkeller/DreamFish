-- DreamFish - Modular Addon Loader
-- This file orchestrates loading of all addon modules

-- Initialize addon namespace
local addonName = "DreamFish"
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

local function NormalizeLootConfig(db)
    if type(db) ~= "table" then
        return
    end

    if db.autoLoot and db.managedLoot then
        db.autoLoot = false
    end

    local delay = tonumber(db.lootDelay)
    if not delay then
        delay = tonumber(addon.defaults and addon.defaults.lootDelay) or 0.5
    end
    db.lootDelay = addon.Clamp(delay, 0, 5)
end

addon.PrintMessage = function(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF7FFFDADreamFish|r " .. msg)
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
        addon.DebugMessage("|cFF9ACDFF[bags]|r " .. tostring(msg))
    end
end

local function DebugLootMessage(msg)
    if addon.db and addon.db.debugMode and addon.db.debugLoot then
        addon.DebugMessage("|cFF9ACDFF[loot]|r " .. tostring(msg))
    end
end


_G.BINDING_HEADER_DREAMFISHER = "DreamFish"
-- Label for CLICK DreamFishSecureFishingButton:RightButton binding.
-- WoW normalizes click-binding token characters to underscores.
if not _G.BINDING_NAME_CLICK_DreamFishSecureFishingButton_RightButton then
    _G.BINDING_NAME_CLICK_DreamFishSecureFishingButton_RightButton = "Trigger Fishing Cast"
 end

-- NOTE: Due to WoW addon architecture, individual module files should be
-- listed in DreamFish.toc in load order, rather than using dofile().
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
        error("DreamFish: RequireFishingAPI helper is required during addon initialization")
    end
    if not requireAudioAPI then
        error("DreamFish: RequireAudioAPI helper is required during addon initialization")
    end
    local fishing = requireFishingAPI()
    local audio = requireAudioAPI()
    -- Focus visuals are optional in reduced test/runtime bootstraps.
    local uiFocus = (getUIFocusAPI and getUIFocusAPI()) or addon.uiFocus

    -- Load saved data
    _G[addonName .. "DB"] = _G[addonName .. "DB"] or {}
    addon.db = _G[addonName .. "DB"]
    addon.CopyDefaults(addon.defaults, addon.db)
    NormalizeLootConfig(addon.db)

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
        NormalizeLootConfig(addon.db)
        if addon.buff and addon.buff.NormalizeBuffConfig then
            addon.buff.NormalizeBuffConfig()
        end
    end

-- World right-click handler
local lastRightClickDisabledDebugAt = 0
if WorldFrame then
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if not requireFishingAPI then
            error("DreamFish: RequireFishingAPI helper is required for world right-click handling")
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
local function CreateLootItemInfo(slot, icon, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin)
    -- Compatibility: some clients/mocks return quality as the 4th result for item slots.
    if quality == nil and type(currencyID) == "number" and currencyID >= 0 and currencyID <= 7 then
        quality = currencyID
        currencyID = nil
    end
    DebugLootMessage("Got loot info for slot " .. tostring(slot) .. ": name=" .. tostring(name)
        .. " quantity=" .. tostring(quantity)
        .. " currencyID=" .. tostring(currencyID)
        .. " quality=" .. tostring(quality)
        .. " locked=" .. tostring(locked)
        .. " isQuestItem=" .. tostring(isQuestItem)
        .. " questID=" .. tostring(questID)
        .. " isActive=" .. tostring(isActive)
        .. " isCoin=" .. tostring(isCoin))
    return {
        slot = slot,
        icon = icon,
        name = name,
        quantity = quantity,
        currencyID = currencyID,
        -- Modern clients may not return quality directly from GetLootSlotInfo.
        quality = tonumber(quality),
        locked = locked,
        isQuestItem = isQuestItem,
        questID = questID,
        isActive = isActive,
        isCoin = isCoin,
        itemID = nil,
        itemLink = nil,
    }
end

local function GetLootItemInfo(slot)
    if type(GetLootSlotInfo) ~= "function" then
        return nil
    end

    local info = CreateLootItemInfo(slot, GetLootSlotInfo(slot))


    -- Parse the itemID from the itemLink's tooltip
    -- currency does not have itemID or link
    if not info.currencyID and not info.isCoin then
        --local slotType = (type(GetLootSlotType) == "function") and tonumber(GetLootSlotType(slot)) or nil
        if type(GetLootSlotLink) == "function" then
            info.itemLink = GetLootSlotLink(slot)
            if info.itemLink then
                info.itemID = tonumber(string.match(info.itemLink, "item:(%d+)"))
            end
        end
    end

    return info
end

local function ShouldAutoLootItem(lootItemInfo)
    -- Junk items have quality 0 or less; we want to auto-loot them if the user has disabled junk skipping,
    -- but skip them if the user has enabled junk skipping.
    local isJunk = lootItemInfo.quality ~= nil and lootItemInfo.quality <= 0
    if isJunk then
        DebugLootMessage("Item in slot " .. tostring(lootItemInfo.slot) .. " is junk")
    end
    if isJunk and addon.db and addon.db.throwAwayJunk then
        return false
    end
    if lootItemInfo.locked then
        DebugLootMessage("Item in slot " .. tostring(lootItemInfo.slot) .. " is locked")
        return false
    end
    return true
end

local function LootItemInSlot(slot)
    if type(LootSlot) ~= "function" then
        return false
    end
    LootSlot(slot)
    return true
end

local function HandleFishingLootWindow()
    if not (addon.db and addon.db.managedLoot) then
        DebugLootMessage("Managed loot is disabled in settings; skipping loot handling")
        return false
    end
    
    local managedAutoLootOverrideActive = addon.state and addon.state.savedAutoLootDefault ~= nil
    local blizzardAutoLootEnabled = (type(GetCVar) == "function" and GetCVar("autoLootDefault") == "1")
    if blizzardAutoLootEnabled and not managedAutoLootOverrideActive then
        DebugLootMessage("Blizzard auto-loot is enabled without managed override; skipping managed loot handling")
        return false
    end
    if type(GetNumLootItems) ~= "function" or type(LootSlot) ~= "function" then
        DebugLootMessage("Required loot functions are not available; skipping loot handling")
        return false
    end

    local lootCount = tonumber(GetNumLootItems()) or 0
    local shouldCloseLootWindow = lootCount > 0

    DebugLootMessage("Handling loot window with " .. tostring(lootCount) .. " items")
    local itemsLooted = 0
    local totalItems = lootCount
    for slot = 1, lootCount do
        local lootItemInfo = GetLootItemInfo(slot)
        if not lootItemInfo then
            DebugLootMessage("Failed to get info for loot slot " .. tostring(slot) .. "; skipping")
            -- in the future, we may want to go ahead and loot unknown items due to player having selected "autoloot while fishing"
            shouldCloseLootWindow = false
            return
        end
        if ShouldAutoLootItem(lootItemInfo) then
            DebugLootMessage("Looting item " .. (lootItemInfo.itemLink or lootItemInfo.name) .. " in loot slot " .. tostring(slot) .. " with quality " .. tostring(lootItemInfo.quality))
            LootItemInSlot(slot)
            itemsLooted = itemsLooted + 1
            slot = slot - 1
            lootCount = lootCount - 1
        else
            DebugLootMessage("Not looting item " .. (lootItemInfo.itemLink or lootItemInfo.name) .. " in loot slot " .. tostring(slot) .. " with quality " .. tostring(lootItemInfo.quality))
            shouldCloseLootWindow = false
        end
    end

    DebugLootMessage("Looted " .. tostring(itemsLooted) .. " of " .. tostring(totalItems) .. " items")

    if shouldCloseLootWindow and type(CloseLoot) == "function" then
        CloseLoot()
    end

    return true
end

local lootTracker = CreateFrame("Frame")
lootTracker:RegisterEvent("LOOT_READY")
lootTracker:RegisterEvent("LOOT_CLOSED")
lootTracker:SetScript("OnEvent", function(_, event, ...)
    if not requireFishingAPI then
        error("DreamFish: RequireFishingAPI helper is required for loot tracker")
    end
    local fishing = requireFishingAPI()

    if event == "LOOT_READY" then
        if addon.db and addon.db.autoLoot then
            DebugLootMessage("Auto-loot while fishing is enabled; skipping managed loot handling to allow Blizzard auto-loot to function")
            return
        end
        if not (fishing and fishing.IsFishingActiveSessionState) then
            error("DreamFish: IsFishingActiveSessionState is required for loot-ready handling")
        end
        -- if not fishing.IsFishingActiveSessionState() then
        --     DebugLootMessage("Received loot event " .. tostring(event) .. " but not in active fishing session; ignoring")
        --     return
        -- end
        if not (fishing and fishing.ApplySessionState and fishing.IsLootReadySessionState) then
            error("DreamFish: ApplySessionState and IsLootReadySessionState are required for loot-ready handling")
        end
        if fishing.IsLootReadySessionState() and not (fishing.IsSessionState and fishing.IsSessionState("LOOTING")) then
            fishing.ApplySessionState("LOOTING", "loot-ready")
        end
        DebugLootMessage("LOOT_READY event received; scheduled loot handling")
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(addon.db.lootDelay, function()
                if fishing.IsSessionState and not fishing.IsSessionState("LOOTING") then
                    DebugLootMessage("Skipping delayed loot callback because session is no longer LOOTING")
                    return
                end
                HandleFishingLootWindow()
            end)
        else
             HandleFishingLootWindow()
        end

    elseif event == "LOOT_CLOSED" then
        if not (fishing and fishing.IsSessionState) then
            error("DreamFish: IsSessionState is required for loot-close handling")
        end
        if fishing.IsSessionState("LOOTING") then
            DebugLootMessage("Fishing loot in progress ended")
            if not (fishing and fishing.StartLingerThenCloseSession) then
                error("DreamFish: StartLingerThenCloseSession is required for loot close handling")
            end
            fishing.StartLingerThenCloseSession(
                "loot-closed-starting-linger",
                "loot-closed",
                {
                restoreAutoLoot = true,
                poleReason = "loot-closed",
                }
            )
        end
        addon.state.lastBagWarning = 0
    end
end)

-- Bag monitoring
local bagMonitor = CreateFrame("Frame")
bagMonitor:RegisterEvent("PLAYER_ENTERING_WORLD")
bagMonitor:RegisterEvent("BAG_UPDATE")
bagMonitor:RegisterEvent("BAG_UPDATE_DELAYED")
bagMonitor:SetScript("OnEvent", function(_, event)
    if addon.utils then addon.utils.CheckBagSpace() end

    local fishing = requireFishingAPI()
    local alerts = requireAlertsAPI()

    if event == "BAG_UPDATE_DELAYED" and addon.utils and addon.alerts then
        if not (fishing and fishing.IsFishingActiveSessionState) then
            error("DreamFish: IsFishingActiveSessionState is required for bag-update handling")
        end
        if not requireAlertsAPI then
            error("DreamFish: RequireAlertsAPI helper is required for bag monitoring")
        end
        local alerts = requireAlertsAPI()
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
        else
            DebugBagMessage("Bag space not low yet")
        end
    elseif event == "BAG_UPDATE" then
        if not (fishing and fishing.IsFishingActiveSessionState) then
            error("DreamFish: IsFishingActiveSessionState is required for bag-update handling")
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
    end
end)

-- Aura tracking
local auraTracker = CreateFrame("Frame")
auraTracker:RegisterEvent("UNIT_AURA")
auraTracker:RegisterEvent("UI_INFO_MESSAGE")
auraTracker:SetScript("OnEvent", function(_, event, ...)
    local arg1, arg2 = ...
    local fishing = requireFishingAPI()
    local alerts = requireAlertsAPI()
    if event == "UNIT_AURA" then
        if type(arg1) ~= "string" or arg1 ~= "player" then return end
        if not requireFishingAPI then
            error("DreamFish: RequireFishingAPI helper is required for aura tracking")
        end
        if not requireAlertsAPI then
            error("DreamFish: RequireAlertsAPI helper is required for aura tracking")
        end

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
    elseif event == "UI_INFO_MESSAGE" then
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
                error("DreamFish: StartLingerThenCloseSession is required for no-fish-hooked handling")
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
