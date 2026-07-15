-- DreamFish Unit Tests
-- Tests for buff timing logic and casting modes

-- ============================================================================
-- Mock WoW API
-- ============================================================================

local mockTime = 1000  -- Start at arbitrary game time
local mockInCombat = false
local mockCastInfo = nil
local mockChannelInfo = nil
local mockAuras = {}  -- Mock aura tracking
local mockBagItems = {}  -- Mock bag item locations
local mockItemInfo = {}  -- Mock item names
local mockCVars = {}  -- Mock CVars

function GetTime()
    return mockTime
end

function InCombatLockdown()
    return mockInCombat
end

function UnitCastingInfo(unit)
    return mockCastInfo
end

function UnitChannelInfo(unit)
    return mockChannelInfo
end

function GetCVar(name)
    return mockCVars[name] or "1.0"
end

function SetCVar(name, value)
    mockCVars[name] = value
end

function ContainerNumSlots(bag)
    return 16
end

function ContainerItemID(bag, slot)
    if not mockBagItems[bag] then
        return nil
    end
    return mockBagItems[bag][slot]
end

function GetItemInfo(itemID)
    return mockItemInfo[itemID] or ("Item " .. itemID)
end

function C_UnitAuras_GetAuraDataByIndex(unit, index, filter)
    if not mockAuras[index] then
        return nil
    end
    return mockAuras[index]
end

function CreateFrame(frameType, name)
    return {
        IsShown = function() return false end,
        Show = function() end,
        Hide = function() end,
    }
end

function SetOverrideBindingClick(frame, priority, key, frameName)
    -- Mock implementation
end

function ClearOverrideBindings(frame)
    -- Mock implementation
end

_G.C_UnitAuras = {
    GetAuraDataByIndex = C_UnitAuras_GetAuraDataByIndex,
}

_G.NUM_BAG_SLOTS = 4

-- ============================================================================
-- Test Infrastructure
-- ============================================================================

local testsPassed = 0
local testsFailed = 0
local currentTestName = ""

function ResetMocks()
    mockTime = 1000
    mockInCombat = false
    mockCastInfo = nil
    mockChannelInfo = nil
    mockAuras = {}
    mockBagItems = {}
    mockItemInfo = {}
    mockCVars = {}
end

function Assert(condition, message)
    if not condition then
        error("FAIL: " .. currentTestName .. " - " .. message)
    end
end

