-- DreamFish: Focus frame fading while fishing
local addonName, ns = ...
local Fishing = ns.Fishing or LibStub("AceAddon-3.0"):GetAddon("DreamFish"):GetModule("Fishing")

local globalDB, profileDB, charDB


local HIDDEN_ALPHA = 0.0001 -- Using 0 can cause issues with mouse events; use a very small number instead.
local VISIBLE_ALPHA = 1.0
local ALPHA_THRESHOLD = 0.25 -- Threshold to consider a frame effectively invisible
local FADE_IN_DURATION = 3.0
local FADE_OUT_DURATION = 3.0

local state = {
    isFishing = false,
    isElvUIActive = false,
}

Fishing:RegisterTraceSource("fade")

local function Trace(msg, ...)
    Fishing:Trace("fade", msg, ...)
end

local function Debug(msg, ...)
    Fishing:DebugSource("fade", msg, ...)
end

Fishing:RegisterOnModuleInitialize(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

Fishing:RegisterOnModuleEnable(function(self)
    self:RefreshFade()
end)

Fishing:RegisterOnModuleRegisterEvents(function(self)
    Debug("Registering events")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "PLAYER_REGEN_ENABLED")
    self:RegisterMessage("FISHING_SESSION_STARTED", "FISHING_SESSION_STARTED")
    self:RegisterMessage("FISHING_SESSION_ENDED",   "FISHING_SESSION_ENDED")
end)

Fishing:RegisterOnModuleUnregisterEvents(function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterMessage("FISHING_SESSION_STARTED")
    self:UnregisterMessage("FISHING_SESSION_ENDED")
end)

Fishing:RegisterOnModuleDisable(function(self)
    self:FadeinUI()
end)

-- Validator for ElvUI frames
function Fishing:IsElvUIActive()
    return state.isElvUIActive
end

-- Frame names to fade come from Fishing.db.profile.fadeFrames (the same data the Frame Fade
-- options tab edits) instead of a hardcoded list, so user-configured Custom entries and
-- checkbox toggles are respected. ElvUF_Player and ElvDB_* bars are excluded from the generic
-- list below since they're handled by their own dedicated code paths (see HideElvUIPlayerFrame
-- and HideElvUIDataBars).
local function GetAllFadeFrameEntries()
    local entries = {}
    if not (profileDB and profileDB.fadeFrames) then
        return entries
    end

    local function IsSectionVisible(sectionEntry)
        if not sectionEntry.validator then
            return true
        end
        local validator = Fishing[sectionEntry.validator]
        return type(validator) ~= "function" or validator(Fishing)
    end

    local function GetSectionFrames(sectionEntry)
        if sectionEntry.generator then
            local generator = Fishing[sectionEntry.generator]
            if type(generator) ~= "function" then
                return {}
            end
            sectionEntry.generatedEnabled = sectionEntry.generatedEnabled or {}
            local frameEntries = {}
            for _, frameName in ipairs(generator(Fishing) or {}) do
                local name = type(frameName) == "table" and frameName.name or frameName
                if name and name ~= "" then
                    frameEntries[#frameEntries + 1] = {
                        name = name,
                        enabled = sectionEntry.generatedEnabled[name] ~= false,
                    }
                end
            end
            return frameEntries
        end
        return sectionEntry.frames or {}
    end

    for _, categoryEntry in ipairs(profileDB.fadeFrames) do
        if categoryEntry.sections then
            for _, sectionEntry in ipairs(categoryEntry.sections) do
                if IsSectionVisible(sectionEntry) then
                    for _, frameEntry in ipairs(GetSectionFrames(sectionEntry)) do
                        table.insert(entries, frameEntry)
                    end
                end
            end
        elseif categoryEntry.frames then
            for _, frameEntry in ipairs(categoryEntry.frames) do
                table.insert(entries, frameEntry)
            end
        end
    end
    return entries
end

local function IsFadeFrameEnabled(frameName)
    for _, frameEntry in ipairs(GetAllFadeFrameEntries()) do
        if frameEntry.name == frameName then
            return frameEntry.enabled and true or false
        end
    end
    return false
