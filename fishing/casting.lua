-- DreamFisher: Fishing Casting and World Right-Click Handler

local addon = _G["DreamFisher"]
local PrintMessage = addon.PrintMessage
local DebugMessage = addon.DebugMessage
local DebugStateMessage = addon.DebugStateMessage or addon.DebugMessage
local requireFishingAPI = addon.RequireFishingAPI
-- Warning cue helpers remain optional so casting flow never hard-depends on audio module wiring.
local getAudioAPI = addon.GetAudioAPI
local OVERSIZED_BOBBER_ITEM_ID = 202207
local DUE_BUFF_CATEGORY_ORDER = { "food_drink", "lure", "bait", "bobber", "other_consumable" }

local ConfigureFishingClickAction
local GetNextReadyDueBuffItem
local GetNextCastableDueBuffItem

local function IsBuffDebugEnabled()
    return addon.db and addon.db.debugMode and addon.db.debugBuffs
end

local function DebugBuffMessage(message)
    if IsBuffDebugEnabled() then
        DebugMessage(message)
    end
end

local function GetDebugItemLabel(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return "unknown"
    end
    local name = (type(GetItemInfo) == "function" and GetItemInfo(numeric)) or nil
    if name and name ~= "" then
        return tostring(name) .. " (" .. tostring(numeric) .. ")"
    end
    return "item:" .. tostring(numeric)
end

local function GetDebugCooldownText(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 or type(GetItemCooldown) ~= "function" then
        return "cooldown=unknown"
    end

    local start, duration, enabled = GetItemCooldown(numeric)
    if not enabled or enabled == 0 then
        return "cooldown=disabled"
    end
    if not start or not duration or duration <= 0 then
        return "cooldown=ready"
    end

    local remaining = math.max(0, (start + duration) - GetTime())
    return "cooldownRemaining=" .. string.format("%.1fs", remaining)
end

local function IsItemReadyForUse(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return false
    end
    if type(GetItemCooldown) ~= "function" then
        return true
    end

    local start, duration, enabled = GetItemCooldown(numeric)
    if enabled == 0 then
        return false
    end
    if not start or not duration then
        return true
    end
    if duration <= 0 then
        return true
    end

    local remaining = (start + duration) - GetTime()
    return remaining <= 0.05
end

local function GetBobberUseDecision()
    local function GetBobberAuraRemainingSeconds(bobberToyID)
        if not (addon.buff and addon.buff.GetAuraBySpellID) then
            return nil
        end

        local known = addon.const
            and type(addon.const.knownBuffItems) == "table"
            and addon.const.knownBuffItems[tonumber(bobberToyID)]
            or nil
        local bobberSpellID = type(known) == "table" and tonumber(known.spellID) or nil
        if not bobberSpellID or bobberSpellID <= 0 then
            return nil
        end

        local aura = addon.buff.GetAuraBySpellID(bobberSpellID)
        if not aura or not aura.expirationTime or aura.expirationTime <= 0 then
            return nil
        end

        return math.max(0, aura.expirationTime - GetTime())
    end

    local bobberToyID = addon.db and tonumber(addon.db.selectedBobberToy) or nil
    local hasToy = (bobberToyID and bobberToyID > 0)
        and (type(PlayerHasToy) ~= "function" or PlayerHasToy(bobberToyID))
    local bobberReady = hasToy and IsItemReadyForUse(bobberToyID)
    local bobberAuraRemaining = hasToy and GetBobberAuraRemainingSeconds(bobberToyID) or nil
    local castLead = (addon.const and addon.const.maxFishingCastSeconds or 20)
        + (addon.const and addon.const.buffPreRefreshSafetySeconds or 2)
    local needsRefreshForCast = (bobberAuraRemaining == nil) or (bobberAuraRemaining <= castLead)
    local mounted = (type(IsMounted) == "function" and IsMounted()) or false
    local swimming = (type(IsSwimming) == "function" and IsSwimming()) or false
    local shouldApply = hasToy and bobberReady and needsRefreshForCast and not mounted and not swimming

    return {
        toyID = bobberToyID,
        hasToy = hasToy,
        ready = bobberReady,
        auraRemaining = bobberAuraRemaining,
        needsRefreshForCast = needsRefreshForCast,
        mounted = mounted,
        swimming = swimming,
        shouldApply = shouldApply,
    }
end

local function GetRaftUseDecision()
    local function GetRaftAuraRemainingSeconds(raftToyID)
        if type(GetItemSpell) ~= "function" or not (addon.buff and addon.buff.GetAuraBySpellID) then
            return nil
        end

        local _, raftSpellID = GetItemSpell(raftToyID)
        if not raftSpellID then
            return nil
        end

        local aura = addon.buff.GetAuraBySpellID(raftSpellID)
        if not aura or not aura.expirationTime or aura.expirationTime <= 0 then
            return nil
        end

        return math.max(0, aura.expirationTime - GetTime())
    end

    local raftToyID = addon.db and tonumber(addon.db.selectedRaftToy) or nil
    local hasToy = (raftToyID and raftToyID > 0)
        and (type(PlayerHasToy) ~= "function" or PlayerHasToy(raftToyID))
    local raftReady = hasToy and IsItemReadyForUse(raftToyID)
    local swimming = (type(IsSwimming) == "function" and IsSwimming()) or false
    local raftAuraRemaining = (hasToy and swimming) and GetRaftAuraRemainingSeconds(raftToyID) or nil
    local castLead = (addon.const and addon.const.maxFishingCastSeconds or 20)
        + (addon.const and addon.const.buffPreRefreshSafetySeconds or 2)
    if raftAuraRemaining == nil and hasToy then
        -- If aura can't be observed while not swimming, try once more without the swim gate.
        raftAuraRemaining = GetRaftAuraRemainingSeconds(raftToyID)
    end
    local needsRefreshForCast = (raftAuraRemaining == nil) or (raftAuraRemaining <= castLead)
    local shouldApply = hasToy
        and raftReady
        and needsRefreshForCast
        and (swimming or raftAuraRemaining ~= nil)

    return {
        toyID = raftToyID,
        hasToy = hasToy,
        ready = raftReady,
        swimming = swimming,
        auraRemaining = raftAuraRemaining,
        needsRefreshForCast = needsRefreshForCast,
        shouldApply = shouldApply,
    }
end

local function GetOversizedBobberDecision()
    local function GetOversizedBobberAuraRemainingSeconds()
        if not (addon.buff and addon.buff.GetAuraBySpellID) then
            return nil
        end

        local known = addon.const
            and type(addon.const.knownBuffItems) == "table"
            and addon.const.knownBuffItems[OVERSIZED_BOBBER_ITEM_ID]
            or nil
        local oversizedSpellID = type(known) == "table" and tonumber(known.spellID) or nil
        if not oversizedSpellID or oversizedSpellID <= 0 then
            return nil
        end

        local aura = addon.buff.GetAuraBySpellID(oversizedSpellID)
        if not aura or not aura.expirationTime or aura.expirationTime <= 0 then
            return nil
        end

        return math.max(0, aura.expirationTime - GetTime())
    end

    local shouldUse = addon.db and addon.db.useOversizedBobber
    if not shouldUse then
        return {
            enabled = false,
            ready = false,
            available = false,
        }
    end

    local available = (type(PlayerHasToy) ~= "function") or PlayerHasToy(OVERSIZED_BOBBER_ITEM_ID)
    local ready = available and IsItemReadyForUse(OVERSIZED_BOBBER_ITEM_ID)
    local auraRemaining = available and GetOversizedBobberAuraRemainingSeconds() or nil
    local castLead = (addon.const and addon.const.maxFishingCastSeconds or 20)
        + (addon.const and addon.const.buffPreRefreshSafetySeconds or 2)
    local needsRefreshForCast = (auraRemaining == nil) or (auraRemaining <= castLead)
    local swimming = (type(IsSwimming) == "function" and IsSwimming()) or false
    local shouldApply = ready and needsRefreshForCast and not swimming

    return {
        enabled = true,
        available = available,
        ready = ready,
        auraRemaining = auraRemaining,
        needsRefreshForCast = needsRefreshForCast,
        swimming = swimming,
        shouldApply = shouldApply,
    }
end

local function HasConfiguredBuffItems()
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return false
    end
    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
        if itemID and itemID > 0 and not (type(entry) == "table" and entry.enabled == false) then
            return true
        end
    end
    return false
end

local function HasAnyActiveBaitAura()
    if not (addon.buff and type(addon.buff.GetAuraBySpellID) == "function") then
        return false
    end
    if not (addon.const and type(addon.const.knownBuffItems) == "table") then
        return false
    end

    for _, known in pairs(addon.const.knownBuffItems) do
        local category = type(known) == "table" and known.category or nil
        local spellID = type(known) == "table" and tonumber(known.spellID) or nil
        if category == "bait" and spellID and spellID > 0 then
            local aura = addon.buff.GetAuraBySpellID(spellID)
            if aura and aura.expirationTime and aura.expirationTime > 0 then
                return true
            end
        end
    end

    return false
end

local function ResetFishingFrameState(frame)
    if not frame then
        return
    end
    frame:SetAttribute("type", nil)
    frame:SetAttribute("type1", nil)
    frame:SetAttribute("type2", nil)
    frame:SetAttribute("spell", nil)
    frame:SetAttribute("spell1", nil)
    frame:SetAttribute("spell2", nil)
    frame:SetAttribute("item", nil)
    frame:SetAttribute("item1", nil)
    frame:SetAttribute("item2", nil)
    frame:SetAttribute("toy", nil)
    frame:SetAttribute("toy1", nil)
    frame:SetAttribute("toy2", nil)
    frame:SetAttribute("macrotext", nil)
    frame:SetAttribute("macrotext1", nil)
    frame:SetAttribute("macrotext2", nil)
    frame:SetAttribute("dreamfisher_castarmed", nil)
end

local function ResetBuffFrameState(frame)
    if not frame then
        return
    end
    frame:SetAttribute("dreamfisher_itemid", nil)
    frame:SetAttribute("type", nil)
    frame:SetAttribute("type1", nil)
    frame:SetAttribute("type2", nil)
    frame:SetAttribute("spell", nil)
    frame:SetAttribute("spell1", nil)
    frame:SetAttribute("spell2", nil)
    frame:SetAttribute("item", nil)
    frame:SetAttribute("item1", nil)
    frame:SetAttribute("item2", nil)
    frame:SetAttribute("toy", nil)
    frame:SetAttribute("toy1", nil)
    frame:SetAttribute("toy2", nil)
    frame:SetAttribute("macrotext", nil)
    frame:SetAttribute("macrotext1", nil)
    frame:SetAttribute("macrotext2", nil)
end

local function CreateSecureFishingFrame()
    if addon.frames.fishing then
        return addon.frames.fishing
    end

    local frame = CreateFrame("Button", "DreamFisherSecureFishingButton", UIParent, "SecureActionButtonTemplate")
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
    ResetFishingFrameState(frame)
    -- Use down-edge only so a single key press triggers one secure action.
    if frame.RegisterForClicks then
        frame:RegisterForClicks("AnyDown")
    end
    -- Keybinding click targets should remain visible to be reliably clickable.
    frame:Show()
    frame:HookScript("PreClick", function()
        if InCombatLockdown() then
            return
        end
        local now = (type(GetTime) == "function") and GetTime() or 0
        local lastConfiguredAt = tonumber(addon.state and addon.state.lastFishingClickConfigAt) or 0
        if lastConfiguredAt > 0 and (now - lastConfiguredAt) < 0.05 then
            return
        end
        if ConfigureFishingClickAction then
            ConfigureFishingClickAction()
        end
    end)
    frame:HookScript("OnClick", function()
        local actionType = tostring(frame:GetAttribute("type") or "nil")
        local spell = tostring(frame:GetAttribute("spell") or "nil")
        local dueBuff = tostring(frame:GetAttribute("dreamfisher_duebuff") or "")
        local dueBuffItemID = tonumber(dueBuff)
        local macrotext = tostring(frame:GetAttribute("macrotext") or "")
        if macrotext ~= "" then
            local firstLine, secondLine = macrotext:match("([^\n]+)\n([^\n]+)")
            if firstLine and secondLine then
                DebugMessage("Fishing secure click fired: type=" .. actionType
                    .. " macro=" .. tostring(firstLine) .. " | " .. tostring(secondLine))
            else
                local onlyLine = macrotext:match("([^\n]+)") or macrotext
                DebugMessage("Fishing secure click fired: type=" .. actionType .. " macro=" .. tostring(onlyLine))
            end
        else
            DebugMessage("Fishing secure click fired: type=" .. actionType .. " spell=" .. spell)
        end
        if actionType ~= "nil" and addon.state then
            addon.state.lastFishingSecureClickAt = (type(GetTime) == "function") and GetTime() or 0
        end
        if dueBuffItemID and dueBuffItemID > 0 and addon.state and addon.buff then
            local now = (type(GetTime) == "function") and GetTime() or 0
            addon.state.buffItemLastUseAt[dueBuffItemID] = now
            if type(addon.buff.BuildHelpfulAuraSnapshot) == "function" then
                addon.state.pendingBuffObservation = {
                    itemID = dueBuffItemID,
                    before = addon.buff.BuildHelpfulAuraSnapshot(),
                    expiresAt = now + 20,
                }
            end
        end
        if not InCombatLockdown() then
            -- Right-click override path still uses this frame.
            ClearOverrideBindings(frame)
        end
        ResetFishingFrameState(frame)
        frame:SetAttribute("dreamfisher_duebuff", nil)
    end)

    addon.frames.fishing = frame
    return addon.frames.fishing
end

local function CreateSecureBuffFrame()
    if addon.frames.buff then
        return addon.frames.buff
    end

    local frame = CreateFrame("Button", "DreamFisherSecureBuffButton", UIParent, "SecureActionButtonTemplate")
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
    ResetBuffFrameState(frame)
    if frame.RegisterForClicks then
        frame:RegisterForClicks("AnyDown")
    end
    frame:Hide()
    frame:HookScript("OnClick", function(self)
        local itemID = tonumber(self:GetAttribute("dreamfisher_itemid"))
        local macrotext = tostring(self:GetAttribute("macrotext") or self:GetAttribute("macrotext2") or "")
        DebugMessage("Secure buff click fired: item=" .. GetDebugItemLabel(itemID)
            .. " item=" .. tostring(self:GetAttribute("item"))
            .. " item2=" .. tostring(self:GetAttribute("item2"))
            .. " macro=" .. tostring(macrotext:match("([^\n]+)") or ""))
        if itemID and itemID > 0 then
            local now = GetTime()
            addon.state.buffItemLastUseAt[itemID] = now
            addon.state.pendingBuffObservation = {
                itemID = itemID,
                before = addon.buff.BuildHelpfulAuraSnapshot(),
                expiresAt = now + 20,
            }
            addon.buff.AnnounceBuffUse(itemID)
        end
        ResetBuffFrameState(self)
        self:Hide()
        if not InCombatLockdown() then
            ClearOverrideBindings(self)
        end
    end)

    addon.frames.buff = frame
    return addon.frames.buff
end

local function ApplySelectedBobberToy()
    -- Bobber usage is applied via secure fishing macro configuration per click.
    return false
end

local function ApplySelectedRaftToy()
    -- Slash-command toy usage is protected; use secure UI buttons for manual toy use.
    return false
end

local function IsLureCategory(category)
    return category == "lure"
end

local function IsFishingPoleEquippedInProfessionSlot()
    if type(GetInventoryItemID) ~= "function" then
        return true
    end

    -- Some clients can return no values; capture first to avoid calling tonumber()
    -- with zero arguments.
    local ok, rawItemID = pcall(GetInventoryItemID, "player", 28)
    if not ok then
        return false
    end
    if rawItemID == nil then
        return false
    end

    local itemID = tonumber(rawItemID)
    return itemID and itemID > 0 or false
end

local function GetEquippedProfessionItemID()
    if type(GetInventoryItemID) ~= "function" then
        return nil
    end
    local ok, rawItemID = pcall(GetInventoryItemID, "player", 28)
    if not ok then
        return nil
    end
    local itemID = tonumber(rawItemID)
    if not itemID or itemID <= 0 then
        return nil
    end
    return itemID
end

local function IsItemEquippedInAnyTrackedSlot(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 or type(GetInventoryItemID) ~= "function" then
        return false
    end

    local maxSlot = (type(INVSLOT_LAST_EQUIPPED) == "number" and INVSLOT_LAST_EQUIPPED) or 19
    if maxSlot < 40 then
        maxSlot = 40
    end
    for slot = 1, maxSlot do
        local ok, rawItemID = pcall(GetInventoryItemID, "player", slot)
        if ok and tonumber(rawItemID) == numeric then
            return true
        end
    end

    return false
end

local function IsItemAvailableForEquip(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return false
    end

    if IsItemEquippedInAnyTrackedSlot(numeric) then
        return true
    end

    if addon.buff and addon.buff.FindItemInBags then
        local bag, slot = addon.buff.FindItemInBags(numeric)
        if bag and slot then
            return true
        end
    end

    return false
end

local function IsUnderlightAnglerItemID(itemID)
    local underlightID = addon.const and tonumber(addon.const.underlightAnglerItemID) or 133755
    return tonumber(itemID) == underlightID
end

local function NormalizeLegacyPoleMode(mode)
    local modeText = type(mode) == "string" and mode or ""
    if modeText == "disabled" or modeText == "always_except_fishing" or modeText == "lock_underlight" then
        return modeText
    end
    return "disabled"
end

local function NormalizePoleSelection(value, validateItemID)
    local itemID = nil
    local isChecked = false

    if type(value) == "table" then
        itemID = tonumber(value.itemID)
        isChecked = value.isChecked ~= false
    else
        itemID = tonumber(value)
        isChecked = itemID ~= nil
    end

    if not itemID or itemID <= 0 then
        itemID = nil
    end
    if itemID and validateItemID and (not validateItemID(itemID)) then
        itemID = nil
    end
    if not itemID then
        isChecked = false
    end

    return {
        itemID = itemID,
        isChecked = isChecked and true or false,
    }
end

local function GetConfiguredPoleSelections()
    local primary = NormalizePoleSelection(addon.db and addon.db.selectedFishingPole)
    local underlight = NormalizePoleSelection(addon.db and addon.db.selectedUnderlightAngler, IsUnderlightAnglerItemID)

    local hasStructuredPrimary = type(addon.db and addon.db.selectedFishingPole) == "table"
    local hasStructuredUnderlight = type(addon.db and addon.db.selectedUnderlightAngler) == "table"
    if (not hasStructuredPrimary) and (not hasStructuredUnderlight) then
        local legacyMode = NormalizeLegacyPoleMode(addon.db and addon.db.underlightAnglerMode)
        if legacyMode == "lock_underlight" then
            primary.isChecked = false
            underlight.isChecked = underlight.itemID ~= nil
        elseif legacyMode == "always_except_fishing" then
            primary.isChecked = primary.itemID ~= nil
            underlight.isChecked = underlight.itemID ~= nil
        else
            primary.isChecked = primary.itemID ~= nil
            underlight.isChecked = false
        end
    end

    return {
        primary = primary,
        underlight = underlight,
    }
end

local function GetWaterContextDiagnostics()
    local diagnostics = {
        isSwimming = false,
        isSubmerged = false,
        secureOption = nil,
        source = nil,
        result = false,
    }

    if type(IsSwimming) == "function" and IsSwimming() then
        diagnostics.isSwimming = true
        diagnostics.source = "IsSwimming"
        diagnostics.result = true
        return diagnostics
    end

    if type(IsSubmerged) == "function" and IsSubmerged() then
        diagnostics.isSubmerged = true
        diagnostics.source = "IsSubmerged"
        diagnostics.result = true
        return diagnostics
    end

    return diagnostics
end

local function IsPlayerInWaterContext()
    return GetWaterContextDiagnostics().result
end

local function GetSelectedFishingPoleDecision()
    local selections = GetConfiguredPoleSelections()
    local poleItemID = selections.primary.itemID
    local hasItem = IsItemAvailableForEquip(poleItemID)
    local mounted = (type(IsMounted) == "function" and IsMounted()) or false
    local equippedItemID = GetEquippedProfessionItemID()
    local alreadyEquipped = poleItemID and equippedItemID and (poleItemID == equippedItemID) or false
    local shouldApply = hasItem
        and selections.primary.isChecked
        and (not mounted)
        and (not alreadyEquipped)

    return {
        itemID = poleItemID,
        hasItem = hasItem,
        mounted = mounted,
        alreadyEquipped = alreadyEquipped,
        shouldApply = shouldApply,
    }
end

local function TryEquipItemToProfessionSlot(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        DebugMessage("Pole equip skipped: invalid itemID=" .. tostring(itemID))
        return false
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false
    end

    if IsItemEquippedInAnyTrackedSlot(numeric) then
        DebugMessage("Pole equip skipped: item already equipped " .. GetDebugItemLabel(numeric))
        return true
    end

    local itemRef = "item:" .. tostring(numeric)
    local equipRequestDispatched = false
    local lastDispatchedMethod = nil

    local function IsNowEquipped()
        return IsItemEquippedInAnyTrackedSlot(numeric)
    end

    local function TryEquipFromBagCursor(targetSlot)
        if not (addon.buff and addon.buff.FindItemInBags) then
            return false
        end

        local bag, slot = addon.buff.FindItemInBags(numeric)
        if bag == nil or slot == nil then
            return false
        end

        local pickupFn = nil
        if C_Container and type(C_Container.PickupContainerItem) == "function" then
            pickupFn = C_Container.PickupContainerItem
        elseif type(PickupContainerItem) == "function" then
            pickupFn = PickupContainerItem
        end

        if type(pickupFn) ~= "function" or type(EquipCursorItem) ~= "function" then
            if type(EquipItemByName) == "function" then
                local okFallback = pcall(EquipItemByName, itemRef, targetSlot)
                equipRequestDispatched = equipRequestDispatched or okFallback
                if okFallback then
                    lastDispatchedMethod = "cursor-fallback:EquipItemByName:slot" .. tostring(targetSlot)
                    if IsNowEquipped() then
                        DebugMessage("Pole equip succeeded via " .. tostring(lastDispatchedMethod)
                            .. " " .. GetDebugItemLabel(numeric))
                        return true
                    end
                end
            end
            return false
        end

        local okPickup = pcall(pickupFn, bag, slot)
        if not okPickup then
            if type(ClearCursor) == "function" then
                pcall(ClearCursor)
            end
            return false
        end

        local okEquip = pcall(EquipCursorItem, targetSlot)
        if not okEquip then
            if type(ClearCursor) == "function" then
                pcall(ClearCursor)
            end
            return false
        end
        equipRequestDispatched = true
        lastDispatchedMethod = "bag-cursor:slot" .. tostring(targetSlot)

        if type(ClearCursor) == "function" then
            pcall(ClearCursor)
        end

        if IsNowEquipped() then
            DebugMessage("Pole equip succeeded via " .. tostring(lastDispatchedMethod)
                .. " " .. GetDebugItemLabel(numeric))
            return true
        end

        return false
    end

    if TryEquipFromBagCursor(28) then
        return true
    end

    if TryEquipFromBagCursor(16) then
        return true
    end

    if equipRequestDispatched then
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.1, function()
                if IsNowEquipped() then
                    DebugMessage("Pole equip completed on delayed verify via "
                        .. tostring(lastDispatchedMethod or "unknown") .. ": " .. GetDebugItemLabel(numeric))
                    return
                end

                C_Timer.After(0.35, function()
                    if IsNowEquipped() then
                        DebugMessage("Pole equip completed on extended verify via "
                            .. tostring(lastDispatchedMethod or "unknown") .. ": " .. GetDebugItemLabel(numeric))
                    else
                        DebugMessage("Failed to equip configured pole after delayed verify " .. GetDebugItemLabel(numeric))
                    end
                end)
            end)
            DebugMessage("Pole equip request dispatched via " .. tostring(lastDispatchedMethod or "unknown")
                .. "; awaiting delayed verification: " .. GetDebugItemLabel(numeric))
        else
            DebugMessage("Pole equip request dispatched; timer unavailable for delayed verification: " .. GetDebugItemLabel(numeric))
        end
        return true
    end

    DebugMessage("Failed to equip configured pole " .. GetDebugItemLabel(numeric))
    return false
end

local function GetDesiredConfiguredPoleItemID(inFishingSession)
    local selections = GetConfiguredPoleSelections()
    local primary = selections.primary
    local underlight = selections.underlight

    if not primary.isChecked and not underlight.isChecked then
        return nil
    end
    if primary.isChecked and not underlight.isChecked then
        return primary.itemID
    end
    if underlight.isChecked and not primary.isChecked then
        return underlight.itemID
    end

    if inFishingSession then
        return primary.itemID
    end
    return underlight.itemID
end

local function MaybeEquipConfiguredUnderlight(reason, forcePrimary)
    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for configured pole sync")
    end
    local fishing = requireFishingAPI()

    if not addon.db then
        return false
    end

    if not (fishing and fishing.IsFishingActiveSessionState) then
        error("DreamFisher: IsFishingActiveSessionState is required for configured pole sync")
    end

    local waterContext = GetWaterContextDiagnostics()
    local swimming = waterContext.result
    local inFishingSession = fishing.IsFishingActiveSessionState()

    if addon.db.debugMode and addon.db.debugState then
        DebugStateMessage("Water context check: result=" .. tostring(swimming)
            .. " source=" .. tostring(waterContext.source or "none")
            .. " isSwimming=" .. tostring(waterContext.isSwimming)
            .. " isSubmerged=" .. tostring(waterContext.isSubmerged)
            .. " secureOption=" .. tostring(waterContext.secureOption))
    end

    local desiredPoleItemID = GetDesiredConfiguredPoleItemID(inFishingSession)
    if not desiredPoleItemID or desiredPoleItemID <= 0 then
        return false
    end
    if not IsItemAvailableForEquip(desiredPoleItemID) then
        return false
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false
    end

    DebugMessage("Syncing configured pole: reason=" .. tostring(reason or "unknown")
        .. " swimming=" .. tostring(swimming)
        .. " inFishingSession=" .. tostring(inFishingSession)
        .. " forcePrimary=" .. tostring(forcePrimary and true or false)
        .. " waterSource=" .. tostring(waterContext.source or "none")
        .. " isSwimmingSignal=" .. tostring(waterContext.isSwimming)
        .. " isSubmergedSignal=" .. tostring(waterContext.isSubmerged)
        .. " secureOption=" .. tostring(waterContext.secureOption)
        .. " desired=" .. GetDebugItemLabel(desiredPoleItemID))
    local equipped = TryEquipItemToProfessionSlot(desiredPoleItemID)
    if equipped then
        DebugMessage("Equipped configured pole: reason=" .. tostring(reason or "unknown")
            .. " item=" .. GetDebugItemLabel(desiredPoleItemID))
    end
    return equipped
end

local function WarnMissingProfessionFishingPoleForLure()
    local now = (type(GetTime) == "function") and GetTime() or 0
    local cooldown = tonumber(addon.state and addon.state.buffMissingWarningCooldown) or 8
    local last = tonumber(addon.state and addon.state.lureMissingPoleWarningAt) or 0
    if (now - last) < cooldown then
        return
    end
    if addon.state then
        addon.state.lureMissingPoleWarningAt = now
    end

    local warningText = "Cannot apply lure: no fishing pole equipped in profession slot."

    if UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, warningText, 1, 0.1, 0.1, 1.0)
    end

    if PrintMessage then
        PrintMessage(warningText)
    end
    local audio = getAudioAPI and getAudioAPI()
    if audio and type(audio.PlayWarningCue) == "function" then
        audio.PlayWarningCue()
    end
end

local function GetTransientCastBlocker()
    if not addon.db or type(addon.db.buffItems) ~= "table" then
        return nil, nil
    end
    if not addon.state or type(addon.state.buffItemTransientUntil) ~= "table" then
        return nil, nil
    end

    local now = (type(GetTime) == "function") and GetTime() or 0

    for _, entry in ipairs(addon.db.buffItems) do
        local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
        if itemID and itemID > 0 and not (type(entry) == "table" and entry.enabled == false) then
            local transientUntil = tonumber(addon.state.buffItemTransientUntil[itemID]) or 0
            if transientUntil > now then
                local lastingAuraActive = false

                -- Prefer known item mapping as the authoritative lasting aura source.
                local known = addon.const
                    and type(addon.const.knownBuffItems) == "table"
                    and addon.const.knownBuffItems[itemID]
                    or nil
                local knownSpellID = type(known) == "table" and tonumber(known.spellID) or nil
                if knownSpellID and addon.buff and type(addon.buff.GetAuraBySpellID) == "function" then
                    local knownAura = addon.buff.GetAuraBySpellID(knownSpellID)
                    lastingAuraActive = knownAura and knownAura.expirationTime and knownAura.expirationTime > now and true or false
                elseif addon.buff and type(addon.buff.GetTrackedBuffRemaining) == "function" then
                    local lastingRemaining = addon.buff.GetTrackedBuffRemaining(itemID)
                    lastingAuraActive = lastingRemaining ~= nil
                end

                if not lastingAuraActive then
                    return itemID, (transientUntil - now)
                end
            end
        end
    end

    return nil, nil
end

local function WarnTransientCastBlocked(itemID, transientRemaining)
    local now = (type(GetTime) == "function") and GetTime() or 0
    local last = tonumber(addon.state and (addon.state.buffCastBlockWarningAt or addon.state.foodDrinkCastBlockWarningAt)) or 0
    if (now - last) < 2 then
        return
    end
    if addon.state then
        addon.state.buffCastBlockWarningAt = now
        addon.state.foodDrinkCastBlockWarningAt = now
    end

    local warningText = "A buff is still being applied. Wait before casting."
    if UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, warningText, 1, 0.2, 0.2, 1.0)
    end
    if PrintMessage then
        PrintMessage(warningText .. " (" .. GetDebugItemLabel(itemID)
            .. ", transient remaining " .. string.format("%.1fs", math.max(0, transientRemaining or 0)) .. ")")
    end
    local audio = getAudioAPI and getAudioAPI()
    if audio and type(audio.PlayWarningCue) == "function" then
        audio.PlayWarningCue()
    end
end

local function ShouldAbortPreCastForTransientBuffInUse()
    local itemID, transientRemaining = GetTransientCastBlocker()
    if not itemID then
        return false
    end

    WarnTransientCastBlocked(itemID, transientRemaining)
    DebugBuffMessage("Aborting pre-cast: transient buff still active for "
        .. GetDebugItemLabel(itemID)
        .. " remaining=" .. string.format("%.1fs", math.max(0, transientRemaining or 0)))
    return true
end

local function HasTargetSelected()
    return (type(UnitExists) == "function") and UnitExists("target") and true or false
end

local function ResolveSecurePreCastDueBuff(raftExclusiveWhileSwimming)
    if raftExclusiveWhileSwimming then
        return nil, nil
    end
    if not (addon.buff and addon.buff.GetNextDueBuffItem) then
        return nil, nil
    end

    if type(GetNextReadyDueBuffItem) == "function" then
        local dueBuffItemID, _, dueBuffCategory = GetNextCastableDueBuffItem(
            "Skipping lure due buff; no fishing pole equipped in profession slot"
        )
        return dueBuffItemID, dueBuffCategory
    end

    DebugBuffMessage("Due buff helper unavailable; skipping due buff on this click")
    return nil, nil
end

local function ApplyDueBuffToSecureMacro(fishingFrame, macroLines, dueBuffItemID, dueBuffCategory)
    if dueBuffItemID then
        table.insert(macroLines, "/use item:" .. tostring(dueBuffItemID))
        if IsLureCategory(dueBuffCategory) then
            table.insert(macroLines, "/use 28") -- apply lure to fishing profession equipment slot
        end
        fishingFrame:SetAttribute("dreamfisher_duebuff", dueBuffItemID)
        DebugBuffMessage("Fishing click will apply due buff: "
            .. GetDebugItemLabel(dueBuffItemID)
            .. " category=" .. tostring(dueBuffCategory)
            .. " " .. GetDebugCooldownText(dueBuffItemID))
        return true
    else
        fishingFrame:SetAttribute("dreamfisher_duebuff", nil)
        return false
    end
end

local function FinalizeSecureFishingAction(fishingFrame, macroLines, raftExclusiveWhileSwimming, bobberDecision, hasConsumableAction)
    if #macroLines > 0 then
        local castArmed = (not raftExclusiveWhileSwimming) and (not hasConsumableAction)
        if castArmed then
            table.insert(macroLines, "/cast Fishing")
        end
        fishingFrame:SetAttribute("type", "macro")
        fishingFrame:SetAttribute("macrotext", table.concat(macroLines, "\n"))
        fishingFrame:SetAttribute("spell", nil)
        fishingFrame:SetAttribute("dreamfisher_castarmed", castArmed and true or false)
        if raftExclusiveWhileSwimming then
            DebugBuffMessage("Fishing click configured as raft-only pre-cast")
        elseif not castArmed then
            DebugBuffMessage("Fishing click configured with pre-cast item usage; cast will arm on next click")
        elseif bobberDecision.shouldApply then
            DebugBuffMessage("Fishing click configured to use bobber toy: "
                .. GetDebugItemLabel(bobberDecision.toyID) .. " " .. GetDebugCooldownText(bobberDecision.toyID))
        else
            DebugBuffMessage("Fishing click configured with pre-cast items before Fishing")
        end
        return castArmed and true or false
    end

    fishingFrame:SetAttribute("type", "spell")
    fishingFrame:SetAttribute("spell", "Fishing")
    fishingFrame:SetAttribute("macrotext", nil)
    fishingFrame:SetAttribute("dreamfisher_castarmed", true)
    if bobberDecision.hasToy and bobberDecision.mounted then
        DebugBuffMessage("Skipping bobber toy while mounted: " .. GetDebugItemLabel(bobberDecision.toyID))
    elseif bobberDecision.hasToy and bobberDecision.swimming then
        DebugBuffMessage("Skipping bobber toy while swimming: " .. GetDebugItemLabel(bobberDecision.toyID))
    elseif bobberDecision.hasToy and bobberDecision.auraRemaining and not bobberDecision.needsRefreshForCast then
        DebugBuffMessage("Skipping bobber reapply; aura covers cast: "
            .. GetDebugItemLabel(bobberDecision.toyID)
            .. " auraRemaining=" .. string.format("%.1fs", bobberDecision.auraRemaining))
    elseif bobberDecision.hasToy and not bobberDecision.ready and bobberDecision.needsRefreshForCast then
        DebugBuffMessage("Skipping bobber toy on cooldown: "
            .. GetDebugItemLabel(bobberDecision.toyID) .. " " .. GetDebugCooldownText(bobberDecision.toyID))
        DebugMessage("Fishing click configured as spell cast only")
    elseif bobberDecision.hasToy then
        DebugBuffMessage("Fishing click configured as spell cast only; bobber not auto-used in current state: "
            .. GetDebugItemLabel(bobberDecision.toyID))
    else
        DebugMessage("Fishing click configured as spell cast only")
    end
    return true
end

ConfigureFishingClickAction = function()
    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for fishing click configuration")
    end
    local fishing = requireFishingAPI()

    local fishingFrame = addon.frames.fishing
    if not fishingFrame then
        return false
    end

    if HasTargetSelected() then
        DebugMessage("Target selected; skipping fishing click configuration")
        ResetFishingFrameState(fishingFrame)
        return false
    end

    local now = (type(GetTime) == "function") and GetTime() or 0
    local lastSecureClickAt = tonumber(addon.state and addon.state.lastFishingSecureClickAt) or 0
    if lastSecureClickAt > 0 and (now - lastSecureClickAt) < 0.20 then
        DebugMessage("Suppressing duplicate secure fishing click: dt="
            .. string.format("%.3f", now - lastSecureClickAt))
        ResetFishingFrameState(fishingFrame)
        return
    end

    if ShouldAbortPreCastForTransientBuffInUse() then
        ResetFishingFrameState(fishingFrame)
        return
    end

    ResetFishingFrameState(fishingFrame)
    if fishing and fishing.IsHookedLootMode and fishing.IsHookedLootMode() then
        if fishing.ConfigureInteractLootAction then
            fishing.ConfigureInteractLootAction(fishingFrame)
            return
        end
    elseif addon.db and addon.db.easyStrike then
        local now = (type(GetTime) == "function") and GetTime() or 0
        local graceUntil = tonumber(addon.state and addon.state.fishingStartGraceUntil) or 0
        DebugMessage("Hooked interact not armed: sessionState=" .. tostring(addon.state and addon.state.fishingSessionState)
            .. " graceRemaining=" .. string.format("%.2f", math.max(0, graceUntil - now)))
    end

    local raftDecision = GetRaftUseDecision()
    local fishingPoleDecision = GetSelectedFishingPoleDecision()
    local bobberDecision = GetBobberUseDecision()
    local oversizedDecision = GetOversizedBobberDecision()
    local poleSelections = GetConfiguredPoleSelections()
    local macroLines = {}
    local hasConsumableAction = false
    local raftExclusiveWhileSwimming = false
    local underlightItemID = poleSelections.underlight.itemID
    local underlightMounted = (type(IsMounted) == "function" and IsMounted()) or false
    local underlightEquippedItemID = GetEquippedProfessionItemID()
    local underlightAlreadyEquipped = underlightItemID
        and underlightEquippedItemID
        and (underlightItemID == underlightEquippedItemID)
        or false
    local shouldEquipUnderlightInMacro = poleSelections.underlight.isChecked
        and (not poleSelections.primary.isChecked)
        and IsItemAvailableForEquip(underlightItemID)
        and not underlightMounted
        and not underlightAlreadyEquipped

    if raftDecision.shouldApply then
        table.insert(macroLines, "/use item:" .. tostring(raftDecision.toyID))
        hasConsumableAction = true
        DebugBuffMessage("Fishing click will apply raft: "
            .. GetDebugItemLabel(raftDecision.toyID) .. " " .. GetDebugCooldownText(raftDecision.toyID))
        if raftDecision.swimming then
            raftExclusiveWhileSwimming = true
            DebugBuffMessage("Raft needed while swimming; skipping other pre-cast items this click")
        end
    elseif raftDecision.hasToy and raftDecision.swimming and raftDecision.auraRemaining and not raftDecision.needsRefreshForCast then
        DebugBuffMessage("Skipping raft reapply; aura covers cast: "
            .. GetDebugItemLabel(raftDecision.toyID)
            .. " auraRemaining=" .. string.format("%.1fs", raftDecision.auraRemaining))
    elseif raftDecision.hasToy
        and not raftDecision.ready
        and raftDecision.needsRefreshForCast
        and (raftDecision.swimming or raftDecision.auraRemaining ~= nil) then
        DebugBuffMessage("Skipping raft toy on cooldown: "
            .. GetDebugItemLabel(raftDecision.toyID) .. " " .. GetDebugCooldownText(raftDecision.toyID))
    end

    if (not raftExclusiveWhileSwimming) and fishingPoleDecision.shouldApply then
        table.insert(macroLines, "/equip item:" .. tostring(fishingPoleDecision.itemID))
        DebugBuffMessage("Fishing click will equip configured fishing pole: "
            .. GetDebugItemLabel(fishingPoleDecision.itemID))
    end

    if shouldEquipUnderlightInMacro then
        table.insert(macroLines, "/equip item:" .. tostring(underlightItemID))
        DebugBuffMessage("Fishing click will equip Underlight Angler: "
            .. GetDebugItemLabel(underlightItemID))
    end

    if (not raftExclusiveWhileSwimming) and bobberDecision.shouldApply then
        table.insert(macroLines, "/use item:" .. tostring(bobberDecision.toyID))
        hasConsumableAction = true
        DebugBuffMessage("Fishing click will apply bobber toy: "
            .. GetDebugItemLabel(bobberDecision.toyID) .. " " .. GetDebugCooldownText(bobberDecision.toyID))
    end

    if (not raftExclusiveWhileSwimming) and oversizedDecision.enabled then
        if oversizedDecision.shouldApply then
            table.insert(macroLines, "/use item:" .. tostring(OVERSIZED_BOBBER_ITEM_ID))
            hasConsumableAction = true
            DebugBuffMessage("Fishing click will apply oversized bobber: "
                .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID) .. " " .. GetDebugCooldownText(OVERSIZED_BOBBER_ITEM_ID))
        elseif oversizedDecision.auraRemaining and not oversizedDecision.needsRefreshForCast then
            DebugBuffMessage("Skipping oversized bobber reapply; aura covers cast: "
                .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID)
                .. " auraRemaining=" .. string.format("%.1fs", oversizedDecision.auraRemaining))
        elseif oversizedDecision.ready and oversizedDecision.swimming then
            DebugBuffMessage("Skipping oversized bobber while swimming: "
                .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID))
        elseif oversizedDecision.available and not oversizedDecision.ready and oversizedDecision.needsRefreshForCast then
            DebugBuffMessage("Skipping oversized bobber on cooldown: "
                .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID) .. " " .. GetDebugCooldownText(OVERSIZED_BOBBER_ITEM_ID))
        else
            DebugBuffMessage("Skipping oversized bobber; toy not owned: " .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID))
        end
    end

    local dueBuffItemID, dueBuffCategory = ResolveSecurePreCastDueBuff(raftExclusiveWhileSwimming)
    local hasDueBuffAction = ApplyDueBuffToSecureMacro(fishingFrame, macroLines, dueBuffItemID, dueBuffCategory)
    if hasDueBuffAction then
        hasConsumableAction = true
    end
    local castArmed = FinalizeSecureFishingAction(
        fishingFrame,
        macroLines,
        raftExclusiveWhileSwimming,
        bobberDecision,
        hasConsumableAction
    )
    if addon.state then
        addon.state.lastFishingClickConfigAt = (type(GetTime) == "function") and GetTime() or 0
    end
    return true, castArmed and true or false
