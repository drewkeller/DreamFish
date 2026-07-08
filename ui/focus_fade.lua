-- DreamFisher: Focus frame fading while fishing

local addon = _G["DreamFisher"]
local DebugStateMessage = addon.DebugStateMessage or addon.DebugMessage or function() end

-- Finding frame names can be done by using /fstack in the game.
-- 1. Turn on frame stack tool by typing /fstack in the game.
-- 2. Hover over the frame you want to identify.
-- 3. Note the frame name displayed by the frame stack tool (in the lighter colored text).
-- 4. Turn off frame stack tool by typing /fstack again in the game.
local panelNamesToFade = {
    -- Minimap
    "Minimap",
    "ObjectiveTrackerFrame",
    "MinimapCluster",
    "GameTimeFrame",             -- Calendar button
    "MiniMapMailFrame",          -- Mail icon
    "MiniMapTracking",           -- Tracking magnifying glass
    "QueueStatusButton",         -- LFG queue eye icon
    "QueueStatusMinimapButton",  -- Classic LFG queue icon
    "GarrisonLandingPageMinimapButton", -- Expansion/Mission tracking button
    "ExpansionLandingPageMinimapButton", -- Dragonflight/TWW expansion button
    "ChatFrame1",
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
}

local frameFader = {
    frame = nil,
    isFaded = false,
    wasShownByName = {},
    restoreAt = nil,
}

local fadeState = nil

