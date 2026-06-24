-- DreamFisher: Fishing Casting and World Right-Click Handler

local addon = _G["DreamFisher"]
local DebugMessage = addon.DebugMessage
local OVERSIZED_BOBBER_ITEM_ID = 202207

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
    local shouldApply = hasToy and bobberReady and not mounted

    return {
        toyID = bobberToyID,
        hasToy = hasToy,
        ready = bobberReady,
        mounted = mounted,
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

    return {
        enabled = true,
        available = available,
        ready = ready,
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
    -- Accept both down and up because the override binding may resolve on either edge.
    if frame.RegisterForClicks then
        frame:RegisterForClicks("AnyDown", "AnyUp")
    end
    frame:Hide()
    frame:HookScript("OnClick", function()
        local actionType = tostring(frame:GetAttribute("type") or "nil")
        local spell = tostring(frame:GetAttribute("spell") or "nil")
        local macrotext = tostring(frame:GetAttribute("macrotext") or "")
        if macrotext ~= "" then
            local firstLine = macrotext:match("([^\n]+)") or macrotext
            DebugMessage("Fishing secure click fired: type=" .. actionType .. " macro=" .. tostring(firstLine))
        else
            DebugMessage("Fishing secure click fired: type=" .. actionType .. " spell=" .. spell)
        end
        if not InCombatLockdown() then
            ClearOverrideBindings(frame)
        end
        ResetFishingFrameState(frame)
        frame:Hide()
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
        frame:RegisterForClicks("AnyDown", "AnyUp")
    end
    frame:Hide()
    frame:HookScript("OnClick", function(self)
        local itemID = tonumber(self:GetAttribute("dreamfisher_itemid"))
        DebugMessage("Secure buff click fired: item=" .. GetDebugItemLabel(itemID)
            .. " item=" .. tostring(self:GetAttribute("item"))
            .. " item2=" .. tostring(self:GetAttribute("item2")))
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

local function ConfigureFishingClickAction()
    local fishingFrame = addon.frames.fishing
    if not fishingFrame then
        return
    end

    ResetFishingFrameState(fishingFrame)
    local bobberDecision = GetBobberUseDecision()
    local oversizedDecision = GetOversizedBobberDecision()
    local macroLines = {}

    if oversizedDecision.enabled then
        if oversizedDecision.ready then
            table.insert(macroLines, "/use item:" .. tostring(OVERSIZED_BOBBER_ITEM_ID))
            DebugMessage("Fishing click will apply oversized bobber: "
                .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID) .. " " .. GetDebugCooldownText(OVERSIZED_BOBBER_ITEM_ID))
        elseif oversizedDecision.available then
            DebugMessage("Skipping oversized bobber on cooldown: "
                .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID) .. " " .. GetDebugCooldownText(OVERSIZED_BOBBER_ITEM_ID))
        else
            DebugMessage("Skipping oversized bobber; toy not owned: " .. GetDebugItemLabel(OVERSIZED_BOBBER_ITEM_ID))
        end
    end

    if bobberDecision.shouldApply then
        table.insert(macroLines, "/use item:" .. tostring(bobberDecision.toyID))
    end

    if #macroLines > 0 then
        table.insert(macroLines, "/cast Fishing")
        fishingFrame:SetAttribute("type", "macro")
        fishingFrame:SetAttribute("macrotext", table.concat(macroLines, "\n"))
        fishingFrame:SetAttribute("spell", nil)
        if bobberDecision.shouldApply then
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

local function GetCastingMode()
    if not addon.db then
        return addon.defaults.castingMode or "doubleRightClick"
    end
    return tostring(addon.db.castingMode or addon.defaults.castingMode or "doubleRightClick")
end

local function IsWorldRightClickActivationPressed()
    local mode = GetCastingMode()
    if mode == "modifierRightClick" then
        local modifier = string.upper(tostring((addon.db and addon.db.worldRightClickModifier) or addon.defaults.worldRightClickModifier or "ALT"))
        if modifier == "NONE" then
            return true
        end
        if modifier == "ALT" then
            return IsAltKeyDown and IsAltKeyDown()
        end
        if modifier == "CTRL" or modifier == "CONTROL" then
            return IsControlKeyDown and IsControlKeyDown()
        end
        if modifier == "SHIFT" then
            return IsShiftKeyDown and IsShiftKeyDown()
        end
        return IsAltKeyDown and IsAltKeyDown()
    end
    if mode == "singleRightClickConfig" then
        return addon.frames.config and addon.frames.config:IsShown() or false
    end
    if mode == "hotkeyNotImplemented" then
        return false
    end
    if mode == "doubleRightClick" or mode == "singleRightClickDoubleStart" then
        return true
    end
    local modifier = string.upper(tostring((addon.db and addon.db.worldRightClickModifier) or addon.defaults.worldRightClickModifier or "ALT"))
    if modifier == "NONE" then
        return true
    end
    if modifier == "ALT" then
        return IsAltKeyDown and IsAltKeyDown()
    end
    if modifier == "CTRL" or modifier == "CONTROL" then
        return IsControlKeyDown and IsControlKeyDown()
    end
    if modifier == "SHIFT" then
        return IsShiftKeyDown and IsShiftKeyDown()
    end
    return IsAltKeyDown and IsAltKeyDown()
end

local function HandleWorldRightClick()
    if InCombatLockdown() then
        DebugMessage("Right click ignored: in combat lockdown")
        return
    end

    local now = GetTime()
    DebugMessage("World right click: dt=" .. string.format("%.3f", now - addon.state.lastRightClickTime))
    local allowSingleClick = addon.frames.config and addon.frames.config:IsShown()
    local hasConfiguredBuffItems = HasConfiguredBuffItems()

    local buffFrame = addon.frames.buff
    local fishingFrame = addon.frames.fishing

    if not hasConfiguredBuffItems and buffFrame then
        buffFrame:Hide()
        ResetBuffFrameState(buffFrame)
        if not InCombatLockdown() then
            ClearOverrideBindings(buffFrame)
        end
        addon.state.pendingBuffObservation = nil
    end

    if not fishingFrame and addon.fishing and addon.fishing.CreateSecureFishingFrame then
        fishingFrame = addon.fishing.CreateSecureFishingFrame()
    end
    if not buffFrame and addon.fishing and addon.fishing.CreateSecureBuffFrame then
        buffFrame = addon.fishing.CreateSecureBuffFrame()
    end

    if buffFrame and buffFrame:IsShown() then
        local currentlyDueItemID = addon.buff.GetNextDueBuffItem(true)
        local armedItemID = tonumber(buffFrame:GetAttribute("dreamfisher_itemid"))
        if currentlyDueItemID and armedItemID and currentlyDueItemID == armedItemID and IsItemReadyForUse(armedItemID) then
            DebugMessage("Buff secure frame already shown; awaiting secure click")
            return
        end

        DebugMessage("Clearing stale secure buff click state")
        buffFrame:Hide()
        ResetBuffFrameState(buffFrame)
        if not InCombatLockdown() then
            ClearOverrideBindings(buffFrame)
        end
    end

    if fishingFrame and fishingFrame:IsShown() then
        DebugMessage("Clearing stale secure fishing click state")
        ResetFishingFrameState(fishingFrame)
        fishingFrame:Hide()
        if not InCombatLockdown() then
            ClearOverrideBindings(fishingFrame)
        end
    end

    if allowSingleClick or (now - addon.state.lastRightClickTime) <= (addon.state.doubleClickWindow + 0.001) then
        addon.state.lastRightClickTime = 0
        local pendingBuffItemID = nil
        local hadUnavailableDueBuff = false
        if hasConfiguredBuffItems then
            local excludedBuffItemIDs = {}
            while true do
                local candidateItemID, dueStatus = addon.buff.GetNextDueBuffItem(true, excludedBuffItemIDs)
                if not candidateItemID then
                    hadUnavailableDueBuff = (dueStatus == "due_unavailable") or hadUnavailableDueBuff
                    break
                end

                if IsItemReadyForUse(candidateItemID) then
                    pendingBuffItemID = candidateItemID
                    break
                end

                DebugMessage("Skipping due buff on cooldown this click: "
                    .. GetDebugItemLabel(candidateItemID) .. " " .. GetDebugCooldownText(candidateItemID))
                excludedBuffItemIDs[candidateItemID] = true
            end
        else
            DebugMessage("No configured buff items in cast handler; skipping buff arm")
        end

        if pendingBuffItemID then
            if allowSingleClick then
                DebugMessage("Config window open: single right-click using due buff")
            end
            buffFrame = addon.frames.buff
            if not buffFrame then
                DebugMessage("No secure buff frame available; skipping due buff binding")
                return
            end
            local bag, slot = addon.buff.FindItemInBags(pendingBuffItemID)
            buffFrame:SetAttribute("type", "item")
            buffFrame:SetAttribute("type2", "item")
            if bag and slot then
                buffFrame:SetAttribute("item", tostring(bag) .. " " .. tostring(slot))
                buffFrame:SetAttribute("item2", tostring(bag) .. " " .. tostring(slot))
            else
                buffFrame:SetAttribute("item", "item:" .. tostring(pendingBuffItemID))
                buffFrame:SetAttribute("item2", "item:" .. tostring(pendingBuffItemID))
            end
            buffFrame:SetAttribute("dreamfisher_itemid", pendingBuffItemID)
            DebugMessage("Double-click arming due buff: " .. GetDebugItemLabel(pendingBuffItemID)
                .. " " .. GetDebugCooldownText(pendingBuffItemID)
                .. " item2=" .. tostring(buffFrame:GetAttribute("item2")))
            if not InCombatLockdown() then
                if fishingFrame then
                    ClearOverrideBindings(fishingFrame)
                    fishingFrame:Hide()
                end
                SetOverrideBindingClick(buffFrame, true, "BUTTON2", buffFrame:GetName(), "RightButton")
            end
            buffFrame:Show()
            return
        end

        -- Double-click detected with no due buffs: initiate fishing
        if buffFrame then
            buffFrame:Hide()
            ResetBuffFrameState(buffFrame)
        end
        addon.audio.StartFishingAudioFocus()
        addon.state.isFishing = true
        addon.state.isBobberActive = true
        addon.state.fishingLootInProgress = false
        addon.fishing.EnableTemporaryAutoLoot()

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
                ClearOverrideBindings(buffFrame)
            end
            local fishingFrame = addon.frames.fishing
            if fishingFrame then
                ConfigureFishingClickAction()
                SetOverrideBindingClick(fishingFrame, true, "BUTTON2", fishingFrame:GetName(), "RightButton")
                -- Show the secure frame so the current click release can trigger the secure action.
                fishingFrame:Show()
            end
        end
    else
        addon.state.lastRightClickTime = now
        DebugMessage("Single right-click: no addon action (awaiting second click)")
        if not InCombatLockdown() then
            if fishingFrame then
                ClearOverrideBindings(fishingFrame)
                ResetFishingFrameState(fishingFrame)
                fishingFrame:Hide()
            end
            buffFrame = addon.frames.buff
            if buffFrame then
                ClearOverrideBindings(buffFrame)
                buffFrame:Hide()
                ResetBuffFrameState(buffFrame)
            end
        end
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
addon.fishing.HandleWorldRightClick = HandleWorldRightClick
addon.fishing.IsFishingCast = IsFishingCast

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