end

local function GetNextReadyDueBuffItemForCategory(category, excludedBuffItemIDs)
    local hadUnavailableDueBuff = false
    while true do
        local candidateItemID, dueStatus = addon.buff.GetNextDueBuffItem(true, excludedBuffItemIDs, category)
        if not candidateItemID then
            hadUnavailableDueBuff = (dueStatus == "due_unavailable") or hadUnavailableDueBuff
            return nil, hadUnavailableDueBuff
        end
        if IsItemReadyForUse(candidateItemID) then
            return candidateItemID, hadUnavailableDueBuff
        end
        DebugBuffMessage("Skipping due buff on cooldown this click: "
            .. GetDebugItemLabel(candidateItemID) .. " " .. GetDebugCooldownText(candidateItemID))
        excludedBuffItemIDs[candidateItemID] = true
    end
end

GetNextReadyDueBuffItem = function(seedExcludedBuffItemIDs)
    if not HasConfiguredBuffItems() then
        return nil, false, nil
    end

    local excludedBuffItemIDs = seedExcludedBuffItemIDs or {}
    local hadUnavailableDueBuff = false

    for _, category in ipairs(DUE_BUFF_CATEGORY_ORDER) do
        if category == "bait" and HasAnyActiveBaitAura() then
            DebugBuffMessage("Skipping bait category pass: active bait aura detected")
        else
            local candidateItemID, unavailableInCategory = GetNextReadyDueBuffItemForCategory(category, excludedBuffItemIDs)
            hadUnavailableDueBuff = hadUnavailableDueBuff or unavailableInCategory
            if candidateItemID then
                return candidateItemID, hadUnavailableDueBuff, category
            end
        end
    end

    return nil, hadUnavailableDueBuff, nil
