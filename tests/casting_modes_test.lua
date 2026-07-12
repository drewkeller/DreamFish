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
_G.SetCVar = function() end
_G.PlayerHasToy = function() return true end
_G.IsSwimming = function() return false end

local function makeFrame()
    return {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function() end,
        GetScript = function() return nil end,
        HookScript = function() end,
        SetAllPoints = function() end,
        SetFrameStrata = function() end,
        SetAttribute = function() end,
        GetAttribute = function() return nil end,
        SetSize = function() end,
        SetPoint = function() end,
        IsShown = function() return false end,
        Show = function() end,
        Hide = function() end,
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
_G.GetItemCooldown = function() return 0, 0, 1 end
_G.CastSpellByName = function() end
_G.NUM_BAG_SLOTS = 4
_G.SlashCmdList = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.UIParent = {}
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
dofile("fishing/interactloot.lua")
dofile("fishing/state.lua")
dofile("audio/ducking.lua")
dofile("audio/alerts.lua")
dofile("ui/commands.lua")
dofile("ui/ace_widget_factory.lua")
dofile("ui/buff_item_drop_box.lua")
dofile("ui/config.lua")

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
        })
        DreamFisher.state.buffItemTransientUntil = {}
        DreamFisher.state.buffCastBlockWarningAt = 0
        DreamFisher.state.foodDrinkCastBlockWarningAt = 0
        DreamFisher._test.SetLastRightClickTime(0)  -- Clear click state
        DreamFisher.state.lastFishingSecureClickAt = 0
        DreamFisher._test.SetSessionState(DreamFisher.fishing.SessionStates.IDLE, "test-run-setup-reset")
        DreamFisher.state.fishingStartGraceUntil = 0
        DreamFisher.state.interactAcquireExpiresAt = 0
        DreamFisher.state.interactOverrideActive = false
        DreamFisher.state.interactOverrideExpiresAt = 0
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
        buffItems = { { itemID = 111 } },
        buffAuraByItem = {},
    })

    -- Buff is due
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 100)

    -- Mock FindItemInBags
    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function() return 0, 1 end

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

    DreamFisher.buff.FindItemInBags = originalFind
end

function tests.TargetSelectedRightClickDoesNotStartFishingFlow()
    local originalUnitExists = _G.UnitExists
    _G.UnitExists = function(unit)
        return unit == "target"
    end

    DreamFisher._test.SetLastRightClickTime(mockTime - 0.1)
    DreamFisher._test.HandleWorldRightClick()

    _G.UnitExists = originalUnitExists

    assertEquals(DreamFisher._test.GetLastRightClickTime(), 0,
        "Target-selected right-click should clear pending click timing")
end

function tests.TargetSelectedRightClickExitsFishingSessionState()
    local originalUnitExists = _G.UnitExists
    _G.UnitExists = function(unit)
        return unit == "target"
    end

    DreamFisher._test.SetSessionState(
        DreamFisher.fishing.SessionStates.LOOTING,
        "test-target-selected-exit"
    )
    DreamFisher.state.interactAcquireExpiresAt = mockTime + 5
    DreamFisher.state.savedFishingAudioCVars = {
        ambience = "0.4",
        music = "0.3",
        dialog = "0.8",
    }

    DreamFisher._test.HandleWorldRightClick()

    _G.UnitExists = originalUnitExists

    assertEquals(DreamFisher._test.GetSessionState(), DreamFisher.fishing.SessionStates.IDLE,
        "Target-selected right-click should exit to IDLE")
    assertEquals(DreamFisher.state.interactAcquireExpiresAt, 0,
        "Target-selected right-click should clear interact acquire window")
    assertEquals(DreamFisher.state.savedFishingAudioCVars, nil,
        "Target-selected right-click should restore and clear ducked audio state")
end

-- ============================================================================
-- Tests: Double-Click with Due Buff
-- ============================================================================

function tests.DoubleClickDueBuff()
    -- Double-click with due buff should use the buff
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111 } },
        buffAuraByItem = {},
    })

    -- Buff is due (used long ago)
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 100)

    -- Mock FindItemInBags
    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
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

    DreamFisher.buff.FindItemInBags = originalFind
end

function tests.DoubleClickDueBuffArmsProfessionSlotMacro()
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111 } },
        buffAuraByItem = {},
    })

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 100)

    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    if fishingFrame then
        local origSet = fishingFrame.SetAttribute
        fishingFrame.SetAttribute = function(self, k, v)
            capturedAttrs[k] = v
            return origSet and origSet(self, k, v)
        end
    end

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 111 then return 1, 18 end
        return nil, nil
    end

    mockTime = 1000
    DreamFisher._test.HandleWorldRightClick()
    mockTime = 1000.1
    DreamFisher._test.HandleWorldRightClick()

    DreamFisher.buff.FindItemInBags = originalFind

    if fishingFrame then
        assertEquals(capturedAttrs["type"], "macro", "Due buff arm should use secure macro action")
        local macrotext = capturedAttrs["macrotext"] or ""
        assertTrue(macrotext:find("/use item:111", 1, true) ~= nil,
            "Due buff arm macro should reference the due item")
        assertTrue(macrotext:find("/use 28", 1, true) == nil, "Non-lure due buff arm should not apply profession slot")
        assertTrue(macrotext:find("/cast Fishing", 1, true) == nil,
            "Due buff prep click should not cast Fishing on same click")
    end
end

function tests.DoubleClickSelectsFirstDueBuff()
    -- When multiple buffs are due, double-click uses first one
    DreamFisher._test.SetDB({
        buffItems = {
            { itemID = 111 },
            { itemID = 222 },
        },
        buffAuraByItem = {},
    })

    -- Both due
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 100)
    DreamFisher._test.SetBuffLastUseTime(222, mockTime - 100)

    -- Mock FindItemInBags
    local originalFind = DreamFisher.buff.FindItemInBags
    local findCalls = {}
    DreamFisher.buff.FindItemInBags = function(itemID)
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

    DreamFisher.buff.FindItemInBags = originalFind
end

-- ============================================================================
-- Tests: Double-Click without Due Buff
-- ============================================================================

function tests.DoubleClickNoDueBuff()
    -- Double-click without due buff should start fishing
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111 } },
        buffAuraByItem = {},
    })

    -- Buff NOT due (used recently)
    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 10)

    -- Mock FindItemInBags
    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function() return 0, 1 end

    -- First click
    mockTime = 1000
    DreamFisher._test.HandleWorldRightClick()

    -- Second click within window
    mockTime = 1000.1
    DreamFisher._test.HandleWorldRightClick()

    -- After double-click without due buff, time should be reset (fishing started)
    local finalTime = DreamFisher._test.GetLastRightClickTime()
    assertEquals(finalTime, 0, "Double-click without due buff should reset time (fishing started)")

    DreamFisher.buff.FindItemInBags = originalFind
end

-- ============================================================================
-- Tests: Double-Click Window
-- ============================================================================

