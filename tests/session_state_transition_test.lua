-- Unit tests for canonical fishing session transitions.
-- Run with: lua tests/session_state_transition_test.lua

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

local function makeNoopFrame(name)
    local frame = {
        _name = name,
        _shown = false,
        _scripts = {},
        _events = {},
    }

    function frame:SetAllPoints() end
    function frame:SetFrameStrata() end
    function frame:SetClampedToScreen() end
    function frame:SetAttribute() end
    function frame:GetAttribute() return nil end
    function frame:RegisterForClicks() end
    function frame:Hide() self._shown = false end
    function frame:Show() self._shown = true end
    function frame:IsShown() return self._shown end
    function frame:HookScript() end
    function frame:RegisterEvent(event) self._events[event] = true end
    function frame:UnregisterEvent(event) self._events[event] = nil end
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
_G.C_Timer = nil
_G.InCombatLockdown = function() return false end
_G.ClearOverrideBindings = function() end
_G.SetOverrideBindingClick = function() end
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
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
_G.strtrim = function(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
_G.PlayerHasToy = function() return true end

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
assertTrue(type(addon.fishing) == "table", "Fishing namespace should exist")
assertTrue(type(addon.fishing.SessionStates) == "table", "Session state constants should exist")

local function findFrameWithEvent(eventName)
    for _, frame in ipairs(createdFrames) do
        if frame._events and frame._events[eventName] and frame._scripts and frame._scripts["OnEvent"] then
            return frame
        end
    end
    return nil
end

-- Fire ADDON_LOADED to initialize module runtime frames.
local rootFrame = nil
for _, frame in ipairs(createdFrames) do
    if frame.GetName and frame:GetName() == "DreamFisherFrame" and frame.GetScript and type(frame:GetScript("OnEvent")) == "function" then
        rootFrame = frame
    end
end
assertTrue(rootFrame ~= nil, "Root addon frame should exist")
rootFrame:GetScript("OnEvent")(rootFrame, "ADDON_LOADED", "DreamFisher")

local stateFrame = addon._test.GetFishingStateFrame()
assertTrue(stateFrame ~= nil, "Fishing state frame should exist")
local stateOnEvent = stateFrame:GetScript("OnEvent")
assertTrue(type(stateOnEvent) == "function", "Fishing state OnEvent should exist")

local lootFrame = findFrameWithEvent("LOOT_READY")
assertTrue(lootFrame ~= nil, "Loot tracker frame should exist")
local lootOnEvent = lootFrame:GetScript("OnEvent")
assertTrue(type(lootOnEvent) == "function", "Loot tracker OnEvent should exist")

addon._test.SetDB({
    focusedAudio = true,
    focusedAudioLinger = 10,
    autoLoot = true,
    bagAlerts = true,
    treasureAlerts = true,
    lowBagThreshold = 2,
})

addon._test.ClearSessionTransitionHistory()

assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.IDLE, "Initial session state should be IDLE")

-- Start fishing cast through spellcast event.
now = 200
stateOnEvent(stateFrame, "UNIT_SPELLCAST_START", "player", nil, addon.const.fishingSpellID)
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.CASTING, "Cast start should move to CASTING")

-- Stop cast before expiry so bobber/strike window is entered.
now = 201
stateOnEvent(stateFrame, "UNIT_SPELLCAST_STOP", "player", nil, addon.const.fishingSpellID)
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.WAITING_FOR_STRIKE,
    "Cast stop should move to WAITING_FOR_STRIKE")