end

GetNextCastableDueBuffItem = function(lureBlockedDebugMessage)
    local excludedBuffItemIDs = {}
    local hadUnavailableDueBuff = false

    while true do
        local candidateItemID, unavailable, category = GetNextReadyDueBuffItem(excludedBuffItemIDs)
        hadUnavailableDueBuff = hadUnavailableDueBuff or unavailable

        if not candidateItemID then
            return nil, hadUnavailableDueBuff, nil
        end

        if IsLureCategory(category) and (not IsFishingPoleEquippedInProfessionSlot()) then
            WarnMissingProfessionFishingPoleForLure()
            DebugMessage(lureBlockedDebugMessage or "Skipping lure due buff; no fishing pole equipped in profession slot")
            excludedBuffItemIDs[candidateItemID] = true
        else
            return candidateItemID, hadUnavailableDueBuff, category
        end
    end
end

local function ResolveBool(value, defaultValue)
    if value == nil then
        return not not defaultValue
    end
    return not not value
end

local function GetCastingModes()
    local defaultsModes = (addon.defaults and addon.defaults.castingModes) or {}
    local dbModes = (addon.db and addon.db.castingModes) or {}

    local modes = {
        doubleRightClick = ResolveBool(dbModes.doubleRightClick, defaultsModes.doubleRightClick),
        singleRightClick = ResolveBool(dbModes.singleRightClick, defaultsModes.singleRightClick),
        castHotkey = ResolveBool(dbModes.castHotkey, defaultsModes.castHotkey),
    }

    if addon.db then
        addon.db.castingModes = modes
    end

    return modes
