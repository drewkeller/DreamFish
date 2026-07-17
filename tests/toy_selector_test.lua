-- Unit tests for DreamFish owned-toy selector helpers.
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

local currentToyName = nil

local makeFrame = dofile("tests/mocks/frame_fixture.lua").makeFrame

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
    RequestLoadItemDataByID = function() end,
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
dofile("core/module_api.lua")
dofile("core/api_resolver.lua")
dofile("buff/tracking.lua")
dofile("buff/timing.lua")
dofile("buff/management.lua")
dofile("fishing/helpers.lua")
dofile("fishing/casting.lua")
dofile("fishing/state.lua")
dofile("audio/ducking.lua")
dofile("audio/alerts.lua")
dofile("ui/commands.lua")
dofile("ui/ace_widget_factory.lua")
dofile("ui/buff_item_drop_box.lua")
dofile("ui/config.lua")
dofile("DreamFish.lua")

local addon = _G.DreamFish
assertEquals(type(addon), "table", "Addon should load")

local bobbers = addon.utils.GetOwnedBobberToyItemIDs()
local rafts = addon.utils.GetOwnedRaftToyItemIDs()

assertEquals(#bobbers, 1, "Only owned bobber toys should be returned")
assertEquals(bobbers[1], 180993, "Owned bobber should be preserved")
assertEquals(#rafts, 1, "Only owned raft toys should be returned")
assertEquals(rafts[1], 85500, "Owned raft should be preserved")

assertTrue(addon.utils.GetToyLabel(180993):find("Toy"), "Toy label should resolve")

assertTrue(addon._test.RequestToyLabelWarmup == nil, "Toy warmup helper should not be exposed")
assertTrue(addon._test.RefreshToySelectors == nil, "Toy selector refresh helper should not be exposed")
assertTrue(addon._test.HandleToyItemDataLoadResult == nil, "Toy item data event helper should not be exposed")

currentToyName = "Toy 180993"
assertEquals(addon.utils.GetToyLabel(180993), "Toy 180993", "Toy box data should resolve the toy label")

print("PASS: toy_selector_test")
