-- Unit tests for DreamFisher treasure alert behavior.
-- Run with: lua tests/treasure_alert_test.lua

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

local createdFrames = {}
local soundCalls = {}
local patientAuraActive = false

local function makeFontString()
    local fs = {
        text = "",
    }
    function fs:SetPoint() end
    function fs:SetTextColor() end
    function fs:SetText(text)
        self.text = text
    end
    return fs
end

local function makeTexture()
    local tx = {
        texture = nil,
    }
    function tx:SetAllPoints() end
    function tx:SetColorTexture() end
    function tx:SetSize() end
    function tx:SetPoint() end
    function tx:SetTexture(texture)
        self.texture = texture
    end
    return tx
end

local function makeFrame(name)
    local frame = {
        _name = name,
        _shown = false,
        _scripts = {},
    }

    function frame:SetAllPoints() end
    function frame:SetFrameStrata() end
    function frame:EnableMouse() end
    function frame:Hide() self._shown = false end
    function frame:Show() self._shown = true end
    function frame:IsShown() return self._shown end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor() end
    function frame:CreateTexture() return makeTexture() end
    function frame:CreateFontString() return makeFontString() end
    function frame:SetScript(kind, fn) self._scripts[kind] = fn end
    function frame:GetScript(kind) return self._scripts[kind] end
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetMovable() end
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:EnableMouse() end
    function frame:RegisterForDrag() end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:RegisterForClicks() end
    function frame:SetAttribute() end
    function frame:HookScript() end
    function frame:GetName() return self._name or "Frame" end

    frame.Text = {
        SetText = function() end,
        SetTextColor = function() end,
    }
    frame.GetChecked = function() return true end
    frame.GetText = function() return "10" end

    return frame
end

_G.CreateFrame = function(_, name)
    local frame = makeFrame(name)
    table.insert(createdFrames, frame)
    return frame
end

_G.UIParent = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.WorldFrame = nil
_G.SlashCmdList = {}
_G.SLASH_DREAMFISHER1 = nil
_G.SLASH_DREAMFISHER2 = nil
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
_G.GetSpellTexture = function() return "Interface\\Icons\\INV_Misc_TreasureChest03a" end
_G.GetContainerNumSlots = function() return 0 end
_G.GetContainerItemID = function() return nil end
_G.GetCVar = function() return "0" end
_G.SetCVar = function() end
_G.strtrim = function(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

_G.SOUNDKIT = {
    READY_CHECK = 1,
    RAID_WARNING = 2,
}

_G.PlaySound = function(sound, channel)
    table.insert(soundCalls, { sound = sound, channel = channel })
end

_G.C_Timer = {
    After = function(_, fn)
        fn()
    end,
}

_G.DreamFisherDB = {}

-- Load addon.
dofile("core/init.lua")
dofile("core/utils.lua")
dofile("core/module_api.lua")
dofile("core/api_resolver.lua")
dofile("buff/tracking.lua")
dofile("fishing/casting.lua")
dofile("fishing/state.lua")
dofile("audio/ducking.lua")
dofile("audio/alerts.lua")
dofile("DreamFisher.lua")

local addon = _G.DreamFisher
assertEquals(type(addon), "table", "Addon should load")

-- Fire ADDON_LOADED for this addon so slash commands are registered.
local rootFrame = nil
for _, frame in ipairs(createdFrames) do
    local onEventScript = frame.GetScript and frame:GetScript("OnEvent")
    if frame.GetName and frame:GetName() == "DreamFisherFrame" and type(onEventScript) == "function" then
        rootFrame = frame
    end
end
if not rootFrame then
    rootFrame = createdFrames[#createdFrames]
end
local onEvent = rootFrame and rootFrame:GetScript("OnEvent")
assertTrue(type(onEvent) == "function", "Root OnEvent should exist")
onEvent(rootFrame, "ADDON_LOADED", "DreamFisher")

-- Find aura tracker frame and simulate Patiently Rewarded aura gain.
_G.C_UnitAuras = {
    GetPlayerAuraBySpellID = function(spellID)
        if spellID == 1235378 and patientAuraActive then
            return { spellId = 1235378 }
        end
        return nil
    end,
}

patientAuraActive = true

for _, frame in ipairs(createdFrames) do
    local onEventScript = frame:GetScript("OnEvent")
    if type(onEventScript) == "function" then
        pcall(onEventScript, frame, "UNIT_AURA", "player")
    end
end

-- Find treasure alert frame by name.
local alertFrame = nil
for _, frame in ipairs(createdFrames) do
    if frame:GetName() == "DreamFisherTreasureAlertFrame" then
        alertFrame = frame
        break
    end
end

assertTrue(alertFrame ~= nil, "Treasure alert frame should be created")
assertTrue(alertFrame:IsShown(), "Treasure alert frame should be shown")
assertTrue(#soundCalls >= 2, "Treasure alert should play a multi-step sound sequence")
assertEquals(soundCalls[1].channel, "Master", "Treasure sound should play on Master channel")

print("PASS: treasure_alert_test")
