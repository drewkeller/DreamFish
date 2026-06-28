-- Unit tests for DreamFisher audio ducking state behavior.
-- Run with: lua tests/audio_ducking_test.lua

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
local cvars = {
    Sound_AmbienceVolume = "0.4",
    Sound_MusicVolume = "0.3",
    Sound_DialogVolume = "0.8",
    autoLootDefault = "0",
}
local currentCastName = nil
local currentChannelName = nil

local function makeNoopFrame(name)
    local frame = {
        _name = name,
        _shown = false,
        _scripts = {},
    }

    function frame:SetAllPoints() end
    function frame:SetFrameStrata() end
    function frame:SetClampedToScreen() end
    function frame:SetAttribute() end
    function frame:RegisterForClicks() end
    function frame:Hide() self._shown = false end
    function frame:Show() self._shown = true end
    function frame:IsShown() return self._shown end
    function frame:HookScript() end
    function frame:RegisterEvent() end
    function frame:SetScript(kind, fn) self._scripts[kind] = fn end
    function frame:GetScript(kind) return self._scripts[kind] end
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:SetMovable() end
    function frame:EnableMouse() end
    function frame:RegisterForDrag() end
    function frame:SetAutoFocus() end
    function frame:SetText() end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor() end
    function frame:CreateTexture()
        return {
            SetAllPoints = function() end,
            SetColorTexture = function() end,
            SetSize = function() end,
            SetPoint = function() end,
            SetTexture = function() end,
        }
    end
    function frame:CreateFontString()
        return {
            SetPoint = function() end,
            SetText = function() end,
            SetTextColor = function() end,
        }
    end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:UnregisterEvent() end
    function frame:GetName() return self._name or "Frame" end

    frame.Text = { SetText = function() end, SetTextColor = function() end }
    frame.GetChecked = function() return true end
    frame.SetChecked = function() end
    frame.GetText = function() return "10" end

    return frame
end

_G.CreateFrame = function(_, name)
    local frame = makeNoopFrame(name)
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
_G.C_UnitAuras = nil
_G.AuraUtil = nil
_G.InCombatLockdown = function() return false end
_G.ClearOverrideBindings = function() end
_G.SetOverrideBindingClick = function() end
_G.UnitCastingInfo = function() return currentCastName end
_G.UnitChannelInfo = function() return currentChannelName end
_G.GetTime = function() return now end
_G.PlaySound = function() end
_G.SOUNDKIT = {}
_G.GetSpellInfo = function() return "Fishing" end
_G.GetContainerNumSlots = function() return 0 end
_G.GetContainerItemID = function() return nil end
_G.GetCVar = function(name)
    return cvars[name]
end
_G.SetCVar = function(name, value)
    cvars[name] = tostring(value)
