local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

local globalDB, profileDB, charDB
Fishing:RegisterOnModuleInitialize(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

local states = {
    currentBobberToyID = nil
}

Fishing:RegisterTraceSource("bobber")

local function Trace(msg)
    Fishing:Trace("bobber", msg)
end

local function GetBobberAuraRemainingSeconds(bobberToyID)
    local known = ns.Fishing.const
        and type(ns.Fishing.const.knownBuffItems) == "table"
        and ns.Fishing.const.knownBuffItems[tonumber(bobberToyID)]
        or nil
    local bobberSpellID = type(known) == "table" and tonumber(known.spellID) or nil
    if not bobberSpellID or bobberSpellID <= 0 then
        return nil
    end

    local aura = ns.GetAuraBySpellID(bobberSpellID)
    if not aura or not aura.expirationTime or aura.expirationTime <= 0 then
        return nil
    end

    return math.max(0, aura.expirationTime - GetTime())
end

local function GetBobberUseDecision()
    local toyID = tonumber(profileDB.selectedBobberToy) or nil
    if toyID == -1 then
        local readyForNewBobber = states.currentBobberToyID == nil or ns.Utils.IsCooldownReady(states.currentBobberToyID)
        if readyForNewBobber then
            toyID = ns.Utils.GetRandomOwnedToyID(ns.Fishing.const.bobberToyItemIDs, states.currentBobberToyID) or nil
            Trace("Selected a random bobber: " .. tostring(toyID) .. " was: " .. tostring(states.currentBobberToyID))
            states.currentBobberToyID = toyID
        else
            toyID = states.currentBobberToyID
        end
    end
    local hasBobberSelected = toyID and toyID > 0
    local hasToy = hasBobberSelected and ns.Utils.IsToyOwned(toyID) or false
    local bobberReady = hasToy and ns.Utils.IsCooldownReady(toyID)
    local bobberAuraRemaining = hasToy and GetBobberAuraRemainingSeconds(toyID) or nil
    local castLead = ns.Fishing.const.maxFishingCastSeconds + ns.Fishing.const.buffPreRefreshSafetySeconds
    local needsRefreshForCast = (bobberAuraRemaining == nil) or (bobberAuraRemaining <= castLead)
    local mounted = IsMounted()
    local swimming = ns.Utils.IsSwimmingOrSubmerged() == true
    local shouldApply = hasBobberSelected
        and hasToy
        and bobberReady
        and needsRefreshForCast
        and not mounted
        and not swimming

    if shouldApply then
        Trace("Bobber can be applied")
    elseif toyID and toyID == 0 then
        Trace("'Standard' bobber is selected")
    elseif not hasBobberSelected then
        Trace("No bobber toy selected or invalid ID: " .. tostring(toyID))
    elseif not hasToy then
        Trace("Bobber is not owned")
    elseif not bobberReady then
        Trace("Bobber toy on cooldown: " .. ns.Utils.GetDebugCooldownText(toyID))
    elseif not needsRefreshForCast then
        Trace("Bobber aura remaining sufficient for cast")
    elseif mounted then
        Trace("Player is mounted")
    elseif swimming then
        Trace("Player is swimming")
    else
        Trace("Bobber will not be applied for unknown reason")
    end

    return {
        toyID = toyID,
        hasToy = hasToy,
        ready = bobberReady,
        auraRemaining = bobberAuraRemaining,
        needsRefreshForCast = needsRefreshForCast,
        mounted = mounted,
        swimming = swimming,
        shouldApply = shouldApply,
    }
end

ns.precast.GetBobberUseDecision = GetBobberUseDecision