end

local function IsWorldRightClickActivationPressed()
    local modes = GetCastingModes()
    if modes.singleRightClick and addon.frames.config and addon.frames.config:IsShown() then
        return true
    end
    if modes.doubleRightClick then
        return true
    end
    return false
end

local function IsHotkeyActivationPressed()
    local modes = GetCastingModes()
    return modes.castHotkey
end

local function ArmFishingRightClickAction(fishingFrame)
    if not fishingFrame then
        return false, false
    end
    local configured, castArmed = ConfigureFishingClickAction()
    if configured == false then
        return false, false
    end
    SetOverrideBindingClick(fishingFrame, true, "BUTTON2", fishingFrame:GetName(), "RightButton")
    -- Show the secure frame so the current click release can trigger the secure action.
    fishingFrame:Show()
    return true, castArmed and true or false
end

local function ClearRightClickBuffFrameState(buffFrame, clearBeforeHide)
    if not buffFrame then
        return
    end

    if clearBeforeHide and not InCombatLockdown() then
        ClearOverrideBindings(buffFrame)
    end
    buffFrame:Hide()
    ResetBuffFrameState(buffFrame)
    if (not clearBeforeHide) and not InCombatLockdown() then
        ClearOverrideBindings(buffFrame)
    end
end

local function ClearRightClickFishingFrameState(fishingFrame, clearBeforeReset)
    if not fishingFrame then
        return
    end

    if clearBeforeReset and not InCombatLockdown() then
        ClearOverrideBindings(fishingFrame)
    end
    ResetFishingFrameState(fishingFrame)
    fishingFrame:Hide()
    if (not clearBeforeReset) and not InCombatLockdown() then
        ClearOverrideBindings(fishingFrame)
    end
