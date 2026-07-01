-- DreamFisher Ace widget factory helpers
-- Builds simple adapters used by config UI tab builders.

local addonName = "DreamFisher"
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
            self:RefreshOptions()
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

    return {
        Checkbox = CreateAceCheckbox,
        EditBox = CreateAceEditBox,
        Title = CreateAceTitle,
        StaticTitle = CreateAceTitle,
        ToySelector = CreateAceToySelector,
        Note = CreateAceNote,
    }
end
