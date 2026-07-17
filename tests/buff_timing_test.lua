-- Unit tests for DreamFish buff timing and logic.
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

local makeFrame = dofile("tests/mocks/frame_fixture.lua").makeFrame

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
dofile("core/module_api.lua")
dofile("core/api_resolver.lua")
dofile("fishing/helpers.lua")
dofile("buff/tracking.lua")
dofile("buff/timing.lua")
dofile("buff/management.lua")
dofile("DreamFish.lua")

local tests = {}
local testsPassed = 0
local testsFailed = 0

function RunTest(name, testFn)
    mockTime = 1000

    local success, err = pcall(function()
        DreamFish._test.SetDB({
            buffItems = {},
            buffAuraByItem = {},
        })
        DreamFish.state.buffItemLastUseAt = {}
        DreamFish.state.buffItemLastReminderAt = {}
        DreamFish.state.buffItemLastMissingWarningAt = {}
        DreamFish.state.buffItemTransientUntil = {}
        DreamFish.state.pendingBuffObservation = nil
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
    local lead30 = DreamFish._test.GetBuffRefreshLead(30)
    assertEquals(lead30, 22, "30s refresh should give 22s lead (max of 3s and cast)")
end

function tests.BuffRefreshLeadMidRange()
    -- For 180s refresh: 10% = 18s, capped at 15s, cast = 22s → expect 22s
    local lead180 = DreamFish._test.GetBuffRefreshLead(180)
    assertEquals(lead180, 22, "180s refresh should give 22s lead")
end

function tests.BuffRefreshLeadLargeRefresh()
    -- For 3600s refresh: 10% = 360s, capped at 15s, cast = 22s → expect 22s
    local lead3600 = DreamFish._test.GetBuffRefreshLead(3600)
    assertEquals(lead3600, 22, "3600s refresh should give 22s lead")
end

function tests.BuffRefreshLeadAlwaysExceedsCastTime()
    -- Lead must always be > 20s fishing cast time
    for refresh = 30, 3600, 100 do
        local lead = DreamFish._test.GetBuffRefreshLead(refresh)
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
    DreamFish._test.SetDB({
        buffItems = { { itemID = 111 } },
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

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(111, 180, false)
    assertTrue(isDue, "Buff with 20s remaining should be due (lead=22s)")
    assertEquals(reason, "tracked_remaining", "Should cite tracked_remaining")

    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

function tests.BuffDueWithTrackedAuraMissing()
    -- When aura is tracked but not found, buff is due immediately
    local originalCUnitAuras = _G.C_UnitAuras
    local originalAuraUtil = _G.AuraUtil
    DreamFish._test.SetDB({
        buffItems = { { itemID = 111 } },
        buffAuraByItem = { ["111"] = { spellID = 999, duration = 30 } },
    })

    -- No auras present
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }
    _G.AuraUtil = nil

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(111, 180, false)
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
    DreamFish._test.SetDB({
        buffItems = { { itemID = 111 } },
        buffAuraByItem = { ["111"] = { spellID = 999, duration = 30 } },
    })

    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }
    _G.AuraUtil = nil

    DreamFish._test.SetBuffLastUseTime(111, mockTime - 10)

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(111, 180, true)
    assertEquals(isDue, false, "Missing tracked aura with very recent use should not be due")
    assertEquals(reason, "tracked_missing_recent_use", "Should cite recent-use tracked fallback")

    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

function tests.BuffDueWithTrackedAuraMissingAfterDuration()
    -- If tracked aura is missing and expected duration window has elapsed, item is due.
    local originalCUnitAuras = _G.C_UnitAuras
    local originalAuraUtil = _G.AuraUtil
    DreamFish._test.SetDB({
        buffItems = { { itemID = 111 } },
        buffAuraByItem = { ["111"] = { spellID = 999, duration = 30 } },
    })

    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }
    _G.AuraUtil = nil

    DreamFish._test.SetBuffLastUseTime(111, mockTime - 181)

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(111, 180, true)
    assertEquals(isDue, true, "Missing tracked aura after expected duration should be due")
    assertEquals(reason, "tracked_missing_aura", "Should cite missing tracked aura once fallback timer elapses")

    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

