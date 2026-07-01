-- DreamFisher Config UI Module
-- Manages configuration panel and settings UI

local addonName = "DreamFisher"
local addon = _G[addonName]

-- Config module namespace
addon.config = addon.config or {}
local config = addon.config

-- Local references to globals
local maxBuffSlots = addon.const.maxBuffSlots or 6
local defaults = addon.defaults
local uiBuffCursorDragState = nil
local buffItemLastUseAt = {}
local buffItemLastKnownCount = {}
local suppressLiveSave = false
local SaveLive
local aceGUI = nil

local function TryGetAceGUI()
    if aceGUI then
        return aceGUI
    end

    local libStub = _G.LibStub
    if type(libStub) ~= "table" and type(libStub) ~= "function" then
        return nil
    end

    local ok, lib = pcall(libStub.GetLibrary, libStub, "AceGUI-3.0", true)
    if ok and lib then
        aceGUI = lib
        return aceGUI
    end

    return nil
end

config.TryGetAceGUI = TryGetAceGUI

local function BuildOwnedToyOptions(candidateIDs, includeDefaultLabel)
    local options = {}
    local seen = {}

    if type(includeDefaultLabel) == "string" and includeDefaultLabel ~= "" then
        table.insert(options, {
            value = 0,
            label = includeDefaultLabel,
        })
    end

    if type(candidateIDs) ~= "table" then
        return options
    end

    for _, itemID in ipairs(candidateIDs) do
        local numeric = tonumber(itemID)
        if numeric and numeric > 0 and not seen[numeric] then
            seen[numeric] = true
            if type(PlayerHasToy) ~= "function" or PlayerHasToy(numeric) then
                table.insert(options, {
                    value = numeric,
                    label = (addon.utils and addon.utils.GetToyLabel and addon.utils.GetToyLabel(numeric)) or tostring(numeric),
                })
            end
        end
    end

    return options
end

local function CollectActiveBuffItemIDs(buffItems)
    local active = {}
    if type(buffItems) ~= "table" then
        return active
    end
    for _, entry in ipairs(buffItems) do
        local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
        if itemID and itemID > 0 then
            active[itemID] = true
        end
    end
    return active
end

local function ResolveExpectedDurationForItem(itemID, fallbackSeconds)
    local numeric = tonumber(itemID)
    local fallback = tonumber(fallbackSeconds) or (addon.db and addon.db.refreshSeconds) or defaults.refreshSeconds
    if not numeric or numeric <= 0 then
        return addon.Clamp(fallback, 30, 3600)
    end

    if addon.db and type(addon.db.buffAuraByItem) == "table" then
        local tracked = addon.db.buffAuraByItem[tostring(numeric)]
        if type(tracked) == "table" and tonumber(tracked.duration) and tonumber(tracked.duration) > 0 then
            return addon.Clamp(tonumber(tracked.duration), 30, 3600)
        end
    end

    if addon.db and type(addon.db.buffItems) == "table" then
        for _, entry in ipairs(addon.db.buffItems) do
            local entryItemID = type(entry) == "table" and tonumber(entry.itemID) or nil
            if entryItemID == numeric then
                local expected = tonumber(entry.expectedDuration) or tonumber(entry.refreshSeconds)
                if expected and expected > 0 then
                    return addon.Clamp(expected, 30, 3600)
                end
                break
            end
        end
    end

    return addon.Clamp(fallback, 30, 3600)
end

local function ResolveBool(value, defaultValue)
    if value == nil then
        return not not defaultValue
    end
    return not not value
end

local function GetCastingModesForConfig()
    local defaultsModes = defaults.castingModes or {}
    local dbModes = (addon.db and addon.db.castingModes) or {}
    local modes = {
        doubleRightClick = ResolveBool(dbModes.doubleRightClick, defaultsModes.doubleRightClick),
        singleRightClickConfig = ResolveBool(dbModes.singleRightClickConfig, defaultsModes.singleRightClickConfig),
        singleRightClickDoubleStart = ResolveBool(dbModes.singleRightClickDoubleStart, defaultsModes.singleRightClickDoubleStart),
        hotkey = ResolveBool(dbModes.hotkey, defaultsModes.hotkey),
    }
    return modes
end

local function UpdateToyApplyButtons()
    local function SyncButton(button, selector, baseLabel)
        if not button then
            return
        end
        local toyID = selector and tonumber(selector:GetText()) or nil
        if toyID and toyID > 0 then
            button:SetAttribute("type", "toy")
            button:SetAttribute("toy", toyID)
            button:SetText(baseLabel)
            button:Enable()
        else
            button:SetAttribute("toy", nil)
            button:SetText(baseLabel .. " (none)")
            button:Disable()
        end
    end

    SyncButton(addon.bobberApplyButton, addon.bobberSelector, "Apply Bobber")
    SyncButton(addon.raftApplyButton, addon.raftSelector, "Apply Raft")
