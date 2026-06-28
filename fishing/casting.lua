-- DreamFisher: Fishing Casting and World Right-Click Handler

local addon = _G["DreamFisher"]
local PrintMessage = addon.PrintMessage
local DebugMessage = addon.DebugMessage
local OVERSIZED_BOBBER_ITEM_ID = 202207
local DUE_BUFF_CATEGORY_ORDER = { "lure", "food_drink", "other_consumable" }

local ConfigureFishingClickAction
local GetNextReadyDueBuffItem
local GetNextCastableDueBuffItem

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
    local bobberToyID = addon.db and tonumber(addon.db.selectedBobberToy) or nil
    local hasToy = (bobberToyID and bobberToyID > 0)
        and (type(PlayerHasToy) ~= "function" or PlayerHasToy(bobberToyID))
    local bobberReady = hasToy and IsItemReadyForUse(bobberToyID)
    local mounted = (type(IsMounted) == "function" and IsMounted()) or false
    local swimming = (type(IsSwimming) == "function" and IsSwimming()) or false
    local shouldApply = hasToy and bobberReady and not mounted and not swimming

    return {
        toyID = bobberToyID,
        hasToy = hasToy,
        ready = bobberReady,
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
    local swimming = (type(IsSwimming) == "function" and IsSwimming()) or false
    local shouldApply = ready and not swimming

    return {
        enabled = true,
        available = available,
        ready = ready,
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
        if itemID and itemID > 0 then
            return true
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
        if ConfigureFishingClickAction then
            ConfigureFishingClickAction()
        end
    end)
    frame:HookScript("OnClick", function()
        local actionType = tostring(frame:GetAttribute("type") or "nil")
        local spell = tostring(frame:GetAttribute("spell") or "nil")
        local dueBuff = tostring(frame:GetAttribute("dreamfisher_duebuff") or "")
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
    if addon.audio and type(addon.audio.PlayWarningCue) == "function" then
        addon.audio.PlayWarningCue()
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
        if itemID and itemID > 0 then
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
    if addon.audio and type(addon.audio.PlayWarningCue) == "function" then
        addon.audio.PlayWarningCue()
    end
end

local function ShouldAbortPreCastForTransientBuffInUse()
    local itemID, transientRemaining = GetTransientCastBlocker()
    if not itemID then
        return false
    end

    WarnTransientCastBlocked(itemID, transientRemaining)
    DebugMessage("Aborting pre-cast: transient buff still active for "
        .. GetDebugItemLabel(itemID)
        .. " remaining=" .. string.format("%.1fs", math.max(0, transientRemaining or 0)))
    return true
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

    DebugMessage("Due buff helper unavailable; skipping due buff on this click")
    return nil, nil
end

local function ApplyDueBuffToSecureMacro(fishingFrame, macroLines, dueBuffItemID, dueBuffCategory)
    if dueBuffItemID then
        table.insert(macroLines, "/use item:" .. tostring(dueBuffItemID))
        if IsLureCategory(dueBuffCategory) then
            table.insert(macroLines, "/use 28") -- apply lure to fishing profession equipment slot
        end
        fishingFrame:SetAttribute("dreamfisher_duebuff", dueBuffItemID)
        DebugMessage("Fishing click will apply due buff: "
            .. GetDebugItemLabel(dueBuffItemID)
            .. " category=" .. tostring(dueBuffCategory)
            .. " " .. GetDebugCooldownText(dueBuffItemID))
    else
        fishingFrame:SetAttribute("dreamfisher_duebuff", nil)
    end
end

local function FinalizeSecureFishingAction(fishingFrame, macroLines, raftExclusiveWhileSwimming, bobberDecision)
    if #macroLines > 0 then
        if not raftExclusiveWhileSwimming then
            table.insert(macroLines, "/cast Fishing")
        end
        fishingFrame:SetAttribute("type", "macro")
        fishingFrame:SetAttribute("macrotext", table.concat(macroLines, "\n"))
        fishingFrame:SetAttribute("spell", nil)
        if raftExclusiveWhileSwimming then
            DebugMessage("Fishing click configured as raft-only pre-cast")
        elseif bobberDecision.shouldApply then
            DebugMessage("Fishing click configured to use bobber toy: "
                .. GetDebugItemLabel(bobberDecision.toyID) .. " " .. GetDebugCooldownText(bobberDecision.toyID))
        else
            DebugMessage("Fishing click configured with pre-cast items before Fishing")
        end
        return
    end

    fishingFrame:SetAttribute("type", "spell")
    fishingFrame:SetAttribute("spell", "Fishing")
    fishingFrame:SetAttribute("macrotext", nil)
    if bobberDecision.hasToy and bobberDecision.mounted then
        DebugMessage("Skipping bobber toy while mounted: " .. GetDebugItemLabel(bobberDecision.toyID))
    elseif bobberDecision.hasToy and bobberDecision.swimming then
        DebugMessage("Skipping bobber toy while swimming: " .. GetDebugItemLabel(bobberDecision.toyID))
    elseif bobberDecision.hasToy and not bobberDecision.ready then
        DebugMessage("Skipping bobber toy on cooldown: "
            .. GetDebugItemLabel(bobberDecision.toyID) .. " " .. GetDebugCooldownText(bobberDecision.toyID))
        DebugMessage("Fishing click configured as spell cast only")
    elseif bobberDecision.hasToy then
        DebugMessage("Fishing click configured as spell cast only; bobber not auto-used in current state: "
            .. GetDebugItemLabel(bobberDecision.toyID))
    else
        DebugMessage("Fishing click configured as spell cast only")
    end
end

ConfigureFishingClickAction = function()
    local fishingFrame = addon.frames.fishing
    if not fishingFrame then
        return
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
    if addon.fishing and addon.fishing.IsHookedLootMode and addon.fishing.IsHookedLootMode() then
        if addon.fishing.ConfigureInteractLootAction then
            addon.fishing.ConfigureInteractLootAction(fishingFrame)
            return
        end
    elseif addon.db and addon.db.enableHookedLoot then
        local now = (type(GetTime) == "function") and GetTime() or 0
        local graceUntil = tonumber(addon.state and addon.state.fishingStartGraceUntil) or 0
        DebugMessage("Hooked interact not armed: isFishing=" .. tostring(addon.state and addon.state.isFishing)
            .. " isBobberActive=" .. tostring(addon.state and addon.state.isBobberActive)
            .. " lootInProgress=" .. tostring(addon.state and addon.state.fishingLootInProgress)
            .. " graceRemaining=" .. string.format("%.2f", math.max(0, graceUntil - now)))
    end

    local raftDecision = GetRaftUseDecision()
    local bobberDecision = GetBobberUseDecision()
    local oversizedDecision = GetOversizedBobberDecision()
    local macroLines = {}
    local raftExclusiveWhileSwimming = false

    if raftDecision.shouldApply then
        table.insert(macroLines, "/use item:" .. tostring(raftDecision.toyID))
        DebugMessage("Fishing click will apply raft: "
            .. GetDebugItemLabel(raftDecision.toyID) .. " " .. GetDebugCooldownText(raftDecision.toyID))
        if raftDecision.swimming then
            raftExclusiveWhileSwimming = true
            DebugMessage("Raft needed while swimming; skipping other pre-cast items this click")
        end
    elseif raftDecision.hasToy and raftDecision.swimming and raftDecision.auraRemaining and not raftDecision.needsRefreshForCast then
        DebugMessage("Skipping raft reapply; aura covers cast: "
            .. GetDebugItemLabel(raftDecision.toyID)
            .. " auraRemaining=" .. string.format("%.1fs", raftDecision.auraRemaining))
    elseif raftDecision.hasToy
        and not raftDecision.ready
        and raftDecision.needsRefreshForCast
        and (raftDecision.swimming or raftDecision.auraRemaining ~= nil) then
        DebugMessage("Skipping raft toy on cooldown: "
            .. GetDebugItemLabel(raftDecision.toyID) .. " " .. GetDebugCooldownText(raftDecision.toyID))
    end

    if (not raftExclusiveWhileSwimming) and bobberDecision.shouldApply then
        table.insert(macroLines, "/use item:" .. tostring(bobberDecision.toyID))
        DebugMessage("Fishing click will apply bobber toy: "
            .. GetDebugItemLabel(bobberDecision.toyID) .. " " .. GetDebugCooldownText(bobberDecision.toyID))
    end

    if (not raftExclusiveWhileSwimming) and oversizedDecision.enabled then
        if oversizedDecision.shouldApply then
            table.insert(macroLines, "/use item:" .. tostring(OVERSIZED_BOBBER_ITEM_ID))
            DebugMessage("Fishing click will apply oversized bobber: "
                .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID) .. " " .. GetDebugCooldownText(OVERSIZED_BOBBER_ITEM_ID))
        elseif oversizedDecision.ready and oversizedDecision.swimming then
            DebugMessage("Skipping oversized bobber while swimming: "
                .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID))
        elseif oversizedDecision.available then
            DebugMessage("Skipping oversized bobber on cooldown: "
                .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID) .. " " .. GetDebugCooldownText(OVERSIZED_BOBBER_ITEM_ID))
        else
            DebugMessage("Skipping oversized bobber; toy not owned: " .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID))
        end
    end

    local dueBuffItemID, dueBuffCategory = ResolveSecurePreCastDueBuff(raftExclusiveWhileSwimming)
    ApplyDueBuffToSecureMacro(fishingFrame, macroLines, dueBuffItemID, dueBuffCategory)
    FinalizeSecureFishingAction(fishingFrame, macroLines, raftExclusiveWhileSwimming, bobberDecision)
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
        DebugMessage("Skipping due buff on cooldown this click: "
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
        local candidateItemID, unavailableInCategory = GetNextReadyDueBuffItemForCategory(category, excludedBuffItemIDs)
        hadUnavailableDueBuff = hadUnavailableDueBuff or unavailableInCategory
        if candidateItemID then
            return candidateItemID, hadUnavailableDueBuff, category
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
        singleRightClickConfig = ResolveBool(dbModes.singleRightClickConfig, defaultsModes.singleRightClickConfig),
        singleRightClickDoubleStart = ResolveBool(dbModes.singleRightClickDoubleStart, defaultsModes.singleRightClickDoubleStart),
        hotkey = ResolveBool(dbModes.hotkey, defaultsModes.hotkey),
    }

    if addon.db then
        addon.db.castingModes = modes
    end

    return modes
