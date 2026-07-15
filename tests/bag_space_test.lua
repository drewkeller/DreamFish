-- Unit tests for DreamFish bag-space behavior.
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
        GetName = function() return "DreamFishSecureFishingButton" end,
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
dofile("core/init.lua")
dofile("core/utils.lua")
dofile("core/module_api.lua")
dofile("core/api_resolver.lua")
dofile("fishing/helpers.lua")
dofile("DreamFish.lua")

local addon = _G.DreamFish
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

-- Case 2: Warning fires at threshold and is throttled for 60 seconds.
addon._test.SetDB({ bagAlertsThreshold = 2, bagAlerts = true, reagentBagAlerts = true, reagentBagAlertsThreshold = 2 })
addon._test.ResetBagWarningState()
clearMessages()
now = 100
addon._test.CheckBagSpace()
assertEquals(#messages, 1, "Should warn when free slots are at threshold")
assertTrue(string.find(messages[1], "Low bag space!", 1, true) ~= nil, "Warning message should contain expected text")

now = 105
addon._test.CheckBagSpace()
assertEquals(#messages, 1, "Should not warn again before cooldown expires")

now = 161
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
addon._test.SetDB({ bagAlertsThreshold = 1, bagAlerts = true, reagentBagAlerts = true, reagentBagAlertsThreshold = 1 })
addon._test.ResetBagWarningState()
clearMessages()
now = 200
addon._test.CheckBagSpace()
assertEquals(#messages, 0, "Should not warn when free slots exceed threshold")

-- Case 4: Warning fires when regular bags are above threshold but reagent bag is at threshold.
setBagState(
    {
        [0] = 4,
        [5] = 2,
    },
    {
        [0] = { [1] = nil, [2] = nil, [3] = nil, [4] = nil },
        [5] = { [1] = 444, [2] = nil },
    }
)
addon._test.SetDB({ bagAlertsThreshold = 1, bagAlerts = true, reagentBagAlerts = true, reagentBagAlertsThreshold = 1 })
addon._test.ResetBagWarningState()
clearMessages()
now = 300
addon._test.CheckBagSpace()
assertEquals(#messages, 1, "Should warn when reagent bag free slots are at threshold")
assertTrue(string.find(messages[1], "Reagent: 1", 1, true) ~= nil, "Warning should include reagent free-slot count")

-- Case 5: Normal-bag alert can fire while reagent-bag alert is disabled.
setBagState(
    {
        [0] = 2,
        [5] = 2,
    },
    {
        [0] = { [1] = 555, [2] = nil },
        [5] = { [1] = 666, [2] = 777 },
    }
)
addon._test.SetDB({ bagAlertsThreshold = 1, bagAlerts = true, reagentBagAlerts = false, reagentBagAlertsThreshold = 0 })
addon._test.ResetBagWarningState()
clearMessages()
now = 400
addon._test.CheckBagSpace()
assertEquals(#messages, 1, "Should warn when regular bag slots are low and reagent alerts are disabled")
assertTrue(string.find(messages[1], "Bags: 1", 1, true) ~= nil,
    "Normal-only warning should include regular free-slot count")

-- Case 6: Reagent-bag alert can fire while normal-bag alert is disabled.
setBagState(
    {
        [0] = 4,
        [5] = 2,
    },
    {
        [0] = { [1] = nil, [2] = nil, [3] = nil, [4] = nil },
        [5] = { [1] = 888, [2] = nil },
    }
)
addon._test.SetDB({ bagAlertsThreshold = 0, bagAlerts = false, reagentBagAlerts = true, reagentBagAlertsThreshold = 1 })
addon._test.ResetBagWarningState()
clearMessages()
now = 500
addon._test.CheckBagSpace()
assertEquals(#messages, 1, "Should warn when reagent bag slots are low and normal alerts are disabled")
assertTrue(string.find(messages[1], "Reagent: 1", 1, true) ~= nil,
    "Reagent-only warning should include reagent free-slot count")

-- Case 6b: A disabled reagent-bag alert should not fire just because reagent slots are low.
setBagState(
    {
        [0] = 3,
        [5] = 2,
    },
    {
        [0] = { [1] = nil, [2] = nil, [3] = 1333 },
        [5] = { [1] = 1444, [2] = nil },
    }
)
addon._test.SetDB({ bagAlertsThreshold = 1, bagAlerts = true, reagentBagAlerts = false, reagentBagAlertsThreshold = 1 })
addon._test.ResetBagWarningState()
clearMessages()
now = 550
addon._test.CheckBagSpace()
assertEquals(#messages, 0, "Should not warn when only reagent slots are low and reagent alerts are disabled")

-- Case 7: Different thresholds should independently gate regular and reagent alerts.
setBagState(
    {
        [0] = 3,
        [5] = 3,
    },
    {
        [0] = { [1] = 999, [2] = nil, [3] = nil },
        [5] = { [1] = 1111, [2] = 1222, [3] = nil },
    }
)
addon._test.SetDB({ bagAlertsThreshold = 2, bagAlerts = true, reagentBagAlerts = true, reagentBagAlertsThreshold = 0 })
addon._test.ResetBagWarningState()
clearMessages()
now = 600
addon._test.CheckBagSpace()
assertEquals(#messages, 1, "Should warn when regular bag threshold is met even if reagent threshold is not")
assertTrue(string.find(messages[1], "Bags: 2", 1, true) ~= nil,
    "Different-threshold warning should include regular free-slot count")
assertTrue(string.find(messages[1], "Reagent: 1", 1, true) ~= nil,
    "Different-threshold warning should include reagent free-slot count")

print("PASS: bag_space_test")
