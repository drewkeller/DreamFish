local addonName, ns = ...
local Addon = ns.Addon
local Utils = ns.Utils

Addon:RegisterTraceSource("utils.ui")

local function Trace(windowName, msg)
    Addon:TraceCore("utils.ui", tostring(windowName) .. ": " .. tostring(msg))
end

local function GetDialogFrame(dialog)
    return dialog and (dialog.frame or dialog) or nil
end

local function GetDialogStatusTable(windowName)
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    if not AceConfigDialog or type(AceConfigDialog.GetStatusTable) ~= "function" then
        return nil
    end

    return AceConfigDialog:GetStatusTable(windowName)
end

local function CopyTable(source)
    if type(source) ~= "table" then
        return source
    end

    local copy = {}
    for key, value in pairs(source) do
        copy[key] = CopyTable(value)
    end
    return copy
end

function Addon:SaveConfigSelection(windowName)
    local globalDB = self.db and self.db.global
    local status = GetDialogStatusTable(windowName)
    if not (globalDB and status and status.groups) then
        return
    end

    globalDB.configSelections = globalDB.configSelections or {}
    globalDB.configSelections[windowName] = CopyTable(status.groups)
end

function Addon:RestoreConfigSelection(windowName)
    local globalDB = self.db and self.db.global
    local savedGroups = globalDB and globalDB.configSelections and globalDB.configSelections[windowName]
    local status = GetDialogStatusTable(windowName)
    if savedGroups and status then
        status.groups = CopyTable(savedGroups)
    end
end

function Addon:RememberMainConfigCategory(appName)
    local globalDB = self.db and self.db.global
    if globalDB then
        globalDB.lastMainConfigCategory = appName
    end
    self:SaveConfigSelection(appName)
end

function Addon:OpenMainConfig()
    local categoryMap = self.mainConfigCategoryIDs or {}
    for appName in pairs(categoryMap) do
        self:RestoreConfigSelection(appName)
    end

    local globalDB = self.db and self.db.global
    local lastCategory = globalDB and globalDB.lastMainConfigCategory
    local categoryID = categoryMap[lastCategory] or self.optionsCategoryID
        or (self.optionsFrame and self.optionsFrame.name) or addonName
    Settings.OpenToCategory(categoryID)
end

local function IsDialogPositionVisible(top, left, width, height)
    top = tonumber(top)
    left = tonumber(left)
    width = tonumber(width) or 700
    height = tonumber(height) or 500

    if not top or not left then
        return false
    end

    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    local screenHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if not screenWidth or not screenHeight then
        return true
    end

    local minVisible = 80
    local right = left + width
    local bottom = top - height

    return right > minVisible
        and left < screenWidth - minVisible
        and top > minVisible
        and bottom < screenHeight - minVisible
end

local function ClearDialogStatusPosition(status)
    if not status then
        return
    end

    status.top = nil
    status.left = nil
end

local function AddMainConfigButton(windowName, dialogFrame)
    if windowName ~= "DreamFishDialog" then
        return
    end

    if dialogFrame.DreamFishMainConfigButton then
        dialogFrame.DreamFishMainConfigButton:Show()
        if dialogFrame.DreamFishReloadUIButton then
            dialogFrame.DreamFishReloadUIButton:Show()
        end
        return
    end

    local closeButton
    for _, child in ipairs({ dialogFrame:GetChildren() }) do
        if child.GetText and child:GetText() == CLOSE then
            closeButton = child
            break
        end
    end

    local button = CreateFrame("Button", nil, dialogFrame, "UIPanelButtonTemplate")
    local elvUI = _G.ElvUI
    local elvUIEngine = elvUI and elvUI[1]
    local skins = elvUIEngine and elvUIEngine.GetModule and elvUIEngine:GetModule("Skins", true)
    if skins and skins.HandleButton then
        skins:HandleButton(button)
    end
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", 27, 17)
    button:SetSize(100, 20)
    button:SetFrameLevel(dialogFrame:GetFrameLevel() + 10)
    button:SetText("Main Config")
    button:SetScript("OnClick", function()
        Addon:OpenMainConfig()
        C_Timer.After(0.01, function()
            Addon:OpenDialogWindow(windowName)
        end)
    end)
    dialogFrame.DreamFishMainConfigButton = button

    -- For development
    if Addon.db.profile.debugEnabled then
        local reloadButton = CreateFrame("Button", nil, dialogFrame, "UIPanelButtonTemplate")
        if skins and skins.HandleButton then
            skins:HandleButton(reloadButton)
        end
        reloadButton:ClearAllPoints()
        reloadButton:SetPoint("BOTTOMLEFT", 140, 17)
        reloadButton:SetSize(100, 20)
        reloadButton:SetFrameLevel(dialogFrame:GetFrameLevel() + 10)
        reloadButton:SetText("Reload UI")
        reloadButton:SetScript("OnClick", function()
            ReloadUI()
        end)
        dialogFrame.DreamFishReloadUIButton = reloadButton
    end

    if closeButton then
        closeButton:ClearAllPoints()
        closeButton:SetPoint("BOTTOMRIGHT", -27, 17)
    end
