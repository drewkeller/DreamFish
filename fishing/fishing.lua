local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

ns.precast = {}

ns.Fishing.ConfigureFishingClickAction = ns.Fishing.ConfigureFishingClickAction or function(self) end

function Fishing:RegisterOnModuleInitialize(func)
    if type(func) == "function" then
        self.onInitializeFuncs = self.onInitializeFuncs or {}
        table.insert(self.onInitializeFuncs, func)
    end
end
local function CallRegisteredOnModuleInitialize(self)
    if type(self.onInitializeFuncs) == "table" then
        for _, func in ipairs(self.onInitializeFuncs) do
            func(self)
        end
    end
end

function Fishing:RegisterOnModuleEnable(func)
    if type(func) == "function" then
        self.onEnableFuncs = self.onEnableFuncs or {}
        table.insert(self.onEnableFuncs, func)
    end
end
local function CallRegisteredOnModuleEnable(self)
    if type(self.onEnableFuncs) == "table" then
        for _, func in ipairs(self.onEnableFuncs) do
            func(self)
        end
    end
end

local rightClickStrikeOwner

Fishing:RegisterTraceSource("EasyStrike")
Fishing:RegisterTraceSource("auraevent")
Fishing:RegisterTraceSource("hotkey")
Fishing:RegisterTraceSource("loot")

function Fishing:OnModuleInitialize()
    -- access the database within "Fishing" functions using self.db
    -- In local functions, use ns.FishingDB
    ns.FishingDB = self.db

    self.state = self.state or {}

    -- FIX 1: FORCE-PURGE DATA CORRUPTION LOCKS FROM SAVEDVARIABLES
    if self.db and self.db.global and type(self.db.global.buffAuraByItem) == "table" then
        if self.db.global.buffAuraByItem["0"] or self.db.global.buffAuraByItem[0] then
            self:Debug("Purging corrupted item:0 database tracking lock record.")
            self.db.global.buffAuraByItem["0"] = nil
            self.db.global.buffAuraByItem[0] = nil
        end
    end

    CallRegisteredOnModuleInitialize(self)
end

function Fishing:OnModuleEnable()
    self:CreateClickFrame()
    self:RegisterEvent("ADDON_LOADED",                 "OnAddonLoaded")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",         "OnCombatEnded")
    self:RegisterEvent("PLAYER_REGEN_DISABLED",        "OnCombatStarted")
    self:RegisterEvent("PLAYER_STARTED_MOVING",        "OnMovementStarted")
    self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", "OnMountDisplayChanged")
    self:RegisterEvent("UNIT_SPELLCAST_START",         "OnSpellCastStarted")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED",     "OnSpellcastChannelStarted")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP",  "OnSpellcastChannelEnded")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED",     "OnEquipmentChanged")
    self:RegisterEvent("BAG_UPDATE_DELAYED",           "OnBagUpdateDelayed")
    self:RegisterEvent("UNIT_AURA",                    "OnAurasChanged")
    self:RegisterEvent("UI_ERROR_MESSAGE",             "OnUIErrorMessage")
    self:RegisterEvent("LOOT_READY",                   "OnLootReady")
    self:RegisterEvent("LOOT_CLOSED",                  "OnLootClosed")

    self:RegisterMessage("FISHING_CAST_ENDED",         "OnFishingCastEnded")

    self:ApplyKeybinding()

    CallRegisteredOnModuleEnable(self)
end

function Fishing:OnModuleDisable()
    self:UnregisterEvent("ADDON_LOADED")
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("PLAYER_STARTED_MOVING")
    self:UnregisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    self:UnregisterEvent("UNIT_SPELLCAST_START")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:UnregisterEvent("UNIT_SPELLCAST_STOP")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self:UnregisterEvent("BAG_UPDATE_DELAYED")
    self:UnregisterEvent("UNIT_AURA")
    self:UnregisterEvent("UI_ERROR_MESSAGE")
    self:UnregisterEvent("LOOT_READY")
    self:UnregisterEvent("LOOT_CLOSED")
    self:UnregisterMessage("FISHING_CAST_ENDED")
    self:RemoveCastBar()
    self:RemoveClickFrame()
end

