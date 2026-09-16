local addonName, ns = ...
local Addon = ns.Addon

local logViewer

local function GetLogText()
    return table.concat(Addon:GetLogDB(), "\n")
end

local function RefreshLogViewer()
    if not logViewer or not logViewer.editBox then
        return
    end

    logViewer.editBox:SetText(GetLogText())
    logViewer.editBox:HighlightText()
end

local function CreateLogViewer()
    local frame = CreateFrame("Frame", "DreamFishLogViewer", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(720, 520)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", RefreshLogViewer)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText(addonName .. " Log")

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 18, -32)
    hint:SetText("Select the log text, then copy it with your usual keyboard shortcut.")

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18, -54)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 52)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetTextInsets(6, 6, 6, 6)
    editBox:SetWidth(650)
    editBox:SetHeight(400)
    editBox:SetTextColor(1, 1, 1)
    editBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    scrollFrame:SetScrollChild(editBox)

    local selectButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectButton:SetSize(100, 22)
    selectButton:SetPoint("BOTTOMLEFT", 18, 18)
    selectButton:SetText("Select All")
    selectButton:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(100, 22)
    closeButton:SetPoint("BOTTOMRIGHT", -18, 18)
    closeButton:SetText(CLOSE)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame.editBox = editBox
    return frame
end

function Addon:OpenLogViewer()
    logViewer = logViewer or CreateLogViewer()
    logViewer:Show()
    RefreshLogViewer()
end

function Addon:RefreshLogViewer()
    RefreshLogViewer()
end