local addonName, ns = ...

ns.ui = ns.ui or {}

local WINDOW_WIDTH, WINDOW_HEIGHT = 550, 450
local TAB_HEIGHT = 24

local TackleWindow = {
    frame = nil,
    tabs = {},      -- ordered list of { id, title, build, button, content, built }
    tabsById = {},
    activeTabId = nil,
}

-- Register a tab. build(contentFrame) is called once, the first time the tab is shown.
-- opts: { id, title, order, build }
function TackleWindow:RegisterTab(opts)
    if not (opts and opts.id and opts.build) then return end
    if self.tabsById[opts.id] then return self.tabsById[opts.id] end

    local tab = {
        id = opts.id,
        title = opts.title or opts.id,
        order = opts.order or (#self.tabs + 1),
        build = opts.build,
        built = false,
    }
    self.tabsById[tab.id] = tab
    table.insert(self.tabs, tab)
    table.sort(self.tabs, function(a, b)
        if a.order == b.order then return a.title < b.title end
        return a.order < b.order
    end)

    if self.frame then
        self:RefreshTabs()
    end
    return tab
end

local function CreateWindowFrame()
    local window = CreateFrame("Frame", "DreamFishTackleWindow", UIParent, "BackdropTemplate")
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetPoint("CENTER", UIParent, "CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    window:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetClampedToScreen(true)
    window:Hide()

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -16)
    title:SetText("Tackle Manager")

    local closeBtn = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -6)

    window.tabStrip = CreateFrame("Frame", nil, window)
    window.tabStrip:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -44)
    window.tabStrip:SetPoint("TOPRIGHT", window, "TOPRIGHT", -16, -44)
    window.tabStrip:SetHeight(TAB_HEIGHT)

    window.contentHost = CreateFrame("Frame", nil, window)
    window.contentHost:SetPoint("TOPLEFT", window.tabStrip, "BOTTOMLEFT", 0, -8)
    window.contentHost:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, 16)

    tinsert(UISpecialFrames, "DreamFishTackleWindow")
    return window
end

function TackleWindow:EnsureFrame()
    if not self.frame then
        self.frame = CreateWindowFrame()
        self:RefreshTabs()
    end
    return self.frame
end

function TackleWindow:RefreshTabs()
    local window = self.frame
    if not window then return end

    local previous
    for _, tab in ipairs(self.tabs) do
        if not tab.button then
            local button = CreateFrame("Button", nil, window.tabStrip, "UIPanelButtonTemplate")
            button:SetHeight(TAB_HEIGHT)
            button:SetText(tab.title)
            button:SetWidth(math.max(80, button:GetTextWidth() + 24))
            button:SetScript("OnClick", function()
                TackleWindow:SelectTab(tab.id)
            end)
            tab.button = button
        end
        tab.button:ClearAllPoints()
        if previous then
            tab.button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            tab.button:SetPoint("LEFT", window.tabStrip, "LEFT", 0, 0)
        end
        previous = tab.button
    end

    -- Hide the tab strip when there is only one tab to show
    window.tabStrip:SetShown(#self.tabs > 1)

    if not self.activeTabId and self.tabs[1] then
        self:SelectTab(self.tabs[1].id)
    end
end

function TackleWindow:SelectTab(tabId)
    local window = self:EnsureFrame()
    local target = self.tabsById[tabId]
    if not (window and target) then return end

    for _, tab in ipairs(self.tabs) do
        local isActive = tab.id == tabId
        if tab.button then
            tab.button:SetEnabled(not isActive)
        end
        if tab.content then
            tab.content:SetShown(isActive)
        end
    end

    if not target.built then
        target.content = target.content or CreateFrame("Frame", nil, window.contentHost)
        target.content:SetAllPoints(window.contentHost)
        target.build(target.content)
        target.built = true
        target.content:Show()
    end

    self.activeTabId = tabId
end

function TackleWindow:Open(tabId)
    local window = self:EnsureFrame()
    if not window then return end
    self:SelectTab(tabId or self.activeTabId or (self.tabs[1] and self.tabs[1].id))
    window:Show()
    window:Raise()
    return window
end

function TackleWindow:Close()
    if self.frame then
        self.frame:Hide()
    end
end

function TackleWindow:Toggle(tabId)
    if self.frame and self.frame:IsShown() then
        self:Close()
    else
        self:Open(tabId)
    end
end

ns.ui.TackleWindow = TackleWindow
