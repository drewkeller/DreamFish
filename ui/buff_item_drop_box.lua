-- DreamFisher Buff Item Drop Box UI

local addon = _G["DreamFisher"]
addon.ui = addon.ui or {}

function addon.ui.CreateBuffItemDropBox(deps, parent, x, y, label, onLiveChange)
    local buffItemLastKnownCount = deps.buffItemLastKnownCount
    local buffItemLastUseAt = deps.buffItemLastUseAt
    local getDragState = deps.getDragState
    local setDragState = deps.setDragState
    local getCachedItemCount = deps.getCachedItemCount

    local hasLabel = type(label) == "string" and label ~= ""
    if type(label) == "string" and label ~= "" then
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", x, y)
        lbl:SetText(label)
    end

    local box = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
    box:SetSize(48, 48)
    box:SetPoint("TOPLEFT", x, y + (hasLabel and -18 or 0))
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    box:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    box:SetBackdropBorderColor(0.42, 0.42, 0.42, 0.9)
    box.defaultBorderColor = { 0.42, 0.42, 0.42, 0.9 }
    box.emptyBorderColor = { 0.36, 0.36, 0.36, 0.8 }
    box.dragHoverBorderColor = { 0.2, 1.0, 0.35, 1 }
    box.mismatchBorderColor = { 1.0, 0.25, 0.25, 1 }
    box.dimIconAlpha = 0.35
    box.fullIconAlpha = 1.0

    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetAllPoints(box)
    box.icon:SetTexture(nil)

    box.mismatchOverlay = box:CreateTexture(nil, "OVERLAY")
    box.mismatchOverlay:SetAllPoints(box)
    box.mismatchOverlay:SetColorTexture(1, 0.15, 0.15, 0.22)
    box.mismatchOverlay:Hide()

    box.itemID = nil
    box.textValue = ""
    box.preCastEnabled = true
    box.expectedCategory = nil
    box.recognizedCategory = nil
    box.isCategoryRecognized = false
    box.hasCategoryMismatch = false
    box.isDragHighlighted = false

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

    local function IsCursorHoldingItem()
        if type(GetCursorInfo) ~= "function" then
            return false
        end
        local cursorType = GetCursorInfo()
        return cursorType == "item"
    end

    local SetDragHighlight

    local function ResolveRecognizedCategory(itemID)
        local numeric = tonumber(itemID)
        if not numeric or numeric <= 0 then
            return nil, false
        end

        local known = addon.const
            and type(addon.const.knownBuffItems) == "table"
            and addon.const.knownBuffItems[numeric]
            or nil
        if type(known) == "table" and type(known.category) == "string" and known.category ~= "" then
            return known.category, true
        end

        if addon.buff and type(addon.buff.GetBuffItemCategory) == "function" then
            local category = addon.buff.GetBuffItemCategory(numeric)
            if category and category ~= "" and category ~= "other_consumable" then
                return category, true
            end
        end

        return nil, false
    end

    local function RefreshBorderState(self)
        local hasItem = self.itemID and self.itemID > 0
        local color = hasItem and self.defaultBorderColor or self.emptyBorderColor
        if self.isDragHighlighted then
            color = self.dragHoverBorderColor
        elseif self.hasCategoryMismatch then
            color = self.mismatchBorderColor
        end
        self:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
    end

    local function RefreshCategoryState(self)
        if not self.itemID or self.itemID <= 0 then
            self.recognizedCategory = nil
            self.isCategoryRecognized = false
            self.hasCategoryMismatch = false
            self.mismatchOverlay:Hide()
            RefreshBorderState(self)
            return
        end

        local category, recognized = ResolveRecognizedCategory(self.itemID)
        self.recognizedCategory = category
        self.isCategoryRecognized = recognized
        self.hasCategoryMismatch = recognized
            and type(self.expectedCategory) == "string"
            and self.expectedCategory ~= ""
            and category ~= self.expectedCategory

        if self.hasCategoryMismatch then
            self.mismatchOverlay:Show()
        else
            self.mismatchOverlay:Hide()
        end

        RefreshBorderState(self)
    end

    local function RefreshVisualState(self)
        local count = tonumber(self.countText and self.countText:GetText()) or 0
        local hasItem = self.itemID and self.itemID > 0

        local shouldDim = (not self.preCastEnabled) or (hasItem and count <= 0)
        local alpha = shouldDim and self.dimIconAlpha or self.fullIconAlpha
        self.icon:SetAlpha(alpha)
        self.countText:SetAlpha(1)
        self.mismatchOverlay:SetAlpha(shouldDim and 0.16 or 0.22)
    end

    function box:SetExpectedCategory(category)
        self.expectedCategory = category
        RefreshCategoryState(self)
    end

    function box:SetEnabledForPreCast(enabled)
        self.preCastEnabled = enabled and true or false
        RefreshVisualState(self)
    end

    local function TryAssignFromCursor(self)
        if type(GetCursorInfo) ~= "function" then
            return false
        end
        local cursorType, itemID = GetCursorInfo()
        if cursorType ~= "item" or not itemID then
            return false
        end

        local targetItemID = self.itemID

        self:SetItemID(itemID)
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
                    setDragState({
                        source = self,
                        sourceItemID = targetItemID,
                    })
                    SetDragHighlight(self, true)
                else
                    setDragState(nil)
                end
            end
        else
            setDragState(nil)
        end

        return true
    end

    SetDragHighlight = function(self, active)
        self.isDragHighlighted = active and true or false
        RefreshBorderState(self)
    end

    local function TryDropCursorItemToSlot(self)
        if type(GetCursorInfo) ~= "function" then
            return false
        end

        local cursorType, cursorItemID = GetCursorInfo()
        if cursorType ~= "item" or not cursorItemID then
            return false
        end

        local sourceState = getDragState()
        local source = sourceState and sourceState.source or nil
        local targetItemID = self.itemID

        self:SetItemID(cursorItemID)

        if source and source ~= self then
            source:SetItemID(targetItemID)
            SetDragHighlight(source, false)
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

        setDragState(nil)
        return true
    end

    box:RegisterForClicks("AnyDown", "AnyUp")
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", function(self)
        if self.itemID and self.itemID > 0 then
            local sourceItemID = self.itemID

            if type(PickupItem) == "function" then
                PickupItem(sourceItemID)
            end

            if type(GetCursorInfo) == "function" then
                local cursorType, cursorItemID = GetCursorInfo()
                if cursorType == "item" and tonumber(cursorItemID) == tonumber(sourceItemID) then
                    self:SetItemID(nil)
                    self.pendingDragPersist = true
                    setDragState({
                        source = self,
                        sourceItemID = sourceItemID,
                    })
                    SetDragHighlight(self, true)
                else
                    setDragState(nil)
                end
            else
                setDragState(nil)
            end
        else
            setDragState(nil)
        end
    end)
    box:SetScript("OnDragStop", function(self)
        local dragState = getDragState()
        if dragState and dragState.source == self then
            setDragState(nil)
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
        local dragState = getDragState()
        if not (dragState and dragState.source == self) then
            SetDragHighlight(self, false)
        end
    end)

    box.countText = box:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    box.countText:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
    box.countText:SetTextColor(0.9, 0.9, 0.9, 1)
    box.countText:SetText("")

    local function UpdateCountDisplay()
        if box.itemID and box.itemID > 0 then
            local count = nil
            if type(getCachedItemCount) == "function" then
                count = tonumber(getCachedItemCount(box.itemID))
            end
            if count == nil then
                count = 0
                if addon.utils and addon.utils.CountItemInBags then
                    count = addon.utils.CountItemInBags(box.itemID)
                end
            end
            box.countText:SetText(tostring(math.max(0, count)))
            if buffItemLastKnownCount[box.itemID] == nil then
                buffItemLastKnownCount[box.itemID] = math.max(0, count)
            end
        else
            box.countText:SetText("")
        end

        RefreshVisualState(box)
    end
    box.UpdateCountDisplay = UpdateCountDisplay

    local originalSetItemID = box.SetItemID
    function box:SetItemID(itemID)
        originalSetItemID(self, itemID)
        UpdateCountDisplay()
        RefreshCategoryState(self)
        if type(self.onItemPresenceChanged) == "function" then
            self:onItemPresenceChanged(self.itemID and self.itemID > 0)
        end
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

    RefreshCategoryState(box)
    RefreshVisualState(box)
    if type(box.onItemPresenceChanged) == "function" then
        box:onItemPresenceChanged(box.itemID and box.itemID > 0)
    end

    return box
end
