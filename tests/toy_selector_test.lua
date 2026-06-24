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

local function makeFrame()
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
        SetScript = function() end,
        HookScript = function() end,
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
    return "Toy " .. tostring(itemID)
end

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
dofile("ui/config.lua")
dofile("DreamFisher.lua")

local addon = _G.DreamFisher
assertEquals(type(addon), "table", "Addon should load")

local bobbers = addon.utils.GetOwnedBobberToyItemIDs()
local rafts = addon.utils.GetOwnedRaftToyItemIDs()

assertEquals(#bobbers, 1, "Only owned bobber toys should be returned")
assertEquals(bobbers[1], 180993, "Owned bobber should be preserved")
assertEquals(#rafts, 1, "Only owned raft toys should be returned")
assertEquals(rafts[1], 85500, "Owned raft should be preserved")

assertTrue(addon.utils.GetToyLabel(180993):find("Toy"), "Toy label should resolve")

print("PASS: toy_selector_test")