end

local function SyncEscapeCloseRegistration()
    if type(UISpecialFrames) ~= "table" then
        return
    end

    local panel = addon.frames and addon.frames.config
    local frameName = panel and panel:GetName() or nil
    if not frameName or frameName == "" then
        return
    end

    local shouldRegister = addon.db and addon.db.configCloseOnEscape
    local existingIndex = nil
    for i, name in ipairs(UISpecialFrames) do
        if name == frameName then
            existingIndex = i
            break
        end
    end

    if shouldRegister and not existingIndex then
        table.insert(UISpecialFrames, frameName)
    elseif not shouldRegister and existingIndex then
        table.remove(UISpecialFrames, existingIndex)
    end
end

-- Helper: Update all config UI elements from saved data
local function UpdateConfigUI()
    if not addon.frames.config or not addon.db then
        return
    end

    suppressLiveSave = true

    if addon.autoLootCheckbox then
        addon.autoLootCheckbox:SetChecked(addon.db.autoLoot)
    end
    if addon.enhancedSoundsCheckbox then
        addon.enhancedSoundsCheckbox:SetChecked(addon.db.enhancedSounds)
    end
    if addon.treasureAlertsCheckbox then
        addon.treasureAlertsCheckbox:SetChecked(addon.db.treasureAlerts)
    end
    if addon.bagAlertsCheckbox then
        addon.bagAlertsCheckbox:SetChecked(addon.db.bagAlerts)
    end
    if addon.escapeCloseCheckbox then
        addon.escapeCloseCheckbox:SetChecked(addon.db.configCloseOnEscape)
    end
    if addon.lowBagBox then
        addon.lowBagBox:SetText(tostring(addon.db.lowBagThreshold or defaults.lowBagThreshold))
    end
    if addon.buffItemControls then
        for i, control in ipairs(addon.buffItemControls) do
            local entry = addon.db.buffItems and addon.db.buffItems[i] or nil
            local itemID = entry and entry.itemID or nil
            local expectedDuration = ResolveExpectedDurationForItem(itemID, entry and (entry.expectedDuration or entry.refreshSeconds))
            control.itemBox:SetText(tostring(itemID or ""))
            if control.itemBox.SetExpectedDuration then
                control.itemBox:SetExpectedDuration(expectedDuration)
            end
        end
    end
    if addon.audioLingerBox then
        addon.audioLingerBox:SetText(tostring(addon.db.audioFocusLinger or defaults.audioFocusLinger))
    end
    if addon.modeDoubleRightClickCheckbox then
        local modes = GetCastingModesForConfig()
        addon.modeDoubleRightClickCheckbox:SetChecked(modes.doubleRightClick)
        addon.modeSingleRightClickConfigCheckbox:SetChecked(modes.singleRightClickConfig)
        addon.modeHotkeyCheckbox:SetChecked(modes.hotkey)
    end
    if addon.underlightAnglerCheckbox then
        addon.underlightAnglerCheckbox:SetChecked(addon.db.useUnderlightAngler)
    end
    if addon.enableHookedLootCheckbox then
        addon.enableHookedLootCheckbox:SetChecked(addon.db.enableHookedLoot)
    end
    if addon.bobberSelector then
        addon.bobberSelector:RefreshOptions()
        addon.bobberSelector:SetText(addon.db.selectedBobberToy or nil)
    end
    if addon.raftSelector then
        addon.raftSelector:RefreshOptions()
        addon.raftSelector:SetText(addon.db.selectedRaftToy or nil)
    end
    if addon.oversizedBobberCheckbox then
        addon.oversizedBobberCheckbox:SetChecked(addon.db.useOversizedBobber)
    end

    UpdateToyApplyButtons()

    suppressLiveSave = false
end

