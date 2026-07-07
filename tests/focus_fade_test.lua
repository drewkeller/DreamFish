-- Unit tests for DreamFisher visual focus fading state behavior.
-- Run with: lua tests/focus_fade_test.lua

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

local now = 100
local createdFrames = {}
local frameStateByName = {}
local trackedFrameNames = {
    "Minimap",
    "ObjectiveTrackerFrame",
    "PlayerFrame",
    "TargetFrame",
}

local function makeFrame(name)
    local scripts = {}
    local attrs = {}
    local frame = nil
    frame = {
        _name = name,
        _shown = true,
        _alpha = 1,
        _scripts = scripts,
        SetAttribute = function(_, key, value) attrs[key] = value end,
        GetAttribute = function(_, key) return attrs[key] end,
        RegisterForClicks = function() end,
        Hide = function() frame._shown = false end,
        Show = function() frame._shown = true end,
        HookScript = function() end,
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function(_, scriptName, fn) scripts[scriptName] = fn end,
        GetScript = function(_, scriptName) return scripts[scriptName] end,
        SetSize = function() end,
        SetPoint = function() end,
        SetMovable = function() end,
        EnableMouse = function() end,
        RegisterForDrag = function() end,
        SetBackdrop = function() end,
        SetBackdropColor = function() end,
        SetFrameStrata = function() end,
        SetAllPoints = function() end,
        SetScale = function() end,
        EnableMouse = function() end,
        SetStaticPOIArrowTexture = function() end,
        SetPlayerTexture = function() end,
        IsShown = function() return frame._shown end,
        GetAlpha = function() return frame._alpha end,
        SetAlpha = function(_, value) frame._alpha = value end,
        GetName = function() return name or "Frame" end,
        CreateFontString = function()
            return {
                SetPoint = function() end,
                SetText = function() end,
                SetTextColor = function() end,
            }
        end,
        CreateTexture = function()
            return {
                SetAllPoints = function() end,
                SetTexture = function() end,
                SetPoint = function() end,
                SetColorTexture = function() end,
            }
        end,
    }
    return frame
end

_G.CreateFrame = function(_, name)
    local frame = makeFrame(name)
    table.insert(createdFrames, frame)
    return frame
end

for _, name in ipairs(trackedFrameNames) do
    _G[name] = makeFrame(name)
    frameStateByName[name] = _G[name]
end

_G.UIFrameFadeOut = nil
_G.UIFrameFadeIn = nil
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
_G.GetTime = function() return now end
_G.GetCVar = function() return "0" end
_G.SetCVar = function() end
_G.PlayerHasToy = function() return true end
_G.C_SuperTrack = { SetSuperTrackedQuestID = function() end }
_G.LibStub = function() return nil end
_G.C_Minimap = { SetTracking = function() end }
_G.C_AddOns = { IsAddOnLoaded = function() return false end }

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
dofile("ui/focus_fade.lua")
dofile("ui/config.lua")
dofile("DreamFisher.lua")

local addon = _G.DreamFisher
assertTrue(type(addon) == "table", "Addon should load")

addon._test.SetDB({ focusedVisuals = true, focusedVisualsLinger = 3, focusedAudio = false, autoLoot = true, bagAlerts = true, treasureAlerts = true, lowBagThreshold = 2 })
addon.uiFocus.CreateFocusFadeFrame()

local focusFrame = addon.uiFocus and addon.uiFocus.CreateFocusFadeFrame and addon.uiFocus.CreateFocusFadeFrame()
assertTrue(focusFrame ~= nil, "Focus fade frame should be created")

addon._test.SetSessionState(addon.fishing.SessionStates.CASTING, "test-focus-fade-fishing")
addon.uiFocus.RefreshFocusFadeState()

for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 0,
        name .. " should fade out while fishing")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "Fade-out should clear any restore timer")

addon._test.SetSessionState(addon.fishing.SessionStates.IDLE, "test-focus-fade-idle")
addon.uiFocus.RefreshFocusFadeState()
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 1,
        name .. " should restore immediately when session returns to IDLE")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "Immediate restore should not schedule a timer")

addon._test.SetSessionState(addon.fishing.SessionStates.PRE_CASTING, "test-focus-fade-pre-cast")
addon.uiFocus.RefreshFocusFadeState()
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 0,
        name .. " should remain hidden in PRE_CASTING")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "PRE_CASTING should keep fade state without restore timer")

addon._test.SetSessionState(addon.fishing.SessionStates.CASTING, "test-focus-fade-refade-after-pre-cast")
addon.uiFocus.RefreshFocusFadeState()
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 0,
        name .. " should fade out again after leaving PRE_CASTING")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "Fade-out after PRE_CASTING should not leave a restore timer")

addon._test.SetSessionState(addon.fishing.SessionStates.IDLE, "test-focus-fade-idle-after-pre-cast")
addon.uiFocus.RefreshFocusFadeState()
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 1,
        name .. " should restore immediately after PRE_CASTING when session is IDLE")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "Idle after PRE_CASTING should not schedule restore timer")

print("PASS: focus_fade_test")