function Fishing:OnBagUpdateDelayed()
    if type(self.CheckAndHandlePoleSwapReset) == "function" then
        self:CheckAndHandlePoleSwapReset()
    end

    local poleDecision = ns.precast.GetSelectedFishingPoleDecision and ns.precast.GetSelectedFishingPoleDecision()
    local shouldApply = poleDecision and poleDecision.shouldApply
    self:Trace("pole", string.format("[PROBE: BAG_DELAYED] State=%s | isEquippingPrimaryPole=%s | shouldApply=%s",
        self:CurrentStateName(), tostring(self.state and self.state.isEquippingPrimaryPole), tostring(shouldApply)))

    if self.state and self.state.isEquippingPrimaryPole then
        local poleDecision = ns.precast.GetSelectedFishingPoleDecision and ns.precast.GetSelectedFishingPoleDecision()
        -- Release the swap lock when the swap is finished. shouldApply can still read true
        -- for a frame or two while the equip registers on the profession slot, which would
        -- otherwise skip this clear and leave isEquippingPrimaryPole stuck until the cast
        -- guard cancels the session ("fishing cast did not start"). Treating "the configured
        -- pole is now equipped" as the source of truth avoids that race.
        local equippedID = ns.precast.GetEquippedProfessionItemID and ns.precast.GetEquippedProfessionItemID() or nil
        local swapSettled = (not poleDecision or not poleDecision.shouldApply)
            or (poleDecision and poleDecision.itemID and equippedID == poleDecision.itemID)
        if swapSettled then
            self:Trace("pole", "Fishing pole equipment change detected in player profession tool slot.")

            -- Release our equipment execution locks smoothly
            self.state.isEquippingPrimaryPole = false
            if ns.CastBar and type(ns.CastBar.HidePoleSwap) == "function" then
                ns.CastBar.HidePoleSwap()
            end

            -- Clear out the temporary stop macro string blocker cleanly
            self.clickFrame:SetAttribute("macrotext", "")

            -- FIX: If we are in the middle of an active hotkey pass (PRECASTING), do NOT move state back to IDLE!
            -- Keep the state locked in PRECASTING so the upcoming up-click release can handle it naturally.
            if not self:IsFishingState(ns.Fishing.states.PRECASTING) then
                self:SetFishingState(ns.Fishing.states.IDLE, "standalone pole change verified")
            end

            -- Re-compile the macro text string arrays instantly with your live lure data lines.
            -- The PreClick release-edge no longer disarms the frame mid-PRECASTING, so a plain
            -- re-arm here is sufficient for the upcoming release to cast.
            self:PrepareFishingClickAction()
        end
    end

    if type(self.state.buffLearning) == "table" then
        if type(self.ConfirmPendingBuffUse) == "function" then
            Addon:TraceCore("learning", "Confirming pending buff use.")
            self:ConfirmPendingBuffUse()
        end
        if type(self.UpdatePendingBuffObservation) == "function" then
            self:UpdatePendingBuffObservation()
        end
    end

    if not self:IsInFishingSession() or self:IsFishingState(ns.Fishing.states.IDLE) then
        return
    end

    if type(self.ConfirmPendingBuffUse) == "function" then
        self:ConfirmPendingBuffUse()
    end

    if type(self.CheckEnabledBuffItemsDepleted) == "function" then
        self:CheckEnabledBuffItemsDepleted()
    end
end

function Fishing:GetKeybindings()
    return {GetBindingKey("CLICK DreamFishSecureFishingFrame:RightButton")}
end

function Fishing:SetKeybindings(primaryKey, secondaryKey)
    local action = "CLICK DreamFishSecureFishingFrame:RightButton"
    local key1, key2 = GetBindingKey(action)

    -- Clear both slots to prevent overlap loops
    if key1 then SetBinding(key1, nil) end
    if key2 then SetBinding(key2, nil) end

    -- Re-bind the new primary key, and put back the old secondary key if it existed (or vice-versa)
    if primaryKey then
        if primaryKey and primaryKey ~= "" then SetBinding(primaryKey, action) end
        if key2 and key2 ~= "" and key2 ~= primaryKey then SetBinding(key2, action) end
    elseif secondaryKey then
        if key1 and key1 ~= "" and key1 ~= secondaryKey then SetBinding(key1, action) end
        if secondaryKey and secondaryKey ~= "" then SetBinding(secondaryKey, action) end
    else
        -- No new keys provided, so just clear the binding entirely
        SetBinding(action, nil)
    end

    SaveBindings(GetCurrentBindingSet())
