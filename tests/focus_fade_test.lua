-- Unit tests for DreamFish visual focus fading state behavior.
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

local makeFrame = dofile("tests/mocks/frame_fixture.lua").makeFrame

_G.CreateFrame = function(_, name)
    local frame = makeFrame(name, { shown = true })
    table.insert(createdFrames, frame)
    return frame
end

for _, name in ipairs(trackedFrameNames) do
    _G[name] = makeFrame(name, { shown = true })
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
dofile("core/module_api.lua")
dofile("core/api_resolver.lua")
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
dofile("DreamFish.lua")

local addon = _G.DreamFish
assertTrue(type(addon) == "table", "Addon should load")
addon.commands.RegisterSlashCommands()

addon._test.SetDB({ focusedVisuals = true, focusedVisualsLinger = 3, focusedAudio = false, managedLoot = true, bagAlerts = true, treasureAlerts = true, bagAlertsThreshold = 2 })
addon.uiFocus.CreateFocusFadeFrame()

local focusFrame = addon.uiFocus and addon.uiFocus.CreateFocusFadeFrame and addon.uiFocus.CreateFocusFadeFrame()
assertTrue(focusFrame ~= nil, "Focus fade frame should be created")

addon._test.SetSessionState(addon.fishing.SessionStates.PRE_CASTING, "test-focus-fade-pre-cast-fishing")
addon.uiFocus.RefreshFocusFadeState()

for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 0.0001,
    name .. " should fade out during PRE_CASTING")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "Fade-out should clear any restore timer")

addon._test.SetSessionState(addon.fishing.SessionStates.CANCELLING_FISHING_SESSION, "test-focus-fade-cancel")
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 1,
        name .. " should restore immediately when fishing is cancelled")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "Cancelling fishing should not schedule a restore timer")

addon.focusedVisualsCheckbox = {
    GetChecked = function()
        return false
    end,
}
addon.db.focusedVisuals = true
addon._test.SaveConfigBindings()
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 1,
        name .. " should restore immediately when focused visuals are unchecked")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "Unchecking focused visuals should not leave a restore timer")
addon.focusedVisualsCheckbox = nil

addon._test.SetSessionState(addon.fishing.SessionStates.PRE_CASTING, "test-focus-fade-disabled-visuals")
addon.uiFocus.RefreshFocusFadeState()
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 1,
    name .. " should not fade out during PRE_CASTING while focused visuals are disabled")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "Disabled focused visuals should not schedule a restore timer")

addon.db.focusedVisuals = true

addon._test.SetSessionState(addon.fishing.SessionStates.PRE_CASTING, "test-focus-fade-reenabled-visuals")
addon.uiFocus.RefreshFocusFadeState()
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 0.0001,
    name .. " should fade out again during PRE_CASTING after focused visuals are re-enabled")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "Re-enabled focused visuals should still clear the restore timer while fishing")

SlashCmdList["DREAMFISHER"]("forcevisible")
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 1,
        name .. " should be fully visible after forcevisible")
end

addon._test.SetSessionState(addon.fishing.SessionStates.PRE_CASTING, "test-focus-fade-forcevisible-once")
addon.uiFocus.RefreshFocusFadeState()
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 0.0001,
    name .. " should fade out again on next PRE_CASTING refresh because forcevisible is one-time")
end

addon._test.SetSessionState(addon.fishing.SessionStates.STARTING_LINGER, "test-focus-fade-starting-linger")
local restoreAt = addon._test.GetFocusFadeRestoreAt()
assertTrue(type(restoreAt) == "number" and restoreAt > now, "STARTING_LINGER should schedule visual restore timer")

local onUpdate = focusFrame:GetScript("OnUpdate")
assertTrue(type(onUpdate) == "function", "Focus fade frame should expose OnUpdate for linger restore")

now = restoreAt - 0.1
onUpdate(focusFrame, 0.1)
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 0.0001,
        name .. " should stay hidden until visual linger expires")
end

now = restoreAt + 0.1
onUpdate(focusFrame, 0.1)
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 1,
        name .. " should restore after visual linger expiry")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "Visual restore timer should clear after fade-in")

addon._test.SetSessionState(addon.fishing.SessionStates.PRE_CASTING, "test-focus-fade-pre-cast")
addon.uiFocus.RefreshFocusFadeState()
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 0.0001,
        name .. " should remain hidden in PRE_CASTING")
end
assertEquals(addon._test.GetFocusFadeRestoreAt(), nil, "PRE_CASTING should keep fade state without restore timer")

addon._test.SetSessionState(addon.fishing.SessionStates.CASTING, "test-focus-fade-refade-after-pre-cast")
addon.uiFocus.RefreshFocusFadeState()
for _, name in ipairs(trackedFrameNames) do
    assertEquals((_G[name] and _G[name].GetAlpha and _G[name]:GetAlpha()) or nil, 0.0001,
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