-- Save config from UI back to database
function config.SaveConfig(skipRefresh)
    if not addon.db then
        return
    end

    local previouslyActiveBuffItems = CollectActiveBuffItemIDs(addon.db.buffItems)

    addon.db.refreshSeconds = addon.Clamp(tonumber(addon.db.refreshSeconds) or defaults.refreshSeconds, 30, 600)
    addon.db.lowBagThreshold = addon.Clamp(tonumber(addon.lowBagBox:GetText()) or defaults.lowBagThreshold, 0, 20)
    addon.db.audioFocusLinger = addon.Clamp(tonumber(addon.audioLingerBox:GetText()) or defaults.audioFocusLinger, 0, 60)
    addon.db.autoLoot = addon.autoLootCheckbox:GetChecked()
    addon.db.enhancedSounds = addon.enhancedSoundsCheckbox:GetChecked()
    addon.db.treasureAlerts = addon.treasureAlertsCheckbox:GetChecked()
    addon.db.bagAlerts = addon.bagAlertsCheckbox:GetChecked()
    local modeFlags = {
        doubleRightClick = addon.modeDoubleRightClickCheckbox and addon.modeDoubleRightClickCheckbox:GetChecked() or false,
        singleRightClickConfig = addon.modeSingleRightClickConfigCheckbox and addon.modeSingleRightClickConfigCheckbox:GetChecked() or false,
        hotkey = addon.modeHotkeyCheckbox and addon.modeHotkeyCheckbox:GetChecked() or false,
    }
    addon.db.castingModes = modeFlags
    addon.db.useUnderlightAngler = addon.underlightAnglerCheckbox and addon.underlightAnglerCheckbox:GetChecked()
    addon.db.enableHookedLoot = addon.enableHookedLootCheckbox and addon.enableHookedLootCheckbox:GetChecked() or false
    addon.db.useOversizedBobber = addon.oversizedBobberCheckbox and addon.oversizedBobberCheckbox:GetChecked()
    if addon.escapeCloseCheckbox then
        addon.db.configCloseOnEscape = addon.escapeCloseCheckbox:GetChecked()
    end
    SyncEscapeCloseRegistration()

    if addon.buffItemControls then
        local previousBuffItems = addon.db.buffItems or {}
        addon.db.buffItems = {}
        for i, control in ipairs(addon.buffItemControls) do
            local itemID = tonumber(control.itemBox:GetText())
            local previous = previousBuffItems[i]
            local previousExpected = type(previous) == "table" and (tonumber(previous.expectedDuration) or tonumber(previous.refreshSeconds)) or nil
            local expectedDuration = ResolveExpectedDurationForItem(itemID, previousExpected)
            if control.itemBox.GetExpectedDuration then
                expectedDuration = addon.Clamp(tonumber(control.itemBox:GetExpectedDuration()) or expectedDuration, 30, 3600)
            end
            addon.db.buffItems[i] = {
                itemID = (itemID and itemID > 0) and itemID or nil,
                expectedDuration = expectedDuration,
            }
        end
    end

    local currentlyActiveBuffItems = CollectActiveBuffItemIDs(addon.db.buffItems)
    for removedItemID, _ in pairs(previouslyActiveBuffItems) do
        if not currentlyActiveBuffItems[removedItemID] then
            if addon.state then
                addon.state.buffItemLastUseAt[removedItemID] = nil
                addon.state.buffItemLastReminderAt[removedItemID] = nil
                if addon.state.buffItemLastReminderCastAnchor then
                    addon.state.buffItemLastReminderCastAnchor[removedItemID] = nil
                end
                addon.state.buffItemLastMissingWarningAt[removedItemID] = nil
                addon.state.buffItemLastKnownCount[removedItemID] = nil
            end
            if addon.db.buffAuraByItem then
                addon.db.buffAuraByItem[tostring(removedItemID)] = nil
            end
        end
    end

    if addon.bobberSelector then
        local selectedBobberToy = tonumber(addon.bobberSelector:GetText())
        addon.db.selectedBobberToy = (selectedBobberToy and selectedBobberToy > 0) and selectedBobberToy or nil
    end
    if addon.raftSelector then
        local selectedRaftToy = tonumber(addon.raftSelector:GetText())
        addon.db.selectedRaftToy = (selectedRaftToy and selectedRaftToy > 0) and selectedRaftToy or nil
    end

    UpdateToyApplyButtons()

    if addon.buff and addon.buff.NormalizeBuffConfig then
        addon.buff.NormalizeBuffConfig()
    end

    if addon.state.savedFishingAudioCVars ~= nil and addon.state.audioRestoreAt ~= nil then
        if addon.audio and addon.audio.RestoreFishingAudioFocusAfterLinger then
            addon.audio.RestoreFishingAudioFocusAfterLinger()
        end
    end

    if not skipRefresh then
        UpdateConfigUI()
    end
end

