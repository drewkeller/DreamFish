local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local globalDB, profileDB, charDB
ns.FishingInitializers = ns.FishingInitializers or {}
local rightClickStrikeOwner

Fishing:RegisterTraceSource("EasyStrike")
Fishing:RegisterTraceSource("aura")
Fishing:RegisterTraceSource("hotkey")
Fishing:RegisterTraceSource("loot")

function Fishing:OnModuleInitialize()
    -- access the database within "Fishing" functions using self.db
    -- In local functions, use ns.FishingDB
    ns.FishingDB = self.db

    globalDB = ns.FishingDB.global
    profileDB = ns.FishingDB.profile
    charDB = ns.FishingDB.char
    for _, initializerFunc in ipairs(ns.FishingInitializers) do
        initializerFunc(self)
    end
end

function Fishing:OnModuleEnable()
    self:CreateClickFrame()
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
    self:RegisterEvent("LOOT_READY",                   "OnLootReady")
    self:RegisterEvent("LOOT_CLOSED",                  "OnLootClosed")
    --self:RegisterEvent("BAG_UPDATE_DELAYED",           "OnBagUpdateDelayed") -- check bag space
    self:ApplyKeybinding()
    self:PrepareFishingClickAction()
end

function Fishing:OnModuleDisable()
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
    self:UnregisterEvent("LOOT_READY")
    self:UnregisterEvent("LOOT_CLOSED")
    --self:UnregisterEvent("BAG_UPDATE_DELAYED")
    self:RemoveClickFrame()
end

function Fishing:OnBagUpdateDelayed()
    if type(self.ConfirmPendingBuffUse) == "function" then
        self:ConfirmPendingBuffUse()
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
    ns.precast.ConfigureFishingClickAction()
end

function Fishing:OnAurasChanged(event, unit, updateInfo)
    if type(unit) == "string" and unit ~= "player" then
        return
    end
    -- if not self:IsInFishingSession() then
    --     return
    -- end
    -- is this really needed? if outside of fishing session, it gets called constantly
    if self:IsFishingState(ns.fishing.states.IDLE)
        or self:IsFishingState(ns.fishing.states.PRECASTING)
        or self:IsFishingState(ns.fishing.states.LINGERING) then
        self:PrepareFishingClickAction()
    end
    if not updateInfo then
        self:Trace("aura", "OnAurasChanged: no updateInfo provided")
        return
    end
    if updateInfo.isFullUpdate == true then
        self:Trace("aura", "Full aura update detected")
        return
    end

    local hasAddedAuras, hasRemovedAuras = false, false

    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            hasAddedAuras = true
            self:Trace("aura", "Added: " .. tostring(aura.spellId) .. " (" .. tostring(aura.name) .. ")")
        end
    end

    if updateInfo.removedAuras then
        -- if a fishing aura was removed, the bobber may have been looted or despawned (cast finished)
        for _, aura in ipairs(updateInfo.removedAuras) do
            hasRemovedAuras = true
            self:Trace("aura", "Removed: " .. tostring(aura.spellId) .. " (" .. tostring(aura.name) .. ")")
        end
    end

    if not hasAddedAuras and not hasRemovedAuras then
        --self:Trace("aura", "No added or removed auras (existing updated?)")
    end
end

function Fishing:OnEquipmentChanged(event, slotId)
    if slotId == FISHINGTOOLSLOT then
        self:Trace("pole", "Fishing pole changed")
        -- if hotkey cast fishing pole, prepare it again
        if self:IsFishingState(ns.fishing.states.IDLE)
            or self:IsFishingState(ns.fishing.states.PRECASTING)
            or self:IsFishingState(ns.fishing.states.LINGERING) then
            self:PrepareFishingClickAction()
        end
        self:RefreshPoleBorders()
    end
end

function Fishing:OnLootReady(event)
    local current = ns.fishing.state.current
    -- The hotkey strike is a native INTERACTTARGET override, so it produces no click we can hook;
    -- the loot window opening is the only signal that the bobber was struck successfully.
    local isStrikeResult = current == ns.fishing.states.WAITING_FOR_LOOT_WINDOW
        or current == ns.fishing.states.WAITING_FOR_BITE
        or current == ns.fishing.states.BITE_DETECTED
        or current == ns.fishing.states.CASTING

    if isStrikeResult then
        self:Trace("loot", "Loot window ready")
        self:StopWatchingStrikeKey()
        self:SendMessage("FISHING_LOOT_READY")
        self:SetFishingState(ns.fishing.states.LOOTING, "loot window ready")
    end
end

function Fishing:OnLootClosed(event)
    if ns.fishing.state.current == ns.fishing.states.LOOTING then
        self:Trace("loot", "Loot window closed")
        self:SendMessage("FISHING_LOOT_CLOSED")
        self:StartLinger()
    end
end

function Fishing:StartLinger()
    -- Recasting is allowed while lingering, so hand the hotkey and the secure action back to casting.
    self:ClearBobberInteractOverride()
    self:PrepareFishingClickAction()
    self:SetFishingState(ns.fishing.states.LINGERING, "start linger")
    self:ScheduleTimer(function()
        if self:IsFishingState(ns.fishing.states.LINGERING) then
            self:EndLinger()
        end
    end, profileDB.lingerDuration)
end

function Fishing:EndLinger()
    if self:IsFishingState(ns.fishing.states.LINGERING) then
        self:EndFishingSession("normally after linger")
    end
end

-- End the fishing session normally, after linger period
function Fishing:EndFishingSession(reason)
    self:SendMessage("FISHING_SESSION_ENDED")
    self:StopWatchingStrikeKey()
    self:StopMouseButtonWatch()
    self:ClearBobberInteractOverride()
    self:ReleaseClickCapture()
    ns.precast.EquipUnderlightAnglerAfterFishing(reason)
    self:SetFishingState(ns.fishing.states.IDLE, reason)
