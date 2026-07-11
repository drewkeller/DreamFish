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
local ownedToyItemCache = {}
local IsLikelyFishingPoleItem
local OVERSIZED_BOBBER_ITEM_ID = 202207
local HOTKEY_CLICK_BINDING = "CLICK DreamFisherSecureFishingButton:RightButton"
local tacklePoleUI = {}
local tackleToyUI = {}

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

local function NormalizeLegacyPoleMode(mode)
    local modeText = type(mode) == "string" and mode or ""
    if modeText == "disabled" or modeText == "always_except_fishing" or modeText == "lock_underlight" then
        return modeText
    end
    return "disabled"
end

local function NormalizePoleSelection(value, validateItemID)
    local itemID = nil
    local isChecked = false

    if type(value) == "table" then
        itemID = IsPositiveItemID(value.itemID)
        isChecked = value.isChecked ~= false
    else
        itemID = IsPositiveItemID(value)
        isChecked = itemID ~= nil
    end

    if itemID and validateItemID and (not validateItemID(itemID)) then
        itemID = nil
    end
    if not itemID then
        isChecked = false
    end

    return {
        isChecked = isChecked and true or false,
        itemID = itemID,
    }
end

local function NormalizeTackleConfigValues()
    if not addon.db then
        return
    end

    local hadStructuredPrimary = type(addon.db.selectedFishingPole) == "table"
    local hadStructuredUnderlight = type(addon.db.selectedUnderlightAngler) == "table"
    local legacyMode = NormalizeLegacyPoleMode(addon.db.underlightAnglerMode)

    addon.db.selectedFishingPole = NormalizePoleSelection(addon.db.selectedFishingPole)
    addon.db.selectedUnderlightAngler = NormalizePoleSelection(addon.db.selectedUnderlightAngler, IsUnderlightAnglerItemID)

    if (not hadStructuredPrimary) and (not hadStructuredUnderlight) then
        if legacyMode == "lock_underlight" then
            addon.db.selectedFishingPole.isChecked = false
            addon.db.selectedUnderlightAngler.isChecked = addon.db.selectedUnderlightAngler.itemID ~= nil
        elseif legacyMode == "always_except_fishing" then
            addon.db.selectedFishingPole.isChecked = addon.db.selectedFishingPole.itemID ~= nil
            addon.db.selectedUnderlightAngler.isChecked = addon.db.selectedUnderlightAngler.itemID ~= nil
        else
            addon.db.selectedFishingPole.isChecked = addon.db.selectedFishingPole.itemID ~= nil
            addon.db.selectedUnderlightAngler.isChecked = false
        end
    end
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

function tacklePoleUI.GetProfessionSlotItemID()
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

function tacklePoleUI.GetEquippedItemIDs()
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

function tacklePoleUI.GetEquippedFishingPoleItemID()
    local equipped = tacklePoleUI.GetEquippedItemIDs()
    for itemID, _ in pairs(equipped) do
        if IsLikelyFishingPoleItem(itemID) and not IsUnderlightAnglerItemID(itemID) then
            return itemID
        end
    end
    return nil
end

function tacklePoleUI.IsUnderlightEquipped()
    local underlightID = GetUnderlightItemID()
    local equipped = tacklePoleUI.GetEquippedItemIDs()
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

local function RefreshUnderlightConfigControls()
    local configuredFishingPoleID = addon.fishingPoleBox and tonumber(addon.fishingPoleBox:GetText()) or nil
    local hasFishingPole = configuredFishingPoleID and configuredFishingPoleID > 0 and IsItemAvailableForConfig(configuredFishingPoleID)
    local configuredUnderlightID = addon.underlightAnglerBox and tonumber(addon.underlightAnglerBox:GetText()) or nil
    local hasUnderlight = configuredUnderlightID and configuredUnderlightID > 0 and IsItemAvailableForConfig(configuredUnderlightID)

    if addon.fishingPoleEquipCheckbox then
        if addon.fishingPoleEquipCheckbox.SetEnabled then
            addon.fishingPoleEquipCheckbox:SetEnabled(hasFishingPole)
        end
        if not hasFishingPole then
            addon.fishingPoleEquipCheckbox:SetChecked(false)
        end
    end
    if addon.underlightAnglerEquipCheckbox then
        if addon.underlightAnglerEquipCheckbox.SetEnabled then
            addon.underlightAnglerEquipCheckbox:SetEnabled(hasUnderlight)
        end
        if not hasUnderlight then
            addon.underlightAnglerEquipCheckbox:SetChecked(false)
        end
    end
end

function tacklePoleUI.GetMainHandItemID()
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

