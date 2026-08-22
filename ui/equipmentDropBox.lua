local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local AceGUI = LibStub("AceGUI-3.0")
local WIDGET_NAME = "DreamFishEquipmentPreview"
local WIDGET_VERSION = 2
local WIDGET_WIDTH = 100
local WIDGET_HEIGHT = 80

local function GetEquippedProfessionItemID(slotID)
    if type(GetInventoryItemID) ~= "function" then return nil end
    local ok, rawItemID = pcall(GetInventoryItemID, "player", slotID)
    return (ok and tonumber(rawItemID) and tonumber(rawItemID) > 0) and tonumber(rawItemID) or nil
end

--[[
Provides the following custom properties to the widget instance:
    itemID      - The itemID currently assigned to the slot
    isChecked   - Boolean state of the checkbox
    slotID      - The inventory slot ID this widget is associated with
    validateItemIDFunc - Optional function to validate itemIDs before assignment
]]
local function CreateEquipmentDropBox()
    -- Create structural root container
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(WIDGET_WIDTH, WIDGET_HEIGHT)

    local labelString = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelString:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, 0)

    -- Item Slot Button
    local boxFrame = CreateFrame("Button", nil, frame, "BackdropTemplate")
    boxFrame:SetSize(48, 48)
    boxFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -20)
    boxFrame:EnableMouse(true)
    boxFrame:RegisterForClicks("AnyUp")
    boxFrame:RegisterForDrag("LeftButton")

    -- Visual Border and Background Layers for the slot
    local border = boxFrame:CreateTexture(nil, "BORDER")
    border:SetAllPoints(boxFrame)
    border:SetColorTexture(0.42, 0.42, 0.42, 0.9)

    local inner = boxFrame:CreateTexture(nil, "ARTWORK")
    inner:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.08, 0.08, 0.08, 1)

    local icon = boxFrame:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -2, 2)

    -- Checkbox
    local checkboxFrame = CreateFrame("CheckButton", nil, frame, "SettingsCheckboxTemplate")
    checkboxFrame:SetPoint("TOPLEFT", boxFrame, "TOPRIGHT", 5, 0)

    local eventFrame = CreateFrame("Frame", nil, frame)
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("PROFESSION_EQUIPMENT_CHANGED") -- Modern retail profession slot swaps

    -- State Keepers attached cleanly to the widget instance wrapper
    local widget = {
        frame       = frame,
        type        = WIDGET_NAME,
        label       = labelString,
        itemID      = nil,
        isChecked   = false,
        slotID      = nil,
        canRemoveItem = true,
    }

    -- LOCAL CORE UTILITIES

    -- Translates the visual option titles straight into your database key strings
    local function GetDBKeyFromWidgetLabel(label)
        if not label then return nil end
        if label:find("Underlight") or label:find("Angler") then
            return "underlightAngler"
        else
            return "primaryPole"
        end
    end

    local function UpdateVisuals()
        -- 1. Manage Textures
        if widget.itemID and widget.itemID > 0 then
            local iconPath = C_Item.GetItemIconByID(widget.itemID)
            icon:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
        else
            icon:SetTexture(nil)
            DreamFish:Debug("widget.itemID is nil")
        end

        -- 2. Handle Highlight Borders for equipped fishing items
        if widget.itemID and widget.itemID == GetEquippedProfessionItemID(widget.slotID) then
            border:SetColorTexture(0.9, 0.8, 0.2, 0.95) -- Yellow Highlight
        else
            border:SetColorTexture(0.42, 0.42, 0.42, 0.9) -- Default Dark Gray
        end

        -- 3. Sync checkbox visual tick mark
        checkboxFrame:SetChecked(widget.isChecked)
    end

    -- Dispatches updates back into the user options database logic blocks
    local function CommitChanges(newID, newCheck)
        if widget.currentLabel then
            local dbKey = GetDBKeyFromWidgetLabel(widget.currentLabel)

            if dbKey and type(ns.DreamFishDialogOptions) == "table" then
                local polesArgs = ns.DreamFishDialogOptions.args.polesTab.args
                local targetNode = polesArgs[dbKey]

                if targetNode then
                    -- 1. Validate the item safely at runtime
                    if newID and targetNode.arg and targetNode.arg.validateItemIDFunc then
                        if not targetNode.arg.validateItemIDFunc(newID) then
                            return
                        end
                    end

                    -- 2. Call the master options table set handler directly
                    if targetNode.set then
                        targetNode.set(nil, newID and tostring(newID) or "")
                    end

                    -- 3. Update checkbox configuration status
                    if targetNode.arg and targetNode.arg.setIsChecked then
                        targetNode.arg.setIsChecked(newCheck)
                    end

                    -- 4. Notify the layout tree framework to refresh
                    LibStub("AceConfigRegistry-3.0"):NotifyChange("DreamFishDialog")
                    return
                end
            end
        end

        -- Fallback memory layer matrix
        DreamFish:Debug("Ecosystem unlinked. Saving to local state workspace matrix.")
        widget.itemID = newID
        widget.isChecked = newCheck
        UpdateVisuals()
    end

    local function AssignFromCursor()
        local cursorType, id = GetCursorInfo()
        if cursorType == "item" and id then
            CommitChanges(tonumber(id), widget.isChecked)
            ClearCursor()
            UpdateVisuals()
            return true
        end
        return false
    end

    -- LOCAL DYNAMIC DATABASE MAPPER
    local function ReadUserData(self)
        -- 1. Look up the database key dynamically based on the stored label string
        local dbKey = GetDBKeyFromWidgetLabel(widget.currentLabel)

        if dbKey then
            -- 2. Reach directly into your addon namespace functions!
            -- This completely cuts out the race-condition dependency on AceConfig tables
            if type(ns.DreamFishDialogOptions) == "table" then
                -- Pull the functions straight out of the master options tree file cache
                local polesArgs = ns.DreamFishDialogOptions.args.polesTab.args
                local targetNode = polesArgs[dbKey]

                if targetNode and targetNode.arg then
                    local config = targetNode.arg

                    if type(config.getIsChecked) == "function" then
                        widget.isChecked = config.getIsChecked() or false
                    else
                        widget.isChecked = config.isChecked or false
                    end

                    if config.desc and config.desc ~= "" then
                        widget.descText = config.desc
                        -- Bind hover rules onto the root background canvas panel frame
                        frame:SetScript("OnEnter", function(this)
                            GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT", 0, 5)
                            GameTooltip:SetText(widget.currentLabel or "Settings", 1, 1, 1)
                            GameTooltip:AddLine(widget.descText, 0.9, 0.9, 0.9, true)
                            GameTooltip:Show()
                        end)
                        frame:SetScript("OnLeave", function()
                            GameTooltip:Hide()
                        end)
                    end
                end
            end
        else
            DreamFish:Debug("Warning: Could not determine database key from widget label: " .. tostring(widget.currentLabel))
            widget.isChecked = false
        end

        -- Redraw the icons, highlights, and checkboxes instantly
        UpdateVisuals()
    end

    -- FRAME EVENT HANDLERS
    eventFrame:SetScript("OnEvent", function(self, event, slot, hasCurrent)
        -- If slot is nil (some fallback states), trigger anyway just to be completely safe
        if not slot or slot == widget.slotID then
            UpdateVisuals()
        end
    end)

    local contextDropdownFrame = CreateFrame("Frame", "DreamFishTopLayerMenuFrame", UIParent, "UIDropDownMenuTemplate")

    -- Define the isolated initialization layout logic loop
    local function InitializeContextMenu()
        if not widget.availableOptionsList then return end

        -- Add Title row
        local titleInfo = UIDropDownMenu_CreateInfo()
        titleInfo.text = "Select Fishing Pole"
        titleInfo.isTitle = true
        titleInfo.notCheckable = true
        UIDropDownMenu_AddButton(titleInfo)

        -- Extract keys for sorting
        local sortedKeys = {}
        for itemIDStr in pairs(widget.availableOptionsList) do
            if itemIDStr ~= "" then table.insert(sortedKeys, itemIDStr) end
        end

        -- Sort using pre-baked integer tokens
        table.sort(sortedKeys, function(a, b)
            local dataA = widget.availableOptionsList[a] or "0:none:Unknown"
            local dataB = widget.availableOptionsList[b] or "0:none:Unknown"

            local levelA = tonumber(dataA:match("^([0-9]+):")) or 0
            local levelB = tonumber(dataB:match("^([0-9]+):")) or 0

            if levelA ~= levelB then
                return levelA > levelB
            else
                local nameA = dataA:match(":[^:]+:(.+)$") or ""
                local nameB = dataB:match(":[^:]+:(.+)$") or ""
                return nameA < nameB
            end
        end)

        -- Generate interactive list row selections
        for _, itemIDStr in ipairs(sortedKeys) do
            local cleanID = tonumber(itemIDStr)
            local rawPayload = widget.availableOptionsList[itemIDStr] or "0:none:Unknown"

            -- FIX: Unpack our extended payload strings accurately using matching tokens
            local currentLevel = tonumber(rawPayload:match("^([0-9]+):")) or 0
            local locationMarker = rawPayload:match("^[^:]+:([^:]+):") or "none"
            local cleanName = rawPayload:match("^[^:]+:[^:]+:(.+)$") or "Unknown"

            -- Fetch structural rarity color hex values
            local _, _, itemQuality = C_Item.GetItemInfo(cleanID or 0)
            local itemColorHex = "ffffffff"
            if itemQuality then
                local r, g, b, hex = C_Item.GetItemQualityColor(itemQuality)
                if hex then itemColorHex = hex end
            end

            -- Assemble displaying text formatting labels string
            local displayName = currentLevel > 0 and ("[" .. currentLevel .. "] " .. cleanName) or cleanName
            local coloredName = "|c" .. itemColorHex .. displayName .. "|r"

            local info = UIDropDownMenu_CreateInfo()
            info.text = coloredName
            info.notCheckable = true
            info.func = function()
                local cleanIDNum = tonumber(itemIDStr) or nil
                CommitChanges(cleanIDNum, widget.isChecked)
            end

            if cleanID and cleanID > 0 then
                info.classicTooltip = true
                info.tooltipTitle = cleanName

                -- FIX: Use the location token to link the exact physical item to the mouseover frame
                info.funcOnEnter = function(buttonFrame)
                    GameTooltip:SetOwner(buttonFrame, "ANCHOR_RIGHT")

                    if locationMarker == "equipped" then
                        -- Pull directly from what the character is actively wearing
                        GameTooltip:SetInventoryItem("player", widget.slotID)
                    elseif locationMarker:find(",") then
                        -- Pull directly from your specific bag coordinates
                        local targetBag, targetSlot = locationMarker:match("^([0-9]+),([0-9]+)")
                        if targetBag and targetSlot then
                            GameTooltip:SetBagItem(tonumber(targetBag), tonumber(targetSlot))
                        end
                    else
                        -- Fallback baseline if coordinates are unlinked
                        GameTooltip:SetItemByID(cleanID)
                    end

                    if GameTooltip.SetFrameStrata then
                        GameTooltip:SetFrameStrata("TOOLTIP")
                    end
                    GameTooltip:Show()
                end

                info.funcOnLeave = function()
                    GameTooltip:Hide()
                end
            end

            UIDropDownMenu_AddButton(info)
        end
    end

    -- SCRIPT ASSIGNMENTS
    boxFrame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            -- Check if the user is holding an item on their cursor to drop in.
            if AssignFromCursor() then return end

            if widget.availableOptionsList then
                -- Force the layout configuration into our drop target
                UIDropDownMenu_Initialize(contextDropdownFrame, InitializeContextMenu, "MENU")

                -- Force the created dropdown canvas up to the top visual strata layer
                contextDropdownFrame:SetFrameStrata("TOOLTIP")

                -- Toggle menu instantly positioned right at the cursor position
                ToggleDropDownMenu(1, nil, contextDropdownFrame, "cursor", 0, 0)
            end
        elseif button == "RightButton" and IsShiftKeyDown() and widget.canRemoveItem then
            CommitChanges(nil, widget.isChecked)
        end
    end)

    boxFrame:SetScript("OnDragStart", function()
        if widget.itemID and widget.itemID > 0 and widget.canRemoveItem then
            C_Item.PickupItem(widget.itemID)
            CommitChanges(nil, widget.isChecked)
        end
    end)

    boxFrame:SetScript("OnReceiveDrag", AssignFromCursor)

    boxFrame:SetScript("OnEnter", function(self)
        if widget.itemID and widget.itemID > 0 then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

            -- 1. Check if this specific item is currently equipped in your profession slot
            if GetInventoryItemID("player", widget.slotID) == widget.itemID then
                GameTooltip:SetInventoryItem("player", widget.slotID)
                GameTooltip:Show()
                return
            end

            -- 2. If it's not equipped, scan your container bags to find its physical location
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

            -- 3. Fallback to generic template info if the item is not currently on your character
            if not foundInBags then
                GameTooltip:SetItemByID(widget.itemID)
            end

            GameTooltip:Show()
        end
    end)

    boxFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    checkboxFrame:SetScript("OnClick", function(self)
        CommitChanges(widget.itemID, self:GetChecked() or false)
    end)

    -- MANDATORY ACE ECOSYSTEM PIPELINE HOOKS
    widget.SetCallback = function(self, name, func)
        self.callbacks = self.callbacks or {}
        self.callbacks[name] = func
    end

    widget.OnAcquire = function(self)
        -- Turn the listeners back on when the config window displays
        if eventFrame then
            eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
            eventFrame:RegisterEvent("PROFESSION_EQUIPMENT_CHANGED")
        end
        self.frame:Show()
    end

    widget.OnRelease = function(self)
        -- Stop listening to events while resting in the background object pool
        if eventFrame then
            eventFrame:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
            eventFrame:UnregisterEvent("PROFESSION_EQUIPMENT_CHANGED")
        end

        self.frame:Hide()
        self.itemID = nil
        self.slotID = nil
        self.isChecked = false
        self.currentLabel = nil
        if self.callbacks then table.wipe(self.callbacks) end
    end

    widget.SetLabel = function(self, text)
        if self.label then
            self.label:SetText(text or "")

            -- Save the label text string onto the widget so SetText can inspect it
            widget.currentLabel = text
        end
    end

    widget.SetText = function(self, value)
        if value and value ~= "" then
            widget.itemID = tonumber(value)
        else
            widget.itemID = nil
        end

        -- Now that the label is cached in memory, execute the visual data synchronization pass
        ReadUserData(self)
    end

    widget.SetList = function(self, list)
        self.availableOptionsList = list
    end

    -- AceConfig calls this to tell the widget which item key is selected
    widget.SetValue = function(self, value)
        self:SetText(value)
    end

    widget.SetDescription = function(self, text)
        if text and text ~= "" then
            DreamFish:Debug("SetDescription called with text: " .. tostring(text))
            widget.descText = text

            -- Bind mouse hover scripting rules natively to the root structural canvas frame layer
            frame:SetScript("OnEnter", function(this)
                GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT", 0, 5)
                GameTooltip:SetText(widget.currentLabel or "Settings", 1, 1, 1) -- Title
                GameTooltip:AddLine(widget.descText, 0.9, 0.9, 0.9, true)      -- Your 'desc' text wrapped cleanly
                GameTooltip:Show()
            end)

            frame:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        else
            widget.descText = nil
            frame:SetScript("OnEnter", nil)
            frame:SetScript("OnLeave", nil)
        end
    end

    widget.SetDisabled = function(self, disabled) end

    widget.SetCustomData = function(self, data)
        local user = self:GetUserDataTable()
        for key, value in pairs(data or {}) do
            user[key] = value
        end
    end

    widget.SetFontObject = function(self, font) if self.label and font then self.label:SetFontObject(font) end end
    widget.OnWidthSet = function(self, width) self.frame:SetWidth(width or WIDGET_WIDTH) end
    widget.OnHeightSet = function(self, height) self.frame:SetHeight(height or WIDGET_HEIGHT) end

    -- keep these alive so mouse movement (drag'n'drop) works properly
    frame.obj = widget
    boxFrame.obj = widget
    AceGUI:RegisterAsWidget(widget)
    return widget
end

AceGUI:RegisterWidgetType(WIDGET_NAME, CreateEquipmentDropBox, WIDGET_VERSION)