function tests.DoubleClickWindowWithinTimeframe()
    -- Clicks within double-click window (0.25s) should form double-click
    local window = DreamFisher._test.GetDoubleClickWindow()
    assertEquals(window, 0.33, "Double-click window should be 0.33s")

    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111 } },
        buffAuraByItem = {},
    })

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 100)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function() return 0, 1 end

    -- First click
    mockTime = 1000
    DreamFisher._test.HandleWorldRightClick()

    -- Second click at window edge (0.25s later)
    mockTime = 1000 + window
    DreamFisher._test.HandleWorldRightClick()

    -- Should still be double-click (within window)
    local finalTime = DreamFisher._test.GetLastRightClickTime()
    assertEquals(finalTime, 0, "Clicks at window edge should be double-click")

    DreamFisher.buff.FindItemInBags = originalFind
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
        buffItems = { { itemID = 111 } },
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

function tests.HotkeyModeDoesNotActivateWorldClick()
    DreamFisher._test.SetDB({
        castingModes = {
            doubleRightClick = false,
            singleRightClick = false,
            castHotkey = true,
        },
        buffItems = {},
        buffAuraByItem = {},
    })

    local active = DreamFisher.fishing.IsWorldRightClickActivationPressed()
    assertFalse(active, "Hotkey mode should not activate world right-click handling")
end

function tests.HotkeyModeCanBeActivated()
    DreamFisher._test.SetDB({
        castingModes = {
            doubleRightClick = false,
            singleRightClick = false,
            castHotkey = true,
        },
        buffItems = {},
        buffAuraByItem = {},
    })

    assertTrue(DreamFisher.fishing.IsHotkeyActivationPressed(), "Hotkey mode should be active when enabled")
end

function tests.HotkeyModeDisabledReturnsFalse()
    DreamFisher._test.SetDB({
        castingModes = {
            doubleRightClick = true,
            singleRightClick = false,
            castHotkey = false,
        },
        buffItems = {},
        buffAuraByItem = {},
    })

    assertFalse(DreamFisher.fishing.IsHotkeyActivationPressed(), "Hotkey mode should be inactive when disabled")
end

-- ============================================================================
-- Tests: Hotkey Secure-Click Path (ConfigureFishingClickAction)
-- ============================================================================

function tests.TargetSelectedSkipsSecureFishingConfiguration()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    local originalUnitExists = _G.UnitExists
    _G.UnitExists = function(unit)
        return unit == "target"
    end

    local configured = DreamFisher.fishing.ConfigureFishingClickAction()

    _G.UnitExists = originalUnitExists

    assertEquals(configured, false,
        "Target-selected secure configure should return false")
    assertEquals(capturedAttrs["type"], nil,
        "Target-selected secure configure should not set an action type")
end

function tests.HotkeyConfiguresFishingSpellWhenNoBuffItems()
    -- With no configured buff items, fishing action should be set to spell cast
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    if fishingFrame then
        local origSet = fishingFrame.SetAttribute
        fishingFrame.SetAttribute = function(self, k, v)
            capturedAttrs[k] = v
            return origSet and origSet(self, k, v)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        useOversizedBobber = false,
        selectedBobberToy = nil,
    })

    DreamFisher.fishing.ConfigureFishingClickAction()

    if fishingFrame then
        assertEquals(capturedAttrs["type"], "spell", "No buff items: action type should be spell")
        assertEquals(capturedAttrs["spell"], "Fishing", "No buff items: spell should be Fishing")
    end
end

function tests.HotkeyConfiguresMacroWhenDueBuffReady()
    -- With a due buff item available, action should stage /use and defer /cast to a follow-up click.
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    if fishingFrame then
        local origSet = fishingFrame.SetAttribute
        fishingFrame.SetAttribute = function(self, k, v)
            capturedAttrs[k] = v
            return origSet and origSet(self, k, v)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = { { itemID = 111 } },
        buffAuraByItem = {},
        useOversizedBobber = false,
        selectedBobberToy = nil,
    })

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 200)

    -- Item must be in bags or GetNextDueBuffItem treats it as due-but-unavailable
    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 111 then return 0, 1 end
        return nil, nil
    end

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.buff.FindItemInBags = originalFind

    if fishingFrame then
        assertEquals(capturedAttrs["type"], "macro", "Due buff: action type should be macro")
        local macrotext = capturedAttrs["macrotext"] or ""
        assertTrue(macrotext:find("111") ~= nil, "Due buff: macro should reference item 111")
        assertTrue(macrotext:find("/use 28", 1, true) == nil, "Non-lure due buff should not target fishing profession slot")
        assertTrue(macrotext:find("/cast Fishing") == nil, "Due buff prep should not include /cast Fishing")
    end
end

function tests.HotkeyLureDueBuffAppliesProfessionSlot()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    if fishingFrame then
        local origSet = fishingFrame.SetAttribute
        fishingFrame.SetAttribute = function(self, k, v)
            capturedAttrs[k] = v
            return origSet and origSet(self, k, v)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = { { itemID = 333 } },
        buffAuraByItem = {},
        useOversizedBobber = false,
        selectedBobberToy = nil,
    })

    DreamFisher.const.knownBuffItems[333] = { spellID = 100333, duration = 60, category = "lure" }
    DreamFisher._test.SetBuffLastUseTime(333, mockTime - 200)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 333 then return 0, 3 end
        return nil, nil
    end

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.buff.FindItemInBags = originalFind
    DreamFisher.const.knownBuffItems[333] = nil

    if fishingFrame then
        local macrotext = capturedAttrs["macrotext"] or ""
        local lureIndex = macrotext:find("/use item:333", 1, true)
        local slotIndex = macrotext:find("/use 28", 1, true)
        assertTrue(lureIndex ~= nil, "Lure due buff should be used in macro")
        assertTrue(slotIndex ~= nil, "Lure due buff should apply profession slot")
        assertTrue(lureIndex < slotIndex, "Lure item should be used before profession slot")
    end
end

function tests.HotkeyLureDueBuffWarnsWhenNoFishingPoleEquipped()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    if fishingFrame then
        local origSet = fishingFrame.SetAttribute
        fishingFrame.SetAttribute = function(self, k, v)
            capturedAttrs[k] = v
            return origSet and origSet(self, k, v)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = { { itemID = 333 } },
        buffAuraByItem = {},
        useOversizedBobber = false,
        selectedBobberToy = nil,
    })

    DreamFisher.const.knownBuffItems[333] = { spellID = 100333, duration = 60, category = "lure" }
    DreamFisher._test.SetBuffLastUseTime(333, mockTime - 200)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 333 then return 0, 3 end
        return nil, nil
    end

    local cueCalls = 0
    local originalWarningCue = DreamFisher.audio.PlayWarningCue
    DreamFisher.audio.PlayWarningCue = function()
        cueCalls = cueCalls + 1
    end

    local originalGetInventoryItemID = _G.GetInventoryItemID
    _G.GetInventoryItemID = function(unit, slot)
        return nil
    end

    DreamFisher.state.lureMissingPoleWarningAt = 0

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.buff.FindItemInBags = originalFind
    DreamFisher.audio.PlayWarningCue = originalWarningCue
    _G.GetInventoryItemID = originalGetInventoryItemID
    DreamFisher.const.knownBuffItems[333] = nil

    if fishingFrame then
        local macrotext = capturedAttrs["macrotext"] or ""
        assertTrue(macrotext:find("/use item:333", 1, true) == nil,
            "Lure should be skipped when no fishing pole is equipped")
    end
    assertEquals(cueCalls, 1, "Missing fishing pole lure warning should play warning cue once")
end