function tacklePoleUI.GetActiveEquippedTacklePoleItemID()
    local underlightID = GetUnderlightItemID()
    if IsItemEquipped(underlightID) then
        return underlightID
    end

    local professionItemID = tacklePoleUI.GetProfessionSlotItemID()
    if professionItemID and professionItemID > 0 then
        return professionItemID
    end

    local mainHandItemID = tacklePoleUI.GetMainHandItemID()
    if mainHandItemID and mainHandItemID > 0 then
        return mainHandItemID
    end

    return nil
end

function tacklePoleUI.RefreshTackleEquippedPoleHighlights()
    if not addon.fishingPoleBox and not addon.underlightAnglerBox then
        return
    end

    local activeEquippedPoleItemID = tacklePoleUI.GetActiveEquippedTacklePoleItemID()

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

local GetProfessionSlotItemID = tacklePoleUI.GetProfessionSlotItemID
local GetEquippedItemIDs = tacklePoleUI.GetEquippedItemIDs
local GetEquippedFishingPoleItemID = tacklePoleUI.GetEquippedFishingPoleItemID
local IsUnderlightEquipped = tacklePoleUI.IsUnderlightEquipped
local GetMainHandItemID = tacklePoleUI.GetMainHandItemID
local GetActiveEquippedTacklePoleItemID = tacklePoleUI.GetActiveEquippedTacklePoleItemID
local RefreshTackleEquippedPoleHighlights = tacklePoleUI.RefreshTackleEquippedPoleHighlights

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
                        tacklePoleUI.RefreshTackleEquippedPoleHighlights()
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

local function GetPerfNowMs()
    if type(debugprofilestop) == "function" then
        return debugprofilestop()
    end
    if type(GetTimePreciseSec) == "function" then
        return GetTimePreciseSec() * 1000
    end
    if type(GetTime) == "function" then
        return GetTime() * 1000
    end
    return 0
end

local function IsConfigPerfDebugEnabled()
    return addon
        and addon.db
        and addon.db.debugMode
        and addon.db.debugState
        and addon.DebugMessage
end

