local addonName, ns = ...
local Fishing = ns.Fishing or LibStub("AceAddon-3.0"):GetAddon("DreamFish"):GetModule("Fishing")

-- Initialize a dedicated sub-namespace for our bar to keep globals clean
ns.InitBar = {}

-- 1. Create the Custom Visual Castbar UI Frame Elements
local bar = CreateFrame("StatusBar", "DreamFishInitCastbar", UIParent, "BackdropTemplate")
bar:SetSize(200, 18)
bar:SetPoint("CENTER", UIParent, "CENTER", 0, -100) -- Renders where standard game castbars sit
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
bar.text:SetText("Initializing Fishing...")
bar.text:SetTextColor(1, 1, 1, 1)

-- 2. Internal Animation Function to Smoothly Fill the Frame
local function AnimateCastbar(duration, completionCallback)
    bar:SetValue(0)
    bar:Show()

    local startTime = GetTime()
    bar:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - startTime
        local progress = elapsed / duration
        if elapsed >= duration then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            if type(completionCallback) == "function" then
                completionCallback()
            end
        else
            self:SetValue(progress)
        end
    end)
end

-- 3. Core Encapsulated Logic Entrypoint API
function ns.InitBar.StartDelayedCastSequence(moduleObj, poleDecisionItemID)
    if InCombatLockdown() or not moduleObj.clickFrame then return false end

    moduleObj:Trace("precast", "[InitBar] Initializing session swap: compiling unified multi-line sequence.")

    -- 1. Flag the active pole swap status
    moduleObj.state.isEquippingPrimaryPole = true

    -- 2. Build a clean, multi-line macro that swaps tools and fires the cast bar on a single pass!
    local lines = {
        "/equip item:" .. tostring(poleDecisionItemID),
        "/cast [nochanneling] Fishing"
    }

    -- 3. Directly commit the values onto your secure intercept button
    moduleObj.clickFrame:SetAttribute("type", "macro")
    moduleObj.clickFrame:SetAttribute("macrotext", table.concat(lines, "\n"))
    moduleObj.clickFrame:SetAttribute("spell", nil)

    moduleObj:Trace("precast", "[InitBar] Setup complete: gear-swap macro safely compiled.")
    return true
end
