-- Unit tests for DreamFisher UI_INFO_MESSAGE fish-hook handling.
-- Run with: lua tests/ui_info_message_test.lua

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEquals failed") .. " | expected=" .. tostring(expected) .. " actual=" .. tostring(actual), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "assertTrue failed", 2)
    end
end

local function makeNoopFrame()
    local scripts = {}
    local events = {}
    local attrs = {}
    return {
        _scripts = scripts,
        _events = events,
        SetAllPoints = function() end,
        SetFrameStrata = function() end,
        SetAttribute = function(_, k, v) attrs[k] = v end,
        GetAttribute = function(_, k) return attrs[k] end,
        RegisterForClicks = function() end,
        Hide = function() end,
        HookScript = function() end,
        RegisterEvent = function(_, event) events[event] = true end,
        SetScript = function(_, scriptName, fn) scripts[scriptName] = fn end,
        SetSize = function() end,
        SetPoint = function() end,
        SetMovable = function() end,
        EnableMouse = function() end,
        RegisterForDrag = function() end,
        SetBackdrop = function() end,
        SetBackdropColor = function() end,
        CreateFontString = function()
            return {
                SetPoint = function() end,
                SetText = function() end,
                SetTextColor = function() end,
            }
        end,
        IsShown = function() return false end,
        Show = function() end,
        StartMoving = function() end,
        StopMovingOrSizing = function() end,
        UnregisterEvent = function(_, event) events[event] = nil end,
        GetName = function() return "DreamFisherSecureFishingButton" end,
    }
end

local createdFrames = {}

_G.CreateFrame = function()
    local frame = makeNoopFrame()
    frame.Text = { SetText = function() end, SetTextColor = function() end }
    frame.GetChecked = function() return true end
    frame.GetText = function() return "2" end
    table.insert(createdFrames, frame)
    return frame
end

_G.UIParent = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.WorldFrame = nil
_G.SLASH_DREAMFISHER1 = nil
_G.SLASH_DREAMFISHER2 = nil
_G.SlashCmdList = {}
_G.NUM_BAG_SLOTS = 4
_G.C_Container = nil
_G.InCombatLockdown = function() return false end
_G.ClearOverrideBindings = function() end
_G.SetOverrideBindingClick = function() end
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.PlaySound = function() end
_G.SOUNDKIT = {}
_G.GetContainerNumSlots = function() return 0 end
_G.GetContainerItemID = function() return nil end
_G.GetCVar = function() return "0" end
_G.SetCVar = function() end
_G.PlayerHasToy = function() return true end
_G.GetTime = function() return 100 end

-- Load addon modules.
dofile("core/init.lua")
dofile("core/utils.lua")
dofile("buff/tracking.lua")
dofile("buff/timing.lua")
dofile("buff/management.lua")
dofile("fishing/helpers.lua")
dofile("fishing/casting.lua")
dofile("fishing/interactloot.lua")
dofile("fishing/state.lua")
dofile("audio/ducking.lua")
dofile("audio/alerts.lua")
dofile("ui/commands.lua")
dofile("ui/ace_widget_factory.lua")
dofile("ui/buff_item_drop_box.lua")
dofile("ui/config.lua")
dofile("DreamFisher.lua")

local addon = _G.DreamFisher
assertTrue(type(addon) == "table", "Addon table should exist")

local function getLootTrackerOnEvent()
    for _, frame in ipairs(createdFrames) do
        if frame._events and frame._events["UI_INFO_MESSAGE"] and frame._scripts and frame._scripts["OnEvent"] then
            return frame._scripts["OnEvent"]
        end
    end
    return nil
end

local onEvent = getLootTrackerOnEvent()
assertTrue(type(onEvent) == "function", "Loot tracker OnEvent script should be discoverable")

local clearCalls = 0
if addon.fishing then
    addon.fishing.ClearNativeInteractOverride = function()
        clearCalls = clearCalls + 1
    end
end

-- Case 1: UI_INFO_MESSAGE type 413 should clear fishing/hooked state.
addon._test.SetSessionState(
    addon.fishing.SessionStates.LOOTING,
    "test-ui-info-pre-413"
)
addon.state.interactAcquireExpiresAt = 9
clearCalls = 0

onEvent(nil, "UI_INFO_MESSAGE", 413, "No fish are hooked.")

assertEquals(addon._test.GetSessionState(), addon.fishing.SessionStates.CLOSING_FISHING_SESSION,
    "Type 413 should finalize to CLOSING_FISHING_SESSION")
assertEquals(addon.state.interactAcquireExpiresAt, 0, "Type 413 should reset interactAcquireExpiresAt")
assertEquals(clearCalls, 1, "Type 413 should clear native interact override")

-- Case 2: Other UI_INFO_MESSAGE types should not clear state.
addon._test.SetSessionState(
    addon.fishing.SessionStates.LOOTING,
    "test-ui-info-pre-non413"
)
addon.state.interactAcquireExpiresAt = 7
clearCalls = 0

onEvent(nil, "UI_INFO_MESSAGE", 999, "Other info message")

assertEquals(addon._test.GetSessionState(), addon.fishing.SessionStates.LOOTING,
    "Non-413 should keep LOOTING session state")
assertEquals(addon.state.interactAcquireExpiresAt, 7, "Non-413 should not change interactAcquireExpiresAt")
assertEquals(clearCalls, 0, "Non-413 should not clear native interact override")

print("PASS: ui_info_message_test")
