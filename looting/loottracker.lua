local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local LootTracker = DreamFish:GetModule("LootTracker", true) or DreamFish:NewModule("LootTracker", "AceConsole-3.0", "AceEvent-3.0")

local AceGUI = LibStub("AceGUI-3.0")
local lootTrackerWindow
local scrollContainer

local itemCache = {}
local currencyCache = {}
local skipNextBagUpdate = false
local skipNextCurrencyUpdate = false

local function CharDB()
    return DreamFish.db.char.lootTracker
end
local function ProfileDB()
    return DreamFish.db.profile.lootTracker
end
local function Debug(msg, ...)
    if DreamFish.db.profile.debugMode then
        DreamFish:Print("|cFF9ACDFF[LootTracker]|r ", msg, ...)
    end
end

function LootTracker:OnInitialize()
    Debug("Initializing")
    DreamFish.db:RegisterDefaults(ns.LootTracker.Defaults)
end

function LootTracker:OnEnable()
    if not ProfileDB().moduleEnabled then
        Debug("Loot Tracker module is disabled in settings. Enable it to use the tracker.")
        return
    end

    Debug("Enabling")

    if ProfileDB().windowVisible or ProfileDB().showWindowOnStartup then
        self:CreateLootTrackerWindow()
    end

    self:ScanAndCacheInventory()
    self:ScanAndCacheCurrencies()
    skipNextBagUpdate = true
    skipNextCurrencyUpdate = true
    self:UpdateTrackerDisplay()

    self:RegisterEvent("BAG_UPDATE_DELAYED")
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
end

function LootTracker:OnDisable()
    if lootTrackerWindow then
        lootTrackerWindow:Hide()
    end

    self:UnregisterEvent("BAG_UPDATE_DELAYED")
    self:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")

    Debug("Disabled")
end

function LootTracker:BAG_UPDATE_DELAYED()
    if skipNextBagUpdate then
        skipNextBagUpdate = false
        self:ScanAndCacheInventory()
        return
    end

    for slotID = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(slotID)
        for slotIndex = 1, numSlots do
            local itemId = C_Container.GetContainerItemID(slotID, slotIndex)

            if itemId then
                local slotInfo = C_Container.GetContainerItemInfo(slotID, slotIndex)
                if slotInfo then
                    local currentQuantity = slotInfo.stackCount
                    local itemKey = slotID .. "_" .. slotIndex

                    local lastQuantity = itemCache[itemKey] or 0
                    if currentQuantity > lastQuantity then
                        local amountGained = currentQuantity - lastQuantity

                        -- 1. Step up overall tracking data metrics
                        CharDB().itemsLooted = CharDB().itemsLooted + amountGained

                        -- 2. ADJUSTMENT: Step up specific character-scoped entry tracking
                        if not CharDB().lootedItems then
                            CharDB().lootedItems = {}
                        end
                        CharDB().lootedItems[itemId] = (CharDB().lootedItems[itemId] or 0) + amountGained

                        -- 3. Redraw your scrolling labels instantly
                        self:UpdateTrackerDisplay()
                        if lootTrackerWindow and ProfileDB().windowVisible then
                            lootTrackerWindow:Show()
                        end
                    end
                end
            end
        end
    end
    self:ScanAndCacheInventory()
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

        if not CharDB().lootedCurrencies then
            CharDB().lootedCurrencies = {}
        end

        CharDB().lootedCurrencies[currencyType] = (CharDB().lootedCurrencies[currencyType] or 0) + amountGained
        CharDB().itemsLooted = CharDB().itemsLooted + amountGained

        self:UpdateTrackerDisplay()
        if lootTrackerWindow and ProfileDB().windowVisible then
            lootTrackerWindow:Show()
        end
    end

    self:ScanAndCacheCurrencies()
end

