local addonName = "DreamFisher"
local frame = CreateFrame("Frame", addonName .. "Frame")
local addon = _G[addonName] or {}
_G[addonName] = addon

addon.frame = frame

local defaults = {
    autoLoot = true,
    enhancedSounds = true,
    treasureAlerts = true,
    buffItem1 = nil,
    buffItem2 = nil,
    refreshSeconds = 180,
    lowBagThreshold = 2,
}

local savedAutoLoot = nil
local isFishing = false
local fishingStartTime = 0
local lastBagWarning = 0
local lastAlertTime = 0
local lastRightClickTime = 0
local lastSoundTime = 0
local doubleClickWindow = 0.25
local fishingSecureFrame = nil
local fishingTrackerFrame = nil
local originalAutoLootState = nil

local function CopyDefaults(source, target)
    for k, v in pairs(source) do
        if target[k] == nil then
            target[k] = v
        end
    end
end

local function Clamp(value, min, max)
    if value == nil then
        return min
    end
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

local function PrintMessage(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF7FFFDADreamFisher|r " .. msg)
    end
end

local function CreateSecureFishingFrame()
    if fishingSecureFrame then
        return fishingSecureFrame
    end

    fishingSecureFrame = CreateFrame("Button", "DreamFisherSecureFishingButton", UIParent, "SecureActionButtonTemplate")
    fishingSecureFrame:SetAllPoints(UIParent)
    fishingSecureFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    fishingSecureFrame:SetAttribute("type", "spell")
    fishingSecureFrame:SetAttribute("spell", "Fishing")
    fishingSecureFrame:RegisterForClicks("AnyDown")
    fishingSecureFrame:Hide()
    fishingSecureFrame:HookScript("OnClick", function()
        if not InCombatLockdown() then
            ClearOverrideBindings(fishingSecureFrame)
        end
    end)

    return fishingSecureFrame
end

local function CreateTrackerFrame()
    if fishingTrackerFrame then
        return fishingTrackerFrame
    end

    fishingTrackerFrame = CreateFrame("Frame")
    fishingTrackerFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    fishingTrackerFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if fishingSecureFrame and not InCombatLockdown() then
                ClearOverrideBindings(fishingSecureFrame)
            end
        end
    end)

    return fishingTrackerFrame
end

local function EnableTemporaryAutoLoot()
    if addon.db and addon.db.autoLoot then
        local current = GetCVar("autoLootDefault")
        if savedAutoLoot == nil then
            savedAutoLoot = current
        end
        SetCVar("autoLootDefault", "1")
    end
end

local function RestoreOriginalAutoLoot()
    if addon.db and addon.db.autoLoot and savedAutoLoot ~= nil then
        SetCVar("autoLootDefault", savedAutoLoot)
        savedAutoLoot = nil
    end
end

local function HandleWorldRightClick()
    local now = GetTime()

    if now - lastRightClickTime < doubleClickWindow then
        lastRightClickTime = 0

        EnableTemporaryAutoLoot()

        if not InCombatLockdown() then
            SetOverrideBindingClick(fishingSecureFrame, true, "BUTTON2", fishingSecureFrame:GetName())
        end
    else
        lastRightClickTime = now
        if not InCombatLockdown() then
            ClearOverrideBindings(fishingSecureFrame)
        end
    end
end

local function ContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    end
    if GetContainerNumSlots then
        return GetContainerNumSlots(bag)
    end
    return 0
end

local function ContainerItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bag, slot)
    end
    if GetContainerItemID then
        return GetContainerItemID(bag, slot)
    end
    return nil
end

local function GetFreeBagSlots()
    local free = 0
    local bagCount = NUM_BAG_SLOTS or 4
    for bag = 0, bagCount do
        local slots = ContainerNumSlots(bag)
        for slot = 1, slots do
            if not ContainerItemID(bag, slot) then
                free = free + 1
            end
        end
    end
    return free
end

local function FindItemInBags(itemID)
    if not itemID then
        return nil, nil
    end

    local bagCount = NUM_BAG_SLOTS or 4
    for bag = 0, bagCount do
        local slots = ContainerNumSlots(bag)
        for slot = 1, slots do
            if ContainerItemID(bag, slot) == itemID then
                return bag, slot
            end
        end
    end

    return nil, nil
end

local function IsFishingCast()
    if UnitCastingInfo("player") == "Fishing" then
        return true
    end
    if UnitChannelInfo("player") == "Fishing" then
        return true
    end
    return false
end

local function IsTreasureItem(name)
    if not name then
        return false
    end
    local lower = string.lower(name)
    return lower:find("treasure") or lower:find("chest") or lower:find("cache") or lower:find("satchel") or lower:find("strongbox")
end