function tests.HotkeyFallsBackToOtherConsumableWhenLureBlockedByMissingPole()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    if fishingFrame then
        local origSet = fishingFrame.SetAttribute
        fishingFrame.SetAttribute = function(self, k, v)
            capturedAttrs[k] = v
            return origSet and origSet(self, k, v)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {
            { itemID = 333 },
            { itemID = 444 },
        },
        buffAuraByItem = {},
        useOversizedBobber = false,
        selectedBobberToy = nil,
    })

    DreamFisher.const.knownBuffItems[333] = { spellID = 100333, duration = 60, category = "lure" }
    DreamFisher.const.knownBuffItems[444] = { spellID = 100444, duration = 60, category = "other_consumable" }
    DreamFisher._test.SetBuffLastUseTime(333, mockTime - 200)
    DreamFisher._test.SetBuffLastUseTime(444, mockTime - 200)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 333 then return 0, 3 end
        if itemID == 444 then return 0, 4 end
        return nil, nil
    end

    local cueCalls = 0
    local originalWarningCue = DreamFisher.audio.PlayWarningCue
    DreamFisher.audio.PlayWarningCue = function()
        cueCalls = cueCalls + 1
    end

    local originalGetInventoryItemID = _G.GetInventoryItemID
    _G.GetInventoryItemID = function(unit, slot)
        return nil
    end

    DreamFisher.state.lureMissingPoleWarningAt = 0

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.buff.FindItemInBags = originalFind
    DreamFisher.audio.PlayWarningCue = originalWarningCue
    _G.GetInventoryItemID = originalGetInventoryItemID
    DreamFisher.const.knownBuffItems[333] = nil
    DreamFisher.const.knownBuffItems[444] = nil

    if fishingFrame then
        local macrotext = capturedAttrs["macrotext"] or ""
        assertTrue(macrotext:find("/use item:333", 1, true) == nil,
            "Blocked lure should be skipped when no fishing pole is equipped")
        assertTrue(macrotext:find("/use item:444", 1, true) ~= nil,
            "Other consumable should be used when lure is blocked")
        assertTrue(macrotext:find("/use 28", 1, true) == nil,
            "Fallback non-lure item should not target fishing profession slot")
    end
    assertEquals(cueCalls, 1, "Blocked lure warning should still play warning cue once")
end

function tests.HotkeyAbortsWhenFoodDrinkTransientActiveWithoutLastingAura()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    if fishingFrame then
        local origSet = fishingFrame.SetAttribute
        fishingFrame.SetAttribute = function(self, k, v)
            capturedAttrs[k] = v
            return origSet and origSet(self, k, v)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = { { itemID = 242299, expectedDuration = 3600 } },
        buffAuraByItem = { ["242299"] = { spellID = 1269152, duration = 3600 } },
        useOversizedBobber = false,
        selectedBobberToy = nil,
    })

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.state.buffItemTransientUntil[242299] = mockTime + 15

    local cueCalls = 0
    local originalWarningCue = DreamFisher.audio.PlayWarningCue
    DreamFisher.audio.PlayWarningCue = function()
        cueCalls = cueCalls + 1
    end

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.audio.PlayWarningCue = originalWarningCue
    _G.C_UnitAuras = originalCUnitAuras

    if fishingFrame then
        assertEquals(capturedAttrs["type"], nil, "Food/drink transient should abort pre-cast action")
        assertEquals(capturedAttrs["spell"], nil, "Food/drink transient should not set Fishing spell")
        assertEquals(capturedAttrs["macrotext"], nil, "Food/drink transient should not set macro action")
    end
    assertEquals(cueCalls, 1, "Food/drink transient cast block should play warning cue once")
end

function tests.HotkeyTransientActiveDoesNotFallbackToOtherBuffItems()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    if fishingFrame then
        local origSet = fishingFrame.SetAttribute
        fishingFrame.SetAttribute = function(self, k, v)
            capturedAttrs[k] = v
            return origSet and origSet(self, k, v)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {
            { itemID = 242299, expectedDuration = 3600 },
            { itemID = 238367, expectedDuration = 30 },
        },
        buffAuraByItem = {
            ["242299"] = { spellID = 1269152, duration = 3600 },
            ["238367"] = { spellID = 1235216, duration = 30 },
        },
        useOversizedBobber = false,
        selectedBobberToy = nil,
    })

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 242299 then return 1, 18 end
        if itemID == 238367 then return 4, 17 end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.state.buffItemTransientUntil[242299] = mockTime + 16

    local cueCalls = 0
    local originalWarningCue = DreamFisher.audio.PlayWarningCue
    DreamFisher.audio.PlayWarningCue = function()
        cueCalls = cueCalls + 1
    end

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.audio.PlayWarningCue = originalWarningCue
    DreamFisher.buff.FindItemInBags = originalFind
    _G.C_UnitAuras = originalCUnitAuras

    if fishingFrame then
        local macrotext = capturedAttrs["macrotext"] or ""
        assertEquals(capturedAttrs["type"], nil, "Transient buff should abort pre-cast action")
        assertTrue(macrotext:find("/use item:238367", 1, true) == nil,
            "No fallback buff item should be used while transient buff is active")
    end
    assertEquals(cueCalls, 1, "Transient cast block should play warning cue once")
end

function tests.HotkeyTeaTransientBlocksFallbackEvenIfTrackedAuraLooksActive()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    if fishingFrame then
        local origSet = fishingFrame.SetAttribute
        fishingFrame.SetAttribute = function(self, k, v)
            capturedAttrs[k] = v
            return origSet and origSet(self, k, v)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {
            { itemID = 242299, expectedDuration = 3600 },
            { itemID = 238381, expectedDuration = 30 },
        },
        -- Simulate transient remap for tea in saved mapping.
        buffAuraByItem = {
            ["242299"] = { spellID = 1277461, duration = 20 },
            ["238381"] = { spellID = 1237942, duration = 30 },
        },
        useOversizedBobber = false,
        selectedBobberToy = nil,
    })

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 242299 then return 1, 18 end
        if itemID == 238381 then return 3, 31 end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == 1277461 then
                return {
                    spellId = 1277461,
                    duration = 20,
                    expirationTime = mockTime + 16,
                }
            end
            -- Known lasting tea aura is not active yet.
            if spellID == 1269152 then
                return nil
            end
            return nil
        end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.state.buffItemTransientUntil[242299] = mockTime + 16

    local cueCalls = 0
    local originalWarningCue = DreamFisher.audio.PlayWarningCue
    DreamFisher.audio.PlayWarningCue = function()
        cueCalls = cueCalls + 1
    end

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.audio.PlayWarningCue = originalWarningCue
    DreamFisher.buff.FindItemInBags = originalFind
    _G.C_UnitAuras = originalCUnitAuras

    if fishingFrame then
        local macrotext = capturedAttrs["macrotext"] or ""
        assertEquals(capturedAttrs["type"], nil, "Tea transient should abort pre-cast action")
        assertTrue(macrotext:find("/use item:238381", 1, true) == nil,
            "Hollow Grouper should not be used while tea transient is active")
    end
    assertEquals(cueCalls, 1, "Tea transient cast block should play warning cue once")
end

