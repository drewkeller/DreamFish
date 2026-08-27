local addonName, ns = ...
local Addon = ns.Addon
local Fishing = Addon:GetModule("Fishing")

local globalDB, profileDB, charDB
local function Initialize()
    globalDB = ns.FishingDB.global
    profileDB = ns.FishingDB.profile
    charDB = ns.FishingDB.char
end
ns.FishingInitializers = ns.FishingInitializers or {}
table.insert(ns.FishingInitializers, Initialize)

Fishing:RegisterTraceSource("bobber")

local function Trace(msg)
    Fishing:Trace("bobber", msg)
end

local function GetBobberAuraRemainingSeconds(bobberToyID)
    local known = ns.fishing.const
        and type(ns.fishing.const.knownBuffItems) == "table"
        and ns.fishing.const.knownBuffItems[tonumber(bobberToyID)]
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
    local hasBobberSelected = toyID and toyID > 0
    local hasToy = hasBobberSelected and Addon:IsToyOwned(toyID) or false
    local bobberReady = hasToy and Addon:IsCooldownReady(toyID)
    local bobberAuraRemaining = hasToy and GetBobberAuraRemainingSeconds(toyID) or nil
    local castLead = ns.fishing.const.maxFishingCastSeconds + ns.fishing.const.buffPreRefreshSafetySeconds
    local needsRefreshForCast = (bobberAuraRemaining == nil) or (bobberAuraRemaining <= castLead)
    local mounted = IsMounted()
    local swimming = IsSwimming()
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
        Trace("No bobber toy selected or invalid ID")
    elseif not hasToy then
        Trace("Bobber is not owned")
    elseif not bobberReady then
        Trace("Bobber toy on cooldown: " .. Addon:GetDebugCooldownText(toyID))
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