end

local function EnsureFishingSecureFrame(frame)
    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for secure fishing frame setup")
    end
    local fishing = requireFishingAPI()

    if frame then
        return frame
    end
    if fishing and fishing.CreateSecureFishingFrame then
        return fishing.CreateSecureFishingFrame()
    end
    return frame
end

local function EnsureBuffSecureFrame(frame)
    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for secure buff frame setup")
    end
    local fishing = requireFishingAPI()

    if frame then
        return frame
    end
    if fishing and fishing.CreateSecureBuffFrame then
        return fishing.CreateSecureBuffFrame()
    end
    return frame
end

local function GetInteractPresenceDiagnostics()
    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for interact diagnostics")
    end
    local fishing = requireFishingAPI()

    local hasAnyInteractUnit = false
    local hasSoftInteractNameOnly = false

    if fishing and fishing.GetInteractDiagnostics then
        local diag = fishing.GetInteractDiagnostics()
        hasAnyInteractUnit = diag and (diag.softExists or diag.targetExists or diag.mouseoverExists) and true or false
        hasSoftInteractNameOnly = diag
            and (not hasAnyInteractUnit)
            and type(diag.softName) == "string"
            and diag.softName ~= ""
            and true or false
    end

    return hasAnyInteractUnit, hasSoftInteractNameOnly
