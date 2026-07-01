-- Unit tests for DreamFisher auto-loot behavior.
-- Run with: lua tests/autoloot_test.lua

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEquals failed") .. " | expected=" .. tostring(expected) .. " actual=" .. tostring(actual), 2)
    end
end

local cvars = {
    autoLootDefault = "0",
}

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

_G.CreateFrame = function()
    local frame = makeNoopFrame()
    frame.Text = { SetText = function() end, SetTextColor = function() end }
    frame.GetChecked = function() return true end
    frame.GetText = function() return "2" end
    return frame
end

_G.UIParent = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
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
_G.GetTime = function() return 100 end
_G.PlaySound = function() end
_G.SOUNDKIT = {}
_G.GetContainerNumSlots = function() return 0 end
_G.GetContainerItemID = function() return nil end
_G.GetCVar = function(name)
    return cvars[name]
end
_G.SetCVar = function(name, value)
    cvars[name] = tostring(value)
end
_G.PlayerHasToy = function() return true end

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
dofile("ui/ace_widget_factory.lua")
dofile("ui/buff_item_drop_box.lua")
dofile("ui/config.lua")

-- Load addon file in this mocked environment.
dofile("DreamFisher.lua")

local addon = _G.DreamFisher
assertEquals(type(addon), "table", "Addon table should exist")
assertEquals(type(addon._test), "table", "Test hooks should exist")

local function resetState(autoLootSetting, userAutoLoot)
    addon._test.ResetAutoLootState()
    addon._test.SetDB({ autoLoot = autoLootSetting })
    cvars.autoLootDefault = tostring(userAutoLoot)
end

-- Case 1: Addon setting enabled and user has auto-loot OFF -> force ON, then restore OFF.
resetState(true, "0")
addon._test.EnableTemporaryAutoLoot()
assertEquals(cvars.autoLootDefault, "1", "Should force auto-loot on while fishing")
addon._test.RestoreOriginalAutoLoot()
assertEquals(cvars.autoLootDefault, "0", "Should restore original auto-loot setting")

-- Case 2: Addon setting enabled and user already has auto-loot ON -> stays ON after restore.
resetState(true, "1")
addon._test.EnableTemporaryAutoLoot()
assertEquals(cvars.autoLootDefault, "1", "Should keep auto-loot on")
addon._test.RestoreOriginalAutoLoot()
assertEquals(cvars.autoLootDefault, "1", "Should restore to original on state")

-- Case 3: Addon setting disabled -> should not modify user CVar.
resetState(false, "0")
addon._test.EnableTemporaryAutoLoot()
assertEquals(cvars.autoLootDefault, "0", "Should not change CVar when addon auto-loot is disabled")
addon._test.RestoreOriginalAutoLoot()
assertEquals(cvars.autoLootDefault, "0", "Restore should be a no-op when addon auto-loot is disabled")

print("PASS: autoloot_test")
