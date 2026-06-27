-- Unit tests for DreamFisher buff timing and logic.
-- Run with: lua tests/buff_timing_test.lua

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

local function assertGreater(actual, threshold, message)
    if actual <= threshold then
        error((message or "assertGreater failed") .. " | expected > " .. threshold .. " actual=" .. tostring(actual), 2)
    end
end

local mockTime = 1000

-- Mock WoW APIs
_G.GetTime = function()
    return mockTime
end

_G.Clamp = function(value, min, max)
    if value == nil then return min end
    if value < min then return min end
    if value > max then return max end
    return value
end

local function makeFrame()
    return {
        IsShown = function() return false end,
        Show = function() end,
        Hide = function() end,
        SetAttribute = function() end,
        GetAttribute = function() return nil end,
        GetName = function() return "Frame" end,
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function() end,
    }
end

_G.CreateFrame = function()
    return makeFrame()
end

_G.SetOverrideBindingClick = function() end
_G.ClearOverrideBindings = function() end
_G.InCombatLockdown = function() return false end
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.GetCVar = function() return "1.0" end
_G.ContainerNumSlots = function() return 16 end
_G.ContainerItemID = function() return nil end
_G.GetItemInfo = function(id) return "Item " .. id end
_G.NUM_BAG_SLOTS = 4
_G.SlashCmdList = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.UIParent = {}

-- Load the addon
dofile("core/init.lua")
dofile("core/utils.lua")
dofile("fishing/helpers.lua")
dofile("buff/tracking.lua")
dofile("buff/timing.lua")
dofile("buff/management.lua")
dofile("DreamFisher.lua")

local tests = {}
local testsPassed = 0
local testsFailed = 0

function RunTest(name, testFn)
    mockTime = 1000

    local success, err = pcall(function()
        DreamFisher._test.SetDB({
            buffItems = {},
            buffAuraByItem = {},
            refreshSeconds = 180,
        })
        DreamFisher.state.buffItemLastUseAt = {}
        DreamFisher.state.buffItemLastReminderAt = {}
        DreamFisher.state.buffItemLastMissingWarningAt = {}
        DreamFisher.state.pendingBuffObservation = nil
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
-- Tests: Buff Refresh Lead Calculation
-- ============================================================================

function tests.BuffRefreshLeadMinimumLead()
    -- For 30s refresh: 10% = 3s, min 3s, max cast = 22s → expect 22s
    local lead30 = DreamFisher._test.GetBuffRefreshLead(30)
    assertEquals(lead30, 22, "30s refresh should give 22s lead (max of 3s and cast)")
end

function tests.BuffRefreshLeadMidRange()
    -- For 180s refresh: 10% = 18s, capped at 15s, cast = 22s → expect 22s
    local lead180 = DreamFisher._test.GetBuffRefreshLead(180)
    assertEquals(lead180, 22, "180s refresh should give 22s lead")
end

function tests.BuffRefreshLeadLargeRefresh()
    -- For 3600s refresh: 10% = 360s, capped at 15s, cast = 22s → expect 22s
    local lead3600 = DreamFisher._test.GetBuffRefreshLead(3600)
    assertEquals(lead3600, 22, "3600s refresh should give 22s lead")
end

function tests.BuffRefreshLeadAlwaysExceedsCastTime()
    -- Lead must always be > 20s fishing cast time
    for refresh = 30, 3600, 100 do
        local lead = DreamFisher._test.GetBuffRefreshLead(refresh)
        assertGreater(lead, 20, "Lead for " .. refresh .. "s should be > 20s")
    end
end

-- ============================================================================
-- Tests: Buff Due Checking
-- ============================================================================

function tests.BuffDueWithTrackedAuraActive()
    -- When aura is tracked and active with time remaining < lead, buff is due
    local originalCUnitAuras = _G.C_UnitAuras
    local originalAuraUtil = _G.AuraUtil
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111, refreshSeconds = 180 } },
        buffAuraByItem = { ["111"] = { spellID = 999, duration = 30 } },
    })

    -- Simulate GetAuraBySpellID would return this aura with 20s remaining
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == 999 then
                return {
                    spellId = 999,
                    duration = 30,
                    expirationTime = mockTime + 20,
                }
            end
            return nil
        end,
        GetAuraDataByIndex = function(unit, index, filter)
            if index == 1 then
                return {
                    spellId = 999,
                    duration = 30,
                    expirationTime = mockTime + 20,  -- 20s remaining, lead is 22s
                }
            end
            return nil
        end,
    }

    local isDue, remaining, reason = DreamFisher._test.IsBuffItemDue(111, 180, false)
    assertTrue(isDue, "Buff with 20s remaining should be due (lead=22s)")
    assertEquals(reason, "tracked_remaining", "Should cite tracked_remaining")

    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

