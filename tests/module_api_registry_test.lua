-- Unit tests for DreamFish module API registry wiring.
-- Run with: lua tests/module_api_registry_test.lua

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

local makeNoopFrame = dofile("tests/mocks/noop_frame.lua").makeNoopFrame

local createdFrames = {}

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
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.GetTime = function() return 100 end
_G.PlaySound = function() end
_G.SOUNDKIT = {}
_G.GetSpellInfo = function() return "Fishing" end
_G.GetContainerNumSlots = function() return 0 end
_G.GetContainerItemID = function() return nil end
_G.GetCVar = function() return "0" end
_G.SetCVar = function() end
_G.C_Timer = nil
_G.strtrim = function(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Mirror TOC load order relevant to registry wiring.
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
assertTrue(type(addon) == "table", "Addon table should exist")
assertTrue(type(addon.moduleAPI) == "table", "moduleAPI registry should exist")
assertTrue(type(addon.moduleAPI.Get) == "function", "moduleAPI.Get should exist")
assertTrue(type(addon.moduleAPI.Require) == "function", "moduleAPI.Require should exist")
assertTrue(type(addon.ResolveModuleAPI) == "function", "ResolveModuleAPI helper should exist")
assertTrue(type(addon.RequireModuleAPI) == "function", "RequireModuleAPI helper should exist")
assertTrue(type(addon.GetFishingAPI) == "function", "GetFishingAPI helper should exist")
assertTrue(type(addon.GetAudioAPI) == "function", "GetAudioAPI helper should exist")
assertTrue(type(addon.GetAlertsAPI) == "function", "GetAlertsAPI helper should exist")
assertTrue(type(addon.GetUIFocusAPI) == "function", "GetUIFocusAPI helper should exist")
assertTrue(type(addon.RequireFishingAPI) == "function", "RequireFishingAPI helper should exist")
assertTrue(type(addon.RequireAudioAPI) == "function", "RequireAudioAPI helper should exist")
assertTrue(type(addon.RequireAlertsAPI) == "function", "RequireAlertsAPI helper should exist")
assertTrue(type(addon.RequireUIFocusAPI) == "function", "RequireUIFocusAPI helper should exist")

local fishingAPI = addon.moduleAPI.Get("fishing")
local audioAPI = addon.moduleAPI.Get("audio")
local alertsAPI = addon.moduleAPI.Get("alerts")
local uiFocusAPI = addon.moduleAPI.Get("uiFocus")

assertTrue(type(fishingAPI) == "table", "Fishing API should be registered")
assertTrue(type(audioAPI) == "table", "Audio API should be registered")
assertTrue(type(alertsAPI) == "table", "Alerts API should be registered")
assertTrue(type(uiFocusAPI) == "table", "UI focus API should be registered")
assertEquals(fishingAPI, addon.fishing, "Fishing registry entry should point to addon.fishing")
assertEquals(audioAPI, addon.audio, "Audio registry entry should point to addon.audio")
assertEquals(alertsAPI, addon.alerts, "Alerts registry entry should point to addon.alerts")
assertEquals(uiFocusAPI, addon.uiFocus, "UI focus registry entry should point to addon.uiFocus")

local requiredFishing = addon.moduleAPI.Require("fishing")
local requiredAudio = addon.moduleAPI.Require("audio")
local requiredAlerts = addon.moduleAPI.Require("alerts")
local requiredUIFocus = addon.moduleAPI.Require("uiFocus")
assertEquals(requiredFishing, fishingAPI, "Require fishing should return registered fishing API")
assertEquals(requiredAudio, audioAPI, "Require audio should return registered audio API")
assertEquals(requiredAlerts, alertsAPI, "Require alerts should return registered alerts API")
assertEquals(requiredUIFocus, uiFocusAPI, "Require uiFocus should return registered uiFocus API")

assertEquals(addon.ResolveModuleAPI("fishing", "fishing"), fishingAPI,
    "ResolveModuleAPI should prefer registered fishing API")
assertEquals(addon.RequireModuleAPI("audio", "audio"), audioAPI,
    "RequireModuleAPI should return registered audio API")
assertEquals(addon.GetFishingAPI(), fishingAPI,
    "GetFishingAPI should return registered fishing API")
assertEquals(addon.GetAudioAPI(), audioAPI,
    "GetAudioAPI should return registered audio API")
assertEquals(addon.GetAlertsAPI(), alertsAPI,
    "GetAlertsAPI should return registered alerts API")
assertEquals(addon.GetUIFocusAPI(), uiFocusAPI,
    "GetUIFocusAPI should return registered uiFocus API")
assertEquals(addon.RequireFishingAPI(), fishingAPI,
    "RequireFishingAPI should return registered fishing API")
assertEquals(addon.RequireAudioAPI(), audioAPI,
    "RequireAudioAPI should return registered audio API")
assertEquals(addon.RequireAlertsAPI(), alertsAPI,
    "RequireAlertsAPI should return registered alerts API")
assertEquals(addon.RequireUIFocusAPI(), uiFocusAPI,
    "RequireUIFocusAPI should return registered uiFocus API")

local ok, err = pcall(function()
    addon.moduleAPI.Require("missing_module")
end)
assertTrue(ok == false, "Require should error for missing module")
assertTrue(type(err) == "string" and string.find(err, "required module API is missing", 1, true) ~= nil,
    "Missing-module Require error should include clear message")

local ok2, err2 = pcall(function()
    addon.RequireModuleAPI("missing_module", "missingField")
end)
assertTrue(ok2 == false, "RequireModuleAPI should error for missing module")
assertTrue(type(err2) == "string" and string.find(err2, "required module API is missing", 1, true) ~= nil,
    "Missing-module RequireModuleAPI error should include clear message")

local originalFishingRegistryAPI = addon.moduleAPI._registry.fishing
local originalFishingFallbackAPI = addon.fishing
addon.moduleAPI._registry.fishing = nil
addon.fishing = nil

local ok3, err3 = pcall(function()
    addon.RequireFishingAPI()
end)

addon.moduleAPI._registry.fishing = originalFishingRegistryAPI
addon.fishing = originalFishingFallbackAPI

assertTrue(ok3 == false, "RequireFishingAPI should error when both registry and fallback are unavailable")
assertTrue(type(err3) == "string" and string.find(err3, "required module API is missing", 1, true) ~= nil,
    "RequireFishingAPI missing-module error should include clear message")

local originalAudioRegistryAPI = addon.moduleAPI._registry.audio
local originalAudioFallbackAPI = addon.audio
addon.moduleAPI._registry.audio = nil
addon.audio = nil

local ok4, err4 = pcall(function()
    addon.RequireAudioAPI()
end)

addon.moduleAPI._registry.audio = originalAudioRegistryAPI
addon.audio = originalAudioFallbackAPI

assertTrue(ok4 == false, "RequireAudioAPI should error when both registry and fallback are unavailable")
assertTrue(type(err4) == "string" and string.find(err4, "required module API is missing", 1, true) ~= nil,
    "RequireAudioAPI missing-module error should include clear message")

local originalAlertsRegistryAPI = addon.moduleAPI._registry.alerts
local originalAlertsFallbackAPI = addon.alerts
addon.moduleAPI._registry.alerts = nil
addon.alerts = nil

local ok5, err5 = pcall(function()
    addon.RequireAlertsAPI()
end)

addon.moduleAPI._registry.alerts = originalAlertsRegistryAPI
addon.alerts = originalAlertsFallbackAPI

assertTrue(ok5 == false, "RequireAlertsAPI should error when both registry and fallback are unavailable")
assertTrue(type(err5) == "string" and string.find(err5, "required module API is missing", 1, true) ~= nil,
    "RequireAlertsAPI missing-module error should include clear message")

local originalUIFocusRegistryAPI = addon.moduleAPI._registry.uiFocus
local originalUIFocusFallbackAPI = addon.uiFocus
addon.moduleAPI._registry.uiFocus = nil
addon.uiFocus = nil

local ok6, err6 = pcall(function()
    addon.RequireUIFocusAPI()
end)

addon.moduleAPI._registry.uiFocus = originalUIFocusRegistryAPI
addon.uiFocus = originalUIFocusFallbackAPI

assertTrue(ok6 == false, "RequireUIFocusAPI should error when both registry and fallback are unavailable")
assertTrue(type(err6) == "string" and string.find(err6, "required module API is missing", 1, true) ~= nil,
    "RequireUIFocusAPI missing-module error should include clear message")

print("PASS: module_api_registry_test")
