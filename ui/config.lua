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

local function BuildOwnedToyOptions(candidateIDs)
    local options = {}
    local seen = {}

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

local function SetDropdownText(selector, text)
    if selector and selector.dropdown then
        UIDropDownMenu_SetText(selector.dropdown, text or "None owned")
    end
    selector.displayText = text or "None owned"
end

local function SetSelectorValue(selector, itemID)
    if not selector then
        return
    end

    local numeric = tonumber(itemID)
    selector.selectedValue = numeric and numeric > 0 and numeric or nil

    if not selector.options or #selector.options == 0 then
        SetDropdownText(selector, "None owned")
        return
    end

    for index, option in ipairs(selector.options) do
        if option.value == selector.selectedValue then
            selector.selectedIndex = index
            break
        end
    end

    if not selector.selectedIndex then
        selector.selectedIndex = 1
        selector.selectedValue = selector.options[1].value
    end

    SetDropdownText(selector, selector.options[selector.selectedIndex].label or tostring(selector.selectedValue))
end

local function CreateDropdownMenu(selector)
    return function(frame, level, menuList)
        local options = selector.options or {}
        for _, option in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.label or tostring(option.value)
            info.value = option.value
            info.checked = (option.value == selector.selectedValue)
            info.func = function()
                selector.selectedValue = option.value
                selector.selectedIndex = nil
                SetDropdownText(selector, option.label or tostring(option.value))
                if selector.onValueChanged then
                    selector.onValueChanged(selector.selectedValue)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
end