local history = addon._test.GetSessionTransitionHistory()
assertTrue(#history >= 3, "Transition history should include pre-cast, cast start, and cast stop transitions")
assertEquals(history[1].fromState, addon.fishing.SessionStates.IDLE,
    "First transition should start from IDLE")
assertEquals(history[1].toState, addon.fishing.SessionStates.PRE_CASTING,
    "First transition should move to PRE_CASTING")
assertEquals(history[1].reason, "cast-start-recover-pre-cast-from-closing",
    "First transition should use recover-pre-cast reason")
assertEquals(history[2].fromState, addon.fishing.SessionStates.PRE_CASTING,
    "Second transition should start from PRE_CASTING")
assertEquals(history[2].toState, addon.fishing.SessionStates.CASTING,
    "Second transition should move to CASTING")
assertEquals(history[2].reason, "cast-start-fishing",
    "Second transition should use cast-start-fishing reason")
assertEquals(history[3].fromState, addon.fishing.SessionStates.CASTING,
    "Third transition should start from CASTING")
assertEquals(history[3].toState, addon.fishing.SessionStates.WAITING_FOR_BITE,
    "Third transition should move to WAITING_FOR_BITE")
assertEquals(history[3].reason, "cast-phase-ended-enter-waiting-for-bite",
    "Third transition should use cast-phase-ended-enter-waiting-for-bite reason")

-- No-hook-evidence timeout should pass through STARTING_LINGER before close.
now = 206
local stateOnUpdate = stateFrame:GetScript("OnUpdate")
assertTrue(type(stateOnUpdate) == "function", "State frame OnUpdate should exist in waiting-for-strike window")
stateOnUpdate(stateFrame, 0.2)
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.CLOSING_FISHING_SESSION,
    "No-hook-evidence timeout should finalize to CLOSING_FISHING_SESSION")

history = addon._test.GetSessionTransitionHistory()
local noHookCloseTransition = history[#history]
local noHookStartingLingerTransition = history[#history - 1]
assertTrue(noHookCloseTransition ~= nil, "Transition history should include no-hook-evidence close transition")
assertTrue(noHookStartingLingerTransition ~= nil,
    "Transition history should include no-hook-evidence starting-linger transition")
assertEquals(noHookStartingLingerTransition.fromState, addon.fishing.SessionStates.WAITING_FOR_STRIKE,
    "No-hook-evidence starting-linger transition should originate from WAITING_FOR_STRIKE")
assertEquals(noHookStartingLingerTransition.toState, addon.fishing.SessionStates.STARTING_LINGER,
    "No-hook-evidence starting-linger transition should move to STARTING_LINGER")
assertEquals(noHookStartingLingerTransition.reason, "post-stop-no-hooked-evidence-starting-linger",
    "No-hook-evidence starting-linger transition should use canonical starting-linger reason")
assertEquals(noHookCloseTransition.fromState, addon.fishing.SessionStates.STARTING_LINGER,
    "No-hook-evidence close transition should originate from STARTING_LINGER")
assertEquals(noHookCloseTransition.toState, addon.fishing.SessionStates.CLOSING_FISHING_SESSION,
    "No-hook-evidence close transition should move to CLOSING_FISHING_SESSION")
assertEquals(noHookCloseTransition.reason, "post-stop-no-hooked-evidence-close",
    "No-hook-evidence close transition should use canonical close reason")

-- Re-enter for loot flow assertions below.
now = 210
stateOnEvent(stateFrame, "UNIT_SPELLCAST_START", "player", nil, addon.const.fishingSpellID)
now = 211
stateOnEvent(stateFrame, "UNIT_SPELLCAST_STOP", "player", nil, addon.const.fishingSpellID)
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.WAITING_FOR_STRIKE,
    "Cast stop should move to WAITING_FOR_STRIKE before loot assertions")

-- Loot starts.
lootOnEvent(lootFrame, "LOOT_READY")
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.LOOTING,
    "LOOT_READY should move to LOOTING")

history = addon._test.GetSessionTransitionHistory()
local lootStartTransition = history[#history]
assertTrue(lootStartTransition ~= nil, "Transition history should include loot-start transition")
assertEquals(lootStartTransition.fromState, addon.fishing.SessionStates.WAITING_FOR_STRIKE,
    "Loot-start transition should originate from WAITING_FOR_STRIKE")
assertEquals(lootStartTransition.toState, addon.fishing.SessionStates.LOOTING,
    "Loot-start transition should move to LOOTING")
assertEquals(lootStartTransition.reason, "loot-ready",
    "Loot-start transition should use loot-ready reason")

-- Loot closes.
lootOnEvent(lootFrame, "LOOT_CLOSED")
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.CLOSING_FISHING_SESSION,
    "LOOT_CLOSED should finalize to CLOSING_FISHING_SESSION")