end

local function ExitFishingSessionForTargetSelection()
    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for target selection exit")
    end
    local fishing = requireFishingAPI()

    if not addon.state then
        return
    end

    if not (fishing and fishing.CancelAndCloseFishingSession) then
        error("DreamFisher: CancelAndCloseFishingSession is required for target selection exit")
    end

    fishing.CancelAndCloseFishingSession(
        "target-selected",
        "target-selected-close",
        {
            restoreAutoLoot = true,
            restoreFocusVisuals = false,
            syncPole = false,
        }
    )
end

local function ExitFishingSessionForNoHookEvidence()
    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for no-hook-evidence exit")
    end
    local fishing = requireFishingAPI()

    if not addon.state then
        return
    end

    if not (fishing and fishing.CancelAndCloseFishingSession) then
        error("DreamFisher: CancelAndCloseFishingSession is required for no-hook-evidence exit")
    end

    fishing.CancelAndCloseFishingSession(
        "no-hook-evidence",
        "no-hook-evidence-close",
        {
            restoreAutoLoot = true,
            restoreFocusVisuals = false,
            syncPole = false,
        }
    )
end

local function HandleHookedPhaseTrigger(source, fishing, shouldRouteHookedInteract, noHookedEvidence, buffFrame, fishingFrame)
    if not shouldRouteHookedInteract then
        return false
    end

    if noHookedEvidence then
        DebugMessage("Hooked route requested without interact evidence; clearing stale fishing session and resuming recast flow")
        ExitFishingSessionForNoHookEvidence()
        return false
    end

    addon.state.lastRightClickTime = 0
    fishingFrame = EnsureFishingSecureFrame(fishingFrame)

    if fishingFrame and not InCombatLockdown() then
        if buffFrame then
            ClearRightClickBuffFrameState(buffFrame, true)
        end
        ArmFishingRightClickAction(fishingFrame)
        DebugMessage("Hooked phase trigger " .. source .. " routed to interact action")
        return true
    end

    return false
