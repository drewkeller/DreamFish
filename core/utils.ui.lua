local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

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

function DreamFish:SaveDialogPosition(frame, windowName)
    local dialogFrame = GetDialogFrame(frame)
    if not dialogFrame then return end

    -- Ensure the global tracking tables exist inside your FishingDB
    local globalDB = DreamFish and DreamFish.db and DreamFish.db.global
    if globalDB then
        globalDB.windowPositions = globalDB.windowPositions or {}

        local status = GetDialogStatusTable(windowName)
        local width = status and status.width or dialogFrame:GetWidth()
        local height = status and status.height or dialogFrame:GetHeight()
        local top = status and status.top or dialogFrame:GetTop()
        local left = status and status.left or dialogFrame:GetLeft()

        if not IsDialogPositionVisible(top, left, width, height) then
            DreamFish:Debug("Skipped saving off-screen position for window " .. windowName .. ".")
            return
        end

        if status then
            status.width = width
            status.height = height
            status.top = top
            status.left = left
        end

        -- Pull current coordinates relative to the master UI screen overlay parent
        globalDB.windowPositions[windowName] = {
            width = math.floor((width or 700) + 0.5),
            height = math.floor((height or 500) + 0.5),
            top = math.floor(top + 0.5),
            left = math.floor(left + 0.5),
        }
        DreamFish:Debug("Saved window " .. windowName .. " to positions database.")
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
        DreamFish:Debug("Restored window " .. windowName .. " from positions database.")
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

    if dialogFrame then
        -- 4. Restore again for old point-based saved positions and then persist AceGUI status on close.
        self:RestoreDialogPosition(dialogFrame, windowName)

        if not dialogFrame.DreamFishPositionHooked then
            dialogFrame:HookScript("OnHide", function()
                DreamFish:SaveDialogPosition(dialogFrame, windowName)
            end)
            dialogFrame.DreamFishPositionHooked = true
        end
    end

    return dialog
end
