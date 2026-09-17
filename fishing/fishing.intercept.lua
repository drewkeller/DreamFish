local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

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
    Fishing:HookPostClickWithHandler()
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

    self:Trace("mouse", "Physical right click state=" .. Fishing:CurrentStateName())

    if not self:IsFishingState(ns.Fishing.states.WAITING_FOR_BITE) then
        -- Catch single-click recasting WHILE IN A SESSION before polling double-click registers
        if self.db.profile.castBySingleRightClickWhenFishing and self:IsInFishingSession() then
            -- If this click happened instantly after another single click, suppress it to prevent double-casting loops
            if (GetTime() - lastSingleFishingClickTime) <= doubleClickDelay then
                lastSingleFishingClickTime = 0
                suppressCapturedClick = true
                self.clickFrame:SetAttribute("type", "macro")
                self.clickFrame:SetAttribute("spell", nil)
                self.clickFrame:SetAttribute("macrotext", "/stopmacro")
                self.clickFrame:SetPropagateMouseClicks(false)
                self:Trace("mouse", "Suppressing second click during single-click fishing")
                return
            end

            lastSingleFishingClickTime = GetTime()
            self:Trace("mouse", "Single right click detected while fishing (Session Active)")
            self:PrepareFishingClickAction()
            self:OnCastStarted("Single right click while fishing")
            return
        end

        local isDoubleClick = self:IsDoubleClick()
        if isDoubleClick and self.db.profile.castByDoubleRightClick then
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
                -- A release edge (down=false) during an active PRECASTING pass must not disarm the
                -- frame: a settling pole swap may have just re-armed it, and clearing here would
                -- leave the frame empty so the release casts nothing and the confirmation guard
                -- cancels with "fishing cast did not start". Modified/mixed PRESSES (down=true)
                -- must still clear the captured action so we don't hijack a modified click.
                if not down and button == "RightButton" and Fishing:IsFishingState(ns.Fishing.states.PRECASTING) then
                    return
                end
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

            if not self.db.profile.castByHotkey then
                self:Trace("hotkey", "PreClick detected but hotkey casting is disabled")
                return
            end
            self:Trace("hotkey", "PreClick state=" .. Fishing:CurrentStateName())
            if not self:IsInFishingSession()
                or self:IsFishingState(ns.Fishing.states.LINGERING) then
                self:OnCastStarted("Hotkey")
            elseif self:IsFishingState(ns.Fishing.states.PRECASTING) then
                self:PrepareFishingClickAction({ showSwimmingGuidance = true })
            end
        end)
    end
end

function Fishing:HookPostClickWithHandler()
    if not self:IsHooked(self.clickFrame, "PostClick") then
        self.clickFrame:SetScript("PostClick", function(frame, button, down)
            if InCombatLockdown() or button ~= "RightButton" or down == true then
                return
            end

            -- INSTRUMENTATION: Gather metrics on every single up-click release frame pass
            local liveMacroText = frame:GetAttribute("macrotext") or "nil"
            local liveType = frame:GetAttribute("type") or "nil"
            local liveSpell = frame:GetAttribute("spell") or "nil"

            self:Trace("mouse", string.format("PostClick: State=%s | type=%s | spell=%s | len(macrotext)=%d",
                Fishing:CurrentStateName(), liveType, liveSpell, #liveMacroText))
            if liveMacroText ~= "nil" then
                self:Trace("mouse", "PostClick Macro: " .. liveMacroText)
            end

            local selectedRaftToy = self.db
                and self.db.profile
                and tonumber(self.db.profile.selectedRaftToy)
                or nil
            if selectedRaftToy and selectedRaftToy > 0
                and type(liveMacroText) == "string"
                and liveMacroText:find("/use item:" .. tostring(selectedRaftToy), 1, true)
                and ns.precast
                and type(ns.precast.MarkRaftUse) == "function" then
                ns.precast.MarkRaftUse(selectedRaftToy)
            end

             if Fishing:IsFishingState(ns.Fishing.states.PRECASTING) then
                local pending = Fishing.state.pendingBuffUse

                -- FIX: Also fetch any active pending use changes if a background pass armed it intra-frame!
                if not pending and self.state.pendingBuffUse then
                    pending = self.state.pendingBuffUse
                end

                if pending then
                    local macroContainsPendingUse = false
                    local pendingUseStarted = false
                    if type(liveMacroText) == "string" and type(pending.uses) == "table" then
                        for _, use in ipairs(pending.uses) do
                            if use.castStarted then
                                pendingUseStarted = true
                            end
                            local itemID = tonumber(use.itemID)
                            if itemID and liveMacroText:find("/use item:" .. tostring(itemID), 1, true) then
                                macroContainsPendingUse = true
                                break
                            end
                        end
                    end
                    if not macroContainsPendingUse and not pendingUseStarted then
                        self:Trace("mouse", "PostClick release: clearing unexecuted consumable pending state not present in clicked macro.")
                        self.state.pendingBuffUse = nil
                        pending = nil
                    end
                end

                if pending then
                    if not pending.executedAt then
                        pending.executedAt = GetTime()
                        for _, use in ipairs(pending.uses or {}) do
                            use.expiresAt = pending.executedAt + 5
                        end
                    end
                    self:Trace("mouse", "PostClick release: Consumable item application pending confirmation. Running delay buffers.")

                    C_Timer.After(0.10, function()
                        if Fishing.clickFrame then
                            Fishing.clickFrame:SetAttribute("macrotext", "")
                        end
                    end)

                    C_Timer.After(0.15, function()
                        if Fishing:IsFishingState(ns.Fishing.states.PRECASTING) then
                            Fishing:PrepareFishingClickAction()
                        end
                    end)

                else
                    -- If a tool swap is still active, suppress release
                    if self.state and self.state.isEquippingPrimaryPole then
                        self:Trace("mouse", "PostClick release suppressed: primary fishing pole gear-swap is actively processing.")
                        return
                    end

                    -- If a tool swap was processed but the bag handler hasn't advanced the engine yet,
                    -- skip manual state overrides to avoid race condition lockouts.
                    if self.state and self.state.isEquippingPrimaryPole then
                        return
                    end

                    if frame:GetAttribute("dreamfish_precast_action") then
                        self:Trace("mouse", "PostClick release: Pre-cast item action awaiting completion.")
                        return
                    end

                    self:Trace("mouse", "PostClick release: Waiting for fishing spellcast confirmation.")
                    Fishing:AwaitFishingCastStart()
                end
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
        if not self.db.profile.castBySingleRightClickWhenFishing or not self:IsInFishingSession() then
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
