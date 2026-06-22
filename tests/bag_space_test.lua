-- Unit tests for DreamFisher bag-space behavior.
-- Run with: lua tests/bag_space_test.lua

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
    return {
        SetAllPoints = function() end,
        SetFrameStrata = function() end,
        SetAttribute = function() end,
        RegisterForClicks = function() end,
        Hide = function() end,
        HookScript = function() end,
        RegisterEvent = function() end,
        SetScript = function() end,
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
        UnregisterEvent = function() end,
        GetName = function() return "DreamFisherSecureFishingButton" end,
    }
end

local now = 100
local messages = {}
local bagSlots = {}
local bagItems = {}

_G.CreateFrame = function()
    local frame = makeNoopFrame()
    frame.Text = { SetText = function() end, SetTextColor = function() end }
    frame.GetChecked = function() return true end
    frame.GetText = function() return "2" end
    return frame
end

_G.UIParent = {}
_G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg)
        table.insert(messages, msg)
    end,
}
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
_G.PlaySound = function() end
_G.SOUNDKIT = {}
_G.GetCVar = function() return "0" end
_G.SetCVar = function() end
_G.GetContainerNumSlots = function(bag)
    return bagSlots[bag] or 0
end
_G.GetContainerItemID = function(bag, slot)
    local byBag = bagItems[bag]
    if not byBag then
        return nil
    end
    return byBag[slot]
end

local function setBagState(slotsTable, itemsTable)
    bagSlots = slotsTable or {}
    bagItems = itemsTable or {}
end

local function clearMessages()
    messages = {}
end

-- Load addon file in mocked environment.
dofile("DreamFisher.lua")

local addon = _G.DreamFisher
assertEquals(type(addon), "table", "Addon table should exist")
assertEquals(type(addon._test), "table", "Test hooks should exist")

-- Case 1: Free slots include both main bags and reagent bag.
setBagState(
    {
        [0] = 2,
        [1] = 1,
        [5] = 2,
    },
    {
        [0] = { [1] = 111, [2] = nil },
        [1] = { [1] = nil },
        [5] = { [1] = 999, [2] = 1000 },
    }
)
assertEquals(addon._test.GetFreeBagSlots(), 2, "Should count free slots across normal and reagent bags")

-- Case 2: Warning fires at threshold and is throttled for 10 seconds.
addon._test.SetDB({ lowBagThreshold = 2 })
addon._test.ResetBagWarningState()
clearMessages()
now = 100
addon._test.CheckBagSpace()
assertEquals(#messages, 1, "Should warn when free slots are at threshold")
assertTrue(string.find(messages[1], "Low bag space!", 1, true) ~= nil, "Warning message should contain expected text")

now = 105
addon._test.CheckBagSpace()
assertEquals(#messages, 1, "Should not warn again before cooldown expires")

now = 111
addon._test.CheckBagSpace()
assertEquals(#messages, 2, "Should warn again after cooldown expires")

-- Case 3: No warning when free slots are above threshold.
setBagState(
    {
        [0] = 3,
        [5] = 2,
    },
    {
        [0] = { [1] = nil, [2] = nil, [3] = 333 },
        [5] = { [1] = nil, [2] = nil },
    }
)
addon._test.SetDB({ lowBagThreshold = 1 })
addon._test.ResetBagWarningState()
clearMessages()
now = 200
addon._test.CheckBagSpace()
assertEquals(#messages, 0, "Should not warn when free slots exceed threshold")

print("PASS: bag_space_test")