end

local function IsWorldRightClickActivationPressed()
    local modes = GetCastingModes()
    if modes.singleRightClickConfig and addon.frames.config and addon.frames.config:IsShown() then
        return true
    end
    if modes.doubleRightClick or modes.singleRightClickDoubleStart then
        return true
    end
    return false
end

local function IsHotkeyActivationPressed()
    local modes = GetCastingModes()
    return modes.hotkey
end

local function TryUseItemDirect(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return false
    end

    if C_Item and type(C_Item.UseItemByID) == "function" then
        local ok = pcall(C_Item.UseItemByID, numeric)
        if ok then
            return true
        end
    end

    if type(UseItemByName) == "function" then
        local ok = pcall(UseItemByName, "item:" .. tostring(numeric))
        if ok then
            return true
        end
    end

    return false
end

local function TryApplyFishingProfessionSlotDirect()
    if type(UseInventoryItem) == "function" then
        local ok = pcall(UseInventoryItem, 28)
        return ok and true or false
    end
    return false
end

local function TryUseBuffItemDirect(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return false
    end

    local bag, slot = addon.buff.FindItemInBags(numeric)
    local used = false
    if bag and slot then
        if C_Container and type(C_Container.UseContainerItem) == "function" then
            local ok = pcall(C_Container.UseContainerItem, bag, slot)
            used = ok and true or false
        elseif type(UseContainerItem) == "function" then
            local ok = pcall(UseContainerItem, bag, slot)
            used = ok and true or false
        end
    end

    if not used then
        used = TryUseItemDirect(numeric)
    end

    if used then
        local now = GetTime()
        addon.state.buffItemLastUseAt[numeric] = now
        addon.state.pendingBuffObservation = {
            itemID = numeric,
            before = addon.buff.BuildHelpfulAuraSnapshot(),
            expiresAt = now + 20,
        }
        addon.buff.AnnounceBuffUse(numeric)
        DebugMessage("Direct cast step used due buff: " .. GetDebugItemLabel(numeric))
        return true
    end

    DebugMessage("Direct cast step failed to use due buff: " .. GetDebugItemLabel(numeric))
    return false
end

local function StartFishingCastState()
    addon.audio.StartFishingAudioFocus()
    addon.state.isFishing = true
    addon.state.isBobberActive = true
    addon.state.fishingLootInProgress = false
    addon.fishing.EnableTemporaryAutoLoot()
end

local function TryCastFishingDirect()
    local casted = false
    local fishingSpellID = (addon.const and addon.const.fishingSpellID) or 131474
    local fishingSpellName = (addon.const and addon.const.fishingSpellName) or "Fishing"

    if type(CastSpellByID) == "function" then
        local ok = pcall(CastSpellByID, fishingSpellID)
        casted = ok and true or false
    end

    if not casted and type(CastSpellByName) == "function" then
        local ok = pcall(CastSpellByName, fishingSpellName)
        casted = ok and true or false
    end

    if casted then
        StartFishingCastState()
        DebugMessage("Direct cast step started fishing cast")
        return true
    end

    DebugMessage("Direct cast step could not cast Fishing")
    return false
end

local function HandleDirectCastStep()
    if InCombatLockdown() then
        DebugMessage("Direct cast ignored: in combat lockdown")
        return false
    end

    if ShouldAbortPreCastForTransientBuffInUse() then
        DebugMessage("Direct cast aborted: transient buff in progress")
        return true
    end

    local raftDecision = GetRaftUseDecision()
    if raftDecision.shouldApply and raftDecision.toyID then
        if TryUseItemDirect(raftDecision.toyID) then
            DebugMessage("Direct cast step used raft: " .. GetDebugItemLabel(raftDecision.toyID))
            return true
        end
        DebugMessage("Direct cast step failed raft use: " .. GetDebugItemLabel(raftDecision.toyID))
    end

    local bobberDecision = GetBobberUseDecision()
    if bobberDecision.shouldApply and bobberDecision.toyID then
        if TryUseItemDirect(bobberDecision.toyID) then
            DebugMessage("Direct cast step used bobber toy: " .. GetDebugItemLabel(bobberDecision.toyID))
            return true
        end
        DebugMessage("Direct cast step failed bobber toy use: " .. GetDebugItemLabel(bobberDecision.toyID))
    end

    local oversizedDecision = GetOversizedBobberDecision()
    if oversizedDecision.enabled and oversizedDecision.shouldApply then
        if TryUseItemDirect(OVERSIZED_BOBBER_ITEM_ID) then
            DebugMessage("Direct cast step used oversized bobber: "
                .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID))
            return true
        end
        DebugMessage("Direct cast step failed oversized bobber use: "
            .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID))
    end

    local hasConfiguredBuffItems = HasConfiguredBuffItems()
    if hasConfiguredBuffItems then
        local candidateItemID, hadUnavailableDueBuff, category = GetNextCastableDueBuffItem(
            "Direct cast skipping lure due buff; no fishing pole equipped in profession slot"
        )
        if candidateItemID and TryUseBuffItemDirect(candidateItemID) then
            if IsLureCategory(category) and not TryApplyFishingProfessionSlotDirect() then
                DebugMessage("Direct cast step could not apply lure to profession slot after item use")
            end
            return true
        end
        if hadUnavailableDueBuff then
            DebugMessage("Direct cast: due buff exists but unavailable")
        end
    end

    return TryCastFishingDirect()