end

local function BuildPanelNamesToFade()
    local names = {}
    for _, frameEntry in ipairs(GetAllFadeFrameEntries()) do
        if frameEntry.enabled and frameEntry.name ~= "ElvUF_Player" and not frameEntry.name:find("^ElvDB_") then
            table.insert(names, frameEntry.name)
        end
    end
    return names
end

local function BuildElvDataBarNames()
    local names = {}
    for _, frameEntry in ipairs(GetAllFadeFrameEntries()) do
        if frameEntry.enabled and frameEntry.name:find("^ElvDB_") then
            table.insert(names, frameEntry.name)
        end
    end
    return names
end

local frameFader = {
    frame = nil,
    isFading = nil,
    isFaded = false,
    cacheSuppressUntil = nil,
    wasShownByName = {},
    originalAlphaByName = {},
    dreamFishDialogWasShown = nil,
    dreamFishDialogOriginalAlpha = nil,
    restoreAt = nil,
}

function Fishing:PLAYER_ENTERING_WORLD(...)
    -- Detect if ElvUI module exists and is enabled by the user
    if C_AddOns.IsAddOnLoaded("ElvUI") and _G["ElvUI"] then
        Trace("ElvUI detected and loaded")
        state.isElvUIActive = true
    end
end

function Fishing:PLAYER_REGEN_ENABLED(...)
    self:RefreshFade()
end

function Fishing:FISHING_SESSION_STARTED(...)
    if not state.isFishing then
        state.isFishing = true
        self:RefreshFade()
    end
end

function Fishing:FISHING_SESSION_ENDED(...)
    if state.isFishing then
        state.isFishing = false
        self:RefreshFade()
    end
end

-- Setup for ElvUI detection and event handling
local function IsElvUIFrameModuleEnabled(E, frameName)
    if not E or not E.db then return nil end
    -- Data Bars (Experience, Reputation, etc.)
    if string.find(frameName, "ElvDB_") then
        local barName = string.gsub(frameName, "ElvDB_", "")
        barName = barName:lower()
        return E.db.databars and E.db.databars[barName] and E.db.databars[barName].enable
    end
end

local function HideElvUIDataBar(E, frameName, hideBars)
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

local function HideElvUIDataBars(hideBars)
    if not state.isElvUIActive or not _G["ElvUI"] then
        return
    end

    local E = _G["ElvUI"][1] -- ElvUI engine
    if not E or not E.db then
        return
    end

    for _, frameName in ipairs(BuildElvDataBarNames()) do
        local isEnabled = IsElvUIFrameModuleEnabled(E, frameName)
        if isEnabled ~= nil then
            HideElvUIDataBar(E, frameName, hideBars)
        end
    end
end

