-- DreamFisher Buff Item Drop Box UI

local addon = _G["DreamFisher"]
addon.ui = addon.ui or {}

function addon.ui.CreateBuffItemDropBox(deps, parent, x, y, label, onLiveChange)
    local ResolveExpectedDurationForItem = deps.ResolveExpectedDurationForItem
    local buffItemLastKnownCount = deps.buffItemLastKnownCount
    local buffItemLastUseAt = deps.buffItemLastUseAt
    local getDragState = deps.getDragState
    local setDragState = deps.setDragState

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
                    setDragState({
                        source = self,
                        sourceItemID = targetItemID,
                        sourceExpectedDuration = targetExpectedDuration,
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

        local sourceState = getDragState()
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

        setDragState(nil)
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
                    setDragState({
                        source = self,
                        sourceItemID = sourceItemID,
                        sourceExpectedDuration = sourceExpectedDuration,
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