function tests.PrecastAppliesRaftBeforeDueBuff()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = { { itemID = 111, expectedDuration = 60 } },
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = 85500,
        selectedBobberToy = nil,
        useOversizedBobber = false,
    })

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 200)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 111 then return 0, 1 end
        return nil, nil
    end

    local originalSwimming = _G.IsSwimming
    _G.IsSwimming = function() return false end

    local originalGetItemSpell = _G.GetItemSpell
    _G.GetItemSpell = function(itemID)
        if itemID == 85500 then
            return "Angler's Fishing Raft", 123450
        end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == 123450 then
                return {
                    spellId = 123450,
                    duration = 600,
                    expirationTime = mockTime + 10,
                }
            end
            return nil
        end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.IsSwimming = originalSwimming
    _G.GetItemSpell = originalGetItemSpell
    _G.C_UnitAuras = originalCUnitAuras
    DreamFisher.buff.FindItemInBags = originalFind

    local macrotext = capturedAttrs["macrotext"] or ""
    local raftIndex = macrotext:find("/use item:85500", 1, true)
    local buffIndex = macrotext:find("/use item:111", 1, true)
    assertTrue(raftIndex ~= nil, "Pre-cast should include raft toy use")
    assertTrue(buffIndex ~= nil, "Pre-cast should include due buff use")
    assertTrue(raftIndex < buffIndex, "Raft use should appear before due buff use")
end

function tests.PrecastAppliesBobberBeforeDueBuff()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = { { itemID = 111, expectedDuration = 60 } },
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = nil,
        selectedBobberToy = 142531,
        useOversizedBobber = false,
    })

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 200)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 111 then return 0, 1 end
        return nil, nil
    end

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.buff.FindItemInBags = originalFind

    local macrotext = capturedAttrs["macrotext"] or ""
    local bobberIndex = macrotext:find("/use item:142531", 1, true)
    local buffIndex = macrotext:find("/use item:111", 1, true)
    assertTrue(bobberIndex ~= nil, "Pre-cast should include bobber use")
    assertTrue(buffIndex ~= nil, "Pre-cast should include due buff use")
    assertTrue(bobberIndex < buffIndex, "Bobber use should appear before due buff use")
end

function tests.PrecastEquipsSelectedFishingPoleBeforeBobber()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = nil,
        selectedFishingPole = 555001,
        selectedUnderlightAngler = nil,
        selectedBobberToy = 142531,
        useOversizedBobber = false,
    })

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 555001 then return 0, 2 end
        return nil, nil
    end

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.buff.FindItemInBags = originalFind

    local macrotext = capturedAttrs["macrotext"] or ""
    local poleIndex = macrotext:find("/equip item:555001", 1, true)
    local bobberIndex = macrotext:find("/use item:142531", 1, true)
    assertTrue(poleIndex ~= nil, "Pre-cast should include selected fishing pole equip")
    assertTrue(bobberIndex ~= nil, "Pre-cast should include bobber use")
    assertTrue(poleIndex < bobberIndex, "Fishing pole equip should appear before bobber")
end

function tests.PrecastLockUnderlightSkipsPrimaryPoleSwap()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = nil,
        selectedFishingPole = { itemID = 555001, isChecked = false },
        selectedUnderlightAngler = { itemID = 133755, isChecked = true },
        selectedBobberToy = nil,
        useOversizedBobber = false,
    })

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 133755 then return 0, 3 end
        if itemID == 555001 then return 0, 2 end
        return nil, nil
    end

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.buff.FindItemInBags = originalFind

    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext:find("/equip item:133755", 1, true) ~= nil,
        "Lock-underlight mode should equip Underlight")
    assertTrue(macrotext:find("/equip item:555001", 1, true) == nil,
        "Lock-underlight mode should not swap to primary fishing pole")
end

function tests.AlwaysExceptFishingIdleHelperEquipsUnderlight()
    DreamFisher._test.SetDB({
        buffItems = {},
        buffAuraByItem = {},
        selectedUnderlightAngler = 133755,
    })

    DreamFisher._test.SetSessionState(DreamFisher.fishing.SessionStates.IDLE, "test-underlight-idle")

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 133755 then return 0, 1 end
        return nil, nil
    end

    local originalEquip = _G.EquipItemByName
    local originalGetInventoryItemID = _G.GetInventoryItemID
    local equippedItemInMainHand = nil
    local equipCalls = 0
    _G.EquipItemByName = function(itemRef, slot)
        equipCalls = equipCalls + 1
        if tostring(itemRef) == "item:133755" then
            equippedItemInMainHand = 133755
        end
    end
    _G.GetInventoryItemID = function(_, slot)
        if slot == 16 then
            return equippedItemInMainHand
        end
        return nil
    end

    local equipped = DreamFisher.fishing.MaybeEquipConfiguredUnderlight("test-idle")

    _G.EquipItemByName = originalEquip
    _G.GetInventoryItemID = originalGetInventoryItemID
    DreamFisher.buff.FindItemInBags = originalFind

    assertTrue(equipped == true, "Idle helper should report successful Underlight equip")
    assertTrue(equipCalls > 0, "Idle helper should call EquipItemByName for Underlight")
end

function tests.UnderlightIdleHelperFallsBackToUnslottedEquip()
    DreamFisher._test.SetDB({
        buffItems = {},
        buffAuraByItem = {},
        selectedUnderlightAngler = 133755,
    })

    DreamFisher._test.SetSessionState(DreamFisher.fishing.SessionStates.IDLE, "test-underlight-idle-fallback")

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 133755 then return 0, 1 end
        return nil, nil
    end

    local originalEquip = _G.EquipItemByName
    local originalGetInventoryItemID = _G.GetInventoryItemID
    local equippedItemInMainHand = nil
    local sawSlot28Attempt = false
    local sawUnslottedAttempt = false

    _G.EquipItemByName = function(itemRef, slot)
        if tostring(itemRef) ~= "item:133755" then
            return
        end

        if slot == 28 then
            sawSlot28Attempt = true
            return
        end

        sawUnslottedAttempt = true
        equippedItemInMainHand = 133755
    end

    _G.GetInventoryItemID = function(_, slot)
        if slot == 16 then
            return equippedItemInMainHand
        end
        return nil
    end

    local equipped = DreamFisher.fishing.MaybeEquipConfiguredUnderlight("test-idle-fallback")

    _G.EquipItemByName = originalEquip
    _G.GetInventoryItemID = originalGetInventoryItemID
    DreamFisher.buff.FindItemInBags = originalFind

    assertTrue(equipped == true, "Idle helper should succeed via unslotted fallback")
    assertTrue(sawSlot28Attempt, "Idle helper should try profession-slot equip first")
    assertTrue(sawUnslottedAttempt, "Idle helper should fallback to unslotted equip")
end

