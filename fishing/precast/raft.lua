local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local Fishing = DreamFish:GetModule("Fishing")

local function TraceRaft(msg)
    if DreamFish.db.profile.debugMode then
        DreamFish:Print("|cFF999999[Raft]|r ", msg)
    end
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

local function GetRaftUseDecision()
    local raftToyID = tonumber(Fishing:GetProfileDB().selectedRaftToy) or nil
    local hasRaftSelected = raftToyID and raftToyID > 0
    local hasToy = hasRaftSelected and PlayerHasToy(raftToyID) or false
    local raftReady = hasToy and DreamFish:IsItemReadyForUse(raftToyID)
    local swimming = IsSwimming()
    local raftAuraRemaining = (hasToy and swimming) and GetRaftAuraRemainingSeconds(raftToyID) or nil
    local castLead = ns.Fishing.const.maxFishingCastSeconds + ns.Fishing.const.buffPreRefreshSafetySeconds
    if raftAuraRemaining == nil and hasToy then
        -- If aura can't be observed while not swimming, try once more without the swim gate.
        raftAuraRemaining = GetRaftAuraRemainingSeconds(raftToyID)
    end
    local needsRefreshForCast = (raftAuraRemaining == nil) or (raftAuraRemaining <= castLead)

    local shouldApply = hasRaftSelected
        and hasToy
        and raftReady
        and needsRefreshForCast
        and (swimming or raftAuraRemaining ~= nil)

    if shouldApply then
        TraceRaft("Raft will be applied")
    elseif raftToyID and raftToyID == 0 then
        TraceRaft("'None' raft is selected")
    elseif not hasRaftSelected then
        TraceRaft("No raft toy selected or invalid ID")
    elseif not hasToy then
        TraceRaft("Raft is not owned")
    elseif not raftReady then
        TraceRaft("Raft toy on cooldown: " .. DreamFish:GetDebugCooldownText(raftToyID))
    elseif not needsRefreshForCast then
        TraceRaft("Raft aura remaining sufficient for cast")
    elseif not (swimming or raftAuraRemaining ~= nil) then
        TraceRaft("Not swimming and no raft aura observed")
    else
        TraceRaft("Raft will not be applied for unknown reason")
    end

    return {
        toyID = raftToyID,
        hasToy = hasToy,
        ready = raftReady,
        swimming = swimming,
        auraRemaining = raftAuraRemaining,
        needsRefreshForCast = needsRefreshForCast,
        shouldApply = shouldApply,
    }
end

ns.precast.GetRaftUseDecision = GetRaftUseDecision