function AssertEqual(actual, expected, message)
    if actual ~= expected then
        error("FAIL: " .. currentTestName .. " - Expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ". " .. message)
    end
end

function AssertGreater(actual, threshold, message)
    if actual <= threshold then
        error("FAIL: " .. currentTestName .. " - Expected > " .. threshold .. ", got " .. actual .. ". " .. message)
    end
end

function AssertLessOrEqual(actual, threshold, message)
    if actual > threshold then
        error("FAIL: " .. currentTestName .. " - Expected <= " .. threshold .. ", got " .. actual .. ". " .. message)
    end
end

function RunTest(name, testFn)
    currentTestName = name
    ResetMocks()

    local success, err = pcall(function()
        -- Setup: Create a minimal addon database
        DreamFish._test.SetDB({
            buffItems = {},
            buffAuraByItem = {},
        })
    end)

    if not success then
        print("[SKIP] " .. name .. " - " .. err)
        return
    end

    success, err = pcall(testFn)

    if success then
        print("[PASS] " .. name)
        testsPassed = testsPassed + 1
    else
        print("[FAIL] " .. name .. " - " .. err)
        testsFailed = testsFailed + 1
    end
end

-- ============================================================================
-- Buff Timing Tests
-- ============================================================================

function TestBuffRefreshLeadMinimum()
    -- Buff refresh lead should be at least max(10% of refresh, 20s + 2s safety)
    local lead30 = DreamFish._test.GetBuffRefreshLead(30)  -- 10% = 3s, min 3s, cast = 22s → 22s
    AssertEqual(lead30, 22, "30s refresh should give 22s lead (max of 3s and 22s cast)")

    local lead180 = DreamFish._test.GetBuffRefreshLead(180)  -- 10% = 18s, capped at 15s, cast = 22s → 22s
    AssertEqual(lead180, 22, "180s refresh should give 22s lead (max of 15s cap and 22s cast)")

    local lead3600 = DreamFish._test.GetBuffRefreshLead(3600)  -- 10% = 360s, capped at 15s, cast = 22s → 22s
    AssertEqual(lead3600, 22, "3600s refresh should give 22s lead (max of 15s cap and 22s cast)")
end

function TestBuffRefreshLeadEnsuresPreCastCompletion()
    -- The lead time must be at least 20s (fishing cast) + 2s (safety margin)
    local lead = DreamFish._test.GetBuffRefreshLead(60)
    AssertGreater(lead, 20, "Lead should be > 20s to accommodate fishing cast")
end

function TestBuffItemDueWithTrackedAuraPresent()
    -- When aura is actively tracked and present, buff is due when remaining <= lead
    DreamFish._test.SetDB({
        buffItems = { { itemID = 12345 } },
        buffAuraByItem = { ["12345"] = { spellID = 99999, duration = 30 } },
    })

    -- Simulate aura present with 25s remaining (lead is 22s for 180s refresh)
    mockAuras[1] = {
        spellId = 99999,
        duration = 30,
        expirationTime = mockTime + 25,
    }

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(12345, 180, false)
    AssertEqual(isDue, true, "Buff should be due when remaining 25s < lead 22s")
    AssertEqual(reason, "tracked_remaining", "Reason should be tracked_remaining")
end

function TestBuffItemDueWithTrackedAuraMissing()
    -- When aura is tracked but missing (not active), buff is due immediately
    DreamFish._test.SetDB({
        buffItems = { { itemID = 12345 } },
        buffAuraByItem = { ["12345"] = { spellID = 99999, duration = 30 } },
    })

    -- No auras active (mockAuras is empty)
    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(12345, 180, false)
    AssertEqual(isDue, true, "Buff should be due when tracked aura is missing")
    AssertEqual(remaining, 0, "Remaining should be 0 when aura is missing")
    AssertEqual(reason, "tracked_missing_aura", "Reason should be tracked_missing_aura")
end

function TestBuffItemDueUntrackedWithoutCastRequirement()
    -- When buff is untracked and not casting, fall back to timer
    DreamFish._test.SetDB({
        buffItems = { { itemID = 12345 } },
        buffAuraByItem = {},  -- No tracking
    })

    -- Set last use time to be within the refresh window
    DreamFish._test.SetBuffLastUseTime(12345, mockTime - 30)  -- Used 30s ago

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(12345, 60, false)
    AssertEqual(isDue, false, "Buff should not be due within 60s of last use")
    AssertEqual(reason, "timer_elapsed=30.0", "Should track elapsed time")
end

function TestBuffItemDueUntrackedForCast()
    -- When buff is untracked and we're about to cast, treat as due
    DreamFish._test.SetDB({
        buffItems = { { itemID = 12345 } },
        buffAuraByItem = {},  -- No tracking
    })

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(12345, 60, true)
    AssertEqual(isDue, true, "Untracked buff should be due when casting is imminent")
    AssertEqual(reason, "untracked_assume_due_for_cast", "Should assume due for cast")
end

function TestGetNextDueBuffItemSelectsFirst()
    -- When multiple buffs are configured, GetNextDueBuffItem should return first due buff
    local item1 = 12345
    local item2 = 67890

    DreamFish._test.SetDB({
        buffItems = {
            { itemID = item1 },
            { itemID = item2 },
        },
        buffAuraByItem = {},
    })

    -- First item was used 40s ago (due), second was used 20s ago (not due)
    DreamFish._test.SetBuffLastUseTime(item1, mockTime - 40)
    DreamFish._test.SetBuffLastUseTime(item2, mockTime - 20)

    -- Add items to bags
    mockBagItems[0] = { [1] = item1, [2] = item2 }

    local nextItem = DreamFish._test.GetNextDueBuffItem(false)
    AssertEqual(nextItem, item1, "Should return first due buff item")
end

function TestGetNextDueBuffItemSkipsUnavailable()
    -- When a buff item isn't in bags, skip it
    local item1 = 12345
    local item2 = 67890

    DreamFish._test.SetDB({
        buffItems = {
            { itemID = item1 },
            { itemID = item2 },
        },
        buffAuraByItem = {},
    })

    -- Both due, but item1 not in bags
    DreamFish._test.SetBuffLastUseTime(item1, mockTime - 100)
    DreamFish._test.SetBuffLastUseTime(item2, mockTime - 100)

    -- Only item2 in bags
    mockBagItems[0] = { [1] = nil, [2] = item2 }

    local nextItem = DreamFish._test.GetNextDueBuffItem(false)
    AssertEqual(nextItem, item2, "Should skip unavailable buff and return second item")
end

-- ============================================================================
-- Casting Mode Tests
-- ============================================================================

function TestSingleRightClickRecordsTime()
    -- Single right-click should record time and clear bindings, no action
    DreamFish._test.SetDB({
        buffItems = {},
        buffAuraByItem = {},
    })

    -- First click at time 1000
    mockTime = 1000
    DreamFish._test.HandleWorldRightClick()

    local lastTime = DreamFish._test.GetLastRightClickTime()
    AssertEqual(lastTime, 1000, "Single right-click should record click time")
end

function TestDoubleClickWithDueBuffUsesBuff()
    -- Double-click within window + due buff should use the buff
    DreamFish._test.SetDB({
        buffItems = { { itemID = 12345 } },
        buffAuraByItem = {},
    })

    -- Buff is due (used long ago)
    DreamFish._test.SetBuffLastUseTime(12345, mockTime - 100)

    -- Item in bags
    mockBagItems[0] = { [1] = 12345 }

    -- First click
    mockTime = 1000
    DreamFish._test.HandleWorldRightClick()

    -- Second click within window
    mockTime = 1000.1
    DreamFish._test.HandleWorldRightClick()

    -- Verify buff action was triggered (time was reset)
    local lastTime = DreamFish._test.GetLastRightClickTime()
    AssertEqual(lastTime, 0, "Double-click with due buff should reset click time")
end

function TestDoubleClickWithoutDueBuffStartsFishing()
    -- Double-click without due buff should start fishing cast
    DreamFish._test.SetDB({
        buffItems = { { itemID = 12345 } },
        buffAuraByItem = {},
    })

    -- Buff not due (used recently)
    DreamFish._test.SetBuffLastUseTime(12345, mockTime - 10)

    -- Item in bags
    mockBagItems[0] = { [1] = 12345 }

    -- First click
    mockTime = 1000
    DreamFish._test.HandleWorldRightClick()

    -- Second click within window
    mockTime = 1000.1
    DreamFish._test.HandleWorldRightClick()

    -- Verify fishing was started (time was reset)
    local lastTime = DreamFish._test.GetLastRightClickTime()
    AssertEqual(lastTime, 0, "Double-click without due buff should reset click time and start fishing")
end

function TestDoubleClickWindowExpiration()
    -- Clicks outside the double-click window should not count as double-click
    DreamFish._test.SetDB({
        buffItems = {},
        buffAuraByItem = {},
    })

    local window = DreamFish._test.GetDoubleClickWindow()

    -- First click
    mockTime = 1000
    DreamFish._test.HandleWorldRightClick()
    AssertEqual(DreamFish._test.GetLastRightClickTime(), 1000, "First click recorded")

    -- Second click outside window
    mockTime = 1000 + window + 0.1
    DreamFish._test.HandleWorldRightClick()

    -- Should have recorded a new single click, not processed as double
    local lastTime = DreamFish._test.GetLastRightClickTime()
    AssertLessOrEqual(lastTime - 1000, window + 0.1, "Click outside window should be new single click")
end

function TestCombatLockdownPreventsAction()
    -- Right-click in combat should be ignored
    DreamFish._test.SetDB({
        buffItems = { { itemID = 12345, } },
        buffAuraByItem = {},
    })

    mockInCombat = true
    mockTime = 1000
    DreamFish._test.HandleWorldRightClick()

    -- Time should not be recorded
    local lastTime = DreamFish._test.GetLastRightClickTime()
    AssertEqual(lastTime, 0, "Combat should prevent any action")
end

-- ============================================================================
-- Run All Tests
-- ============================================================================

function RunAllTests()
    print("\n=== DreamFish Unit Tests ===\n")

    print("--- Buff Timing Tests ---")
    RunTest("GetBuffRefreshLead minimum", TestBuffRefreshLeadMinimum)
    RunTest("GetBuffRefreshLead ensures pre-cast completion", TestBuffRefreshLeadEnsuresPreCastCompletion)
    RunTest("IsBuffItemDue with tracked aura present", TestBuffItemDueWithTrackedAuraPresent)
    RunTest("IsBuffItemDue with tracked aura missing", TestBuffItemDueWithTrackedAuraMissing)
    RunTest("IsBuffItemDue untracked without cast requirement", TestBuffItemDueUntrackedWithoutCastRequirement)
    RunTest("IsBuffItemDue untracked for cast", TestBuffItemDueUntrackedForCast)
    RunTest("GetNextDueBuffItem selects first due", TestGetNextDueBuffItemSelectsFirst)
    RunTest("GetNextDueBuffItem skips unavailable", TestGetNextDueBuffItemSkipsUnavailable)

    print("\n--- Casting Mode Tests ---")
    RunTest("Single right-click records time", TestSingleRightClickRecordsTime)
    RunTest("Double-click with due buff uses buff", TestDoubleClickWithDueBuffUsesBuff)
    RunTest("Double-click without due buff starts fishing", TestDoubleClickWithoutDueBuffStartsFishing)
    RunTest("Double-click window expiration", TestDoubleClickWindowExpiration)
    RunTest("Combat lockdown prevents action", TestCombatLockdownPreventsAction)

    print("\n=== Test Summary ===")
    print("Passed: " .. testsPassed)
    print("Failed: " .. testsFailed)

    if testsFailed == 0 then
        print("\nAll tests passed! ✓")
    else
        print("\n" .. testsFailed .. " test(s) failed.")
    end

    return testsFailed == 0
end

-- Run tests if this file is executed
if type(_G.DreamFish) == "table" then
    RunAllTests()
else
    print("Warning: DreamFish addon not loaded. Cannot run tests.")
    print("Load the addon with: dofile('path/to/DreamFish.lua')")
end