local function CreateToySelector(parent, x, y, width, label, optionsGetter, onLiveChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 52)
    row:SetPoint("TOPLEFT", x, y)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.label:SetPoint("TOPLEFT", 0, 0)
    row.label:SetText(label)

    row.dropdown = CreateFrame("Frame", nil, row, "UIDropDownMenuTemplate")
    row.dropdown:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(row.dropdown, math.max(180, width - 8))
    UIDropDownMenu_JustifyText(row.dropdown, "LEFT")

    row.options = {}
    row.selectedValue = nil
    row.selectedIndex = nil
    row.onValueChanged = onLiveChange

    function row:RefreshOptions()
        self.options = optionsGetter and optionsGetter() or {}
        if #self.options == 0 then
            self.selectedValue = nil
            self.selectedIndex = nil
            SetDropdownText(self, "None owned")
            return
        end
        SetSelectorValue(self, self.selectedValue or self.options[1].value)
        UIDropDownMenu_Initialize(self.dropdown, CreateDropdownMenu(self))
    end

    function row:SetText(value)
        SetSelectorValue(self, value)
        UIDropDownMenu_Initialize(self.dropdown, CreateDropdownMenu(self))
    end

    function row:GetText()
        return tostring(self.selectedValue or "")
    end

    UIDropDownMenu_Initialize(row.dropdown, CreateDropdownMenu(row))
    row:RefreshOptions()
    return row
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
    if addon.refreshBox then
        addon.refreshBox:SetText(tostring(addon.db.refreshSeconds or defaults.refreshSeconds))
    end
    if addon.lowBagBox then
        addon.lowBagBox:SetText(tostring(addon.db.lowBagThreshold or defaults.lowBagThreshold))
    end
    if addon.buffItemControls then
        for i, control in ipairs(addon.buffItemControls) do
            local entry = addon.db.buffItems and addon.db.buffItems[i] or nil
            local itemID = entry and entry.itemID or nil
            local refreshSeconds = entry and entry.refreshSeconds or addon.db.refreshSeconds or defaults.refreshSeconds
            control.itemBox:SetText(tostring(itemID or ""))
            control.refreshBox:SetText(tostring(refreshSeconds))
        end
    end
    if addon.audioLingerBox then
        addon.audioLingerBox:SetText(tostring(addon.db.audioFocusLinger or defaults.audioFocusLinger))
    end
    if addon.modeDoubleRightClickCheckbox then
        local modes = GetCastingModesForConfig()
        addon.modeDoubleRightClickCheckbox:SetChecked(modes.doubleRightClick)
        addon.modeSingleRightClickConfigCheckbox:SetChecked(modes.singleRightClickConfig)
        addon.modeSingleRightClickDoubleStartCheckbox:SetChecked(modes.singleRightClickDoubleStart)
        addon.modeHotkeyCheckbox:SetChecked(modes.hotkey)
    end
    if addon.underlightAnglerCheckbox then
        addon.underlightAnglerCheckbox:SetChecked(addon.db.useUnderlightAngler)
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

    addon.db.refreshSeconds = addon.Clamp(tonumber(addon.refreshBox:GetText()) or defaults.refreshSeconds, 30, 600)
    addon.db.lowBagThreshold = addon.Clamp(tonumber(addon.lowBagBox:GetText()) or defaults.lowBagThreshold, 0, 20)
    addon.db.audioFocusLinger = addon.Clamp(tonumber(addon.audioLingerBox:GetText()) or defaults.audioFocusLinger, 0, 60)
    addon.db.autoLoot = addon.autoLootCheckbox:GetChecked()
    addon.db.enhancedSounds = addon.enhancedSoundsCheckbox:GetChecked()
    addon.db.treasureAlerts = addon.treasureAlertsCheckbox:GetChecked()
    addon.db.bagAlerts = addon.bagAlertsCheckbox:GetChecked()
    local modeFlags = {
        doubleRightClick = addon.modeDoubleRightClickCheckbox and addon.modeDoubleRightClickCheckbox:GetChecked() or false,
        singleRightClickConfig = addon.modeSingleRightClickConfigCheckbox and addon.modeSingleRightClickConfigCheckbox:GetChecked() or false,
        singleRightClickDoubleStart = addon.modeSingleRightClickDoubleStartCheckbox and addon.modeSingleRightClickDoubleStartCheckbox:GetChecked() or false,
        hotkey = addon.modeHotkeyCheckbox and addon.modeHotkeyCheckbox:GetChecked() or false,
    }
    addon.db.castingModes = modeFlags
    addon.db.useUnderlightAngler = addon.underlightAnglerCheckbox and addon.underlightAnglerCheckbox:GetChecked()
    addon.db.useOversizedBobber = addon.oversizedBobberCheckbox and addon.oversizedBobberCheckbox:GetChecked()
    if addon.escapeCloseCheckbox then
        addon.db.configCloseOnEscape = addon.escapeCloseCheckbox:GetChecked()
    end
    SyncEscapeCloseRegistration()

    if addon.buffItemControls then
        addon.db.buffItems = {}
        for i, control in ipairs(addon.buffItemControls) do
            local itemID = tonumber(control.itemBox:GetText())
            local refreshSeconds = addon.Clamp(tonumber(control.refreshBox:GetText()) or addon.db.refreshSeconds or defaults.refreshSeconds, 30, 3600)
            addon.db.buffItems[i] = {
                itemID = (itemID and itemID > 0) and itemID or nil,
                refreshSeconds = refreshSeconds,
            }
        end
    end

    local currentlyActiveBuffItems = CollectActiveBuffItemIDs(addon.db.buffItems)
    for removedItemID, _ in pairs(previouslyActiveBuffItems) do
        if not currentlyActiveBuffItems[removedItemID] then
            if addon.state then
                addon.state.buffItemLastUseAt[removedItemID] = nil
                addon.state.buffItemLastReminderAt[removedItemID] = nil
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

    local panel = CreateFrame("Frame", addonName .. "ConfigFrame", UIParent, "BackdropTemplate")
    panel:SetSize(520, 690)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:EnableKeyboard(false)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if addon.db then
            local point, _, relativePoint, x, y = self:GetPoint(1)
            addon.db.configWindowPosition = {
                point = point or "CENTER",
                relativePoint = relativePoint or "CENTER",
                x = math.floor((x or 0) + 0.5),
                y = math.floor((y or 0) + 0.5),
            }
        end
    end)

    if addon.db and type(addon.db.configWindowPosition) == "table" then
        local pos = addon.db.configWindowPosition
        panel:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", tonumber(pos.x) or 0, tonumber(pos.y) or 0)
    else
        panel:SetPoint("CENTER")
    end
    panel:Hide()

    panel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)

    addon.frames.config = panel
    SyncEscapeCloseRegistration()

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 20, -20)
    panel.title:SetText(addonName .. " Settings")

    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -8, -8)

    local tabNames = { "focus", "tackle", "buffs", "modes" }
    local tabLabels = {
        focus = "Focus",
        tackle = "Tackle",
        buffs = "Buffs",
        modes = "Modes",
    }

    panel.tabButtons = {}
    panel.pages = {}
    panel.activeTab = "focus"

    local function ShowTab(tabName)
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

    local function CreateTabButton(tabName, x)
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(92, 22)
        button:SetPoint("TOPLEFT", x, -46)
        button:SetText(tabLabels[tabName] or tabName)
        button:SetScript("OnClick", function()
            ShowTab(tabName)
        end)
        panel.tabButtons[tabName] = button
        return button
    end

    CreateTabButton("focus", 18)
    CreateTabButton("tackle", 114)
    CreateTabButton("buffs", 210)
    CreateTabButton("modes", 306)

    local function CreatePage(name)
        local page = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        page:SetPoint("TOPLEFT", 18, -76)
        page:SetPoint("BOTTOMRIGHT", -18, 18)
        page:Hide()
        panel.pages[name] = page
        return page
    end

    local focusPage = CreatePage("focus")
    local tacklePage = CreatePage("tackle")
    local buffsPage = CreatePage("buffs")
    local modesPage = CreatePage("modes")

    local function CreateCheckbox(parent, x, y, label, onLiveChange)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        cb.Text:SetText(label)
        cb.Text:SetTextColor(1, 1, 1, 1)
        if onLiveChange then
            cb:SetScript("OnClick", onLiveChange)
        end
        return cb
    end

    local function CreateEditBox(parent, x, y, width, label, onLiveChange)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", x, y)
        lbl:SetText(label)

        local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        eb:SetSize(width, 20)
        eb:SetPoint("TOPLEFT", x, y - 15)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            if addon.db and addon.db.configCloseOnEscape then
                panel:Hide()
            end
        end)
        if onLiveChange then
            eb:SetScript("OnTextChanged", function(_, userInput)
                if userInput then
                    onLiveChange()
                end
            end)
        end
        return eb
    end

    local function CreateBuffRefreshBox(parent, x, y, onLiveChange)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", x, y)
        lbl:SetText("Refresh (s)")

        local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        eb:SetSize(70, 20)
        eb:SetPoint("TOPLEFT", x, y - 12)
        eb:SetAutoFocus(false)
        if onLiveChange then
            eb:SetScript("OnTextChanged", function(_, userInput)
                if userInput then
                    onLiveChange()
                end
            end)
        end
        return eb
    end

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
                if addon.fishing and addon.fishing.FindItemInBags then
                    local bag, slot = addon.fishing.FindItemInBags(numeric)
                    self:SetAttribute("type2", "item")
                    if bag and slot then
                        self:SetAttribute("item2", tostring(bag) .. " " .. tostring(slot))
                    else
                        self:SetAttribute("item2", "item:" .. tostring(numeric))
                    end
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

        local function TryAssignFromCursor(self)
            if type(GetCursorInfo) ~= "function" then
                return
            end
            local cursorType, itemID = GetCursorInfo()
            if cursorType == "item" and itemID then
                self:SetItemID(itemID)
                if type(ClearCursor) == "function" then
                    ClearCursor()
                end
            end
        end

        local function SetDragHighlight(self, active)
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
            local sourceRefresh = sourceState and sourceState.sourceRefresh or nil

            local targetItemID = self.itemID
            local targetRefresh = self.refreshBox and self.refreshBox:GetText() or tostring(addon.db and addon.db.refreshSeconds or defaults.refreshSeconds)

            self:SetItemID(cursorItemID)
            if sourceRefresh and self.refreshBox then
                self.refreshBox:SetText(sourceRefresh)
            end

            if source and source ~= self then
                source:SetItemID(targetItemID)
                if source.refreshBox then
                    source.refreshBox:SetText(targetRefresh)
                end
                SetDragHighlight(source, false)
            end

            if source and source == self and sourceRefresh and self.refreshBox then
                self.refreshBox:SetText(sourceRefresh)
            end

            if type(ClearCursor) == "function" then
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
                local sourceRefresh = self.refreshBox and self.refreshBox:GetText() or tostring(addon.db and addon.db.refreshSeconds or defaults.refreshSeconds)

                if type(PickupItem) == "function" then
                    PickupItem(sourceItemID)
                end

                if type(GetCursorInfo) == "function" then
                    local cursorType, cursorItemID = GetCursorInfo()
                    if cursorType == "item" and tonumber(cursorItemID) == tonumber(sourceItemID) then
                        self:SetItemID(nil)
                        uiBuffCursorDragState = {
                            source = self,
                            sourceItemID = sourceItemID,
                            sourceRefresh = sourceRefresh,
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

        box.countText = box:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        box.countText:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        box.countText:SetTextColor(1, 1, 1, 1)
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

    local function CreateActionButton(parent, x, y, width, text, onClick)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetPoint("TOPLEFT", x, y)
        button:SetText(text)
        button:SetScript("OnClick", onClick)
        return button
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

    addon.autoLootCheckbox = CreateCheckbox(focusPage, 20, -20, "Temporary Auto-Loot", SaveLive)
    addon.enhancedSoundsCheckbox = CreateCheckbox(focusPage, 20, -55, "Fishing Focused Audio", SaveLive)
    addon.treasureAlertsCheckbox = CreateCheckbox(focusPage, 20, -90, "Patient Treasure Notification", SaveLive)
    addon.bagAlertsCheckbox = CreateCheckbox(focusPage, 20, -125, "Bag Monitor / Alert", SaveLive)
    addon.escapeCloseCheckbox = CreateCheckbox(focusPage, 20, -160, "Escape closes this window", SaveLive)
    addon.lowBagBox = CreateEditBox(focusPage, 20, -210, 100, "Low Bag Threshold:", SaveLive)
    addon.audioLingerBox = CreateEditBox(focusPage, 20, -260, 100, "Audio Linger After Catch (s):", SaveLive)

    addon.bobberSelector = CreateToySelector(tacklePage, 20, -20, 360, "Selected Bobber:", function()
        return BuildOwnedToyOptions(addon.const.bobberToyItemIDs)
    end, SaveLive)
    addon.oversizedBobberCheckbox = CreateCheckbox(tacklePage, 20, -85, "Use oversized bobber", SaveLive)
    addon.bobberApplyButton = CreateSecureToyActionButton(tacklePage, 20, -125, 160, "Apply Bobber")

    addon.raftSelector = CreateToySelector(tacklePage, 20, -190, 360, "Selected Raft:", function()
        return BuildOwnedToyOptions(addon.const.raftToyItemIDs)
    end, SaveLive)
    addon.raftApplyButton = CreateSecureToyActionButton(tacklePage, 20, -255, 160, "Apply Raft")

    local modeLabel = modesPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeLabel:SetPoint("TOPLEFT", 20, -20)
    modeLabel:SetText("Casting Triggers:")

    addon.modeDoubleRightClickCheckbox = CreateCheckbox(modesPage, 20, -45, "Right double click", SaveLive)
    addon.modeSingleRightClickConfigCheckbox = CreateCheckbox(modesPage, 20, -75, "Single right click (when DF window is open)", SaveLive)
    addon.modeSingleRightClickDoubleStartCheckbox = CreateCheckbox(modesPage, 20, -105, "Single right click (double right click to start. ESC to stop)", SaveLive)
    addon.modeHotkeyCheckbox = CreateCheckbox(modesPage, 20, -135, "Keyboard hotkey", SaveLive)

    local hotkeyNote = modesPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hotkeyNote:SetPoint("TOPLEFT", 20, -170)
    hotkeyNote:SetText("Set key in Game Menu > Options > Keybindings > DreamFisher")

    addon.underlightAnglerCheckbox = CreateCheckbox(modesPage, 20, -205, "Equip Underlight Angler while swimming", SaveLive)

    addon.buffItemControls = {}
    for i = 1, maxBuffSlots do
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local baseX = 20 + (col * 220)
        local baseY = -20 - (row * 95)
        local itemBox = CreateBuffItemDropBox(buffsPage, baseX, baseY, "Buff " .. i, SaveLive)
        local refreshBox = CreateBuffRefreshBox(buffsPage, baseX + 65, baseY - 4, SaveLive)
        itemBox.refreshBox = refreshBox
        itemBox.slotIndex = i
        addon.buffItemControls[i] = {
            itemBox = itemBox,
            refreshBox = refreshBox,
        }
    end
    addon.refreshBox = CreateEditBox(buffsPage, 20, -340, 100, "Default Refresh (s):", SaveLive)

    panel.buffItemControls = addon.buffItemControls
    UpdateToyApplyButtons()

    panel:SetScript("OnShow", function()
        UpdateConfigUI()
        SyncEscapeCloseRegistration()
        ShowTab(panel.activeTab or "focus")
    end)
    panel:SetScript("OnHide", function()
        if not suppressLiveSave then
            config.SaveConfig(true)
        end
    end)

    ShowTab("focus")
    return panel
end

-- Update config module exports
config.UpdateConfigUI = UpdateConfigUI
