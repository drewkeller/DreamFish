local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local globalDB, profileDB, charDB
local function Initialize()
    globalDB = ns.FishingDB.global
    profileDB = ns.FishingDB.profile
    charDB = ns.FishingDB.char
end
ns.FishingInitializers = ns.FishingInitializers or {}
table.insert(ns.FishingInitializers, Initialize)

Fishing:RegisterTraceSource("mouse")

local lastClickTime = 0
local lastSingleFishingClickTime = 0
local doubleClickDelay = 0.25
local hideTimerHandle = nil
local suppressCapturedClick = false
local clickFrameName = "DreamFishSecureFishingFrame"
local strikeKeyFrame
local mouseButtonWatchFrame
local mouseButtonWatchElapsed = 0
local mouseButtonWatchInterval = 0.05
local bothMouseButtonsHeld = false
local leftMouseButtonHeld = false
local cleanupEventFrame = CreateFrame("Frame")

cleanupEventFrame:SetScript("OnEvent", function()
    Fishing:RemoveClickFrame()
end)

function Fishing:CreateClickFrame()
    -- Create a secure frame to intercept clicks for fishing
    if not self.clickFrame then
        self.clickFrame = CreateFrame("Button", clickFrameName, UIParent, "SecureActionButtonTemplate")
    end

    -- if hotkey is enabled and no mouse interaction, we don't need the frame to cover the screen
    self.clickFrame:ClearAllPoints()
    self.clickFrame:SetAllPoints(UIParent)
    self.clickFrame:SetFrameStrata("BACKGROUND")
    self.clickFrame:SetAttribute("type", "spell")
    self.clickFrame:SetAttribute("spell", "Fishing")
    self.clickFrame:SetAttribute("macrotext", nil)
    self.clickFrame:RegisterForClicks("RightButtonDown", "RightButtonUp")
    self.clickFrame:SetPropagateMouseClicks(true)
    self.clickFrame:SetPropagateMouseMotion(true)
    self.clickFrame:Hide()
    self.clickFrame:EnableMouse(false)
    self.clickFrame:SetMouseClickEnabled(false)
    self.clickFrame:SetMouseMotionEnabled(false)

    Fishing:HookMouseDown()
    Fishing:HookPreClickWithHandler()
end

function Fishing:HookMouseDown()
    if not self:IsHooked(WorldFrame, "OnMouseDown") then
        self:SecureHookScript(WorldFrame, "OnMouseDown", "HandleMouseDown")
    end
end

-- WorldFrame stops delivering OnMouseDown once mouselook engages, so a button pressed while
-- another is held is only observable by polling.
function Fishing:StartMouseButtonWatch()
    if not mouseButtonWatchFrame then
        -- Parentless so hiding the UI can't stop the poll.
        mouseButtonWatchFrame = CreateFrame("Frame")
        mouseButtonWatchFrame:Hide()
        mouseButtonWatchFrame:SetScript("OnUpdate", function(_, elapsed)
            mouseButtonWatchElapsed = mouseButtonWatchElapsed + elapsed
            if mouseButtonWatchElapsed < mouseButtonWatchInterval then return end
            mouseButtonWatchElapsed = 0
            Fishing:CheckHeldMouseButtons()
        end)
    end

    bothMouseButtonsHeld = IsMouseButtonDown("LeftButton") and IsMouseButtonDown("RightButton")
    leftMouseButtonHeld = IsMouseButtonDown("LeftButton")
    mouseButtonWatchElapsed = 0
    mouseButtonWatchFrame:Show()
end

function Fishing:StopMouseButtonWatch()
    if not mouseButtonWatchFrame then return end
    mouseButtonWatchFrame:Hide()
    bothMouseButtonsHeld = false
    leftMouseButtonHeld = false
end

function Fishing:CheckHeldMouseButtons()
    local leftDown = IsMouseButtonDown("LeftButton")
    local rightDown = IsMouseButtonDown("RightButton")

    if leftDown ~= leftMouseButtonHeld then
        leftMouseButtonHeld = leftDown
        -- A held left button means the player is mouselooking, so the right button belongs to the camera.
        if leftDown then
            self:SuspendRightClickStrike()
        else
            self:ArmRightClickStrike()
        end
    end

    local held = leftDown and rightDown
    if held == bothMouseButtonsHeld then return end

    bothMouseButtonsHeld = held
    if held and self:IsInFishingSession() then
        self:Trace("mouse", "both mouse buttons held")
        self:CancelFishingSession("both mouse buttons held")
    end