end

local function BuildDueBuffMacroText(itemID, category)
    local bag, slot = addon.buff.FindItemInBags(itemID)
    local macroLines = {}
    if bag and slot then
        table.insert(macroLines, "/use " .. tostring(bag) .. " " .. tostring(slot))
    else
        table.insert(macroLines, "/use item:" .. tostring(itemID))
    end
    if IsLureCategory(category) then
        table.insert(macroLines, "/use 28")
    end
    return table.concat(macroLines, "\n")
end

local function ArmDueBuffRightClick(buffFrame, fishingFrame, pendingBuffItemID, pendingBuffCategory)
    if not buffFrame then
        DebugMessage("No secure buff frame available; skipping due buff binding")
        return false
    end

    local macrotext = BuildDueBuffMacroText(pendingBuffItemID, pendingBuffCategory)

    buffFrame:SetAttribute("type", "macro")
    buffFrame:SetAttribute("type2", "macro")
    buffFrame:SetAttribute("macrotext", macrotext)
    buffFrame:SetAttribute("macrotext2", macrotext)
    buffFrame:SetAttribute("item", nil)
    buffFrame:SetAttribute("item2", nil)
    buffFrame:SetAttribute("dreamfisher_itemid", pendingBuffItemID)
    DebugMessage("Double-click arming due buff: " .. GetDebugItemLabel(pendingBuffItemID)
        .. " category=" .. tostring(pendingBuffCategory)
        .. " " .. GetDebugCooldownText(pendingBuffItemID)
        .. " macro=" .. tostring(macrotext:gsub("\n", " | ")))

    if not InCombatLockdown() then
        if fishingFrame then
            ClearOverrideBindings(fishingFrame)
            fishingFrame:Hide()
        end
        SetOverrideBindingClick(buffFrame, true, "BUTTON2", buffFrame:GetName(), "RightButton")
    end
    buffFrame:Show()
    return true
