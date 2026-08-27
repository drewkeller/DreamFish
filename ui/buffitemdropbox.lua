local addonName, ns = ...
local Addon = ns.Addon
local Fishing = Addon:GetModule("Fishing")
local AceGUI = LibStub("AceGUI-3.0")

Addon:RegisterTraceSource("buffitemdropbox")

local WIDGET_NAME = "DreamFishBuffItemDropBox"
local WIDGET_VERSION = 1
local BOX_SIZE = 48

-- Global or namespace reference tracking the current drag state
Fishing.state = Fishing.state or {}
Fishing.state.uiBuffCursorDragState = Fishing.state.uiBuffCursorDragState or nil
Fishing.state.buffItemLastKnownCount = Fishing.state.buffItemLastKnownCount or {}
Fishing.state.buffItemLastUseAt = Fishing.state.buffItemLastUseAt or {}

local function Trace(msg)
    ns.Utils("buffitemdropbox", msg)
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

    -- FIX: Clean registration sequence with zero debugging proxy wrapper overhead
    frame.obj = widget
    AceGUI:RegisterAsWidget(widget)
    return widget
end

AceGUI:RegisterWidgetType(WIDGET_NAME, CreateBuffItemWidget, WIDGET_VERSION)
