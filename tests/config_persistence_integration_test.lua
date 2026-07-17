-- Integration tests for DreamFish config persistence flows.
-- Run with: lua tests/config_persistence_integration_test.lua

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

local makeNoopFrame = dofile("tests/mocks/noop_frame.lua").makeNoopFrame

_G.CreateFrame = function(_, name)
    return makeNoopFrame(name)
end

_G.UIParent = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.WorldFrame = nil
_G.SLASH_DREAMFISHER1 = nil
_G.SLASH_DREAMFISHER2 = nil
_G.SlashCmdList = {}
_G.UISpecialFrames = {}
_G.NUM_BAG_SLOTS = 4
_G.C_Container = nil
_G.C_UnitAuras = nil
_G.AuraUtil = nil
_G.InCombatLockdown = function() return false end
_G.ClearOverrideBindings = function() end
_G.SetOverrideBindingClick = function() end
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.GetTime = function() return 100 end
_G.PlaySound = function() end
_G.SOUNDKIT = {}
_G.GetSpellInfo = function() return "Fishing" end
_G.GetContainerNumSlots = function() return 0 end
_G.GetContainerItemID = function() return nil end
_G.GetCVar = function() return "0" end
_G.SetCVar = function() end
_G.GetInventoryItemID = function() return nil end
_G.GetItemInfoInstant = function() return nil, nil, nil, nil, nil, nil, nil end
_G.GetItemInfo = function() return "Test Item" end
_G.PlayerHasToy = function() return true end
_G.C_Timer = nil
_G.strtrim = function(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Mirror production-ish load order used in tests.
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
dofile("DreamFish.lua")

local addon = _G.DreamFish
assertTrue(type(addon) == "table", "Addon table should exist")
assertTrue(type(addon.config) == "table", "Config module should exist")
assertTrue(type(addon.config.SaveConfig) == "function", "SaveConfig should exist")

addon._test.SetDB({
    autoLoot = true,
    focusedVisuals = true,
    focusedAudio = false,
    focusedAudioLinger = 10,
    focusedVisualsLinger = 10,
    bagAlerts = true,
    bagAlertsThreshold = 2,
    reagentBagAlerts = true,
    reagentBagAlertsThreshold = 2,
    managedLoot = true,
    treasureAlerts = true,
    easyStrike = false,
    closeWindowOnEscape = true,
    buffItems = {
        { enabled = true, itemID = 11111 },
        { enabled = true, itemID = 22222 },
    },
    selectedFishingPole = { isChecked = false, itemID = nil },
    selectedUnderlightAngler = { isChecked = false, itemID = nil },
    castingModes = {
        doubleRightClick = false,
        singleRightClick = false,
        castHotkey = false,
    },
})

-- Keep underlight considered available in this test scenario.
if addon.utils then
    addon.utils.CountItemInBags = function(itemID)
        if tonumber(itemID) == 133755 then
            return 1
        end
        return 0
    end
end

local fadeInCalls = 0
addon.uiFocus = addon.uiFocus or {}
addon.uiFocus.FadeInUI = function()
    fadeInCalls = fadeInCalls + 1
end

local restoreAfterLingerCalls = 0
addon.audio = addon.audio or {}
addon.audio.RestoreFishingAudioFocusAfterLinger = function()
    restoreAfterLingerCalls = restoreAfterLingerCalls + 1
end

-- Simulate active delayed restore so SaveConfig triggers audio finalize path.
addon.state.savedFishingAudioCVars = { ambience = "0.3", music = "0.3", dialog = "0.3" }
addon.state.audioRestoreAt = 105

-- Focus controls
addon.bagAlertsThresholdBox = { GetText = function() return "7" end }
addon.reagentBagAlertsThresholdBox = { GetText = function() return "4" end }
addon.audioLingerBox = { GetText = function() return "12" end }
addon.autoLootCheckbox = { GetChecked = function() return true end }
addon.managedLootCheckbox = { GetChecked = function() return false end }
addon.lootDelayBox = { GetText = function() return "750" end }
addon.focusedAudioCheckbox = { GetChecked = function() return true end }
addon.focusedVisualsCheckbox = { GetChecked = function() return false end }
addon.focusedVisualsLingerBox = { GetText = function() return "9" end }
addon.treasureAlertsCheckbox = { GetChecked = function() return false end }
addon.bagAlertsCheckbox = { GetChecked = function() return true end }
addon.reagentBagAlertsCheckbox = { GetChecked = function() return false end }

-- Modes controls
addon.modeDoubleRightClickCheckbox = { GetChecked = function() return false end }
addon.modeSingleRightClickConfigCheckbox = { GetChecked = function() return true end }
addon.modeHotkeyCheckbox = { GetChecked = function() return true end }
addon.enableHookedLootCheckbox = { GetChecked = function() return true end }
addon.escapeCloseCheckbox = { GetChecked = function() return false end }

-- Tackle controls
addon.fishingPoleBox = { GetText = function() return "6256" end }
addon.fishingPoleEquipCheckbox = { GetChecked = function() return true end }
addon.underlightAnglerBox = { GetText = function() return "133755" end }
addon.underlightAnglerEquipCheckbox = { GetChecked = function() return true end }

-- Buff controls
addon.buffItemControls = {
    {
        itemBox = { GetText = function() return "44444" end },
        enabledCheckbox = { GetChecked = function() return false end },
        desiredEnabled = false,
    },
    {
        itemBox = { GetText = function() return "55555" end },
        enabledCheckbox = { GetChecked = function() return true end },
        desiredEnabled = true,
    },
}

addon.config.SaveConfig(true)

assertEquals(addon.db.bagAlertsThreshold, 7, "Bag alert threshold should persist from UI control")
assertEquals(addon.db.reagentBagAlertsThreshold, 4, "Reagent bag alert threshold should persist from UI control")
assertEquals(addon.db.focusedAudioLinger, 12, "Focused audio linger should persist from UI control")
assertEquals(addon.db.focusedVisualsLinger, 9, "Focused visuals linger should persist from UI control")
assertEquals(addon.db.autoLoot, true, "Native auto-loot checkbox should persist")
assertEquals(addon.db.managedLoot, false, "Auto-loot checkbox should persist")
assertEquals(addon.db.lootDelay, 0.75, "Loot delay milliseconds should persist as seconds")
assertEquals(addon.db.focusedAudio, true, "Focused audio checkbox should persist")
assertEquals(addon.db.focusedVisuals, false, "Focused visuals checkbox should persist")
assertEquals(addon.db.treasureAlerts, false, "Treasure alert checkbox should persist")
assertEquals(addon.db.bagAlerts, true, "Bag alerts checkbox should persist")
assertEquals(addon.db.reagentBagAlerts, false, "Reagent bag alerts checkbox should persist")

assertEquals(addon.db.castingModes.doubleRightClick, false, "Double-right-click mode should persist")
assertEquals(addon.db.castingModes.singleRightClick, true, "Single-right-click mode should persist")
assertEquals(addon.db.castingModes.castHotkey, true, "Cast-hotkey mode should persist")
assertEquals(addon.db.easyStrike, true, "EasyStrike checkbox should persist")
assertEquals(addon.db.closeWindowOnEscape, false, "Escape-close checkbox should persist")

assertEquals(addon.db.selectedFishingPole.itemID, 6256, "Fishing pole selection should persist")
assertEquals(addon.db.selectedFishingPole.isChecked, true, "Fishing pole enabled state should persist")
assertEquals(addon.db.selectedUnderlightAngler.itemID, 133755, "Underlight selection should persist")
assertEquals(addon.db.selectedUnderlightAngler.isChecked, true, "Underlight enabled state should persist")

assertEquals(addon.db.buffItems[1].itemID, 44444, "First buff slot item should persist")
assertEquals(addon.db.buffItems[1].enabled, false, "First buff slot enabled state should persist")
assertEquals(addon.db.buffItems[2].itemID, 55555, "Second buff slot item should persist")
assertEquals(addon.db.buffItems[2].enabled, true, "Second buff slot enabled state should persist")

assertEquals(fadeInCalls, 1, "Disabling focused visuals should trigger a single FadeInUI call")
assertEquals(restoreAfterLingerCalls, 1,
    "SaveConfig should trigger delayed audio restore completion when restore timer is active")

print("PASS: config_persistence_integration_test")