local function PlayFishingSound()
    if not addon.db or not addon.db.enhancedSounds then
        return
    end
    if GetTime() - lastSoundTime < 1.2 then
        return
    end
    lastSoundTime = GetTime()
    if type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.UI_BONUS_ROLL_START then
        PlaySound(SOUNDKIT.UI_BONUS_ROLL_START)
    end
end

local function UpdateConfigUI()
    if not addon.configFrame or not addon.db then
        return
    end

    if addon.autoLootCheckbox then
        addon.autoLootCheckbox:SetChecked(addon.db.autoLoot)
    end
    if addon.enhancedSoundsCheckbox then
        addon.enhancedSoundsCheckbox:SetChecked(addon.db.enhancedSounds)
    end
    if addon.treasureAlertsCheckbox then
        addon.treasureAlertsCheckbox:SetChecked(addon.db.treasureAlerts)
    end
    if addon.refreshBox then
        addon.refreshBox:SetText(tostring(addon.db.refreshSeconds or defaults.refreshSeconds))
    end
    if addon.lowBagBox then
        addon.lowBagBox:SetText(tostring(addon.db.lowBagThreshold or defaults.lowBagThreshold))
    end
    if addon.buffItem1Box then
        addon.buffItem1Box:SetText(tostring(addon.db.buffItem1 or ""))
    end
    if addon.buffItem2Box then
        addon.buffItem2Box:SetText(tostring(addon.db.buffItem2 or ""))
    end
end

function addon:SaveConfig()
    if not addon.db then
        return
    end

    addon.db.refreshSeconds = Clamp(tonumber(addon.refreshBox:GetText()) or defaults.refreshSeconds, 30, 600)
    addon.db.lowBagThreshold = Clamp(tonumber(addon.lowBagBox:GetText()) or defaults.lowBagThreshold, 0, 20)
    addon.db.autoLoot = addon.autoLootCheckbox:GetChecked()
    addon.db.enhancedSounds = addon.enhancedSoundsCheckbox:GetChecked()
    addon.db.treasureAlerts = addon.treasureAlertsCheckbox:GetChecked()

    if addon.buffItem1Box then
        local item1 = tonumber(addon.buffItem1Box:GetText())
        addon.db.buffItem1 = item1 or nil
    end
    if addon.buffItem2Box then
        local item2 = tonumber(addon.buffItem2Box:GetText())
        addon.db.buffItem2 = item2 or nil
    end

    UpdateConfigUI()
end

function addon:CreateConfigPanel()
    if addon.configFrame then
        return
    end

    local panel = CreateFrame("Frame", addonName .. "ConfigFrame", UIParent)
    panel.name = addonName
    panel:SetSize(420, 380)
    panel:SetPoint("CENTER")
    panel:Hide()

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 16, -16)
    panel.title:SetText(addonName)

    local function CreateCheckbox(x, y, label, key)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        cb.Text:SetText(label)
        cb:SetScript("OnClick", function()
            addon.db[key] = cb:GetChecked()
        end)
        return cb
    end

    addon.autoLootCheckbox = CreateCheckbox(20, -50, "Enable temporary auto-loot", "autoLoot")
    addon.enhancedSoundsCheckbox = CreateCheckbox(20, -85, "Enable enhanced fishing sounds", "enhancedSounds")
    addon.treasureAlertsCheckbox = CreateCheckbox(20, -120, "Enable treasure alerts", "treasureAlerts")

    local refreshLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    refreshLabel:SetPoint("TOPLEFT", 20, -165)
    refreshLabel:SetText("Buff refresh time (seconds):")

    addon.refreshBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    addon.refreshBox:SetSize(90, 24)
    addon.refreshBox:SetPoint("TOPLEFT", 220, -160)
    addon.refreshBox:SetAutoFocus(false)
    addon.refreshBox:SetScript("OnEnterPressed", function()
        addon:SaveConfig()
    end)

    local bagLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bagLabel:SetPoint("TOPLEFT", 20, -210)
    bagLabel:SetText("Low bag warning threshold:")

    addon.lowBagBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    addon.lowBagBox:SetSize(90, 24)
    addon.lowBagBox:SetPoint("TOPLEFT", 220, -205)
    addon.lowBagBox:SetAutoFocus(false)
    addon.lowBagBox:SetScript("OnEnterPressed", function()
        addon:SaveConfig()
    end)

    local item1Label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    item1Label:SetPoint("TOPLEFT", 20, -255)
    item1Label:SetText("Buff item 1:")

    local item2Label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    item2Label:SetPoint("TOPLEFT", 20, -315)
    item2Label:SetText("Buff item 2:")

    local function CreateItemBox(x, y)
        local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetSize(140, 24)
        box:SetPoint("TOPLEFT", x, y)
        box:SetAutoFocus(false)
        box:SetScript("OnEnterPressed", function()
            addon:SaveConfig()
        end)
        return box
    end

    addon.buffItem1Box = CreateItemBox(220, -250)
    addon.buffItem2Box = CreateItemBox(220, -310)

    local closeButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    closeButton:SetSize(120, 24)
    closeButton:SetPoint("BOTTOMRIGHT", -16, 16)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        panel:Hide()
    end)

    local saveButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    saveButton:SetSize(120, 24)
    saveButton:SetPoint("BOTTOMLEFT", 16, 16)
    saveButton:SetText("Save")
    saveButton:SetScript("OnClick", function()
        addon:SaveConfig()
    end)

    panel:SetScript("OnShow", function()
        UpdateConfigUI()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, addonName)
        Settings.RegisterAddOnCategory(category)
        addon.configFrame = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        addon.configFrame = panel
    else
        addon.configFrame = panel
    end
