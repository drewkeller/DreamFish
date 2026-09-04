local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

local globalDB, profileDB, charDB
Fishing:RegisterOnModuleInitialize(function(self)
    globalDB = self.db.global
    profileDB = self.db.profile
    charDB = self.db.char
end)

Fishing:RegisterTraceSource("oversize")

local function Trace(msg)
    Fishing:Trace("oversize", msg)
end

local function GetOversizedBobberAuraRemainingSeconds()
    if not (ns.FishingDB and ns.GetAuraBySpellID) then
        return nil
    end

    local known = ns.Fishing.const
        and type(ns.Fishing.const.knownBuffItems) == "table"
        and ns.Fishing.const.knownBuffItems[ns.Fishing.const.oversizedBobberItemID]
        or nil
    local oversizedSpellID = type(known) == "table" and tonumber(known.spellID) or nil
    if not oversizedSpellID or oversizedSpellID <= 0 then
        return nil
    end

    local aura = ns.GetAuraBySpellID(oversizedSpellID)
    if not aura or not aura.expirationTime or aura.expirationTime <= 0 then
        return nil
    end

    return math.max(0, aura.expirationTime - GetTime())
end

local function GetOversizedBobberDecision()

    local toyID = ns.Fishing.const and ns.Fishing.const.oversizedBobberItemID or 0
    local hasBobberSelected = profileDB.useOversizedBobber
    local hasToy = hasBobberSelected and ns.Utils.IsToyOwned(toyID) or false
    local isReady = hasToy and ns.Utils.IsCooldownReady(toyID)
    local auraRemaining = hasToy and GetOversizedBobberAuraRemainingSeconds() or nil
    local castLead = ns.Fishing.const.maxFishingCastSeconds + ns.Fishing.const.buffPreRefreshSafetySeconds
    local needsRefresh = (auraRemaining == nil) or (auraRemaining <= castLead)
    local mounted = IsMounted()
    local swimming = IsSwimming()
    local shouldApply = hasBobberSelected
        and hasToy
        and isReady
        and needsRefresh
        and not mounted
        and not swimming

    if shouldApply then
        Trace("Oversize bobber can be applied")
    elseif toyID and toyID == 0 then
        Trace("Oversize bobber is not configured")
    elseif not hasBobberSelected then
        Trace("Oversize bobber is not enabled")
    elseif not hasToy then
        Trace("Oversize bobber is not owned")
    elseif not isReady then
        Trace("Oversize bobber toy on cooldown: " .. ns.Utils.GetDebugCooldownText(toyID))
    elseif not needsRefresh then
        Trace("Oversize bobber aura remaining sufficient for cast")
    elseif mounted then
        Trace("Player is mounted")
    elseif swimming then
        Trace("Player is swimming")
    else
        Trace("Oversize bobber will not be applied for unknown reason")
    end

    return {
        toyID = toyID,
        hasToy = hasToy,
        ready = isReady,
        auraRemaining = auraRemaining,
        needsRefreshForCast = needsRefresh,
        mounted = mounted,
        swimming = swimming,
        shouldApply = shouldApply,
    }
end

ns.precast.GetOversizedBobberDecision = GetOversizedBobberDecision