end

function Fishing:IsSoloPhysicalRightClick()
    return not IsShiftKeyDown()
        and not IsControlKeyDown()
        and not IsAltKeyDown()
        and not IsMouseButtonDown("LeftButton")
end

-- Handle player right clicks
function Fishing:HandleMouseDown(_, button)
    if button ~= "RightButton" then return end
    if not self.clickFrame or InCombatLockdown() then return end
    local isAutoLoot = IsModifiedClick("AUTOLOOTTOGGLE")
    if not isAutoLoot and not self:IsSoloPhysicalRightClick() then
        lastClickTime = 0
        self:Trace("mouse", "Ignoring right click: not solo")
        return
    end

    self:Trace("mouse", "Physical right click state=" .. tostring(ns.fishing.state.current))

    if not self:IsFishingState(ns.fishing.states.WAITING_FOR_BITE) then
        local isDoubleClick = self:IsDoubleClick()
        local isSecondSingleFishingClick = profileDB.castBySingleRightClickWhenFishing
            and isDoubleClick
            and (GetTime() - lastSingleFishingClickTime) <= doubleClickDelay
        if isSecondSingleFishingClick then
            lastSingleFishingClickTime = 0
            suppressCapturedClick = true
            self.clickFrame:SetAttribute("type", "macro")
            self.clickFrame:SetAttribute("spell", nil)
            self.clickFrame:SetAttribute("macrotext", "/stopmacro")
            self.clickFrame:SetPropagateMouseClicks(false)
            self:Trace("mouse", "Suppressing second click during single-click fishing")
        elseif profileDB.castBySingleRightClickWhenFishing and self:IsInFishingSession() then
            lastSingleFishingClickTime = GetTime()
            self:Trace("mouse", "Single right click detected while fishing")
            self:OnCastStarted("Single right click while fishing")
        elseif isDoubleClick and profileDB.castByDoubleRightClick then
            self:Trace("mouse", "Double right click detected")
            self:OnCastStarted("Double right click")
        else
            self:Trace("mouse", "Right click detected")
        end
    end
end

-- Handle hotkey "pre-click"
function Fishing:HookPreClickWithHandler()
    if not self:IsHooked(self.clickFrame, "PreClick") then
        self.clickFrame:SetScript("PreClick", function(_, button, down)
            if InCombatLockdown() then return end
            if button ~= "RightButton" or not down or not self:IsSoloPhysicalRightClick() then
                self.clickFrame:SetAttribute("type", nil)
                self.clickFrame:SetAttribute("spell", nil)
                self.clickFrame:SetAttribute("macrotext", nil)
                self:ReleaseClickCapture()
                return
            end

            -- If the right mouse button is already down, we are in the middle of a click
            -- and should not trigger a cast.
            if IsMouseButtonDown("RightButton") then
                return
            end

            if not profileDB.castByHotkey then
                self:Trace("hotkey", "PreClick detected but hotkey casting is disabled")
                return
            end
            self:Trace("hotkey", "PreClick state=" .. tostring(ns.fishing.state.current))
            if not self:IsInFishingSession() then
                self:OnCastStarted("Hotkey")
            end
        end)
    end
end

function Fishing:IsDoubleClick()
    local currentTime = GetTime()
    local isDoubleClick = false
    if (currentTime - lastClickTime) <= doubleClickDelay then
        -- Show the secure intercept frame to catch the up-click
        self.clickFrame:EnableMouse(true)
        self.clickFrame:SetMouseClickEnabled(true)
        self.clickFrame:SetMouseMotionEnabled(true)
        self.clickFrame:Show()

        isDoubleClick = true

        -- Queue the frame cleanup
        if hideTimerHandle then self:CancelTimer(hideTimerHandle) end
        hideTimerHandle = self:ScheduleTimer("HideClickFrame", 0.1)
    end

    lastClickTime = currentTime
    return isDoubleClick
end

function Fishing:HideClickFrame()
    if not InCombatLockdown() then
        if suppressCapturedClick then
            self.clickFrame:SetPropagateMouseClicks(true)
            suppressCapturedClick = false
            self:PrepareFishingClickAction()
        end
        if not profileDB.castBySingleRightClickWhenFishing or not self:IsInFishingSession() then
            ClearOverrideBindings(self.clickFrame)
        end
        self.clickFrame:Hide()
        self.clickFrame:SetMouseMotionEnabled(false)
    end
    hideTimerHandle = nil