function tests.ModeChangeDisabledEquipsPrimaryPole()
    DreamFisher._test.SetDB({
        buffItems = {},
        buffAuraByItem = {},
        selectedFishingPole = 555001,
        selectedUnderlightAngler = 133755,
    })

    DreamFisher._test.SetSessionState(DreamFisher.fishing.SessionStates.IDLE, "test-mode-change-disabled")

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 133755 then return 0, 1 end
        if itemID == 555001 then return 0, 2 end
        return nil, nil
    end

    local originalEquip = _G.EquipItemByName
    local originalGetInventoryItemID = _G.GetInventoryItemID
    local equippedItemInMainHand = nil

    _G.EquipItemByName = function(itemRef)
        if tostring(itemRef) == "item:555001" then
            equippedItemInMainHand = 555001
        end
    end

    _G.GetInventoryItemID = function(_, slot)
        if slot == 16 then
            return equippedItemInMainHand
        end
        return nil
    end

    local equipped = DreamFisher.fishing.MaybeEquipConfiguredUnderlight("config-underlight-mode-change")

    _G.EquipItemByName = originalEquip
    _G.GetInventoryItemID = originalGetInventoryItemID
    DreamFisher.buff.FindItemInBags = originalFind

    assertTrue(equipped == true, "Mode-change should immediately equip primary pole for disabled mode")
end

function tests.PrecastSkipsBobberWhenAuraCoversCast()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = { { itemID = 111, expectedDuration = 60 } },
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = nil,
        selectedBobberToy = 142529,
        useOversizedBobber = false,
    })

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 200)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 111 then return 0, 1 end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == 231319 then
                return {
                    spellId = 231319,
                    duration = 3600,
                    expirationTime = mockTime + 1800,
                }
            end
            return nil
        end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.C_UnitAuras = originalCUnitAuras
    DreamFisher.buff.FindItemInBags = originalFind

    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext:find("/use item:142529", 1, true) == nil,
        "Bobber should not be reapplied while bobber aura covers cast")
    assertTrue(macrotext:find("/use item:111", 1, true) ~= nil,
        "Due buff should still be included when bobber aura covers cast")
end

function tests.PrecastAppliesBobberWhenAuraExpiring()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = { { itemID = 111, expectedDuration = 60 } },
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = nil,
        selectedBobberToy = 142529,
        useOversizedBobber = false,
    })

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 200)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 111 then return 0, 1 end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == 231319 then
                return {
                    spellId = 231319,
                    duration = 3600,
                    expirationTime = mockTime + 10,
                }
            end
            return nil
        end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.C_UnitAuras = originalCUnitAuras
    DreamFisher.buff.FindItemInBags = originalFind

    local macrotext = capturedAttrs["macrotext"] or ""
    local bobberIndex = macrotext:find("/use item:142529", 1, true)
    local buffIndex = macrotext:find("/use item:111", 1, true)
    assertTrue(bobberIndex ~= nil, "Bobber should be reapplied when aura is expiring")
    assertTrue(buffIndex ~= nil, "Due buff should still be included when bobber aura is expiring")
    assertTrue(bobberIndex < buffIndex, "Bobber should remain ordered before due buff")
end

function tests.PrecastBobberFallsBackToCooldownWhenAuraUnavailable()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = { { itemID = 111, expectedDuration = 60 } },
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = nil,
        selectedBobberToy = 142529,
        useOversizedBobber = false,
    })

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 200)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 111 then return 0, 1 end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.C_UnitAuras = originalCUnitAuras
    DreamFisher.buff.FindItemInBags = originalFind

    local macrotext = capturedAttrs["macrotext"] or ""
    local bobberIndex = macrotext:find("/use item:142529", 1, true)
    local buffIndex = macrotext:find("/use item:111", 1, true)
    assertTrue(bobberIndex ~= nil, "Bobber should still apply when aura cannot be observed and cooldown is ready")
    assertTrue(buffIndex ~= nil, "Due buff should still be included when bobber falls back to cooldown")
    assertTrue(bobberIndex < buffIndex, "Fallback bobber use should remain ordered before due buff")
end

function tests.PrecastPrioritizesBaitAfterLureBeforeFoodDrink()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {
            { itemID = 262651, expectedDuration = 600 }, -- lure
            { itemID = 198401, expectedDuration = 1800 }, -- bait
            { itemID = 242299, expectedDuration = 3600 }, -- food/drink
        },
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = nil,
        selectedBobberToy = nil,
        useOversizedBobber = false,
    })

    DreamFisher._test.SetBuffLastUseTime(262651, mockTime - 800)
    DreamFisher._test.SetBuffLastUseTime(198401, mockTime - 2000)
    DreamFisher._test.SetBuffLastUseTime(242299, mockTime - 4000)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 262651 then return nil, nil end -- force lure unavailable so next category is evaluated
        if itemID == 198401 then return 0, 9 end
        if itemID == 242299 then return 0, 10 end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.C_UnitAuras = originalCUnitAuras
    DreamFisher.buff.FindItemInBags = originalFind

    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext:find("/use item:242299", 1, true) ~= nil,
        "Food/drink item should be selected before bait after lure pass")
    assertTrue(macrotext:find("/use item:198401", 1, true) == nil,
        "Bait should not be selected when food/drink is due and available")
end

function tests.PrecastSkipsBaitCategoryWhenAnyBaitAuraIsActive()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {
            { itemID = 198401, expectedDuration = 1800 }, -- bait
            { itemID = 241316, expectedDuration = 3600 }, -- other consumable
        },
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = nil,
        selectedBobberToy = nil,
        useOversizedBobber = false,
    })

    DreamFisher._test.SetBuffLastUseTime(198401, mockTime - 2000)
    DreamFisher._test.SetBuffLastUseTime(241316, mockTime - 4000)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 198401 then return 0, 9 end
        if itemID == 241316 then return 0, 10 end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == 375787 then -- Cerulean Spinefish Lure active
                return {
                    spellId = 375787,
                    duration = 1800,
                    expirationTime = mockTime + 900,
                }
            end
            return nil
        end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.C_UnitAuras = originalCUnitAuras
    DreamFisher.buff.FindItemInBags = originalFind

    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext:find("/use item:198401", 1, true) == nil,
        "Bait category should be skipped while any bait aura is active")
    assertTrue(macrotext:find("/use item:241316", 1, true) ~= nil,
        "Selection should continue to next category when bait pass is skipped")
end

function tests.PrecastPrioritizesFoodDrinkBeforeOtherConsumable()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {
            { itemID = 241316, expectedDuration = 3600 },
            { itemID = 242299, expectedDuration = 3600 },
        },
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = nil,
        selectedBobberToy = nil,
        useOversizedBobber = false,
    })

    DreamFisher._test.SetBuffLastUseTime(241316, mockTime - 3700)
    DreamFisher._test.SetBuffLastUseTime(242299, mockTime - 3700)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 241316 then return 0, 6 end
        if itemID == 242299 then return 0, 7 end
        return nil, nil
    end

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.buff.FindItemInBags = originalFind

    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext:find("/use item:242299", 1, true) ~= nil,
        "Food/drink item should be selected when both categories are due")
    assertTrue(macrotext:find("/use item:241316", 1, true) == nil,
        "Other consumable should not be selected when food/drink is due")
end

function tests.HotkeyConfiguresFishingWhenBuffNotDue()
    -- Buff present but not due: should fall through to plain fishing spell
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    if fishingFrame then
        local origSet = fishingFrame.SetAttribute
        fishingFrame.SetAttribute = function(self, k, v)
            capturedAttrs[k] = v
            return origSet and origSet(self, k, v)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = { { itemID = 111 } },
        buffAuraByItem = {},
        useOversizedBobber = false,
        selectedBobberToy = nil,
    })

    DreamFisher._test.SetBuffLastUseTime(111, mockTime - 5)

    -- Item must be in bags or GetNextDueBuffItem treats it as due-but-unavailable
    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 111 then return 0, 1 end
        return nil, nil
    end

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.buff.FindItemInBags = originalFind

    if fishingFrame then
        local actionType = capturedAttrs["type"]
        assertTrue(
            actionType == "spell" or actionType == nil or actionType == "macro",
            "Not-due buff: should configure spell or macro with no buff pre-cast"
        )
    end
