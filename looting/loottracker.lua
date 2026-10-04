local addonName, ns = ...
local Addon = ns.Addon
local LootTracker = Addon:GetModule("LootTracker")
local AceGUI = LibStub("AceGUI-3.0")

ns.LootTracker = LootTracker

local globalDB, profileDB, charDB

local lootTrackerWindow
local scrollContainer
local resetButton
local panelScrollContainer

-- these are non-prototype variables
local currencyCache = {}
local skipNextCurrencyUpdate = false
local showCatchRate = false

LootTracker:RegisterTraceSource("LootTracker")

local function Trace(msg, ...)
    LootTracker:Trace("LootTracker", msg, ...)
end

local function CountLootDataRows(charData)
    local count = 0
    for _ in pairs(type(charData.lootedItems) == "table" and charData.lootedItems or {}) do
        count = count + 1
    end
    for _ in pairs(type(charData.lootedCurrencies) == "table" and charData.lootedCurrencies or {}) do
        count = count + 1
    end
    return count
end

local function CanAddLootDataRow(self, rows, key)
    if rows[key] ~= nil then
        return true
    end

    local limit = tonumber(self.db.profile.limitLootDataRows)
    return not limit or CountLootDataRows(self.db.char) < limit
end

function LootTracker:OnModuleInitialize()
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end

function LootTracker:OnModuleEnable()
    if self:GetTrackerDisplayMode() ~= "tab" and (self.db.profile.windowVisible or self.db.profile.showWindowOnStartup) then
        self:CreateLootTrackerWindow()
    end

    self:ScanAndCacheCurrencies()
    skipNextCurrencyUpdate = true
    self:UpdateTrackerDisplay()
end

function LootTracker:OnModuleRegisterEvents()
    self:RegisterEvent("BAG_UPDATE_DELAYED", "BAG_UPDATE_DELAYED")
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "CURRENCY_DISPLAY_UPDATE")
end

function LootTracker:OnModuleDisable()
    if lootTrackerWindow then
        lootTrackerWindow:Hide()
    end

    self:UnregisterEvent("BAG_UPDATE_DELAYED")
    self:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
end

-- the rest of this file is non-prototype code

function LootTracker:BAG_UPDATE_DELAYED(...)
    self:Alerts_BAG_UPDATE_DELAYED(...)
end

function LootTracker:RecordLootedItem(itemID, quantity)
    itemID = tonumber(itemID)
    quantity = math.floor(tonumber(quantity) or 1)
    if not itemID or itemID <= 0 or quantity <= 0 then
        return
    end

    local lootedItems = self.db.char.lootedItems
    if type(lootedItems) ~= "table" then
        lootedItems = {}
        self.db.char.lootedItems = lootedItems
    end
    if not CanAddLootDataRow(self, lootedItems, itemID) then
        Trace("Loot data limit reached; ignoring new item " .. tostring(itemID))
        return
    end
    lootedItems[itemID] = (tonumber(lootedItems[itemID]) or 0) + quantity
    self:UpdateTrackerDisplay()
    if lootTrackerWindow and self.db.profile.windowVisible then
        lootTrackerWindow:Show()
    end
end

function LootTracker:RecordSuccessfulCast()
    self.db.char.castsLooted = (tonumber(self.db.char.castsLooted) or 0) + 1
    self:UpdateTrackerDisplay()
    if lootTrackerWindow and self.db.profile.windowVisible then
        lootTrackerWindow:Show()
    end
end

function LootTracker:CURRENCY_DISPLAY_UPDATE(event, currencyType, quantityChanged, quantityGained, changeReason)
    if skipNextCurrencyUpdate then
        skipNextCurrencyUpdate = false
        self:ScanAndCacheCurrencies()
        return
    end

    if not currencyType then
        return
    end

    local info = C_CurrencyInfo.GetCurrencyInfo(currencyType)
    local currentQuantity = info and info.quantity
    local lastQuantity = currencyCache[currencyType] or 0

    if not currentQuantity then
        return
    end

    if currentQuantity > lastQuantity then
        local amountGained = currentQuantity - lastQuantity

        if type(self.db.char.lootedCurrencies) ~= "table" then
            self.db.char.lootedCurrencies = {}
        end

        local lootedCurrencies = self.db.char.lootedCurrencies
        if CanAddLootDataRow(self, lootedCurrencies, currencyType) then
            lootedCurrencies[currencyType] = (tonumber(lootedCurrencies[currencyType]) or 0) + amountGained

            self:UpdateTrackerDisplay()
            if lootTrackerWindow and self.db.profile.windowVisible then
                lootTrackerWindow:Show()
            end
        else
            Trace("Loot data limit reached; ignoring new currency " .. tostring(currencyType))
        end
    end

    self:ScanAndCacheCurrencies()
end

function LootTracker:ScanAndCacheCurrencies()
    currencyCache = {}
    -- 5000 is a safe maximum loop index to catch all standard expansion currency types
    for currencyID = 1, 5000 do
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info and info.discovered then
            currencyCache[currencyID] = info.quantity
        end
    end
