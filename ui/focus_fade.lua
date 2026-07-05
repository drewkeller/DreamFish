-- DreamFisher: Focus frame fading while fishing

local addon = _G["DreamFisher"]

local panelNamesToFade = {
    "Minimap",
    "ObjectiveTrackerFrame",
    "ChatFrame1",
    "PlayerFrame",
    "TargetFrame",
    "MainMenuBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarLeft",
    "MultiBarRight",
    "MicroButtonAndBagsBar",
    "ObjectiveTrackerFrame"
}

local frameFader = {
    frame = nil,
    isFaded = false,
    wasShownByName = {},
    restoreAt = nil,
}





local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
local currentFishingState = nil

-- 1. Establish global variables to track active modules
local isElvUIActive = false

local function ToggleElvUIStanceBar(hideBar)
    if isElvUIActive and _G["ElvUI"] then
        -- --- ELVUI ACTIVE ROUTINE ---
        local E = unpack(_G["ElvUI"])
        local AB = E:GetModule('ActionBars', true)

        if AB and E.db and E.db.actionbar and E.db.actionbar.stanceBar then
            -- 1. Modify ElvUI's internal stance bar database visibility switch
            -- If hideBar is true, set enable to false; otherwise, restore to true
            E.db.actionbar.stanceBar.enable = not hideBar

            -- 2. Safely tell the ActionBar module to completely re-initialize the bar
            if type(AB.PositionAndSizeBarStance) == "function" then
                AB:PositionAndSizeBarStance()
            end
        end

        -- Fallback Brute Force: Target the literal secure frame wrapper directly
        local stanceFrame = _G["ElvUI_StanceBar"]
        if stanceFrame then
            local targetAlpha = hideBar and 0.0 or 1.0
            stanceFrame:SetAlpha(targetAlpha)

            -- Temporarily hook SetAlpha so ElvUI's engine can't draw it back while fishing
            if hideBar then
                if not stanceFrame.SetAlpha_Old then
                    stanceFrame.SetAlpha_Old = stanceFrame.SetAlpha
                    stanceFrame.SetAlpha = function() end
                end
            else
                if stanceFrame.SetAlpha_Old then
                    stanceFrame.SetAlpha = stanceFrame.SetAlpha_Old
                    stanceFrame.SetAlpha_Old = nil
                end
                stanceFrame:SetAlpha(1)
            end
        end
    else
        -- --- DEFAULT BLIZZARD STANCE BAR FALLBACK ---
        -- Targets the default Blizzard stance/shapeshift bar container safely
        local blizzStance = _G["StanceBar"] or _G["StanceBarFrame"]
        if blizzStance and blizzStance.SetAlpha then
            blizzStance:SetAlpha(hideBar and 0.0 or 1.0)
        end
    end
end

local function TogglePlayerAurasVisibility(hideAuras)
    local targetAlpha = hideAuras and 0.0 or 1.0

    if isElvUIActive and _G["ElvUI"] then
        -- --- ELVUI ACTIVE ROUTINE ---
        local E = unpack(_G["ElvUI"])
        local A = E:GetModule('Auras', true)

        -- ElvUI places headers for player buffs and debuffs globally
        local elvBuffs = _G["ElvUF_PlayerBuffs"]
        local elvDebuffs = _G["ElvUF_PlayerDebuffs"]

        -- Method A: If using ElvUI's standalone Aura module
        if elvBuffs or elvDebuffs then
            for _, frame in ipairs({elvBuffs, elvDebuffs}) do
                if frame then
                    frame:SetAlpha(targetAlpha)
                    -- Protect the transparency from ElvUI's layout update engine
                    if hideAuras then
                        if not frame.SetAlpha_Old then
                            frame.SetAlpha_Old = frame.SetAlpha
                            frame.SetAlpha = function() end
                        end
                    else
                        if frame.SetAlpha_Old then
                            frame.SetAlpha = frame.SetAlpha_Old
                            frame.SetAlpha_Old = nil
                        end
                        frame:SetAlpha(1)
                    end
                end
            end
        end

        -- Method B: If they use ElvUI Unitframe-attached Auras (built into the player frame)
        local elvPlayer = _G["ElvUF_Player"]
        if elvPlayer then
            if elvPlayer.Buffs then elvPlayer.Buffs:SetAlpha(targetAlpha) end
            if elvPlayer.Debuffs then elvPlayer.Debuffs:SetAlpha(targetAlpha) end
            if elvPlayer.Auras then elvPlayer.Auras:SetAlpha(targetAlpha) end
        end

    else
        -- --- DEFAULT BLIZZARD UI ROUTINE ---
        -- Target modern and classic Blizzard Buff/Debiff containers safely
        local blizzContainers = {
            "BuffFrame",
            "DebuffFrame",
            "DeadlyDebuffFrame",
            "UIWidgetTopCenterContainerFrame"
        }

        for _, frameName in ipairs(blizzContainers) do
            local frameObj = _G[frameName]
            if frameObj and frameObj.SetAlpha then
                frameObj:SetAlpha(targetAlpha)
            end
        end
    end