end

function Fishing:CancelFishingSession(reason)
    self:SetFishingState(ns.fishing.states.CANCELLING, reason)
    self:EndFishingSession("cancelled: " .. tostring(reason))
end

function Fishing:OnCombatStarted()
    if not self:IsInFishingSession() then return end
    self:CancelFishingSession("combat started")
end

function Fishing:OnCombatEnded()
    self:UpdateKeybindsAfterCombat()
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
    if InCombatLockdown() or not profileDB.strikeByRightClick then return end
    if not self:IsFishingState(ns.fishing.states.WAITING_FOR_BITE) then return end
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
    if InCombatLockdown() or not (profileDB.strikeByRightClick or profileDB.strikeByHotkey) then
        self:Trace("EasyStrike", "override skipped: combat=" .. tostring(InCombatLockdown())
            .. " rightClick=" .. tostring(profileDB.strikeByRightClick)
            .. " hotkey=" .. tostring(profileDB.strikeByHotkey))
        return false
    end

    -- arm EasyStrike by overriding the native INTERACTTARGET binding with a secure click on the fishing frame
    local owner = self.clickFrame
    local boundKeys = self:GetKeybindings()

    self:Trace("EasyStrike", "override hotkey1=" .. tostring(boundKeys[1] or "none") .. " hotkey2=" .. tostring(boundKeys[2] or "none"))

    local hotkeyApplied = false
    ClearOverrideBindings(owner)
    -- set up hotkey(s) to interract with the bobber
    if profileDB.strikeByHotkey then
        for _, key in ipairs(boundKeys) do
            if key and key ~= "" then
                SetOverrideBinding(owner, true, key, "INTERACTTARGET")
                hotkeyApplied = true
            end
        end
    end
    -- BUTTON2 is armed separately so mouse steering can reclaim it mid-cast.

    local applied = hotkeyApplied or profileDB.strikeByRightClick
    if applied then
        if hotkeyApplied then
            self:WatchStrikeKey(boundKeys[1])
        end
        self:SetFishingState(ns.fishing.states.WAITING_FOR_BITE, "armed bobber interaction override")
        self:ArmRightClickStrike()
    end
    self:Trace("EasyStrike", "native interact override=" .. tostring(applied)
        .. " state=" .. tostring(ns.fishing.state.current))
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
end

function Fishing:OnSpellcastChannelStarted(event, unit, ...)
    if unit ~= "player" then
        return
    end
    -- Leave this commented so hotkey still works
    --if not self:IsInFishingSession() then return end

    -- args are (castGUID, spellID, ...); some events add extra trailing numeric args, so don't scan for "any number"
    local _, spellID = ...

    if type(self.ConfirmPendingBuffUse) == "function" then
        self:ConfirmPendingBuffUse(spellID)
    end

    if spellID ~= ns.fishing.const.fishingSpellID then
        --Fishing:Trace("aura", "Spellcast channel started for non-fishing spellID=" .. tostring(spellID))
        return
    end

    self:SetFishingState(ns.fishing.states.CASTING, "spellcast")
    -- The bobber can splash at any point during the channel and there's no event for it;
    -- the player has to watch for it, so the strike action must be ready for the whole cast.
    self:StartMouseButtonWatch()
    self:ConfigureBobberInteractAction()
    self:ArmBobberInteractOverride()
end

function Fishing:OnSpellcastChannelEnded(event, unit, ...)
    if unit ~= "player" then
        return
    end
    if not self:IsInFishingSession() then return end

    local _, spellID = ...

    local isFishingSpell = spellID == ns.fishing.const.fishingSpellID or spellID == 131476

    if isFishingSpell then
        self:Trace("EasyStrike", "cast finished event=" .. tostring(event) .. " state=" .. self:CurrentStateName())
        -- Currently, looting happens in CASTING state and if we cancel fishing here, we don't get the loot.
        if (ns.fishing.state.current == ns.fishing.states.WAITING_FOR_BITE) then
            -- A last-moment strike stops the channel before LOOT_READY arrives, so give the loot window a chance.
            self:ScheduleTimer(function()
                if self:IsFishingState(ns.fishing.states.WAITING_FOR_BITE) then
                    self:CancelFishingSession("cast ended without a catch")
                end
            end, 0.5)
        elseif (ns.fishing.state.current == ns.fishing.states.WAITING_FOR_LOOT_WINDOW)
            or (ns.fishing.state.current == ns.fishing.states.LOOTING)
            or (ns.fishing.state.current == ns.fishing.states.LINGERING) then
            -- The strike landed; looting/linger owns the session end from here.
            self:Trace("EasyStrike", "cast ended with a catch")
        else
            self:Debug("Fishing finished in unexpected state: spellID=" .. tostring(spellID)
                .. " state=" .. (self:CurrentStateName()) )
            self:CancelFishingSession("cast ended for unknown reason")
        end
    end
end

function Fishing:OnCastStarted(reason)
    self:SetFishingState(ns.fishing.states.PRECASTING, reason)
    self:SendMessage("FISHING_CAST_STARTED")
    self:PrepareFishingClickAction()
    self:StartMouseButtonWatch()

    -- Set the secure action to trigger on right-clicks of the secure frame.
    -- The secure frame is shown when the player right-clicks, so the current click release will trigger the secure action.
    SetOverrideBindingClick(self.clickFrame, true, "BUTTON2", self.clickFrame:GetName(), "RightButton")
    -- Show the secure frame so the current click release can trigger the secure action.
    self.clickFrame:Show()
end

ns.precast.ConfigureFishingClickAction = ConfigureFishingClickAction
