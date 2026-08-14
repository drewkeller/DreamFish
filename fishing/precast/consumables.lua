local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local globalDB, profileDB, charDB
local state
local function Initialize()
    globalDB = ns.FishingDB.global
    profileDB = ns.FishingDB.profile
    charDB = ns.FishingDB.char
    state = ns.fishing.state
end
ns.FishingInitializers = ns.FishingInitializers or {}
table.insert(ns.FishingInitializers, Initialize)

local function IsLureCategory(category)
    return category == "lure"
end

local function IsFishingPoleEquippedInProfessionSlot()
    if type(GetInventoryItemID) ~= "function" then
        return true
    end

    -- Some clients can return no values; capture first to avoid calling tonumber()
    -- with zero arguments.
    local ok, rawItemID = pcall(GetInventoryItemID, "player", 28)
    if not ok then
        return false
    end
    if rawItemID == nil then
        return false
    end

    local itemID = tonumber(rawItemID)
    return itemID and itemID > 0 or false
end

local function WarnMissingProfessionFishingPoleForLure()
    local now = (type(GetTime) == "function") and GetTime() or 0
    local cooldown = tonumber(state.buffMissingWarningCooldown) or 8
    local last = tonumber(state.lureMissingPoleWarningAt) or 0
    if (now - last) < cooldown then
        return
    end
    state.lureMissingPoleWarningAt = now

    local warningText = "Cannot apply lure: no fishing pole equipped in profession slot."

    if UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, warningText, 1, 0.1, 0.1, 1.0)
    end

    DreamFish:Print(warningText)
    DreamFish:PlayWarningCue()
end

GetNextCastableDueBuffItem = function()
    local excludedBuffItemIDs = {}
    local hadUnavailableDueBuff = false

    while true do
        local candidateItemID, unavailable, category = GetNextReadyDueBuffItem(excludedBuffItemIDs)
        hadUnavailableDueBuff = hadUnavailableDueBuff or unavailable

        if not candidateItemID then
            return nil, hadUnavailableDueBuff, nil
        end

        if IsLureCategory(category) and (not IsFishingPoleEquippedInProfessionSlot()) then
            WarnMissingProfessionFishingPoleForLure()
            DreamFish:Debug("Skipping lure due buff; no fishing pole equipped in profession slot")
            excludedBuffItemIDs[candidateItemID] = true
        else
            return candidateItemID, hadUnavailableDueBuff, category
        end
    end
end