function LootTracker:ScanAndCacheInventory()
    itemCache = {}
    for slotID = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(slotID)
        for slotIndex = 1, numSlots do
            local itemId = C_Container.GetContainerItemID(slotID, slotIndex)
            if itemId then
                local slotInfo = C_Container.GetContainerItemInfo(slotID, slotIndex)
                if slotInfo then
                    itemCache[slotID .. "_" .. slotIndex] = slotInfo.stackCount
                end
            end
        end
    end
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

    local pos = ProfileDB().windowPos
    pos.width = pos.width or 280
    pos.height = pos.height or 340

    -- Let AceGUI persist width/height/top/left on drag/resize via its internal mouse handlers.
    lootTrackerWindow:SetStatusTable(pos)

    lootTrackerWindow:SetCallback("OnClose", function(widget)
        ProfileDB().windowVisible = false
        widget.frame:Hide()
    end)

    local nativeFrame = lootTrackerWindow.frame

    scrollContainer = AceGUI:Create("ScrollFrame")
    scrollContainer:SetLayout("Flow")
    scrollContainer.frame:SetParent(nativeFrame)
    scrollContainer.frame:Show()

    local resetButton = AceGUI:Create("Button")
    resetButton:SetText("Reset LootTracker")
    resetButton:SetWidth(240)
    resetButton:SetCallback("OnClick", function()
        CharDB().itemsLooted = 0
        CharDB().lootedItems = {}
        CharDB().lootedCurrencies = {}
        self:UpdateTrackerDisplay()
        print("|cFF00FF00[DreamFish]|r History track cleared.")
    end)

    -- Strip the button from AceGUI flow and hard-anchor it to the window's bottom margin
    resetButton.frame:SetParent(nativeFrame)
    resetButton.frame:ClearAllPoints()
    resetButton.frame:SetPoint("BOTTOMLEFT", nativeFrame, "BOTTOMLEFT", 15, 15)
    resetButton.frame:SetPoint("BOTTOMRIGHT", nativeFrame, "BOTTOMRIGHT", -15, 15)
    resetButton.frame:Show()

    -- Anchor scroll region to the reset button so resize never lets content overlap it.
    scrollContainer.frame:ClearAllPoints()
    scrollContainer.frame:SetPoint("TOPLEFT", nativeFrame, "TOPLEFT", 15, -30)
    scrollContainer.frame:SetPoint("TOPRIGHT", nativeFrame, "TOPRIGHT", -15, -30)
    scrollContainer.frame:SetPoint("BOTTOMLEFT", resetButton.frame, "TOPLEFT", 0, 30)
    scrollContainer.frame:SetPoint("BOTTOMRIGHT", resetButton.frame, "TOPRIGHT", 0, 30)

    ProfileDB().windowVisible = true
    self:UpdateTrackerDisplay()
end

function CreateItemRow(itemLink, count)
    local itemRow = AceGUI:Create("InteractiveLabel")
    itemRow:SetText(itemLink .. " x" .. count)
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

function LootTracker:UpdateTrackerDisplay()
    -- Guard condition against unexpected data calls prior to full load sequences
    if not lootTrackerWindow or not scrollContainer then return end


    -- COMPLETELY CLEAR SCROLL SUB-WIDGETS
    scrollContainer:ReleaseChildren()

    local grandTotal = CharDB().itemsLooted or 0
    local totalLabel = AceGUI:Create("Label")
    totalLabel:SetText("Total Looted: |cFF00FF00" .. grandTotal .. "|r")
    totalLabel:SetFontObject(GameFontNormalLarge)
    totalLabel:SetFullWidth(true)
    scrollContainer:AddChild(totalLabel)

    local separator = AceGUI:Create("Heading")
    separator:SetFullWidth(true)
    scrollContainer:AddChild(separator)

    if not CharDB().lootedItems then CharDB().lootedItems = {} end
    if not CharDB().lootedCurrencies then CharDB().lootedCurrencies = {} end
    local hasEntries = false
    local minQualityFilter = ProfileDB().minQualityFilter or 0
    local displayEntries = {}

    -- PROCESS STANDARD LOOTED ITEMS DYNAMICALLY
    for itemId, count in pairs(CharDB().lootedItems) do
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
    for currencyId, count in pairs(CharDB().lootedCurrencies) do
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
        local itemRow = CreateItemRow(entry.itemLink, entry.count)
        scrollContainer:AddChild(itemRow)
    end

    -- 5. FALLBACK EMPTY TRACKER ITEM NOTICE
    if not hasEntries then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetText("No items or currencies tracked yet.")
        emptyLabel:SetFontObject(GameFontHighlight)
        emptyLabel:SetFullWidth(true)
        scrollContainer:AddChild(emptyLabel)
    end

    -- Forces the scroll layout framework to calculate boundaries
    scrollContainer:DoLayout()
end

function LootTracker:UpdateDisplayIfVisible()
    if lootTrackerWindow and lootTrackerWindow.frame:IsShown() then
        self:UpdateTrackerDisplay()
    end
end

function LootTracker:ToggleTrackerWindow()
    if lootTrackerWindow then
        if lootTrackerWindow.frame:IsShown() then
            lootTrackerWindow:Hide()
            ProfileDB().windowVisible = false
        else
            lootTrackerWindow:Show()
            ProfileDB().windowVisible = true
        end
    else
        self:CreateLootTrackerWindow()
    end
end