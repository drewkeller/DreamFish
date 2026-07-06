-- DreamFisher: Focus frame fading while fishing

local addon = _G["DreamFisher"]

local panelNamesToFade = {
    "Minimap",
    "ObjectiveTrackerFrame",
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
    -- "ElvUI_MicroBar", -- maybe we don't want to hide this one?
    "ElvUF_Player_Castbar", -- We want to make sure this is shown
    -- Core unit frames
    --"ElvUF_Player",
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
    --print("Fallback check for frame: " .. frameName .. ", exists: " .. tostring(fallbackFrame ~= nil))
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

-- local function ToggleElvUIStanceBar(E, hideBar, targetAlpha)
--     if isElvUIActive and E then
--         -- --- ELVUI ACTIVE ROUTINE ---
--         local AB = E:GetModule('ActionBars', true)

--         if AB and E.db and E.db.actionbar and E.db.actionbar.stanceBar then
--             -- 1. Modify ElvUI's internal stance bar database visibility switch
--             -- If hideBar is true, set enable to false; otherwise, restore to true
--             E.db.actionbar.stanceBar.enable = not hideBar

--             -- 2. Safely tell the ActionBar module to completely re-initialize the bar
--             if type(AB.PositionAndSizeBarStance) == "function" then
--                 AB:PositionAndSizeBarStance()
--             end
--         end

--         -- Fallback Brute Force: Target the literal secure frame wrapper directly
--         local stanceFrame = _G["ElvUI_StanceBar"]
--         if stanceFrame then
--             stanceFrame:SetAlpha(targetAlpha)

--             -- Temporarily hook SetAlpha so ElvUI's engine can't draw it back while fishing
--             if hideBar then
--                 if not stanceFrame.SetAlpha_Old then
--                     stanceFrame.SetAlpha_Old = stanceFrame.SetAlpha
--                     stanceFrame.SetAlpha = function() end
--                 end
--             else
--                 if stanceFrame.SetAlpha_Old then
--                     stanceFrame.SetAlpha = stanceFrame.SetAlpha_Old
--                     stanceFrame.SetAlpha_Old = nil
--                 end
--                 stanceFrame:SetAlpha(1)
--             end
--         end
--     end
-- end

-- local function ToggleElvUIPlayerAurasVisibility(E, hideAuras, targetAlpha)
--     if isElvUIActive and E then
--         local A = E:GetModule('Auras', true)

--         -- ElvUI places headers for player buffs and debuffs globally
--         local elvBuffs = _G["ElvUF_PlayerBuffs"]
--         local elvDebuffs = _G["ElvUF_PlayerDebuffs"]

--         -- Method A: If using ElvUI's standalone Aura module
--         if elvBuffs or elvDebuffs then
--             for _, frame in ipairs({elvBuffs, elvDebuffs}) do
--                 if frame then
--                     frame:SetAlpha(targetAlpha)
--                     -- Protect the transparency from ElvUI's layout update engine
--                     if hideAuras then
--                         if not frame.SetAlpha_Old then
--                             frame.SetAlpha_Old = frame.SetAlpha
--                             frame.SetAlpha = function() end
--                         end
--                     else
--                         if frame.SetAlpha_Old then
--                             frame.SetAlpha = frame.SetAlpha_Old
--                             frame.SetAlpha_Old = nil
--                         end
--                         frame:SetAlpha(1)
--                     end
--                 end
--             end
--         end

--         -- Method B: If they use ElvUI Unitframe-attached Auras (built into the player frame)
--         local elvPlayer = _G["ElvUF_Player"]
--         if elvPlayer then
--             if elvPlayer.Buffs then elvPlayer.Buffs:SetAlpha(targetAlpha) end
--             if elvPlayer.Debuffs then elvPlayer.Debuffs:SetAlpha(targetAlpha) end
--             if elvPlayer.Auras then elvPlayer.Auras:SetAlpha(targetAlpha) end
--         end
--     end
-- end

-- local function ToggleElvUIUnitFramesVisibility(E, hideFrames, targetAlpha)
--     local UF = E:GetModule('UnitFrames', true)
--     if UF then
--         -- Locate ElvUI's secure player frame wrapper
--         local elvPlayer = _G["ElvUF_Player"]
--         if elvPlayer then
--             if hideFrames then
--                 elvPlayer:SetAlpha(targetAlpha)
--                 -- Temporarily hook SetAlpha so ElvUI can't override it while fishing
--                 if not elvPlayer.SetAlpha_Old then
--                     elvPlayer.SetAlpha_Old = elvPlayer.SetAlpha
--                     elvPlayer.SetAlpha = function() end
--                 end
--             else
--                 -- Restore normal ElvUI control when done fishing
--                 if elvPlayer.SetAlpha_Old then
--                     elvPlayer.SetAlpha = elvPlayer.SetAlpha_Old
--                     elvPlayer.SetAlpha_Old = nil
--                 end
--                 if elvuiAlphaSettings and elvuiAlphaSettings.unitFrameAlpha then
--                     elvPlayer:SetAlpha(elvuiAlphaSettings.unitFrameAlpha)
--                 else
--                     elvPlayer:SetAlpha(1)
--                 end
--             end
--         end
--     end
-- end

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

-- ElvUI: Main initialization and event loop
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

local function ToggleMinimapIcons(hideIcons)
    local targetAlpha = hideIcons and 0.0 or 1.0

    -- --- 1. HIDE NATIVE BLIZZARD / ELVUI MINIMAP BUTTONS ---
    -- List of standard tracking and event frames anchored around the minimap
    local standardMinimapButtons = {
        "MinimapCluster",
        "GameTimeFrame",             -- Calendar button
        "MiniMapMailFrame",          -- Mail icon
        "MiniMapTracking",           -- Tracking magnifying glass
        "QueueStatusButton",         -- LFG queue eye icon
        "QueueStatusMinimapButton",  -- Classic LFG queue icon
        "GarrisonLandingPageMinimapButton", -- Expansion/Mission tracking button
        "ExpansionLandingPageMinimapButton" -- Dragonflight/TWW expansion button
    }

    for _, frameName in ipairs(standardMinimapButtons) do
        local btn = _G[frameName]
        if btn then
            btn:SetAlpha(targetAlpha)

            -- Prevent internal event triggers from undoing our visibility change
            if hideIcons then
                if not btn.SetAlpha_Old then
                    btn.SetAlpha_Old = btn.SetAlpha
                    btn.SetAlpha = function() end
                end
            else
                if btn.SetAlpha_Old then
                    btn.SetAlpha = btn.SetAlpha_Old
                    btn.SetAlpha_Old = nil
                end
                btn:SetAlpha(1)
            end
        end
    end

    -- --- 2. HIDE THIRD-PARTY ADDON ICONS (LibDBIcon) ---
    -- Almost every addon (Details, WeakAuras, etc.) uses LibDBIcon-1.0 to attach buttons.
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if LibDBIcon and LibDBIcon.GetButtonList then
        for _, iconName in ipairs(LibDBIcon:GetButtonList()) do
            local buttonFrame = LibDBIcon:GetMinimapButton(iconName)
            if buttonFrame then
                buttonFrame:SetAlpha(targetAlpha)

                if hideIcons then
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

local function ToggleMinimapMarkers(hideMarkers)
    if hideMarkers then
        -- 1. Wipe the quest POI indicators and shaded yellow objective circles
        SetCVar("questPOI", 0)
        SetCVar("minimapShowQuestBlobs", 0)

        -- 2. Turn off the tracking system entirely (Hides Herbs, Ore, Fish, Tracked Targets)
        -- This disables tracking nodes on your active mini navigation wheel
        C_Minimap.SetTracking(0, false)
    else
        -- Restore your normal UI tracking behaviors when putting the rod away
        SetCVar("questPOI", 1)
        SetCVar("minimapShowQuestBlobs", 1)

        -- Optional: Re-enable Fish tracking explicitly when done
        -- (Or leave this part out to let the player manually re-check their preferred tracking)
    end
end

local function TogglePOIArrows(hideArrows)
    if _G["Minimap"] then
        if hideArrows then
            -- Replace the default spinning arrow texture file path with a blank string
            if type(Minimap.SetStaticPOIArrowTexture) == "function" then
                Minimap:SetStaticPOIArrowTexture("")
            end
        else
            -- Restore the factory default Blizzard rotating arrow asset
            if type(Minimap.SetStaticPOIArrowTexture) == "function" then
                Minimap:SetStaticPOIArrowTexture([[Interface\Minimap\ROTATING-MINIMAPARROW]])
            end
        end
    end
end

local function ToggleHandyNotesMapPins(hidePins)
    if C_AddOns.IsAddOnLoaded("HandyNotes") and _G["HandyNotes"] then
        local HandyNotes = LibStub("AceAddon-3.0"):GetAddon("HandyNotes", true)
        if HandyNotes and type(HandyNotes.SetEnabled) == "function" then
            -- Disabling/Enabling the module sweeps the pins away safely
            if hidePins then HandyNotes:Disable() else HandyNotes:Enable() end
        end
    end
end

-- Hide the player unit frame without hiding the castbar, which is a child of the player frame
-- Also, don't hide the loot window, which is an oUF tag like the health and power texts we need to hide.
local function SetElvUIPlayerFrameVisibility(hideFrame)
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
local function SetBlizzardMicroMenuVisibility(hideMenu)
    -- 1. Handle Micro Menu Container (and Bag Bar if attached)
    local targetContainer = MicroMenuContainer or MicroButtonAndBagsBar
    if targetContainer then
        if hideMenu then
            targetContainer:SetAlpha(0)
            targetContainer:SetScale(0.0001)
        else
            targetContainer:SetAlpha(1)
            targetContainer:SetScale(1)
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

    -- 3. Handle Minimap Static POI Arrows
    if hideMenu then
        Minimap:SetStaticPOIArrowTexture("")
        Minimap:SetPlayerTexture("") -- Optional: Hides player arrow as well
        C_SuperTrack.SetSuperTrackedQuestID(0) -- Clear current quest path arrow
    else
        -- Resets to the default Blizzard UI textures when done
        Minimap:SetStaticPOIArrowTexture("Interface\\Minimap\\MinimapArrow")
        Minimap:SetPlayerTexture("Interface\\Minimap\\MinimapArrow")
    end
end

-- Intercept the Super Tracking system while fishing
-- hooksecurefunc(C_SuperTrack, "SetSuperTrackedQuestID", function(questID)
--     -- If a player equips a fishing rod and a quest updates, kill the new arrow instantly
--     if questID ~= 0 and IsEquippedItemType("Fishing") then
--         C_SuperTrack.SetSuperTrackedQuestID(0)
--     end
-- end)


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
    -- Blizzard UI elements
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
    SetBlizzardMicroMenuVisibility(true)

    -- ElvUI elements
    -- for each frame
    if _G["ElvUI"] then
        local E = unpack(_G["ElvUI"])

        -- elvUIFrameFader["LeftChatPanel"] = GetElvUIFrameSettings(E, "LeftChatPanel")
        -- elvUIFrameFader["RightChatPanel"] = GetElvUIFrameSettings(E, "RightChatPanel")

        for _, name in ipairs(elvUIFrames) do
            -- Read current settings so we can restore them later
            local isEnabled, alpha = GetElvUIFrameSettings(E, name)
            local isShown = isEnabled and alpha > 0.0
            local doFadeOut = name ~= "ElvUF_Player_Castbar"
            elvUIFrameFader[name] = {wasShown = isShown, originalAlpha = alpha}
            -- if the frame/bar is shown, hide it
            if isShown and doFadeOut then
                if string.find(name, "ElvDB_") then
                    SetElvUIDataBarVisibility(E, name, true)
                else
                    local duration = 0.3
                    local targetAlpha = 0 -- hidden
                    local frame = _G[name]
                    FadeFrameCustom(frame, "OUT", duration, targetAlpha)
                end
            end
        end
        SetElvUIPlayerFrameVisibility(true)
    end

    ToggleMinimapIcons(true)
    ToggleMinimapMarkers(true)
    TogglePOIArrows(true)
    ToggleHandyNotesMapPins(true)

    frameFader.isFaded = true
end

local function FadeInUI()
    -- Blizzard UI elements
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
                panel:SetAlpha(0) -- need to do anything?
            end
        end
    end
    SetBlizzardMicroMenuVisibility(false)

    if _G["ElvUI"] then
        local E = unpack(_G["ElvUI"])
        for _, frameName in ipairs(elvUIFrames) do
            if elvUIFrameFader[frameName] then
                local wasShown = elvUIFrameFader[frameName].wasShown or false
                local originalAlpha = elvUIFrameFader[frameName].originalAlpha or 0
                -- if the frame was shown before, fade it back in to its original alpha
                if wasShown then
                    if string.find(frameName, "ElvDB_") then
                        SetElvUIDataBarVisibility(E, frameName, false)
                    else
                        local duration = 0.3
                        local frame = _G[frameName]
                        FadeFrameCustom(frame, "IN", duration, originalAlpha)
                    end
                end
            end
        end
        SetElvUIPlayerFrameVisibility(false)
    end

    ToggleMinimapIcons(false)
    ToggleMinimapMarkers(false)
    TogglePOIArrows(false)
    ToggleHandyNotesMapPins(false)

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