end

function Fishing:PrepareFishingClickAction()
    if not self.clickFrame or InCombatLockdown() then
        return
    end

    self:Trace("precast", string.format("[PrepareClick Action] Live State=%s", Fishing:CurrentStateName()))

    -- Securely defend your JIT compilation states.
    -- If a channel bar is actively running, never re-compile the macro text arrays mid-cast!
    if self:IsFishingState(ns.Fishing.states.CASTING) or self:IsFishingState(ns.Fishing.states.WAITING_FOR_BITE) then
        return
    end

    ns.Fishing.ConfigureFishingClickAction(self)

    if self:IsFishingState(ns.Fishing.states.PRECASTING) then
        self:StartPrecastLingerTimer()
    end
end

function Fishing:OnAurasChanged(event, unit, updateInfo)
    if type(unit) == "string" and unit ~= "player" then
        return
    end

    if type(self.state.buffLearning) == "table"
        and type(self.UpdatePendingBuffObservation) == "function" then
        self:UpdatePendingBuffObservation()
    end

    if not self:IsInFishingSession() or self:IsFishingState(ns.Fishing.states.IDLE) then
        return
    end

    if self:IsFishingState(ns.Fishing.states.PRECASTING)
        or self:IsFishingState(ns.Fishing.states.LINGERING) then
        self:PrepareFishingClickAction()
    end

    if updateInfo.isFullUpdate == true then
        self:Trace("auraevent", "Full aura update detected")
        return
    end

    local hasAddedAuras, hasRemovedAuras = false, false

    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            hasAddedAuras = true
            self:Trace("auraevent", "Added: " .. tostring(aura.spellId) .. " (" .. tostring(aura.name) .. ")")
        end
    end

    if updateInfo.removedAuras then
        -- if a fishing aura was removed, the bobber may have been looted or despawned (cast finished)
        for _, aura in ipairs(updateInfo.removedAuras) do
            hasRemovedAuras = true
            self:Trace("auraevent", "Removed: " .. tostring(aura.spellId) .. " (" .. tostring(aura.name) .. ")")
        end
    end

    if not hasAddedAuras and not hasRemovedAuras then
        --self:Trace("auraevent", "No added or removed auras (existing updated?)")
    end
end

function Fishing:OnAddonLoaded(event)
    -- Delay the initial login equipment check to allow the client to fully cache bag and inventory tracking
    C_Timer.After(2.0, function()
        if type(self.CheckAndEquipUnderlightAngler) == "function" then
            self:CheckAndEquipUnderlightAngler("addon loaded (delayed packet safety pass)")
        end
    end)
end

-- This function does NOT fire for profession slotted items
function Fishing:OnEquipmentChanged(event, slotId)
    if slotId == FISHINGTOOLSLOT then
        self:Trace("pole", "Fishing pole changed")
        self.state.isEquippingPrimaryPole = false
        if ns.CastBar and type(ns.CastBar.HidePoleSwap) == "function" then
            ns.CastBar.HidePoleSwap()
        end
        -- if hotkey cast fishing pole, prepare it again
        if self:IsFishingState(ns.Fishing.states.IDLE)
            or self:IsFishingState(ns.Fishing.states.PRECASTING)
            or self:IsFishingState(ns.Fishing.states.LINGERING) then
            self:PrepareFishingClickAction()
        end
        self:RefreshPoleBorders()
    end
end

function Fishing:OnLootReady(event)
    local current = self.state.current
    -- The hotkey strike is a native INTERACTTARGET override, so it produces no click we can hook;
    -- the loot window opening is the only signal that the bobber was struck successfully.
    local isStrikeResult = current == ns.Fishing.states.WAITING_FOR_LOOT_WINDOW
        or current == ns.Fishing.states.WAITING_FOR_BITE
        or current == ns.Fishing.states.BITE_DETECTED
        or current == ns.Fishing.states.CASTING

    if isStrikeResult then
        self:Trace("loot", "Loot window ready")
        self:StopWatchingStrikeKey()
        self:SendMessage("FISHING_LOOT_READY")
        self:SetFishingState(ns.Fishing.states.LOOTING, "loot window ready")
    end
end

