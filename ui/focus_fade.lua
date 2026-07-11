-- DreamFisher: Focus frame fading while fishing

local addon = _G["DreamFisher"]

local HIDDEN_ALPHA = 0.0001 -- Using 0 can cause issues with mouse events; use a very small number instead.
local VISIBLE_ALPHA = 1.0
local ALPHA_THRESHOLD = 0.25 -- Threshold to consider a frame effectively invisible
local FADE_IN_DURATION = 3.0
local FADE_OUT_DURATION = 3.0

-- Finding frame names can be done by using /fstack in the game.
-- 1. Turn on frame stack tool by typing /fstack in the game.
-- 2. Hover over the frame you want to identify.
-- 3. Note the frame name displayed by the frame stack tool (in the lighter colored text).
-- 4. Turn off frame stack tool by typing /fstack again in the game.
local panelNamesToFade = {
    -- Minimap
    "Minimap",
    "MinimapCluster",
    "ObjectiveTrackerFrame",
    "GameTimeFrame",             -- Calendar button
    "MiniMapMailFrame",          -- Mail icon
    "MiniMapTracking",           -- Tracking magnifying glass
    "QueueStatusButton",         -- LFG queue eye icon
    "QueueStatusMinimapButton",  -- Classic LFG queue icon
    "GarrisonLandingPageMinimapButton", -- Expansion/Mission tracking button
    "ExpansionLandingPageMinimapButton", -- Dragonflight/TWW expansion button
    -- Unit frames
    "PlayerFrame",
    "CompactPlayerFrame",
    "TargetFrame",
    "MainMenuBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarLeft",
    "MultiBarRight",
    "MicroButtonAndBagsBar",
    "ObjectiveTrackerFrame",
    -- Status bar frames (more?)
    "StatusTrackingBarManager",
    -- Buff/debuff frames
    "BuffFrame",
    "DebuffFrame",
    "DeadlyDebuffFrame",
    "UIWidgetTopCenterContainerFrame",
    -- Stance bar frames
    "StanceBar",
    "StanceBarFrame",
    "ElvUI_Bar1",
    "ElvUI_Bar2",
    "ElvUI_Bar3",
    "ElvUI_Bar4",
    "ElvUI_Bar5",
    "ElvUI_Bar6",
    "ElvUI_Bar7",
    "ElvUI_Bar8",
    "ElvUI_Bar9",
    "ElvUI_Bar10",
    "ElvUI_Bar13",
    "ElvUI_Bar14",
    "ElvUI_Bar15",
    "ElvUI_StanceBar",
    "ElvUI_PetBar",
    "ElvUI_MicroBar", -- maybe we don't want to hide this one?
    "ElvUF_Player_Castbar", -- We want to make sure this is shown
    -- Core unit frames
    --"ElvUF_Player", -- Need to handle specially, in order to keep fishing castbar visible
    "ElvUF_Target",
    "ElvUF_Pet",
    "ElvUF_Focus",
    "ElvUF_TargetTarget",
    -- Group/Boss frames
    "ElvUF_Party",
    "ElvUF_Raid",
    "ElvUF_Boss",
    "ElvUF_Arena",
    -- Chat/Info panels
    "ChatFrame1",    -- Chat frame text
    "LeftChatPanel", -- Chat frame background
    "ChatFrame2",
    "ChatFrame3",
    --"ChatFrame4",      -- Loot frame text
    --"RightChatPanel",  -- Loot frame background
    "LeftChatToggleButton",
    "RightChatToggleButton",
    "ElvUI_BottomPanel",
    "ElvUI_TopPanel",
    -- Buffs/Minimap/Data
    "ElvUI_PlayerBuffs",
    "ElvUI_PlayerDebuffs",
    "ElvUI_Minimap",
    --"ElvUI_LootFrame", --keep this for fishing
    -- Data bars (these are not official names, I'm just using them to normalize processing)
    "ElvDB_Experience",
    "ElvDB_Reputation",
    "ElvDB_Honor",
    "ElvDB_Azerite",
    "ElvDB_Threat",
    -- Data text panels
    "ElvUI_DataTextPanel_LeftChatDataPanelSlot1",
    "ElvUI_DataTextPanel_LeftChatDataPanelSlot2",
    "ElvUI_DataTextPanel_LeftChatDataPanelSlot3",
    "ElvUI_DataTextPanel_RightChatDataPanelSlot1",
    "ElvUI_DataTextPanel_RightChatDataPanelSlot2",
    "ElvUI_DataTextPanel_RightChatDataPanelSlot3",
    "ElvUI_DataTextPanel_MiniMapDataPanelSlot1",
    "ElvUI_DataTextPanel_MiniMapDataPanelSlot2",
    "ElvUI_DataTextPanel_MiniMapDataPanelSlot3",
    "AddonCompartmentFrame",
}

local frameFader = {
    frame = nil,
    isFading = nil,
    isFaded = false,
    cacheSuppressUntil = nil,
    wasShownByName = {},
    originalAlphaByName = {},
    restoreAt = nil,
}

-- array[frameName] = {wasShown = boolean, originalAlpha = number}
elvUIFrameFader = {}

-- Setup for ElvUI detection and event handling
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
local isElvUIActive = false

-- ElvUI: Detect
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

    if not (addon.fishing and addon.fishing.IsFishingActiveSessionState and addon.fishing.IsSessionState) then
        error("DreamFisher: IsFishingActiveSessionState and IsSessionState are required for focus fade state checks")
    end

    return addon.fishing.IsFishingActiveSessionState() or addon.fishing.IsSessionState("LOOTING")
end

local function IsPreCastingSessionState()
    if not addon or not addon.state then
        return false
    end

    if not (addon.fishing and addon.fishing.IsSessionState) then
        error("DreamFisher: IsSessionState is required for focus fade PRE_CASTING checks")
    end

    return addon.fishing.IsSessionState("PRE_CASTING")
end

local function IsFadeFeatureEnabled()
    if not addon or not addon.db then
        return false
    end
    return addon.db.focusedVisuals and true or false
end

local ForceVisibleFocusVisuals

local function ClearSetAlphaOverride(frame)
    if frame and frame.SetAlpha_Old then
        frame.SetAlpha = frame.SetAlpha_Old
        frame.SetAlpha_Old = nil
    end
end

local function GetVisualsLingerSeconds()
    local defaults = addon and addon.defaults or nil
    local linger = (addon and addon.db and addon.db.focusedVisualsLinger)
        or (defaults and defaults.focusedVisualsLinger)
        or 0
    return math.max(0, tonumber(linger) or 0)
end

local function HideMinimapButtons(hideButtons)
    local targetAlpha = hideButtons and HIDDEN_ALPHA or VISIBLE_ALPHA


    -- --- 2. HIDE THIRD-PARTY ADDON ICONS (LibDBIcon) ---
    -- Almost every addon (Details, WeakAuras, etc.) uses LibDBIcon-1.0 to attach buttons.
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if LibDBIcon and LibDBIcon.GetButtonList then
        for _, iconName in ipairs(LibDBIcon:GetButtonList()) do
            local buttonFrame = LibDBIcon:GetMinimapButton(iconName)
            if buttonFrame then
                buttonFrame:SetAlpha(targetAlpha)

                if hideButtons then
                    if not buttonFrame.SetAlpha_Old then
                        buttonFrame.SetAlpha_Old = buttonFrame.SetAlpha
                        buttonFrame.SetAlpha = function() end
                    end
                else
                    if buttonFrame.SetAlpha_Old then
                        buttonFrame.SetAlpha = buttonFrame.SetAlpha_Old
                        buttonFrame.SetAlpha_Old = nil
                    end
                    buttonFrame:SetAlpha(VISIBLE_ALPHA)
                end
            end
        end
    end
end

local function HideHandyNotesMapPins(hidePins)
    if C_AddOns.IsAddOnLoaded("HandyNotes") and _G["HandyNotes"] then
        local HandyNotes = LibStub("AceAddon-3.0"):GetAddon("HandyNotes", true)
        if HandyNotes and type(HandyNotes.SetEnabled) == "function" then
            -- Disabling/Enabling the module sweeps the pins away safely
            if hidePins then HandyNotes:Disable() else HandyNotes:Enable() end
        end
    end
end

local function HideGatherMateMinimap(hidePins)
    if _G["GatherMate2"] then
        -- Toggle database setting
        GatherMate2.db.profile.showMinimap = not hidePins

        -- Force update to apply changes
        local cfg = GatherMate2:GetModule("Config", true) or GatherMate2:GetModule("Display", true)
        if cfg and cfg.UpdateConfig then cfg:UpdateConfig()
        elseif cfg and cfg.UpdateMiniMap then cfg:UpdateMiniMap(true) end
    end
end

local function HideMinimapCluster(hideMiniMap)
    local minimapCluster = _G["MinimapCluster"]
    local minimap = _G["Minimap"]

    if hideMiniMap then
        if minimapCluster and minimapCluster.Hide then
            minimapCluster:Hide()
        end
        return
    end

    if minimapCluster and minimapCluster.Show then
        ClearSetAlphaOverride(minimapCluster)
        minimapCluster:Show()
        if minimapCluster.SetAlpha then
            minimapCluster:SetAlpha(tonumber(frameFader.originalAlphaByName["MinimapCluster"]) or 1)
        end
    end

    -- Some UIs leave Minimap itself hidden/locked even after the cluster is shown.
    if minimap then
        ClearSetAlphaOverride(minimap)
        if minimap.Show then
            minimap:Show()
        end
        if minimap.SetAlpha then
            minimap:SetAlpha(tonumber(frameFader.originalAlphaByName["Minimap"]) or 1)
        end
    end
end

-- Hide the player unit frame without hiding the castbar, which is a child of the player frame
-- Also, don't hide the loot window, which is an oUF tag like the health and power texts we need to hide.
local function HideElvUIPlayerFrame(hideFrame)
    local targetAlpha = hideFrame and HIDDEN_ALPHA or VISIBLE_ALPHA

    if isElvUIActive and _G["ElvUI"] then
        -- --- ELVUI ACTIVE ROUTINE ---
        local elvPlayer = _G["ElvUF_Player"]
        if elvPlayer then

            -- 1. Lock out the visual bar layout components completely
            local physicalBars = {
                elvPlayer.Health,
                elvPlayer.Power,
                elvPlayer.Portrait,
                elvPlayer.InfoPanel,
                elvPlayer.AlternativePower,
                elvPlayer.ClassPower,
            }

            for _, bar in ipairs(physicalBars) do
                if bar and bar.SetAlpha then
                    -- CRITICAL CRASH/HIDE PREVENTION:
                    -- Double-check that we aren't accidentally messing with the Loot frame or its children
                    if bar ~= _G["ElvUI_LootFrame"] and bar:GetParent() ~= _G["ElvUI_LootFrame"] then
                        bar:SetAlpha(targetAlpha)
                        if hideFrame then
                            if not bar.SetAlpha_Old then
                                bar.SetAlpha_Old = bar.SetAlpha
                                bar.SetAlpha = function() end
                            end
                        else
                            if bar.SetAlpha_Old then
                                bar.SetAlpha = bar.SetAlpha_Old
                                bar.SetAlpha_Old = nil
                            end
                            bar:SetAlpha(VISIBLE_ALPHA)
                        end
                    end
                end
            end

            -- 2. SECURE oUF TEXT TAG SUPPRESSION
            if hideFrame then
                if elvPlayer.unregisteredString == nil then
                    elvPlayer.unregisteredString = {}

                    local tagContainers = { elvPlayer.Health, elvPlayer.Power }
                    if elvPlayer.customTexts then
                        for _, txtObj in pairs(elvPlayer.customTexts) do
                            table.insert(tagContainers, txtObj)
                        end
                    end

                    for _, container in ipairs(tagContainers) do
                        -- CRITICAL SAFETY EXCLUSION: Skip if this text belongs to the loot frame layout
                        if container ~= _G["ElvUI_LootFrame"] and container:GetParent() ~= _G["ElvUI_LootFrame"] then
                            local targetStringObj = container and (container.value or container)
                            if targetStringObj and targetStringObj.GetText then
                                elvPlayer.unregisteredString[targetStringObj] = targetStringObj:GetText() or ""
                                targetStringObj:SetText("")

                                -- Make sure we ONLY disable tags on the player frame, never the loot frame
                                if elvPlayer.DisableElement and elvPlayer ~= _G["ElvUI_LootFrame"] then
                                    elvPlayer:DisableElement('Tags')
                                end
                            end
                        end
                    end
                end
            else
                -- Restore the native oUF engine strings
                if elvPlayer.unregisteredString then
                    if elvPlayer.EnableElement and elvPlayer ~= _G["ElvUI_LootFrame"] then
                        elvPlayer:EnableElement('Tags')
                    end

                    if type(elvPlayer.UpdateAllElements) == "function" then
                        elvPlayer:UpdateAllElements("PLAYER_ENTERING_WORLD")
                    end
                    elvPlayer.unregisteredString = nil
                end
            end

        end
    else
        -- --- DEFAULT BLIZZARD UI ROUTINE ---
        local blizzPlayer = _G["PlayerFrame"] or _G["CompactPlayerFrame"]
        if blizzPlayer then
            blizzPlayer:SetAlpha(targetAlpha)
        end
    end
end

-- Helper function to control visibility states
local function HideBlizzardMicroMenu(hideMenu)
    -- 1. Handle Micro Menu Container (and Bag Bar if attached)
    local targetContainer = MicroMenuContainer or MicroButtonAndBagsBar
    if targetContainer then
        if hideMenu then
            targetContainer:SetAlpha(HIDDEN_ALPHA)
        else
            targetContainer:SetAlpha(VISIBLE_ALPHA)
        end
    end

    -- 2. Handle Individual Micro Buttons (Prevents mouse hover artifacts)
    if MICRO_BUTTONS then
        for _, buttonName in ipairs(MICRO_BUTTONS) do
            local button = _G[buttonName]
            if button then
                button:EnableMouse(not hideMenu)
                button:SetAlpha(hideMenu and HIDDEN_ALPHA or VISIBLE_ALPHA)
            end
        end
    end
end

local function IsFrameFading(frame)
    if not UIFrameFadeTimers or not frame then return false end
    -- If the frame exists as a key in the table, it is actively fading
    return UIFrameFadeTimers[frame] ~= nil
end

local function SetFrameClickEnabled(frame, enabled)
    if not frame then
        return
    end
    if type(frame.SetMouseClickEnabled) == "function" then
        frame:SetMouseClickEnabled(enabled)
    elseif type(frame.EnableMouse) == "function" then
        frame:EnableMouse(enabled)
    end
end

local function IsBaselineCaptureSuppressed()
    local suppressUntil = tonumber(frameFader.cacheSuppressUntil) or 0
    if suppressUntil <= 0 then
        return false
    end

    if type(GetTime) ~= "function" then
        return true
    end

    if GetTime() < suppressUntil then
        return true
    end

    frameFader.cacheSuppressUntil = nil
    return false
end

local function FadeFrameIn(name, duration)
    local frame = ResolveNamedFrame(name)
    if not frame then
        return
    end

    local wasShown = frameFader.wasShownByName[name]
    if wasShown == nil and frame and frame.IsShown then
        wasShown = frame:IsShown() and true or false
    end
    local originalAlpha = tonumber(frameFader.originalAlphaByName[name])

    if wasShown == true then
        SetFrameClickEnabled(frame, true)
        ClearSetAlphaOverride(frame)
        -- cancel previous fade-out / fade-in timers before restoring
        if type(UIFrameFadeRemoveFrame) == "function" then
            UIFrameFadeRemoveFrame(frame)
        end

        local targetAlpha = originalAlpha
        if targetAlpha == nil or targetAlpha <= ALPHA_THRESHOLD then
            targetAlpha = VISIBLE_ALPHA
        end

        if frame.Show then
            frame:Show()
        end

        if duration and duration > 0 and type(UIFrameFadeIn) == "function" and frame.GetAlpha then
            UIFrameFadeIn(frame, duration, frame:GetAlpha() or HIDDEN_ALPHA, targetAlpha)
        elseif frame.SetAlpha then
            frame:SetAlpha(targetAlpha)
        end
    end
end

local function FadeOutUI()
    if frameFader.isFading then
        return
    end
    frameFader.isFading = true
    frameFader.restoreAt = nil

    -- Blizzard UI elements
    for _, name in ipairs(panelNamesToFade) do
        local frame = ResolveNamedFrame(name)

        local isShown = frame and frame.IsShown and frame:IsShown()
        local alpha = frame and frame.GetAlpha and frame:GetAlpha()

        -- cache current visibility states for restoral
        if (not frameFader.isFaded) and (not IsFrameFading(frame)) and (not IsBaselineCaptureSuppressed()) then
            frameFader.wasShownByName[name] = isShown
            frameFader.originalAlphaByName[name] = alpha
        end

        -- cancel previous fade-out / fade-in timers before restoring
        if type(UIFrameFadeRemoveFrame) == "function" then
            UIFrameFadeRemoveFrame(frame)
        end

        if frame and isShown == true and alpha > 0.001 then
            SetFrameClickEnabled(frame, false)
            if type(UIFrameFadeOut) == "function" and frame.GetAlpha then
                UIFrameFadeOut(frame, FADE_OUT_DURATION, frame:GetAlpha() or VISIBLE_ALPHA, HIDDEN_ALPHA)
            elseif frame.SetAlpha then
                frame:SetAlpha(HIDDEN_ALPHA)
            elseif frame.Hide then
                frame:Hide()
            end
        end
    end

    HideElvUIPlayerFrame(true)
    HideBlizzardMicroMenu(true)
    HideMinimapButtons(true)
    HideMinimapCluster(true)
    HideHandyNotesMapPins(true)
    HideGatherMateMinimap(true)

    frameFader.isFaded = true
    frameFader.isFading = false
end

local function FadeInUI()
    if frameFader.isFading then
        return
    end
    frameFader.isFading = true

    if type(GetTime) == "function" then
        frameFader.cacheSuppressUntil = GetTime() + FADE_IN_DURATION
    else
        frameFader.cacheSuppressUntil = nil
    end

    for _, name in ipairs(panelNamesToFade) do
        FadeFrameIn(name, FADE_IN_DURATION)
    end

    HideElvUIPlayerFrame(false)
    HideBlizzardMicroMenu(false)
    HideMinimapButtons(false)
    HideMinimapCluster(false)
    HideHandyNotesMapPins(false)
    HideGatherMateMinimap(false)

    frameFader.wasShownByName = {}
    frameFader.originalAlphaByName = {}
    frameFader.isFaded = false
    frameFader.restoreAt = nil
    frameFader.isFading = false
end

local function RestoreFocusVisualsAfterLinger()
    if not frameFader.isFaded then
        frameFader.restoreAt = nil
        return
    end

    if not IsFadeFeatureEnabled() then
        FadeInUI()
        return
    end

    local linger = GetVisualsLingerSeconds()
    if linger <= 0 or type(GetTime) ~= "function" then
        FadeInUI()
        return
    end

    frameFader.restoreAt = GetTime() + linger
end

ForceVisibleFocusVisuals = function()
    frameFader.isFading = true
    frameFader.restoreAt = nil
    frameFader.cacheSuppressUntil = nil

    for _, name in ipairs(panelNamesToFade) do
        FadeFrameIn(name, 0.0) -- immediate
    end

    HideElvUIPlayerFrame(false)
    HideBlizzardMicroMenu(false)
    HideMinimapButtons(false)
    HideMinimapCluster(false)
    HideHandyNotesMapPins(false)
    HideGatherMateMinimap(false)

    frameFader.isFaded = false
    frameFader.isFading = false
end

local function RefreshFocusFadeState()
    if IsFadeFeatureEnabled() and IsPreCastingSessionState() then
        if not frameFader.isFaded then
            FadeOutUI()
        elseif frameFader.restoreAt ~= nil then
            frameFader.restoreAt = nil
        end
        return
    end

    local shouldFade = IsFadeFeatureEnabled() and IsFishingSessionActive()

    if shouldFade and frameFader.restoreAt ~= nil then
        frameFader.restoreAt = nil
    elseif IsFadeFeatureEnabled()
        and (addon.fishing and addon.fishing.IsSessionState
            and (addon.fishing.IsSessionState("CANCELLING_FISHING_SESSION") or addon.fishing.IsSessionState("CLOSING_FISHING_SESSION")))
        and frameFader.isFaded then
        RestoreFocusVisualsAfterLinger()
    elseif not shouldFade and frameFader.isFaded then
        FadeInUI()
    end
end

local function CreateFocusFadeFrame()
    if frameFader.frame then
        return frameFader.frame
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            RefreshFocusFadeState()
        end
    end)

    frame:SetScript("OnUpdate", function()
        if frameFader.restoreAt == nil then
            return
        end

        if type(GetTime) ~= "function" or GetTime() >= frameFader.restoreAt then
            FadeInUI()
        end
    end)

    frameFader.frame = frame
    return frame
end

addon.uiFocus = addon.uiFocus or {}
addon.uiFocus.CreateFocusFadeFrame = CreateFocusFadeFrame
addon.uiFocus.RefreshFocusFadeState = RefreshFocusFadeState
addon.uiFocus.FadeOutUI = FadeOutUI
addon.uiFocus.FadeInUI = FadeInUI
addon.uiFocus.RestoreFocusVisualsAfterLinger = RestoreFocusVisualsAfterLinger
addon.uiFocus.ForceVisibleFocusVisuals = ForceVisibleFocusVisuals
addon._test = addon._test or {}
addon._test.GetFocusFadeRestoreAt = function()
    return frameFader.restoreAt
end