end

function addon:TryRefreshBuffItems()
    if not addon.db or not isFishing then
        return
    end

    local now = GetTime()
    if now - fishingStartTime < (addon.db.refreshSeconds or defaults.refreshSeconds) then
        return
    end

    for _, itemID in ipairs({addon.db.buffItem1, addon.db.buffItem2}) do
        if itemID then
            local bag, slot = FindItemInBags(itemID)
            if bag and slot then
                UseContainerItem(bag, slot)
                fishingStartTime = now
                return
            end
        end
    end
end

function addon:OpenConfigPanel()
    if not addon.configFrame then
        addon:CreateConfigPanel()
    end

    if addon.configFrame and addon.configFrame.Show then
        addon.configFrame:Show()
    end
end

function addon:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= addonName then
            return
        end

        if not DreamFisherDB then
            DreamFisherDB = {}
        end
        addon.db = DreamFisherDB
        CopyDefaults(defaults, addon.db)
        addon:CreateConfigPanel()
        CreateSecureFishingFrame()
        CreateTrackerFrame()
        if WorldFrame then
            WorldFrame:HookScript("OnMouseDown", function(_, button)
                if button == "RightButton" then
                    HandleWorldRightClick()
                end
            end)
        end
        PrintMessage("Ready")

    elseif event == "PLAYER_LOGIN" then
        CreateSecureFishingFrame()
        CreateTrackerFrame()

    elseif event == "PLAYER_REGEN_DISABLED" then
        if fishingSecureFrame and not InCombatLockdown() then
            ClearOverrideBindings(fishingSecureFrame)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if fishingSecureFrame and not InCombatLockdown() then
            ClearOverrideBindings(fishingSecureFrame)
        end

    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit, spell = ...
        if unit == "player" and spell == "Fishing" then
            isFishing = true
            fishingStartTime = GetTime()
        end

    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local unit, spell = ...
        if unit == "player" and spell == "Fishing" then
            -- Keep isFishing true until the loot window has fully closed.
            -- This avoids losing the auto-loot state before LOOT_OPENED runs.
        end

    elseif event == "LOOT_READY" then
        print("LOOT_READY event detected")
        RestoreOriginalAutoLoot()

        if addon.db and addon.db.enhancedSounds and isFishing then
            PlayFishingSound()
        end

        if addon.db and addon.db.treasureAlerts and isFishing then
            local count = GetNumLootItems()
            for i = 1, count do
                local _, itemName = GetLootSlotInfo(i)
                if itemName and IsTreasureItem(itemName) then
                    if GetTime() - lastAlertTime > 3 then
                        lastAlertTime = GetTime()
                        PrintMessage("Treasure caught: " .. itemName)
                        if type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.QUEST_COMPLETED then
                            PlaySound(SOUNDKIT.QUEST_COMPLETED)
                        end
                    end
                    break
                end
            end
        end

    elseif event == "LOOT_CLOSED" then
        RestoreOriginalAutoLoot()
        isFishing = false

    elseif event == "BAG_UPDATE" then
        local freeSlots = GetFreeBagSlots()
        if addon.db and addon.db.lowBagThreshold and freeSlots <= addon.db.lowBagThreshold and GetTime() - lastBagWarning > 30 then
            lastBagWarning = GetTime()
            PrintMessage("Low bag space: " .. freeSlots .. " free slot(s)")
        end

    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        addon:TryRefreshBuffItems()
    end
end

function addon:OnUpdate(elapsed)
    if isFishing then
        addon:TryRefreshBuffItems()
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    addon:OnEvent(event, ...)
end)
frame:SetScript("OnUpdate", function(self, elapsed)
    addon:OnUpdate(elapsed)
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
frame:RegisterEvent("UNIT_SPELLCAST_STOP")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("LOOT_CLOSED")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")

SLASH_DREAMFISHER1 = "/dreamfisher"
SLASH_DREAMFISHER2 = "/df"
SlashCmdList["DREAMFISHER"] = function()
    addon:OpenConfigPanel()
end