-- Create and return the config panel frame
function config.CreateConfigPanel()
    if addon.frames.config then
        return addon.frames.config
    end

    local panel = nil
    local aceGUIInstance = TryGetAceGUI()
    if not aceGUIInstance then
        return nil
    end

    local aceWindow = aceGUIInstance:Create("Frame")
    aceWindow:SetTitle(addonName .. " Settings")
    aceWindow:SetStatusText("")
    aceWindow:SetLayout("Fill")
    aceWindow:SetWidth(520)
    aceWindow:SetHeight(690)
    if aceWindow.EnableResize then
        aceWindow:EnableResize(false)
    end
    panel = aceWindow.frame
    panel.aceWindow = aceWindow
    panel:Hide()

    local function SavePanelPosition(self)
        if addon.db then
            local point, _, relativePoint, x, y = self:GetPoint(1)
            addon.db.configWindowPosition = {
                point = point or "CENTER",
                relativePoint = relativePoint or "CENTER",
                x = math.floor((x or 0) + 0.5),
                y = math.floor((y or 0) + 0.5),
            }
        end
    end

    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:EnableKeyboard(false)
    panel:RegisterForDrag("LeftButton")
    panel:HookScript("OnDragStop", function(self)
        SavePanelPosition(self)
    end)

    if addon.db and type(addon.db.configWindowPosition) == "table" then
        local pos = addon.db.configWindowPosition
        panel:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", tonumber(pos.x) or 0, tonumber(pos.y) or 0)
    else
        panel:SetPoint("CENTER")
    end
    panel:Hide()

    addon.frames.config = panel
    SyncEscapeCloseRegistration()

    local ShowTab = nil
    local focusPage = nil
    local tacklePage = nil
    local buffsPage = nil
    local modesPage = nil

    local function BuildTabScaffold()
        local tabLabels = {
            focus = "Focus",
            tackle = "Tackle",
            buffs = "Buffs",
            modes = "Modes",
        }

        panel.tabButtons = {}
        panel.pages = {}
        panel.activeTab = "focus"

        ShowTab = function(tabName)
            panel.activeTab = tabName
            for name, page in pairs(panel.pages) do
                page:SetShown(name == tabName)
            end
            for name, button in pairs(panel.tabButtons) do
                if name == tabName then
                    button:Disable()
                else
                    button:Enable()
                end
            end
        end

        local aceTabGroup = aceGUIInstance:Create("TabGroup")
        aceTabGroup:SetLayout("Fill")
        aceTabGroup:SetTabs({
            { text = tabLabels.focus, value = "focus" },
            { text = tabLabels.tackle, value = "tackle" },
            { text = tabLabels.buffs, value = "buffs" },
            { text = tabLabels.modes, value = "modes" },
        })
        aceTabGroup:SetCallback("OnGroupSelected", function(_, _, group)
            ShowTab(group)
        end)
        panel.aceTabGroup = aceTabGroup
        panel.aceWindow:AddChild(aceTabGroup)

        local function CreatePage(name)
            local parentFrame = panel.aceTabGroup and panel.aceTabGroup.content or panel
            local page = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
            page:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 8, -8)
            page:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -8, 8)
            page:Hide()
            panel.pages[name] = page
            return page
        end

        focusPage = CreatePage("focus")
        tacklePage = CreatePage("tackle")
        buffsPage = CreatePage("buffs")
        modesPage = CreatePage("modes")
    end

    BuildTabScaffold()

    local function CreateBuffItemDropBox(parent, x, y, label, onLiveChange)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", x, y)
        lbl:SetText(label)

        local box = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
        box:SetSize(48, 48)
        box:SetPoint("TOPLEFT", x, y - 18)
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        box:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        box:SetBackdropBorderColor(0.9, 0.8, 0.2, 1)
        box.defaultBorderColor = { 0.9, 0.8, 0.2, 1 }
        box.dragHoverBorderColor = { 0.2, 1.0, 0.35, 1 }

        box.icon = box:CreateTexture(nil, "ARTWORK")
        box.icon:SetAllPoints(box)
        box.icon:SetTexture(nil)

        box.itemID = nil
        box.textValue = ""

        function box:SetItemID(itemID)
            local numeric = tonumber(itemID)
            if numeric and numeric > 0 then
                self.itemID = numeric
                self.textValue = tostring(numeric)
                if type(GetItemIcon) == "function" then
                    self.icon:SetTexture(GetItemIcon(numeric))
                else
                    self.icon:SetTexture(nil)
                end
                local bag, slot = nil, nil
                if addon.buff and addon.buff.FindItemInBags then
                    bag, slot = addon.buff.FindItemInBags(numeric)
                elseif addon.fishing and addon.fishing.FindItemInBags then
                    bag, slot = addon.fishing.FindItemInBags(numeric)
                end
                self:SetAttribute("type2", "item")
                if bag and slot then
                    self:SetAttribute("item2", tostring(bag) .. " " .. tostring(slot))
                else
                    self:SetAttribute("item2", "item:" .. tostring(numeric))
                end
            else
                self.itemID = nil
                self.textValue = ""
                self.icon:SetTexture(nil)
                self:SetAttribute("type2", nil)
                self:SetAttribute("item2", nil)
            end
        end

        function box:SetText(value)
            self:SetItemID(value)
        end

        function box:GetText()
            return self.textValue or ""
        end

        function box:SetExpectedDuration(seconds)
            local resolved = ResolveExpectedDurationForItem(self.itemID, seconds)
            self.expectedDuration = resolved
        end

        function box:GetExpectedDuration()
            return tonumber(self.expectedDuration) or ResolveExpectedDurationForItem(self.itemID, nil)
        end

        local function IsCursorHoldingItem()
            if type(GetCursorInfo) ~= "function" then
                return false
            end
            local cursorType = GetCursorInfo()
            return cursorType == "item"
        end

        local SetDragHighlight

        local function TryAssignFromCursor(self)
            if type(GetCursorInfo) ~= "function" then
                return false
            end
            local cursorType, itemID = GetCursorInfo()
            if cursorType ~= "item" or not itemID then
                return false
            end

            local targetItemID = self.itemID
            local targetExpectedDuration = self:GetExpectedDuration()

            self:SetItemID(itemID)
            self:SetExpectedDuration(ResolveExpectedDurationForItem(itemID, targetExpectedDuration))
            if type(ClearCursor) == "function" then
                ClearCursor()
            end

            if targetItemID and targetItemID > 0 and tonumber(targetItemID) ~= tonumber(itemID) then
                if type(PickupItem) == "function" then
                    PickupItem(targetItemID)
                end
                if type(GetCursorInfo) == "function" then
                    local swappedType, swappedItemID = GetCursorInfo()
                    if swappedType == "item" and tonumber(swappedItemID) == tonumber(targetItemID) then
                        uiBuffCursorDragState = {
                            source = self,
                            sourceItemID = targetItemID,
                            sourceExpectedDuration = targetExpectedDuration,
                        }
                        SetDragHighlight(self, true)
                    else
                        uiBuffCursorDragState = nil
                    end
                end
            else
                uiBuffCursorDragState = nil
            end

            return true
        end

        SetDragHighlight = function(self, active)
            if active then
                self:SetBackdropBorderColor(self.dragHoverBorderColor[1], self.dragHoverBorderColor[2], self.dragHoverBorderColor[3], self.dragHoverBorderColor[4])
            else
                self:SetBackdropBorderColor(self.defaultBorderColor[1], self.defaultBorderColor[2], self.defaultBorderColor[3], self.defaultBorderColor[4])
            end
        end

        local function TryDropCursorItemToSlot(self)
            if type(GetCursorInfo) ~= "function" then
                return false
            end

            local cursorType, cursorItemID = GetCursorInfo()
            if cursorType ~= "item" or not cursorItemID then
                return false
            end

            local sourceState = uiBuffCursorDragState
            local source = sourceState and sourceState.source or nil
            local sourceExpectedDuration = sourceState and sourceState.sourceExpectedDuration or nil

            local targetItemID = self.itemID
            local targetExpectedDuration = self:GetExpectedDuration()

            self:SetItemID(cursorItemID)
            self:SetExpectedDuration(sourceExpectedDuration or ResolveExpectedDurationForItem(cursorItemID, targetExpectedDuration))

            if source and source ~= self then
                source:SetItemID(targetItemID)
                source:SetExpectedDuration(targetExpectedDuration)
                SetDragHighlight(source, false)
            end

            if source and source == self and sourceExpectedDuration then
                self:SetExpectedDuration(sourceExpectedDuration)
            end

            local shouldClearCursor = true
            if (not source)
                and targetItemID
                and targetItemID > 0
                and tonumber(targetItemID) ~= tonumber(cursorItemID)
                and type(PickupItem) == "function" then
                if type(ClearCursor) == "function" then
                    ClearCursor()
                end
                PickupItem(targetItemID)
                shouldClearCursor = false
            end

            if shouldClearCursor and type(ClearCursor) == "function" then
                ClearCursor()
            end

            uiBuffCursorDragState = nil
            return true
        end

        box:RegisterForClicks("AnyDown", "AnyUp")
        box:RegisterForDrag("LeftButton")
        box:SetScript("OnDragStart", function(self)
            if self.itemID and self.itemID > 0 then
                local sourceItemID = self.itemID
                local sourceExpectedDuration = self:GetExpectedDuration()

                if type(PickupItem) == "function" then
                    PickupItem(sourceItemID)
                end

                if type(GetCursorInfo) == "function" then
                    local cursorType, cursorItemID = GetCursorInfo()
                    if cursorType == "item" and tonumber(cursorItemID) == tonumber(sourceItemID) then
                        self:SetItemID(nil)
                        self.pendingDragPersist = true
                        uiBuffCursorDragState = {
                            source = self,
                            sourceItemID = sourceItemID,
                            sourceExpectedDuration = sourceExpectedDuration,
                        }
                        SetDragHighlight(self, true)
                    else
                        uiBuffCursorDragState = nil
                    end
                else
                    uiBuffCursorDragState = nil
                end
            else
                uiBuffCursorDragState = nil
            end
        end)
        box:SetScript("OnDragStop", function(self)
            if uiBuffCursorDragState and uiBuffCursorDragState.source == self then
                uiBuffCursorDragState = nil
            end
            if self.pendingDragPersist and onLiveChange then
                onLiveChange()
            end
            self.pendingDragPersist = nil
            SetDragHighlight(self, false)
        end)
        box:SetScript("OnReceiveDrag", function(self)
            if TryDropCursorItemToSlot(self) then
                if onLiveChange then
                    onLiveChange()
                end
                return
            end
            TryAssignFromCursor(self)
            if onLiveChange then
                onLiveChange()
            end
        end)
        box:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                if not TryDropCursorItemToSlot(self) then
                    TryAssignFromCursor(self)
                end
                if onLiveChange then
                    onLiveChange()
                end
            elseif button == "RightButton" then
                if IsShiftKeyDown() then
                    self:SetItemID(nil)
                    if onLiveChange then
                        onLiveChange()
                    end
                end
            end
        end)

        box:SetScript("OnEnter", function(self)
            if self.itemID and self.itemID > 0 and type(GameTooltip) == "table" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if type(GameTooltip.SetItemByID) == "function" then
                    GameTooltip:SetItemByID(self.itemID)
                else
                    GameTooltip:SetText((type(GetItemInfo) == "function" and GetItemInfo(self.itemID)) or ("item:" .. tostring(self.itemID)))
                end
                GameTooltip:Show()
            end
            if IsCursorHoldingItem() then
                SetDragHighlight(self, true)
            end
        end)

        box:SetScript("OnLeave", function(self)
            if type(GameTooltip) == "table" then
                GameTooltip:Hide()
            end
            if not (uiBuffCursorDragState and uiBuffCursorDragState.source == self) then
                SetDragHighlight(self, false)
            end
        end)

        box.countText = box:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        box.countText:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        box.countText:SetTextColor(0.9, 0.9, 0.9, 1)
        box.countText:SetText("")

        local function UpdateCountDisplay()
            if box.itemID and box.itemID > 0 then
                local count = 0
                if addon.utils and addon.utils.CountItemInBags then
                    count = addon.utils.CountItemInBags(box.itemID)
                end
                box.countText:SetText(tostring(math.max(0, count)))
                if buffItemLastKnownCount[box.itemID] == nil then
                    buffItemLastKnownCount[box.itemID] = math.max(0, count)
                end
            else
                box.countText:SetText("")
            end
        end
        box.UpdateCountDisplay = UpdateCountDisplay

        local originalSetItemID = box.SetItemID
        function box:SetItemID(itemID)
            originalSetItemID(self, itemID)
            UpdateCountDisplay()
        end

        box:HookScript("OnClick", function(self, button)
            if button ~= "RightButton" or not self.itemID or self.itemID <= 0 then
                return
            end
            local now = GetTime()
            buffItemLastUseAt[self.itemID] = now
            if addon.buff and addon.buff.BuildHelpfulAuraSnapshot then
                addon.state.pendingBuffObservation = {
                    itemID = self.itemID,
                    before = addon.buff.BuildHelpfulAuraSnapshot(),
                    expiresAt = now + 20,
                }
            end
            if addon.buff and addon.buff.AnnounceBuffUse then
                addon.buff.AnnounceBuffUse(self.itemID)
            end
            self:UpdateCountDisplay()
        end)

        return box
    end

    SaveLive = function()
        if suppressLiveSave then
            return
        end
        config.SaveConfig(true)
    end

    local function CreateSecureToyActionButton(parent, x, y, width, text)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate,SecureActionButtonTemplate")
        button:SetSize(width, 22)
        button:SetPoint("TOPLEFT", x, y)
        button:SetText(text)
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("type", "toy")
        button:SetAttribute("toy", nil)
        return button
    end

    local CreateAceCheckbox = nil
    local CreateAceEditBox = nil
    local CreateAceTitle = nil
    local CreateAceNote = nil
    local CreateAceToySelector = nil

    do
        local aceWidgets = {}
        panel.aceWidgets = aceWidgets

        local function RegisterAceWidget(widget)
            table.insert(aceWidgets, widget)
            return widget
        end

        local function AnchorAceWidget(widget, parent, x, y)
            widget.frame:SetParent(parent)
            widget.frame:SetPoint("TOPLEFT", x, y)
            widget.frame:Show()
            return RegisterAceWidget(widget)
        end

        CreateAceCheckbox = function(parent, x, y, label, onLiveChange)
            local widget = aceGUIInstance:Create("CheckBox")
            widget:SetType("checkbox")
            widget:SetLabel(label)
            if onLiveChange then
                widget:SetCallback("OnValueChanged", function()
                    onLiveChange()
                end)
            end
            widget = AnchorAceWidget(widget, parent, x, y)

            return {
                SetChecked = function(_, value)
                    widget:SetValue(value and true or false)
                end,
                GetChecked = function()
                    return widget:GetValue() and true or false
                end,
            }
        end

        CreateAceEditBox = function(parent, x, y, width, label, onLiveChange)
            local widget = aceGUIInstance:Create("EditBox")
            widget:SetLabel(label)
            widget:SetWidth(width)
            if onLiveChange then
                widget:SetCallback("OnTextChanged", function()
                    onLiveChange()
                end)
                widget:SetCallback("OnEnterPressed", function()
                    onLiveChange()
                end)
            end
            widget = AnchorAceWidget(widget, parent, x, y)

            return {
                SetText = function(_, value)
                    widget:SetText(tostring(value or ""))
                end,
                GetText = function()
                    return widget:GetText() or ""
                end,
            }
        end

        CreateAceTitle = function(parent, x, y, text)
            local widget = aceGUIInstance:Create("Label")
            widget:SetText(text)
            return AnchorAceWidget(widget, parent, x, y)
        end

        CreateAceNote = function(parent, x, y, width, text)
            local widget = aceGUIInstance:Create("Label")
            widget:SetText(text)
            widget:SetWidth(width)
            return AnchorAceWidget(widget, parent, x, y)
        end

        CreateAceToySelector = function(parent, x, y, width, label, optionsGetter, onLiveChange)
            CreateAceTitle(parent, x, y, label)

            local dropdown = aceGUIInstance:Create("Dropdown")
            dropdown:SetWidth(width)
            dropdown = AnchorAceWidget(dropdown, parent, x, y - 24)

            local selector = {
                options = {},
                selectedValue = nil,
                onValueChanged = onLiveChange,
                dropdown = nil,
            }

            function selector:RefreshOptions()
                self.options = optionsGetter and optionsGetter() or {}

                local list = {}
                for _, option in ipairs(self.options) do
                    list[option.value] = option.label or tostring(option.value)
                end
                dropdown:SetList(list)

                if #self.options == 0 then
                    self.selectedValue = nil
                    dropdown:SetValue(nil)
                    return
                end

                local desired = tonumber(self.selectedValue)
                local found = false
                for _, option in ipairs(self.options) do
                    if option.value == desired then
                        found = true
                        break
                    end
                end

                if not found then
                    self.selectedValue = self.options[1].value
                else
                    self.selectedValue = desired
                end

                dropdown:SetValue(self.selectedValue)
            end

            function selector:SetText(value)
                local numeric = tonumber(value)
                self.selectedValue = numeric and numeric > 0 and numeric or 0
                self:RefreshOptions()
            end

            function selector:GetText()
                return tostring(self.selectedValue or "")
            end

            dropdown:SetCallback("OnValueChanged", function(_, _, value)
                selector.selectedValue = tonumber(value) or 0
                if selector.onValueChanged then
                    selector.onValueChanged(selector.selectedValue)
                end
            end)

            selector:RefreshOptions()
            return selector
        end
    end

    local ui = {
        Checkbox = CreateAceCheckbox,
        EditBox = CreateAceEditBox,
        Title = CreateAceTitle,
        StaticTitle = CreateAceTitle,
        ToySelector = CreateAceToySelector,
        CreateBuffsHost = function(parent)
            local host = CreateFrame("Frame", nil, parent)
            host:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -12)
            host:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 12)
            return host
        end,
        Note = CreateAceNote,
    }

    local function BuildFocusTab()
        local layout = {
            treasureY = -50,
            bagY = -80,
            thresholdY = -120,
            thresholdWidth = 140,
            audioTitleY = -200,
            audioCheckboxY = -230,
            audioLingerY = -270,
            audioLingerWidth = 180,
        }

        addon.autoLootCheckbox = ui.Checkbox(focusPage, 20, -20, "Temporary Auto-Loot", SaveLive)
        addon.treasureAlertsCheckbox = ui.Checkbox(focusPage, 20, layout.treasureY, "Patient Treasure Notification", SaveLive)
        addon.bagAlertsCheckbox = ui.Checkbox(focusPage, 20, layout.bagY, "Bag Monitor / Alert", SaveLive)
        addon.lowBagBox = ui.EditBox(focusPage, 60, layout.thresholdY, layout.thresholdWidth, "Low Bag Threshold:", SaveLive)

        ui.Title(focusPage, 20, layout.audioTitleY, "Audio:")
        addon.enhancedSoundsCheckbox = ui.Checkbox(focusPage, 20, layout.audioCheckboxY, "Fishing Focused Audio", SaveLive)
        addon.audioLingerBox = ui.EditBox(focusPage, 60, layout.audioLingerY, layout.audioLingerWidth, "Audio Linger After Catch (s):", SaveLive)
    end

    local function BuildTackleTab()
        local layout = {
            selectorWidth = 280,
            oversizedY = -82,
            bobberApplyY = -116,
            raftApplyY = -236,
        }

        addon.bobberSelector = ui.ToySelector(tacklePage, 20, -20, layout.selectorWidth, "Selected Bobber:", function()
            return BuildOwnedToyOptions(addon.const.bobberToyItemIDs, "Standard Bobber")
        end, SaveLive)
        addon.oversizedBobberCheckbox = ui.Checkbox(tacklePage, 20, layout.oversizedY, "Use oversized bobber", SaveLive)
        addon.bobberApplyButton = CreateSecureToyActionButton(tacklePage, 20, layout.bobberApplyY, 160, "Apply Bobber")

        addon.raftSelector = ui.ToySelector(tacklePage, 20, -170, layout.selectorWidth, "Selected Raft:", function()
            return BuildOwnedToyOptions(addon.const.raftToyItemIDs, "No Raft")
        end, SaveLive)
        addon.raftApplyButton = CreateSecureToyActionButton(tacklePage, 20, layout.raftApplyY, 160, "Apply Raft")
    end

    local function BuildModesTab()
        ui.Title(modesPage, 20, -20, "Casting Triggers:")
        addon.modeDoubleRightClickCheckbox = ui.Checkbox(modesPage, 20, -45, "Right double click", SaveLive)
        addon.modeSingleRightClickConfigCheckbox = ui.Checkbox(modesPage, 20, -75, "Single right click (when this window is open)", SaveLive)
        addon.modeHotkeyCheckbox = ui.Checkbox(modesPage, 20, -105, "Keybinding (set the key in Keybindings > DreamFisher)", SaveLive)
        addon.enableHookedLootCheckbox = ui.Checkbox(modesPage, 20, -135, "Use right click and/or hotkey to reel in the fish", SaveLive)

        ui.Note(modesPage, 40, -170, 480,
            "Requires some setup in Game Menu > Options: \n"
            .. "1. Turn on \"Enable Interact Key\" (Options > Controls).\n"
            .. "2. Set a keybinding (Keybindings > DreamFisher).\n"
            .. "3. Ensure another addon does not try to control interactions while fishing.")

        addon.escapeCloseCheckbox = ui.Checkbox(modesPage, 20, -235, "Escape closes this window", SaveLive)

        ui.Title(modesPage, 20, -295, "Underlight Angler:")
        addon.underlightAnglerCheckbox = ui.Checkbox(modesPage, 20, -315, "Equip Underlight Angler while swimming", SaveLive)
    end

    local function BuildBuffsTab()
        local buffsHost = ui.CreateBuffsHost(buffsPage)
        ui.StaticTitle(buffsHost, 20, -20, "Buff Items")

        addon.buffItemControls = {}
        for i = 1, maxBuffSlots do
            local row = math.floor((i - 1) / 2)
            local col = (i - 1) % 2
            local baseX = 20 + (col * 220)
            local baseY = -56 - (row * 95)
            local itemBox = CreateBuffItemDropBox(buffsHost, baseX, baseY, "Buff " .. i, SaveLive)
            itemBox:SetExpectedDuration(addon.db and addon.db.refreshSeconds or defaults.refreshSeconds)
            itemBox.slotIndex = i
            addon.buffItemControls[i] = {
                itemBox = itemBox,
            }
        end
    end

    BuildFocusTab()
    BuildTackleTab()
    BuildModesTab()
    BuildBuffsTab()

    panel.buffItemControls = addon.buffItemControls
    UpdateToyApplyButtons()

    local function SelectAceTab(tabName)
        if panel.aceTabGroup and panel.aceTabGroup.SelectTab then
            panel.aceTabGroup:SelectTab(tabName)
        end
    end

    local function ShowCurrentActiveTab()
        local selectedTab = panel.activeTab or "focus"
        SelectAceTab(selectedTab)
        ShowTab(selectedTab)
    end

    local function HandlePanelShow()
        UpdateConfigUI()
        SyncEscapeCloseRegistration()
        ShowCurrentActiveTab()
    end

    local function HandlePanelHide()
        if not suppressLiveSave then
            config.SaveConfig(true)
        end
    end

    local function BindPanelLifecycle()
        panel:HookScript("OnShow", HandlePanelShow)
        panel:HookScript("OnHide", HandlePanelHide)
    end

    BindPanelLifecycle()
    ShowTab("focus")
    SelectAceTab("focus")
    return panel
end

-- Update config module exports
config.UpdateConfigUI = UpdateConfigUI
