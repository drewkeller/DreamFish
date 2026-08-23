local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

DreamFish:RegisterTraceSource("subbuttonslot")

local function Trace(msg)
    DreamFish:Trace("subbuttonslot", msg)
end

local BOX_SIZE = 48

-- Global or namespace reference tracking the current drag state
Fishing.state = Fishing.state or {}
Fishing.state.uiBuffCursorDragState = Fishing.state.uiBuffCursorDragState or nil
Fishing.state.buffItemLastKnownCount = Fishing.state.buffItemLastKnownCount or {}
Fishing.state.buffItemLastUseAt = Fishing.state.buffItemLastUseAt or {}

local function CreateSubButtonSlot(parentCanvas, slotIndex)
    local frame = CreateFrame("Frame", nil, parentCanvas, "BackdropTemplate")
    frame:SetSize(BOX_SIZE + 4, BOX_SIZE + 4)

    local box = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate,BackdropTemplate")
    box:SetSize(BOX_SIZE, BOX_SIZE)
    box:SetPoint("CENTER", frame, "CENTER", 0, 0)
    box:EnableMouse(true)
    box:RegisterForClicks("AnyDown", "AnyUp")
    box:RegisterForDrag("LeftButton")

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

    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetAllPoints(box)

    box.countText = box:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    box.countText:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
    box.countText:SetTextColor(1, 1, 1, 1)

    local checkbox = CreateFrame("CheckButton", nil, box, "SettingsCheckboxTemplate")
    checkbox:SetSize(20, 20)
    checkbox:SetPoint("TOPLEFT", box, "TOPLEFT", -2, 2)
    checkbox:SetFrameStrata("MEDIUM")
    checkbox:SetFrameLevel(box:GetFrameLevel() + 5)

    local contextDropdownFrame = CreateFrame("Frame", "DreamFishCanvasMenuFrame_" .. slotIndex, UIParent, "UIDropDownMenuTemplate")

    local slot = {
        frame = frame,
        box = box,
        checkbox = checkbox,
        contextDropdownFrame = contextDropdownFrame,
        index = slotIndex,
        itemID = nil,
        isChecked = false,
    }

    local function SetDragHighlight(state)
        if state == "active" or state == "valid" then
            box:SetBackdropBorderColor(unpack(box.dragHoverBorderColor))
        elseif state == "invalid" then
            box:SetBackdropBorderColor(unpack(box.invalidDragBorderColor))
        else
            box:SetBackdropBorderColor(unpack(box.defaultBorderColor))
        end
    end

    local function UpdateCountDisplay()
        if slot.itemID and slot.itemID > 0 then
            local count = C_Item.GetItemCount(slot.itemID, false, false, false, false) or 0
            box.countText:SetText(tostring(math.max(0, count)))
            Fishing.state.buffItemLastKnownCount[slot.itemID] = math.max(0, count)
        else
            box.countText:SetText("")
        end
    end

    local function SyncVisuals()
        if slot.itemID and slot.itemID > 0 then
            Trace("SyncVisuals: updating slot " .. tostring(slot.index) .. " with itemID " .. tostring(slot.itemID) .. " and checked state " .. tostring(slot.isChecked))
            box.icon:SetTexture(C_Item.GetItemIconByID(slot.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")

            -- FIX: Locate the item in bags so the SecureActionButton can fire it reliably
            local bag, slotLoc = DreamFish:FindItemInBags(slot.itemID)
            box:SetAttribute("type2", "item")
            if bag and slotLoc then
                box:SetAttribute("item2", string.format("%d %d", bag, slotLoc))
            else
                box:SetAttribute("item2", "item:" .. slot.itemID)
            end
        else
            box.icon:SetTexture(nil)
            box:SetAttribute("type2", nil)
            box:SetAttribute("item2", nil)
        end
        checkbox:SetChecked(slot.isChecked)
        UpdateCountDisplay()
    end

    local function CommitChanges(newItemID, newChecked)
        slot.itemID = newItemID or nil
        slot.isChecked = newChecked and true or false

        if parentCanvas.arg then
            -- 1. Pass the absolute variable straight to your updated database setters
            if parentCanvas.arg.SetItemValue then
                parentCanvas.arg.SetItemValue(slot.index, slot.itemID)
            end
            if parentCanvas.arg.SetCheckedValue then
                parentCanvas.arg.SetCheckedValue(slot.index, slot.isChecked)
            end

            if LibStub("AceConfigRegistry-3.0") then
                Trace("Notifying AceConfigRegistry of changes to " .. tostring(parentCanvas.arg and parentCanvas.arg.category) .. "[" .. tostring(slot.index) .. "]")

                -- This one allows changes to appear in the dialog, but doesn't seem to save to database
                -- or even when closing the dialog
                --LibStub("AceConfigRegistry-3.0"):NotifyChange("DreamFish")

                -- This one does not show changes in the dialog, not sure about the database
                -- Perhaps due to some other conflict or misalignment
                LibStub("AceConfigRegistry-3.0"):NotifyChange("DreamFishDialog")
            end
        end
        SyncVisuals()
    end

    local function IsItemValidForSlot(itemID)
        if not itemID then return false end
        if parentCanvas.arg and type(parentCanvas.arg.validateItemIDFunc) == "function" then
            -- Look up the item's live physical container bag and slot coordinates
            -- so Fishing:IsBuffItemCategory can accurately execute its tooltip checks
            local bag, slotLoc = DreamFish:FindItemInBags(itemID)
            if not bag or not slotLoc then
                local cursorType, cursorID = GetCursorInfo()
                if cursorType == "item" and tonumber(cursorID) == tonumber(itemID) then
                    bag, slotLoc = "cursor", 0
                end
            end
            return parentCanvas.arg.validateItemIDFunc(itemID, bag, slotLoc)
        end
        return true
    end

    local function TryAssignFromCursor()
        local cursorType, id = GetCursorInfo()
        if cursorType == "item" and id then
            local cleanID = tonumber(id)
            if not IsItemValidForSlot(cleanID) then
                Trace("TryAssignFromCursor: rejected itemID " .. tostring(cleanID) .. " for " .. tostring(parentCanvas.arg and parentCanvas.arg.category) .. "[" .. tostring(slot.index) .. "]")
                return false
            end
            Trace("TryAssignFromCursor: assigning itemID " .. tostring(cleanID) .. " to " .. tostring(parentCanvas.arg and parentCanvas.arg.category) .. "[" .. tostring(slot.index) .. "]")
            CommitChanges(cleanID, slot.isChecked)
            ClearCursor()
            return true
        end
        return false
    end

    local function TryDropCursorItemToSlot()
        local cursorType, cursorItemID = GetCursorInfo()
        if cursorType ~= "item" or not cursorItemID then return false end
        local cleanCursorItemID = tonumber(cursorItemID)
        if not IsItemValidForSlot(cleanCursorItemID) then
            Trace("TryDropCursorItemToSlot: rejected itemID " .. tostring(cleanCursorItemID) .. " for " .. tostring(parentCanvas.arg and parentCanvas.arg.category) .. "[" .. tostring(slot.index) .. "]")
            return false
        end

        local sourceState = Fishing.state.uiBuffCursorDragState
        local sourceWidget = sourceState and sourceState.source or nil
        local targetItemID = slot.itemID

        Trace("TryDropCursorItemToSlot: assigning itemID " .. tostring(cleanCursorItemID) .. " to " .. tostring(parentCanvas.arg and parentCanvas.arg.category) .. "[" .. tostring(slot.index) .. "]")
        CommitChanges(cleanCursorItemID, slot.isChecked)

        if sourceWidget and sourceWidget ~= slot then
            sourceWidget.obj:ExternalCommit(targetItemID, sourceWidget.obj.isChecked)
            sourceWidget.obj.box:SetBackdropBorderColor(unpack(sourceWidget.obj.box.defaultBorderColor))
        end

        ClearCursor()
        Fishing.state.uiBuffCursorDragState = nil
        return true
    end

    function slot:ExternalCommit(id, checked)
        CommitChanges(id, checked)
    end

    local function InitializeContextMenu()
        if not parentCanvas.arg or not parentCanvas.arg.category then return end
        local catKey = parentCanvas.arg.category

        local titleInfo = UIDropDownMenu_CreateInfo()
        titleInfo.text = "Select " .. (parentCanvas.arg.categoryTitle or "Item") .. " Item"
        titleInfo.isTitle = true
        titleInfo.notCheckable = true
        UIDropDownMenu_AddButton(titleInfo)

        -- FIX: Query the game database directly using your options table callback logic
        -- to construct menu values on-the-fly, completely bypassing cross-file caching issues
        if type(parentCanvas.arg.dropdownMenuData) == "function" then
            local menuData = parentCanvas.arg.dropdownMenuData()
            local sortedKeys = {}
            for k in pairs(menuData) do table.insert(sortedKeys, k) end
            table.sort(sortedKeys, function(a, b)
                return string.lower(tostring(menuData[a]):match("^([^:]+)")) < string.lower(tostring(menuData[b]):match("^([^:]+)"))
            end)

            for _, itemIDStr in ipairs(sortedKeys) do
                local cleanID = tonumber(itemIDStr)
                local cleanName = tostring(menuData[itemIDStr]):match("^([^:]+)") or "Unknown"

                local info = UIDropDownMenu_CreateInfo()
                info.text = cleanName
                info.value = cleanID
                info.func = function(self)
                    Trace("Dropdown selection: assigning itemID " .. tostring(self.value) .. " to " .. tostring(parentCanvas.arg and parentCanvas.arg.category) .. "[" .. tostring(slot.index) .. "]")
                    CommitChanges(self.value, slot.isChecked)
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
    end

    box:SetScript("OnDragStart", function()
        if slot.itemID and slot.itemID > 0 then
            C_Item.PickupItem(slot.itemID)
            if GetCursorInfo() == "item" then
                CommitChanges(nil, slot.isChecked)
                Fishing.state.uiBuffCursorDragState = { source = slot }
                SetDragHighlight("active")
            end
        end
    end)

    box:SetScript("OnDragStop", function()
        if Fishing.state.uiBuffCursorDragState and Fishing.state.uiBuffCursorDragState.source == slot then
            Fishing.state.uiBuffCursorDragState = nil
        end
        SetDragHighlight(nil)
    end)

    box:SetScript("OnReceiveDrag", function()
        if TryDropCursorItemToSlot() then return end
        TryAssignFromCursor()
        SetDragHighlight(nil)
    end)

    box:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            local hasItemOnCursor = (GetCursorInfo() == "item")
            if TryDropCursorItemToSlot() then return end
            if TryAssignFromCursor() then return end
            if hasItemOnCursor then return end

            if parentCanvas.arg and type(parentCanvas.arg.dropdownMenuData) == "function" then
                UIDropDownMenu_Initialize(contextDropdownFrame, InitializeContextMenu, "MENU")
                contextDropdownFrame:SetFrameStrata("TOOLTIP")
                ToggleDropDownMenu(1, nil, contextDropdownFrame, "cursor", 0, 0)
            end
        elseif button == "RightButton" and IsShiftKeyDown() then
            CommitChanges(nil, slot.isChecked)
        end
    end)

    box:SetScript("OnEnter", function(self)
        local cursorType, cursorItemID = GetCursorInfo()
        if cursorType == "item" and cursorItemID then
            if IsItemValidForSlot(tonumber(cursorItemID)) then SetDragHighlight("valid") else SetDragHighlight("invalid") end
        end
        if slot.itemID and slot.itemID > 0 then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(slot.itemID)
            GameTooltip:Show()
        end
    end)

    box:SetScript("OnLeave", function()
        SetDragHighlight(nil)
        GameTooltip:Hide()
    end)

    box:HookScript("OnClick", function(_, button)
        if button ~= "RightButton" or not slot.itemID or slot.itemID <= 0 then return end
        if IsShiftKeyDown() then
            Fishing.state.buffItemLastUseAt[slot.itemID] = nil
            CommitChanges(nil, slot.isChecked)
        else
            local now = GetTime()
            Fishing.state.buffItemLastUseAt[slot.itemID] = now
            Fishing.state.pendingBuffObservation = {
                itemID = slot.itemID,
                before = Fishing:BuildHelpfulAuraSnapshot(),
                expiresAt = now + 20,
            }
            Fishing:AnnounceBuffUse(slot.itemID)
            UpdateCountDisplay()
        end
    end)

    checkbox:SetScript("OnClick", function(self)
        CommitChanges(slot.itemID, self:GetChecked() or false)
    end)

    function slot:LoadSavedState()
        if parentCanvas.arg then
            self.itemID = tonumber(parentCanvas.arg.GetItemValue(self.index)) or nil
            self.isChecked = parentCanvas.arg.GetCheckedValue(self.index) or false
        end
        SyncVisuals()
    end

    box.obj = slot
    return slot

end

-- Export the factory function directly onto your shared addon namespace
ns.CreateSubButtonSlot = CreateSubButtonSlot