end

function tests.HookedLootModeConfiguresInteractAction()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = true,
    })

    DreamFisher._test.SetSessionState(
        DreamFisher.fishing.SessionStates.WAITING_FOR_STRIKE,
        "test-hooked-mode-bobber-only"
    )
    DreamFisher.state.fishingStartGraceUntil = mockTime - 1
    DreamFisher.fishing.ConfigureFishingClickAction()

    assertEquals(capturedAttrs["type"], "macro", "Hooked mode should configure macro action")
    assertTrue((capturedAttrs["macrotext"] or ""):find("/interact", 1, true) ~= nil,
        "Hooked mode should configure interact macro")
end

function tests.HookedLootModeDisabledKeepsFishingCastAction()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = false,
    })

    DreamFisher._test.SetSessionState(
        DreamFisher.fishing.SessionStates.WAITING_FOR_STRIKE,
        "test-hooked-mode-disabled-bobber-only"
    )
    DreamFisher.fishing.ConfigureFishingClickAction()

    assertEquals(capturedAttrs["type"], "spell", "Disabled hooked mode should keep normal cast action")
    assertEquals(capturedAttrs["spell"], "Fishing", "Disabled hooked mode should cast Fishing")
end

function tests.HookedLootFallbackWindowConfiguresInteractAction()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = true,
    })

    DreamFisher._test.SetSessionState(DreamFisher.fishing.SessionStates.CASTING, "test-hooked-fallback-window")
    DreamFisher.state.fishingStartGraceUntil = mockTime - 1

    DreamFisher.fishing.ConfigureFishingClickAction()

    assertEquals(capturedAttrs["type"], "macro", "Fallback hook window should configure interact macro")
    assertTrue((capturedAttrs["macrotext"] or ""):find("/interact", 1, true) ~= nil,
        "Fallback hook window should use interact")
end

function tests.PrecastIncludesRaftWhenSwimming()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = 85500,
        selectedBobberToy = nil,
        useOversizedBobber = false,
    })

    local originalSwimming = _G.IsSwimming
    _G.IsSwimming = function() return true end

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.IsSwimming = originalSwimming

    assertEquals(capturedAttrs["type"], "macro", "Swimming with selected raft should use macro pre-cast")
    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext:find("85500", 1, true) ~= nil, "Pre-cast macro should include selected raft toy")
    assertTrue(macrotext:find("/cast Fishing", 1, true) == nil, "Raft-only swimming pre-cast should not cast Fishing on same click")
end

function tests.PrecastSkipsBobberAndOversizedWhileSwimming()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = 85500,
        selectedBobberToy = 147307,
        useOversizedBobber = true,
    })

    local originalSwimming = _G.IsSwimming
    _G.IsSwimming = function() return true end

    local originalGetItemSpell = _G.GetItemSpell
    _G.GetItemSpell = function(itemID)
        if itemID == 85500 then
            return "Angler's Fishing Raft", 123450
        end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.IsSwimming = originalSwimming
    _G.GetItemSpell = originalGetItemSpell
    _G.C_UnitAuras = originalCUnitAuras

    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext:find("/use item:85500", 1, true) ~= nil,
        "Raft should be applied while swimming when aura is missing")
    assertTrue(macrotext:find("/use item:147307", 1, true) == nil,
        "Bobber should not be applied while swimming")
    assertTrue(macrotext:find("/use item:202207", 1, true) == nil,
        "Oversized bobber should not be applied while swimming")
end

function tests.PrecastSkipsOversizedWhenAuraCoversCast()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = nil,
        selectedBobberToy = nil,
        useOversizedBobber = true,
    })

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == 397827 then
                return {
                    spellId = 397827,
                    duration = 3600,
                    expirationTime = mockTime + 2700,
                }
            end
            return nil
        end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.C_UnitAuras = originalCUnitAuras

    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext:find("/use item:202207", 1, true) == nil,
        "Oversized bobber should not be reapplied while aura covers cast")
end

function tests.PrecastAppliesOversizedWhenAuraExpiring()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = nil,
        selectedBobberToy = nil,
        useOversizedBobber = true,
    })

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == 397827 then
                return {
                    spellId = 397827,
                    duration = 3600,
                    expirationTime = mockTime + 10,
                }
            end
            return nil
        end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.C_UnitAuras = originalCUnitAuras

    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext:find("/use item:202207", 1, true) ~= nil,
        "Oversized bobber should be reapplied when aura is expiring")
end

function tests.PrecastUsesOnlyRaftItemWhenSwimmingAndNeeded()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = { { itemID = 241316, expectedDuration = 3600 } },
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = 85500,
        selectedBobberToy = 147307,
        useOversizedBobber = true,
    })

    DreamFisher._test.SetBuffLastUseTime(241316, mockTime - 4000)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 241316 then return 0, 8 end
        return nil, nil
    end

    local originalSwimming = _G.IsSwimming
    _G.IsSwimming = function() return true end

    local originalGetItemSpell = _G.GetItemSpell
    _G.GetItemSpell = function(itemID)
        if itemID == 85500 then
            return "Angler's Fishing Raft", 123450
        end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    DreamFisher.buff.FindItemInBags = originalFind
    _G.IsSwimming = originalSwimming
    _G.GetItemSpell = originalGetItemSpell
    _G.C_UnitAuras = originalCUnitAuras

    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext:find("/use item:85500", 1, true) ~= nil,
        "Raft should be applied while swimming when needed")
    assertTrue(macrotext:find("/use item:147307", 1, true) == nil,
        "Bobber should be skipped when raft is exclusive")
    assertTrue(macrotext:find("/use item:202207", 1, true) == nil,
        "Oversized bobber should be skipped when raft is exclusive")
    assertTrue(macrotext:find("/use item:241316", 1, true) == nil,
        "Due consumable should be skipped when raft is exclusive")
    assertTrue(macrotext:find("/cast Fishing", 1, true) == nil,
        "Fishing cast should be skipped on raft-exclusive swimming click")
end

