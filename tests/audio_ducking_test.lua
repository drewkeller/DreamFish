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

dofile("core/init.lua")
dofile("core/utils.lua")
dofile("core/module_api.lua")
dofile("core/api_resolver.lua")
dofile("buff/tracking.lua")
dofile("buff/timing.lua")
dofile("buff/management.lua")
dofile("fishing/helpers.lua")
dofile("fishing/casting.lua")
dofile("fishing/state.lua")
dofile("audio/ducking.lua")
dofile("ui/ace_widget_factory.lua")
dofile("ui/buff_item_drop_box.lua")
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
    addon._test.SetSessionState(addon.fishing.SessionStates.IDLE, "test-audio-reset")
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
addon._test.SetDB({ focusedAudio = true, focusedAudioLinger = 10, autoLoot = true, bagAlerts = true, reagentBagAlerts = true, treasureAlerts = true, bagAlertsThreshold = 2, reagentBagAlertsThreshold = 2 })
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
local currentSessionState = addon._test.GetSessionState()
assertTrue(addon._test.GetAudioDucked(), "Audio should duck on right-double-click fishing trigger")
assertEquals(currentSessionState, addon.fishing.SessionStates.PRE_CASTING,
    "Right-double-click should enter PRE_CASTING session state")

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

-- Case 2c: Reload while already ducked should resume runtime state and avoid re-ducking.
resetState()
addon._test.EnableFishingAudioFocus(true)
local duckedAmbience = cvars.Sound_AmbienceVolume
local duckedMusic = cvars.Sound_MusicVolume
local duckedDialog = cvars.Sound_DialogVolume
addon.state.savedFishingAudioCVars = nil
addon.state.lastFishingDuckedAudioCVars = nil
addon._test.ResumePersistedAudioDuckingState()
assertTrue(addon._test.GetAudioDucked(), "Audio ducking state should resume after simulated reload")
addon._test.EnableFishingAudioFocus(true)
assertEquals(cvars.Sound_AmbienceVolume, duckedAmbience, "Reload-resumed ambience should not be ducked again")
assertEquals(cvars.Sound_MusicVolume, duckedMusic, "Reload-resumed music should not be ducked again")
assertEquals(cvars.Sound_DialogVolume, duckedDialog, "Reload-resumed dialog should not be ducked again")
addon._test.RestoreFishingAudioFocus()

-- Case 3: Manual cast start via spell-name fallback ducks audio and starts session.
resetState()
now = 300
currentCastName = "Fishing"
onEvent(fishingStateFrame, "UNIT_SPELLCAST_START", "player", "cast-guid", 999999)
currentSessionState = addon._test.GetSessionState()
assertTrue(addon._test.GetAudioDucked(), "Audio should duck on manual Fishing cast")
assertEquals(currentSessionState, addon.fishing.SessionStates.CASTING,
    "Manual Fishing cast should enter CASTING state")

-- Case 4: Cast stop transitions to bobber-active while keeping fishing session active.
currentCastName = nil
onEvent(fishingStateFrame, "UNIT_SPELLCAST_STOP", "player", "cast-guid", addon.const.fishingSpellID)
currentSessionState = addon._test.GetSessionState()
assertEquals(currentSessionState, addon.fishing.SessionStates.WAITING_FOR_STRIKE,
    "Cast stop should move to WAITING_FOR_STRIKE state")

-- Case 5: RestoreFishingAudioFocusAfterLinger schedules restore and OnUpdate restores after time.
now = 100
addon._test.RestoreFishingAudioFocusAfterLinger()
assertTrue(addon._test.GetAudioRestoreAt() ~= nil, "Linger restore time should be scheduled")
assertEquals(addon._test.GetAudioRestoreAt(), 110, "Default linger should schedule a 10 second restore")

addon.db.focusedAudioLinger = 3
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
addon._test.SetSessionState(addon.fishing.SessionStates.WAITING_FOR_STRIKE, "test-audio-movement")
onEvent(fishingStateFrame, "PLAYER_STARTED_MOVING")
assertTrue(not addon._test.GetAudioDucked(), "Audio should restore immediately on movement")

-- Case 7: Combat event restores immediately while ducked.
resetState()
addon._test.EnableFishingAudioFocus(true)
addon._test.SetSessionState(addon.fishing.SessionStates.WAITING_FOR_STRIKE, "test-audio-combat")
onEvent(fishingStateFrame, "PLAYER_REGEN_DISABLED")
assertTrue(not addon._test.GetAudioDucked(), "Audio should restore immediately on combat")

-- Case 8: Strict fishing failed/quiet should cancel session.
resetState()
currentCastName = nil
addon._test.EnableFishingAudioFocus(true)
addon._test.SetSessionState(addon.fishing.SessionStates.CASTING, "test-audio-failed-quiet")
onEvent(fishingStateFrame, "UNIT_SPELLCAST_FAILED_QUIET", "player", "cast-guid", addon.const.fishingSpellID)
assertTrue(not addon._test.GetAudioDucked(), "Audio should restore on failed/quiet fishing cancel")

