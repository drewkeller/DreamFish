local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

DreamFish:RegisterTraceSource("utils.ui")

local function TraceUi(windowName, msg)
    DreamFish:Trace("utils.ui", tostring(windowName) .. ": " .. tostring(msg))
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

function DreamFish:SaveDialogFrameCoordinates(windowName, dialogFrame)
    local globalDB = DreamFish and DreamFish.db and DreamFish.db.global
    if globalDB and dialogFrame then
        globalDB.windowPositions = globalDB.windowPositions or {}
        local width = dialogFrame:GetWidth()
        local height = dialogFrame:GetHeight()
        local top = dialogFrame:GetTop()
        local left = dialogFrame:GetLeft()
        globalDB.windowPositions[windowName] = {
            width = math.floor((width or 700) + 0.5),
            height = math.floor((height or 500) + 0.5),
            top = math.floor(top + 0.5),
            left = math.floor(left + 0.5),
        }
        --TraceUi(windowName, "Saved window coordinates to positions database.")
    end
end

function DreamFish:RestoreDialogPosition(frame, windowName)
    local dialogFrame = GetDialogFrame(frame)

    local globalDB = DreamFish and DreamFish.db and DreamFish.db.global
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
        TraceUi(windowName, "Restored window from positions database.")
    elseif dialogFrame then
        -- Fallback default position if no coordinate footprint exists yet
        dialogFrame:ClearAllPoints()
        dialogFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function DreamFish:OpenDialogWindow(windowName)
    -- 1. Tell AceConfigRegistry to refresh data variables across fields
    LibStub("AceConfigRegistry-3.0"):NotifyChange(windowName)

    local AceConfigDialog = LibStub("AceConfigDialog-3.0")

    -- 2. Prime AceGUI's status table before opening so it does not center the frame.
    self:RestoreDialogPosition(nil, windowName)

    -- 3. Open the window frame and capture its AceGUI widget from AceConfigDialog's registry.
    AceConfigDialog:Open(windowName)
    local dialog = AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames[windowName]
    local dialogFrame = GetDialogFrame(dialog)
    TraceUi(windowName, "OpenDialogWindow")

    if dialogFrame and dialog then
        -- 4. Restore again for old point-based saved positions and then persist AceGUI status on close.
        self:RestoreDialogPosition(dialogFrame, windowName)

        -- Intercept various events
        if dialogFrame.DreamFishPositionHooked then
            TraceUi(windowName, "Dialog frame events already hooked, skipping.")
        else
            TraceUi(windowName, "Hooking dialog frame events")
            dialogFrame.DreamFishPositionHooked = true

            -- Hook the standard close event
            dialogFrame:HookScript("OnHide", function()
                DreamFish:SaveDialogFrameCoordinates(windowName, dialogFrame)
            end)

            -- Monitor window movement and scaling
            dialogFrame:HookScript("OnSizeChanged", function()
                --TraceUi(windowName, "OnSizeChanged")
                DreamFish:SaveDialogFrameCoordinates(windowName, dialogFrame)
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

                    DreamFish:SaveDialogFrameCoordinates(windowName, dialogFrame)
                end
            end)

            -- Hook the resizer frame components if they exist for scaling safety
            if dialog.resizer then
                dialog.resizer:HookScript("OnMouseUp", function()
                    --TraceUi(windowName, "OnMouseUp resizer")
                    DreamFish:SaveDialogFrameCoordinates(windowName, dialogFrame)
                end)
            end
        end
    end

    return dialog
end
