-- Unit tests for DreamFisher casting modes (right-click double-click behavior).
-- Run with: lua tests/casting_modes_test.lua

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

local function assertFalse(value, message)
    if value then
        error((message or "assertFalse failed"), 2)
    end
end

local mockTime = 1000
local mockInCombat = false

-- Mock WoW APIs
_G.GetTime = function()
    return mockTime
end

_G.InCombatLockdown = function()
    return mockInCombat
end

_G.Clamp = function(value, min, max)
    if value == nil then return min end
    if value < min then return min end
    if value > max then return max end
    return value
end

_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.GetCVar = function() return "1.0" end

local function makeFrame()
    return {
        IsShown = function() return false end,
        Show = function() end,
        Hide = function() end,
        SetAttribute = function() end,
        GetAttribute = function() return nil end,
        GetName = function() return "Frame" end,
    }
end

_G.CreateFrame = function()
    return makeFrame()
end

_G.SetOverrideBindingClick = function() end
_G.ClearOverrideBindings = function() end
_G.ContainerNumSlots = function() return 16 end
_G.ContainerItemID = function() return nil end
_G.GetItemInfo = function(id) return "Item " .. id end
_G.NUM_BAG_SLOTS = 4
_G.SlashCmdList = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.UIParent = {}
_G.WorldFrame = nil

-- Load the addon
dofile("DreamFisher.lua")

local tests = {}
local testsPassed = 0
local testsFailed = 0

function RunTest(name, testFn)
    mockTime = 1000
    mockInCombat = false

    local success, err = pcall(function()
        DreamFisher._test.SetDB({
            buffItems = {},
            buffAuraByItem = {},
            refreshSeconds = 180,
        })
        DreamFisher._test.SetLastRightClickTime(0)  -- Clear click state
        testFn()
    end)

    if success then
        print("[PASS] " .. name)
        testsPassed = testsPassed + 1
    else
        print("[FAIL] " .. name .. " - " .. err)
        testsFailed = testsFailed + 1
    end
end

-- ============================================================================
-- Tests: Single Right-Click
-- ============================================================================

function tests.SingleClickRecordsTime()
    -- First right-click should record the time
    DreamFisher._test.SetLastRightClickTime(0)
    mockTime = 1000

    DreamFisher._test.HandleWorldRightClick()

    local lastTime = DreamFisher._test.GetLastRightClickTime()
    assertEquals(lastTime, 1000, "Single right-click should record time")
end

function tests.SingleClickClearsBindings()
    -- Single right-click should clear override bindings (awaiting double-click)
    -- This is tested indirectly: if second click is within window, it processes double-click
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111, refreshSeconds = 60 } },
        buffAuraByItem = {},
    })

    -- Buff is due
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 100)

    -- Mock FindItemInBags
    local originalFind = _G.FindItemInBags
    _G.FindItemInBags = function() return 0, 1 end

    -- First click
    mockTime = 1000
    DreamFisher._test.HandleWorldRightClick()
    local firstTime = DreamFisher._test.GetLastRightClickTime()
    assertEquals(firstTime, 1000, "First click recorded")

    -- Second click within window should be double-click
    mockTime = 1000.1
    DreamFisher._test.HandleWorldRightClick()

    -- Double-click should reset time to 0 (processed)
    local secondTime = DreamFisher._test.GetLastRightClickTime()
    assertEquals(secondTime, 0, "Double-click should reset time after processing")

    _G.FindItemInBags = originalFind
end

-- ============================================================================
-- Tests: Double-Click with Due Buff
-- ============================================================================

function tests.DoubleClickDueBuff()
    -- Double-click with due buff should use the buff
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111, refreshSeconds = 60 } },
        buffAuraByItem = {},
    })

    -- Buff is due (used long ago)
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 100)

    -- Mock FindItemInBags
    local originalFind = _G.FindItemInBags
    _G.FindItemInBags = function(itemID)
        if itemID == 111 then return 0, 1 end
        return nil, nil
    end

    -- First click
    mockTime = 1000
    DreamFisher._test.HandleWorldRightClick()

    -- Second click within window (0.25s)
    mockTime = 1000.1
    DreamFisher._test.HandleWorldRightClick()

    -- After double-click with due buff, time should be reset
    local finalTime = DreamFisher._test.GetLastRightClickTime()
    assertEquals(finalTime, 0, "Double-click with due buff should reset time (buff processed)")

    _G.FindItemInBags = originalFind
end

function tests.DoubleClickSelectsFirstDueBuff()
    -- When multiple buffs are due, double-click uses first one
    DreamFisher._test.SetDB({
        buffItems = {
            { itemID = 111, refreshSeconds = 60 },
            { itemID = 222, refreshSeconds = 60 },
        },
        buffAuraByItem = {},
    })

    -- Both due
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 100)
    DreamFisher._test.SetBuffLastUseTime(222, mockTime - 100)

    -- Mock FindItemInBags
    local originalFind = _G.FindItemInBags
    local findCalls = {}
    _G.FindItemInBags = function(itemID)
        table.insert(findCalls, itemID)
        if itemID == 111 then return 0, 1 end
        if itemID == 222 then return 0, 2 end
        return nil, nil
    end

    -- First click
    mockTime = 1000
    DreamFisher._test.HandleWorldRightClick()

    -- Second click within window
    mockTime = 1000.1
    DreamFisher._test.HandleWorldRightClick()

    -- Should have searched for item 111 first
    assertTrue(findCalls[1] == 111, "Should search for first buff item first")

    _G.FindItemInBags = originalFind