end

function LootTracker:CreateLootTrackerWindow()
    if lootTrackerWindow then return end

    lootTrackerWindow = AceGUI:Create("Window")
    lootTrackerWindow:SetTitle("Loot Tracker")
    lootTrackerWindow:SetWidth(280)
    lootTrackerWindow:SetHeight(340)
    lootTrackerWindow:SetLayout("Fill")

    local pos = self.db.profile.windowPos
    pos.width = pos.width or 280
    pos.height = pos.height or 340

    -- Let AceGUI persist width/height/top/left on drag/resize via its internal mouse handlers.
    lootTrackerWindow:SetStatusTable(pos)

    lootTrackerWindow:SetCallback("OnClose", function(widget)
        self.db.profile.windowVisible = false
        widget.frame:Hide()
    end)

    ---@diagnostic disable-next-line: invisible
    local nativeFrame = lootTrackerWindow.frame

    scrollContainer = AceGUI:Create("ScrollFrame")
    scrollContainer:SetLayout("Flow")
    ---@diagnostic disable-next-line: invisible
    local scrollFrame = scrollContainer.frame
    scrollFrame:SetParent(nativeFrame)
    scrollFrame:Show()

    resetButton = AceGUI:Create("Button")
    resetButton:SetText("Clear")
    resetButton:SetWidth(240)
    resetButton:SetCallback("OnClick", function()
        self.db.char.lootedItems = {}
        self.db.char.lootedCurrencies = {}
        self.db.char.castsLooted = 0
        self:UpdateTrackerDisplay()
        print("|cFF00FF00[LootTracker]|r History track cleared.")
    end)

    -- Strip the button from AceGUI flow and hard-anchor it to the window's bottom margin
    ---@diagnostic disable-next-line: invisible
    local resetButtonFrame = resetButton.frame
    resetButtonFrame:SetParent(nativeFrame)
    resetButtonFrame:ClearAllPoints()
    resetButtonFrame:SetPoint("BOTTOMLEFT", nativeFrame, "BOTTOMLEFT", 15, 15)
    resetButtonFrame:SetPoint("BOTTOMRIGHT", nativeFrame, "BOTTOMRIGHT", -15, 15)
    resetButtonFrame:Show()

    -- Anchor scroll region above the action buttons so resize never lets content overlap them.
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", nativeFrame, "TOPLEFT", 15, -30)
    scrollFrame:SetPoint("TOPRIGHT", nativeFrame, "TOPRIGHT", -15, -30)
    scrollFrame:SetPoint("BOTTOMLEFT", resetButtonFrame, "TOPLEFT", 0, 30)
    scrollFrame:SetPoint("BOTTOMRIGHT", resetButtonFrame, "TOPRIGHT", 0, 30)

    self.db.profile.windowVisible = true
    self:UpdateTrackerDisplay()
end

-- Explicit release needed: scrollContainer/resetButton are reparented via raw SetParent,
-- so they are not tracked as the window's AceGUI children and won't cascade-release with it.
function LootTracker:DestroyLootTrackerWindow()
    if resetButton then
        AceGUI:Release(resetButton)
        resetButton = nil
    end
    if scrollContainer then
        AceGUI:Release(scrollContainer)
        scrollContainer = nil
    end
    if lootTrackerWindow then
        AceGUI:Release(lootTrackerWindow)
        lootTrackerWindow = nil
    end
end

function LootTracker:GetTrackerDisplayMode()
    return self.db.profile.showTrackerAs or "window"
end

function LootTracker:ApplyTrackerDisplayMode()
    if self:GetTrackerDisplayMode() == "tab" then
        self:DestroyLootTrackerWindow()
    elseif self.db.profile.windowVisible or self.db.profile.showWindowOnStartup then
        self:CreateLootTrackerWindow()
    end

    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName .. "Dialog")
    self:UpdateTrackerDisplay()
end

function LootTracker:ShowTracker()
    if self:GetTrackerDisplayMode() == "tab" then
        Addon:OpenDialogToTab(addonName .. "Dialog", "lootTrackerTab")
    else
        self:ShowTrackerDisplay()
    end
end

function LootTracker:RegisterPanelScrollContainer(container)
    panelScrollContainer = container
    self:UpdateTrackerDisplay()
end

function LootTracker:UnregisterPanelScrollContainer(container)
    if panelScrollContainer == container then
        panelScrollContainer = nil
    end
end

function CreateItemRow(itemLink, count, showCatchRate)
    local itemRow = AceGUI:Create("InteractiveLabel")
    local catchRateText = ""
    local numberCatches = tonumber(LootTracker.db.char.castsLooted) or 0

    if showCatchRate and numberCatches > 0 then
        local catchRateForItem = (count / numberCatches) * 100 or 0
        catchRateText = string.format(" (%.2f%%)", catchRateForItem)
    end

    itemRow:SetText(itemLink .. " x" .. count .. catchRateText)
    itemRow:SetFontObject(GameFontHighlight)
    itemRow:SetFullWidth(true)

    itemRow:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
    end)

    itemRow:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)

    return itemRow