function Fishing:OnLootClosed(event)
    if self.state.current == ns.Fishing.states.LOOTING then
        self:Trace("loot", "Loot window closed")
        self:SendMessage("FISHING_LOOT_CLOSED")
        self:StartLinger()
    end
end

function Fishing:CancelLingerTimer()
    if self.state.lingerTimer then
        self:CancelTimer(self.state.lingerTimer)
        self.state.lingerTimer = nil
    end
end

function Fishing:StartPrecastLingerTimer()
    self:CancelLingerTimer()
    if not (self.db and self.db.profile and self.db.profile.lingerExpirationEnabled) then
        return
    end
    local duration = tonumber(self.db and self.db.profile and self.db.profile.lingerDuration) or 10
    if duration <= 0 then
        return
    end
    self.state.lingerTimer = self:ScheduleTimer(function()
        self.state.lingerTimer = nil
        if self:IsFishingState(ns.Fishing.states.PRECASTING) then
            self:Trace("precast", "Precasting linger duration expired while waiting for action")
            self:EndFishingSession("normally after linger")
        end
    end, duration)
end

function Fishing:StartLinger()
    -- Recasting is allowed while lingering, so hand the hotkey and the secure action back to casting.
    self:ClearBobberInteractOverride()
    self:SetFishingState(ns.Fishing.states.LINGERING, "start linger")
    -- Drop any stale linger timer from a previous cast so it can't end this linger early.
    self:CancelLingerTimer()
    if not (self.db and self.db.profile and self.db.profile.lingerExpirationEnabled) then
        return
    end
    local duration = tonumber(self.db and self.db.profile and self.db.profile.lingerDuration) or 10
    if duration <= 0 then
        return
    end
    self.state.lingerTimer = self:ScheduleTimer(function()
        self.state.lingerTimer = nil
        if self:IsFishingState(ns.Fishing.states.LINGERING) then
            self:EndLinger()
        end
    end, duration)
end

function Fishing:EndLinger()
    if self:IsFishingState(ns.Fishing.states.LINGERING) then
        self:EndFishingSession("normally after linger")
    end
end

-- End the fishing session normally, after linger period
function Fishing:EndFishingSession(reason)
    self.state.fishingSessionGeneration = (self.state.fishingSessionGeneration or 0) + 1
    self.state.suppressPendingBuffFailure = true
    self:CancelLingerTimer()
    self:StopWatchingStrikeKey()
    self:StopMouseButtonWatch()
    self:ClearBobberInteractOverride()
    self:ReleaseClickCapture()
    self:CheckAndEquipUnderlightAngler(reason, true)
    self.state.pendingBuffUse = nil
    self.state.buffDepletionAlerted = nil
    self.state.castStartConfirmationAttempt = nil
    self.state.poleSwapInitiatedAt = nil
    -- Clear any pole-swap lock left over from an interrupted/cancelled cast so the
    -- next cast isn't suppressed into "fishing cast did not start".
    self.state.isEquippingPrimaryPole = false
    -- Restore the click frame to the same baseline a fresh IDLE has, so the next cast
    -- starts from clean conditions rather than whatever transient state a cancel left behind.
    if self.clickFrame and not InCombatLockdown() then
        self.clickFrame:SetAttribute("type", "spell")
        self.clickFrame:SetAttribute("spell", "Fishing")
        self.clickFrame:SetAttribute("macrotext", nil)
        self.clickFrame:SetAttribute("dreamfish_precast_action", nil)
    end
    self:SetFishingState(ns.Fishing.states.IDLE, reason)
end

function Fishing:CancelFishingSession(reason)
    self:SetFishingState(ns.Fishing.states.CANCELLING, reason)
    self:EndFishingSession("cancelled: " .. tostring(reason))
end

function Fishing:OnCombatStarted()
    if not self:IsInFishingSession() then return end
    self:CancelFishingSession("combat started")
end

function Fishing:OnCombatEnded()
    self:UpdateKeybindsAfterCombat()
    self:CheckAndEquipUnderlightAngler("combat ended")
end

function Fishing:OnMovementStarted()
    if not self:IsInFishingSession() then return end
    self:CancelFishingSession("movement started")
end

function Fishing:OnMountDisplayChanged()
    if not self:IsInFishingSession() then return end
    if IsMounted() then
        self:CancelFishingSession("mounted")
    end
