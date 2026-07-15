-- DreamFish Ace widget factory helpers
-- Builds simple adapters used by config UI tab builders.

local addonName = "DreamFish"
local addon = _G[addonName]

addon.ui = addon.ui or {}

function addon.ui.CreateAceWidgetAdapters(aceGUIInstance, panel)
    if not aceGUIInstance or not panel then
        return nil
    end

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

    local function RegisterAndAttachChild(container, widget)
        if container and container.AddChild then
            container:AddChild(widget)
        end
        return RegisterAceWidget(widget)
    end

    local function AttachTooltip(frame, title, text)
        if not frame or type(frame.HookScript) ~= "function" then
            return
        end
        if type(text) ~= "string" or text == "" then
            return
        end

        frame:HookScript("OnEnter", function(self)
            if type(GameTooltip) ~= "table" then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if type(title) == "string" and title ~= "" then
                GameTooltip:SetText(title, 1, 0.82, 0)
                GameTooltip:AddLine(text, 1, 1, 1, true)
            else
                GameTooltip:SetText(text, 1, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)

        frame:HookScript("OnLeave", function()
            if type(GameTooltip) == "table" then
                GameTooltip:Hide()
            end
        end)
    end

    local function AttachTooltipToDropdownWidget(widget, title, text)
        if not widget then
            return
        end

        AttachTooltip(widget.frame, title, text)
    end

    local function CreateAceFlowRoot(parent, inset)
        local padding = tonumber(inset) or 12
        local group = aceGUIInstance:Create("SimpleGroup")
        group:SetLayout("List")
        group:SetFullWidth(true)
        group:SetFullHeight(true)
        group.frame:SetParent(parent)
        group.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", padding, -padding)
        group.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -padding, padding)
        group.frame:Show()
        return RegisterAceWidget(group)
    end

    local function CreateAceFlowSection(parent, title, layout)
        local section = aceGUIInstance:Create("InlineGroup")
        section:SetTitle(title or "")
        section:SetLayout(layout or "List")
        section:SetFullWidth(true)
        return RegisterAndAttachChild(parent, section)
    end

    local function CreateAceFlowCheckbox(parent, label, onLiveChange, tooltipText)
        local widget = aceGUIInstance:Create("CheckBox")
        widget:SetType("checkbox")
        widget:SetLabel(label)
        widget:SetFullWidth(true)
        if onLiveChange then
            widget:SetCallback("OnValueChanged", function()
                onLiveChange()
            end)
        end
        widget = RegisterAndAttachChild(parent, widget)
        AttachTooltip(widget.frame, label, tooltipText)

        return {
            SetChecked = function(_, value)
                widget:SetValue(value and true or false)
            end,
            GetChecked = function()
                return widget:GetValue() and true or false
            end,
            SetDisabled = function(_, disabled)
                if widget and widget.SetDisabled then
                    widget:SetDisabled(disabled and true or false)
                end
            end,
            SetCallback = function(_, eventName, callback)
                if widget and widget.SetCallback then
                    widget:SetCallback(eventName, callback)
                end
            end,
        }
    end

    local function CreateAceFlowEditBox(parent, label, width, onLiveChange, tooltipText)
        local widget = aceGUIInstance:Create("EditBox")
        widget:SetLabel(label)
        widget:DisableButton(true)
        if width then
            widget:SetWidth(width)
        else
            widget:SetFullWidth(true)
        end
        if onLiveChange then
            widget:SetCallback("OnTextChanged", function()
                onLiveChange()
            end)
            widget:SetCallback("OnEnterPressed", function()
                onLiveChange()
            end)
        end
        widget = RegisterAndAttachChild(parent, widget)
        AttachTooltip(widget.frame, label, tooltipText)

        return {
            SetText = function(_, value)
                widget:SetText(tostring(value or ""))
            end,
            GetText = function()
                return widget:GetText() or ""
            end,
            SetDisabled = function(_, disabled)
                if widget and widget.SetDisabled then
                    widget:SetDisabled(disabled and true or false)
                end
            end,
        }
    end

    local function CreateAceFlowSlider(parent, label, width, minValue, maxValue, stepValue, onLiveChange, tooltipText)
        local widget = aceGUIInstance:Create("Slider")
        widget:SetLabel(label)
        widget:SetSliderValues(tonumber(minValue) or 0, tonumber(maxValue) or 100, tonumber(stepValue) or 1)
        if width then
            widget:SetWidth(width)
        else
            widget:SetFullWidth(true)
        end
        if onLiveChange then
            widget:SetCallback("OnValueChanged", function()
                onLiveChange()
            end)
        end
        widget = RegisterAndAttachChild(parent, widget)
        AttachTooltip(widget.frame, label, tooltipText)

        return {
            SetText = function(_, value)
                widget:SetValue(tonumber(value) or 0)
            end,
            GetText = function()
                return tostring(widget:GetValue() or "")
            end,
            SetDisabled = function(_, disabled)
                if widget and widget.SetDisabled then
                    widget:SetDisabled(disabled and true or false)
                end
            end,
        }
    end

    local function CreateAceFlowTitle(parent, text)
        local widget = aceGUIInstance:Create("Label")
        widget:SetText(text)
        widget:SetFullWidth(true)
        return RegisterAndAttachChild(parent, widget)
    end

    local function CreateAceFlowNote(parent, text)
        local widget = aceGUIInstance:Create("Label")
        widget:SetText(text)
        widget:SetFullWidth(true)
        return RegisterAndAttachChild(parent, widget)
    end

    local function CreateAceFlowColumns(parent, columnCount)
        local columns = {}
        local count = tonumber(columnCount) or 2
        if count < 1 then
            count = 1
        end

        local row = aceGUIInstance:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        row = RegisterAndAttachChild(parent, row)

        local width = 1 / count
        for _ = 1, count do
            local col = aceGUIInstance:Create("SimpleGroup")
            col:SetLayout("List")
            col:SetRelativeWidth(width)
            col = RegisterAndAttachChild(row, col)
            table.insert(columns, col)
        end

        return columns
    end

    local function CreateAceFlowDropdown(parent, label, width, optionsGetter, onLiveChange, tooltipText)
        if label and label ~= "" then
            CreateAceFlowTitle(parent, label)
        end

        local dropdown = aceGUIInstance:Create("Dropdown")
        dropdown:SetFullWidth(true)
        if width then
            dropdown:SetWidth(width)
        end
        dropdown = RegisterAndAttachChild(parent, dropdown)
        AttachTooltipToDropdownWidget(dropdown, label, tooltipText)

        local selector = {
            options = {},
            selectedValue = nil,
            onValueChanged = onLiveChange,
            dropdown = dropdown,
        }

        function selector:RefreshOptions()
            self.options = optionsGetter and optionsGetter() or {}

            local list = {}
            local order = {}
            for _, option in ipairs(self.options) do
                list[option.value] = option.label or tostring(option.value)
                table.insert(order, option.value)
            end
            dropdown:SetList(list, order)

            if #self.options == 0 then
                self.selectedValue = nil
                dropdown:SetValue(nil)
                return
            end

            local desired = self.selectedValue
            local found = false
            for _, option in ipairs(self.options) do
                if option.value == desired then
                    found = true
                    break
                end
            end

            if not found then
                self.selectedValue = self.options[1].value
            end

            dropdown:SetValue(self.selectedValue)
        end

        function selector:SetText(value)
            if value == nil or value == "" then
                self.selectedValue = nil
            else
                self.selectedValue = value
            end
            if not self.options or #self.options == 0 then
                self:RefreshOptions()
                return
            end
            dropdown:SetValue(self.selectedValue)
        end

        function selector:GetText()
            if self.selectedValue == nil then
                return ""
            end
            return tostring(self.selectedValue)
        end

        function selector:SetEnabled(enabled)
            if dropdown and dropdown.SetDisabled then
                dropdown:SetDisabled(not enabled)
            end
        end

        dropdown:SetCallback("OnValueChanged", function(_, _, value)
            selector.selectedValue = value
            if selector.onValueChanged then
                selector.onValueChanged(selector.selectedValue)
            end
        end)

        selector:RefreshOptions()
        return selector
    end

    local function CreateAceFlowToySelector(parent, label, width, optionsGetter, onLiveChange, tooltipText)
        CreateAceFlowTitle(parent, label)

        local dropdown = aceGUIInstance:Create("Dropdown")
        -- Use full-width in flow layouts so row packing is stable as controls are added.
        dropdown:SetFullWidth(true)
        if width then
            dropdown:SetWidth(width)
        end
        dropdown = RegisterAndAttachChild(parent, dropdown)
        AttachTooltipToDropdownWidget(dropdown, label, tooltipText)

        local selector = {
            options = {},
            selectedValue = nil,
            onValueChanged = onLiveChange,
            dropdown = dropdown,
        }

        function selector:RefreshOptions()
            self.options = optionsGetter and optionsGetter() or {}

            local list = {}
            local order = {}
            for _, option in ipairs(self.options) do
                list[option.value] = option.label or tostring(option.value)
                table.insert(order, option.value)
            end
            dropdown:SetList(list, order)

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
            if not self.options or #self.options == 0 then
                self:RefreshOptions()
                return
            end
            dropdown:SetValue(self.selectedValue)
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

    local function CreateAceFlowSecureToyActionButton(parent, width, text, tooltipText)
        local buttonHost = aceGUIInstance:Create("SimpleGroup")
        buttonHost:SetLayout("Fill")
        buttonHost:SetFullWidth(true)
        buttonHost:SetHeight(28)
        buttonHost = RegisterAndAttachChild(parent, buttonHost)

        local buttonParent = buttonHost.content or buttonHost.frame
        local button = CreateFrame("Button", nil, buttonParent, "UIPanelButtonTemplate,SecureActionButtonTemplate")
        button:SetSize(width or 160, 22)
        button:SetPoint("LEFT", buttonParent, "LEFT", 0, 0)
        button:SetText(text)
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("type", "toy")
        button:SetAttribute("toy", nil)
        AttachTooltip(button, text, tooltipText)
        return button
    end

    local function AttachTooltipToKeybindingWidget(widget, title, text)
        if not widget then
            return
        end

        AttachTooltip(widget.frame, title, text)

        local root = nil
        if widget.frame and widget.frame.obj then
            root = widget.frame.obj
        else
            root = widget
        end

        if root.button then
            AttachTooltip(root.button, title, text)
        end
    end

    local function CreateAceFlowKeybinding(parent, label, width, onLiveChange, tooltipText)
        local widget = aceGUIInstance:Create("Keybinding")
        widget:SetLabel(label or "")
        if width then
            widget:SetWidth(width)
        else
            widget:SetFullWidth(true)
        end

        if onLiveChange then
            widget:SetCallback("OnKeyChanged", function(_, _, value)
                onLiveChange(value)
            end)
        end

        widget = RegisterAndAttachChild(parent, widget)
        AttachTooltipToKeybindingWidget(widget, label, tooltipText)

        return {
            SetText = function(_, value)
                widget:SetKey((type(value) == "string" and value) or "")
            end,
            GetText = function()
                return widget:GetKey() or ""
            end,
            SetEnabled = function(_, enabled)
                widget:SetDisabled(not enabled)
            end,
            SetLabel = function(_, value)
                widget:SetLabel(tostring(value or ""))
            end,
        }
    end

    local function CreateAceFlowRowHost(parent, height)
        local rowHost = aceGUIInstance:Create("SimpleGroup")
        rowHost:SetLayout("Fill")
        rowHost:SetFullWidth(true)
        rowHost:SetHeight(height or 96)
        rowHost = RegisterAndAttachChild(parent, rowHost)
        return rowHost.content or rowHost.frame
    end

    local function CreateAceFlowCheckboxWithNote(parent, label, noteText, onLiveChange, noteOptions, tooltipText)
        local checkboxControl = CreateAceFlowCheckbox(parent, label, onLiveChange, tooltipText)

        local opts = noteOptions or {}
        local fixedHeight = tonumber(opts.noteHeight)
        local minHeight = tonumber(opts.minHeight) or 1
        local leftIndent = tonumber(opts.leftIndent) or 20
        local rightInset = tonumber(opts.rightInset) or 8
        local topInset = tonumber(opts.topInset) or 2
        local bottomInset = tonumber(opts.bottomInset) or 3
        local fontObject = opts.fontObject or "GameFontHighlightSmall"

        local noteHostWidget = aceGUIInstance:Create("SimpleGroup")
        noteHostWidget:SetLayout("Fill")
        noteHostWidget:SetFullWidth(true)
        noteHostWidget:SetHeight(fixedHeight or minHeight)
        noteHostWidget = RegisterAndAttachChild(parent, noteHostWidget)

        local noteHost = noteHostWidget.content or noteHostWidget.frame
        local note = noteHost:CreateFontString(nil, "OVERLAY", fontObject)
        note:SetPoint("TOPLEFT", noteHost, "TOPLEFT", leftIndent, -topInset)
        note:SetPoint("TOPRIGHT", noteHost, "TOPRIGHT", -rightInset, -topInset)
        note:SetJustifyH("LEFT")
        note:SetJustifyV("TOP")
        if note.SetWordWrap then
            note:SetWordWrap(true)
        end
        if note.SetNonSpaceWrap then
            note:SetNonSpaceWrap(true)
        end
        note:SetText(noteText or "")

        if not fixedHeight then
            local function UpdateNoteHeight()
                local textHeight = note:GetStringHeight() or 0
                local desiredHeight = math.max(minHeight, math.ceil(textHeight + topInset + bottomInset))
                if noteHostWidget.frame.height ~= desiredHeight then
                    noteHostWidget:SetHeight(desiredHeight)
                    if parent and parent.DoLayout then
                        parent:DoLayout()
                    end
                end
            end

            noteHost:SetScript("OnSizeChanged", UpdateNoteHeight)
            UpdateNoteHeight()
        end

        return checkboxControl
    end

    local function CreateAceCheckbox(parent, x, y, label, onLiveChange)
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

    local function CreateAceEditBox(parent, x, y, width, label, onLiveChange)
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

    local function CreateAceTitle(parent, x, y, text)
        local widget = aceGUIInstance:Create("Label")
        widget:SetText(text)
        return AnchorAceWidget(widget, parent, x, y)
    end

    local function CreateAceNote(parent, x, y, width, text)
        local widget = aceGUIInstance:Create("Label")
        widget:SetText(text)
        widget:SetWidth(width)
        return AnchorAceWidget(widget, parent, x, y)
    end

    local function CreateAceToySelector(parent, x, y, width, label, optionsGetter, onLiveChange)
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
            if not self.options or #self.options == 0 then
                self:RefreshOptions()
                return
            end
            dropdown:SetValue(self.selectedValue)
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

    local function CreateAceKeybinding(parent, x, y, width, label, onLiveChange, tooltipText)
        local widget = aceGUIInstance:Create("Keybinding")
        widget:SetLabel(label or "")
        widget:SetWidth(width or 220)
        if onLiveChange then
            widget:SetCallback("OnKeyChanged", function(_, _, value)
                onLiveChange(value)
            end)
        end

        widget = AnchorAceWidget(widget, parent, x, y)
        AttachTooltipToKeybindingWidget(widget, label, tooltipText)

        return {
            SetText = function(_, value)
                widget:SetKey((type(value) == "string" and value) or "")
            end,
            GetText = function()
                return widget:GetKey() or ""
            end,
            SetEnabled = function(_, enabled)
                widget:SetDisabled(not enabled)
            end,
            SetLabel = function(_, value)
                widget:SetLabel(tostring(value or ""))
            end,
        }
    end

    local function CreateAceFlowInsetHost(parent, leftInset)
        local host = aceGUIInstance:Create("SimpleGroup")
        host:SetLayout("List")
        host:SetFullWidth(true)
        host = RegisterAndAttachChild(parent, host)

        local inset = tonumber(leftInset) or 0
        if inset ~= 0 and host.content and host.frame then
            host.content:ClearAllPoints()
            host.content:SetPoint("TOPLEFT", host.frame, "TOPLEFT", inset, 0)
            host.content:SetPoint("BOTTOMRIGHT", host.frame, "BOTTOMRIGHT", 0, 0)
        end

        return host
    end

    return {
        Checkbox = CreateAceCheckbox,
        EditBox = CreateAceEditBox,
        Keybinding = CreateAceKeybinding,
        Title = CreateAceTitle,
        StaticTitle = CreateAceTitle,
        ToySelector = CreateAceToySelector,
        Note = CreateAceNote,
        FlowRoot = CreateAceFlowRoot,
        FlowSection = CreateAceFlowSection,
        FlowCheckbox = CreateAceFlowCheckbox,
        FlowEditBox = CreateAceFlowEditBox,
        FlowSlider = CreateAceFlowSlider,
        FlowTitle = CreateAceFlowTitle,
        FlowNote = CreateAceFlowNote,
        FlowColumns = CreateAceFlowColumns,
        FlowDropdown = CreateAceFlowDropdown,
        FlowToySelector = CreateAceFlowToySelector,
        FlowKeybinding = CreateAceFlowKeybinding,
        FlowSecureToyActionButton = CreateAceFlowSecureToyActionButton,
        FlowRowHost = CreateAceFlowRowHost,
        FlowCheckboxWithNote = CreateAceFlowCheckboxWithNote,
        FlowInsetHost = CreateAceFlowInsetHost,
    }
end
