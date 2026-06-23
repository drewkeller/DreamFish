-- DreamFisher - Modular Addon Loader
-- This file orchestrates loading of all addon modules

-- Initialize addon namespace
local addonName = "DreamFisher"
local addon = _G[addonName] or {}
_G[addonName] = addon

-- Create frame for event handling
local frame = CreateFrame("Frame", addonName .. "Frame")
addon.frame = frame

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

    -- Load saved data
    _G[addonName .. "DB"] = _G[addonName .. "DB"] or {}
    addon.db = _G[addonName .. "DB"]
    addon.CopyDefaults(addon.defaults, addon.db)

    -- Migration: Reset modifier to NONE if user never explicitly chose one
    if not addon.db.worldRightClickModifierUserSet then
        addon.db.worldRightClickModifier = "NONE"
    end

    -- Initialize buff config
    if addon.buff and addon.buff.NormalizeBuffConfig then
        addon.buff.NormalizeBuffConfig()
        addon.utils.CheckBuffItemStockWarnings()
    end

    -- Create secure frames
    if addon.fishing then
        addon.fishing.CreateSecureFishingFrame()
        addon.fishing.CreateSecureBuffFrame()
        addon.fishing.CreateFishingStateFrame()
    end

    -- Register slash commands
    if addon.commands then
        addon.commands.RegisterSlashCommands()
    end

    addon.PrintMessage("Loaded! Type /df to configure.")
    self:UnregisterEvent("ADDON_LOADED")
end)

-- World right-click handler
if WorldFrame then
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if button == "RightButton" and not InCombatLockdown() then
            if addon.fishing and addon.fishing.IsWorldRightClickActivationPressed then
                if addon.fishing.IsWorldRightClickActivationPressed() then
                    addon.fishing.HandleWorldRightClick()
                end
            end
        end
    end)
end

-- Loot tracking
local lootTracker = CreateFrame("Frame")
lootTracker:RegisterEvent("LOOT_READY")
lootTracker:RegisterEvent("LOOT_CLOSED")
lootTracker:RegisterEvent("BAG_UPDATE")
lootTracker:SetScript("OnEvent", function(_, event)
    if event == "LOOT_READY" then
        if addon.state.isBobberActive or addon.state.savedFishingAudioCVars ~= nil then
            addon.state.fishingLootInProgress = true
            addon.state.isBobberActive = false
            addon.state.isFishing = false
        end
    elseif event == "LOOT_CLOSED" then
        if addon.fishing then addon.fishing.RestoreOriginalAutoLoot() end
        if addon.state.fishingLootInProgress then
            addon.state.fishingLootInProgress = false
            if addon.audio then addon.audio.RestoreFishingAudioFocusAfterLinger() end
            if addon.utils and addon.utils.GetFreeBagSlots() == 0 then
                if addon.alerts then addon.alerts.ShowBagFullAlert() end
            end
        end
        addon.state.isBobberActive = false
        addon.state.lastBagWarning = 0
    elseif event == "BAG_UPDATE" then
        if addon.state.isFishing and addon.utils then
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

-- Bag monitoring
local bagMonitor = CreateFrame("Frame")
bagMonitor:RegisterEvent("PLAYER_ENTERING_WORLD")
bagMonitor:RegisterEvent("BAG_UPDATE_DELAYED")
bagMonitor:SetScript("OnEvent", function()
    if addon.utils then addon.utils.CheckBagSpace() end
end)

-- Aura tracking
local auraTracker = CreateFrame("Frame")
auraTracker:RegisterEvent("UNIT_AURA")
auraTracker:SetScript("OnEvent", function(_, _, unit)
    if unit ~= "player" then return end

    if addon.buff then addon.buff.UpdatePendingBuffObservation() end

    if addon.fishing and addon.fishing.HasPatientlyRewardedAura then
        local hasAura = addon.fishing.HasPatientlyRewardedAura()
        if hasAura and not addon.state.patientAuraActive then
            addon.state.patientAuraActive = true
            if addon.alerts then addon.alerts.ShowPatientTreasureAlert("Patiently Rewarded") end
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