function tests.BuffDueWithTrackedAuraMissing()
    -- When aura is tracked but not found, buff is due immediately
    local originalCUnitAuras = _G.C_UnitAuras
    local originalAuraUtil = _G.AuraUtil
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111, refreshSeconds = 180 } },
        buffAuraByItem = { ["111"] = { spellID = 999, duration = 30 } },
    })

    -- No auras present
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }
    _G.AuraUtil = nil

    local isDue, remaining, reason = DreamFisher._test.IsBuffItemDue(111, 180, false)
    assertTrue(isDue, "Missing tracked aura should be due")
    assertTrue(remaining == nil or remaining == 0, "Remaining should be nil or 0 for missing tracked aura")
    assertEquals(reason, "tracked_missing_aura", "Should cite missing tracked aura path")

    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

function tests.BuffDueWithTrackedAuraMissingRespectsRecentUse()
    -- If tracked aura cannot be detected but item was just used, do not reapply immediately.
    local originalCUnitAuras = _G.C_UnitAuras
    local originalAuraUtil = _G.AuraUtil
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111, refreshSeconds = 180 } },
        buffAuraByItem = { ["111"] = { spellID = 999, duration = 30 } },
    })

    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }
    _G.AuraUtil = nil

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 10)

    local isDue, remaining, reason = DreamFisher._test.IsBuffItemDue(111, 180, true)
    assertEquals(isDue, false, "Missing tracked aura with very recent use should not be due")
    assertEquals(reason, "tracked_missing_recent_use", "Should cite recent-use tracked fallback")

    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

function tests.BuffDueWithTrackedAuraMissingAfterDuration()
    -- If tracked aura is missing and expected duration window has elapsed, item is due.
    local originalCUnitAuras = _G.C_UnitAuras
    local originalAuraUtil = _G.AuraUtil
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111, refreshSeconds = 180 } },
        buffAuraByItem = { ["111"] = { spellID = 999, duration = 30 } },
    })

    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }
    _G.AuraUtil = nil

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 181)

    local isDue, remaining, reason = DreamFisher._test.IsBuffItemDue(111, 180, true)
    assertEquals(isDue, true, "Missing tracked aura after expected duration should be due")
    assertEquals(reason, "tracked_missing_aura", "Should cite missing tracked aura once fallback timer elapses")

    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

function tests.BuffDueUntrackedWithTimerNotExpired()
    -- Untracked buff: use timer; not due if within refresh window
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 222, refreshSeconds = 60 } },
        buffAuraByItem = {},  -- Untracked
    })

    -- Used 30s ago (not yet 60s)
    DreamFisher._test.SetBuffLastUseTime(222, mockTime - 30)

    local isDue, remaining, reason = DreamFisher._test.IsBuffItemDue(222, 60, false)
    assertEquals(isDue, false, "Buff within timer should not be due")
    assertTrue(reason:find("timer_elapsed"), "Should cite timer_elapsed reason")
end

