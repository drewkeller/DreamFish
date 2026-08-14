local addonName, ns = ...

-- Helper function to get currently equipped item in profession slot (slot 16 = main hand weapon)
local function GetEquippedProfessionItemID()
    if type(GetInventoryItemID) ~= "function" then
        return nil
    end
    local ok, rawItemID = pcall(GetInventoryItemID, "player", 16)
    if not ok then
        return nil
    end
    local itemID = tonumber(rawItemID)
    if not itemID or itemID <= 0 then
        return nil
    end
    return itemID
end

-- Create a reusable item dropbox widget
-- Parameters:
--   charDB: Character database table (for persistence)
--   dbKey: Key in charDB where the item data is stored (must be a table with .itemID and .isChecked)
--   parentFrame: Parent frame to attach the widget to
--   x, y: Position relative to parent
--   title: Display title for the dropbox
--   onChangeCallback: Optional callback function when item changes
--   validateItemIDFunc: Optional validation function to filter items
local function CreateItemDropBox(charDB, dbKey, parentFrame, x, y, title, onChangeCallback, validateItemIDFunc)
    -- The saved-variable entry may not exist yet on a fresh character
    if type(charDB[dbKey]) ~= "table" then
        charDB[dbKey] = { isChecked = false, itemID = nil }
    end

    local container = CreateFrame("Frame", nil, parentFrame)
    container:SetSize(100, 80)
    container:SetPoint("TOPLEFT", x, y)

    -- Title
    local titleText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    titleText:SetText(title)

    -- Dropbox frame
    local boxFrame = CreateFrame("Button", nil, container)
    boxFrame:SetSize(48, 48)
    boxFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -20)
    boxFrame:RegisterForClicks("AnyUp")
    boxFrame:RegisterForDrag("LeftButton")

    -- Background
    local bg = boxFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(boxFrame)
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)

    -- Border
    local border = boxFrame:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", 0, 0)
    border:SetColorTexture(0.42, 0.42, 0.42, 0.9)

    -- Inner
    local inner = boxFrame:CreateTexture(nil, "ARTWORK")
    inner:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.08, 0.08, 0.08, 1)

    -- Icon
    local icon = boxFrame:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -2, 2)
    icon:SetTexture(nil)

    -- Checkbox for enable/disable
    local checkboxFrame = CreateFrame("CheckButton", nil, container, "ChatConfigCheckButtonTemplate")
    checkboxFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 52, -20)

    boxFrame.itemID = nil
    boxFrame.isEquipped = false

    local function UpdateBorderColor()
        local equippedID = GetEquippedProfessionItemID()
        boxFrame.isEquipped = boxFrame.itemID and boxFrame.itemID > 0 and equippedID == boxFrame.itemID
        if boxFrame.isEquipped then
            border:SetColorTexture(0.9, 0.8, 0.2, 0.95) -- Yellow
        else
            border:SetColorTexture(0.42, 0.42, 0.42, 0.9)
        end
    end

    local function SetItemID(itemID)
        local numeric = tonumber(itemID)
        if numeric and numeric > 0 then
            if validateItemIDFunc and not validateItemIDFunc(numeric) then
                return
            end
            boxFrame.itemID = numeric
            charDB[dbKey].itemID = numeric
            local itemObj = Item:CreateFromItemID(numeric)
            if itemObj then
                local textureID = itemObj:GetItemIcon()
                icon:SetTexture(textureID)
            end
        else
            boxFrame.itemID = nil
            charDB[dbKey].itemID = nil
            icon:SetTexture(nil)
        end
        UpdateBorderColor()
        if onChangeCallback then
            onChangeCallback()
        end
    end

    local function AssignFromCursor()
        if type(GetCursorInfo) ~= "function" then
            return false
        end
        local cursorType, itemID = GetCursorInfo()
        if cursorType ~= "item" or not itemID then
            return false
        end
        if validateItemIDFunc and not validateItemIDFunc(itemID) then
            return false
        end
        SetItemID(itemID)
        if type(ClearCursor) == "function" then
            ClearCursor()
        end
        return true
    end

    boxFrame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            AssignFromCursor()
        elseif button == "RightButton" and IsShiftKeyDown() then
            SetItemID(nil)
        end
    end)

    boxFrame:SetScript("OnDragStart", function(self)
        if self.itemID and self.itemID > 0 then
            if type(C_Item) == "table" and type(C_Item.PickupItem) == "function" then
                C_Item.PickupItem(self.itemID)
                SetItemID(nil)
            end
        end
    end)

    boxFrame:SetScript("OnReceiveDrag", function(self)
        AssignFromCursor()
    end)

    boxFrame:SetScript("OnEnter", function(self)
        if self.itemID and self.itemID > 0 and type(GameTooltip) == "table" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if type(GameTooltip.SetItemByID) == "function" then
                GameTooltip:SetItemByID(self.itemID)
            end
            GameTooltip:Show()
        end
    end)

    boxFrame:SetScript("OnLeave", function()
        if type(GameTooltip) == "table" then
            GameTooltip:Hide()
        end
    end)

    -- Checkbox handling
    checkboxFrame:SetScript("OnClick", function(self)
        charDB[dbKey].isChecked = self:GetChecked() or false
        if onChangeCallback then
            onChangeCallback()
        end
    end)

    return boxFrame, checkboxFrame, SetItemID, UpdateBorderColor
end

ns.ui = ns.ui or {}
ns.ui.CreateItemDropBox = CreateItemDropBox
ns.ui.GetEquippedProfessionItemID = GetEquippedProfessionItemID