end

function Addon:SaveDialogFrameCoordinates(windowName, dialogFrame)
    local globalDB = Addon and Addon.db and Addon.db.global
    if globalDB and dialogFrame then
        globalDB.windowPositions = globalDB.windowPositions or {}
        local status = GetDialogStatusTable(windowName)
        local width = status and status.width or dialogFrame:GetWidth()
        local height = status and status.height or dialogFrame:GetHeight()
        local top = (status and status.top) or dialogFrame:GetTop()
        local left = (status and status.left) or dialogFrame:GetLeft()

        -- Frame may not yet be positioned (e.g. still centering); skip saving until it is.
        if not top or not left then
            return
        end

        globalDB.windowPositions[windowName] = {
            width = math.floor((width or 400) + 0.5),
            height = math.floor((height or 700) + 0.5),
            top = math.floor(top + 0.5),
            left = math.floor(left + 0.5),
        }
        --Trace(windowName, "Saved window coordinates to positions database.")
    end
end

function Addon:RestoreDialogPosition(frame, windowName)
    local dialogFrame = GetDialogFrame(frame)

    local globalDB = Addon and Addon.db and Addon.db.global
    if globalDB and globalDB.windowPositions and globalDB.windowPositions[windowName] then
        local saved = globalDB.windowPositions[windowName]
        local status = GetDialogStatusTable(windowName)
        local savedTop = tonumber(saved.top)
        local savedLeft = tonumber(saved.left)
        local savedWidth = tonumber(saved.width)
        local savedHeight = tonumber(saved.height)
        local hasVisibleStatus = IsDialogPositionVisible(savedTop, savedLeft, savedWidth, savedHeight)

        if status then
            status.width = savedWidth or status.width
            status.height = savedHeight or status.height
            if hasVisibleStatus then
                status.top = savedTop
                status.left = savedLeft
            else
                ClearDialogStatusPosition(status)
            end
        end

        if not dialogFrame then
            return
        end

        dialogFrame:ClearAllPoints()
        if hasVisibleStatus then
            dialogFrame:SetPoint("TOP", UIParent, "BOTTOM", 0, savedTop)
            dialogFrame:SetPoint("LEFT", UIParent, "LEFT", savedLeft, 0)
        else
            dialogFrame:SetPoint(
                saved.point or "CENTER",
                UIParent,
                saved.relativePoint or "CENTER",
                saved.x or 0,
                saved.y or 0
            )
        end
        Trace(windowName, "Restored window from positions database.")
    elseif dialogFrame then
        -- Fallback default position if no coordinate footprint exists yet
        dialogFrame:ClearAllPoints()
        dialogFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function Addon:SetDefaultPosition(windowName, left, top)
    local globalDB = Addon and Addon.db and Addon.db.global
    if globalDB then
        globalDB.windowPositions = globalDB.windowPositions or {}
        globalDB.windowPositions[windowName] = globalDB.windowPositions[windowName] or {}
        if globalDB.windowPositions[windowName].left == nil and globalDB.windowPositions[windowName].top == nil then
            globalDB.windowPositions[windowName].left = left
            globalDB.windowPositions[windowName].top = top
        end
    end
end

