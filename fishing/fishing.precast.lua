local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local Fishing = DreamFish:GetModule("Fishing")

function DreamFish:ResolveBobberApplyAction()
    local selectedToyID = DreamFish.addon.bobberSelector and tonumber(DreamFish.addon.bobberSelector:GetText()) or nil
    if not selectedToyID or selectedToyID <= 0 then
        return nil, "Apply Bobber (none)", false
    end

    if DreamFish:IsItemReadyForUse(selectedToyID) then
        return selectedToyID, "Apply Bobber", true
    end

    local oversizedEnabled = DreamFish.addon.db and DreamFish.addon.db.useOversizedBobber
    if oversizedEnabled
        and selectedToyID ~= ns.const.oversizedBobberItemID
        and DreamFish:IsToyOwned(ns.const.oversizedBobberItemID)
        and DreamFish:IsItemReadyForUse(ns.const.oversizedBobberItemID) then
        return ns.const.oversizedBobberItemID, "Oversize Bobber", true
    end

    return selectedToyID, "Apply Bobber", false
end