function tackleToyUI.IsToyOwned(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return false
    end

    local cached = ownedToyItemCache[numeric]
    if cached ~= nil then
        return cached
    end

    local owned = (type(PlayerHasToy) ~= "function") or PlayerHasToy(numeric)
    ownedToyItemCache[numeric] = owned and true or false
    return ownedToyItemCache[numeric]
end

function tackleToyUI.IsItemReadyForUse(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 or type(GetItemCooldown) ~= "function" then
        return true
    end

    local start, duration, enabled = GetItemCooldown(numeric)
    if enabled == 0 then
        return false
    end

    start = tonumber(start) or 0
    duration = tonumber(duration) or 0
    if start <= 0 or duration <= 0 then
        return true
    end

    local now = (type(GetTime) == "function") and GetTime() or 0
    return (start + duration) <= (now + 0.05)
end

function tackleToyUI.ResolveBobberApplyAction()
    local selectedToyID = addon.bobberSelector and tonumber(addon.bobberSelector:GetText()) or nil
    if not selectedToyID or selectedToyID <= 0 then
        return nil, "Apply Bobber (none)", false
    end

    if tackleToyUI.IsItemReadyForUse(selectedToyID) then
        return selectedToyID, "Apply Bobber", true
    end

    local oversizedEnabled = addon.db and addon.db.useOversizedBobber
    if oversizedEnabled
        and selectedToyID ~= OVERSIZED_BOBBER_ITEM_ID
        and tackleToyUI.IsToyOwned(OVERSIZED_BOBBER_ITEM_ID)
        and tackleToyUI.IsItemReadyForUse(OVERSIZED_BOBBER_ITEM_ID) then
        return OVERSIZED_BOBBER_ITEM_ID, "Oversize Bobber", true
    end

    return selectedToyID, "Apply Bobber", false
end

local IsToyOwned = tackleToyUI.IsToyOwned
local IsItemReadyForUse = tackleToyUI.IsItemReadyForUse
local ResolveBobberApplyAction = tackleToyUI.ResolveBobberApplyAction

local function BuildOwnedToyOptions(candidateIDs, includeDefaultLabel)
    local defaultKey = tostring(includeDefaultLabel or "")
    local candidateKey = (type(candidateIDs) == "table") and candidateIDs or "__non_table__"

    local cacheByCandidate = ownedToyOptionsCache[candidateKey]
    if not cacheByCandidate then
        cacheByCandidate = {}
        ownedToyOptionsCache[candidateKey] = cacheByCandidate
    end

    local cached = cacheByCandidate[defaultKey]
    if cached then
        return cached
    end

    local options = {}
    local seen = {}

    if type(includeDefaultLabel) == "string" and includeDefaultLabel ~= "" then
        table.insert(options, {
            value = 0,
            label = includeDefaultLabel,
        })
    end

    if type(candidateIDs) ~= "table" then
        return options
    end

    for _, toy in ipairs(candidateIDs) do
        local numeric = tonumber(type(toy) == "table" and toy.id or toy)
        local name = type(toy) == "table" and toy.name or nil
        if numeric and numeric > 0 and not seen[numeric] then
            seen[numeric] = true
            if IsToyOwned(numeric) then
                table.insert(options, {
                    value = numeric,
                    label = (type(name) == "string" and name ~= "") and name or ("item:" .. tostring(numeric)),
                })
            end
        end
    end

    cacheByCandidate[defaultKey] = options
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
        singleRightClick = ResolveBool(dbModes.singleRightClick, defaultsModes.singleRightClick),
        castHotkey = ResolveBool(dbModes.castHotkey, defaultsModes.castHotkey),
    }
    return modes
end

local function GetConfiguredHotkeyBinding()
    if type(GetBindingKey) ~= "function" then
        return ""
    end

    local boundKeys = { GetBindingKey(HOTKEY_CLICK_BINDING) }
    for _, key in ipairs(boundKeys) do
        if type(key) == "string" and key ~= "" then
            return key
        end
    end

    return ""
end

local function ApplyConfiguredHotkeyBinding(keyText)
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false
    end
    if type(SetBinding) ~= "function" and type(SetBindingClick) ~= "function" then
        return false
    end

    local boundKeys = (type(GetBindingKey) == "function") and { GetBindingKey(HOTKEY_CLICK_BINDING) } or {}
    for _, key in ipairs(boundKeys) do
        if type(key) == "string" and key ~= "" and type(SetBinding) == "function" then
            pcall(SetBinding, key, nil)
        end
    end

    local desiredKey = type(keyText) == "string" and keyText:match("^%s*(.-)%s*$") or ""
    if desiredKey ~= "" then
        if type(SetBindingClick) == "function" then
            pcall(SetBindingClick, desiredKey, "DreamFisherSecureFishingButton", "RightButton")
        elseif type(SetBinding) == "function" then
            pcall(SetBinding, desiredKey, HOTKEY_CLICK_BINDING)
        end
    end

    if type(SaveBindings) == "function" and type(GetCurrentBindingSet) == "function" then
        pcall(SaveBindings, GetCurrentBindingSet())
    end

    return true
end

local function LoadTackleBindings(isTackleActive)
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
    local selectedFishingPoleConfig = type(addon.db.selectedFishingPole) == "table"
        and addon.db.selectedFishingPole
        or { isChecked = false, itemID = addon.db.selectedFishingPole }
    local selectedFishingPole = selectedFishingPoleConfig.itemID or fishingPoleFallback or nil
    if isTackleActive and addon.fishingPoleBox then
        local desiredPoleText = tostring(selectedFishingPole or "")
        if addon.fishingPoleBox:GetText() ~= desiredPoleText then
            addon.fishingPoleBox:SetText(desiredPoleText)
        end
    end
    if isTackleActive and addon.fishingPoleEquipCheckbox then
        addon.fishingPoleEquipCheckbox:SetChecked(selectedFishingPoleConfig.isChecked and selectedFishingPole ~= nil)
    end

    local underlightID = GetUnderlightItemID()
    local selectedUnderlightConfig = type(addon.db.selectedUnderlightAngler) == "table"
        and addon.db.selectedUnderlightAngler
        or { isChecked = false, itemID = addon.db.selectedUnderlightAngler }
    local selectedUnderlight = selectedUnderlightConfig.itemID
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
    if isTackleActive and addon.underlightAnglerEquipCheckbox then
        addon.underlightAnglerEquipCheckbox:SetChecked(selectedUnderlightConfig.isChecked and selectedUnderlight ~= nil)
    end

    if isTackleActive then
        RefreshUnderlightConfigControls()
        RefreshTackleEquippedPoleHighlights()
    end

    UpdateToyApplyButtons()
end

local function SaveTackleBindings()
    if addon.oversizedBobberCheckbox then
        addon.db.useOversizedBobber = addon.oversizedBobberCheckbox:GetChecked()
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
        local itemID = (selectedFishingPole and selectedFishingPole > 0) and selectedFishingPole or nil
        addon.db.selectedFishingPole = {
            isChecked = (addon.fishingPoleEquipCheckbox and addon.fishingPoleEquipCheckbox:GetChecked()) and (itemID ~= nil) or false,
            itemID = itemID,
        }
    end
    if addon.underlightAnglerBox then
        local selectedUnderlight = tonumber(addon.underlightAnglerBox:GetText())
        if selectedUnderlight and selectedUnderlight > 0 and IsUnderlightAnglerItemID(selectedUnderlight) then
            addon.db.selectedUnderlightAngler = {
                isChecked = (addon.underlightAnglerEquipCheckbox and addon.underlightAnglerEquipCheckbox:GetChecked()) and true or false,
                itemID = selectedUnderlight,
            }
        else
            addon.db.selectedUnderlightAngler = {
                isChecked = false,
                itemID = nil,
            }
        end
    end

    if not IsItemAvailableForConfig(GetUnderlightItemID()) then
        addon.db.selectedUnderlightAngler = {
            isChecked = false,
            itemID = nil,
        }
    end

    NormalizeTackleConfigValues()

    if addon.fishing and addon.fishing.MaybeEquipConfiguredUnderlight then
        addon.fishing.MaybeEquipConfiguredUnderlight("config-save")
    end

    if addon.uiFocus and addon.uiFocus.RefreshFocusFadeState then
        addon.uiFocus.RefreshFocusFadeState()
    end

    UpdateToyApplyButtons()
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
                    local quantity = addon.utils and addon.utils.ContainerItemCount and addon.utils.ContainerItemCount(bag, slot) or 1
                    counts[itemID] = (counts[itemID] or 0) + math.max(1, tonumber(quantity) or 1)
                end
            end
        end

        local reagentSlots = addon.utils and addon.utils.ContainerNumSlots and addon.utils.ContainerNumSlots(5) or 0
        if reagentSlots and reagentSlots > 0 then
            for slot = 1, reagentSlots do
                local itemID = addon.utils and addon.utils.ContainerItemID and addon.utils.ContainerItemID(5, slot) or nil
                if itemID then
                    local quantity = addon.utils and addon.utils.ContainerItemCount and addon.utils.ContainerItemCount(5, slot) or 1
                    counts[itemID] = (counts[itemID] or 0) + math.max(1, tonumber(quantity) or 1)
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
    if isFocusActive and addon.focusedAudioCheckbox then
        addon.focusedAudioCheckbox:SetChecked(addon.db.focusedAudio)
    end
    if isFocusActive and addon.focusedVisualsCheckbox then
        addon.focusedVisualsCheckbox:SetChecked(addon.db.focusedVisuals)
    end
    if isFocusActive and addon.focusedVisualsLingerBox then
        addon.focusedVisualsLingerBox:SetText(tostring(addon.db.focusedVisualsLinger or defaults.focusedVisualsLinger))
    end
    if isFocusActive and addon.treasureAlertsCheckbox then
        addon.treasureAlertsCheckbox:SetChecked(addon.db.treasureAlerts)
    end
    if isFocusActive and addon.bagAlertsCheckbox then
        addon.bagAlertsCheckbox:SetChecked(addon.db.bagAlerts)
    end
    if isModesActive and addon.escapeCloseCheckbox then
        addon.escapeCloseCheckbox:SetChecked(addon.db.closeWindowOnEscape)
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
            if control.itemBox and control.itemBox.UpdateCountDisplay then
                control.itemBox:UpdateCountDisplay()
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
        addon.audioLingerBox:SetText(tostring(addon.db.focusedAudioLinger or defaults.focusedAudioLinger))
    end
    if isModesActive and addon.modeDoubleRightClickCheckbox then
        local modes = GetCastingModesForConfig()
        addon.modeDoubleRightClickCheckbox:SetChecked(modes.doubleRightClick)
        addon.modeSingleRightClickConfigCheckbox:SetChecked(modes.singleRightClick)
        addon.modeHotkeyCheckbox:SetChecked(modes.castHotkey)
        if addon.castHotkeyKeybinding and addon.castHotkeyKeybinding.SetText then
            addon.castHotkeyKeybinding:SetText(GetConfiguredHotkeyBinding())
        end
    end
    if isModesActive and addon.enableHookedLootCheckbox then
        addon.enableHookedLootCheckbox:SetChecked(addon.db.easyStrike)
    end

    LoadTackleBindings(isTackleActive)
end

local function SaveConfigBindings()
    if not addon.db then
        return nil
    end

    local previouslyActiveBuffItems = CollectActiveBuffItemIDs(addon.db.buffItems)

    if addon.lowBagBox then
        addon.db.lowBagThreshold = addon.Clamp(tonumber(addon.lowBagBox:GetText()) or defaults.lowBagThreshold, 0, 20)
    else
        addon.db.lowBagThreshold = addon.Clamp(tonumber(addon.db.lowBagThreshold) or defaults.lowBagThreshold, 0, 20)
    end

    if addon.audioLingerBox then
        addon.db.focusedAudioLinger = addon.Clamp(tonumber(addon.audioLingerBox:GetText()) or defaults.focusedAudioLinger, 0, 60)
    else
        addon.db.focusedAudioLinger = addon.Clamp(tonumber(addon.db.focusedAudioLinger) or defaults.focusedAudioLinger, 0, 60)
    end

    if addon.autoLootCheckbox then
        addon.db.autoLoot = addon.autoLootCheckbox:GetChecked()
    end
    if addon.focusedAudioCheckbox then
        addon.db.focusedAudio = addon.focusedAudioCheckbox:GetChecked()
    end
    if addon.focusedVisualsCheckbox then
        local newFocusedVisuals = addon.focusedVisualsCheckbox:GetChecked()
        local oldFocusedVisuals = addon.db.focusedVisuals and true or false
        addon.db.focusedVisuals = newFocusedVisuals

        if oldFocusedVisuals and not newFocusedVisuals and addon.uiFocus and addon.uiFocus.FadeInUI then
            addon.uiFocus.FadeInUI()
        end
    end
    if addon.focusedVisualsLingerBox then
        addon.db.focusedVisualsLinger = addon.Clamp(tonumber(addon.focusedVisualsLingerBox:GetText()) or defaults.focusedVisualsLinger, 0, 60)
    else
        addon.db.focusedVisualsLinger = addon.Clamp(tonumber(addon.db.focusedVisualsLinger) or defaults.focusedVisualsLinger, 0, 60)
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
        singleRightClick = addon.modeSingleRightClickConfigCheckbox
            and addon.modeSingleRightClickConfigCheckbox:GetChecked()
            or ResolveBool(existingModes.singleRightClick, defaultModes.singleRightClick),
        castHotkey = addon.modeHotkeyCheckbox
            and addon.modeHotkeyCheckbox:GetChecked()
            or ResolveBool(existingModes.castHotkey, defaultModes.castHotkey),
    }
    addon.db.castingModes = modeFlags

    if addon.castHotkeyKeybinding and addon.castHotkeyKeybinding.GetText then
        ApplyConfiguredHotkeyBinding(addon.castHotkeyKeybinding:GetText())
    end

    if addon.enableHookedLootCheckbox then
        addon.db.easyStrike = addon.enableHookedLootCheckbox:GetChecked() or false
    else
        addon.db.easyStrike = addon.db.easyStrike and true or false
    end

    if addon.escapeCloseCheckbox then
        addon.db.closeWindowOnEscape = addon.escapeCloseCheckbox:GetChecked()
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

    SaveTackleBindings()

    return previouslyActiveBuffItems
