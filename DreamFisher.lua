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
local isBobberActive = false
local fishingStartTime = 0
local lastBagWarning = 0
local lastAlertTime = 0
local lastRightClickTime = 0
local lastSoundTime = 0
local doubleClickWindow = 0.25
local fishingSecureFrame = nil
local fishingTrackerFrame = nil
local originalAutoLootState = nil
local fishingStateFrame = nil

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

local function CreateFishingStateFrame()
    if fishingStateFrame then
        return fishingStateFrame
    end

    fishingStateFrame = CreateFrame("Frame")
    fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_START")
    fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    fishingStateFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

    fishingStateFrame:SetScript("OnEvent", function(self, event, unit, ...)
        if unit ~= "player" then
            return
        end

        if event == "UNIT_SPELLCAST_START" then
            local spellName = select(1, UnitCastingInfo("player"))
            if spellName == "Fishing" then
                isFishing = true
                isBobberActive = false
                fishingStartTime = GetTime()
                EnableTemporaryAutoLoot()
                -- Start periodic bag space monitoring
                fishingStateFrame:SetScript("OnUpdate", function()
                    CheckBagSpace()
                end)
            end
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            local spellName = select(1, UnitChannelInfo("player"))
            if spellName == "Fishing" then
                isFishing = false
                isBobberActive = true
                -- Stop bag monitoring when fishing ends
                fishingStateFrame:SetScript("OnUpdate", nil)
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            -- Cancel fishing if combat starts
            if isFishing then
                isFishing = false
                isBobberActive = false
                RestoreOriginalAutoLoot()
                -- Stop bag monitoring
                fishingStateFrame:SetScript("OnUpdate", nil)
            end
        end
    end)

    return fishingStateFrame
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

-- Minimal test hooks for local unit tests with mocked WoW APIs.
addon._test = addon._test or {}
addon._test.EnableTemporaryAutoLoot = EnableTemporaryAutoLoot
addon._test.RestoreOriginalAutoLoot = RestoreOriginalAutoLoot
addon._test.SetDB = function(db)
    addon.db = db
end
addon._test.ResetAutoLootState = function()
    savedAutoLoot = nil
end

local function HandleWorldRightClick()
    -- Only allow double-click fishing if not already fishing
    if isFishing or InCombatLockdown() then
        return
    end

    local now = GetTime()

    if now - lastRightClickTime < doubleClickWindow then
        lastRightClickTime = 0
        -- Double-click detected, initiate fishing
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

local function AttemptBobberInteraction()
    -- Click the bobber when it becomes active
    if not isBobberActive or isFishing then
        return
    end

    -- Look for the fishing bobber frame
    -- In WoW, the bobber is created as a frame when a cast is successful
    local bobber = _G["FishingLineIkonTooltip"]
    if bobber then
        bobber:Click()
        isBobberActive = false
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
    -- Check main bags (0 is backpack, 1-4 are other bags)
    for bag = 0, bagCount do
        local slots = ContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                if not ContainerItemID(bag, slot) then
                    free = free + 1
                end
            end
        end
    end
    -- Check reagent bag (bag index 5 in retail WoW)
    local reagentSlots = ContainerNumSlots(5)
    if reagentSlots and reagentSlots > 0 then
        for slot = 1, reagentSlots do
            if not ContainerItemID(5, slot) then
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

local function CheckBagSpace()
    -- Alert if bag space falls below the configured threshold
    if not addon.db then
        return
    end

    local threshold = addon.db.lowBagThreshold or defaults.lowBagThreshold
    local free = GetFreeBagSlots()

    if free <= threshold then
        local now = GetTime()
        -- Only alert once per 10 seconds to avoid spam
        if now - lastBagWarning >= 10 then
            lastBagWarning = now
            PrintMessage("Low bag space! " .. free .. " slot(s) remaining (threshold: " .. threshold .. ").")
        end
    end
end