end

-- BUTTON2 lives on its own owner frame so it can be released without dropping the hotkey override.
function Fishing:ArmRightClickStrike()
    if InCombatLockdown() or not self.db.profile.strikeByRightClick then return end
    if not self:IsFishingState(ns.Fishing.states.WAITING_FOR_BITE) then return end
    if IsMouseButtonDown("LeftButton") then return end

    if not rightClickStrikeOwner then
        rightClickStrikeOwner = CreateFrame("Frame")
    end
    SetOverrideBinding(rightClickStrikeOwner, true, "BUTTON2", "INTERACTTARGET")
    self:Trace("EasyStrike", "right-click strike armed")
end

-- Overriding BUTTON2 costs the native TURNORACTION binding, so give it back while the player steers.
function Fishing:SuspendRightClickStrike()
    if InCombatLockdown() or not rightClickStrikeOwner then return end
    ClearOverrideBindings(rightClickStrikeOwner)
    self:Trace("EasyStrike", "right-click strike suspended")
end

function Fishing:ConfigureBobberInteractAction()
    local macroLines = {}
    table.insert(macroLines, "/interact")

    self.clickFrame:SetAttribute("type", "macro")
    self.clickFrame:SetAttribute("spell", nil)
    self.clickFrame:SetAttribute("macrotext", table.concat(macroLines, "\n"))
    self:Trace("EasyStrike", "configured secure bobber interaction macro")
end

function Fishing:ArmBobberInteractOverride()
    if InCombatLockdown() or not (self.db.profile.strikeByRightClick or self.db.profile.strikeByHotkey) then
        self:Trace("EasyStrike", "override skipped: combat=" .. tostring(InCombatLockdown())
            .. " rightClick=" .. tostring(self.db.profile.strikeByRightClick)
            .. " hotkey=" .. tostring(self.db.profile.strikeByHotkey))
        return false
    end

    -- arm EasyStrike by overriding the native INTERACTTARGET binding with a secure click on the fishing frame
    local owner = self.clickFrame
    local boundKeys = self:GetKeybindings()

    self:Trace("EasyStrike", "override hotkey1=" .. tostring(boundKeys[1] or "none") .. " hotkey2=" .. tostring(boundKeys[2] or "none"))

    local hotkeyApplied = false
    ClearOverrideBindings(owner)
    -- set up hotkey(s) to interract with the bobber
    if self.db.profile.strikeByHotkey then
        for _, key in ipairs(boundKeys) do
            if key and key ~= "" then
                SetOverrideBinding(owner, true, key, "INTERACTTARGET")
                hotkeyApplied = true
            end
        end
    end
    -- BUTTON2 is armed separately so mouse steering can reclaim it mid-cast.

    local applied = hotkeyApplied or self.db.profile.strikeByRightClick
    if applied then
        if hotkeyApplied then
            self:WatchStrikeKey(boundKeys[1])
        end
        self:SetFishingState(ns.Fishing.states.WAITING_FOR_BITE, "armed bobber interaction override")
        self:ArmRightClickStrike()
    end
    self:Trace("EasyStrike", "native interact override=" .. tostring(applied)
        .. " state=" .. tostring(self.state.current))
    return applied
end

function Fishing:ClearBobberInteractOverride()
    if self.clickFrame and not InCombatLockdown() then
        ClearOverrideBindings(self.clickFrame)
        self:Trace("EasyStrike", "override cleared")
    end
    self:SuspendRightClickStrike()
end

