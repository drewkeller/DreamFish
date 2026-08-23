local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")
local AceGUI = LibStub("AceGUI-3.0")

Fishing:RegisterTraceSource("buffitemdropbox")

local WIDGET_NAME = "DreamFishBuffItemDropBox"
local WIDGET_VERSION = 1
local BOX_SIZE = 48

-- Global or namespace reference tracking the current drag state
Fishing.state = Fishing.state or {}
Fishing.state.uiBuffCursorDragState = Fishing.state.uiBuffCursorDragState or nil
Fishing.state.buffItemLastKnownCount = Fishing.state.buffItemLastKnownCount or {}
Fishing.state.buffItemLastUseAt = Fishing.state.buffItemLastUseAt or {}

local function Trace(msg)
    Fishing:Trace("buffitemdropbox", msg)
end

local function CreateBuffItemWidget()
    -- Base layout panel container
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(BOX_SIZE + 4, BOX_SIZE + 4) -- Compact sizing profile

    -- Core Item Drop Box Button
    local box = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate,BackdropTemplate")
    box:SetSize(BOX_SIZE, BOX_SIZE)
    box:SetPoint("CENTER", frame, "CENTER", 0, 0)
    box:EnableMouse(true)
    box:RegisterForClicks("AnyDown", "AnyUp")
    box:RegisterForDrag("LeftButton")

    -- Visual Border and Backdrop Styling
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    box:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    box.defaultBorderColor = { 0.9, 0.8, 0.2, 1 }
    box.dragHoverBorderColor = { 0.2, 1.0, 0.35, 1 }
    box.invalidDragBorderColor = { 1.0, 0.15, 0.15, 1 }
    box:SetBackdropBorderColor(unpack(box.defaultBorderColor))

    -- Texture Canvas Layer
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetAllPoints(box)

    -- Item Count Overlay Text
    box.countText = box:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    box.countText:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
    box.countText:SetTextColor(1, 1, 1, 1)

    -- Compact Layout: Checkbox placed directly over top-left of the box
    local checkbox = CreateFrame("CheckButton", nil, box, "SettingsCheckboxTemplate")
    checkbox:SetSize(20, 20)
    checkbox:SetPoint("TOPLEFT", box, "TOPLEFT", -2, 2)
    checkbox:SetFrameStrata("MEDIUM")
    checkbox:SetFrameLevel(box:GetFrameLevel() + 5)

    local contextDropdownFrame = CreateFrame("Frame", "DreamFishTopLayerMenuFrame", UIParent, "UIDropDownMenuTemplate")

    -- State Trackers
    local widget = {
        frame     = frame,
        type      = WIDGET_NAME,
        box       = box,
        checkbox  = checkbox,
        itemID    = nil,
        isChecked = false,
        category  = nil,
        index     = nil,
    }

    -- HELPER UTILITIES

    local function SetDragHighlight(state)
        if state == "active" then
            box:SetBackdropBorderColor(unpack(box.dragHoverBorderColor))
        elseif state == "invalid" then
            box:SetBackdropBorderColor(unpack(box.invalidDragBorderColor))
        else
            box:SetBackdropBorderColor(unpack(box.defaultBorderColor))
        end
    end

    local function UpdateCountDisplay()
        if widget.itemID and widget.itemID > 0 then
            local count
            if C_Item and type(C_Item.GetItemCount) == "function" then
                count = C_Item.GetItemCount(widget.itemID, false, false, false, false)
            end
            count = tonumber(count) or 0
            box.countText:SetText(tostring(math.max(0, count)))
            Fishing.state.buffItemLastKnownCount[widget.itemID] = math.max(0, count)
        else
            box.countText:SetText("")
        end
    end

    local function SyncVisuals()
        if widget.itemID and widget.itemID > 0 then
            local iconPath = C_Item.GetItemIconByID(widget.itemID)
            box.icon:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")

            -- Secure Action Right-Click attributes setup
            local bag, slot = DreamFish:FindItemInBags(widget.itemID)
            box:SetAttribute("type2", "item")
            if bag and slot then
                box:SetAttribute("item2", string.format("%d %d", bag, slot))
            else
                box:SetAttribute("item2", "item:" .. widget.itemID)
            end
        else
            box.icon:SetTexture(nil)
            box:SetAttribute("type2", nil)
            box:SetAttribute("item2", nil)
        end

        checkbox:SetChecked(widget.isChecked)
        UpdateCountDisplay()
    end

    local function GetOptionNode()
        local category = widget.arg and widget.arg.category or widget.category
        local index = widget.arg and tonumber(widget.arg.index) or widget.index

        if not category or type(ns.DreamFishDialogOptions) ~= "table" then
            return nil
        end

        local buffsTab = ns.DreamFishDialogOptions.args and ns.DreamFishDialogOptions.args.buffsTab
        local buffArgs = buffsTab and buffsTab.args
        if not buffArgs then return nil end

        local expectedKey = category .. "_" .. tostring(index or 1)
        for _, group in pairs(buffArgs) do
            if type(group) == "table" and type(group.args) == "table" then
                local targetNode = group.args[expectedKey]
                if targetNode then
                    Trace("GetOptionNode: Found target node for category '" .. tostring(category) .. "' index " .. tostring(index) .. " " .. DreamFish:GetDebugItemLabel(widget.itemID))
                    return targetNode
                end
            end
        end

        Trace("GetOptionNode: Did not find target node for category '" .. tostring(category) .. "' index " .. tostring(index) .. " " .. DreamFish:GetDebugItemLabel(widget.itemID))
        return nil
    end

    local function CommitChanges(newItemID, newChecked)
        widget.itemID = newItemID
        widget.isChecked = newChecked

        local targetNode = GetOptionNode()
        if targetNode then
            if targetNode.set then
                targetNode.set(nil, widget.itemID and tostring(widget.itemID) or "")
            end
            if targetNode.arg and targetNode.arg.setIsChecked then
                targetNode.arg.setIsChecked(widget.isChecked)
            end
        end
        SyncVisuals()
    end

    local function IsItemValidForSlot(itemID)
        if not itemID then return false end
        local targetNode = GetOptionNode()
        -- If a validator function is registered in the node's 'arg' table, evaluate it
        if targetNode and targetNode.arg and type(targetNode.arg.validateItemIDFunc) == "function" then
            local bag, slot = DreamFish:FindItemInBags(itemID)
            -- FIX: If the item is currently held on the cursor, bag/slot will be nil.
            -- We inject a placeholder marker so the fallback parser knows to extract data.
            if not bag or not slot then
                if type(GetCursorInfo) == "function" then
                    local cursorType, cursorID = GetCursorInfo()
                    if cursorType == "item" and tonumber(cursorID) == tonumber(itemID) then
                        -- Set virtual slot coordinates to cross-reference cursor contents
                        bag, slot = "cursor", 0
                    end
                end
            end
            return targetNode.arg.validateItemIDFunc(itemID, bag, slot)
        end
        return true -- Default to pass if no specific filter is declared
    end

    local function TryAssignFromCursor()
        if type(GetCursorInfo) ~= "function" then return false end
        local cursorType, id = GetCursorInfo()
        if cursorType == "item" and id then
            local cleanID = tonumber(id)
            -- Reject drops that do not pass validation
            if not IsItemValidForSlot(cleanID) then
                Trace("Rejected item drop from cursor: itemID " .. tostring(cleanID) .. " failed validation requirements.")
                return false
            end

            CommitChanges(cleanID, widget.isChecked)
            if type(ClearCursor) == "function" then ClearCursor() end
            return true
        end
        return false
    end

    local function TryDropCursorItemToSlot()
        if type(GetCursorInfo) ~= "function" then return false end
        local cursorType, cursorItemID = GetCursorInfo()
        if cursorType ~= "item" or not cursorItemID then return false end

        local cleanCursorItemID = tonumber(cursorItemID)
        -- Reject swaps or placement if the validation rules fail
        if not IsItemValidForSlot(cleanCursorItemID) then
            Trace("Rejected inter-slot drag assignment: itemID " .. tostring(cleanCursorItemID) .. " failed validation requirements.")
            return false
        end

        local sourceState = Fishing.state.uiBuffCursorDragState
        local sourceWidget = sourceState and sourceState.source or nil
        local targetItemID = widget.itemID

        -- Reassign item variables onto slot positions
        CommitChanges(cleanCursorItemID, widget.isChecked)

        if sourceWidget and sourceWidget ~= widget then
            sourceWidget.obj:ExternalCommit(targetItemID, sourceWidget.obj.isChecked)
            SetDragHighlight(false)
        end

        if type(ClearCursor) == "function" then ClearCursor() end
        Fishing.uiBuffCursorDragState = nil
        return true
    end

    function widget:ExternalCommit(id, checked)
        CommitChanges(id, checked)
    end

    local function Capitalize(str)
        return (string.gsub(str, "^%l", string.upper))
    end

    local function InitializeContextMenu()
        if not widget.availableOptionsList then return end
        local titleInfo = UIDropDownMenu_CreateInfo()
        titleInfo.text = "Select " .. widget.categoryTitle .. " Item"
        titleInfo.isTitle = true
        titleInfo.notCheckable = true
        UIDropDownMenu_AddButton(titleInfo)

        local sortedKeys = {}
        for itemIDStr in pairs(widget.availableOptionsList) do
            table.insert(sortedKeys, itemIDStr)
        end

        table.sort(sortedKeys, function(leftKey, rightKey)
            local leftPayload = widget.availableOptionsList[leftKey] or ""
            local rightPayload = widget.availableOptionsList[rightKey] or ""

            local leftName = tostring(leftPayload):match("^([^:]+)") or "Unknown"
            local rightName = tostring(rightPayload):match("^([^:]+)") or "Unknown"

            -- Case-insensitive alphabetical comparison
            return string.lower(leftName) < string.lower(rightName)
        end)

        -- 3. Render the buttons sequentially using the sorted keys array
        for _, itemIDStr in ipairs(sortedKeys) do
            local cleanID = tonumber(itemIDStr)
            local payload = widget.availableOptionsList[itemIDStr]
            local cleanName = tostring(payload):match("^([^:]+)") or "Unknown"

            local info = UIDropDownMenu_CreateInfo()
            info.text = cleanName
            info.value = cleanID
            info.func = function(self)
                CommitChanges(self.value, widget.isChecked)
            end
            info.classicTooltip = true
            info.tooltipTitle = cleanName
            info.funcOnEnter = function(self)
                GameTooltip:SetOwner(self:GetParent(), "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.value)
                GameTooltip:Show()
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    -- DRAG AND DROP SCRIPTS BINDINGS
    box:SetScript("OnDragStart", function(self)
        if widget.itemID and widget.itemID > 0 then
            local sourceItemID = widget.itemID
            if type(C_Item.PickupItem) == "function" then C_Item.PickupItem(sourceItemID) end

            if type(GetCursorInfo) == "function" then
                local cursorType, cursorItemID = GetCursorInfo()
                if cursorType == "item" and tonumber(cursorItemID) == tonumber(sourceItemID) then
                    CommitChanges(nil, widget.isChecked)
                    Fishing.state.uiBuffCursorDragState = { source = box }
                    SetDragHighlight(true)
                else
                    Fishing.state.uiBuffCursorDragState = nil
                end
            end
        end
    end)

    box:SetScript("OnDragStop", function(self)
        if Fishing.state.uiBuffCursorDragState and Fishing.state.uiBuffCursorDragState.source == box then
            Fishing.state.uiBuffCursorDragState = nil
        end
        SetDragHighlight(false)
    end)

    box:SetScript("OnReceiveDrag", function(self)
        if TryDropCursorItemToSlot() then return end
        TryAssignFromCursor()
        SetDragHighlight(nil)
    end)

    box:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            local hasItemOnCursor = false
            if type(GetCursorInfo) == "function" then
                hasItemOnCursor = (GetCursorInfo() == "item")
            end

            if TryDropCursorItemToSlot() then return end
            if TryAssignFromCursor() then return end
            if hasItemOnCursor then return end

            if widget.availableOptionsList then
                UIDropDownMenu_Initialize(contextDropdownFrame, InitializeContextMenu, "MENU")
                contextDropdownFrame:SetFrameStrata("TOOLTIP")
                ToggleDropDownMenu(1, nil, contextDropdownFrame, "cursor", 0, 0)
            end
        elseif button == "RightButton" and IsShiftKeyDown() then
            CommitChanges(nil, widget.isChecked)
        end
    end)

    -- MOUSE OVER TOOLTIPS PIPELINES
    box:SetScript("OnEnter", function(self)
        Trace("OnEnter ".. widget.category)
        if type(GetCursorInfo) == "function" then
            local cursorType, cursorItemID = GetCursorInfo()
            if cursorType == "item" and cursorItemID then
                Trace("OnEnter: " .. DreamFish:GetDebugItemLabel(cursorItemID))
                if IsItemValidForSlot(tonumber(cursorItemID)) then
                    SetDragHighlight("valid")
                else
                    SetDragHighlight("invalid")
                end
            end
        else
            Trace("GetCursorInfo() is not available; cannot validate item drag state.")
        end
        if widget.itemID and widget.itemID > 0 then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local foundInBags = false
            for bag = 0, NUM_BAG_SLOTS do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    if C_Container.GetContainerItemID(bag, slot) == widget.itemID then
                        GameTooltip:SetBagItem(bag, slot)
                        foundInBags = true
                        break
                    end
                end
                if foundInBags then break end
            end
            if not foundInBags then GameTooltip:SetItemByID(widget.itemID) end
            GameTooltip:Show()
        end
    end)

    box:SetScript("OnLeave", function()
        SetDragHighlight(nil)
        GameTooltip:Hide()
    end)

    -- SECURE ACTION USAGE MONITORS HOOK

    -- Shift-right click to remove the item
    -- Right click to use the item and track its usage
    box:HookScript("OnClick", function(self, button)
        if button ~= "RightButton" or not widget.itemID or widget.itemID <= 0 then return end
        if IsShiftKeyDown() then
            Fishing.state.buffItemLastUseAt[widget.itemID] = nil
            CommitChanges(nil, widget.isChecked)
        else
            local now = GetTime()
            Fishing.state.buffItemLastUseAt[widget.itemID] = now
            Fishing.state.pendingBuffObservation = {
                itemID = widget.itemID,
                before = Fishing:BuildHelpfulAuraSnapshot(),
                expiresAt = now + 20,
            }
            Fishing:AnnounceBuffUse(widget.itemID)
            UpdateCountDisplay()
        end
    end)

    checkbox:SetScript("OnClick", function(self)
        Trace("Checkbox clicked: " .. tostring(widget.itemID) .. " isChecked=" .. tostring(self:GetChecked() or false))
        CommitChanges(widget.itemID, self:GetChecked() or false)
    end)

    -- ACEGUI LIFECYCLE INTERFACES REQUIRED IMPLEMENTATIONS
    widget.OnRelease = function(self)
        self.frame:Hide()
        self.itemID = nil
        self.isChecked = false
        self.category = nil
        self.index = nil
        self:SetUserData("category", nil)
        self:SetUserData("index", nil)
    end

    widget.OnAcquire = function(self)
        self.frame:Show()
    end

    widget.SetLabel = function(self, text)
        -- The label is a display name, not the nested option key.
    end

    widget.SetList = function(self, list)
        self.availableOptionsList = list
    end

    widget.SetCustomData = function(self, data)
        self.category = data and data.category or nil
        self.index = data and tonumber(data.index) or 1
        self.categoryTitle = data and data.categoryTitle or nil
    end

    widget.SetText = function(self, value)
        if value and value ~= "" then
            self.itemID = tonumber(value)
        else
            self.itemID = nil
        end

        if self.arg then
            self.category = self.arg.category or self.category
            self.index = tonumber(self.arg.index) or self.index
            self.categoryTitle = self.arg.categoryTitle or self.categoryTitle
        end
        local targetNode = GetOptionNode()
        if targetNode and targetNode.arg and targetNode.arg.getIsChecked then
            self.isChecked = targetNode.arg.getIsChecked() or false
        end
        SyncVisuals()
    end

    widget.SetValue = function(self, value)
        self:SetText(value)
    end

    widget.SetDisabled = function(self, disabled) end
    widget.OnWidthSet = function(self, width) self.frame:SetWidth(width or (BOX_SIZE + 4)) end
    widget.OnHeightSet = function(self, height) self.frame:SetHeight(height or (BOX_SIZE + 4)) end
    frame.obj = widget
    box.obj = widget
    AceGUI:RegisterAsWidget(widget)
    return widget
end

AceGUI:RegisterWidgetType(WIDGET_NAME, CreateBuffItemWidget, WIDGET_VERSION)
