-- DreamFisher: Fishing Casting and World Right-Click Handler

local addon = _G["DreamFisher"]
local DebugMessage = addon.DebugMessage

local function CreateSecureFishingFrame()
    if addon.frames.fishing then
        return addon.frames.fishing
    end

    local frame = CreateFrame("Button", "DreamFisherSecureFishingButton", UIParent, "SecureActionButtonTemplate")
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetAttribute("type", "spell")
    frame:SetAttribute("spell", "Fishing")
    frame:RegisterForClicks("AnyDown")
    frame:Hide()
    frame:HookScript("OnClick", function()
        if not InCombatLockdown() then
            ClearOverrideBindings(frame)
        end
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
    frame:EnableMouse(true)
    frame:SetAttribute("type", "item")
    frame:SetAttribute("type2", "item")
    frame:RegisterForClicks("AnyDown", "AnyUp")
    frame:Hide()
    frame:HookScript("OnClick", function(self)
        local itemID = tonumber(self:GetAttribute("dreamfisher_itemid"))
        DebugMessage("Secure buff click fired: itemID=" .. tostring(itemID)
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
        self:Hide()
        if not InCombatLockdown() then
            ClearOverrideBindings(self)
        end
    end)

    addon.frames.buff = frame
    return addon.frames.buff
end

local function IsWorldRightClickActivationPressed()
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

    local buffFrame = addon.frames.buff
    if buffFrame and buffFrame:IsShown() then
        DebugMessage("Buff secure frame already shown; awaiting secure click")
        return
    end

    if allowSingleClick or now - addon.state.lastRightClickTime < addon.state.doubleClickWindow then
        addon.state.lastRightClickTime = 0
        local pendingBuffItemID = addon.buff.GetNextDueBuffItem(true)
        if pendingBuffItemID then
            if allowSingleClick then
                DebugMessage("Config window open: single right-click using due buff")
            end
            buffFrame = addon.frames.buff
            local bag, slot = addon.buff.FindItemInBags(pendingBuffItemID)
            if bag and slot then
                buffFrame:SetAttribute("item", tostring(bag) .. " " .. tostring(slot))
                buffFrame:SetAttribute("item2", tostring(bag) .. " " .. tostring(slot))
            else
                buffFrame:SetAttribute("item", "item:" .. tostring(pendingBuffItemID))
                buffFrame:SetAttribute("item2", "item:" .. tostring(pendingBuffItemID))
            end
            buffFrame:SetAttribute("dreamfisher_itemid", pendingBuffItemID)
            DebugMessage("Double-click arming due buff: itemID=" .. tostring(pendingBuffItemID)
                .. " item2=" .. tostring(buffFrame:GetAttribute("item2")))
            if not InCombatLockdown() then
                local fishingFrame = addon.frames.fishing
                if fishingFrame then
                    ClearOverrideBindings(fishingFrame)
                end
                SetOverrideBindingClick(buffFrame, true, "BUTTON2", buffFrame:GetName())
            end
            buffFrame:Show()
            return
        end

        -- Double-click detected with no due buffs: initiate fishing
        addon.audio.StartFishingAudioFocus()
        addon.state.isFishing = true
        addon.state.isBobberActive = true
        addon.state.fishingLootInProgress = false
        addon.fishing.EnableTemporaryAutoLoot()
        DebugMessage("No due buffs; starting fishing cast")
        if allowSingleClick then
            DebugMessage("Config window open: single right-click starting fishing")
        end
        if not InCombatLockdown() then
            buffFrame = addon.frames.buff
            if buffFrame then
                ClearOverrideBindings(buffFrame)
            end
            SetOverrideBindingClick(addon.frames.fishing, true, "BUTTON2", addon.frames.fishing:GetName())
        end
    else
        addon.state.lastRightClickTime = now
        DebugMessage("Single right-click: no addon action (awaiting second click)")
        if not InCombatLockdown() then
            local fishingFrame = addon.frames.fishing
            if fishingFrame then
                ClearOverrideBindings(fishingFrame)
            end
            buffFrame = addon.frames.buff
            if buffFrame then
                ClearOverrideBindings(buffFrame)
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