function Addon:OpenDialogWindow(windowName, tabOrGroupName)
    -- 1. Tell AceConfigRegistry to refresh data variables across fields
    LibStub("AceConfigRegistry-3.0"):NotifyChange(windowName)

    local AceConfigDialog = LibStub("AceConfigDialog-3.0")

    -- 2. Prime AceGUI's status table before opening so it does not center the frame.
    self:RestoreDialogPosition(nil, windowName)
    self:RestoreConfigSelection(windowName)

    -- 3. Open the window frame and capture its AceGUI widget from AceConfigDialog's registry.
    AceConfigDialog:Open(windowName, tabOrGroupName)
    local dialog = AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames[windowName]
    local dialogFrame = GetDialogFrame(dialog)
    Trace(windowName, "OpenDialogWindow")

    if windowName == "DreamFishDialog" and ns.Fishing and ns.Fishing.RefreshDreamFishDialogFade then
        ns.Fishing:RefreshDreamFishDialogFade()
    end

    if dialogFrame and dialog then
        -- 4. Restore again for old point-based saved positions and then persist AceGUI status on close.
        self:RestoreDialogPosition(dialogFrame, windowName)
        AddMainConfigButton(windowName, dialogFrame)

        if dialogFrame.frame then
            dialogFrame.frame:SetFrameStrata("BACKGROUND")
            dialogFrame.frame:SetFrameLevel(1)
            Trace(windowName, "(1) Set frame strata to BACKGROUND and level to 1")
        else
            dialogFrame:SetFrameStrata("BACKGROUND")
            dialogFrame:SetFrameLevel(1)
            Trace(windowName, "(2) Set frame strata to BACKGROUND and level to 1")
        end

        -- Intercept various events
        if dialogFrame.DreamFishPositionHooked then
            Trace(windowName, "Dialog frame events already hooked, skipping.")
        else
            Trace(windowName, "Hooking dialog frame events")
            dialogFrame.DreamFishPositionHooked = true

            -- Hook the standard close event
            dialogFrame:HookScript("OnHide", function()
                if dialogFrame.DreamFishMainConfigButton then
                    dialogFrame.DreamFishMainConfigButton:Hide()
                end
                if dialogFrame.DreamFishReloadUIButton then
                    dialogFrame.DreamFishReloadUIButton:Hide()
                end
                Addon:SaveDialogFrameCoordinates(windowName, dialogFrame)
                Addon:SaveConfigSelection(windowName)
            end)

            -- Allow dragging from empty areas of the dialog, not only the title.
            dialogFrame:HookScript("OnMouseDown", function(self, button)
                if button == "LeftButton" then
                    self:StartMoving()
                end
            end)

            dialogFrame:HookScript("OnMouseUp", function(self, button)
                if button == "LeftButton" then
                    self:StopMovingOrSizing()
                    Addon:SaveDialogFrameCoordinates(windowName, self)
                end
            end)

            -- Monitor window movement and scaling
            dialogFrame:HookScript("OnSizeChanged", function()
                --Trace(windowName, "OnSizeChanged")
                Addon:SaveDialogFrameCoordinates(windowName, dialogFrame)
            end)

            -- Monitor hardware tracking loops using a safe gate to capture moving offsets instantly
            local lastLeft, lastTop = dialogFrame:GetLeft(), dialogFrame:GetTop()

            dialogFrame:HookScript("OnUpdate", function(self)
                local currentLeft = self:GetLeft()
                local currentTop = self:GetTop()

                -- If coordinates changed, the player is dragging or scaling the frame right now
                if currentLeft ~= lastLeft or currentTop ~= lastTop then
                    lastLeft = currentLeft
                    lastTop = currentTop

                    Addon:SaveDialogFrameCoordinates(windowName, dialogFrame)
                end
            end)

            -- Hook the resizer frame components if they exist for scaling safety
            if dialog.resizer then
                dialog.resizer:HookScript("OnMouseUp", function()
                    --TraceUi(windowName, "OnMouseUp resizer")
                    Addon:SaveDialogFrameCoordinates(windowName, dialogFrame)
                end)
            end
        end
    end

    return dialog
end

function Addon:OpenDialogToTab(windowName, tabName)
    local ACD = LibStub("AceConfigDialog-3.0")
    local statusTable = ACD:GetStatusTable(windowName)
    if statusTable then
        statusTable.groups = statusTable.groups or {}
        statusTable.groups.selected = tabName
    end
    ACD:Open(windowName)
end
