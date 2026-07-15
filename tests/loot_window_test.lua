-- Unit tests for DreamFish loot-window behavior.
-- Run with: lua tests/loot_window_test.lua

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

local now = 100
local createdFrames = {}
local lootSlots = {}
local lootedSlots = {}
local closeLootCalls = 0
local cvars = {
    autoLootDefault = "0",
}

local function makeNoopFrame(name)
    local frame = {
        _name = name,
        _shown = false,
        _scripts = {},
        _events = {},
    }

    function frame:SetAllPoints() end
    function frame:SetFrameStrata() end
    function frame:SetClampedToScreen() end
    function frame:SetAttribute() end
    function frame:GetAttribute() return nil end
    function frame:RegisterForClicks() end
    function frame:Hide() self._shown = false end
    function frame:Show() self._shown = true end
    function frame:IsShown() return self._shown end
    function frame:HookScript() end
    function frame:RegisterEvent(event) self._events[event] = true end
    function frame:UnregisterEvent(event) self._events[event] = nil end
    function frame:SetScript(kind, fn) self._scripts[kind] = fn end
    function frame:GetScript(kind) return self._scripts[kind] end
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:SetMovable() end
    function frame:EnableMouse() end
    function frame:RegisterForDrag() end
    function frame:SetAutoFocus() end
    function frame:SetText() end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor() end
    function frame:CreateTexture()
        return {
            SetAllPoints = function() end,
            SetColorTexture = function() end,
            SetSize = function() end,
            SetPoint = function() end,
            SetTexture = function() end,
        }
    end
    function frame:CreateFontString()
        return {
            SetPoint = function() end,
            SetText = function() end,
            SetTextColor = function() end,
        }
    end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:GetName() return self._name or "Frame" end

    frame.Text = { SetText = function() end, SetTextColor = function() end }
    frame.GetChecked = function() return true end
    frame.SetChecked = function() end
    frame.GetText = function() return "10" end

    return frame
end

local function setLootSlots(newLootSlots)
    lootSlots = newLootSlots or {}
    lootedSlots = {}
    closeLootCalls = 0
end

_G.CreateFrame = function(_, name)
    local frame = makeNoopFrame(name)
    table.insert(createdFrames, frame)
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
_G.C_UnitAuras = nil
_G.AuraUtil = nil
_G.C_Timer = nil
_G.InCombatLockdown = function() return false end
_G.ClearOverrideBindings = function() end
_G.SetOverrideBindingClick = function() end
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.GetTime = function() return now end
_G.PlaySound = function() end
_G.SOUNDKIT = {}
_G.GetSpellInfo = function() return "Fishing" end
_G.GetContainerNumSlots = function() return 0 end
_G.GetContainerItemID = function() return nil end
_G.GetCVar = function(name)
    return cvars[name]
end
_G.SetCVar = function(name, value)
    cvars[name] = tostring(value)
end
_G.strtrim = function(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
_G.PlayerHasToy = function() return true end
_G.GetNumLootItems = function()
    return #lootSlots
end
_G.GetLootSlotInfo = function(slot)
    local item = lootSlots[slot]
    if not item then
        return nil
    end
    return nil, item.name, item.count or 1, item.quality
end
_G.LootSlot = function(slot)
    table.insert(lootedSlots, slot)
    return true
end
_G.CloseLoot = function()
    closeLootCalls = closeLootCalls + 1
end

-- Load addon modules.
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
assertEquals(type(addon), "table", "Addon table should exist")
assertEquals(type(addon._test), "table", "Test hooks should exist")

local function findFrameWithEvent(eventName)
    for _, frame in ipairs(createdFrames) do
        if frame._events and frame._events[eventName] and frame._scripts and frame._scripts["OnEvent"] then
            return frame
        end
    end
    return nil
end

local function fireEventToRegisteredFrames(eventName, ...)
    for _, frame in ipairs(createdFrames) do
        if frame._events and frame._events[eventName] and frame._scripts and type(frame._scripts["OnEvent"]) == "function" then
            frame._scripts["OnEvent"](frame, eventName, ...)
        end
    end
end

local rootFrame = nil
for _, frame in ipairs(createdFrames) do
    if frame.GetName and frame:GetName() == "DreamFishFrame" and frame.GetScript and type(frame:GetScript("OnEvent")) == "function" then
        rootFrame = frame
    end
end
assertTrue(rootFrame ~= nil, "Root addon frame should exist")
rootFrame:GetScript("OnEvent")(rootFrame, "ADDON_LOADED", "DreamFish")

local stateFrame = addon._test.GetFishingStateFrame()
assertTrue(stateFrame ~= nil, "Fishing state frame should exist")
assertTrue(type(stateFrame:GetScript("OnEvent")) == "function", "Fishing state OnEvent should exist")

local lootFrame = findFrameWithEvent("LOOT_READY")
assertTrue(lootFrame ~= nil, "Loot tracker frame should exist")
local lootOnEvent = lootFrame:GetScript("OnEvent")
assertTrue(type(lootOnEvent) == "function", "Loot tracker OnEvent should exist")

local function startFishingSession()
    addon._test.SetDB({ managedLoot = true, throwAwayJunk = false })
    addon._test.ResetAutoLootState()
    now = 100
    fireEventToRegisteredFrames("UNIT_SPELLCAST_START", "player", nil, addon.const.fishingSpellID)
    now = 101
    fireEventToRegisteredFrames("UNIT_SPELLCAST_STOP", "player", nil, addon.const.fishingSpellID)
    assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.WAITING_FOR_STRIKE,
        "Fishing cast should enter WAITING_FOR_STRIKE before loot")
