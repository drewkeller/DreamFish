local addonName, ns = ...
local Addon = ns.Addon
local AceGUI = LibStub("AceGUI-3.0")

local WIDGET_NAME = "DreamFishLootTrackerPanel"
local WIDGET_VERSION = 1
local PANEL_HEIGHT = 320

local function CreateLootTrackerPanelWidget()
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(360, PANEL_HEIGHT)

    local widget = {
        frame    = frame,
        type     = WIDGET_NAME,
        userdata = {},
    }

    local scrollContainer = AceGUI:Create("ScrollFrame")
    scrollContainer:SetLayout("Flow")
    ---@diagnostic disable-next-line: invisible
    local scrollFrame = scrollContainer.frame
    scrollFrame:SetParent(frame)
    scrollFrame:Show()

    local resetButton = AceGUI:Create("Button")
    resetButton:SetText("Reset LootTracker")
    resetButton:SetWidth(240)
    resetButton:SetCallback("OnClick", function()
        local LootTracker = ns.LootTracker
        LootTracker.db.char.itemsLooted = 0
        LootTracker.db.char.lootedItems = {}
        LootTracker.db.char.lootedCurrencies = {}
        LootTracker:UpdateTrackerDisplay()
        print("|cFF00FF00[LootTracker]|r History track cleared.")
    end)

    ---@diagnostic disable-next-line: invisible
    local resetButtonFrame = resetButton.frame
    resetButtonFrame:SetParent(frame)
    resetButtonFrame:ClearAllPoints()
    resetButtonFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    resetButtonFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    resetButtonFrame:Show()

    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    scrollFrame:SetPoint("BOTTOMLEFT", resetButtonFrame, "TOPLEFT", 0, 8)
    scrollFrame:SetPoint("BOTTOMRIGHT", resetButtonFrame, "TOPRIGHT", 0, 8)

    -- ACEGUI LIFECYCLE INTERFACE REQUIRED IMPLEMENTATIONS
    widget.OnRelease = function(self)
        self.frame:Hide()
        ns.LootTracker:UnregisterPanelScrollContainer(scrollContainer)
    end

    widget.OnAcquire = function(self)
        self.frame:Show()
        ns.LootTracker:RegisterPanelScrollContainer(scrollContainer)
    end

    widget.SetHeight = function(self, height)
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
        return self.frame:GetWidth() or 360
    end

    widget.GetHeight = function(self)
        return self.frame:GetHeight() or PANEL_HEIGHT
    end

    widget.SetCallback = function(self, name, func)
        if not self.eventsTableMatrix then self.eventsTableMatrix = {} end
        self.eventsTableMatrix[name] = func
    end

    widget.Fire = function(self, name, ...)
        if self.eventsTableMatrix and self.eventsTableMatrix[name] then
            self.eventsTableMatrix[name](self, name, ...)
        end
    end

    widget.GetText = function(self) return "" end
    widget.GetValue = function(self) return "" end
    widget.GetLabel = function(self) return "" end
    widget.SetText = function(self, value) end
    widget.SetValue = function(self, value) end
    widget.SetDisabled = function(self, disabled) self.disabled = disabled end
    widget.SetUserData = function(self, key, value) self.userdata[key] = value end
    widget.GetUserData = function(self, key) return self.userdata[key] end
    widget.SetCustomData = function(self, data) end
    widget.SetDescription = function(self, text) end
    widget.SetLabel = function(self, text) end
    widget.SetList = function(self, list) end
    widget.SetHelptext = function(self, text) end
    widget.SetMultiselect = function(self, value) end
    widget.SetItemValue = function(self, item, value) end

    frame.obj = widget
    AceGUI:RegisterAsWidget(widget)
    widget.height = "fill" -- lets AceGUI's Flow layout stretch this control to the bottom of its tab
    return widget
end

AceGUI:RegisterWidgetType(WIDGET_NAME, CreateLootTrackerPanelWidget, WIDGET_VERSION)