function tests.KnownAuraFallbackPreventsStaleTrackedRecast()
    -- If tracked mapping is stale/transient but known long-duration aura is active,
    -- the item should not be considered due.
    local originalCUnitAuras = _G.C_UnitAuras
    local originalAuraUtil = _G.AuraUtil

    DreamFish._test.SetDB({
        buffItems = { { itemID = 242299, expectedDuration = 3600 } },
        buffAuraByItem = { ["242299"] = { spellID = 1277461, duration = 20 } },
    })

    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == 1269152 then
                return {
                    spellId = 1269152,
                    duration = 3600,
                    expirationTime = mockTime + 3500,
                }
            end
            return nil
        end,
        GetAuraDataByIndex = function() return nil end,
    }
    _G.AuraUtil = nil

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(242299, 3600, true)
    assertEquals(isDue, false, "Known active tea aura should prevent stale tracked recast")
    assertEquals(reason, "tracked_remaining", "Known aura fallback should use tracked remaining path")
    assertTrue(remaining and remaining > 0, "Known aura fallback should report remaining time")

    local tracked = DreamFish.db.buffAuraByItem["242299"]
    assertTrue(type(tracked) == "table", "Self-heal should retain tracked mapping table")
    assertEquals(tracked.spellID, 1269152, "Self-heal should rewrite tracked spellID to known lasting aura")
    assertEquals(tracked.duration, 3600, "Self-heal should restore known expected duration")

    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

function tests.BuffDueUntrackedWithTimerNotExpired()
    -- Untracked buff without known duration: do not reapply outside cast probing.
    DreamFish._test.SetDB({
        buffItems = { { itemID = 222 } },
        buffAuraByItem = {},  -- Untracked
    })

    -- Used 30s ago (not yet 60s)
    DreamFish._test.SetBuffLastUseTime(222, mockTime - 30)

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(222, 60, false)
    assertEquals(isDue, false, "Buff within timer should not be due")
    assertEquals(reason, "unknown_duration_no_reapply", "Should cite unknown-duration suppression reason")
end

function tests.BuffDueUntrackedWithTimerExpired()
    -- Untracked buff without known duration stays suppressed outside cast probing.
    DreamFish._test.SetDB({
        buffItems = { { itemID = 222 } },
        buffAuraByItem = {},  -- Untracked
    })

    -- Used 70s ago (past 60s window)
    DreamFish._test.SetBuffLastUseTime(222, mockTime - 70)

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(222, 60, false)
    assertEquals(isDue, false, "Unknown-duration untracked buff should not be auto-due")
    assertEquals(reason, "unknown_duration_no_reapply", "Should remain on unknown-duration no-reapply path")
end

function tests.BuffDueUntrackedForCastIsAlwaysDue()
    -- Very recent use should block immediate reuse even on cast.
    DreamFish._test.SetDB({
        buffItems = { { itemID = 333 } },
        buffAuraByItem = {},  -- Untracked
    })

    -- Even if recently used, cast path allows a probe until explicitly suppressed.
    DreamFish._test.SetBuffLastUseTime(333, mockTime - 5)

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(333, 60, true)
    assertEquals(isDue, false, "Very recently used buff should not be immediately reusable on cast")
    assertEquals(reason, "too_soon_to_use", "Recent-use guard should take precedence over probe-due logic")
end

function tests.BuffDueUntrackedNoHistoryForCast()
    -- Untracked buff with no history should be due on cast so the addon can learn it.
    DreamFish._test.SetDB({
        buffItems = { { itemID = 444, expectedDuration = 60 } },
        buffAuraByItem = {},
    })

    local isDue, remaining, reason = DreamFish._test.IsBuffItemDue(444, 60, true)
    assertEquals(isDue, true, "Untracked buff with no history should be due for cast")
    assertEquals(reason, "untracked_no_history_due_cast", "Should cite first-use cast reason")
end

function tests.BobberToyItemsResolveBobberCategory()
    local categoryKnown = DreamFish.buff.GetBuffItemCategory(142529)
    assertEquals(categoryKnown, "bobber", "Known bobber toy should resolve to bobber category")

    local categoryFromList = DreamFish.buff.GetBuffItemCategory(142531)
    assertEquals(categoryFromList, "bobber", "Bobber toy from bobber list should resolve to bobber category")
