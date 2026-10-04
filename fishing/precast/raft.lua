local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing
local states = {
    currentRaftToyID = nil,
    lastSelectedAt = nil,
}

local MIN_TIME_CHANGE_RAFT = 300

Fishing:RegisterTraceSource("raft")
local function Trace(msg)
    -- prevent noisy logging
    --Fishing:Trace("raft", msg)
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

local function IsRecentlyUsed(toyID)
    local lastUseAt = Fishing.state
        and type(Fishing.state.raftToyLastUseAt) == "table"
        and Fishing.state.raftToyLastUseAt[toyID]
        or nil
    return lastUseAt and (GetTime() - lastUseAt) < 10
end

local function MarkRaftUse(toyID)
    if not toyID then
        return
    end
    Fishing.state.raftToyLastUseAt = type(Fishing.state.raftToyLastUseAt) == "table"
        and Fishing.state.raftToyLastUseAt
        or {}
    Fishing.state.raftToyLastUseAt[toyID] = GetTime()
end

local function GetRaftUseDecision(self)
    local toyID = tonumber(self.db.profile.selectedRaftToy) or nil
    if toyID == -1 then
        local now = GetTime()
        local needRaft = states.currentRaftToyID == nil
        local timeForNewRaft = states.lastSelectedAt == nil or (now - states.lastSelectedAt) >= MIN_TIME_CHANGE_RAFT
        if needRaft or timeForNewRaft then
            toyID = ns.Utils.GetRandomOwnedToyID(ns.Fishing.const.raftToyItemIDs, states.currentRaftToyID) or nil
            Trace("Selected a random raft: " .. tostring(toyID) .. " was: " .. tostring(states.currentRaftToyID))
            states.currentRaftToyID = toyID
            states.lastSelectedAt = now
        else
            toyID = states.currentRaftToyID
        end
    end
    local hasRaftSelected = toyID and toyID > 0
    local hasToy = hasRaftSelected and ns.Utils.IsToyOwned(toyID) or false
    local isReady = hasToy and ns.Utils.IsCooldownReady(toyID)
    local swimming = ns.Utils.IsSwimmingOrSubmerged() == true
    -- Don't tell the player they are swimming if they aren't, but still likely want to use raft
    --local recentlySwimming = ns.Fishing.states.wasRecentlySwimming == true
    local blockedByShapeshift = IsRaftBlockedByShapeshift()
    local recentlyUsed = hasToy and IsRecentlyUsed(toyID) or false
    local auraRemaining = (hasToy and swimming) and GetRaftAuraRemainingSeconds(toyID) or nil
    local castLead = ns.Fishing.const.maxFishingCastSeconds + ns.Fishing.const.buffPreRefreshSafetySeconds
    local isShapeShifted = IsRaftBlockedByShapeshift()
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
        and not recentlyUsed
        and (swimming or auraRemaining ~= nil) -- or recentlySwimming)
        and not isShapeShifted

    Trace(string.format("swimming=%s submerged=%s aura=%s recentlyUsed=%s",
        tostring(swimming), tostring(type(IsSubmerged) == "function" and IsSubmerged()),
        tostring(auraRemaining), tostring(recentlyUsed)))

    if shouldApply then
        Trace("Raft can be applied")
    elseif toyID and toyID == 0 then
        Trace("'None' raft is selected")
    elseif not hasRaftSelected then
        Trace("No raft toy selected or invalid ID: " .. tostring(toyID))
    elseif not hasToy then
        Trace("Raft is not owned")
    elseif not isReady then
        Trace("Raft toy on cooldown: " .. ns.Utils.GetDebugCooldownText(toyID))
    elseif recentlyUsed then
        Trace("Raft was recently used; waiting for player to climb on or aura state to settle")
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
        recentlyUsed = recentlyUsed,
        auraRemaining = auraRemaining,
        needsRefreshForCast = needsRefresh,
        shouldApply = shouldApply,
        isShapeShifted = isShapeShifted,
    }
end

ns.precast.IsRaftBlockedByShapeshift = IsRaftBlockedByShapeshift
ns.precast.MarkRaftUse = MarkRaftUse
ns.precast.GetRaftUseDecision = GetRaftUseDecision