end

UpdateToyApplyButtons = function()
    local function SyncButton(button, selector, baseLabel, respectCooldown)
        if not button then
            return
        end
        local toyID = selector and tonumber(selector:GetText()) or nil
        if toyID and toyID > 0 then
            button:SetAttribute("type", "toy")
            button:SetAttribute("toy", toyID)
            button:SetText(baseLabel)
            if (not respectCooldown) or IsItemReadyForUse(toyID) then
                button:Enable()
            else
                button:Disable()
            end
        else
            button:SetAttribute("toy", nil)
            button:SetText(baseLabel .. " (none)")
            button:Disable()
        end
    end

    if addon.bobberApplyButton then
        local bobberToyID, bobberLabel, bobberEnabled = ResolveBobberApplyAction()
        addon.bobberApplyButton:SetAttribute("type", "toy")
        addon.bobberApplyButton:SetAttribute("toy", bobberToyID)
        addon.bobberApplyButton:SetText(bobberLabel)
        if bobberEnabled then
            addon.bobberApplyButton:Enable()
        else
            addon.bobberApplyButton:Disable()
        end
    end

    SyncButton(addon.raftApplyButton, addon.raftSelector, "Apply Raft", false)
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

    local shouldRegister = addon.db and addon.db.closeWindowOnEscape
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

    -- 1. Movable frame: Access the underlying Blizzard Frame objects
    local blizzFrame = aceWindow.frame
    local titleBg = aceWindow.titlebg

    -- 2. Kill the restricted default AceGUI TitleRegion
    -- (This prevents the old logic from conflicting with our custom drag scripts)
    if blizzFrame and blizzFrame.GetTitleRegion then
        blizzFrame:GetTitleRegion():SetWidth(0)
        blizzFrame:GetTitleRegion():SetHeight(0)
    end

    -- 3. Enable mouse tracking on the main container frame
    blizzFrame:EnableMouse(true)
    blizzFrame:SetMovable(true)

    -- 4. Attach scripts to drag using the background
    blizzFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not self.isMoving then
            self:StartMoving()
            self.isMoving = true
        end
    end)

    blizzFrame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
            SavePanelPosition(self)
        end
    end)

    -- 5. Ensure the old title visual background still works to drag
    titleBg:EnableMouse(false) -- Allows clicks to pass through to the blizzFrame

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

        if tabName == "tackle" and UpdateToyApplyButtons then
            UpdateToyApplyButtons()
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
    addon.autoLootCheckbox = ui.FlowCheckbox(focusSection, "Temporary auto-loot", onLiveChange,
        "Enables auto-loot while fishing and returns it to your previous setting when done.")
    addon.treasureAlertsCheckbox = ui.FlowCheckbox(focusSection, "Patient Treasure notification", onLiveChange,
        "Notifies you if you catch a Patient Treasure by coloring the screen and playing a distinct sound.")
    addon.bagAlertsCheckbox = ui.FlowCheckbox(focusSection, "Bag monitor / alert", onLiveChange,
        "Monitors your bag space and alerts you when it is low.")
    addon.lowBagBox = ui.FlowEditBox(focusSection, "Threshold (slots)", 150, onLiveChange,
        "Minimum number of free bag slots before bag alerts are triggered (either normal or reagent slots).")

    local audioSection = ui.FlowSection(root, "Audio")
    addon.focusedAudioCheckbox = ui.FlowCheckbox(audioSection, "Focused audio when fishing", onLiveChange,
        "Reduces other sounds and focuses audio on fishing sounds, then restores when done fishing.")
    addon.audioLingerBox = ui.FlowEditBox(audioSection, "After catch (s)", 150, onLiveChange,
        "How long to keep the fishing audio focused after a cast is stopped. Combat or other cancellations immediately revert the audio focus.")

    local visualSection = ui.FlowSection(root, "Visual")
    addon.focusedVisualsCheckbox = ui.FlowCheckbox(visualSection, "Fade out visual elements when fishing", onLiveChange,
        "Fades out other UI frames and focuses on fishing, then restores when done fishing. Not everything can be hidden.")
    addon.focusedVisualsLingerBox = ui.FlowEditBox(visualSection, "After catch (s)", 150, onLiveChange,
        "How long to keep the visuals faded after a cast is stopped. Combat or other cancellations immediately restore the visuals.")
