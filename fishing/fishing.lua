local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local globalDB, profileDB, charDB
ns.FishingInitializers = ns.FishingInitializers or {}
local interactOverrideFrame

Fishing:RegisterTraceSource("EasyStrike")

function Fishing:OnModuleInitialize()
	self:Debug("Initializing")
    -- access the database within "Fishing" functions using self.db
    -- In local functions, use ns.FishingDB
    ns.FishingDB = self.db

    globalDB = ns.FishingDB.global
    profileDB = ns.FishingDB.profile
    charDB = ns.FishingDB.char
    for _, initializerFunc in ipairs(ns.FishingInitializers) do
        initializerFunc(self)
    end

    self.hotkey = profileDB.castHotkeyKeybind
end

function Fishing:OnModuleEnable()
    self:RegisterTackleWindowTab()
    self:CreateClickFrame()
    self:RegisterEvent("PLAYER_REGEN_ENABLED",         "UpdateKeybindsAfterCombat")
    self:RegisterEvent("PLAYER_REGEN_DISABLED",        "CancelFishingForCombat")
    self:RegisterEvent("PLAYER_STARTED_MOVING",        "CancelFishingForMovement")
    self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", "CancelFishingForMount")
    self:RegisterEvent("UNIT_SPELLCAST_START",         "HandleFishingSpellcast")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "HandleFishingSpellcast")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED",     "HandleFishingSpellcast")
    self:RegisterEvent("UNIT_SPELLCAST_STOP",          "HandleFishingSpellcastFinished")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP",  "HandleFishingSpellcastFinished")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED",     "OnEquipmentChanged")
    self:RegisterEvent("UNIT_AURA",                    "OnAurasChanged")
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
    self:UnregisterEvent("UNIT_AURA")
    self:UnregisterEvent("LOOT_READY")
    self:UnregisterEvent("LOOT_CLOSED")
    --self:UnregisterEvent("BAG_UPDATE_DELAYED")
    self:Debug("Removing click frame (module disabled)")
    self:RemoveClickFrame()
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
    if ns.fishing.state.current == ns.fishing.states.IDLE then
        self:PrepareFishingClickAction()
    end
    if not updateInfo then
        self:Debug("OnAurasChanged: no updateInfo provided")
        return
    end
    if updateInfo.isFullUpdate == true then
        self:Debug("Full aura update detected")
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
        self:Debug("No known fishing aura changes detected")
    end
end

function Fishing:OnEquipmentChanged(event, unit)
    if type(unit) == "string" and unit ~= "player" then
        return
    end
    if ns.fishing.state.current == ns.fishing.states.IDLE then
        self:PrepareFishingClickAction()
    end
    self:RefreshPoleBorders()
    self:Debug("Equipment changed")
end

function Fishing:CancelFishingSession(reason)
    self:SetFishingState(ns.fishing.states.CANCELLING, reason)
    self:ClearBobberInteractOverride()
    self:ReleaseClickCapture()
    ns.precast.EquipUnderlightAnglerAfterFishing(reason)
    self:SetFishingState(ns.fishing.states.IDLE, "After cancel: " .. tostring(reason))
end

function Fishing:CancelFishingForCombat()
    self:CancelFishingSession("combat")
end

function Fishing:CancelFishingForMovement()
    self:CancelFishingSession("movement")
end

function Fishing:CancelFishingForMount()
    if IsMounted() then
        self:CancelFishingSession("mounted")
    end
end

function Fishing:ClearBobberInteractOverride()
    if interactOverrideFrame and not InCombatLockdown() then
        ClearOverrideBindings(interactOverrideFrame)
        self:Trace("EasyStrike", "override cleared")
    end
end

function Fishing:ArmBobberInteractOverride()
    if InCombatLockdown() or not profileDB.easyStrike then
        self:Trace("EasyStrike", "override skipped: combat=" .. tostring(InCombatLockdown())
            .. " enabled=" .. tostring(profileDB.easyStrike))
        return false
    end

    -- arm EasyStrike by overriding the native INTERACTTARGET binding with a secure click on the fishing frame
    --local owner = GetInteractOverrideFrame()
    local owner = self.clickFrame
    local boundKeys = { self.hotkey or profileDB.castHotkeyKeybind }
    if not boundKeys[1] or boundKeys[1] == "" then
        boundKeys = { GetBindingKey("CLICK DreamFishSecureFishingFrame:RightButton") }
    end

    self:Trace("EasyStrike", "override hotkey1=" .. tostring(boundKeys[1] or "none") .. " hotkey2=" .. tostring(boundKeys[2] or "none"))

    local applied = false
    ClearOverrideBindings(owner)
    -- set up hotkey(s) to interract with the bobber
    for _, key in ipairs(boundKeys) do
        if key and key ~= "" then
            SetOverrideBinding(owner, true, key, "INTERACTTARGET")
            applied = true
        end
    end
    -- set up right click to interract
    SetOverrideBinding(owner, true, "BUTTON2", "INTERACTTARGET")

    if applied then
        self:SetFishingState(ns.fishing.states.WAITING_FOR_BITE, "armed bobber interaction override")
    end
    self:Trace("EasyStrike", "native interact override=" .. tostring(applied)
        .. " state=" .. tostring(ns.fishing.state.current))
    return applied