end

-- Case 1: Accept all loot and close the window.
setLootSlots({
    [1] = { name = "Mossy Coin", count = 1, quality = 2 },
    [2] = { name = "Rusty Boots", count = 1, quality = 0 },
})
startFishingSession()
lootOnEvent(lootFrame, "LOOT_READY")
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.LOOTING,
    "LOOT_READY should move to LOOTING")
assertEquals(#lootedSlots, 2, "Should loot every slot when throw-away junk is disabled")
assertEquals(lootedSlots[1], 1, "Should loot slot 1 first")
assertEquals(lootedSlots[2], 2, "Should loot slot 2 second")
assertEquals(closeLootCalls, 1, "Should close the loot window after looting everything")
lootOnEvent(lootFrame, "LOOT_CLOSED")
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.IDLE,
    "LOOT_CLOSED should return the session to IDLE")

-- Case 2: Skip junk items and leave the window open.
setLootSlots({
    [1] = { name = "Silver Scale", count = 1, quality = 2 },
    [2] = { name = "Broken Tackle", count = 1, quality = 0 },
    [3] = { name = "Old Boot", count = 1, quality = 0 },
})
addon._test.SetDB({ managedLoot = true, throwAwayJunk = true })
addon._test.ResetAutoLootState()
now = 200
fireEventToRegisteredFrames("UNIT_SPELLCAST_START", "player", nil, addon.const.fishingSpellID)
now = 201
fireEventToRegisteredFrames("UNIT_SPELLCAST_STOP", "player", nil, addon.const.fishingSpellID)
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.WAITING_FOR_STRIKE,
    "Fishing cast should enter WAITING_FOR_STRIKE before junk-skipping loot")
lootOnEvent(lootFrame, "LOOT_READY")
assertEquals(addon.state.fishingSessionState, addon.fishing.SessionStates.LOOTING,
    "LOOT_READY should move to LOOTING when junk is present")
assertEquals(#lootedSlots, 1, "Should only loot non-junk items when throw-away junk is enabled")
assertEquals(lootedSlots[1], 1, "Should loot the non-junk slot")
assertEquals(closeLootCalls, 0, "Should leave the loot window open when junk is skipped")

-- Case 3: Junk-only windows should also stay open.
setLootSlots({
    [1] = { name = "Torn Fin", count = 1, quality = 0 },
})
addon._test.SetDB({ managedLoot = true, throwAwayJunk = true })
addon._test.ResetAutoLootState()
now = 300
fireEventToRegisteredFrames("UNIT_SPELLCAST_START", "player", nil, addon.const.fishingSpellID)
now = 301
fireEventToRegisteredFrames("UNIT_SPELLCAST_STOP", "player", nil, addon.const.fishingSpellID)
lootOnEvent(lootFrame, "LOOT_READY")
assertEquals(#lootedSlots, 0, "Should not loot junk-only windows when throw-away junk is enabled")
assertEquals(closeLootCalls, 0, "Should keep junk-only windows open")

print("PASS: loot_window_test")