end

-- ============================================================================
-- Tests: Double-Click without Due Buff
-- ============================================================================

function tests.DoubleClickNoDueBuff()
    -- Double-click without due buff should start fishing
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111, refreshSeconds = 60 } },
        buffAuraByItem = {},
    })

    -- Buff NOT due (used recently)
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 10)

    -- Mock FindItemInBags
    local originalFind = _G.FindItemInBags
    _G.FindItemInBags = function() return 0, 1 end

    -- First click
    mockTime = 1000
    DreamFisher._test.HandleWorldRightClick()

    -- Second click within window
    mockTime = 1000.1
    DreamFisher._test.HandleWorldRightClick()

    -- After double-click without due buff, time should be reset (fishing started)
    local finalTime = DreamFisher._test.GetLastRightClickTime()
    assertEquals(finalTime, 0, "Double-click without due buff should reset time (fishing started)")

    _G.FindItemInBags = originalFind
end

-- ============================================================================
-- Tests: Double-Click Window
-- ============================================================================

function tests.DoubleClickWindowWithinTimeframe()
    -- Clicks within double-click window (0.25s) should form double-click
    local window = DreamFisher._test.GetDoubleClickWindow()
    assertEquals(window, 0.25, "Double-click window should be 0.25s")

    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111, refreshSeconds = 60 } },
        buffAuraByItem = {},
    })

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 100)

    local originalFind = _G.FindItemInBags
    _G.FindItemInBags = function() return 0, 1 end

    -- First click
    mockTime = 1000
    DreamFisher._test.HandleWorldRightClick()

    -- Second click at window edge (0.25s later)
    mockTime = 1000 + window
    DreamFisher._test.HandleWorldRightClick()

    -- Should still be double-click (within window)
    local finalTime = DreamFisher._test.GetLastRightClickTime()
    assertEquals(finalTime, 0, "Clicks at window edge should be double-click")

    _G.FindItemInBags = originalFind
end

function tests.DoubleClickWindowExpired()
    -- Clicks outside double-click window should NOT form double-click
    local window = DreamFisher._test.GetDoubleClickWindow()

    DreamFisher._test.SetDB({
        buffItems = {},
        buffAuraByItem = {},
    })

    -- First click
    mockTime = 1000
    DreamFisher._test.HandleWorldRightClick()

    -- Second click past window
    mockTime = 1000 + window + 0.01
    DreamFisher._test.HandleWorldRightClick()

    -- Should be recorded as new single click, not double-click
    local finalTime = DreamFisher._test.GetLastRightClickTime()
    assertTrue(finalTime > 1000 + window, "Click past window should be new single click")
end

-- ============================================================================
-- Tests: Combat Lockdown
-- ============================================================================

function tests.CombatLockdownPreventsAction()
    -- Right-click in combat should be ignored completely
    mockInCombat = true

    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111, refreshSeconds = 60 } },
        buffAuraByItem = {},
    })

    mockTime = 1000
    DreamFisher._test.HandleWorldRightClick()

    -- Time should not have been recorded
    local lastTime = DreamFisher._test.GetLastRightClickTime()
    assertEquals(lastTime, 0, "Combat should prevent any right-click action")
end

function tests.CombatLockdownDoesNotResetWindow()
    -- Multiple clicks in combat should not affect the window
    mockInCombat = true

    DreamFisher._test.SetDB({
        buffItems = {},
        buffAuraByItem = {},
    })

    -- Try several clicks - none should register
    for i = 1, 5 do
        mockTime = 1000 + i * 0.05
        DreamFisher._test.HandleWorldRightClick()
    end

    -- Time should still be 0
    local lastTime = DreamFisher._test.GetLastRightClickTime()
    assertEquals(lastTime, 0, "Multiple combat clicks should not register")
end

-- ============================================================================
-- Tests: Interaction with Buff State Changes
-- ============================================================================

function tests.DoubleClickAdaptsToDueBuff()
    -- If first click happens with no due buff, but buff becomes due by second click
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111, refreshSeconds = 60 } },
        buffAuraByItem = {},
    })

    local originalFind = _G.FindItemInBags
    _G.FindItemInBags = function() return 0, 1 end

    -- First click: buff not due
    mockTime = 1000
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 10)
    DreamFisher._test.HandleWorldRightClick()

    -- Simulate buff becoming due before second click (time passes)
    mockTime = 1000.1
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 100)

    -- Second click: buff now due
    DreamFisher._test.HandleWorldRightClick()

    -- Should process buff (time reset to 0)
    local finalTime = DreamFisher._test.GetLastRightClickTime()
    assertEquals(finalTime, 0, "Double-click should process buff if due at second click")

    _G.FindItemInBags = originalFind
end

-- ============================================================================
-- Run All Tests
-- ============================================================================

print("\n=== DreamFisher Casting Modes Tests ===\n")

for name, testFn in pairs(tests) do
    RunTest(name, testFn)
end

print("\n=== Summary ===")
print("Passed: " .. testsPassed)
print("Failed: " .. testsFailed)

if testsFailed > 0 then
    os.exit(1)
end