end

local function HandlePrecastTrigger(source, allowSingleClick, fishing, audio, buffFrame)
    if ShouldAbortPreCastForTransientBuffInUse() then
        return
    end

    local raftDecision = GetRaftUseDecision()
    if raftDecision.shouldApply and raftDecision.swimming then
        if allowSingleClick then
            DebugMessage("Config window open: single right-click applying raft before cast")
        end
        DebugMessage("Fishing trigger " .. source .. " routing to raft-only pre-cast while swimming")
        if not InCombatLockdown() then
            if buffFrame then
                ClearRightClickBuffFrameState(buffFrame, true)
            end
            local activeFishingFrame = addon.frames.fishing
            if activeFishingFrame then
                ArmFishingRightClickAction(activeFishingFrame)
            end
        end
        return
    end

    if buffFrame then
        ClearRightClickBuffFrameState(buffFrame, false)
    end

    if not InCombatLockdown() then
        buffFrame = addon.frames.buff
        if buffFrame then
            ClearRightClickBuffFrameState(buffFrame, true)
        end
        local fishingFrame = addon.frames.fishing
        if fishingFrame then
            local armed, castArmed = ArmFishingRightClickAction(fishingFrame)
            if not armed then
                return
            end
            if castArmed then
                if audio and audio.StartFishingAudioFocus then
                    audio.StartFishingAudioFocus()
                end
                local castNow = (type(GetTime) == "function") and GetTime() or 0
                -- Mark a pre-cast fishing session for audio/tests. Hooked mode is
                -- still blocked by grace-window gating until cast has transitioned.
                if fishing and fishing.ApplySessionState then
                    fishing.ApplySessionState("PRE_CASTING", "right-click-pre-cast")
                end
                addon.state.fishingStartTime = castNow
                addon.state.fishingStartGraceUntil = castNow + 1.5
                addon.state.interactAcquireExpiresAt = 0
                DebugBuffMessage("No due buffs; starting fishing cast")
                if allowSingleClick then
                    DebugMessage("Config window open: single right-click starting fishing")
                end
            else
                DebugBuffMessage("Prepared pre-cast item usage; cast will start on a follow-up click")
            end
        end
    end
end

local function HandlePlayerTrigger(source, allowSingleClick, fishing, audio, skipHookedPhase)
    local now = GetTime()
    local hasConfiguredBuffItems = HasConfiguredBuffItems()
    local easyStrike = addon.db and addon.db.easyStrike

    local hasAnyInteractUnit = false
    local hasSoftInteractNameOnly = false
    local inAcquireWindow = false
    if easyStrike then
        hasAnyInteractUnit, hasSoftInteractNameOnly = GetInteractPresenceDiagnostics()
        local acquireExpiresAt = tonumber(addon.state and addon.state.interactAcquireExpiresAt) or 0
        inAcquireWindow = acquireExpiresAt > now
    end

    local hookedModeActive = easyStrike
        and fishing and fishing.IsHookedLootMode
        and fishing.IsHookedLootMode()
    local shouldRouteHookedInteract = easyStrike and hookedModeActive
    local noHookedEvidence = easyStrike
        and (not hasAnyInteractUnit)
        and (not hasSoftInteractNameOnly)
        and (not inAcquireWindow)

    local buffFrame = addon.frames.buff
    local fishingFrame = addon.frames.fishing

    if not skipHookedPhase then
        if HandleHookedPhaseTrigger(
            source,
            fishing,
            shouldRouteHookedInteract,
            noHookedEvidence,
            buffFrame,
            fishingFrame
        ) then
            return
        end
    end

    if not hasConfiguredBuffItems and buffFrame then
        ClearRightClickBuffFrameState(buffFrame, false)
        addon.state.pendingBuffObservation = nil
    end

    fishingFrame = EnsureFishingSecureFrame(fishingFrame)
    buffFrame = EnsureBuffSecureFrame(buffFrame)

    if buffFrame and buffFrame:IsShown() then
        local currentlyDueItemID = GetNextReadyDueBuffItem()
        local armedItemID = tonumber(buffFrame:GetAttribute("dreamfisher_itemid"))
        if currentlyDueItemID and armedItemID and currentlyDueItemID == armedItemID and IsItemReadyForUse(armedItemID) then
            DebugMessage("Buff secure frame already shown; awaiting secure click")
            return
        end

        DebugMessage("Clearing stale secure buff click state")
        ClearRightClickBuffFrameState(buffFrame, false)
    end

    if fishingFrame and fishingFrame:IsShown() then
        DebugMessage("Clearing stale secure fishing click state")
        ClearRightClickFishingFrameState(fishingFrame, false)
    end

    HandlePrecastTrigger(source, allowSingleClick, fishing, audio, buffFrame)