-- Case 11: Non-fishing failed/quiet should not cancel active cast-stage session.
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
addon.db.focusedAudioLinger = 0
now = 500
addon._test.HandleWorldRightClick()
now = 500.1
addon._test.HandleWorldRightClick()
currentCastName = nil
onEvent(fishingStateFrame, "UNIT_SPELLCAST_STOP", "player", "cast-guid", addon.const.fishingSpellID)
assertTrue(addon._test.GetAudioDucked(), "Audio should remain ducked until fishing session close is triggered")

resetState()
now = 700
currentCastName = "Fishing"
onEvent(fishingStateFrame, "UNIT_SPELLCAST_START", "player", "cast-guid", addon.const.fishingSpellID)
addon.state.interactOverrideActive = true
addon.state.interactAcquireExpiresAt = now + 2
onEvent(fishingStateFrame, "UNIT_SPELLCAST_FAILED_QUIET", "player", "cast-guid", 121125)
assertTrue(addon._test.GetAudioDucked(), "Non-fishing failed/quiet should not cancel active fishing cast")
currentSessionState = addon._test.GetSessionState()
assertEquals(currentSessionState, addon.fishing.SessionStates.CASTING,
    "Non-fishing failed/quiet should keep cast-stage fishing state")
assertEquals(addon.state.interactOverrideActive, true, "Non-fishing failed/quiet should not clear native interact override")

-- Case 12: Post-stop bobber mode with no hooked evidence should self-clear after confirmation window.
resetState()
addon.db.focusedAudioLinger = 10
now = 800
currentCastName = "Fishing"
onEvent(fishingStateFrame, "UNIT_SPELLCAST_START", "player", "cast-guid", addon.const.fishingSpellID)
currentCastName = nil
now = 808
onEvent(fishingStateFrame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-guid", addon.const.fishingChannelSpellID)
currentSessionState = addon._test.GetSessionState()
assertEquals(currentSessionState, addon.fishing.SessionStates.WAITING_FOR_STRIKE,
    "Post-stop should enter WAITING_FOR_STRIKE before stale-evidence check")
driveOnUpdateUntil(813)
currentSessionState = addon._test.GetSessionState()
assertEquals(currentSessionState, addon.fishing.SessionStates.IDLE,
    "No-evidence bobber mode should self-clear to IDLE once linger starts")
local audioRestoreAt = addon._test.GetAudioRestoreAt()
assertTrue(type(audioRestoreAt) == "number" and audioRestoreAt > now,
    "No-evidence bobber mode should schedule audio restore after linger")
assertTrue(addon._test.GetAudioDucked(),
    "Audio should remain ducked until stale bobber linger expires")

-- Case 13: Starting another cast during linger should clear the old linger timer and keep fishing state active.
local previousRestoreAt = audioRestoreAt
now = 814
currentCastName = "Fishing"
onEvent(fishingStateFrame, "UNIT_SPELLCAST_START", "player", "cast-guid", addon.const.fishingSpellID)
assertEquals(addon._test.GetSessionState(), addon.fishing.SessionStates.CASTING,
    "A new fishing cast should start immediately during linger")
assertEquals(addon._test.GetAudioRestoreAt(), nil,
    "Starting a new cast should clear the previous linger restore timer")
driveOnUpdateUntil(previousRestoreAt + 1)
assertEquals(addon._test.GetSessionState(), addon.fishing.SessionStates.CASTING,
    "Expired prior linger timer should not affect active fishing state")
assertTrue(addon._test.GetAudioDucked(),
    "Audio should remain ducked for the new active cast after the old linger timer would have expired")

resetState()
addon.db.focusedAudioLinger = 10
now = 800
currentCastName = "Fishing"
onEvent(fishingStateFrame, "UNIT_SPELLCAST_START", "player", "cast-guid", addon.const.fishingSpellID)
currentCastName = nil
now = 808
currentCastName = "Fishing"
onEvent(fishingStateFrame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-guid", addon.const.fishingChannelSpellID)
currentCastName = nil
assertEquals(addon._test.GetSessionState(), addon.fishing.SessionStates.WAITING_FOR_STRIKE,
    "Post-stop should enter WAITING_FOR_STRIKE before stale-evidence close")
driveOnUpdateUntil(813)
assertEquals(addon._test.GetSessionState(), addon.fishing.SessionStates.IDLE,
    "No-evidence bobber mode should transition to IDLE before linger timer is consumed")
audioRestoreAt = addon._test.GetAudioRestoreAt()
assertTrue(type(audioRestoreAt) == "number" and audioRestoreAt > now,
    "No-evidence bobber mode should schedule audio restore after linger")
driveOnUpdateUntil(audioRestoreAt + 1)
assertTrue(not addon._test.GetAudioDucked(),
    "Audio should restore after stale bobber linger expires")

print("PASS: audio_ducking_test")