function tests.ClickCastUsesRaftOnlyWhenSwimmingEvenIfBuffDue()
    local fishingAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origFishingSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        fishingAttrs[k] = v
        return origFishingSet and origFishingSet(self, k, v)
    end

    local buffAttrs = {}
    local buffFrame = DreamFisher.fishing.CreateSecureBuffFrame()
    local origBuffSet = buffFrame.SetAttribute
    buffFrame.SetAttribute = function(self, k, v)
        buffAttrs[k] = v
        return origBuffSet and origBuffSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = false, doubleRightClick = true },
        buffItems = { { itemID = 241316, expectedDuration = 3600 } },
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = 85500,
        selectedBobberToy = nil,
        useOversizedBobber = false,
    })

    DreamFisher._test.SetBuffLastUseTime(241316, mockTime - 4000)

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function(itemID)
        if itemID == 241316 then return 0, 8 end
        return nil, nil
    end

    local originalSwimming = _G.IsSwimming
    _G.IsSwimming = function() return true end

    local originalGetItemSpell = _G.GetItemSpell
    _G.GetItemSpell = function(itemID)
        if itemID == 85500 then
            return "Angler's Fishing Raft", 123450
        end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function() return nil end,
        GetAuraDataByIndex = function() return nil end,
    }

    mockTime = 1000
    DreamFisher._test.HandleWorldRightClick()
    mockTime = 1000.1
    DreamFisher._test.HandleWorldRightClick()

    DreamFisher.buff.FindItemInBags = originalFind
    _G.IsSwimming = originalSwimming
    _G.GetItemSpell = originalGetItemSpell
    _G.C_UnitAuras = originalCUnitAuras

    local macrotext = fishingAttrs["macrotext"] or ""
    assertTrue(macrotext:find("/use item:85500", 1, true) ~= nil,
        "Click-cast should route to raft-only pre-cast while swimming")
    assertTrue(macrotext:find("/use item:241316", 1, true) == nil,
        "Click-cast should not arm due buff when raft-exclusive swimming path is active")
    assertTrue(macrotext:find("/cast Fishing", 1, true) == nil,
        "Click-cast raft-exclusive path should not cast Fishing on same click")
    assertTrue(buffAttrs["dreamfisher_itemid"] == nil,
        "Buff secure frame should not be armed on raft-exclusive swimming click")
end

function tests.PrecastSkipsRaftWhenAuraCoversCast()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = 85500,
        selectedBobberToy = nil,
        useOversizedBobber = false,
    })

    local originalSwimming = _G.IsSwimming
    _G.IsSwimming = function() return true end

    local originalGetItemSpell = _G.GetItemSpell
    _G.GetItemSpell = function(itemID)
        if itemID == 85500 then
            return "Angler's Fishing Raft", 123450
        end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == 123450 then
                return {
                    spellId = 123450,
                    duration = 600,
                    expirationTime = mockTime + 90,
                }
            end
            return nil
        end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.IsSwimming = originalSwimming
    _G.GetItemSpell = originalGetItemSpell
    _G.C_UnitAuras = originalCUnitAuras

    assertEquals(capturedAttrs["type"], "spell", "Raft should not be reapplied when aura covers cast window")
    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext == "", "No pre-cast raft macro should be configured when aura is sufficient")
end

function tests.PrecastReappliesRaftWhenAuraExpiringEvenIfNotSwimming()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = false,
        selectedRaftToy = 85500,
        selectedBobberToy = nil,
        useOversizedBobber = false,
    })

    local originalSwimming = _G.IsSwimming
    _G.IsSwimming = function() return false end

    local originalGetItemSpell = _G.GetItemSpell
    _G.GetItemSpell = function(itemID)
        if itemID == 85500 then
            return "Angler's Fishing Raft", 123450
        end
        return nil, nil
    end

    local originalCUnitAuras = _G.C_UnitAuras
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == 123450 then
                return {
                    spellId = 123450,
                    duration = 600,
                    expirationTime = mockTime + 10,
                }
            end
            return nil
        end,
        GetAuraDataByIndex = function() return nil end,
    }

    DreamFisher.fishing.ConfigureFishingClickAction()

    _G.IsSwimming = originalSwimming
    _G.GetItemSpell = originalGetItemSpell
    _G.C_UnitAuras = originalCUnitAuras

    assertEquals(capturedAttrs["type"], "macro", "Raft should be reapplied when aura is expiring during cast")
    local macrotext = capturedAttrs["macrotext"] or ""
    assertTrue(macrotext:find("/use item:85500", 1, true) ~= nil,
        "Pre-cast macro should reapply raft when aura would timeout during cast")
end

function tests.HookedRightClickRoutesToInteractWhenHooked()
    local originalUnitExists = _G.UnitExists
    _G.UnitExists = function(unit)
        if unit == "target" then
            return false
        end
        return false
    end

    local originalBindingClick = _G.SetOverrideBindingClick
    local bindingCalls = 0
    _G.SetOverrideBindingClick = function(...)
        bindingCalls = bindingCalls + 1
        if originalBindingClick then
            return originalBindingClick(...)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = {
            doubleRightClick = true,
            singleRightClick = false,
            castHotkey = false,
        },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = true,
    })

    DreamFisher._test.SetSessionState(DreamFisher.fishing.SessionStates.WAITING_FOR_STRIKE, "test-hooked-right-click")
    DreamFisher.state.fishingStartGraceUntil = mockTime - 1
    DreamFisher.state.interactAcquireExpiresAt = mockTime + 2
    DreamFisher._test.SetLastRightClickTime(0)

    DreamFisher._test.HandleWorldRightClick()

    assertTrue(bindingCalls > 0, "Hooked world right-click should route to secure interact binding")
    assertEquals(DreamFisher._test.GetLastRightClickTime(), 0, "Hooked world right-click should clear double-click timing")

    _G.UnitExists = originalUnitExists
    _G.SetOverrideBindingClick = originalBindingClick
end

function tests.StaleHookedOverrideFallsBackToCastFlow()
    local originalGetDiag = DreamFisher.fishing.GetInteractDiagnostics
    DreamFisher.fishing.GetInteractDiagnostics = function()
        return {
            softExists = false,
            targetExists = false,
            mouseoverExists = false,
        }
    end

    DreamFisher._test.SetDB({
        castingModes = {
            doubleRightClick = true,
            singleRightClick = false,
            castHotkey = false,
        },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = true,
    })

    DreamFisher._test.SetSessionState(DreamFisher.fishing.SessionStates.IDLE, "test-stale-hooked-override")
    DreamFisher.state.fishingStartTime = 0
    DreamFisher.state.fishingStartGraceUntil = 0
    DreamFisher.state.interactOverrideActive = true
    DreamFisher.state.interactOverrideExpiresAt = mockTime + 10
    DreamFisher.state.interactAcquireExpiresAt = 0
    DreamFisher._test.SetLastRightClickTime(0)

    DreamFisher._test.HandleWorldRightClick()

    assertEquals(DreamFisher._test.GetLastRightClickTime(), mockTime,
        "Stale hooked override should fall back to normal single-click cast flow")

    DreamFisher.fishing.GetInteractDiagnostics = originalGetDiag
end

function tests.RecentFishingWithInteractTargetRoutesHookedFallback()
    local originalGetDiag = DreamFisher.fishing.GetInteractDiagnostics
    DreamFisher.fishing.GetInteractDiagnostics = function()
        return {
            softExists = true,
            targetExists = false,
            mouseoverExists = false,
        }
    end

    local originalBindingClick = _G.SetOverrideBindingClick
    local bindingCalls = 0
    _G.SetOverrideBindingClick = function(...)
        bindingCalls = bindingCalls + 1
        if originalBindingClick then
            return originalBindingClick(...)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = {
            doubleRightClick = true,
            singleRightClick = false,
            castHotkey = false,
        },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = true,
    })

    DreamFisher._test.SetSessionState(DreamFisher.fishing.SessionStates.IDLE, "test-recent-fishing-target")
    DreamFisher.state.fishingStartTime = mockTime - 3
    DreamFisher.state.fishingStartGraceUntil = mockTime - 1
    DreamFisher.state.interactOverrideActive = false
    DreamFisher.state.interactAcquireExpiresAt = 0
    DreamFisher._test.SetLastRightClickTime(0)

    DreamFisher._test.HandleWorldRightClick()

    assertEquals(bindingCalls, 0,
        "Recent fishing with interact target should not force hooked interact without hooked mode")
    assertEquals(DreamFisher._test.GetLastRightClickTime(), mockTime,
        "Without hooked-mode routing, first click should follow normal timing flow")

    DreamFisher.fishing.GetInteractDiagnostics = originalGetDiag
    _G.SetOverrideBindingClick = originalBindingClick
