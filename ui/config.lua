-- DreamFisher Config UI Module
-- Manages configuration panel and settings UI

local addonName = "DreamFisher"
local addon = _G[addonName]

-- Config module namespace
addon.config = addon.config or {}
local config = addon.config

-- Local references to globals
local maxBuffSlots = addon.const.maxBuffSlots or 6
local defaults = addon.defaults
local uiBuffCursorDragState = nil
local buffItemLastUseAt = {}
local buffItemLastKnownCount = {}
local buffBagCountSnapshot = nil
local suppressLiveSave = false
local SaveLive
local aceGUI = nil
local UpdateToyApplyButtons
local SyncEscapeCloseRegistration
local ownedToyOptionsCache = {}
local UNDERLIGHT_MODE_DISABLED = "disabled"
local UNDERLIGHT_MODE_ALWAYS_EXCEPT_FISHING = "always_except_fishing"
local UNDERLIGHT_MODE_LOCK = "lock_underlight"
local IsLikelyFishingPoleItem

local function IsPositiveItemID(value)
    local numeric = tonumber(value)
    return numeric and numeric > 0 and numeric or nil
end

local function GetUnderlightItemID()
    return (addon.const and tonumber(addon.const.underlightAnglerItemID)) or 133755
end

local function IsUnderlightAnglerItemID(itemID)
    return tonumber(itemID) == GetUnderlightItemID()
end

local function NormalizeUnderlightMode(mode)
    local allowed = addon.const and addon.const.underlightAnglerModes or nil
    if type(mode) == "string" and allowed and allowed[mode] then
        return mode
    end
    if type(mode) == "string" then
        if mode == UNDERLIGHT_MODE_DISABLED
            or mode == UNDERLIGHT_MODE_ALWAYS_EXCEPT_FISHING
            or mode == UNDERLIGHT_MODE_LOCK then
            return mode
        end
    end
    return UNDERLIGHT_MODE_DISABLED
end

local function NormalizeTackleConfigValues()
    if not addon.db then
        return
    end
    addon.db.selectedFishingPole = IsPositiveItemID(addon.db.selectedFishingPole)
    local underlightID = GetUnderlightItemID()
    local configuredUnderlight = IsPositiveItemID(addon.db.selectedUnderlightAngler)
    addon.db.selectedUnderlightAngler = (configuredUnderlight == underlightID) and configuredUnderlight or nil
    addon.db.underlightAnglerMode = NormalizeUnderlightMode(addon.db.underlightAnglerMode)
end