end

local function ResolveRightClickPendingDueBuff(hasConfiguredBuffItems)
    if not hasConfiguredBuffItems then
        DebugMessage("No configured buff items in cast handler; skipping buff arm")
        return nil, false, nil
    end

    return GetNextCastableDueBuffItem(
        "Double-click skipping lure due buff; no fishing pole equipped in profession slot"
    )
end

local function ArmFishingRightClickAction(fishingFrame)
    if not fishingFrame then
        return false
    end

    ConfigureFishingClickAction()
    SetOverrideBindingClick(fishingFrame, true, "BUTTON2", fishingFrame:GetName(), "RightButton")
    -- Show the secure frame so the current click release can trigger the secure action.
    fishingFrame:Show()
    return true
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
    if frame then
        return frame
    end
    if addon.fishing and addon.fishing.CreateSecureFishingFrame then
        return addon.fishing.CreateSecureFishingFrame()
    end
    return frame
end

local function EnsureBuffSecureFrame(frame)
    if frame then
        return frame
    end
    if addon.fishing and addon.fishing.CreateSecureBuffFrame then
        return addon.fishing.CreateSecureBuffFrame()
    end
    return frame
end

local function GetInteractPresenceDiagnostics()
    local hasAnyInteractUnit = false
    local hasSoftInteractNameOnly = false

    if addon.fishing and addon.fishing.GetInteractDiagnostics then
        local diag = addon.fishing.GetInteractDiagnostics()
        hasAnyInteractUnit = diag and (diag.softExists or diag.targetExists or diag.mouseoverExists) and true or false
        hasSoftInteractNameOnly = diag
            and (not hasAnyInteractUnit)
            and type(diag.softName) == "string"
            and diag.softName ~= ""
            and true or false
    end

    return hasAnyInteractUnit, hasSoftInteractNameOnly
