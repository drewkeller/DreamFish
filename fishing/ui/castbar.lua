local addonName, ns = ...
local Fishing = ns.Fishing or LibStub("AceAddon-3.0"):GetAddon("DreamFish"):GetModule("Fishing")

ns.CastBar = {}

Fishing:RegisterTraceSource("castbar")

local function Trace(msg)
    Fishing:Trace("castbar", msg)
end

-- 1. Create the Custom Visual Castbar UI Frame Elements
local bar = CreateFrame("StatusBar", "DreamFishInitCastbar", UIParent, "BackdropTemplate")
bar:SetSize(200, 18)
bar:SetPoint("CENTER", UIParent, "CENTER", 0, -100) -- Renders where standard game castbars sit
bar:SetFrameStrata("DIALOG")
bar:SetMinMaxValues(0, 1)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(0.9, 0.8, 0.2, 1) -- Golden fishing theme color
bar:Hide()

-- Add a clean, lightweight backdrop border profile
bar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
})
bar:SetBackdropColor(0.05, 0.05, 0.05, 0.8)

-- Add a centered text label
bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
bar.text:SetText("Equipping fishing pole")
bar.text:SetTextColor(1, 1, 1, 1)

function ns.CastBar.ShowPoleSwap()
    bar:SetValue(1)
    bar:Show()
end

function ns.CastBar.HidePoleSwap()
    bar:Hide()
end

function Fishing:RemoveCastBar()
    ns.CastBar.HidePoleSwap()
end
