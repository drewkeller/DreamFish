local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

Fishing:RegisterTraceSource("raft")
local function Trace(msg)
    Fishing:Trace("raft", msg)
end

local function GetRaftAuraRemainingSeconds(raftToyID)
    local _, raftSpellID = C_Item.GetItemSpell(raftToyID)
    if not raftSpellID then
        return nil
    end

    local aura = ns.GetAuraBySpellID(raftSpellID)
    if not aura or not aura.expirationTime or aura.expirationTime <= 0 then
        return nil
    end

    return math.max(0, aura.expirationTime - GetTime())
end

local function IsRaftBlockedByShapeshift()
    return type(GetShapeshiftForm) == "function" and GetShapeshiftForm() > 0
end

local function GetRaftUseDecision(self)
    local toyID = tonumber(self.db.profile.selectedRaftToy) or nil
    local hasRaftSelected = toyID and toyID > 0
    local hasToy = hasRaftSelected and ns.Utils.IsToyOwned(toyID) or false
    local isReady = hasToy and ns.Utils.IsCooldownReady(toyID)
    local swimming = IsSwimming()
    local blockedByShapeshift = IsRaftBlockedByShapeshift()
    local auraRemaining = (hasToy and swimming) and GetRaftAuraRemainingSeconds(toyID) or nil
    local castLead = ns.Fishing.const.maxFishingCastSeconds + ns.Fishing.const.buffPreRefreshSafetySeconds
    if auraRemaining == nil and hasToy then
        -- If aura can't be observed while not swimming, try once more without the swim gate.
        auraRemaining = GetRaftAuraRemainingSeconds(toyID)
    end
    local needsRefresh = (auraRemaining == nil) or (auraRemaining <= castLead)

    local shouldApply = hasRaftSelected
        and hasToy
        and isReady
        and needsRefresh
        and not blockedByShapeshift
        and (swimming or auraRemaining ~= nil)

    if shouldApply then
        Trace("Raft can be applied")
    elseif toyID and toyID == 0 then
        Trace("'None' raft is selected")
    elseif not hasRaftSelected then
        Trace("No raft toy selected or invalid ID")
    elseif not hasToy then
        Trace("Raft is not owned")
    elseif not isReady then
        Trace("Raft toy on cooldown: " .. ns.Utils.GetDebugCooldownText(toyID))
    elseif blockedByShapeshift then
        Trace("Raft cannot be applied while shapeshifted")
    elseif not needsRefresh then
        Trace("Raft aura remaining sufficient for cast")
    elseif not (swimming or auraRemaining ~= nil) then
        Trace("Not swimming and no raft aura observed")
    else
        Trace("Raft will not be applied for unknown reason")
    end

    return {
        toyID = toyID,
        hasToy = hasToy,
        ready = isReady,
        swimming = swimming,
        blockedByShapeshift = blockedByShapeshift,
        auraRemaining = auraRemaining,
        needsRefreshForCast = needsRefresh,
        shouldApply = shouldApply,
    }
end

ns.precast.IsRaftBlockedByShapeshift = IsRaftBlockedByShapeshift
ns.precast.GetRaftUseDecision = GetRaftUseDecision