end
_G.C_Timer = nil
_G.strtrim = function(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Load addon file in mocked environment.
dofile("core/init.lua")
dofile("core/utils.lua")
dofile("buff/tracking.lua")
dofile("buff/timing.lua")
dofile("buff/management.lua")
dofile("fishing/helpers.lua")
dofile("fishing/casting.lua")
dofile("fishing/state.lua")
dofile("audio/ducking.lua")
dofile("ui/config.lua")
dofile("DreamFisher.lua")

local addon = _G.DreamFisher
assertEquals(type(addon), "table", "Addon table should exist")
assertEquals(type(addon._test), "table", "Audio test hooks should exist")

-- Fire ADDON_LOADED so runtime frames and slash handlers are initialized.
local rootFrame = nil
for _, frame in ipairs(createdFrames) do
    local onEventScript = frame.GetScript and frame:GetScript("OnEvent")
    if frame.GetName and frame:GetName() == "DreamFisherFrame" and type(onEventScript) == "function" then
        rootFrame = frame
    end
end
if not rootFrame then
    rootFrame = createdFrames[#createdFrames]
end
local rootOnEvent = rootFrame and rootFrame:GetScript("OnEvent")
assertTrue(type(rootOnEvent) == "function", "Root OnEvent should exist")
rootOnEvent(rootFrame, "ADDON_LOADED", "DreamFisher")

local function resetAudioCVars()
    cvars.Sound_AmbienceVolume = "0.4"
    cvars.Sound_MusicVolume = "0.3"
    cvars.Sound_DialogVolume = "0.8"
end

local function resetSpellNames()
    currentCastName = nil
    currentChannelName = nil
end

local function resetState()
    resetAudioCVars()
    resetSpellNames()
    addon._test.RestoreFishingAudioFocus()
    addon._test.SetFishingFlags(false, false, false)
end

local function driveOnUpdateUntil(targetTime)
    while now < targetTime do
        now = now + 1
        for _, frame in ipairs(createdFrames) do
            local onUpdate = frame.GetScript and frame:GetScript("OnUpdate")
            if onUpdate then
                onUpdate(frame, 1)
            end
        end
    end
end

-- Initialize addon state.
addon._test.SetDB({ enhancedSounds = true, audioFocusLinger = 10, autoLoot = true, bagAlerts = true, treasureAlerts = true, lowBagThreshold = 2 })
local fishingStateFrame = addon._test.GetFishingStateFrame()
local onEvent = fishingStateFrame and fishingStateFrame:GetScript("OnEvent")
assertTrue(type(onEvent) == "function", "Fishing state frame OnEvent should exist")

-- Case 1: EnableFishingAudioFocus ducks channels.
resetState()
addon._test.RestoreFishingAudioFocus()
addon._test.EnableFishingAudioFocus(true)
assertTrue(addon._test.GetAudioDucked(), "Audio should be marked ducked after enabling focus")
assertEquals(cvars.Sound_AmbienceVolume, tostring(0.4 * 0.35), "Ambience should be ducked")
assertEquals(cvars.Sound_MusicVolume, tostring(0.3 * 0.2), "Music should be ducked")
assertEquals(cvars.Sound_DialogVolume, tostring(0.8 * 0.5), "Dialog should be ducked")

-- Case 2: Right double-click path enters a fishing session and ducks audio.
resetState()
now = 200
addon._test.HandleWorldRightClick()
now = 200.1
addon._test.HandleWorldRightClick()
local isFishing, bobberActive = addon._test.GetFishingFlags()
assertTrue(addon._test.GetAudioDucked(), "Audio should duck on right-double-click fishing trigger")
assertTrue(isFishing, "Fishing session should be active after right-double-click")
assertTrue(bobberActive, "Bobber should be treated as active for fallback session tracking")

-- Case 2b: If current levels already match previous ducked targets, do not duck again.
addon._test.RestoreFishingAudioFocus()
cvars.Sound_AmbienceVolume = tostring(0.4 * 0.35)
cvars.Sound_MusicVolume = tostring(0.3 * 0.2)
cvars.Sound_DialogVolume = tostring(0.8 * 0.5)
addon._test.EnableFishingAudioFocus(true)
assertEquals(cvars.Sound_AmbienceVolume, tostring(0.4 * 0.35), "Already-ducked ambience should not be ducked again")
assertEquals(cvars.Sound_MusicVolume, tostring(0.3 * 0.2), "Already-ducked music should not be ducked again")
assertEquals(cvars.Sound_DialogVolume, tostring(0.8 * 0.5), "Already-ducked dialog should not be ducked again")
addon._test.RestoreFishingAudioFocus()

-- Case 3: Manual cast start via spell-name fallback ducks audio and starts session.
resetState()
now = 300
currentCastName = "Fishing"
onEvent(fishingStateFrame, "UNIT_SPELLCAST_START", "player", "cast-guid", 999999)
isFishing, bobberActive = addon._test.GetFishingFlags()
assertTrue(addon._test.GetAudioDucked(), "Audio should duck on manual Fishing cast")
assertTrue(isFishing, "Fishing session should start on manual Fishing cast")
assertTrue(not bobberActive, "Bobber should not be active until cast/channel stop")

-- Case 4: Cast stop transitions to bobber-active while keeping fishing session active.
currentCastName = nil
onEvent(fishingStateFrame, "UNIT_SPELLCAST_STOP", "player", "cast-guid", 999999)
isFishing, bobberActive = addon._test.GetFishingFlags()
assertTrue(isFishing, "Fishing session should remain active after cast stop")
assertTrue(bobberActive, "Bobber should become active after cast stop")

-- Case 5: RestoreFishingAudioFocusAfterLinger schedules restore and OnUpdate restores after time.
now = 100
addon._test.RestoreFishingAudioFocusAfterLinger()
assertTrue(addon._test.GetAudioRestoreAt() ~= nil, "Linger restore time should be scheduled")
assertEquals(addon._test.GetAudioRestoreAt(), 110, "Default linger should schedule a 10 second restore")

addon.db.audioFocusLinger = 3
addon._test.RestoreFishingAudioFocusAfterLinger()
assertEquals(addon._test.GetAudioRestoreAt(), 103, "Saving the config should reschedule the active linger timer from the UI value")

driveOnUpdateUntil(111)
assertTrue(not addon._test.GetAudioDucked(), "Audio should restore after linger expires")
assertEquals(cvars.Sound_AmbienceVolume, "0.4", "Ambience should restore to original value")
assertEquals(cvars.Sound_MusicVolume, "0.3", "Music should restore to original value")
assertEquals(cvars.Sound_DialogVolume, "0.8", "Dialog should restore to original value")

-- Case 6: Movement event restores immediately while ducked.
resetState()
addon._test.EnableFishingAudioFocus(true)
addon._test.SetFishingFlags(true, true, false)
onEvent(fishingStateFrame, "PLAYER_STARTED_MOVING")
assertTrue(not addon._test.GetAudioDucked(), "Audio should restore immediately on movement")

-- Case 7: Combat event restores immediately while ducked.
resetState()
addon._test.EnableFishingAudioFocus(true)
addon._test.SetFishingFlags(true, true, false)
onEvent(fishingStateFrame, "PLAYER_REGEN_DISABLED")
assertTrue(not addon._test.GetAudioDucked(), "Audio should restore immediately on combat")

-- Case 8: Failed/quiet cancel restores immediately while ducked.
resetState()
currentCastName = "Fishing"
addon._test.EnableFishingAudioFocus(true)
addon._test.SetFishingFlags(true, false, false)
onEvent(fishingStateFrame, "UNIT_SPELLCAST_FAILED_QUIET", "player", "cast-guid", 999999)
assertTrue(not addon._test.GetAudioDucked(), "Audio should restore on failed/quiet fishing cancel")

-- Case 9: A different player spell after the grace period cancels fishing and restores audio.
resetState()
now = 400
addon._test.HandleWorldRightClick()
now = 400.1
addon._test.HandleWorldRightClick()
currentCastName = "Hearthstone"
onEvent(fishingStateFrame, "UNIT_SPELLCAST_START", "player", "cast-guid", 123456)
assertTrue(addon._test.GetAudioDucked(), "Audio should remain ducked during startup grace window")
now = 403
onEvent(fishingStateFrame, "UNIT_SPELLCAST_START", "player", "cast-guid", 123456)
assertTrue(not addon._test.GetAudioDucked(), "Audio should restore when a different spell cancels fishing after grace window")

-- Case 10: Zero linger restores audio immediately when the double-click cast bar ends.
resetState()
addon.db.audioFocusLinger = 0
now = 500
addon._test.HandleWorldRightClick()
now = 500.1
addon._test.HandleWorldRightClick()
currentCastName = nil
onEvent(fishingStateFrame, "UNIT_SPELLCAST_STOP", "player", "cast-guid", 999999)
assertTrue(not addon._test.GetAudioDucked(), "Audio should restore immediately when fishing expires with zero linger")

print("PASS: audio_ducking_test")
