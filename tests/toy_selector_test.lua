-- Unit tests for DreamFisher owned-toy selector helpers.
-- Run with: lua tests/toy_selector_test.lua

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

local toyOwnership = {
    [180993] = true,
    [85500] = true,
}

local requestedToyData = {}
local currentToyName = nil

local function makeFrame()
    local scripts = {}
    return {
        SetAllPoints = function() end,
        SetFrameStrata = function() end,
        RegisterForClicks = function() end,
        RegisterForDrag = function() end,
        EnableMouse = function() end,
        EnableKeyboard = function() end,
        SetMovable = function() end,
        SetClampedToScreen = function() end,
        SetBackdrop = function() end,
        SetBackdropColor = function() end,
        SetBackdropBorderColor = function() end,
        SetSize = function() end,
        SetPoint = function() end,
        RegisterEvent = function() end,
        IsShown = function() return false end,
        Show = function() end,
        Hide = function() end,
        SetAttribute = function() end,
        GetAttribute = function() return nil end,
        GetName = function() return "Frame" end,
        SetScript = function(self, event, handler)
            scripts[event] = handler
        end,
        HookScript = function(self, event, handler)
            scripts[event] = handler
        end,
        GetScript = function(self, event)
            return scripts[event]
        end,
        CreateFontString = function()
            return {
                SetPoint = function() end,
                SetText = function() end,
                SetTextColor = function() end,
                SetJustifyH = function() end,
            }
        end,
        CreateTexture = function()
            return {
                SetAllPoints = function() end,
                SetTexture = function() end,
                SetPoint = function() end,
            }
        end,
        StartMoving = function() end,
        StopMovingOrSizing = function() end,
        UnregisterEvent = function() end,
    }
end

_G.CreateFrame = function()
    return makeFrame()
end

_G.PlayerHasToy = function(itemID)
    return toyOwnership[itemID] == true
end

_G.GetItemInfo = function(itemID)
    if tonumber(itemID) == 180993 and currentToyName then
        return nil
    end
    return "Toy " .. tostring(itemID)
end

_G.C_ToyBox = {
    GetToyInfo = function(itemID)
        if tonumber(itemID) == 180993 and currentToyName then
            return nil, currentToyName
        end
        return nil, nil
    end,
}

_G.C_Item = {
    RequestLoadItemDataByID = function(itemID)
        table.insert(requestedToyData, tonumber(itemID))
    end,
}

_G.SetOverrideBindingClick = function() end
_G.ClearOverrideBindings = function() end
_G.InCombatLockdown = function() return false end
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.GetCVar = function() return "1.0" end
_G.GetTime = function() return 1000 end
_G.ContainerNumSlots = function() return 0 end
_G.ContainerItemID = function() return nil end
_G.NUM_BAG_SLOTS = 4
_G.SlashCmdList = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.UIParent = {}
_G.C_Container = nil
_G.WorldFrame = nil

dofile("core/init.lua")
dofile("core/utils.lua")
dofile("buff/tracking.lua")
dofile("buff/timing.lua")
dofile("buff/management.lua")
dofile("fishing/helpers.lua")
dofile("fishing/casting.lua")
dofile("fishing/state.lua")
dofile("audio/ducking.lua")
dofile("audio/alerts.lua")
dofile("ui/commands.lua")
dofile("ui/buff_item_drop_box.lua")
dofile("ui/config.lua")
dofile("DreamFisher.lua")

local addon = _G.DreamFisher
assertEquals(type(addon), "table", "Addon should load")

assertTrue(#requestedToyData > 0, "Addon load should request toy item data")
assertTrue(requestedToyData[1] == 180993 or requestedToyData[1] == 85500,
    "Toy warmup should request configured toy item data")

local bobbers = addon.utils.GetOwnedBobberToyItemIDs()
local rafts = addon.utils.GetOwnedRaftToyItemIDs()

assertEquals(#bobbers, 1, "Only owned bobber toys should be returned")
assertEquals(bobbers[1], 180993, "Owned bobber should be preserved")
assertEquals(#rafts, 1, "Only owned raft toys should be returned")
assertEquals(rafts[1], 85500, "Owned raft should be preserved")

assertTrue(addon.utils.GetToyLabel(180993):find("Toy"), "Toy label should resolve")

local refreshCount = 0
local originalUpdateConfigUI = addon.config.UpdateConfigUI
addon.frames.config = {}
addon.config.UpdateConfigUI = function()
    refreshCount = refreshCount + 1
end

assertTrue(type(addon._test.RefreshToySelectors) == "function", "Toy refresh helper should be exposed for tests")
addon._test.RefreshToySelectors()
addon._test.RefreshToySelectors()

assertEquals(refreshCount, 2, "Toy data events should refresh the config UI")

local warmupCount = 0
addon.config.UpdateConfigUI = function()
    warmupCount = warmupCount + 1
end

local warmupResult = addon._test.RequestToyLabelWarmup()
assertTrue(type(warmupResult) == "table", "Toy warmup should return the loaded item set")

assertTrue(type(addon._test.HandleToyItemDataLoadResult) == "function", "Toy data event handler should be exposed for tests")
addon._test.HandleToyItemDataLoadResult(nil, "ITEM_DATA_LOAD_RESULT", 180993, true)
addon._test.HandleToyItemDataLoadResult(nil, "ITEM_DATA_LOAD_RESULT", 85500, true)
addon._test.HandleToyItemDataLoadResult(nil, "ITEM_DATA_LOAD_RESULT", 999999, true)

assertEquals(warmupCount, 2, "Toy data load results should refresh only for warmed-up toy IDs")

addon.config.UpdateConfigUI = originalUpdateConfigUI

currentToyName = "Toy 180993"
assertEquals(addon.utils.GetToyLabel(180993), "Toy 180993", "Toy box data should resolve the toy label")

print("PASS: toy_selector_test")