local elvUIFrames = {
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
    "LeftChatPanel",
    "RightChatPanel",
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

-- array[frameName] = {wasShown = boolean, originalAlpha = number}
elvUIFrameFader = {}

-- Setup for ElvUI detection and event handling
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
local isElvUIActive = false
local elvuiAlphaSettings = {    -- frameName, isEnabled, originalAlpha
    actionBarAlpha = nil,
    unitFrameAlpha = nil,
}

local function IsElvUIFrameModuleEnabled(E, frameName)
    if not E or not E.db then return nil end

    -- Action Bars
    if string.find(frameName, "ElvUI_Bar") then
        local barIndex = string.match(frameName, "ElvUI_Bar(%d+)")
        if barIndex and E.db.actionbar then
            local barKey = "bar" .. barIndex
            return E.db.actionbar[barKey] and E.db.actionbar[barKey].enabled
        end
    end

    -- Stance Bar
    if frameName == "ElvUI_StanceBar" then
        return E.db.actionbar and E.db.actionbar.stanceBar and E.db.actionbar.stanceBar.enable
    end

    if frameName == "ElvUF_Player_Castbar" then
        local UF = E:GetModule('UnitFrames', true)

        if UF and E.db and E.db.unitframe and E.db.unitframe.units and E.db.unitframe.units.player then
            return E.db.unitframe.units.player.castbar.enable == true
        end
    end

    -- Core Unit Frames (Player, Target, Focus, etc.)
    if string.find(frameName, "ElvUF_") then
        -- Extract the unit key (e.g., "ElvUF_Player" becomes "player")
        local unitKey = string.lower(string.gsub(frameName, "ElvUF_", ""))

        -- Master UnitFrame module switch must be on, and the specific unit frame layout must be enabled
        if E.db.unitframe and E.db.unitframe.units and E.db.unitframe.units[unitKey] then
            local moduleEnabled = C_AddOns.IsAddOnLoaded("ElvUI_OptionsUI") or E:GetModule('UnitFrames', true)
            return moduleEnabled and E.db.unitframe.units[unitKey].enable
        end
    end

    -- Standalone Auras (Buffs / Debuffs)
    if frameName == "ElvUI_PlayerBuffs" or frameName == "ElvUI_PlayerDebuffs" then
        return E.db.auras and E.db.auras.enable
    end

    -- Chat Panels
    if frameName == "LeftChatPanel" or frameName == "RightChatPanel" then
        if not E.private or not E.private.chat or not E.private.chat.enable then
            return false
        end

        -- Possible settings: "SHOWBOTH", "HIDEBOTH", "LEFT", or "RIGHT"
        local backdropSetting = E.db.chat.panelBackdrop or "SHOWBOTH"

        local isEnabled = true
        if frameName == "LeftChatPanel" then
            isEnabled = (backdropSetting == "SHOWBOTH" or backdropSetting == "LEFT")
        elseif frameName == "RightChatPanel" then
            isEnabled = (backdropSetting == "SHOWBOTH" or backdropSetting == "RIGHT")
        end
        return isEnabled
    end

    -- Data Bars (Experience, Reputation, etc.)
    if string.find(frameName, "ElvDB_") then
        local barName = string.gsub(frameName, "ElvDB_", "")
        barName = barName:lower()
        return E.db.databars and E.db.databars[barName] and E.db.databars[barName].enable
    end

    -- Fallback: If it's a generic frame, check if it physically exists and is visible
    local fallbackFrame = _G[frameName]
    return (fallbackFrame ~= nil) or nil
end

local function FadeFrameCustom(frame, fadeMode, duration, targetAlpha)
    if not frame or not frame.GetAlpha then return end

    -- Safety: If you previously overrode SetAlpha with an empty function,
    -- restore it so the animation engine can physically adjust the visibility.
    if frame.SetAlpha_Old then
        frame.SetAlpha = frame.SetAlpha_Old
        frame.SetAlpha_Old = nil
    end

    -- Setup the native Blizzard fading parameter block
    local fadeInfo = {
        mode = fadeMode,                -- "IN" to fade in, "OUT" to fade out
        timeToFade = duration or 0.3,   -- Animation time in seconds
        startAlpha = frame:GetAlpha(),   -- Dynamically capture current visibility
        endAlpha = targetAlpha or 0.0,  -- The destination alpha (e.g., 0 for invisible)
        finishedFunc = function()
            -- Set SetAlpha to an empty function so frame can't be changed while in fishing mode.
            if fadeMode == "OUT" and targetAlpha == 0 then
                frame:SetAlpha(0)
                frame.SetAlpha_Old = frame.SetAlpha
                frame.SetAlpha = function() end
            end
        end
    }

    -- Execute Blizzard's native UI animation frame manager
    -- (This works seamlessly across Retail and Classic clients)
    if _G["UIFrameFade"] then
        _G["UIFrameFade"](frame, fadeInfo)
    else
        -- Fallback: Instant change if the animation frame module is completely missing
        frame:SetAlpha(targetAlpha or 0.0)
    end
end

local function SetElvUIDataBarVisibility(E, frameName, hideBars)
    local DB = E:GetModule('DataBars', true)
    local barTitle = frameName:gsub("ElvDB_", "")
    local barName = barTitle:lower()

    if DB and E.db and E.db.databars and E.db.databars[barName] then
        E.db.databars[barName].enable = not hideBars

        -- Refresh the individual bar layout using ElvUI's internal API
        local barMethodName = "Update" .. barTitle .. "Dimensions"
        if type(DB[barMethodName]) == "function" then
            DB[barMethodName](DB)
        end

        -- Force a top-level master redraw of the entire module framework (yes, this appears to be necessary)
        if type(DB.UpdateAll) == "function" then
            DB:UpdateAll()
        end
    end
end

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
local BuildFocusVisualStateLines

local function FocusFadeTrace(message)
    if addon and addon.db and addon.db.debugMode and addon.db.debugState then
        -- Keep chat output readable by default; per-frame traces are too noisy.
        local isFrameDetail = string.find(message, " frame ", 1, true) ~= nil
        if isFrameDetail and not (addon.db and addon.db.debugFadeVerbose) then
            return
        end
        DebugStateMessage("Focus fade: " .. tostring(message))
    end
end

local function FocusFadeTraceState(prefix)
    if not (addon and addon.db and addon.db.debugMode and addon.db.debugState) then
        return
    end
    local minimap = ResolveNamedFrame("Minimap")
    local minimapShown = minimap and minimap.IsShown and minimap:IsShown() or false
    local minimapAlpha = minimap and minimap.GetAlpha and minimap:GetAlpha() or nil
    local cluster = ResolveNamedFrame("MinimapCluster")
    local clusterShown = cluster and cluster.IsShown and cluster:IsShown() or false
    local alphaText = minimapAlpha == nil and "n/a" or string.format("%.2f", tonumber(minimapAlpha) or 0)
    DebugStateMessage("Focus fade: " .. tostring(prefix)
        .. " featureEnabled=" .. tostring(IsFadeFeatureEnabled())
        .. " isFaded=" .. tostring(frameFader.isFaded)
        .. " restoreAt=" .. tostring(frameFader.restoreAt)
        .. " minimapShown=" .. tostring(minimapShown)
        .. " minimapAlpha=" .. alphaText
        .. " clusterShown=" .. tostring(clusterShown))
end

local function ClearSetAlphaOverride(frame)
    if frame and frame.SetAlpha_Old then
        frame.SetAlpha = frame.SetAlpha_Old
        frame.SetAlpha_Old = nil
    end
end

local function ForceFrameVisible(frame)
    if not frame then
        return
    end
    ClearSetAlphaOverride(frame)
    if frame.Show then
        frame:Show()
    end
    if frame.SetAlpha then
        frame:SetAlpha(1)
    end
end

BuildFocusVisualStateLines = function()
    local lines = {}
    table.insert(lines, "Focus visuals dump: featureEnabled=" .. tostring(IsFadeFeatureEnabled())
        .. " isFaded=" .. tostring(frameFader.isFaded)
        .. " restoreAt=" .. tostring(frameFader.restoreAt))

    local function AppendFrameLine(name)
        local frame = ResolveNamedFrame(name)
        if not frame then
            table.insert(lines, name .. ": missing")
            return
        end

        local shown = frame.IsShown and frame:IsShown() or false
        local alpha = frame.GetAlpha and frame:GetAlpha() or nil
        local alphaText = alpha == nil and "n/a" or string.format("%.2f", tonumber(alpha) or 0)
        local locked = frame.SetAlpha_Old and " locked" or ""
        table.insert(lines, name .. ": shown=" .. tostring(shown) .. " alpha=" .. alphaText .. locked)
    end

    for _, name in ipairs(panelNamesToFade) do
        AppendFrameLine(name)
    end

    for _, name in ipairs(elvUIFrames) do
        AppendFrameLine(name)
    end

    return lines
end

local function GetVisualsLingerSeconds()
    local defaults = addon and addon.defaults or nil
    local linger = (addon and addon.db and addon.db.focusedVisualsLinger)
        or (defaults and defaults.focusedVisualsLinger)
        or 0
    return math.max(0, tonumber(linger) or 0)
end

local function HideMinimapButtons(hideButtons)
    local targetAlpha = hideButtons and 0.0 or 1.0


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
                    buttonFrame:SetAlpha(1)
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
        minimapCluster:Show()
    end

    -- Some UIs leave Minimap itself hidden/locked even after the cluster is shown.
    if minimap then
        ClearSetAlphaOverride(minimap)
        if minimap.Show then
            minimap:Show()
        end
        if minimap.SetAlpha then
            minimap:SetAlpha(1)
        end
    end
end

-- Hide the player unit frame without hiding the castbar, which is a child of the player frame
-- Also, don't hide the loot window, which is an oUF tag like the health and power texts we need to hide.
local function HideElvUIPlayerFrame(hideFrame)
    local targetAlpha = hideFrame and 0.0 or 1.0

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
                            bar:SetAlpha(1)
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
            targetContainer:SetAlpha(0)
        else
            targetContainer:SetAlpha(1)
        end
    end

    -- 2. Handle Individual Micro Buttons (Prevents mouse hover artifacts)
    if MICRO_BUTTONS then
        for _, buttonName in ipairs(MICRO_BUTTONS) do
            local button = _G[buttonName]
            if button then
                button:EnableMouse(not hideMenu)
                button:SetAlpha(hideMenu and 0 or 1)
            end
        end
    end
end

local function GetElvUIFrameSettings(E, frameName)
    local isEnabled = IsElvUIFrameModuleEnabled(E, frameName)
    local alpha = nil
    if isEnabled then
        local targetFrame = _G[frameName]

        if targetFrame and targetFrame.GetAlpha then
            alpha = targetFrame:GetAlpha()
        end

        -- Action bars "global" alpha setting
        if alpha == nil and  string.find(frameName, "ElvUI_Bar") then
            if E.db.actionbar and E.db.actionbar.globalFadeAlpha then
                alpha = E.db.actionbar.globalFadeAlpha
            end

        -- Player castbar
        elseif alpha == nil and string.find(frameName, "ElvUF_PlayerCastbar") then
            -- if E.db.unitframe and E.db.unitframe.units and E.db.unitframe.units.player and E.db.unitframe.units.player.castbar and E.db.unitframe.units.player.castbar.enable ~= nil then
            --     alpha = E.db.unitframe.units.player.castbar.enable and 1 or 0
            -- end

        -- Unit frames
        elseif alpha == nil and string.find(frameName, "ElvUF_") then
            if E.db.unitframe and E.db.unitframe.general and E.db.unitframe.general.globalFadeAlpha then
                alpha = E.db.unitframe.general.globalFadeAlpha
            end

        -- Data bars (no "alpha" setting, other than that which is determined by their "color" setting)
        elseif alpha == nil and string.find(frameName, "ElvDB_") then
            local barName = string.gsub(frameName, "ElvDB_", "")
            barName = barName:lower()
            local isVisible = E.db.databars and E.db.databars[barName] and E.db.databars[barName].enable
            alpha = isVisible and 1 or 0
        end
    end

    alpha = alpha == nil and 0 or alpha
    return isEnabled, alpha
end

local function FadeOutUI()
    FocusFadeTrace("FadeOutUI begin")
    frameFader.restoreAt = nil

    -- Blizzard UI elements
    for _, name in ipairs(panelNamesToFade) do
        local panel = ResolveNamedFrame(name)
        if panel and panel.IsShown and panel:IsShown() then
            frameFader.wasShownByName[name] = true
            FocusFadeTrace("FadeOutUI hide Blizzard frame " .. name .. " alpha=" .. tostring(panel.GetAlpha and panel:GetAlpha() or 1))
            if type(UIFrameFadeOut) == "function" and panel.GetAlpha then
                UIFrameFadeOut(panel, 0.5, panel:GetAlpha() or 1, 0)
            elseif panel.SetAlpha then
                panel:SetAlpha(0)
            end
        else
            frameFader.wasShownByName[name] = false
            FocusFadeTrace("FadeOutUI skip Blizzard frame " .. name .. " (not shown)")
        end
    end
    HideBlizzardMicroMenu(true)

    -- ElvUI elements
    if _G["ElvUI"] then
        local E = unpack(_G["ElvUI"])

        for _, name in ipairs(elvUIFrames) do
            -- Read current settings so we can restore them later
            local isEnabled, alpha = GetElvUIFrameSettings(E, name)
            local isShown = isEnabled and alpha > 0.0
            local doFadeOut = name ~= "ElvUF_Player_Castbar"
            elvUIFrameFader[name] = {wasShown = isShown, originalAlpha = alpha}
            -- if the frame/bar is shown, hide it
            if isShown and doFadeOut then
                FocusFadeTrace("FadeOutUI hide ElvUI frame " .. name .. " alpha=" .. tostring(alpha))
                if string.find(name, "ElvDB_") then
                    SetElvUIDataBarVisibility(E, name, true)
                else
                    local duration = 0.3
                    local targetAlpha = 0 -- hidden
                    local frame = _G[name]
                    FadeFrameCustom(frame, "OUT", duration, targetAlpha)
                end
            elseif isShown then
                FocusFadeTrace("FadeOutUI keep ElvUI frame visible " .. name .. " (castbar exception)")
            else
                FocusFadeTrace("FadeOutUI skip ElvUI frame " .. name .. " (not shown)")
            end
        end
        HideElvUIPlayerFrame(true)
    end

    HideMinimapButtons(true)
    HideMinimapCluster(true)
    HideHandyNotesMapPins(true)
    HideGatherMateMinimap(true)

    frameFader.isFaded = true
    FocusFadeTraceState("FadeOutUI end")
end

local function FadeInUI()
    FocusFadeTrace("FadeInUI begin")
    -- Blizzard UI elements
    for _, name in ipairs(panelNamesToFade) do
        local panel = ResolveNamedFrame(name)
        if panel and panel.SetAlpha then
            local wasShown = frameFader.wasShownByName[name]
            if wasShown then
                FocusFadeTrace("FadeInUI restore Blizzard frame " .. name)
                if type(UIFrameFadeIn) == "function" and panel.GetAlpha then
                    UIFrameFadeIn(panel, 0.3, panel:GetAlpha() or 0, 1)
                else
                    panel:SetAlpha(1)
                end
            else
                FocusFadeTrace("FadeInUI leave Blizzard frame hidden " .. name .. " (was not shown before fade)")
                panel:SetAlpha(0) -- need to do anything?
            end
        end
    end
    HideBlizzardMicroMenu(false)

    FocusFadeTrace("FadeInUI restoring ElvUI frames")
    if _G["ElvUI"] then
        local E = unpack(_G["ElvUI"])
        for _, name in ipairs(elvUIFrames) do
            if elvUIFrameFader[name] then
                local wasShown = elvUIFrameFader[name].wasShown or false
                local originalAlpha = elvUIFrameFader[name].originalAlpha or 0
                -- if the frame was shown before, fade it back in to its original alpha
                if wasShown then
                    FocusFadeTrace("FadeInUI restore ElvUI frame " .. name .. " alpha=" .. tostring(originalAlpha))
                    if string.find(name, "ElvDB_") then
                        SetElvUIDataBarVisibility(E, name, false)
                    else
                        local duration = 0.3
                        local frame = _G[name]
                        FadeFrameCustom(frame, "IN", duration, originalAlpha)
                    end
                else
                    FocusFadeTrace("FadeInUI skip ElvUI frame " .. name .. " (was not shown before fade)")
                end
            end
        end
        HideElvUIPlayerFrame(false)
    end

    HideMinimapButtons(false)
    HideMinimapCluster(false)
    HideHandyNotesMapPins(false)
    HideGatherMateMinimap(false)

    frameFader.wasShownByName = {}
    frameFader.isFaded = false
    frameFader.restoreAt = nil
    FocusFadeTraceState("FadeInUI end")
end

local function RestoreFocusVisualsAfterLinger()
    FocusFadeTrace("RestoreFocusVisualsAfterLinger begin")
    if not frameFader.isFaded then
        frameFader.restoreAt = nil
        FocusFadeTrace("RestoreFocusVisualsAfterLinger skipped; UI not faded")
        return
    end

    if not IsFadeFeatureEnabled() then
        FocusFadeTrace("RestoreFocusVisualsAfterLinger immediate restore; focused visuals disabled")
        FadeInUI()
        return
    end

    local linger = GetVisualsLingerSeconds()
    if linger <= 0 or type(GetTime) ~= "function" then
        FocusFadeTrace("RestoreFocusVisualsAfterLinger immediate restore; linger=" .. tostring(linger) .. " GetTimeAvailable=" .. tostring(type(GetTime) == "function"))
        FadeInUI()
        return
    end

    frameFader.restoreAt = GetTime() + linger
    FocusFadeTrace("RestoreFocusVisualsAfterLinger scheduled restoreAt=" .. tostring(frameFader.restoreAt) .. " linger=" .. tostring(linger))
end

ForceVisibleFocusVisuals = function()
    frameFader.restoreAt = nil

    for _, name in ipairs(panelNamesToFade) do
        ForceFrameVisible(ResolveNamedFrame(name))
        frameFader.wasShownByName[name] = true
    end

    if _G["ElvUI"] then
        local E = unpack(_G["ElvUI"])
        for _, name in ipairs(elvUIFrames) do
            local frame = ResolveNamedFrame(name)
            if frame then
                ForceFrameVisible(frame)
                if string.find(name, "ElvDB_") then
                    SetElvUIDataBarVisibility(E, name, false)
                end
            end
        end
        HideElvUIPlayerFrame(false)
    end

    HideBlizzardMicroMenu(false)
    HideMinimapButtons(false)
    HideMinimapCluster(false)
    HideHandyNotesMapPins(false)
    HideGatherMateMinimap(false)

    frameFader.isFaded = false
end

local function RefreshFocusFadeState()
    FocusFadeTrace("RefreshFocusFadeState begin state=" .. tostring(addon.state and addon.state.fishingSessionState)
        .. " featureEnabled=" .. tostring(IsFadeFeatureEnabled())
        .. " isFaded=" .. tostring(frameFader.isFaded)
        .. " restoreAt=" .. tostring(frameFader.restoreAt))
    if IsFadeFeatureEnabled() and IsPreCastingSessionState() then
        if not frameFader.isFaded then
            FocusFadeTrace("RefreshFocusFadeState entering PRE_CASTING -> fade out")
            FadeOutUI()
        elseif frameFader.restoreAt ~= nil then
            FocusFadeTrace("RefreshFocusFadeState clearing pending restore during PRE_CASTING")
            frameFader.restoreAt = nil
        end
        return
    end

    local shouldFade = IsFadeFeatureEnabled() and IsFishingSessionActive()

    if shouldFade and not frameFader.isFaded then
        FocusFadeTrace("RefreshFocusFadeState shouldFade=true and not faded -> fade out")
        FadeOutUI()
    elseif shouldFade and frameFader.restoreAt ~= nil then
        FocusFadeTrace("RefreshFocusFadeState shouldFade=true and restoreAt pending -> clear timer")
        frameFader.restoreAt = nil
    elseif IsFadeFeatureEnabled()
        and (addon.fishing and addon.fishing.IsSessionState
            and (addon.fishing.IsSessionState("CANCELLING_FISHING_SESSION") or addon.fishing.IsSessionState("CLOSING_FISHING_SESSION")))
        and frameFader.isFaded then
        FocusFadeTrace("RefreshFocusFadeState close/cancel state with faded UI -> schedule restore")
        RestoreFocusVisualsAfterLinger()
    elseif not shouldFade and frameFader.isFaded then
        FocusFadeTrace("RefreshFocusFadeState shouldFade=false and faded -> fade in")
        FadeInUI()
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

    frame:SetScript("OnUpdate", function()
        if frameFader.restoreAt == nil then
            return
        end
        if type(GetTime) ~= "function" or GetTime() >= frameFader.restoreAt then
            FocusFadeTrace("OnUpdate restoreAt reached -> FadeInUI")
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
addon.uiFocus.GetFocusVisualStateLines = BuildFocusVisualStateLines
addon._test = addon._test or {}
addon._test.GetFocusFadeRestoreAt = function()
    return frameFader.restoreAt
end
addon._test.GetFocusVisualStateLines = BuildFocusVisualStateLines