end

-- 3. Core function to alter element opacity safely
local function ApplyElvUIFade(isFishing)
    if currentFishingState == isFishing then
        return
    end
    currentFishingState = isFishing

    local targetAlpha = isFishing and 0.0 or 1.0 -- 0.0 hides completely, 1.0 restores fully

    TogglePlayerAurasVisibility(isFishing)
    ToggleElvUIStanceBar(isFishing)

    -- --- FORCE ACTION BARS OVERRIDE ---
    -- Loop through ElvUI's structural bar frames and strip their alpha completely.
    -- This prevents ElvUI's GlobalFadeManager from forcing them visible mid-cast.
    for i = 1, 15 do
        local bar = _G["ElvUI_Bar"..i]
        if bar then
            if isFishing then
                bar:SetAlpha(0)
                -- Temporarily block ElvUI from changing this specific bar's alpha
                bar.SetAlpha_Old = bar.SetAlpha
                bar.SetAlpha = function() end
            else
                -- Restore normal ElvUI execution when done fishing
                if bar.SetAlpha_Old then
                    bar.SetAlpha = bar.SetAlpha_Old
                    bar.SetAlpha_Old = nil
                end
                bar:SetAlpha(1)
            end
        end
    end

    if isElvUIActive and _G["ElvUI"] then
        -- --- ELVUI ACTIVE ROUTINE ---
        local E = unpack(_G["ElvUI"])

        if E.db and E.db.actionbar then
            E.db.actionbar.globalFadeAlpha = targetAlpha
            local AB = E:GetModule('ActionBars', true)
            if AB then
                if type(AB.UpdateBarFade) == "function" then
                    AB:UpdateBarFade()
                end
            end
        end

        -- 2. Modern & Safe alternative for Unit Frame Global Fade
        -- Instead of indexing .general, we talk straight to ElvUI's fader system
        local FM = E:GetModule('GlobalFadeManager', true)
        if FM then
            -- Force ElvUI to manually recalculate or hold fading states
            FM:SetGlobalFadeAlpha(targetAlpha) -- Hides them
        end

        local UF = E:GetModule('UnitFrames', true)
        if UF then
            -- Locate ElvUI's secure player frame wrapper
            local elvPlayer = _G["ElvUF_Player"]
            if elvPlayer then
                if isFishing then
                    elvPlayer:SetAlpha(0)
                    -- Temporarily hook SetAlpha so ElvUI can't override it while fishing
                    if not elvPlayer.SetAlpha_Old then
                        elvPlayer.SetAlpha_Old = elvPlayer.SetAlpha
                        elvPlayer.SetAlpha = function() end
                    end
                else
                    -- Restore normal ElvUI control when done fishing
                    if elvPlayer.SetAlpha_Old then
                        elvPlayer.SetAlpha = elvPlayer.SetAlpha_Old
                        elvPlayer.SetAlpha_Old = nil
                    end
                    elvPlayer:SetAlpha(1)
                end
            end
        end

        local DB = E:GetModule('DataBars', true)
        if DB and E.db and E.db.databars then
            -- List of all ElvUI data bar names in the database
            local barTypes = { "experience", "reputation", "honor", "azerite", "threat" }
            local hideBars = isFishing

            for _, barName in ipairs(barTypes) do
                if E.db.databars[barName] then
                    -- If hiding, set enable to false; otherwise, restore to true
                    E.db.databars[barName].enable = not hideBars

                    -- Safely refresh the individual bar layout using ElvUI's internal API
                    local barMethodName = "Update" .. barName:gsub("^%l", string.upper) .. "Dimensions"
                    if type(DB[barMethodName]) == "function" then
                        DB[barMethodName](DB)
                    end
                end
            end

            -- Force a top-level master redraw of the entire module framework
            if type(DB.UpdateAll) == "function" then
                DB:UpdateAll()
            end
        end


        -- Handle ElvUI Chat Panels
        if _G["LeftChatPanel"] then _G["LeftChatPanel"]:SetAlpha(targetAlpha) end
        if _G["RightChatPanel"] then _G["RightChatPanel"]:SetAlpha(targetAlpha) end

    else
        -- Fallback: If ElvUI is active but they disabled the Unitframes module
        local blizzPlayer = _G["PlayerFrame"] or _G["CompactPlayerFrame"]
        if blizzPlayer then blizzPlayer:SetAlpha(targetAlpha) end

        -- Targets default Blizzard status bars (like StatusTrackingBarManager)
        if _G["StatusTrackingBarManager"] then
            _G["StatusTrackingBarManager"]:SetAlpha(targetAlpha)
        end
    end
