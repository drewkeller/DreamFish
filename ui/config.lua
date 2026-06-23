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

    suppressLiveSave = false
end

-- Save config from UI back to database
function config.SaveConfig(skipRefresh)
    if not addon.db then
        return
    end

    addon.db.refreshSeconds = addon.Clamp(tonumber(addon.refreshBox:GetText()) or defaults.refreshSeconds, 30, 600)
    addon.db.lowBagThreshold = addon.Clamp(tonumber(addon.lowBagBox:GetText()) or defaults.lowBagThreshold, 0, 20)
    addon.db.audioFocusLinger = addon.Clamp(tonumber(addon.audioLingerBox:GetText()) or defaults.audioFocusLinger, 0, 60)
    addon.db.autoLoot = addon.autoLootCheckbox:GetChecked()
    addon.db.enhancedSounds = addon.enhancedSoundsCheckbox:GetChecked()
    addon.db.treasureAlerts = addon.treasureAlertsCheckbox:GetChecked()
    addon.db.bagAlerts = addon.bagAlertsCheckbox:GetChecked()
    if addon.escapeCloseCheckbox then
        addon.db.configCloseOnEscape = addon.escapeCloseCheckbox:GetChecked()
    end

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

    -- 1. Main Container Frame
    local panel = CreateFrame("Frame", addonName .. "ConfigFrame", UIParent, "BackdropTemplate")
    panel:SetSize(480, 700)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:EnableKeyboard(true)
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

    -- Aesthetic Frame Styling
    panel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)

    addon.frames.config = panel

    -- 2. Title Text
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 20, -20)
    panel.title:SetText(addonName .. " Settings")

    -- 3. Close Button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -8, -8)

    -- 4. Checkbox Helper
    local function CreateCheckbox(x, y, label, onLiveChange)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        cb.Text:SetText(label)
        cb.Text:SetTextColor(1, 1, 1, 1)
        if onLiveChange then
            cb:SetScript("OnClick", onLiveChange)
        end
        return cb
    end

    -- 4. Input Box Helper
    local function CreateEditBox(x, y, width, label, onLiveChange)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", x, y)
        lbl:SetText(label)

        local eb = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
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

    local function CreateBuffItemDropBox(x, y, label, onLiveChange)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", x, y)
        lbl:SetText(label)

        local box = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate,BackdropTemplate")
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

        -- Preserve EditBox-like API for save/load logic compatibility
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

        local function SetDragHighlight(self, active)
            if active then
                self:SetBackdropBorderColor(self.dragHoverBorderColor[1], self.dragHoverBorderColor[2], self.dragHoverBorderColor[3], self.dragHoverBorderColor[4])
            else
                self:SetBackdropBorderColor(self.defaultBorderColor[1], self.defaultBorderColor[2], self.defaultBorderColor[3], self.defaultBorderColor[4])
            end
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
        box:SetScript("OnEnter", function(self)
            if uiBuffCursorDragState and uiBuffCursorDragState.source ~= self then
                SetDragHighlight(self, true)
            end
            if not self.itemID or type(GameTooltip) ~= "table" then
                return
            end
            if type(GameTooltip.SetOwner) == "function" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            end
            if type(GameTooltip.SetItemByID) == "function" then
                GameTooltip:SetItemByID(self.itemID)
            elseif type(GameTooltip.SetHyperlink) == "function" then
                GameTooltip:SetHyperlink("item:" .. tostring(self.itemID))
            end
            if type(GameTooltip.Show) == "function" then
                GameTooltip:Show()
            end
        end)
        box:SetScript("OnLeave", function(self)
            SetDragHighlight(self, false)
            if type(GameTooltip) == "table" and type(GameTooltip.Hide) == "function" then
                GameTooltip:Hide()
            end
        end)

        -- Add count text overlay
        box.countText = box:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        box.countText:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        box.countText:SetTextColor(1, 1, 1, 1)
        box.countText:SetText("")

        -- Update count display
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

        -- Update count when item changes
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

    local function CreateBuffRefreshBox(x, y, onLiveChange)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", x, y)
        lbl:SetText("Refresh (s)")

        local eb = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
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

    local function SaveLive()
        if suppressLiveSave then
            return
        end
        config.SaveConfig(true)
    end

    -- Instantiate UI elements
    addon.autoLootCheckbox = CreateCheckbox(20, -50, "Temporary Auto-Loot", SaveLive)
    addon.enhancedSoundsCheckbox = CreateCheckbox(20, -85, "Fishing Focused Audio", SaveLive)
    addon.treasureAlertsCheckbox = CreateCheckbox(20, -120, "Patient Treasure Notification", SaveLive)
    addon.bagAlertsCheckbox = CreateCheckbox(20, -155, "Bag Monitor / Alert", SaveLive)
    addon.escapeCloseCheckbox = CreateCheckbox(20, -190, "Escape closes this window", SaveLive)

    addon.buffItemControls = {}
    for i = 1, maxBuffSlots do
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local baseX = 20 + (col * 220)
        local baseY = -240 - (row * 95)
        local itemBox = CreateBuffItemDropBox(baseX, baseY, "Buff " .. i, SaveLive)
        local refreshBox = CreateBuffRefreshBox(baseX + 65, baseY - 4, SaveLive)
        itemBox.refreshBox = refreshBox
        itemBox.slotIndex = i
        addon.buffItemControls[i] = {
            itemBox = itemBox,
            refreshBox = refreshBox,
        }
    end

    addon.refreshBox = CreateEditBox(20, -540, 100, "Default Refresh (s):", SaveLive)
    addon.lowBagBox = CreateEditBox(20, -590, 100, "Low Bag Threshold:", SaveLive)
    addon.audioLingerBox = CreateEditBox(20, -640, 100, "Audio Linger After Catch (s):", SaveLive)

    panel:SetScript("OnShow", function()
        UpdateConfigUI()
    end)
    panel:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and addon.db and addon.db.configCloseOnEscape then
            self:Hide()
        end
    end)

    return panel
end

-- Update config module exports
config.UpdateConfigUI = UpdateConfigUI