history = addon._test.GetSessionTransitionHistory()
local lootCloseTransition = history[#history]
local lootStartingLingerTransition = history[#history - 1]
assertTrue(lootCloseTransition ~= nil, "Transition history should include loot-close transition")
assertTrue(lootStartingLingerTransition ~= nil,
    "Transition history should include loot-starting-linger transition")
assertEquals(lootStartingLingerTransition.fromState, addon.fishing.SessionStates.LOOTING,
    "Loot-starting-linger transition should originate from LOOTING")
assertEquals(lootStartingLingerTransition.toState, addon.fishing.SessionStates.STARTING_LINGER,
    "Loot-starting-linger transition should move to STARTING_LINGER")
assertEquals(lootStartingLingerTransition.reason, "loot-closed-starting-linger",
    "Loot-starting-linger transition should use loot-closed-starting-linger reason")

assertEquals(lootCloseTransition.fromState, addon.fishing.SessionStates.STARTING_LINGER,
    "Loot-close transition should originate from STARTING_LINGER")
assertEquals(lootCloseTransition.toState, addon.fishing.SessionStates.CLOSING_FISHING_SESSION,
    "Loot-close transition should move to CLOSING_FISHING_SESSION")
assertEquals(lootCloseTransition.reason, "loot-closed",
    "Loot-close transition should use loot-closed reason")

-- Cancellation path should preserve explicit canonical cancel state.
now = 300
stateOnEvent(stateFrame, "UNIT_SPELLCAST_START", "player", nil, addon.const.fishingSpellID)
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.CASTING,
    "Cast start should move to CASTING before cancellation test")

history = addon._test.GetSessionTransitionHistory()
local castStartTransition = history[#history]
local recoverPreCastTransition = history[#history - 1]
assertTrue(castStartTransition ~= nil, "Transition history should include cast-start transition")
assertTrue(recoverPreCastTransition ~= nil,
    "Transition history should include recover-pre-cast transition when starting from close")
assertEquals(recoverPreCastTransition.fromState, addon.fishing.SessionStates.CLOSING_FISHING_SESSION,
    "Recover-pre-cast transition should originate from CLOSING_FISHING_SESSION")
assertEquals(recoverPreCastTransition.toState, addon.fishing.SessionStates.PRE_CASTING,
    "Recover-pre-cast transition should move to PRE_CASTING")
assertEquals(recoverPreCastTransition.reason, "cast-start-recover-pre-cast-from-closing",
    "Recover-pre-cast transition should use canonical reason")
assertEquals(castStartTransition.fromState, addon.fishing.SessionStates.PRE_CASTING,
    "Cast-start transition should originate from PRE_CASTING after close recovery")
assertEquals(castStartTransition.toState, addon.fishing.SessionStates.CASTING,
    "Cast-start transition should move to CASTING")
assertEquals(castStartTransition.reason, "cast-start-fishing",
    "Cast-start transition should use cast-start-fishing reason")

stateOnEvent(stateFrame, "PLAYER_REGEN_DISABLED")
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.CLOSING_FISHING_SESSION,
    "Combat cancellation should finalize to CLOSING_FISHING_SESSION state")

-- Linger zero should close immediately on cast stop.
addon._test.SetDB({
    focusedAudio = true,
    focusedAudioLinger = 0,
    autoLoot = true,
    bagAlerts = true,
    treasureAlerts = true,
    lowBagThreshold = 2,
})

now = 400
stateOnEvent(stateFrame, "UNIT_SPELLCAST_START", "player", nil, addon.const.fishingSpellID)
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.CASTING,
    "Cast start should move to CASTING before linger-zero stop")

now = 401
stateOnEvent(stateFrame, "UNIT_SPELLCAST_STOP", "player", nil, addon.const.fishingSpellID)
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.CLOSING_FISHING_SESSION,
    "Linger-zero cast stop should immediately move to CLOSING_FISHING_SESSION")

print("PASS: session_state_transition_test")