end

-- 5. Main initialization and event loop
loader:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Detect if ElvUI module exists and is enabled by the user
        if C_AddOns.IsAddOnLoaded("ElvUI") and _G["ElvUI"] then
            isElvUIActive = true
        end
    end
end)




local function ResolveNamedFrame(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return _G[name]
end

local function IsFishingSessionActive()
    if not addon or not addon.state then
        return false
    end

    return (addon.state.isFishing or addon.state.isBobberActive or addon.state.fishingLootInProgress) and true or false
end

local function IsFadeFeatureEnabled()
    if not addon or not addon.db then
        return false
    end
    return addon.db.focusedVisuals and true or false
end

local function GetVisualsLingerSeconds()
    local defaults = addon and addon.defaults or nil
    local linger = (addon and addon.db and addon.db.focusedVisualsLinger) or (defaults and defaults.focusedVisualsLinger) or 0
    return math.max(0, tonumber(linger) or 0)
end

local function FadeOutUI()
    ApplyElvUIFade(true)  -- Fade out ElvUI elements
    frameFader.restoreAt = nil
    for _, name in ipairs(panelNamesToFade) do
        local panel = ResolveNamedFrame(name)
        if panel and panel.IsShown and panel:IsShown() then
            frameFader.wasShownByName[name] = true
            if type(UIFrameFadeOut) == "function" and panel.GetAlpha then
                UIFrameFadeOut(panel, 0.5, panel:GetAlpha() or 1, 0)
            elseif panel.SetAlpha then
                panel:SetAlpha(0)
            end
        else
            frameFader.wasShownByName[name] = false
        end
    end
    frameFader.isFaded = true
end

local function FadeInUI()
    ApplyElvUIFade(false)
    for _, name in ipairs(panelNamesToFade) do
        local panel = ResolveNamedFrame(name)
        if panel and panel.SetAlpha then
            local wasShown = frameFader.wasShownByName[name]
            if wasShown then
                if type(UIFrameFadeIn) == "function" and panel.GetAlpha then
                    UIFrameFadeIn(panel, 0.3, panel:GetAlpha() or 0, 1)
                else
                    panel:SetAlpha(1)
                end
            else
                panel:SetAlpha(1)
            end
        end
    end
    frameFader.wasShownByName = {}
    frameFader.isFaded = false
    frameFader.restoreAt = nil
end

local function ScheduleFadeInUI()
    local lingerSeconds = GetVisualsLingerSeconds()
    if lingerSeconds <= 0 then
        FadeInUI()
        return
    end

    if type(GetTime) ~= "function" then
        FadeInUI()
        return
    end

    frameFader.restoreAt = GetTime() + lingerSeconds
end

local function RefreshFocusFadeState()
    local shouldFade = IsFadeFeatureEnabled() and IsFishingSessionActive()

    if shouldFade and not frameFader.isFaded then
        FadeOutUI()
    elseif not shouldFade and frameFader.isFaded then
        if not IsFadeFeatureEnabled() then
            FadeInUI()
            return
        end

        if frameFader.restoreAt == nil then
            ScheduleFadeInUI()
            return
        end

        if type(GetTime) ~= "function" or GetTime() >= frameFader.restoreAt then
            FadeInUI()
        end
    elseif shouldFade and frameFader.restoreAt ~= nil then
        frameFader.restoreAt = nil
    end
end

local function CreateFocusFadeFrame()
    if frameFader.frame then
        return frameFader.frame
    end

    local frame = CreateFrame("Frame")
    local elapsedSinceRefresh = 0

    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            RefreshFocusFadeState()
        end
    end)

    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceRefresh = elapsedSinceRefresh + (tonumber(elapsed) or 0)
        if elapsedSinceRefresh < 0.20 then
            return
        end
        elapsedSinceRefresh = 0
        RefreshFocusFadeState()
    end)

    frameFader.frame = frame
    return frame
end

addon.uiFocus = addon.uiFocus or {}
addon.uiFocus.CreateFocusFadeFrame = CreateFocusFadeFrame
addon.uiFocus.RefreshFocusFadeState = RefreshFocusFadeState
addon.uiFocus.FadeOutUI = FadeOutUI
addon.uiFocus.FadeInUI = FadeInUI
addon._test = addon._test or {}
addon._test.GetFocusFadeRestoreAt = function()
    return frameFader.restoreAt
end