addon._test.GetFreeBagSlots = GetFreeBagSlots
addon._test.CheckBagSpace = CheckBagSpace
addon._test.ResetBagWarningState = function()
    lastBagWarning = 0
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
        return addon.configFrame
    end

    -- 1. Main Container Frame
    local panel = CreateFrame("Frame", addonName .. "ConfigFrame", UIParent, "BackdropTemplate")
    panel:SetSize(420, 400)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()

    -- Aesthetic Frame Styling (Makes it visible)
    panel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)

    addon.configFrame = panel

    -- 2. Title Text
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 20, -20)
    panel.title:SetText(addonName .. " Settings")

    -- 3. Close Button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -8, -8)

    -- 4. Checkbox Helper
    local function CreateCheckbox(x, y, label)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        cb.Text:SetText(label)
        cb.Text:SetTextColor(1, 1, 1, 1)
        return cb
    end

    -- 5. Input Box Helper
    local function CreateEditBox(x, y, width, label)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", x, y)
        lbl:SetText(label)

        local eb = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        eb:SetSize(width, 20)
        eb:SetPoint("TOPLEFT", x, y - 15)
        eb:SetAutoFocus(false)
        return eb
    end

    -- Instantiate UI elements
    addon.autoLootCheckbox = CreateCheckbox(20, -50, "Enable Temporary Auto-Loot")
    addon.enhancedSoundsCheckbox = CreateCheckbox(20, -85, "Enhanced Audio Alerts")
    addon.treasureAlertsCheckbox = CreateCheckbox(20, -120, "Treasure / Node Notifications")

    addon.buffItem1Box = CreateEditBox(20, -170, 100, "Buff Item ID 1:")
    addon.buffItem2Box = CreateEditBox(140, -170, 100, "Buff Item ID 2:")

    addon.refreshBox = CreateEditBox(20, -220, 100, "Refresh Frequency (s):")
    addon.lowBagBox = CreateEditBox(20, -270, 100, "Low Bag Threshold:")

    -- 6. Save Button
    local saveBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    saveBtn:SetSize(120, 25)
    saveBtn:SetPoint("BOTTOMRIGHT", -20, 20)
    saveBtn:SetText("Save & Close")
    saveBtn:SetScript("OnClick", function()
        addon:SaveConfig()
        panel:Hide()
        PrintMessage("Configuration Saved.")
    end)

    panel:SetScript("OnShow", function()
        UpdateConfigUI()
    end)

    return panel
end

function addon:ToggleUI()
    local panel = addon.configFrame or addon:CreateConfigPanel()
    if panel:IsShown() then
        panel:Hide()
    else
        UpdateConfigUI()
        panel:Show()
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if event ~= "ADDON_LOADED" or name ~= addonName then
        return
    end

    _G[addonName .. "DB"] = _G[addonName .. "DB"] or {}
    addon.db = _G[addonName .. "DB"]
    CopyDefaults(defaults, addon.db)

    CreateSecureFishingFrame()
    CreateTrackerFrame()
    CreateFishingStateFrame()

    SLASH_DREAMFISHER1 = "/df"
    SLASH_DREAMFISHER2 = "/dreamfisher"
    SlashCmdList["DREAMFISHER"] = function()
        addon:ToggleUI()
    end

    PrintMessage("Loaded! Type /df to configure.")
    self:UnregisterEvent("ADDON_LOADED")
end)

if WorldFrame then
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if button == "RightButton" and not InCombatLockdown() then
            HandleWorldRightClick()
        end
    end)
end

local lootTracker = CreateFrame("Frame")
lootTracker:RegisterEvent("LOOT_READY")
lootTracker:RegisterEvent("LOOT_CLOSED")
lootTracker:RegisterEvent("BAG_UPDATE")
lootTracker:SetScript("OnEvent", function(_, event)
    if event == "LOOT_READY" then
        -- Loot opened while fishing
        if isBobberActive then
            isBobberActive = false
            isFishing = false
        end
    elseif event == "LOOT_CLOSED" then
        RestoreOriginalAutoLoot()
        isBobberActive = false
        -- Reset bag warning cooldown when loot is closed (bag space may have changed)
        lastBagWarning = 0
    elseif event == "BAG_UPDATE" then
        -- Check bag space immediately when inventory changes
        if isFishing then
            CheckBagSpace()
        end
    end
end)

local bagMonitor = CreateFrame("Frame")
bagMonitor:RegisterEvent("PLAYER_ENTERING_WORLD")
bagMonitor:RegisterEvent("BAG_UPDATE_DELAYED")
bagMonitor:SetScript("OnEvent", function()
    CheckBagSpace()
end)