end

function tests.PostCastHookWindowRoutesHookedFallbackWithoutUnits()
    local originalGetDiag = DreamFisher.fishing.GetInteractDiagnostics
    DreamFisher.fishing.GetInteractDiagnostics = function()
        return {
            softExists = false,
            targetExists = false,
            mouseoverExists = false,
        }
    end

    local originalBindingClick = _G.SetOverrideBindingClick
    local bindingCalls = 0
    _G.SetOverrideBindingClick = function(...)
        bindingCalls = bindingCalls + 1
        if originalBindingClick then
            return originalBindingClick(...)
        end
    end

    DreamFisher._test.SetDB({
        castingModes = {
            doubleRightClick = true,
            singleRightClick = false,
            castHotkey = false,
        },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = true,
    })

    DreamFisher._test.SetSessionState(DreamFisher.fishing.SessionStates.CASTING, "test-post-cast-hook-window")
    DreamFisher.state.fishingStartTime = mockTime - 3
    DreamFisher.state.fishingStartGraceUntil = mockTime - 1
    DreamFisher.state.interactOverrideActive = false
    DreamFisher.state.interactOverrideExpiresAt = 0
    DreamFisher.state.interactAcquireExpiresAt = 0
    DreamFisher._test.SetLastRightClickTime(0)

    DreamFisher._test.HandleWorldRightClick()

    assertEquals(bindingCalls, 0,
        "Post-cast no-evidence state should not force hooked interact routing")
    assertEquals(DreamFisher._test.GetLastRightClickTime(), mockTime,
        "Post-cast no-evidence state should return to normal click timing flow")
    assertEquals(DreamFisher._test.GetSessionState(), DreamFisher.fishing.SessionStates.IDLE,
        "Post-cast no-evidence fallback should finalize to IDLE")

    DreamFisher.fishing.GetInteractDiagnostics = originalGetDiag
    _G.SetOverrideBindingClick = originalBindingClick
end

function tests.HookedAcquireWindowKeepsTargetMacroWithoutSoftName()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = true,
    })

    DreamFisher._test.SetSessionState(DreamFisher.fishing.SessionStates.CASTING, "test-hooked-acquire-window")
    DreamFisher.state.fishingStartGraceUntil = mockTime - 1
    DreamFisher.state.interactAcquireExpiresAt = 0

    local originalUnitExists = _G.UnitExists
    local originalUnitName = _G.UnitName
    _G.UnitExists = function() return false end
    _G.UnitName = function(unit)
        return nil
    end

    DreamFisher.fishing.ConfigureFishingClickAction()
    local firstMacro = capturedAttrs["macrotext"] or ""
    assertTrue(firstMacro:find("/targetexact", 1, true) ~= nil,
        "First hooked acquire click should use target acquisition macro")

    mockTime = mockTime + 0.5
    DreamFisher.fishing.ConfigureFishingClickAction()
    local secondMacro = capturedAttrs["macrotext"] or ""
    assertTrue(secondMacro:find("/targetexact", 1, true) ~= nil,
        "Acquire window should keep target acquisition macro when no unit exists")
    assertTrue(secondMacro:find("/interact", 1, true) == nil,
        "Acquire window should not switch to /interact before unit exists")

    _G.UnitExists = originalUnitExists
    _G.UnitName = originalUnitName
end

function tests.HookedSoftNameUsesAcquirePlusInteractMacro()
    local capturedAttrs = {}
    local fishingFrame = DreamFisher.fishing.CreateSecureFishingFrame()
    local origSet = fishingFrame.SetAttribute
    fishingFrame.SetAttribute = function(self, k, v)
        capturedAttrs[k] = v
        return origSet and origSet(self, k, v)
    end

    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
        easyStrike = true,
    })

    DreamFisher._test.SetSessionState(DreamFisher.fishing.SessionStates.CASTING, "test-hooked-soft-name")
    DreamFisher.state.fishingStartGraceUntil = mockTime - 1
    DreamFisher.state.interactAcquireExpiresAt = 0

    local originalUnitExists = _G.UnitExists
    local originalUnitName = _G.UnitName
    _G.UnitExists = function() return false end
    _G.UnitName = function(unit)
        if unit == "softinteract" then
            return "Fishing Bobber"
        end
        return nil
    end

    DreamFisher.fishing.ConfigureFishingClickAction()
    local firstMacro = capturedAttrs["macrotext"] or ""
    assertTrue(firstMacro:find("/targetexact", 1, true) ~= nil,
        "Soft-name-only hooked state should still include target acquisition")
    assertTrue(firstMacro:find("/interact", 1, true) ~= nil,
        "Soft-name-only hooked state should include /interact in same macro")

    _G.UnitExists = originalUnitExists
    _G.UnitName = originalUnitName
end

function tests.HotkeyPressInCombatReturnsTrue()
    -- HandleHotkeyPress returns true (consumed) even in combat
    DreamFisher._test.SetDB({
        castingModes = { castHotkey = true },
        buffItems = {},
        buffAuraByItem = {},
    })

    mockInCombat = true
    local result = DreamFisher.fishing.HandleHotkeyPress()
    assertTrue(result == true, "Hotkey press in combat should return true (consumed)")
end

function tests.HotkeyPressWhenDisabledReturnsFalse()
    -- HandleHotkeyPress returns false when hotkey mode is off
    DreamFisher._test.SetDB({
        castingModes = {
            doubleRightClick = true,
            singleRightClick = false,
            castHotkey = false,
        },
        buffItems = {},
        buffAuraByItem = {},
    })

    mockInCombat = false
    local result = DreamFisher.fishing.HandleHotkeyPress()
    assertFalse(result, "Hotkey press when disabled should return false")
end

function tests.HotkeyPressWhenEnabledOutOfCombatReturnsTrue()
    -- HandleHotkeyPress returns true when hotkey mode enabled and out of combat
    DreamFisher._test.SetDB({
        castingModes = {
            doubleRightClick = false,
            singleRightClick = false,
            castHotkey = true,
        },
        buffItems = {},
        buffAuraByItem = {},
    })

    mockInCombat = false
    local result = DreamFisher.fishing.HandleHotkeyPress()
    assertTrue(result == true, "Hotkey press when enabled should return true")
end

-- ============================================================================
-- Tests: Interaction with Buff State Changes
-- ============================================================================

function tests.DoubleClickAdaptsToDueBuff()
    -- If first click happens with no due buff, but buff becomes due by second click
    DreamFisher._test.SetDB({
        buffItems = { { itemID = 111 } },
        buffAuraByItem = {},
    })

    local originalFind = DreamFisher.buff.FindItemInBags
    DreamFisher.buff.FindItemInBags = function() return 0, 1 end

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

    DreamFisher.buff.FindItemInBags = originalFind
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