function Fishing:OnSpellCastStarted(event, unit, _, spellID, ...)
    if unit ~= "player" then return end

    -- Log every single spell cast initialization
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or tostring(spellID)
    local liveMacroText = self.clickFrame and self.clickFrame:GetAttribute("macrotext") or "nil"

    self:Trace("auraevent", string.format("OnSpellCastStarted: Spell=%s | State=%s | len(macrotext)=%d",
        spellName, self:CurrentStateName(), #liveMacroText))

    -- A cast bar starting for a queued consumable's spell proves it is not instant-use.
    local pending = self.state.pendingBuffUse
    if type(pending) == "table" and type(pending.uses) == "table" then
        for _, use in ipairs(pending.uses) do
            if tonumber(use.itemSpellID) == tonumber(spellID) or tonumber(use.knownSpellID) == tonumber(spellID) then
                use.castStarted = true
            end
        end
    end
end

function Fishing:OnSpellcastChannelStarted(event, unit, ...)
    if unit ~= "player" then return end

    local _, spellID = ...
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or tostring(spellID)
    local liveMacroText = self.clickFrame and self.clickFrame:GetAttribute("macrotext") or "nil"

    -- Log channel succession confirmations
    self:Trace("auraevent", string.format("OnSpellcastChannelStarted: Spell=%s | State=%s | len(macrotext)=%d",
        spellName, self:CurrentStateName(), #liveMacroText))

    local learning = self.state.buffLearning
    if type(learning) == "table" then
        local pending = self.state.pendingBuffUse
        local pendingItemID = type(pending) == "table" and type(pending.uses) == "table"
            and pending.uses[1] and pending.uses[1].itemID or nil
        Addon:TraceCore("learning", "Spell success: spellID=" .. tostring(spellID)
            .. " name=" .. tostring(spellName)
            .. " learningItemID=" .. tostring(learning.itemID)
            .. " pendingItemID=" .. tostring(pendingItemID))
    end

    if type(self.ConfirmPendingBuffUse) == "function" then
        self:ConfirmPendingBuffUse(spellID)
    end

    if spellID ~= ns.Fishing.const.fishingSpellID then
        return
    end

    self.state.castStartConfirmationAttempt = nil
    self:SetFishingState(ns.Fishing.states.CASTING, "spellcast")
    self:StartMouseButtonWatch()
    self:ReleaseClickCapture()
    self:ConfigureBobberInteractAction()
    self:ArmBobberInteractOverride()
end

function Fishing:OnUIErrorMessage(_, messageType, message)
    local attemptUntil = tonumber(self.state.buffLearningAttemptUntil) or 0
    if type(self.state.buffLearning) == "table" or GetTime() <= attemptUntil then
        Addon:TraceCore("learning", "UI error: type=" .. tostring(messageType)
            .. " message=" .. tostring(message)
            .. " learningItemID=" .. tostring(self.state.buffLearning and self.state.buffLearning.itemID))
    end
end

function Fishing:OnSpellcastChannelEnded(event, unit, ...)
    if unit ~= "player" then
        return
    end
    if not self:IsInFishingSession() then return end

    local _, spellID = ...

    -- If we are already looting or lingering, let those lifecycle states manage the session cleanup.
    local current = self.state.current
    if current == ns.Fishing.states.LOOTING or current == ns.Fishing.states.LINGERING then
        self:Trace("EasyStrike", "Channel stop event ignored; already processing catch cleanup.")
        return
    end

    local isFishingSpell = spellID == ns.Fishing.const.fishingSpellID or spellID == 131476

    if isFishingSpell then
        if current == ns.Fishing.states.PRECASTING then
            self:Trace("EasyStrike", "Channel stop event ignored; cast start is not confirmed yet.")
            return
        end

        self:Trace("EasyStrike", "cast finished event=" .. tostring(event) .. " state=" .. self:CurrentStateName())
        -- Currently, looting happens in CASTING state and if we cancel fishing here, we don't get the loot.
        if (self.state.current == ns.Fishing.states.WAITING_FOR_BITE) then
            -- A right-click strike stops the channel before LOOT_READY arrives, so give the loot window a chance.
            self:ScheduleTimer(function()
                if self:IsFishingState(ns.Fishing.states.WAITING_FOR_BITE) then
                    self:StartLinger()
                end
            end, 0.5)
        elseif (self.state.current == ns.Fishing.states.WAITING_FOR_LOOT_WINDOW) then
            -- The strike landed; looting/linger owns the session end from here.
            self:Trace("EasyStrike", "cast ended with a catch")
        else
            self:Debug("Fishing finished in unexpected state: spellID=" .. tostring(spellID)
                .. " state=" .. (self:CurrentStateName()) )
            self:CancelFishingSession("cast ended for unknown reason")
        end
    end
end

function Fishing:AwaitFishingCastStart()
    local castAttempt = self.state.castAttempt
    if self.state.castStartConfirmationAttempt == castAttempt then
        return
    end

    self.state.castStartConfirmationAttempt = castAttempt
    -- When this cast just performed a pole swap, the fishing channel can't start until the
    -- equipment-swap GCD clears (~1.5s), which can exceed the normal 0.5s confirmation window
    -- and produce a spurious "fishing cast did not start" cancel. Give swap casts a longer window.
    local swappedThisCast = self.state.poleSwapInitiatedAt and (GetTime() - self.state.poleSwapInitiatedAt) < 2
    local confirmDelay = swappedThisCast and 1.6 or 0.5
    self:ScheduleTimer(function()
        if self.state.castStartConfirmationAttempt ~= castAttempt then
            return
        end

        self.state.castStartConfirmationAttempt = nil
        if self:IsFishingState(ns.Fishing.states.PRECASTING)
            and not self.state.pendingBuffUse
            and not self.state.isEquippingPrimaryPole then
            self:CancelFishingSession("fishing cast did not start")
        end
    end, confirmDelay)
end

function Fishing:OnCastStarted(reason)
    self:SetFishingState(ns.Fishing.states.PRECASTING, reason)
    self.state.fishingSessionGeneration = (self.state.fishingSessionGeneration or 0) + 1
    self.state.suppressPendingBuffFailure = false
    -- A new cast supersedes any pending linger from the previous catch.
    self:CancelLingerTimer()

    self.state.castAttempt = (self.state.castAttempt or 0) + 1
    self.state.castStartConfirmationAttempt = nil
    local poleDecision = ns.precast.GetSelectedFishingPoleDecision and ns.precast.GetSelectedFishingPoleDecision()

    -- INSTRUMENTATION: Log the starting state of the secure frame attributes
    local initialMacro = self.clickFrame:GetAttribute("macrotext") or "nil"
    self:Trace("pole", string.format("[OnCastStarted Start] Reason=%s | Initial macrotext length=%d",
        tostring(reason), #initialMacro))

    local isSwapping = false
    if poleDecision and poleDecision.shouldApply and poleDecision.itemID then
        self.state.isEquippingPrimaryPole = true
        if ns.CastBar and type(ns.CastBar.ShowPoleSwap) == "function" then
            ns.CastBar.ShowPoleSwap()
        end
        isSwapping = true
        self.state.poleSwapInitiatedAt = GetTime()
        self:Trace("pole", "Initiating primary fishing pole gear-swap: " .. tostring(poleDecision.itemID))

        -- 1. Fire the instant hardware equipment swap command
        C_Item.EquipItemByName(poleDecision.itemID)

        -- 2. Lock attributes to stopmacro so this specific down-press safely halts casting
        self.clickFrame:SetAttribute("type", "macro")
        self.clickFrame:SetAttribute("macrotext", "/stopmacro")
        self.clickFrame:SetAttribute("spell", nil)

        -- 3. The swap clears via BAG_UPDATE_DELAYED, but that event does not always arrive
        -- (profession-slot swaps don't reliably fire PLAYER_EQUIPMENT_CHANGED, and a fresh
        -- IDLE cast can outpace the bag packet). Add a settling pass so a settled swap still
        -- releases the lock before the 0.5s cast-confirmation guard cancels the session.
        local expectedPoleID = poleDecision.itemID
        self:ScheduleTimer(function()
            if self.state.isEquippingPrimaryPole
                and ns.precast.GetEquippedProfessionItemID
                and ns.precast.GetEquippedProfessionItemID() == expectedPoleID then
                self.state.isEquippingPrimaryPole = false
                if ns.CastBar and type(ns.CastBar.HidePoleSwap) == "function" then
                    ns.CastBar.HidePoleSwap()
                end
                self.clickFrame:SetAttribute("macrotext", "")
                self:PrepareFishingClickAction()
            end
        end, 0.3)
    else
        self.state.isEquippingPrimaryPole = false
        if ns.CastBar and type(ns.CastBar.HidePoleSwap) == "function" then
            ns.CastBar.HidePoleSwap()
        end
    end

    self:CheckEnabledBuffItemsDepleted()

    -- Only run the central macro compiler if an active rod swap isn't forcing a stop block
    if not isSwapping then
        self:PrepareFishingClickAction()
    end

    self:StartMouseButtonWatch()

    -- FIX: Always cleanly anchor your secure hooks and show the window frame container!
    SetOverrideBindingClick(self.clickFrame, true, "BUTTON2", self.clickFrame:GetName(), "RightButton")
    self.clickFrame:Show()
end