end

function tests.TrackingDoesNotDowngradeKnownLongDurationToTransientAura()
    local originalCUnitAuras = _G.C_UnitAuras
    local originalAuraUtil = _G.AuraUtil

    DreamFish._test.SetDB({
        buffItems = { { itemID = 242299, expectedDuration = 3600 } },
        buffAuraByItem = {
            ["242299"] = { spellID = 1269152, duration = 3600 },
        },
    })

    DreamFish.state.pendingBuffObservation = {
        itemID = 242299,
        before = {},
        expiresAt = mockTime + 10,
    }

    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function(unit, index, filter)
            if index == 1 then
                return {
                    spellId = 1277461,
                    duration = 20,
                    expirationTime = mockTime + 20,
                }
            end
            return nil
        end,
    }
    _G.AuraUtil = nil

    DreamFish.buff.UpdatePendingBuffObservation()

    local tracked = DreamFish.db.buffAuraByItem["242299"]
    assertTrue(type(tracked) == "table", "Tracked mapping should exist for tea")
    assertEquals(tracked.spellID, 1269152, "Transient aura should not replace long tracked spellID")
    assertEquals(tracked.duration, 3600, "Transient aura should not replace long tracked duration")
    assertEquals(DreamFish.state.pendingBuffObservation, nil, "Pending observation should be cleared")

    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

function tests.TrackingSkipsTransientAuraForFoodDrinkByExpectedDuration()
    local originalCUnitAuras = _G.C_UnitAuras
    local originalAuraUtil = _G.AuraUtil
    local originalGetBuffItemCategory = DreamFish.buff.GetBuffItemCategory

    DreamFish._test.SetDB({
        buffItems = { { itemID = 555001, expectedDuration = 1800 } },
        buffAuraByItem = {},
    })

    DreamFish.buff.GetBuffItemCategory = function(itemID)
        if itemID == 555001 then
            return "food_drink"
        end
        if originalGetBuffItemCategory then
            return originalGetBuffItemCategory(itemID)
        end
        return "other_consumable"
    end

    DreamFish.state.pendingBuffObservation = {
        itemID = 555001,
        before = {},
        expiresAt = mockTime + 10,
    }

    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function(unit, index, filter)
            if index == 1 then
                return {
                    spellId = 1277461,
                    duration = 20,
                    expirationTime = mockTime + 20,
                }
            end
            return nil
        end,
    }
    _G.AuraUtil = nil

    DreamFish.buff.UpdatePendingBuffObservation()

    local tracked = DreamFish.db.buffAuraByItem["555001"]
    assertEquals(tracked, nil, "Food/drink mapping should not learn from transient short aura")
    assertEquals(DreamFish.state.pendingBuffObservation, nil, "Pending observation should be cleared")

    DreamFish.buff.GetBuffItemCategory = originalGetBuffItemCategory
    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

function tests.FoodDrinkTransientWindowSuppressesDueAction()
    local originalCUnitAuras = _G.C_UnitAuras
    local originalAuraUtil = _G.AuraUtil

    DreamFish._test.SetDB({
        buffItems = { { itemID = 242299, expectedDuration = 3600 } },
        buffAuraByItem = { ["242299"] = { spellID = 1269152, duration = 3600 } },
    })

    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }
    _G.AuraUtil = nil

    DreamFish.state.buffItemTransientUntil[242299] = mockTime + 12

    local isDueNow, remainingNow, reasonNow = DreamFish._test.IsBuffItemDue(242299, 3600, true)
    assertEquals(isDueNow, false, "Food/drink should not be due while transient window is active")
    assertEquals(reasonNow, "food_drink_transient_active", "Should cite food_drink transient suppression")
    assertTrue(remainingNow and remainingNow > 0, "Transient suppression should report remaining time")

    mockTime = mockTime + 13

    local isDueAfter, _, reasonAfter = DreamFish._test.IsBuffItemDue(242299, 3600, true)
    assertEquals(isDueAfter, true, "Food/drink can become due again after transient window expires")
    assertEquals(reasonAfter, "tracked_missing_aura", "After transient window, fallback should be tracked_missing_aura")

    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