local function ResolveNamedFrame(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return _G[name]
end

local function GetDreamFishDialogSettings()
    for _, categoryEntry in ipairs(profileDB and profileDB.fadeFrames or {}) do
        if categoryEntry.name == "Tackle Box" then
            return categoryEntry
        end
    end
end

local function GetDreamFishDialogFrame()
    local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
    local dialog = AceConfigDialog and AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames["DreamFishDialog"]
    return dialog and (dialog.frame or dialog) or nil
end

local function SetDreamFishDialogAlpha(frame, targetAlpha, duration)
    if not frame or not frame.IsShown or not frame:IsShown() then
        return
    end

    if type(UIFrameFadeRemoveFrame) == "function" then
        UIFrameFadeRemoveFrame(frame)
    end
    if duration and duration > 0 and type(UIFrameFadeIn) == "function" and frame.GetAlpha then
        UIFrameFadeIn(frame, duration, frame:GetAlpha() or VISIBLE_ALPHA, targetAlpha)
    elseif frame.SetAlpha then
        frame:SetAlpha(targetAlpha)
    end
end

local function RefreshDreamFishDialogFade(duration)
    local settings = GetDreamFishDialogSettings()
    if not settings then
        return
    end

    local frame = GetDreamFishDialogFrame()
    if not frame and state.isFishing and settings.dreamfishDialogWhenFishing then
        -- Not currently open (e.g. never opened this session) — open it so "Show when fishing" actually shows it.
        ns.Addon:OpenDialogWindow("DreamFishDialog")
        return
    end
    if not frame then
        return
    end

    if state.isFishing then
        if settings.dreamfishDialogWhenFishing then
            if frameFader.dreamFishDialogWasShown == nil then
                frameFader.dreamFishDialogWasShown = frame.IsShown and frame:IsShown() or false
                frameFader.dreamFishDialogOriginalAlpha = frame.GetAlpha and frame:GetAlpha() or VISIBLE_ALPHA
            end
            SetDreamFishDialogAlpha(frame, tonumber(settings.dreamFishDialogAlphaWhenFishing) or VISIBLE_ALPHA, duration)
        else
            SetDreamFishDialogAlpha(frame, HIDDEN_ALPHA, duration)
        end
    elseif frameFader.dreamFishDialogWasShown ~= nil then
        if frameFader.dreamFishDialogWasShown and frame.Show then
            frame:Show()
            SetDreamFishDialogAlpha(frame, frameFader.dreamFishDialogOriginalAlpha or VISIBLE_ALPHA, duration)
        elseif not frameFader.dreamFishDialogWasShown and frame.Hide then
            frame:Hide()
        end
        frameFader.dreamFishDialogWasShown = nil
        frameFader.dreamFishDialogOriginalAlpha = nil
    else
        SetDreamFishDialogAlpha(frame, tonumber(settings.dreamFishDialogAlphaWhenOther) or VISIBLE_ALPHA, duration)
    end
end

local function ClearSetAlphaOverride(frame)
    if frame and frame.SetAlpha_Old then
        frame.SetAlpha = frame.SetAlpha_Old
        frame.SetAlpha_Old = nil
    end
end

-- Generator for frame names
function Fishing:GetMinimapButtonNames()
    local buttonNames = {}
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if LibDBIcon and LibDBIcon.GetButtonList then
        for _, iconName in ipairs(LibDBIcon:GetButtonList()) do
            table.insert(buttonNames, iconName)
        end
    end
    return buttonNames
end

local function HideMinimapButtons(hideButtons)
    local targetAlpha = hideButtons and HIDDEN_ALPHA or VISIBLE_ALPHA

    -- HIDE THIRD-PARTY ADDON ICONS (LibDBIcon)
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

-- Hide the player unit frame without hiding the castbar, which is a child of the player frame
-- Also, don't hide the loot window, which is an oUF tag like the health and power texts we need to hide.
local function HideElvUIPlayerFrame(hideFrame)
    if not state.isElvUIActive then return end
    if hideFrame and not IsFadeFrameEnabled("ElvUF_Player") then
        return -- user disabled fading this frame in the Frame Fade options
    end

    -- Dynamically fetch the frame from the global environment
    local elvPlayer = _G["ElvUF_Player"]

    -- 3. If it's missing, try to fetch it one more time via standard global lookup
    if not elvPlayer and ElvUF_Player then
        elvPlayer = ElvUF_Player
    end

    if elvPlayer then
        local targetAlpha = hideFrame and HIDDEN_ALPHA or VISIBLE_ALPHA

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
                    --Trace("Applying alpha to ElvUI bar: ", bar:GetName(), " targetAlpha: ", targetAlpha)
                    bar:SetAlpha(targetAlpha)
                    if hideFrame then
                        if not bar.SetAlpha_Old then
                            bar.SetAlpha_Old = bar.SetAlpha
                            bar.SetAlpha = function(dummy) end
                        end
                    else
                        if bar.SetAlpha_Old then
                            bar.SetAlpha = bar.SetAlpha_Old
                            bar.SetAlpha_Old = nil
                        end
                        bar:SetAlpha(VISIBLE_ALPHA)
                    end
                end
            elseif bar then
                Debug("Skipping alpha application for ElvUI bar without SetAlpha: ", bar:GetName())
            else
                Debug("Skipping alpha application for nil ElvUI bar")
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
    else
        Debug("No ElvUI player frame detected")
    end
end

-- Helper function to control visibility states
local function HideBlizzardMicroMenu(hideMenu)
    if hideMenu and not IsFadeFrameEnabled("MicroMenuContainer") then
        return -- user disabled fading this frame in the Frame Fade options
    end

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

local function HideAllFrames(hide)
    HideElvUIDataBars(hide)
    HideElvUIPlayerFrame(hide)
    -- we don't have a way to make these optional yet
    HideBlizzardMicroMenu(hide)
    HideMinimapButtons(hide)
    HideHandyNotesMapPins(hide)
    HideGatherMateMinimap(hide)
end

function Fishing:RefreshDreamFishDialogFade()
    RefreshDreamFishDialogFade(0.0)
end

local function FadeFrameOut(name, duration)
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

-- Instantly hides/shows a single named frame, same as ForceHidden/ForceVisible but scoped to one
-- frame, so toggling a checkbox in the Frame Fade options gives immediate visual feedback.
function Fishing:SetFrameFadeState(name, hide)
    if name == "ElvUF_Player" then
        HideElvUIPlayerFrame(hide)
    elseif name:find("^ElvDB_") then
        if not (state.isElvUIActive and _G["ElvUI"]) then return end
        local E = _G["ElvUI"][1]
        if not (E and E.db) then return end
        if IsElvUIFrameModuleEnabled(E, name) ~= nil then
            HideElvUIDataBar(E, name, hide)
        end
    elseif hide then
        FadeFrameOut(name, 0.0)
    else
        FadeFrameIn(name, 0.0)
    end
end

local function FadeOutUI()
    if frameFader.isFading then
        return
    end
    frameFader.isFading = true
    frameFader.restoreAt = nil
    Trace("Fading out")

    -- Standard fadeable frames
    for _, name in ipairs(BuildPanelNamesToFade()) do
        FadeFrameOut(name, FADE_OUT_DURATION)
    end

    RefreshDreamFishDialogFade(FADE_OUT_DURATION)

    HideAllFrames(true)

    frameFader.isFaded = true
    frameFader.isFading = false
end

local function FadeInUI()
    if frameFader.isFading then
        return
    end
    frameFader.isFading = true
    Trace("Fading in")

    if type(GetTime) == "function" then
        frameFader.cacheSuppressUntil = GetTime() + FADE_IN_DURATION
    else
        frameFader.cacheSuppressUntil = nil
    end

    -- Standard fadeable frames
    for _, name in ipairs(BuildPanelNamesToFade()) do
        FadeFrameIn(name, FADE_IN_DURATION)
    end

    RefreshDreamFishDialogFade(FADE_IN_DURATION)

    HideAllFrames(false)

    frameFader.wasShownByName = {}
    frameFader.originalAlphaByName = {}
    frameFader.isFaded = false
    frameFader.restoreAt = nil
    frameFader.isFading = false
end

function Fishing:ForceHidden()
    frameFader.isFading = true
    frameFader.cacheSuppressUntil = nil

    for _, name in ipairs(BuildPanelNamesToFade()) do
        FadeFrameOut(name, 0.0) -- immediate
    end

    RefreshDreamFishDialogFade(0.0)

    HideAllFrames(true)

    frameFader.isFaded = true
    frameFader.isFading = false
end

function Fishing:ForceVisible()
    frameFader.isFading = true
    frameFader.cacheSuppressUntil = nil

    for _, name in ipairs(BuildPanelNamesToFade()) do
        FadeFrameIn(name, 0.0) -- immediate
    end

    RefreshDreamFishDialogFade(0.0)

    HideAllFrames(false)

    frameFader.isFaded = false
    frameFader.isFading = false
end

function Fishing:RefreshFade()
    local shouldFade = profileDB.frameFocusEnabled and state.isFishing

    if shouldFade and not frameFader.isFaded then
        FadeOutUI()
    elseif not shouldFade and frameFader.isFaded then
        FadeInUI()
    end
end