end

-- Shared by the standalone window and the dialog-tab panel widget so both stay in sync.
function LootTracker:PopulateScrollContainer(container)
    if not container then return end

    -- COMPLETELY CLEAR SCROLL SUB-WIDGETS
    container:ReleaseChildren()

    local successfulCasts = tonumber(self.db.char.castsLooted) or 0
    local totalLabel = AceGUI:Create("Label")
    totalLabel:SetText("Successful fishing casts: |cFF00FF00" .. successfulCasts .. "|r")
    totalLabel:SetFontObject(GameFontNormalLarge)
    totalLabel:SetFullWidth(true)
    container:AddChild(totalLabel)

    local separator = AceGUI:Create("Heading")
    separator:SetFullWidth(true)
    container:AddChild(separator)

    if not self.db.char.lootedItems then self.db.char.lootedItems = {} end
    if not self.db.char.lootedCurrencies then self.db.char.lootedCurrencies = {} end
    local hasEntries = false
    local minQualityFilter = self.db.profile.minQualityFilter or 0
    local displayEntries = {}

    -- PROCESS STANDARD LOOTED ITEMS DYNAMICALLY
    for itemId, count in pairs(self.db.char.lootedItems) do
        if not count then count = 0 end
        if count > 0 then
            local itemName, itemLink, itemQuality = C_Item.GetItemInfo(itemId)

            -- Fallback if the item isn't locally cached in game memory yet
            if not itemLink then
                itemName = itemName or ("Loading Item #" .. itemId)
                itemLink = "|cFFaaaaaa[Loading Item #" .. itemId .. "]|r"
                C_Item.RequestLoadItemDataByID(itemId)
            end

            if not itemQuality or itemQuality >= minQualityFilter then
                table.insert(displayEntries, {
                    sortName = string.lower(itemName or itemLink),
                    itemLink = itemLink,
                    count = count,
                })
                hasEntries = true
            end
        end
    end

    -- PROCESS LOOTED CURRENCIES DYNAMICALLY
    for currencyId, count in pairs(self.db.char.lootedCurrencies) do
        if not count then count = 0 end
        if count > 0 then
            local currencyLink = C_CurrencyInfo.GetCurrencyLink(currencyId, count)

            if not currencyLink then
                local info = C_CurrencyInfo.GetCurrencyInfo(currencyId)
                local name = info and info.name or ("Currency #" .. currencyId)
                currencyLink = "|cFFFFD100[" .. name .. "]|r"
                table.insert(displayEntries, {
                    sortName = string.lower(name),
                    itemLink = currencyLink,
                    count = count,
                })
            else
                local info = C_CurrencyInfo.GetCurrencyInfo(currencyId)
                local name = info and info.name or currencyLink
                table.insert(displayEntries, {
                    sortName = string.lower(name),
                    itemLink = currencyLink,
                    count = count,
                })
            end
            hasEntries = true
        end
    end

    table.sort(displayEntries, function(left, right)
        if left.sortName == right.sortName then
            return left.itemLink < right.itemLink
        end
        return left.sortName < right.sortName
    end)

    for _, entry in ipairs(displayEntries) do
        local showCatchRate = LootTracker.db.profile.showCatchRate or true
        local itemRow = CreateItemRow(entry.itemLink, entry.count, showCatchRate)
        container:AddChild(itemRow)
    end

    -- 5. FALLBACK EMPTY TRACKER ITEM NOTICE
    if not hasEntries then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetText("No items or currencies tracked yet.")
        emptyLabel:SetFontObject(GameFontHighlight)
        emptyLabel:SetFullWidth(true)
        container:AddChild(emptyLabel)
    end

    -- Forces the scroll layout framework to calculate boundaries
    container:DoLayout()
end

function LootTracker:UpdateTrackerDisplay()
    if lootTrackerWindow and scrollContainer then
        self:PopulateScrollContainer(scrollContainer)
    end
    if panelScrollContainer then
        self:PopulateScrollContainer(panelScrollContainer)
    end
end

function LootTracker:UpdateDisplayIfVisible()
    if lootTrackerWindow and lootTrackerWindow.frame:IsShown() then
        self:UpdateTrackerDisplay()
    end
end

function LootTracker:ShowTrackerDisplay()
    if lootTrackerWindow then
        lootTrackerWindow:Show()
        profileDB.windowVisible = true
    else
        self:CreateLootTrackerWindow()
    end
end

function LootTracker:ToggleTrackerWindow()
    if lootTrackerWindow then
        if lootTrackerWindow.frame:IsShown() then
            lootTrackerWindow:Hide()
            profileDB.windowVisible = false
        else
            lootTrackerWindow:Show()
            profileDB.windowVisible = true
        end
    else
        self:CreateLootTrackerWindow()
    end
end