function tests.BuffDueUntrackedWithTimerExpired()
    -- Untracked buff: use timer; due if refresh window expired
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 222, refreshSeconds = 60 } },
        buffAuraByItem = {},  -- Untracked
    })

    -- Used 70s ago (past 60s window)
    DreamFisher._test.SetBuffLastUseTime(222, mockTime - 70)

    local isDue, remaining, reason = DreamFisher._test.IsBuffItemDue(222, 60, false)
    assertEquals(isDue, true, "Buff past timer should be due")
end

function tests.BuffDueUntrackedForCastIsAlwaysDue()
    -- Untracked buff for cast keeps its timer-based behavior.
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 333, refreshSeconds = 60 } },
        buffAuraByItem = {},  -- Untracked
    })

    -- Even if recently used, it should not be treated as due yet.
    DreamFisher._test.SetBuffLastUseTime(333, mockTime - 5)

    local isDue, remaining, reason = DreamFisher._test.IsBuffItemDue(333, 60, true)
    assertEquals(isDue, false, "Untracked buff for cast should still respect timer when recently used")
    assertTrue(reason:find("timer_elapsed") ~= nil or reason == "untracked_no_history_due_cast", "Should cite the timer path or cast first-use reason")
end

function tests.BuffDueUntrackedNoHistoryForCast()
    -- Untracked buff with no history should be due on cast so the addon can learn it.
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 444, expectedDuration = 60 } },
        buffAuraByItem = {},
    })

    local isDue, remaining, reason = DreamFisher._test.IsBuffItemDue(444, 60, true)
    assertEquals(isDue, true, "Untracked buff with no history should be due for cast")
    assertEquals(reason, "untracked_no_history_due_cast", "Should cite first-use cast reason")
end

-- ============================================================================
-- Tests: Get Next Due Buff Item
-- ============================================================================

function tests.GetNextDueBuffReturnsFirst()
    -- When multiple buffs are due, return first one
    DreamFisher._test.SetDB({
        buffItems = {
            { itemID = 111, refreshSeconds = 60 },
            { itemID = 222, refreshSeconds = 60 },
        },
        buffAuraByItem = {},
    })

    -- Both used long ago (both due)
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 100)
    DreamFisher._test.SetBuffLastUseTime(222, mockTime - 100)

    -- Mock FindItemInBags to return both items
    local originalFindItemInBags = _G.FindItemInBags
    _G.FindItemInBags = function(itemID)
        if itemID == 111 then return 0, 1 end
        if itemID == 222 then return 0, 2 end
        return nil, nil
    end

    local nextItem = DreamFisher._test.GetNextDueBuffItem(false)
    assertEquals(nextItem, 111, "Should return first due buff")

    _G.FindItemInBags = originalFindItemInBags
end

function tests.GetNextDueBuffSkipsUnavailable()
    -- When first buff is excluded, the helper should still return a due item.
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

    local nextItem = DreamFisher._test.GetNextDueBuffItem(false, { [111] = true })
    assertTrue(nextItem ~= nil, "Should return some due buff item")
end

function tests.GetNextDueBuffReturnsNilWhenNoneDue()
    -- When no buffs are due, return nil
    DreamFisher._test.SetDB({
        buffItems = {
            { itemID = 111, refreshSeconds = 60 },
        },
        buffAuraByItem = {},
    })

    -- Used recently (not due)
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 30)

    local originalFindItemInBags = _G.FindItemInBags
    _G.FindItemInBags = function() return 0, 1 end

    local nextItem = DreamFisher._test.GetNextDueBuffItem(false)
    assertEquals(nextItem, nil, "Should return nil when no buffs due")

    _G.FindItemInBags = originalFindItemInBags
end

-- ============================================================================
-- Run All Tests
-- ============================================================================

print("\n=== DreamFisher Buff Timing Tests ===\n")

for name, testFn in pairs(tests) do
    RunTest(name, testFn)
end

print("\n=== Summary ===")
print("Passed: " .. testsPassed)
print("Failed: " .. testsFailed)

if testsFailed > 0 then
    os.exit(1)
end