local function IsItemInBags(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return false
    end

    if addon.buff and addon.buff.FindItemInBags then
        local bag, slot = addon.buff.FindItemInBags(numeric)
        if bag and slot then
            return true
        end
    end

    if addon.utils and addon.utils.CountItemInBags then
        return (addon.utils.CountItemInBags(numeric) or 0) > 0
    end

    return false
end

local function IsItemEquipped(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 or type(GetInventoryItemID) ~= "function" then
        return false
    end

    local maxSlot = (type(INVSLOT_LAST_EQUIPPED) == "number" and INVSLOT_LAST_EQUIPPED) or 19
    for slot = 1, maxSlot do
        if GetInventoryItemID("player", slot) == numeric then
            return true
        end
    end

    if GetInventoryItemID("player", 28) == numeric then
        return true
    end

    return false
end

local function IsItemAvailableForConfig(itemID)
    return IsItemInBags(itemID) or IsItemEquipped(itemID)
end

local function GetProfessionSlotItemID()
    if type(GetInventoryItemID) ~= "function" then
        return nil
    end

    local rawItemID = GetInventoryItemID("player", 28)
    local itemID = tonumber(rawItemID)
    if not itemID or itemID <= 0 then
        return nil
    end
    return itemID
end

local function GetEquippedItemIDs()
    local itemIDs = {}
    if type(GetInventoryItemID) ~= "function" then
        return itemIDs
    end

    local maxSlot = (type(INVSLOT_LAST_EQUIPPED) == "number" and INVSLOT_LAST_EQUIPPED) or 19
    for slot = 1, maxSlot do
        local rawItemID = GetInventoryItemID("player", slot)
        local itemID = tonumber(rawItemID)
        if itemID and itemID > 0 then
            itemIDs[itemID] = true
        end
    end

    local rawProfessionSlotItem = GetInventoryItemID("player", 28)
    local professionSlotItem = tonumber(rawProfessionSlotItem)
    if professionSlotItem and professionSlotItem > 0 then
        itemIDs[professionSlotItem] = true
    end

    return itemIDs
end

local function GetEquippedFishingPoleItemID()
    local equipped = GetEquippedItemIDs()
    for itemID, _ in pairs(equipped) do
        if IsLikelyFishingPoleItem(itemID) and not IsUnderlightAnglerItemID(itemID) then
            return itemID
        end
    end
    return nil
end

local function IsUnderlightEquipped()
    local underlightID = GetUnderlightItemID()
    local equipped = GetEquippedItemIDs()
    return equipped[underlightID] and true or false
end

IsLikelyFishingPoleItem = function(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return false
    end

    if type(GetItemInfoInstant) == "function" then
        local _, _, itemSubType, equipLoc, _, classID, subClassID = GetItemInfoInstant(numeric)
        if equipLoc == "INVTYPE_PROFESSION_GEAR" then
            return true
        end
        if tonumber(classID) == 2 and tonumber(subClassID) == 20 then
            return true
        end
        if itemSubType == "Fishing Poles" then
            return true
        end
    end

    local itemName = (type(GetItemInfo) == "function") and GetItemInfo(numeric) or nil
    if type(itemName) == "string" and itemName ~= "" then
        local lowered = string.lower(itemName)
        if string.find(lowered, "fishing pole", 1, true) then
            return true
        end
    end

    return false
end

local function BuildOwnedFishingPoleOptions(includeDefaultLabel)
    local options = {}
    local seen = {}

    if type(includeDefaultLabel) == "string" and includeDefaultLabel ~= "" then
        table.insert(options, {
            value = 0,
            label = includeDefaultLabel,
        })
    end

    local function AddOption(itemID)
        local numeric = tonumber(itemID)
        if not numeric or numeric <= 0 or seen[numeric] then
            return
        end
        if not IsLikelyFishingPoleItem(numeric) then
            return
        end
        seen[numeric] = true
        table.insert(options, {
            value = numeric,
            label = (type(GetItemInfo) == "function" and GetItemInfo(numeric)) or ("item:" .. tostring(numeric)),
        })
    end

    local maxSlot = (type(INVSLOT_LAST_EQUIPPED) == "number" and INVSLOT_LAST_EQUIPPED) or 19
    if type(GetInventoryItemID) == "function" then
        for slot = 1, maxSlot do
            AddOption(GetInventoryItemID("player", slot))
        end
        AddOption(GetInventoryItemID("player", 28))
    end

    local bagCount = NUM_BAG_SLOTS or 4
    for bag = 0, bagCount do
        local slots = addon.utils and addon.utils.ContainerNumSlots and addon.utils.ContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemID = addon.utils and addon.utils.ContainerItemID and addon.utils.ContainerItemID(bag, slot) or nil
            AddOption(itemID)
        end
    end

    local reagentSlots = addon.utils and addon.utils.ContainerNumSlots and addon.utils.ContainerNumSlots(5) or 0
    if reagentSlots and reagentSlots > 0 then
        for slot = 1, reagentSlots do
            local itemID = addon.utils and addon.utils.ContainerItemID and addon.utils.ContainerItemID(5, slot) or nil
            AddOption(itemID)
        end
    end

    table.sort(options, function(a, b)
        if a.value == 0 then
            return true
        end
        if b.value == 0 then
            return false
        end
        return tostring(a.label) < tostring(b.label)
    end)

    return options
end

local function BuildUnderlightModeOptions()
    local modeLabels = addon.const and addon.const.underlightAnglerModes or {}
    return {
        { value = UNDERLIGHT_MODE_DISABLED, label = modeLabels[UNDERLIGHT_MODE_DISABLED] or "Do not equip Underlight Angler" },
        { value = UNDERLIGHT_MODE_ALWAYS_EXCEPT_FISHING, label = modeLabels[UNDERLIGHT_MODE_ALWAYS_EXCEPT_FISHING] or "Equip always except when fishing" },
        { value = UNDERLIGHT_MODE_LOCK, label = modeLabels[UNDERLIGHT_MODE_LOCK] or "Equip now and don't swap" },
    }
end

local function RefreshUnderlightConfigControls()
    local configuredUnderlightID = addon.underlightAnglerBox and tonumber(addon.underlightAnglerBox:GetText()) or nil
    local hasUnderlight = configuredUnderlightID and configuredUnderlightID > 0 and IsItemAvailableForConfig(configuredUnderlightID)
    if addon.underlightAnglerModeSelector and addon.underlightAnglerModeSelector.SetEnabled then
        addon.underlightAnglerModeSelector:SetEnabled(hasUnderlight)
    end

    if not hasUnderlight then
        if addon.underlightAnglerModeSelector then
            addon.underlightAnglerModeSelector:SetText(UNDERLIGHT_MODE_DISABLED)
        end
    end
end

local function GetMainHandItemID()
    if type(GetInventoryItemID) ~= "function" then
        return nil
    end
    local rawItemID = GetInventoryItemID("player", 16)
    local itemID = tonumber(rawItemID)
    if not itemID or itemID <= 0 then
        return nil
    end
    return itemID
end

local function GetActiveEquippedTacklePoleItemID()
    local underlightID = GetUnderlightItemID()
    if IsItemEquipped(underlightID) then
        return underlightID
    end

    local professionItemID = GetProfessionSlotItemID()
    if professionItemID and professionItemID > 0 then
        return professionItemID
    end

    local mainHandItemID = GetMainHandItemID()
    if mainHandItemID and mainHandItemID > 0 then
        return mainHandItemID
    end

    return nil
end

local function RefreshTackleEquippedPoleHighlights()
    if not addon.fishingPoleBox and not addon.underlightAnglerBox then
        return
    end

    local activeEquippedPoleItemID = GetActiveEquippedTacklePoleItemID()

    local selectedPole = addon.fishingPoleBox and tonumber(addon.fishingPoleBox:GetText()) or nil
    local selectedUnderlight = addon.underlightAnglerBox and tonumber(addon.underlightAnglerBox:GetText()) or nil

    local poleMatch = selectedPole
        and selectedPole > 0
        and activeEquippedPoleItemID
        and selectedPole == activeEquippedPoleItemID
        and true
        or false
    local underlightMatch = selectedUnderlight
        and selectedUnderlight > 0
        and activeEquippedPoleItemID
        and selectedUnderlight == activeEquippedPoleItemID
        and true
        or false

    if addon.fishingPoleBox and addon.fishingPoleBox.SetHighlightedAsEquipped then
        addon.fishingPoleBox:SetHighlightedAsEquipped(poleMatch)
    end
    if addon.underlightAnglerBox and addon.underlightAnglerBox.SetHighlightedAsEquipped then
        addon.underlightAnglerBox:SetHighlightedAsEquipped(underlightMatch)
    end
end

local tackleHighlightEventFrame = nil
local tackleHighlightRefreshActive = false

local function SetTackleHighlightAutoRefreshEnabled(enabled)
    if enabled then
        if tackleHighlightRefreshActive then
            return
        end
        if type(CreateFrame) ~= "function" then
            return
        end
        if not tackleHighlightEventFrame then
            tackleHighlightEventFrame = CreateFrame("Frame")
            if tackleHighlightEventFrame and tackleHighlightEventFrame.SetScript then
                tackleHighlightEventFrame:SetScript("OnEvent", function(_, event, arg1)
                    if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then
                        return
                    end
                    local panel = addon.frames and addon.frames.config
                    if panel and panel:IsShown() then
                        RefreshTackleEquippedPoleHighlights()
                    end
                end)
            end
        end
        if not tackleHighlightEventFrame then
            return
        end
        if tackleHighlightEventFrame.RegisterEvent then
            tackleHighlightEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
            tackleHighlightEventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
            tackleHighlightEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        end
        tackleHighlightRefreshActive = true
    else
        if not tackleHighlightRefreshActive or not tackleHighlightEventFrame then
            return
        end
        if tackleHighlightEventFrame.UnregisterEvent then
            tackleHighlightEventFrame:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
            tackleHighlightEventFrame:UnregisterEvent("UNIT_INVENTORY_CHANGED")
            tackleHighlightEventFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        end
        tackleHighlightRefreshActive = false
    end
end

local function TryGetAceGUI()
    if aceGUI then
        return aceGUI
    end

    local libStub = _G.LibStub
    if type(libStub) ~= "table" and type(libStub) ~= "function" then
        return nil
    end

    local ok, lib = pcall(libStub.GetLibrary, libStub, "AceGUI-3.0", true)
    if ok and lib then
        aceGUI = lib
        return aceGUI
    end

    return nil
end

config.TryGetAceGUI = TryGetAceGUI

local function BuildOwnedToyOptions(candidateIDs, includeDefaultLabel)
    local cacheKeyParts = { tostring(includeDefaultLabel or "") }
    if type(candidateIDs) == "table" then
        for _, itemID in ipairs(candidateIDs) do
            table.insert(cacheKeyParts, tostring(itemID))
        end
    end
    local cacheKey = table.concat(cacheKeyParts, "|")
    local cached = ownedToyOptionsCache[cacheKey]
    if cached then
        return cached
    end

    local options = {}
    local seen = {}

    local function GetFastToyLabel(itemID)
        local numeric = tonumber(itemID)
        if not numeric or numeric <= 0 then
            return tostring(itemID)
        end

        if C_Item and type(C_Item.IsItemDataCachedByID) == "function" then
            local ok, cached = pcall(C_Item.IsItemDataCachedByID, numeric)
            if ok and not cached then
                return "item:" .. tostring(numeric)
            end
        end

        return (addon.utils and addon.utils.GetToyLabel and addon.utils.GetToyLabel(numeric))
            or ("item:" .. tostring(numeric))
    end

    if type(includeDefaultLabel) == "string" and includeDefaultLabel ~= "" then
        table.insert(options, {
            value = 0,
            label = includeDefaultLabel,
        })
    end

    if type(candidateIDs) ~= "table" then
        return options
    end

    for _, itemID in ipairs(candidateIDs) do
        local numeric = tonumber(itemID)
        if numeric and numeric > 0 and not seen[numeric] then
            seen[numeric] = true
            if type(PlayerHasToy) ~= "function" or PlayerHasToy(numeric) then
                table.insert(options, {
                    value = numeric,
                    label = GetFastToyLabel(numeric),
                })
            end
        end
    end

    ownedToyOptionsCache[cacheKey] = options
    return options
end

local function CollectActiveBuffItemIDs(buffItems)
    local active = {}
    if type(buffItems) ~= "table" then
        return active
    end
    for _, entry in ipairs(buffItems) do
        local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
        if itemID and itemID > 0 then
            active[itemID] = true
        end
    end
    return active
end

local function ApplyBuffSlotEnabledState(control, isEnabled)
    if not control then
        return
    end
    control.desiredEnabled = isEnabled and true or false
    if control.enabledCheckbox and control.enabledCheckbox.GetChecked then
        if control.enabledCheckbox:GetChecked() ~= control.desiredEnabled then
            control.enabledCheckbox:SetChecked(control.desiredEnabled)
        end
    end
end

local function ResolveBool(value, defaultValue)
    if value == nil then
        return not not defaultValue
    end
    return not not value
end

local function GetCastingModesForConfig()
    local defaultsModes = defaults.castingModes or {}
    local dbModes = (addon.db and addon.db.castingModes) or {}
    local modes = {
        doubleRightClick = ResolveBool(dbModes.doubleRightClick, defaultsModes.doubleRightClick),
        singleRightClickConfig = ResolveBool(dbModes.singleRightClickConfig, defaultsModes.singleRightClickConfig),
        singleRightClickDoubleStart = ResolveBool(dbModes.singleRightClickDoubleStart, defaultsModes.singleRightClickDoubleStart),
        hotkey = ResolveBool(dbModes.hotkey, defaultsModes.hotkey),
    }
    return modes
end

local function LoadConfigBindings()
    if not addon.db then
        return
    end

    NormalizeTackleConfigValues()
    local activeTab = addon.frames
        and addon.frames.config
        and addon.frames.config.activeTab
        or "focus"
    local isFocusActive = activeTab == "focus"
    local isTackleActive = activeTab == "tackle"
    local isModesActive = activeTab == "modes"

    local function BuildBuffBagCountSnapshot()
        local counts = {}
        local bagCount = NUM_BAG_SLOTS or 4
        for bag = 0, bagCount do
            local slots = addon.utils and addon.utils.ContainerNumSlots and addon.utils.ContainerNumSlots(bag) or 0
            for slot = 1, slots do
                local itemID = addon.utils and addon.utils.ContainerItemID and addon.utils.ContainerItemID(bag, slot) or nil
                if itemID then
                    counts[itemID] = (counts[itemID] or 0) + 1
                end
            end
        end

        local reagentSlots = addon.utils and addon.utils.ContainerNumSlots and addon.utils.ContainerNumSlots(5) or 0
        if reagentSlots and reagentSlots > 0 then
            for slot = 1, reagentSlots do
                local itemID = addon.utils and addon.utils.ContainerItemID and addon.utils.ContainerItemID(5, slot) or nil
                if itemID then
                    counts[itemID] = (counts[itemID] or 0) + 1
                end
            end
        end

        return counts
    end

    local shouldBuildBuffSnapshot = addon.buffItemControls
        and #addon.buffItemControls > 0
        and addon.frames
        and addon.frames.config
        and addon.frames.config.activeTab == "buffs"
    if shouldBuildBuffSnapshot then
        buffBagCountSnapshot = BuildBuffBagCountSnapshot()
    else
        buffBagCountSnapshot = nil
    end

    if isFocusActive and addon.autoLootCheckbox then
        addon.autoLootCheckbox:SetChecked(addon.db.autoLoot)
    end
    if isFocusActive and addon.enhancedSoundsCheckbox then
        addon.enhancedSoundsCheckbox:SetChecked(addon.db.enhancedSounds)
    end
    if isFocusActive and addon.treasureAlertsCheckbox then
        addon.treasureAlertsCheckbox:SetChecked(addon.db.treasureAlerts)
    end
    if isFocusActive and addon.bagAlertsCheckbox then
        addon.bagAlertsCheckbox:SetChecked(addon.db.bagAlerts)
    end
    if isModesActive and addon.escapeCloseCheckbox then
        addon.escapeCloseCheckbox:SetChecked(addon.db.configCloseOnEscape)
    end
    if isFocusActive and addon.lowBagBox then
        addon.lowBagBox:SetText(tostring(addon.db.lowBagThreshold or defaults.lowBagThreshold))
    end
    if activeTab == "buffs" and addon.buffItemControls then
        for i, control in ipairs(addon.buffItemControls) do
            local entry = addon.db.buffItems and addon.db.buffItems[i] or nil
            local itemID = entry and entry.itemID or nil
            local isEnabled = nil
            if type(entry) == "table" and entry.enabled ~= nil then
                isEnabled = (entry.enabled ~= false)
            elseif control and control.desiredEnabled ~= nil then
                isEnabled = (control.desiredEnabled ~= false)
            else
                isEnabled = true
            end
            local desiredText = tostring(itemID or "")
            if control.itemBox:GetText() ~= desiredText then
                control.itemBox:SetText(desiredText)
            end

            -- Refresh presence-driven checkbox dim/enable state even when text
            -- does not change, so reopened windows correctly dim empty slots.
            local hasItem = itemID and tonumber(itemID) and tonumber(itemID) > 0
            if control.enabledCheckbox and control.enabledCheckbox.SetEnabled then
                control.enabledCheckbox:SetEnabled(hasItem and true or false)
            end
            if control.itemBox and control.itemBox.SetEnabledForPreCast then
                control.itemBox:SetEnabledForPreCast((hasItem and true or false) and (isEnabled ~= false))
            end

            ApplyBuffSlotEnabledState(control, isEnabled)
        end
    end
    buffBagCountSnapshot = nil
    if isFocusActive and addon.audioLingerBox then
        addon.audioLingerBox:SetText(tostring(addon.db.audioFocusLinger or defaults.audioFocusLinger))
    end
    if isModesActive and addon.modeDoubleRightClickCheckbox then
        local modes = GetCastingModesForConfig()
        addon.modeDoubleRightClickCheckbox:SetChecked(modes.doubleRightClick)
        addon.modeSingleRightClickConfigCheckbox:SetChecked(modes.singleRightClickConfig)
        addon.modeHotkeyCheckbox:SetChecked(modes.hotkey)
    end
    if isModesActive and addon.enableHookedLootCheckbox then
        addon.enableHookedLootCheckbox:SetChecked(addon.db.enableHookedLoot)
    end

    if addon._lastAppliedTackleBindings == nil then
        addon._lastAppliedTackleBindings = {}
    end

    local lastTackle = addon._lastAppliedTackleBindings
    local desiredRaftToy = addon.db.selectedRaftToy or nil
    local desiredBobberToy = addon.db.selectedBobberToy or nil
    if isTackleActive and addon.bobberSelector and lastTackle.selectedBobberToy ~= desiredBobberToy then
        addon.bobberSelector:SetText(desiredBobberToy)
        lastTackle.selectedBobberToy = desiredBobberToy
    end
    if isTackleActive and addon.raftSelector and lastTackle.selectedRaftToy ~= desiredRaftToy then
        addon.raftSelector:SetText(desiredRaftToy)
        lastTackle.selectedRaftToy = desiredRaftToy
    end
    if isTackleActive and addon.oversizedBobberCheckbox then
        addon.oversizedBobberCheckbox:SetChecked(addon.db.useOversizedBobber)
    end

    local equippedProfessionItem = GetProfessionSlotItemID()
    local fishingPoleFallback = (equippedProfessionItem and not IsUnderlightAnglerItemID(equippedProfessionItem))
        and equippedProfessionItem
        or GetEquippedFishingPoleItemID()
    local selectedFishingPole = addon.db.selectedFishingPole or fishingPoleFallback or nil
    if isTackleActive and addon.fishingPoleBox then
        local desiredPoleText = tostring(selectedFishingPole or "")
        if addon.fishingPoleBox:GetText() ~= desiredPoleText then
            addon.fishingPoleBox:SetText(desiredPoleText)
        end
    end

    local underlightID = GetUnderlightItemID()
    local selectedUnderlight = addon.db.selectedUnderlightAngler
    if (not selectedUnderlight or selectedUnderlight <= 0)
        and (IsUnderlightEquipped() or IsItemInBags(underlightID)) then
        selectedUnderlight = underlightID
    end
    if isTackleActive and addon.underlightAnglerBox then
        local desiredUnderlightText = tostring(selectedUnderlight or "")
        if addon.underlightAnglerBox:GetText() ~= desiredUnderlightText then
            addon.underlightAnglerBox:SetText(desiredUnderlightText)
        end
    end

    if isTackleActive and addon.underlightAnglerModeSelector then
        addon.underlightAnglerModeSelector:RefreshOptions()
        addon.underlightAnglerModeSelector:SetText(addon.db.underlightAnglerMode or UNDERLIGHT_MODE_DISABLED)
    end

    if isTackleActive then
        RefreshUnderlightConfigControls()
        RefreshTackleEquippedPoleHighlights()
    end

    UpdateToyApplyButtons()
end

local function SaveConfigBindings()
    if not addon.db then
        return nil
    end

    local previouslyActiveBuffItems = CollectActiveBuffItemIDs(addon.db.buffItems)

    addon.db.refreshSeconds = addon.Clamp(tonumber(addon.db.refreshSeconds) or defaults.refreshSeconds, 30, 600)

    if addon.lowBagBox then
        addon.db.lowBagThreshold = addon.Clamp(tonumber(addon.lowBagBox:GetText()) or defaults.lowBagThreshold, 0, 20)
    else
        addon.db.lowBagThreshold = addon.Clamp(tonumber(addon.db.lowBagThreshold) or defaults.lowBagThreshold, 0, 20)
    end

    if addon.audioLingerBox then
        addon.db.audioFocusLinger = addon.Clamp(tonumber(addon.audioLingerBox:GetText()) or defaults.audioFocusLinger, 0, 60)
    else
        addon.db.audioFocusLinger = addon.Clamp(tonumber(addon.db.audioFocusLinger) or defaults.audioFocusLinger, 0, 60)
    end

    if addon.autoLootCheckbox then
        addon.db.autoLoot = addon.autoLootCheckbox:GetChecked()
    end
    if addon.enhancedSoundsCheckbox then
        addon.db.enhancedSounds = addon.enhancedSoundsCheckbox:GetChecked()
    end
    if addon.treasureAlertsCheckbox then
        addon.db.treasureAlerts = addon.treasureAlertsCheckbox:GetChecked()
    end
    if addon.bagAlertsCheckbox then
        addon.db.bagAlerts = addon.bagAlertsCheckbox:GetChecked()
    end

    local existingModes = (type(addon.db.castingModes) == "table") and addon.db.castingModes or {}
    local defaultModes = defaults.castingModes or {}
    local modeFlags = {
        doubleRightClick = addon.modeDoubleRightClickCheckbox
            and addon.modeDoubleRightClickCheckbox:GetChecked()
            or ResolveBool(existingModes.doubleRightClick, defaultModes.doubleRightClick),
        singleRightClickConfig = addon.modeSingleRightClickConfigCheckbox
            and addon.modeSingleRightClickConfigCheckbox:GetChecked()
            or ResolveBool(existingModes.singleRightClickConfig, defaultModes.singleRightClickConfig),
        singleRightClickDoubleStart = ResolveBool(existingModes.singleRightClickDoubleStart, defaultModes.singleRightClickDoubleStart),
        hotkey = addon.modeHotkeyCheckbox
            and addon.modeHotkeyCheckbox:GetChecked()
            or ResolveBool(existingModes.hotkey, defaultModes.hotkey),
    }
    addon.db.castingModes = modeFlags

    if addon.enableHookedLootCheckbox then
        addon.db.enableHookedLoot = addon.enableHookedLootCheckbox:GetChecked() or false
    else
        addon.db.enableHookedLoot = addon.db.enableHookedLoot and true or false
    end

    if addon.oversizedBobberCheckbox then
        addon.db.useOversizedBobber = addon.oversizedBobberCheckbox:GetChecked()
    end
    if addon.escapeCloseCheckbox then
        addon.db.configCloseOnEscape = addon.escapeCloseCheckbox:GetChecked()
    end
    SyncEscapeCloseRegistration()

    if addon.buffItemControls then
        local previousBuffItems = addon.db.buffItems or {}
        addon.db.buffItems = {}
        for i, control in ipairs(addon.buffItemControls) do
            local itemID = tonumber(control.itemBox:GetText())
            local previous = previousBuffItems[i]
            local enabledState = nil
            if control and control.desiredEnabled ~= nil then
                enabledState = (control.desiredEnabled ~= false)
            end
            if enabledState == nil and control.enabledCheckbox and control.enabledCheckbox.GetChecked then
                enabledState = control.enabledCheckbox:GetChecked()
            end
            if enabledState == nil then
                enabledState = (((type(previous) == "table") and (previous.enabled ~= false)) or true)
            end
            addon.db.buffItems[i] = {
                itemID = (itemID and itemID > 0) and itemID or nil,
                enabled = enabledState,
            }
        end
    end

    if addon.bobberSelector then
        local selectedBobberToy = tonumber(addon.bobberSelector:GetText())
        addon.db.selectedBobberToy = (selectedBobberToy and selectedBobberToy > 0) and selectedBobberToy or nil
    end
    if addon.raftSelector then
        local selectedRaftToy = tonumber(addon.raftSelector:GetText())
        addon.db.selectedRaftToy = (selectedRaftToy and selectedRaftToy > 0) and selectedRaftToy or nil
    end
    if addon.fishingPoleBox then
        local selectedFishingPole = tonumber(addon.fishingPoleBox:GetText())
        addon.db.selectedFishingPole = (selectedFishingPole and selectedFishingPole > 0) and selectedFishingPole or nil
    end
    if addon.underlightAnglerBox then
        local selectedUnderlight = tonumber(addon.underlightAnglerBox:GetText())
        if selectedUnderlight and selectedUnderlight > 0 and IsUnderlightAnglerItemID(selectedUnderlight) then
            addon.db.selectedUnderlightAngler = selectedUnderlight
        else
            addon.db.selectedUnderlightAngler = nil
        end
    end
    if addon.underlightAnglerModeSelector then
        addon.db.underlightAnglerMode = NormalizeUnderlightMode(addon.underlightAnglerModeSelector:GetText())
    else
        addon.db.underlightAnglerMode = NormalizeUnderlightMode(addon.db.underlightAnglerMode)
    end

    if not IsItemAvailableForConfig(GetUnderlightItemID()) then
        addon.db.selectedUnderlightAngler = nil
        addon.db.underlightAnglerMode = UNDERLIGHT_MODE_DISABLED
    end

    NormalizeTackleConfigValues()

    if addon.fishing and addon.fishing.MaybeEquipConfiguredUnderlight then
        addon.fishing.MaybeEquipConfiguredUnderlight("config-save")
    end

    UpdateToyApplyButtons()

    return previouslyActiveBuffItems
end

UpdateToyApplyButtons = function()
    local function SyncButton(button, selector, baseLabel)
        if not button then
            return
        end
        local toyID = selector and tonumber(selector:GetText()) or nil
        if toyID and toyID > 0 then
            button:SetAttribute("type", "toy")
            button:SetAttribute("toy", toyID)
            button:SetText(baseLabel)
            button:Enable()
        else
            button:SetAttribute("toy", nil)
            button:SetText(baseLabel .. " (none)")
            button:Disable()
        end
    end

    SyncButton(addon.bobberApplyButton, addon.bobberSelector, "Apply Bobber")
    SyncButton(addon.raftApplyButton, addon.raftSelector, "Apply Raft")
end

SyncEscapeCloseRegistration = function()
    if type(UISpecialFrames) ~= "table" then
        return
    end

    local panel = addon.frames and addon.frames.config
    local frameName = panel and (panel:GetName() or panel.escapeFrameAlias) or nil
    if not frameName or frameName == "" then
        return
    end

    local shouldRegister = addon.db and addon.db.configCloseOnEscape
    local existingIndex = nil
    for i, name in ipairs(UISpecialFrames) do
        if name == frameName then
            existingIndex = i
            break
        end
    end

    if shouldRegister and not existingIndex then
        table.insert(UISpecialFrames, frameName)
    elseif not shouldRegister and existingIndex then
        table.remove(UISpecialFrames, existingIndex)
    end
end

-- Helper: Update all config UI elements from saved data
local function UpdateConfigUI()
    if not addon.frames.config or not addon.db then
        return
    end

    suppressLiveSave = true
    LoadConfigBindings()
    suppressLiveSave = false
end

-- Save config from UI back to database
function config.SaveConfig(skipRefresh)
    if not addon.db then
        return
    end

    local previouslyActiveBuffItems = SaveConfigBindings()
    local currentlyActiveBuffItems = CollectActiveBuffItemIDs(addon.db.buffItems)
    for removedItemID, _ in pairs(previouslyActiveBuffItems) do
        if not currentlyActiveBuffItems[removedItemID] then
            if addon.state then
                addon.state.buffItemLastUseAt[removedItemID] = nil
                addon.state.buffItemLastReminderAt[removedItemID] = nil
                if addon.state.buffItemLastReminderCastAnchor then
                    addon.state.buffItemLastReminderCastAnchor[removedItemID] = nil
                end
                addon.state.buffItemLastMissingWarningAt[removedItemID] = nil
                addon.state.buffItemLastKnownCount[removedItemID] = nil
                if addon.state.buffUnknownDurationSuppressed then
                    addon.state.buffUnknownDurationSuppressed[removedItemID] = nil
                end
            end
            if addon.db.buffAuraByItem then
                addon.db.buffAuraByItem[tostring(removedItemID)] = nil
            end
        end
    end

    if addon.buff and addon.buff.NormalizeBuffConfig then
        addon.buff.NormalizeBuffConfig()
    end

    if addon.state.savedFishingAudioCVars ~= nil and addon.state.audioRestoreAt ~= nil then
        if addon.audio and addon.audio.RestoreFishingAudioFocusAfterLinger then
            addon.audio.RestoreFishingAudioFocusAfterLinger()
        end
    end

    if not skipRefresh then
        UpdateConfigUI()
    end
end

local function BuildPanelShell(aceGUIInstance)
    local aceWindow = aceGUIInstance:Create("Frame")
    aceWindow:SetTitle(addonName .. " Settings")
    aceWindow:SetStatusText("")
    aceWindow:SetLayout("Fill")
    aceWindow:SetWidth(520)
    aceWindow:SetHeight(690)
    if aceWindow.EnableResize then
        aceWindow:EnableResize(false)
    end

    local panel = aceWindow.frame
    panel.aceWindow = aceWindow
    panel.escapeFrameAlias = panel.escapeFrameAlias or (addonName .. "ConfigPanel")
    _G[panel.escapeFrameAlias] = panel
    panel:Hide()

    local function SavePanelPosition(self)
        if addon.db then
            local point, _, relativePoint, x, y = self:GetPoint(1)
            addon.db.configWindowPosition = {
                point = point or "CENTER",
                relativePoint = relativePoint or "CENTER",
                x = math.floor((x or 0) + 0.5),
                y = math.floor((y or 0) + 0.5),
            }
        end
    end

    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:EnableKeyboard(false)
    panel:RegisterForDrag("LeftButton")
    panel:HookScript("OnDragStop", function(self)
        SavePanelPosition(self)
    end)

    if addon.db and type(addon.db.configWindowPosition) == "table" then
        local pos = addon.db.configWindowPosition
        panel:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", tonumber(pos.x) or 0, tonumber(pos.y) or 0)
    else
        panel:SetPoint("CENTER")
    end
    panel:Hide()

    return panel
end

local function BuildTabs(panel, aceGUIInstance)
    local tabLabels = {
        focus = "Focus",
        tackle = "Tackle",
        buffs = "Buffs",
        modes = "Modes",
    }

    panel.tabButtons = {}
    panel.pages = {}
    panel.activeTab = "focus"

    local function ShowTab(tabName)
        panel.activeTab = tabName
        for name, page in pairs(panel.pages) do
            page:SetShown(name == tabName)
        end
        for name, button in pairs(panel.tabButtons) do
            if name == tabName then
                button:Disable()
            else
                button:Enable()
            end
        end
    end

    local aceTabGroup = aceGUIInstance:Create("TabGroup")
    aceTabGroup:SetLayout("Fill")
    aceTabGroup:SetTabs({
        { text = tabLabels.focus, value = "focus" },
        { text = tabLabels.tackle, value = "tackle" },
        { text = tabLabels.buffs, value = "buffs" },
        { text = tabLabels.modes, value = "modes" },
    })
    aceTabGroup:SetCallback("OnGroupSelected", function(_, _, group)
        if panel.HandleTabSelected then
            panel.HandleTabSelected(group)
        end
        ShowTab(group)
    end)
    panel.aceTabGroup = aceTabGroup
    panel.aceWindow:AddChild(aceTabGroup)

    local function CreatePage(name)
        local parentFrame = panel.aceTabGroup and panel.aceTabGroup.content or panel
        local page = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
        page:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 8, -8)
        page:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -8, 8)
        page:Hide()
        panel.pages[name] = page
        return page
    end

    local pages = {
        focus = CreatePage("focus"),
        tackle = CreatePage("tackle"),
        buffs = CreatePage("buffs"),
        modes = CreatePage("modes"),
    }

    local function SelectTab(tabName)
        if panel.aceTabGroup and panel.aceTabGroup.SelectTab then
            panel.aceTabGroup:SelectTab(tabName)
        end
    end

    return {
        pages = pages,
        ShowTab = ShowTab,
        SelectTab = SelectTab,
    }
end

local function BuildFocusTab(focusPage, ui, onLiveChange)
    local root = ui.FlowRoot(focusPage, 12)

    local focusSection = ui.FlowSection(root, "Focus")
    addon.autoLootCheckbox = ui.FlowCheckbox(focusSection, "Temporary Auto-Loot", onLiveChange)
    addon.treasureAlertsCheckbox = ui.FlowCheckbox(focusSection, "Patient Treasure Notification", onLiveChange)
    addon.bagAlertsCheckbox = ui.FlowCheckbox(focusSection, "Bag Monitor / Alert", onLiveChange)
    addon.lowBagBox = ui.FlowEditBox(focusSection, "Low Bag Threshold:", 190, onLiveChange)

    local audioSection = ui.FlowSection(root, "Audio")
    addon.enhancedSoundsCheckbox = ui.FlowCheckbox(audioSection, "Fishing Focused Audio", onLiveChange)
    addon.audioLingerBox = ui.FlowEditBox(audioSection, "Audio Linger After Catch (s):", 260, onLiveChange)
end

local function BuildTackleTab(tacklePage, ui, createTackleItemDropBox, onLiveChange)
    local root = ui.FlowRoot(tacklePage, 12)

    ui.FlowNote(root, "Tackle is automatically applied during pre-casting in this order, "
        .. "if selected/enabled: raft (if swimming), fishing pole, underlight mode equip, bobber, oversized bobber.")
    ui.FlowRowHost(root, 5)

    ui.FlowTitle(root, "Raft")
    addon.raftSelector = ui.FlowToySelector(root, "Selected Raft:", 320, function()
        return BuildOwnedToyOptions(addon.const.raftToyItemIDs, "No Raft")
    end, onLiveChange)
    addon.raftApplyButton = ui.FlowSecureToyActionButton(root, 160, "Apply Raft")
    ui.FlowRowHost(root, 6)

    ui.FlowTitle(root, "Bobber")
    addon.bobberSelector = ui.FlowToySelector(root, "Selected Bobber:", 320, function()
        return BuildOwnedToyOptions(addon.const.bobberToyItemIDs, "Standard Bobber")
    end, onLiveChange)
    addon.oversizedBobberCheckbox = ui.FlowCheckbox(root, "Use oversized bobber", onLiveChange)
    addon.bobberApplyButton = ui.FlowSecureToyActionButton(root, 160, "Apply Bobber")
    ui.FlowRowHost(root, 6)

    ui.FlowTitle(root, "Rods & Poles")
    local columns = ui.FlowColumns(root, 2)
    local leftColumn = columns[1]
    local rightColumn = columns[2]

    local poleLabelHost = ui.FlowRowHost(leftColumn, 20)
    local poleLabel = poleLabelHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    poleLabel:SetPoint("TOPLEFT", poleLabelHost, "TOPLEFT", 0, -2)
    poleLabel:SetText("Fishing Pole:")
    local poleBoxHost = ui.FlowRowHost(leftColumn, 56)
    addon.fishingPoleBox = createTackleItemDropBox(poleBoxHost, 0, -2, nil, function()
        RefreshUnderlightConfigControls()
        RefreshTackleEquippedPoleHighlights()
        if onLiveChange then
            onLiveChange()
        end
    end)
    ui.FlowNote(leftColumn, "Drag a fishing pole from your bags into this box.")

    local underlightLabelHost = ui.FlowRowHost(rightColumn, 20)
    local underlightLabel = underlightLabelHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    underlightLabel:SetPoint("TOPLEFT", underlightLabelHost, "TOPLEFT", 0, -2)
    underlightLabel:SetText("Underlight Angler:")
    local underlightBoxHost = ui.FlowRowHost(rightColumn, 56)
    addon.underlightAnglerBox = createTackleItemDropBox(underlightBoxHost, 0, -2, nil, function()
        RefreshUnderlightConfigControls()
        RefreshTackleEquippedPoleHighlights()
        if onLiveChange then
            onLiveChange()
        end
    end, {
        validateItemID = IsUnderlightAnglerItemID,
    })
    -- This acts as a spacer (text alpha is set to transparent) to keep layout the same as the left column
    local hiddenUnderlightNote = ui.FlowNote(rightColumn, "Drag a fishing pole from your bags into this box.")
    if hiddenUnderlightNote.label then
        hiddenUnderlightNote.label:SetAlpha(0)
    end

    ui.FlowRowHost(root, 6)
    addon.underlightAnglerModeSelector = ui.FlowDropdown(root, "Underlight Angler Mode:", 320, BuildUnderlightModeOptions, function()
        local selectedMode = NormalizeUnderlightMode(addon.underlightAnglerModeSelector and addon.underlightAnglerModeSelector:GetText())
        if addon.db then
            addon.db.underlightAnglerMode = selectedMode
            local selectedUnderlight = addon.underlightAnglerBox and tonumber(addon.underlightAnglerBox:GetText()) or nil
            if selectedUnderlight and selectedUnderlight > 0 and IsUnderlightAnglerItemID(selectedUnderlight) then
                addon.db.selectedUnderlightAngler = selectedUnderlight
            end
        end

        if addon.fishing then
            if addon.fishing.SyncConfiguredPoleForCurrentState then
                addon.fishing.SyncConfiguredPoleForCurrentState("config-underlight-mode-change")
            elseif addon.fishing.MaybeEquipConfiguredUnderlight then
                addon.fishing.MaybeEquipConfiguredUnderlight("config-underlight-mode-change")
            end
        end

        if onLiveChange then
            onLiveChange()
        end
    end)

    RefreshUnderlightConfigControls()
    RefreshTackleEquippedPoleHighlights()
end

local function BuildModesTab(modesPage, ui, onLiveChange)
    local root = ui.FlowRoot(modesPage, 12)

    local castingSection = ui.FlowSection(root, "Casting Triggers")
    addon.modeDoubleRightClickCheckbox = ui.FlowCheckbox(castingSection, "Right double click", onLiveChange)
    addon.modeSingleRightClickConfigCheckbox = ui.FlowCheckbox(castingSection, "Single right click (when this window is open)", onLiveChange)
    addon.modeHotkeyCheckbox = ui.FlowCheckboxWithNote(
        castingSection,
        "Keybinding",
        "Set the key in Keybindings > DreamFisher.",
        onLiveChange)

    addon.enableHookedLootCheckbox = ui.FlowCheckboxWithNote(
        castingSection,
        "Use right click and/or hotkey to reel in the fish",
        "Requires some setup in Game Menu > Options: \n"
        .. "1. Turn on \"Enable Interact Key\" (Options > Controls).\n"
        .. "2. Set a keybinding (Keybindings > DreamFisher).\n"
        .. "3. Ensure another addon does not try to control interactions while fishing.",
        onLiveChange)

    addon.escapeCloseCheckbox = ui.FlowCheckbox(root, "Escape closes this window", onLiveChange)
end

local function BuildBuffsTab(buffsPage, ui, createBuffItemDropBox, onLiveChange)
    local root = ui.FlowRoot(buffsPage, 12)
    ui.FlowNote(root, "Drag items from your bags into the slots below.\n\n"
        .. "Buffs are automatically applied during pre-casting.\n"
        .. "Each category is processed in the order below.\n"
        .. "Items within a category are prioritized in the order of the slots.")
    ui.FlowRowHost(root, 15)
    local buffRoot = root

    addon.buffItemControls = {}
    local slotsPerRow = 5
    local rowHeight = 54
    local columnWidth = 92
    local boxStartX = 36
    local rowSpecs = {
        { title = "Food/Drink", expectedCategory = "food_drink" },
        { title = "Lure", expectedCategory = "lure" },
        { title = "Bait", expectedCategory = "bait" },
        { title = "Other", expectedCategory = "other_consumable" },
        { title = "Other", expectedCategory = "other_consumable" },
    }

    local function CreateEnabledCheckbox(parent, x, y, onToggle)
        local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        checkbox:SetSize(24, 24)
        checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        checkbox:SetChecked(true)
        checkbox:SetScript("OnClick", function(self)
            onToggle(self:GetChecked() and true or false)
        end)

        return {
            SetChecked = function(_, value)
                checkbox:SetChecked(value and true or false)
            end,
            GetChecked = function()
                return checkbox:GetChecked() and true or false
            end,
            SetEnabled = function(_, enabled)
                if enabled then
                    checkbox:Enable()
                    checkbox:SetAlpha(1)
                else
                    checkbox:Disable()
                    checkbox:SetAlpha(0.45)
                end
            end,
        }
    end

    local maxRows = math.min(#rowSpecs, math.ceil(maxBuffSlots / slotsPerRow))
    for row = 1, maxRows do
        local rowSpec = rowSpecs[row]
        if row < maxRows then
            ui.FlowTitle(buffRoot, rowSpec.title)
        end
        local rowHost = ui.FlowRowHost(buffRoot, rowHeight)

        for col = 1, slotsPerRow do
            local index = ((row - 1) * slotsPerRow) + col
            if index <= maxBuffSlots then
                local baseX = boxStartX + ((col - 1) * columnWidth)
                local itemBox = createBuffItemDropBox(rowHost, baseX, -8, nil, onLiveChange)
                itemBox.slotIndex = index
                if itemBox.SetExpectedCategory then
                    itemBox:SetExpectedCategory(rowSpec.expectedCategory)
                end

                local enabledCheckbox = CreateEnabledCheckbox(rowHost, baseX - 26, -20, function(isChecked)
                    local control = addon.buffItemControls[index]
                    if control then
                        control.desiredEnabled = isChecked and true or false

                        if addon.db then
                            if type(addon.db.buffItems) ~= "table" then
                                addon.db.buffItems = {}
                            end
                            local persisted = addon.db.buffItems[index]
                            if type(persisted) ~= "table" then
                                persisted = {}
                                addon.db.buffItems[index] = persisted
                            end
                            persisted.enabled = control.desiredEnabled
                        end
                    end
                    if itemBox.SetEnabledForPreCast then
                        itemBox:SetEnabledForPreCast(isChecked)
                    end
                    if onLiveChange then
                        onLiveChange()
                    end
                end)

                addon.buffItemControls[index] = {
                    itemBox = itemBox,
                    enabledCheckbox = enabledCheckbox,
                    expectedCategory = rowSpec.expectedCategory,
                    desiredEnabled = (type(addon.db) == "table"
                        and type(addon.db.buffItems) == "table"
                        and type(addon.db.buffItems[index]) == "table")
                        and (addon.db.buffItems[index].enabled ~= false)
                        or true,
                }

                itemBox.onItemPresenceChanged = function(_, hasItem)
                    local control = addon.buffItemControls[index]
                    if not control then
                        return
                    end

                    if control.enabledCheckbox and control.enabledCheckbox.SetEnabled then
                        control.enabledCheckbox:SetEnabled(hasItem)
                    end

                    if not hasItem then
                        if itemBox.SetEnabledForPreCast then
                            itemBox:SetEnabledForPreCast(false)
                        end
                    else
                        if itemBox.SetEnabledForPreCast then
                            itemBox:SetEnabledForPreCast(control.desiredEnabled ~= false)
                        end
                    end
                end
            end
        end

        if row < (maxRows - 1) then
            ui.FlowRowHost(buffRoot, 20)
        end
    end
end

-- Create and return the config panel frame
function config.CreateConfigPanel()
    if addon.frames.config then
        return addon.frames.config
    end

    local aceGUIInstance = TryGetAceGUI()
    if not aceGUIInstance then
        return nil
    end

    local panel = BuildPanelShell(aceGUIInstance)

    addon.frames.config = panel
    SyncEscapeCloseRegistration()

    local tabs = BuildTabs(panel, aceGUIInstance)
    local tackleItemLastKnownCount = {}
    local tackleItemLastUseAt = {}

    local function CreateBuffItemDropBox(parent, x, y, label, onLiveChange)
        return addon.ui.CreateBuffItemDropBox({
            buffItemLastKnownCount = buffItemLastKnownCount,
            buffItemLastUseAt = buffItemLastUseAt,
            getCachedItemCount = function(itemID)
                if not buffBagCountSnapshot then
                    return nil
                end
                return buffBagCountSnapshot[itemID] or 0
            end,
            getDragState = function()
                return uiBuffCursorDragState
            end,
            setDragState = function(value)
                uiBuffCursorDragState = value
            end,
        }, parent, x, y, label, onLiveChange)
    end

    local function CreateTackleItemDropBox(parent, x, y, label, onLiveChange, options)
        local validateItemID = options and options.validateItemID or nil
        local box = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
        box:SetSize(48, 48)
        box:SetPoint("TOPLEFT", x, y)
        box:RegisterForClicks("AnyUp")
        box:RegisterForDrag("LeftButton")

        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(box)
        bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)

        local border = box:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        border:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
        border:SetColorTexture(0.42, 0.42, 0.42, 0)

        local inner = box:CreateTexture(nil, "ARTWORK")
        inner:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
        inner:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
        inner:SetColorTexture(0.08, 0.08, 0.08, 1)

        box.icon = box:CreateTexture(nil, "OVERLAY")
        box.icon:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
        box.icon:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        box.icon:SetTexture(nil)

        box.itemID = nil
        box.textValue = ""
        box.isEquippedHighlight = false

        function box:SetHighlightedAsEquipped(active)
            self.isEquippedHighlight = active and true or false
            if self.isEquippedHighlight then
                border:SetColorTexture(0.9, 0.8, 0.2, 0.95)
            else
                border:SetColorTexture(0.42, 0.42, 0.42, 0)
            end
        end

        local function IsCursorHoldingItem()
            if type(GetCursorInfo) ~= "function" then
                return false
            end
            local cursorType = GetCursorInfo()
            return cursorType == "item"
        end

        local function IsItemAccepted(itemID)
            local numeric = tonumber(itemID)
            if not numeric or numeric <= 0 then
                return true
            end
            if validateItemID and (not validateItemID(numeric)) then
                return false
            end
            return true
        end

        local function WarnRejectedItem()
            if UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
                UIErrorsFrame:AddMessage("Item is not valid for this slot.", 1.0, 0.2, 0.2, 1.0)
            end
        end

        function box:SetItemID(itemID)
            local numeric = tonumber(itemID)
            if numeric and numeric > 0 and (not IsItemAccepted(numeric)) then
                self.itemID = nil
                self.textValue = ""
                self.icon:SetTexture(nil)
                return
            end
            if numeric and numeric > 0 then
                self.itemID = numeric
                self.textValue = tostring(numeric)
                if type(GetItemIcon) == "function" then
                    self.icon:SetTexture(GetItemIcon(numeric))
                else
                    self.icon:SetTexture(nil)
                end
            else
                self.itemID = nil
                self.textValue = ""
                self.icon:SetTexture(nil)
            end
        end

        function box:SetText(value)
            self:SetItemID(value)
        end

        function box:GetText()
            return self.textValue or ""
        end

        local function AssignFromCursor(self)
            if type(GetCursorInfo) ~= "function" then
                return false
            end
            local cursorType, itemID = GetCursorInfo()
            if cursorType ~= "item" or not itemID then
                return false
            end
            if not IsItemAccepted(itemID) then
                WarnRejectedItem()
                if type(ClearCursor) == "function" then
                    ClearCursor()
                end
                return false
            end
            self:SetItemID(itemID)
            if type(ClearCursor) == "function" then
                ClearCursor()
            end
            return true
        end

        box:SetScript("OnDragStart", function(self)
            if not self.itemID or self.itemID <= 0 then
                return
            end
            if type(PickupItem) == "function" then
                PickupItem(self.itemID)
                if IsCursorHoldingItem() then
                    self:SetItemID(nil)
                    if onLiveChange then
                        onLiveChange()
                    end
                end
            end
        end)

        box:SetScript("OnReceiveDrag", function(self)
            if AssignFromCursor(self) and onLiveChange then
                onLiveChange()
            end
        end)

        box:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                if AssignFromCursor(self) and onLiveChange then
                    onLiveChange()
                end
            elseif button == "RightButton" and IsShiftKeyDown() then
                self:SetItemID(nil)
                if onLiveChange then
                    onLiveChange()
                end
            end
        end)

        box:SetScript("OnEnter", function(self)
            if self.itemID and self.itemID > 0 and type(GameTooltip) == "table" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if type(GameTooltip.SetItemByID) == "function" then
                    GameTooltip:SetItemByID(self.itemID)
                else
                    GameTooltip:SetText((type(GetItemInfo) == "function" and GetItemInfo(self.itemID)) or ("item:" .. tostring(self.itemID)))
                end
                GameTooltip:Show()
            end
        end)

        box:SetScript("OnLeave", function()
            if type(GameTooltip) == "table" then
                GameTooltip:Hide()
            end
        end)

        return box
    end

    SaveLive = function()
        if suppressLiveSave then
            return
        end
        config.SaveConfig(true)
    end

    local ui = addon.ui.CreateAceWidgetAdapters(aceGUIInstance, panel)
    if not ui then
        return nil
    end

    local builtTabs = {
        focus = false,
        tackle = false,
        buffs = false,
        modes = false,
    }

    local function EnsureTabBuilt(tabName)
        if builtTabs[tabName] then
            return
        end

        suppressLiveSave = true
        if tabName == "focus" then
            BuildFocusTab(tabs.pages.focus, ui, SaveLive)
        elseif tabName == "tackle" then
            BuildTackleTab(tabs.pages.tackle, ui, CreateTackleItemDropBox, SaveLive)
        elseif tabName == "modes" then
            BuildModesTab(tabs.pages.modes, ui, SaveLive)
        elseif tabName == "buffs" then
            BuildBuffsTab(tabs.pages.buffs, ui, CreateBuffItemDropBox, SaveLive)
            panel.buffItemControls = addon.buffItemControls
        end
        suppressLiveSave = false

        builtTabs[tabName] = true

        if panel:IsShown() then
            suppressLiveSave = true
            panel.activeTab = tabName
            LoadConfigBindings()
            suppressLiveSave = false
        end
    end

    panel.HandleTabSelected = EnsureTabBuilt

    suppressLiveSave = true
    EnsureTabBuilt("focus")
    suppressLiveSave = false

    UpdateToyApplyButtons()

    local function ShowCurrentActiveTab()
        local selectedTab = panel.activeTab or "focus"
        EnsureTabBuilt(selectedTab)
        tabs.SelectTab(selectedTab)
        tabs.ShowTab(selectedTab)
    end

    local function HandlePanelShow()
        UpdateConfigUI()
        SyncEscapeCloseRegistration()
        ShowCurrentActiveTab()
        RefreshTackleEquippedPoleHighlights()
        SetTackleHighlightAutoRefreshEnabled(true)
    end

    local function HandlePanelHide()
        SetTackleHighlightAutoRefreshEnabled(false)
        if not suppressLiveSave then
            config.SaveConfig(true)
        end
    end

    local function BindPanelLifecycle()
        panel:HookScript("OnShow", HandlePanelShow)
        panel:HookScript("OnHide", HandlePanelHide)
    end

    BindPanelLifecycle()
    tabs.ShowTab("focus")
    tabs.SelectTab("focus")
    return panel
end

-- Update config module exports
config.UpdateConfigUI = UpdateConfigUI
