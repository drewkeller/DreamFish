local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

local globalDB, profileDB, charDB
local function Initialize()
    globalDB = ns.FishingDB.global
    profileDB = ns.FishingDB.profile
    charDB = ns.FishingDB.char
end
ns.FishingInitializers = ns.FishingInitializers or {}
table.insert(ns.FishingInitializers, Initialize)

local function Trace(msg)
    if DreamFish.db.profile.debugMode then
        DreamFish:Print("|cFF999999[Oversize]|r ", msg)
    end
end

local function GetOversizedBobberAuraRemainingSeconds()
    if not (ns.FishingDB and ns.GetAuraBySpellID) then
        return nil
    end

    local known = ns.fishing.const
        and type(ns.fishing.const.knownBuffItems) == "table"
        and ns.fishing.const.knownBuffItems[ns.fishing.const.oversizedBobberItemID]
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

    local toyID = ns.fishing.const and ns.fishing.const.oversizedBobberItemID or 0
    local hasBobberSelected = profileDB.useOversizedBobber
    local hasToy = hasBobberSelected and DreamFish:IsToyOwned(toyID) or false
    local isReady = hasToy and DreamFish:IsItemReadyForUse(toyID)
    local auraRemaining = hasToy and GetOversizedBobberAuraRemainingSeconds() or nil
    local castLead = ns.fishing.const.maxFishingCastSeconds + ns.fishing.const.buffPreRefreshSafetySeconds
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
        Trace("Oversize bobber toy on cooldown: " .. DreamFish:GetDebugCooldownText(toyID))
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