end

function Fishing:HandleFishingSpellcast(event, unit, ...)
    if unit ~= "player" then
        return
    end

    -- args are (castGUID, spellID, ...); some events add extra trailing numeric args, so don't scan for "any number"
    local _, spellID = ...

    if spellID ~= ns.fishing.const.fishingSpellID then
        return
    end

    self:SetFishingState(ns.fishing.states.CASTING, "spellcast")
    -- The bobber can splash at any point during the channel and there's no event for it;
    -- the player has to watch for it, so the strike action must be ready for the whole cast.
    self:ConfigureBobberInteractAction()
    self:ArmBobberInteractOverride()
end

function Fishing:HandleFishingSpellcastFinished(event, unit, ...)
    if unit ~= "player" then
        return
    end

    self:Debug(event .. " detected for Fishing spellcast finished")

    -- args are (castGUID, spellID, ...); some events add extra trailing numeric args, so don't scan for "any number"
    local _, spellID = ...

    local isFishingSpell = spellID == ns.fishing.const.fishingSpellID or spellID == 131476

    if isFishingSpell then
        -- Currently, looting happens in CASTING state and if we cancel fishing here, we don't get the loot.
        if (ns.fishing.state.current == ns.fishing.states.PRECASTING
            or ns.fishing.state.current == ns.fishing.states.CASTING) then
            -- The channel ended without the player striking a bobber splash (no catch); cancel and let them recast.
            self:CancelFishingSession("cast ended without a catch (or looted in ambiguous state?)")
        -- else
        --     self:Debug("Fishing finished ignored: spellID=" .. tostring(spellID)
        --         .. " state=" .. tostring(ns.fishing.state.current))
        --     self:CancelFishingSession("cast ended for unknown reason")
        end
    else
        self:Debug("Non-fishing spell? spellID=" .. tostring(spellID)
            .. " state=" .. tostring(ns.fishing.state.current))
    end
end

function Fishing:ConfigureBobberInteractAction()
    local macroLines = {}
    -- local selectedBobberToy = tonumber(self.db.profile.selectedBobberToy)
    -- local selectedBobberName = selectedBobberToy and C_Item.GetItemInfo(selectedBobberToy)
    -- if selectedBobberName then
    --     table.insert(macroLines, "/targetexact " .. selectedBobberName)
    -- end
    -- table.insert(macroLines, "/targetexact Fishing Bobber")
    table.insert(macroLines, "/interact")

    self.clickFrame:SetAttribute("type", "macro")
    self.clickFrame:SetAttribute("spell", nil)
    self.clickFrame:SetAttribute("macrotext", table.concat(macroLines, "\n"))
    self:Trace("EasyStrike", "configured secure bobber interaction macro")
end

function Fishing:HandleBobberInteraction(reason)
    self:Trace("EasyStrike", "------------------- HandleBobberInteraction: input=" .. tostring(reason)
        .. " state=" .. tostring(ns.fishing.state.current)
        .. " enabled=" .. tostring(profileDB.easyStrike))
    -- The player watches the bobber and strikes whenever it splashes, so any point during the cast is valid.
    local isInStateForStrike = ns.fishing.state.current == ns.fishing.states.WAITING_FOR_BITE
    if not isInStateForStrike or InCombatLockdown() then
        self:Debug("----------------- Bobber interaction ignored (state: " .. tostring(ns.fishing.state.current) .. ", combat: " .. tostring(InCombatLockdown()) .. ")")
        return false
    end

    self:Trace("EasyStrike", "------------------ Bobber interaction attempted: " .. tostring(reason))
    -- The macro/override were already configured once when casting started; don't reconfigure on every trigger.
    self:Trace("EasyStrike", "-------------------- Clearing bobber interaction override")
    self:ClearBobberInteractOverride()
    self:SetFishingState(ns.fishing.states.WAITING_FOR_LOOT_WINDOW, reason)
    -- looting is not implemented yet, go directly to IDLE
    --self:SetFishingState(ns.fishing.states.IDLE, "Looting not implemented")
    return true
end

function Fishing:OnCastStarted(reason)
    self:SetFishingState(ns.fishing.states.PRECASTING, reason)
    self:SendMessage("FISHING_CAST_STARTED")
    self:PrepareFishingClickAction()
    self:Debug("OnCastStarted: " .. tostring(reason))

    -- Set the secure action to trigger on right-clicks of the secure frame.
    -- The secure frame is shown when the player right-clicks, so the current click release will trigger the secure action.
    SetOverrideBindingClick(self.clickFrame, true, "BUTTON2", self.clickFrame:GetName(), "RightButton")
    -- Show the secure frame so the current click release can trigger the secure action.
    self.clickFrame:Show()
end

ns.precast.ConfigureFishingClickAction = ConfigureFishingClickAction