function tests.PendingObservationPrefersKnownSpellOverLongerBobberAura()
    local originalCUnitAuras = _G.C_UnitAuras
    local originalAuraUtil = _G.AuraUtil

    DreamFish._test.SetDB({
        buffItems = { { itemID = 238381 } },
        buffAuraByItem = {},
    })

    DreamFish.state.pendingBuffObservation = {
        itemID = 238381,
        before = {},
        expiresAt = mockTime + 10,
    }

    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function(unit, index, filter)
            if index == 1 then
                return {
                    spellId = 231341,
                    duration = 3600,
                    expirationTime = mockTime + 3600,
                }
            end
            if index == 2 then
                return {
                    spellId = 1237942,
                    duration = 30,
                    expirationTime = mockTime + 30,
                }
            end
            return nil
        end,
    }
    _G.AuraUtil = nil

    DreamFish.buff.UpdatePendingBuffObservation()

    local tracked = DreamFish.db.buffAuraByItem["238381"]
    assertTrue(type(tracked) == "table", "Pending observation should learn a mapping for Hollow Grouper")
    assertEquals(tracked.spellID, 1237942, "Pending observation should prefer the item's known spell over bobber aura")
    assertEquals(tracked.duration, 30, "Pending observation should preserve the short consumable duration")
    assertEquals(DreamFish.state.pendingBuffObservation, nil, "Pending observation should clear after matching known spell")

    _G.C_UnitAuras = originalCUnitAuras
    _G.AuraUtil = originalAuraUtil
end

-- ============================================================================
-- Tests: Get Next Due Buff Item
-- ============================================================================

function tests.GetNextDueBuffReturnsFirst()
    -- When multiple buffs are due, return first one
    DreamFish._test.SetDB({
        buffItems = {
            { itemID = 111 },
            { itemID = 222 },
        },
        buffAuraByItem = {},
    })

    -- Both used long ago (both due)
    DreamFish._test.SetBuffLastUseTime(111, mockTime - 100)
    DreamFish._test.SetBuffLastUseTime(222, mockTime - 100)

    -- Mock FindItemInBags to return both items
    local originalFindItemInBags = _G.FindItemInBags
    _G.FindItemInBags = function(itemID)
        if itemID == 111 then return 0, 1 end
        if itemID == 222 then return 0, 2 end
        return nil, nil
    end

    local nextItem = DreamFish._test.GetNextDueBuffItem(true)
    assertEquals(nextItem, 111, "Should return first due buff")

    _G.FindItemInBags = originalFindItemInBags
end

function tests.GetNextDueBuffSkipsUnavailable()
    -- When first buff is excluded, the helper should still return a due item.
    DreamFish._test.SetDB({
        buffItems = {
            { itemID = 111 },
            { itemID = 222 },
        },
        buffAuraByItem = {},
    })

    -- Both due
    DreamFish._test.SetBuffLastUseTime(111, mockTime - 100)
    DreamFish._test.SetBuffLastUseTime(222, mockTime - 100)

    local nextItem = DreamFish._test.GetNextDueBuffItem(true, { [111] = true })
    assertTrue(nextItem ~= nil, "Should return some due buff item")
end

function tests.GetNextDueBuffReturnsNilWhenNoneDue()
    -- When no buffs are due, return nil
    DreamFish._test.SetDB({
        buffItems = {
            { itemID = 111 },
        },
        buffAuraByItem = {},
    })

    -- Used recently (not due)
    DreamFish._test.SetBuffLastUseTime(111, mockTime - 30)

    local originalFindItemInBags = _G.FindItemInBags
    _G.FindItemInBags = function() return 0, 1 end

    local nextItem = DreamFish._test.GetNextDueBuffItem(false)
    assertEquals(nextItem, nil, "Should return nil when no buffs due")

    _G.FindItemInBags = originalFindItemInBags
end

-- ============================================================================
-- Run All Tests
-- ============================================================================

print("\n=== DreamFish Buff Timing Tests ===\n")

for name, testFn in pairs(tests) do
    RunTest(name, testFn)
end

print("\n=== Summary ===")
print("Passed: " .. testsPassed)
print("Failed: " .. testsFailed)

if testsFailed > 0 then
    os.exit(1)
end