end

local function HandleWorldRightClick(forceImmediate)
    if InCombatLockdown() then
        DebugMessage("Right click ignored: in combat lockdown")
        return
    end

    if addon.db and addon.db.enableHookedLoot
        and addon.state and addon.state.interactOverrideActive
        and addon.fishing and addon.fishing.IsHookedLootMode
        and addon.fishing.IsHookedLootMode() then
        local hasAnyInteractUnit, hasSoftInteractNameOnly = GetInteractPresenceDiagnostics()
        local acquireExpiresAt = tonumber(addon.state.interactAcquireExpiresAt) or 0
        local inAcquireWindow = acquireExpiresAt > GetTime()

        if hasAnyInteractUnit or inAcquireWindow or hasSoftInteractNameOnly then
            DebugMessage("Hooked phase world right-click delegated to native interact override")
            return
        end

        DebugMessage("Stale hooked interact override with no target; clearing override and resuming cast flow")
        if addon.fishing.ClearNativeInteractOverride then
            addon.fishing.ClearNativeInteractOverride()
        else
            addon.state.interactOverrideActive = false
            addon.state.interactOverrideExpiresAt = 0
        end
        addon.state.interactAcquireExpiresAt = 0
    end

    local now = GetTime()
    DebugMessage("World right click: dt=" .. string.format("%.3f", now - addon.state.lastRightClickTime))
    local modes = GetCastingModes()
    local allowSingleClick = modes.singleRightClickConfig and addon.frames.config and addon.frames.config:IsShown() or false
    local hasConfiguredBuffItems = HasConfiguredBuffItems()
    local enableHookedLoot = addon.db and addon.db.enableHookedLoot

    local hasAnyInteractUnit = false
    if enableHookedLoot then
        hasAnyInteractUnit = GetInteractPresenceDiagnostics()
    end

    local graceUntil = tonumber(addon.state and addon.state.fishingStartGraceUntil) or 0
    local fishingStartTime = tonumber(addon.state and addon.state.fishingStartTime) or 0
    local fishingExpireSeconds = tonumber(addon.state and addon.state.fishingExpireSeconds) or 35
    local inFishingWindow = addon.state and (
        addon.state.isFishing
        or addon.state.isBobberActive
        or (fishingStartTime > 0 and (now - fishingStartTime) <= (fishingExpireSeconds + 2))
    ) or false
    local postCastHookWindow = addon.state
        and addon.state.isFishing
        and (now >= graceUntil)
        and (not addon.state.fishingLootInProgress)
        and true or false

    local hookedModeActive = enableHookedLoot
        and addon.fishing and addon.fishing.IsHookedLootMode
        and addon.fishing.IsHookedLootMode()
    local shouldRouteHookedInteract = enableHookedLoot
        and (hookedModeActive or (hasAnyInteractUnit and inFishingWindow) or postCastHookWindow)

    local buffFrame = addon.frames.buff
    local fishingFrame = addon.frames.fishing

    if shouldRouteHookedInteract then
        addon.state.lastRightClickTime = 0
        fishingFrame = EnsureFishingSecureFrame(fishingFrame)

        if fishingFrame and not InCombatLockdown() then
            if buffFrame then
                ClearRightClickBuffFrameState(buffFrame, true)
            end
            ArmFishingRightClickAction(fishingFrame)
            if (not hookedModeActive) and hasAnyInteractUnit and inFishingWindow then
                DebugMessage("Hooked interact fallback active: routing right-click to interact target")
            elseif (not hookedModeActive) and postCastHookWindow then
                DebugMessage("Hooked interact timing fallback active: routing right-click during post-cast hook window")
            end
            DebugMessage("Hooked phase world right-click routed to interact action")
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

    if forceImmediate or allowSingleClick or (now - addon.state.lastRightClickTime) <= (addon.state.doubleClickWindow + 0.001) then
        addon.state.lastRightClickTime = 0
        if ShouldAbortPreCastForTransientBuffInUse() then
            return
        end
        local raftDecision = GetRaftUseDecision()
        if raftDecision.shouldApply and raftDecision.swimming then
            if allowSingleClick then
                DebugMessage("Config window open: single right-click applying raft before cast")
            end
            DebugMessage("Click-cast routing to raft-only pre-cast while swimming")
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

        local pendingBuffItemID, hadUnavailableDueBuff, pendingBuffCategory = ResolveRightClickPendingDueBuff(hasConfiguredBuffItems)

        if pendingBuffItemID then
            if allowSingleClick then
                DebugMessage("Config window open: single right-click using due buff")
            end
            buffFrame = addon.frames.buff
            if not ArmDueBuffRightClick(buffFrame, fishingFrame, pendingBuffItemID, pendingBuffCategory) then
                return
            end
            return
        end

        -- Double-click detected with no due buffs: initiate fishing
        if buffFrame then
            ClearRightClickBuffFrameState(buffFrame, false)
        end
        addon.audio.StartFishingAudioFocus()
        local now = (type(GetTime) == "function") and GetTime() or 0
        -- Mark a pre-cast fishing session for audio/tests. Hooked mode is
        -- still blocked by grace-window gating until cast has transitioned.
        addon.state.isFishing = true
        addon.state.isBobberActive = true
        addon.state.fishingStartTime = now
        addon.state.fishingStartGraceUntil = now + 1.5
        addon.state.fishingLootInProgress = false
        addon.state.interactAcquireExpiresAt = 0

        if hadUnavailableDueBuff then
            DebugMessage("No usable due buffs; starting fishing cast")
        else
            DebugMessage("No due buffs; starting fishing cast")
        end
        if allowSingleClick then
            DebugMessage("Config window open: single right-click starting fishing")
        end
        if not InCombatLockdown() then
            buffFrame = addon.frames.buff
            if buffFrame then
                ClearRightClickBuffFrameState(buffFrame, true)
            end
            local fishingFrame = addon.frames.fishing
            if fishingFrame then
                ArmFishingRightClickAction(fishingFrame)
            end
        end
    else
        addon.state.lastRightClickTime = now
        DebugMessage("Single right-click: no addon action (awaiting second click)")
        if not InCombatLockdown() then
            if fishingFrame then
                ClearRightClickFishingFrameState(fishingFrame, true)
            end
            buffFrame = addon.frames.buff
            if buffFrame then
                ClearRightClickBuffFrameState(buffFrame, true)
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

    -- Legacy callback path. Real hotkey casting is now done through
    -- CLICK DreamFisherSecureFishingButton:RightButton in Bindings.xml.
    DebugMessage("Hotkey callback path is deprecated; use CLICK binding")
    return true
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
