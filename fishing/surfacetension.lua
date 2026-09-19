local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing
local state = ns.Fishing.state

--[[
    SurfaceTension aura and swimming state monitor for the Fishing module.
    Tracks whether the player is swimming or submerged and manages
    the equipping of the Underlight Angler item based on water context in order
    to use benefits of the Underlight Angler.
    - Surface Tension: Water walking
    - Underlight Blessing: Water breathing and increased swim speed (Surface Tension is awarded before this)

    This system is active only if Underlight Angler is configured and equippable.
    * State changes that trigger a reevaluation:
        - Entering or leaving swimming/submerged state
        - Leaving combat while underwater
    * Upon a relevant state change, detect if SurfaceTension aura (216441) is active.
      - If active, don't need to do anything
      - If not active...
        - If Angler is already equipped...
            - If primary pole is equippable, swap to the "other" pole and then swap to Angler.
            - Else unequip Angler and then equip Angler
        - If Angler is not equipped, equip it directly.
]]

local UNDERLIGHT_SWAP_DELAY_SECONDS = 1.0
local SURFACE_TENSION_DELAY_SECONDS = 5.0 -- This aura takes approx 2.5 seconds to appear after request to equip Underlight

Fishing:RegisterTraceSource("swimming")

local function Trace(msg)
    Fishing:Trace("swimming", msg)
end

Fishing:RegisterOnModuleEnable(function(self)
    local underlightDecision = ns.precast.GetUnderlightAnglerEquipDecision()
    if underlightDecision and underlightDecision.canEquip then
        self:CreateSurfaceTensionMonitor()
    end
end)
Fishing:RegisterOnModuleDisable(function(self)
    self:RemoveSurfaceTensionMonitor()
end)

local function HasSurfaceTensionAura()
    return Fishing:GetAuraBySpellID(ns.Fishing.const.surfaceTensionSpellID) ~= nil
end

local function GetPoleEquipmentInfo()
    local underlightDecision = ns.precast.GetUnderlightAnglerEquipDecision()
    local canEquipUnderlight = underlightDecision and underlightDecision.canEquip or false
    local poleDecision = ns.precast.GetSelectedFishingPoleDecision()
    local canEquipOtherPole = poleDecision and poleDecision.canEquip or false
    return {
        underlightItemID = underlightDecision.itemID,
        primaryItemID = poleDecision.itemID,
        isUnderlightEquipped = underlightDecision.alreadyEquipped,
        isPrimaryEquipped = poleDecision.alreadyEquipped,
        canEquipUnderlight = canEquipUnderlight,
        canEquipPrimary = canEquipOtherPole,
    }
end


local function GetWaterContextDiagnostics()
    if type(IsSwimming) == "function" and IsSwimming() then
        return true
    end

    if type(IsSubmerged) == "function" and IsSubmerged() then
        return true
    end

    return false
end

function Fishing:CreateSurfaceTensionMonitor()
    if ns.frames.swimMonitor then
        return ns.frames.swimMonitor
    end
    Trace("Creating swimming state monitor.")

    local frame = CreateFrame("Frame")
    local elapsedSinceCheck = 0
    local underlightSwapBackAt = nil
    local surfaceTensionExpectedBy = nil
    local lastSwimmingState = nil
    local lastCombatState = nil
    local lastSurfaceTensionState = nil
    local failedToProduceAura = nil

    local function ResetTimers()
        underlightSwapBackAt = nil
        surfaceTensionExpectedBy = nil
        failedToProduceAura = nil
    end

    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceCheck = elapsedSinceCheck + (tonumber(elapsed) or 0)
        if elapsedSinceCheck < 0.5 then
            return
        end
        elapsedSinceCheck = 0

        if InCombatLockdown() then
            lastCombatState = true
            return
        end
        if not Fishing:IsFishingState(ns.Fishing.states.IDLE) then
            ResetTimers()
            return
        end

        -- if left combat under water, we still might need to swap
        local swimming = GetWaterContextDiagnostics()
        local hasSwimmingChange = swimming ~= lastSwimmingState or lastSwimmingState == nil
        local hasCombatChange = lastCombatState == true or lastCombatState == nil
        if hasSwimmingChange or (swimming and hasCombatChange) then
            lastSwimmingState = swimming
            lastCombatState = false
            Trace("Water context: isSwimming=" .. tostring(swimming)
                .. " surfaceTension=" .. tostring(HasSurfaceTensionAura()))
        end
        local hasSurfaceTension = HasSurfaceTensionAura()
        local hasSurfaceTensionChange = lastSurfaceTensionState ~= hasSurfaceTension or lastSurfaceTensionState == nil
        if hasSurfaceTensionChange then
            lastSurfaceTensionState = hasSurfaceTension
            Trace("SurfaceTension changed: " .. tostring(hasSurfaceTension))
        end

        local info = GetPoleEquipmentInfo()
        if not info.canEquipUnderlight then
            ResetTimers()
            return
        end

        local now = (type(GetTime) == "function") and GetTime() or 0
        local hasSurfaceTension = HasSurfaceTensionAura()
        if surfaceTensionExpectedBy then
            if surfaceTensionExpectedBy <= now then
                surfaceTensionExpectedBy = nil
                Trace("Surface tension expected by now: " .. tostring(HasSurfaceTensionAura()))
                if not HasSurfaceTensionAura() then
                    failedToProduceAura = true
                    Addon:Warning("swimming", "Failed to produce SurfaceTension aura.")
                end
            end
        -- we have a pole swap pending
        elseif underlightSwapBackAt then
            if underlightSwapBackAt <= now then
                underlightSwapBackAt = nil
                surfaceTensionExpectedBy = now + SURFACE_TENSION_DELAY_SECONDS
                Trace("Equip Underlight: Swapping back to Underlight, Surface Tension expected in " .. tostring(SURFACE_TENSION_DELAY_SECONDS) .. " seconds.")
                ns.precast.TryEquipItemToProfessionSlot(info.underlightItemID)
            end
        elseif swimming and not hasSurfaceTension and not failedToProduceAura then
            -- if underlight is already equipped, equip other pole or unequip underlight
            if info.isUnderlightEquipped then
                underlightSwapBackAt = now + UNDERLIGHT_SWAP_DELAY_SECONDS
                if info.canEquipPrimary then
                    Trace("Equip Primary  : Swapping back to Underlight in " .. tostring(UNDERLIGHT_SWAP_DELAY_SECONDS) .. " seconds.")
                    ns.precast.TryEquipItemToProfessionSlot(info.primaryItemID)
                else
                    -- unequip underlight
                    Trace("Unequip Underlight: No primary pole available.")
                    ns.precast.TryUnequipFishingPole()
                end
            else
                underlightSwapBackAt = nil
                surfaceTensionExpectedBy = now + SURFACE_TENSION_DELAY_SECONDS
                Trace("Equip Underlight: Surface Tension in " .. tostring(SURFACE_TENSION_DELAY_SECONDS) .. " seconds.")
                ns.precast.TryEquipItemToProfessionSlot(info.underlightItemID)
            end
        end
    end)

    ns.frames.swimMonitor = frame
    return ns.frames.swimMonitor
end

function Fishing:RemoveSurfaceTensionMonitor()
    if ns.frames.swimMonitor then
        ns.frames.swimMonitor:SetScript("OnUpdate", nil)
        ns.frames.swimMonitor = nil
    end
    Trace("Swimming state monitor removed.")
end