end

local function HandleWorldRightClick()
    local now = GetTime()
    local modes = GetCastingModes()
    local allowSingleClick = modes.singleRightClick and addon.frames.config and addon.frames.config:IsShown() or false
    local isDoubleRightClick = (now - addon.state.lastRightClickTime) <= (addon.state.doubleClickWindow + 0.001)
    local isSingleRightClick = allowSingleClick and not isDoubleRightClick
    local source = "unknown"
    if isDoubleRightClick then
        source = "world-double-right-click"
    elseif isSingleRightClick then
        source = "world-single-right-click"
    end

    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for world right-click handling")
    end
    local fishing = requireFishingAPI()
    local audio = getAudioAPI and getAudioAPI()

    if InCombatLockdown() then
        DebugMessage("Fishing trigger " .. source .. " ignored: in combat lockdown")
        return
    end

    local mounted = (type(IsMounted) == "function" and IsMounted()) or false
    if HasTargetSelected() or (mounted and isSingleRightClick) then
        addon.state.lastRightClickTime = 0
        if mounted then
            DebugMessage("Single right-click ignored while mounted")
        else
            DebugMessage("Target selected; ignoring fishing trigger: " .. source)
        end
        ExitFishingSessionForTargetSelection()
        if not InCombatLockdown() then
            if addon.frames.fishing then
                ClearRightClickFishingFrameState(addon.frames.fishing, true)
            end
            if addon.frames.buff then
                ClearRightClickBuffFrameState(addon.frames.buff, true)
            end
        end
        return
    end

    if addon.db and addon.db.easyStrike
        and addon.state and addon.state.interactOverrideActive
        and fishing and fishing.IsHookedLootMode
        and fishing.IsHookedLootMode() then
        local hasAnyInteractUnit, hasSoftInteractNameOnly = GetInteractPresenceDiagnostics()
        local acquireExpiresAt = tonumber(addon.state.interactAcquireExpiresAt) or 0
        local inAcquireWindow = acquireExpiresAt > GetTime()

        if hasAnyInteractUnit or inAcquireWindow or hasSoftInteractNameOnly then
            DebugMessage("Hooked phase trigger " .. source .. " delegated to native interact override")
            return
        end

        DebugMessage("Stale hooked interact override with no target; clearing override and resuming cast flow")
        if not (fishing and fishing.ClearNativeInteractOverride) then
            error("DreamFisher: ClearNativeInteractOverride is required for stale hooked override cleanup")
        end
        fishing.ClearNativeInteractOverride()
        addon.state.interactAcquireExpiresAt = 0
    end

    local now = GetTime()
    DebugMessage("Fishing trigger " .. source .. ": dt=" .. string.format("%.3f", now - addon.state.lastRightClickTime))
    local modes = GetCastingModes()
    local allowSingleClick = modes.singleRightClick and addon.frames.config and addon.frames.config:IsShown() or false
    local easyStrike = addon.db and addon.db.easyStrike
    local hookedModeActive = easyStrike
        and fishing and fishing.IsHookedLootMode
        and fishing.IsHookedLootMode()
    local hookedPhasePreHandled = false

    if hookedModeActive then
        local hasAnyInteractUnit, hasSoftInteractNameOnly = GetInteractPresenceDiagnostics()
        local acquireExpiresAt = tonumber(addon.state and addon.state.interactAcquireExpiresAt) or 0
        local inAcquireWindow = acquireExpiresAt > now
        local noHookedEvidence = (not hasAnyInteractUnit)
            and (not hasSoftInteractNameOnly)
            and (not inAcquireWindow)

        hookedPhasePreHandled = true
        if HandleHookedPhaseTrigger(
            source,
            fishing,
            true,
            noHookedEvidence,
            addon.frames.buff,
            addon.frames.fishing
        ) then
            return
        end
    end

    if allowSingleClick
        or (now - addon.state.lastRightClickTime) <= (addon.state.doubleClickWindow + 0.001) then
        addon.state.lastRightClickTime = 0
        HandlePlayerTrigger(source, allowSingleClick, fishing, audio, hookedPhasePreHandled)
    else
        addon.state.lastRightClickTime = now
        DebugMessage("Single right-click: no addon action (awaiting second click)")
        if not InCombatLockdown() then
            if addon.frames.fishing then
                ClearRightClickFishingFrameState(addon.frames.fishing, true)
            end
            if addon.frames.buff then
                ClearRightClickBuffFrameState(addon.frames.buff, true)
            end
        end
    end
end

local function HandleHotkeyPress()
    if not IsHotkeyActivationPressed() then
        return false
    end

    if InCombatLockdown() then
        DebugMessage("Hotkey ignored: in combat lockdown")
        return true
    end

    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for hotkey handling")
    end
    local fishing = requireFishingAPI()

    -- Hotkey bypasses right-click timing logic and enters the shared trigger flow directly.
    HandlePlayerTrigger("hotkey", false, fishing, audio)
    return true
end

local function HandleSpellCastTrigger()
    if not requireFishingAPI then
        error("DreamFisher: RequireFishingAPI helper is required for spell cast trigger handling")
    end
    local fishing = requireFishingAPI()
    local audio = getAudioAPI and getAudioAPI()

    fishing.HandlePlayerTrigger("spell-cast", false, fishing, audio)
end

local function HandleCastCommand()
    if PrintMessage then
        PrintMessage("Protected cast requires a secure click.")
        PrintMessage("Use macro: /click DreamFisherSecureFishingButton RightButton")
    end
end

local function IsFishingCast()
    if UnitCastingInfo("player") == "Fishing" then
        return true
    end
    if UnitChannelInfo("player") == "Fishing" then
        return true
    end
    return false
end

-- Export to addon
addon.fishing = addon.fishing or {}
addon.fishing.CreateSecureFishingFrame = CreateSecureFishingFrame
addon.fishing.CreateSecureBuffFrame = CreateSecureBuffFrame
addon.fishing.ApplySelectedBobberToy = ApplySelectedBobberToy
addon.fishing.ApplySelectedRaftToy = ApplySelectedRaftToy
addon.fishing.IsWorldRightClickActivationPressed = IsWorldRightClickActivationPressed
addon.fishing.IsHotkeyActivationPressed = IsHotkeyActivationPressed
addon.fishing.HandleHotkeyPress = HandleHotkeyPress
addon.fishing.HandleCastCommand = HandleCastCommand
addon.fishing.HandleWorldRightClick = HandleWorldRightClick
addon.fishing.IsFishingCast = IsFishingCast
addon.fishing.ConfigureFishingClickAction = ConfigureFishingClickAction
addon.fishing.IsPlayerInWaterContext = IsPlayerInWaterContext
addon.fishing.GetWaterContextDiagnostics = GetWaterContextDiagnostics
addon.fishing.SyncConfiguredPoleForCurrentState = MaybeEquipConfiguredUnderlight
addon.fishing.MaybeEquipConfiguredUnderlight = MaybeEquipConfiguredUnderlight

-- Test hooks
addon._test.HandleWorldRightClick = function()
    HandleWorldRightClick()
end
addon._test.SetLastRightClickTime = function(time)
    addon.state.lastRightClickTime = time
end
addon._test.GetLastRightClickTime = function()
    return addon.state.lastRightClickTime
end
addon._test.GetDoubleClickWindow = function()
    return addon.state.doubleClickWindow
end