end

function Fishing:ReleaseClickCapture()
    if not self.clickFrame or InCombatLockdown() then
        return
    end

    if hideTimerHandle then
        self:CancelTimer(hideTimerHandle)
        hideTimerHandle = nil
    end

    ClearOverrideBindings(self.clickFrame)
    self.clickFrame:SetPropagateMouseClicks(true)
    suppressCapturedClick = false
    self.clickFrame:Hide()
    self.clickFrame:SetMouseClickEnabled(false)
    self.clickFrame:SetMouseMotionEnabled(false)
    self.clickFrame:EnableMouse(false)
end

function Fishing:RemoveClickFrame()
    self:Unhook(WorldFrame, "OnMouseDown")

    if not self.clickFrame then return end

    if InCombatLockdown() then
        cleanupEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    if hideTimerHandle then
        self:CancelTimer(hideTimerHandle)
        hideTimerHandle = nil
    end

    ClearOverrideBindings(self.clickFrame)
    self.clickFrame:RegisterForClicks()
    self.clickFrame:SetScript("PreClick", nil)
    self.clickFrame:SetFrameStrata("BACKGROUND")
    self.clickFrame:SetAttribute("type", nil)
    self.clickFrame:SetAttribute("spell", nil)
    self.clickFrame:SetAttribute("macrotext", nil)
    self.clickFrame:SetPropagateMouseClicks(true)
    self.clickFrame:SetPropagateMouseMotion(true)
    self.clickFrame:SetMouseClickEnabled(false)
    self.clickFrame:SetMouseMotionEnabled(false)
    self.clickFrame:EnableMouse(false)
    self.clickFrame:Hide()
    self.clickFrame:ClearAllPoints()
    cleanupEventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

function Fishing:UpdateKeybindsAfterCombat()
    self:ApplyKeybinding()
end

-- The strike hotkey is bound straight to INTERACTTARGET, so it never reaches PreClick;
-- this propagating listener is the only way to observe that the player pressed it.
-- It doesn't consume the key (the INTERACTTARGET override still runs), it just traces strike key.
function Fishing:WatchStrikeKey(key)
    if not key or key == "" then return end

    if not strikeKeyFrame then
        strikeKeyFrame = CreateFrame("Frame", "DreamFishStrikeKeyWatcher", UIParent)
        strikeKeyFrame:SetScript("OnKeyDown", function(frame, pressedKey)
            frame:SetPropagateKeyboardInput(true)
            Fishing:HandleStrikeKeyDown(pressedKey)
        end)
    end

    strikeKeyFrame.watchedKey = key
    strikeKeyFrame:SetPropagateKeyboardInput(true)
    strikeKeyFrame:EnableKeyboard(true)
    strikeKeyFrame:Show()
end

function Fishing:StopWatchingStrikeKey()
    if not strikeKeyFrame then return end
    strikeKeyFrame:EnableKeyboard(false)
    strikeKeyFrame:Hide()
end

function Fishing:HandleStrikeKeyDown(pressedKey)
    if not strikeKeyFrame or pressedKey ~= strikeKeyFrame.watchedKey then return end

    local target = UnitExists("target") and UnitName("target") or "none"
    local softInteract = UnitExists("softinteract") and UnitName("softinteract") or "none"
    self:Trace("EasyStrike", "strike key=" .. tostring(pressedKey)
        .. " state=" .. self:CurrentStateName()
        .. " target=" .. tostring(target)
        .. " softinteract=" .. tostring(softInteract))
end

function Fishing:ApplyKeybinding()
    if InCombatLockdown() then return end

    local boundKeys = self:GetKeybindings()
    local hasKey1 = boundKeys[1] and boundKeys[1] ~= ""
    local hasKey2 = boundKeys[2] and boundKeys[2] ~= ""
    if hasKey1 or hasKey2 then
        ClearOverrideBindings(self.clickFrame)

        if hasKey1 then
            SetBindingClick(boundKeys[1], clickFrameName, "RightButton")
        end
        if hasKey2 then
            SetBindingClick(boundKeys[2], clickFrameName, "RightButton")
        end
    end
end