end

local function BuildTackleTab(tacklePage, ui, createTackleItemDropBox, onLiveChange)
    local root = ui.FlowRoot(tacklePage, 12)

    local function AttachToyApplyButtonRefresh(button)
        if not button or type(button.HookScript) ~= "function" then
            return
        end

        local function RefreshApplyButtonsSoon()
            if not UpdateToyApplyButtons then
                return
            end

            UpdateToyApplyButtons()

            if C_Timer and type(C_Timer.After) == "function" then
                local refreshDelays = { 0.12, 0.30, 0.60, 1.00 }
                for _, delaySeconds in ipairs(refreshDelays) do
                    C_Timer.After(delaySeconds, UpdateToyApplyButtons)
                end
            end
        end

        button:HookScript("OnMouseUp", RefreshApplyButtonsSoon)
    end

    local function CreateTackleEnabledCheckbox(parent, x, y, onToggle, tooltipText)
        local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        checkbox:SetSize(24, 24)
        checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        checkbox:SetChecked(true)
        checkbox:SetScript("OnClick", function(self)
            onToggle(self:GetChecked() and true or false)
        end)

        if type(tooltipText) == "string" and tooltipText ~= "" then
            checkbox:SetScript("OnEnter", function(self)
                if type(GameTooltip) ~= "table" then
                    return
                end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            checkbox:SetScript("OnLeave", function()
                if type(GameTooltip) == "table" then
                    GameTooltip:Hide()
                end
            end)
        end

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

    ui.FlowNote(root, "Tackle is automatically applied during pre-casting in this order, "
        .. "if selected/enabled: raft (if swimming), pole, bobber, oversized bobber.")

    -- Raft section
    ui.FlowRowHost(root, 20)
    --ui.FlowTitle(root, "Raft")
    addon.raftSelector = ui.FlowToySelector(root, "Raft", 320, function()
        return BuildOwnedToyOptions(addon.const.raftToyItemIDs, "No Raft")
    end, onLiveChange, "Choose the raft to be used when fishing. Applied automatically when casting the fishing line.")
    addon.raftApplyButton = ui.FlowSecureToyActionButton(root, 160, "Apply Raft",
        "Manually apply the selected raft now.")
    AttachToyApplyButtonRefresh(addon.raftApplyButton)

    -- Bobber section
    ui.FlowRowHost(root, 20)
    --ui.FlowTitle(root, "Bobber")
    addon.bobberSelector = ui.FlowToySelector(root, "Bobber", 320, function()
        return BuildOwnedToyOptions(addon.const.bobberToyItemIDs, "Standard Bobber")
    end, onLiveChange, "Choose the bobber to be used when fishing. Applied automatically when casting the fishing line.")
    addon.oversizedBobberCheckbox = ui.FlowCheckbox(root, "Use oversized bobber", onLiveChange,
        "Also apply the oversized bobber to your selected bobber (adds another click to apply it).")
    addon.bobberApplyButton = ui.FlowSecureToyActionButton(root, 160, "Apply Bobber",
        "Manually apply the selected bobber/oversized bobber now.")
    AttachToyApplyButtonRefresh(addon.bobberApplyButton)

    -- Rods & Poles section
    ui.FlowRowHost(root, 20)
    ui.FlowTitle(root, "Rods & Poles")
    local columns = ui.FlowColumns(root, 2)
    local leftColumn = columns[1]
    local rightColumn = columns[2]

    local poleLabelHost = ui.FlowRowHost(leftColumn, 20)
    local poleLabel = poleLabelHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    poleLabel:SetPoint("TOPLEFT", poleLabelHost, "TOPLEFT", 0, -2)
    poleLabel:SetText("Fishing Pole:")
    local poleBoxHost = ui.FlowRowHost(leftColumn, 56)
    addon.fishingPoleBox = createTackleItemDropBox(poleBoxHost, 26, -2, nil, function()
        RefreshUnderlightConfigControls()
        RefreshTackleEquippedPoleHighlights()
        if onLiveChange then
            onLiveChange()
        end
    end)
    addon.fishingPoleEquipCheckbox = CreateTackleEnabledCheckbox(poleBoxHost, 0, -14, function()
        if onLiveChange then
            onLiveChange()
        end
    end, "Enable this pole for equipping.")
    addon.fishingPoleBox.onItemPresenceChanged = function(_, hasItem)
        if addon.fishingPoleEquipCheckbox and addon.fishingPoleEquipCheckbox.SetEnabled then
            addon.fishingPoleEquipCheckbox:SetEnabled(hasItem)
        end
        if (not hasItem) and addon.fishingPoleEquipCheckbox then
            addon.fishingPoleEquipCheckbox:SetChecked(false)
        end
    end

    local underlightLabelHost = ui.FlowRowHost(rightColumn, 20)
    local underlightLabel = underlightLabelHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    underlightLabel:SetPoint("TOPLEFT", underlightLabelHost, "TOPLEFT", 0, -2)
    underlightLabel:SetText("Underlight Angler:")
    local underlightBoxHost = ui.FlowRowHost(rightColumn, 56)
    addon.underlightAnglerBox = createTackleItemDropBox(underlightBoxHost, 26, -2, nil, function()
        RefreshUnderlightConfigControls()
        RefreshTackleEquippedPoleHighlights()
        if onLiveChange then
            onLiveChange()
        end
    end, {
        validateItemID = IsUnderlightAnglerItemID,
    })
    addon.underlightAnglerEquipCheckbox = CreateTackleEnabledCheckbox(underlightBoxHost, 0, -14, function()
        if onLiveChange then
            onLiveChange()
        end
    end, "Enable Underlight Angler for equipping.")
    addon.underlightAnglerBox.onItemPresenceChanged = function(_, hasItem)
        if addon.underlightAnglerEquipCheckbox and addon.underlightAnglerEquipCheckbox.SetEnabled then
            addon.underlightAnglerEquipCheckbox:SetEnabled(hasItem)
        end
        if (not hasItem) and addon.underlightAnglerEquipCheckbox then
            addon.underlightAnglerEquipCheckbox:SetChecked(false)
        end
    end
    ui.FlowNote(root, "Drag a pole from your bags into the first slot to equip it.\n\n"
        .. "Modes:\n"
        .. "* Auto-swap: Check both boxes\n    (swap occurs when starting/stopping fishing)\n"
        .. "* Single-pole: Only check one box.\n"
        .. "* Manual: Leave both boxes unchecked.")

    ui.FlowRowHost(root, 20)

    RefreshUnderlightConfigControls()
    RefreshTackleEquippedPoleHighlights()
end

local function BuildModesTab(modesPage, ui, onLiveChange)
    local root = ui.FlowRoot(modesPage, 12)

    local castingSection = ui.FlowSection(root, "Casting Triggers")
    addon.modeDoubleRightClickCheckbox = ui.FlowCheckbox(castingSection, "Double right click", onLiveChange,
        "Double right-click in the world begins fishing.")
    addon.modeSingleRightClickConfigCheckbox = ui.FlowCheckbox(castingSection,
        "Single right click (when this window is open)", onLiveChange,
        "Single right-click in the world begins fishing when the DreamFisher window is open.")
    addon.modeHotkeyCheckbox = ui.FlowCheckboxWithNote(
        castingSection,
        "Hotkey",
        "",
        onLiveChange,
        nil,
        "Use a keybinding to begin fishing.")
    addon.castHotkeyKeybinding = ui.FlowKeybinding(castingSection, "", 220, onLiveChange,
        "The keybinding to use for casting the fishing line (and reeling it in, if EasyStrike is enabled).")

    local castingSection = ui.FlowSection(root, "Reeling Triggers")
    addon.enableHookedLootCheckbox = ui.FlowCheckboxWithNote(
        castingSection,
        "EasyStrike (right click anywhere or use the hotkey)",
        "Requirements:\n"
        .. "1. Turn on \"Enable Interact Key\" (Game Options > Controls).\n"
        .. "2. Set the \"Hotkey\" keybinding.\n"
        .. "3. Ensure another addon does not interfere while fishing.\n",
        onLiveChange,
        nil,
        "When the bobber indicates a bite,  right click anywhere or the hotkey to hook, play and land the fish.")

    ui.FlowRowHost(root, 40)
    addon.escapeCloseCheckbox = ui.FlowCheckbox(root, "Escape closes this window", onLiveChange,
        "Allow the Esc key to close the DreamFisher window.")
end

local function BuildBuffsTab(buffsPage, ui, createBuffItemDropBox, onLiveChange)
    local root = ui.FlowRoot(buffsPage, 12)
    ui.FlowNote(root, "Drag items from your bags into the slots below.\n\n"
        .. "Buffs are automatically applied during pre-casting.\n"
        .. "Each category is processed in the order below.\n"
        .. "Items within a category are prioritized in the order of the slots.")
    ui.FlowRowHost(root, 20)
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

    local function TryUnequipProfessionSlotItem(expectedItemID)
        local expected = tonumber(expectedItemID)
        if type(InCombatLockdown) == "function" and InCombatLockdown() then
            return false
        end
        if type(GetInventoryItemID) ~= "function" or type(PickupInventoryItem) ~= "function" then
            return false
        end

        local equipped = tonumber(GetInventoryItemID("player", 28))
        if not equipped or equipped <= 0 then
            return false
        end
        if expected and expected > 0 and equipped ~= expected then
            return false
        end

        local function CursorHasItem()
            if type(GetCursorInfo) ~= "function" then
                return false
            end
            local cursorType = GetCursorInfo()
            return cursorType == "item"
        end

        local function TryPlaceCursorItemInBags()
            local pickupFn = nil
            if C_Container and type(C_Container.PickupContainerItem) == "function" then
                pickupFn = C_Container.PickupContainerItem
            elseif type(PickupContainerItem) == "function" then
                pickupFn = PickupContainerItem
            end
            if type(pickupFn) ~= "function" then
                return false
            end

            local bagCount = NUM_BAG_SLOTS or 4
            for bag = 0, bagCount do
                local slots = addon.utils and addon.utils.ContainerNumSlots and addon.utils.ContainerNumSlots(bag) or 0
                for slot = 1, slots do
                    local slotItemID = addon.utils and addon.utils.ContainerItemID and addon.utils.ContainerItemID(bag, slot) or nil
                    if not slotItemID then
                        pcall(pickupFn, bag, slot)
                        if not CursorHasItem() then
                            return true
                        end
                    end
                end
            end

            return false
        end

        pcall(PickupInventoryItem, 28)
        if not CursorHasItem() then
            return false
        end

        if type(PutItemInBackpack) == "function" then
            pcall(PutItemInBackpack)
        end
        if CursorHasItem() then
            TryPlaceCursorItemInBags()
        end
        if CursorHasItem() and type(ClearCursor) == "function" then
            pcall(ClearCursor)
        end

        local after = tonumber(GetInventoryItemID("player", 28))
        return not after or after <= 0
    end

    local function CreateTackleItemDropBox(parent, x, y, label, onLiveChange, options)
        local validateItemID = options and options.validateItemID or nil
        local box = CreateFrame("Button", nil, parent)
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
        border:SetColorTexture(0.42, 0.42, 0.42, 0.9)

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
        box.isDragHover = false

        local function UpdateBorderVisual()
            if box.isEquippedHighlight then
                border:SetColorTexture(0.9, 0.8, 0.2, 0.95)
            elseif box.isDragHover then
                border:SetColorTexture(0.25, 0.65, 1.0, 0.95)
            else
                border:SetColorTexture(0.42, 0.42, 0.42, 0)
            end
        end

        function box:SetHighlightedAsEquipped(active)
            self.isEquippedHighlight = active and true or false
            UpdateBorderVisual()
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
            local previousItemID = self.itemID
            if numeric and numeric > 0 and (not IsItemAccepted(numeric)) then
                self.itemID = nil
                self.textValue = ""
                self.icon:SetTexture(nil)
                if self.onItemPresenceChanged then
                    self.onItemPresenceChanged(self, false)
                end
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
                if previousItemID and previousItemID > 0 then
                    TryUnequipProfessionSlotItem(previousItemID)
                end
                self.itemID = nil
                self.textValue = ""
                self.icon:SetTexture(nil)
            end

            if self.onItemPresenceChanged then
                self.onItemPresenceChanged(self, (self.itemID and self.itemID > 0) and true or false)
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
            self.isDragHover = true
            UpdateBorderVisual()
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
            self.isDragHover = IsCursorHoldingItem()
            UpdateBorderVisual()
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
            box.isDragHover = false
            UpdateBorderVisual()
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
addon._test = addon._test or {}
addon._test.SaveConfigBindings = SaveConfigBindings
