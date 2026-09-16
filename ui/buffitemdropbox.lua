local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing
local AceGUI = LibStub("AceGUI-3.0")

Addon:RegisterTraceSource("buffitemdropbox")
Addon:RegisterTraceSource("learning")

local WIDGET_NAME = "DreamFishBuffItemDropBox"
local WIDGET_VERSION = 1
local BOX_SIZE = 48

-- Global or namespace reference tracking the current drag state
Fishing.state = Fishing.state or {}
Fishing.state.uiBuffCursorDragState = Fishing.state.uiBuffCursorDragState or nil
Fishing.state.buffItemLastKnownCount = Fishing.state.buffItemLastKnownCount or {}
Fishing.state.buffItemLastUseAt = Fishing.state.buffItemLastUseAt or {}
ns.BuffLearningWidgets = ns.BuffLearningWidgets or {}

local function Trace(msg)
    Addon:TraceCore("buffitemdropbox", msg)
end

local function CreateBuffItemWidget()
    -- Base layout panel container canvas row; the real per-slot buttons are built
    -- on demand into this frame by ns.CreateSubButtonSlot (see subButtonSlot.lua).
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(300, BOX_SIZE + 4)

    -- State Trackers
    local widget = {
        frame    = frame,
        type     = WIDGET_NAME,
        category = nil,
        userdata = {},
    }

    local function EnsureLearningButton(self)
        if self.learningButton then
            return self.learningButton
        end
        local button = CreateFrame("Button", nil, self.frame, "SecureActionButtonTemplate,UIPanelButtonTemplate")
        button:SetSize(180, 28)
        button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:HookScript("OnMouseDown", function(_, mouseButton)
            Addon:TraceCore("learning", "Learning mouse down: button=" .. tostring(mouseButton))
        end)
        button:HookScript("OnMouseUp", function(_, mouseButton)
            Addon:TraceCore("learning", "Learning mouse up: button=" .. tostring(mouseButton))
        end)
        button:HookScript("PreClick", function(_, mouseButton, down)
            local parent = button:GetParent()
            local mouseFocus = type(GetMouseFocus) == "function" and GetMouseFocus() or nil
            Addon:TraceCore("learning", "Learning PreClick: button=" .. tostring(mouseButton)
                .. " down=" .. tostring(down)
                .. " type1=" .. tostring(button:GetAttribute("type1"))
                .. " macrotext1=" .. tostring(button:GetAttribute("macrotext1"))
                .. " combat=" .. tostring(InCombatLockdown())
                .. " protected=" .. tostring(button:IsProtected())
                .. " enabled=" .. tostring(button:IsEnabled())
                .. " visible=" .. tostring(button:IsVisible())
                .. " parentProtected=" .. tostring(parent and parent:IsProtected())
                .. " focused=" .. tostring(mouseFocus == button))
            if mouseButton == "LeftButton" and not down and button.learningCandidate then
                Fishing.state.buffLearningAttemptUntil = GetTime() + 7
                Fishing:BeginBuffLearning(button.learningCandidate)
            end
        end)
        button:HookScript("PostClick", function(_, mouseButton, down)
            if mouseButton ~= "LeftButton" or down then
                return
            end
            Addon:TraceCore("learning", "Learning button clicked")
            if type(Fishing.state.buffLearning) == "table" then
                Addon:TraceCore("learning", "Buff learning started for item "
                    .. tostring(Fishing.state.buffLearning.itemID))
                Fishing:MarkBuffLearningExecuted()
            end
            C_Timer.After(0, function()
                Fishing:NotifyBuffLearningChanged()
            end)
            C_Timer.After(0.1, function()
                local learning = Fishing.state.buffLearning
                local itemID = learning and learning.itemID or nil
                local itemCount = itemID and C_Item.GetItemCount(itemID, false, false, false, false) or nil
                local cooldownInfo = itemID and C_Item.GetItemCooldown and C_Item.GetItemCooldown(itemID) or nil
                Addon:TraceCore("learning", "Learning post-click: itemID=" .. tostring(itemID)
                    .. " count=" .. tostring(itemCount)
                    .. " cooldown=" .. tostring(cooldownInfo)
                    .. " type1=" .. tostring(button:GetAttribute("type1"))
                    .. " macrotext1=" .. tostring(button:GetAttribute("macrotext1")))
            end)
        end)
        self.learningButton = button
        return button
    end

    local function RefreshLearningButton(self)
        local button = EnsureLearningButton(self)
        local learning = Fishing:GetBuffLearningStatus()
        local count = Fishing:GetBuffLearningCandidateCount()
        local isBusy = type(learning) == "table" and learning.phase ~= nil
        button.learningCandidate = isBusy and nil or learning
        button:Show()
        button:SetText(isBusy and "Learning..." or ("Learn (" .. tostring(count) .. " items)"))
        if not InCombatLockdown() then
            local macroText = learning and not isBusy and "/use item:" .. tostring(learning.itemID) or nil
            button:SetAttribute("type", macroText and "macro" or nil)
            button:SetAttribute("macrotext", macroText)
            button:SetAttribute("type1", macroText and "macro" or nil)
            button:SetAttribute("macrotext1", macroText)
            button:SetAttribute("type2", nil)
            button:SetAttribute("macrotext2", nil)
            button:SetAttribute("item", nil)
            button:SetAttribute("item1", nil)
        end
        Addon:TraceCore("learning", button:GetText() .. " learning=" .. tostring(learning)
            .. " isBusy=" .. tostring(isBusy) .. ", count=" .. tostring(count)
            .. ", macrotext1=" .. tostring(button:GetAttribute("macrotext1")))
        if count <= 0 or isBusy or InCombatLockdown() then
            button:Disable()
        else
            button:Enable()
        end
    end

    -- ACEGUI LIFECYCLE INTERFACES REQUIRED IMPLEMENTATIONS
    widget.OnRelease = function(self)
        self.frame:Hide()
        self.category = nil
        self:SetUserData("category", nil)
    end

    widget.OnAcquire = function(self)
        self.frame:Show()
    end

    widget.SetHeight = function(self, height)
        -- We deliberately leave this empty or pass it straight to the container frame,
        -- as our custom SetText loop already calculates and sets the true 2D height dynamically!
        if height and height > 0 then
            self.frame:SetHeight(height)
        end
    end

    widget.SetWidth = function(self, width)
        if width and width > 0 then
            self.frame:SetWidth(width)
        end
    end

    widget.GetWidth = function(self)
        -- Return the host frame's actual visual canvas layout width parameters
        return self.frame:GetWidth() or 320
    end

    widget.GetHeight = function(self)
        -- Return the host frame's actual dynamic multi-row height boundaries
        return self.frame:GetHeight() or (BOX_SIZE + 4)
    end

    widget.SetCallback = function(self, name, func)
        -- Initialize our local event tracking dictionary if it doesn't exist yet
        if not self.eventsTableMatrix then self.eventsTableMatrix = {} end
        self.eventsTableMatrix[name] = func
    end

    widget.Fire = function(self, name, ...)
        if self.eventsTableMatrix and self.eventsTableMatrix[name] then
            self.eventsTableMatrix[name](self, name, ...)
        end
    end

    widget.GetText = function(self)
        return ""
    end

    widget.GetValue = function(self)
        return ""
    end

    widget.GetLabel = function(self)
        return ""
    end

    widget.SetText = function(self, value)
        -- FIX 2: Capture the row's true identity key directly from the value argument
        if type(value) == "string" and value ~= "" then
            self.category = value
        end

        local arg = self.arg
        if not arg and ns.DialogOptions and self.category then
            local buffsTab = ns.DialogOptions.args and ns.DialogOptions.args.buffsTab
            local buffArgs = buffsTab and buffsTab.args
            if buffArgs then
                -- Match directly against the precise group key container
                local targetingGroupKey = self.category .. "Group"
                local targetGroup = buffArgs[targetingGroupKey]
                if targetGroup and type(targetGroup.args) == "table" and targetGroup.args.gridCanvasSlot then
                    arg = targetGroup.args.gridCanvasSlot.arg
                end
            end
        end

        if arg then
            self.arg = arg
            self.category = arg.category or self.category
            self.categoryTitle = arg.categoryTitle or self.categoryTitle
            -- Force the reference down onto the physical container frame for subButtonSlot usage
            self.frame.arg = arg
        end

        if self.arg and self.arg.mode == "learningControl" then
            ns.BuffLearningWidgets[self] = true
            if self.slotsMatrixPool then
                for _, btnSlot in ipairs(self.slotsMatrixPool) do
                    btnSlot.frame:Hide()
                end
            end
            self.frame:SetHeight(28)
            RefreshLearningButton(self)
            return
        end

        ns.BuffLearningWidgets[self] = nil

        if self.learningButton then
            self.learningButton:Hide()
        end
        local maxSlotsCount = self.arg and tonumber(self.arg.slots) or 5
        local itemsPerRow = 5
        local rowsNeeded = math.ceil(maxSlotsCount / itemsPerRow)
        local totalCanvasHeight = (rowsNeeded * (BOX_SIZE + 4)) + ((rowsNeeded - 1) * 8)
        self.frame:SetHeight(totalCanvasHeight)

        if not self.slotsMatrixPool then self.slotsMatrixPool = {} end

        for i = 1, maxSlotsCount do
            if not self.slotsMatrixPool[i] then
                self.slotsMatrixPool[i] = ns.CreateSubButtonSlot(self.frame, i)
            end

            local btnSlot = self.slotsMatrixPool[i]
            btnSlot.frame:Show()

            local col = (i - 1) % itemsPerRow
            local row = math.floor((i - 1) / itemsPerRow)

            local posX = col * (BOX_SIZE + 4 + 8)
            local posY = -(row * (BOX_SIZE + 4 + 8))

            btnSlot.frame:ClearAllPoints()
            btnSlot.frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", posX, posY)

            -- Only load states if our isolated data link has successfully bound
            if self.frame.arg then
                btnSlot:LoadSavedState()
            end
        end

        for i = maxSlotsCount + 1, #self.slotsMatrixPool do
            self.slotsMatrixPool[i].frame:Hide()
        end
    end

    widget.SetValue = function(self, value)
        self:SetText(tostring(value or ""))
    end

    widget.SetDisabled = function(self, disabled)
        self.disabled = disabled
        if self.slotsMatrixPool then
            for _, btnSlot in ipairs(self.slotsMatrixPool) do
                if btnSlot.box then
                    if disabled then
                        btnSlot.box:Disable()
                        btnSlot.checkbox:Disable()
                        btnSlot.box:SetAlpha(0.35)
                    else
                        btnSlot.box:Enable()
                        btnSlot.checkbox:Enable()
                        btnSlot.box:SetAlpha(1.0)
                    end
                end
            end
        end
    end

    widget.SetUserData = function(self, key, value)
        self.userdata[key] = value
    end

    widget.GetUserData = function(self, key)
        return self.userdata[key]
    end

    -- AceConfigDialog forwards option.arg here via InjectInfo; this is the real bind point
    -- for our category/slot data (SetText only ever receives the literal "name" string).
    widget.SetCustomData = function(self, data)
        if type(data) == "table" then
            self.arg = data
            self.category = data.category or self.category
            self.categoryTitle = data.categoryTitle or self.categoryTitle
            self.frame.arg = data
            if not self.userdata then self.userdata = {} end
            self.userdata.category = self.category
            self:SetText(self.category or "")
        elseif type(data) == "string" and data ~= "" then
            self.category = data
            if not self.userdata then self.userdata = {} end
            self.userdata.category = data
        end
    end

    widget.SetDescription = function(self, text) end
    widget.SetLabel = function(self, text) end
    widget.SetList = function(self, list) self.availableOptionsList = list end
    widget.SetHelptext = function(self, text) end
    widget.SetMultiselect = function(self, value) end
    widget.SetItemValue = function(self, item, value) end
    widget.RefreshLearningButton = RefreshLearningButton

    -- FIX: Clean registration sequence with zero debugging proxy wrapper overhead
    frame.obj = widget
    AceGUI:RegisterAsWidget(widget)
    return widget
end

function ns.RefreshBuffLearningWidgets()
    for widget in pairs(ns.BuffLearningWidgets) do
        if widget.frame and widget.frame:IsShown() and type(widget.RefreshLearningButton) == "function" then
            widget:RefreshLearningButton()
        end
    end
end

AceGUI:RegisterWidgetType(WIDGET_NAME, CreateBuffItemWidget, WIDGET_VERSION)
