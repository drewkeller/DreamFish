local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing
local state = ns.Fishing.state

local FISHING_POLE_SLOT = 28
local AURA_WAIT_DURATION = 3.0 -- SurfaceTension takes approx 2.5s to appear after request to equip Underlight
local EXIT_DEBOUNCE_DELAY = 5.0 -- Prevent pole swap immediately after fish transformation and jumping out of water

Fishing:RegisterTraceSource("surfacetension")

local function Trace(msg)
    Fishing:Trace("surfacetension", msg)
end

Fishing:RegisterOnModuleEnable(function(self)
    self:CreateSurfaceTensionMonitor()
end)
Fishing:RegisterOnModuleDisable(function(self)
    self:RemoveSurfaceTensionMonitor()
end)

local function HasSurfaceTensionAura()
    return Fishing:GetAuraBySpellID(ns.Fishing.const.surfaceTensionSpellID) ~= nil
end

local function GetPoleEquipmentInfo()
    local underlightDecision = ns.precast.GetUnderlightAnglerEquipDecision()
    local poleDecision = ns.precast.GetSelectedFishingPoleDecision()
    return {
        underlightItemID = underlightDecision and underlightDecision.itemID,
        primaryItemID = poleDecision and poleDecision.itemID,
        isUnderlightEquipped = underlightDecision and underlightDecision.alreadyEquipped,
        isPrimaryEquipped = poleDecision and poleDecision.alreadyEquipped,
        canEquipUnderlight = underlightDecision and underlightDecision.canEquip or false,
        canEquipPrimary = poleDecision and poleDecision.canEquip or false,
    }
end

local function GetWaterContextDiagnostics()
    return (type(IsSwimming) == "function" and IsSwimming()) or (type(IsSubmerged) == "function" and IsSubmerged()) or false
end

-- State variables for the event engine
local monitorFrame = nil
local isAuraLockActive = false
local currentTimerID = 0
local exitDebounceTimer = nil
local lastConfirmedSwimmingState = nil
local isProcessingSwap = false
local awaitingPrimaryClearHandshake = false

local ExecuteStabilizedGearChanges

-- CORE ACTIONS PROCESSING PIPELINE
local function EquipUnderlightAngler(info)
    isProcessingSwap = true
    ns.Utils.TryEquipItemToProfessionSlot(info.underlightItemID, FISHING_POLE_SLOT)
    isProcessingSwap = false

    -- Start timer to give the server time to apply the buff and prevent trying to swap again
    currentTimerID = currentTimerID + 1
    local myTimerID = currentTimerID
    isAuraLockActive = true

    Trace("Underlight equipped.")
    C_Timer.After(AURA_WAIT_DURATION, function()
        if myTimerID == currentTimerID and isAuraLockActive then
            isAuraLockActive = false
            ExecuteStabilizedGearChanges("aura-wait-finished", true)
        end
    end)
end

ExecuteStabilizedGearChanges = function(reason, targetSwimmingState)
    if InCombatLockdown() or not ns.isStartupScanComplete then
        return
    end

    -- prevent water walking -> attempt to fish -> pole swap -> swimming -> pole swap -> underlight equip loop
    if Fishing:IsFishingState(ns.Fishing.states.PRECASTING) then
        return
    end

    local currentRealSwimming = GetWaterContextDiagnostics()
    if currentRealSwimming ~= targetSwimmingState then
        return
    end

    -- If player left the water, abort and reset everything
    if not currentRealSwimming then
        if isAuraLockActive or awaitingPrimaryClearHandshake then
            Trace("Action-Pass ["..reason.."]: Confirmed on dry land. Clearing locks.")
            isAuraLockActive = false
            awaitingPrimaryClearHandshake = false
        end
        currentTimerID = currentTimerID + 1
        return
    end

    -- STEP 1: AURA LOCKOUT PHASE
    if isAuraLockActive then
        if HasSurfaceTensionAura() then
            Trace("SurfaceTension aura successfully detected! Breaking lock early.")
            isAuraLockActive = false
            currentTimerID = currentTimerID + 1
        else
            return -- Sleep until the AURA_WAIT_DURATION timer completes
        end
    end

    local info = GetPoleEquipmentInfo()
    if not info.canEquipUnderlight or HasSurfaceTensionAura() then return end

    -- STEP 2: ITEM SWAP HANDSHAKE (Triggered via BAG_UPDATE_DELAYED)
    if awaitingPrimaryClearHandshake then
        if info.isPrimaryEquipped or not GetInventoryItemID("player", FISHING_POLE_SLOT) then
            Trace("Action-Pass ["..reason.."]: Primary swap confirmed. Equipping Underlight Angler.")
            awaitingPrimaryClearHandshake = false
            EquipUnderlightAngler(info)
        end
        return
    end

    -- STEP 3: INITIAL DETECTION ENTRY POINT
    if info.isUnderlightEquipped then
        -- Underlight equipped but no aura. Start the reset swap.
        if info.canEquipPrimary then
            Trace("Action-Pass ["..reason.."]: Missing SurfaceTension. Equipping primary pole.")
            isProcessingSwap = true
            ns.Utils.TryEquipItemToProfessionSlot(info.primaryItemID, FISHING_POLE_SLOT)
            isProcessingSwap = false

            -- Set handshake flag. BAG_UPDATE_DELAYED will trigger Step 2 when it arrives.
            awaitingPrimaryClearHandshake = true
        else
            Trace("Action-Pass ["..reason.."]: Missing SurfaceTension. Unequipping Underlight (No fallback).")
            isProcessingSwap = true
            ns.Utils.TryUnequipSlot(FISHING_POLE_SLOT)
            isProcessingSwap = false
            awaitingPrimaryClearHandshake = true
        end
    else
        -- Underlight isn't equipped.
        Trace("Action-Pass ["..reason.."]: Equipping Underlight Angler.")
        EquipUnderlightAngler(info)
    end
end

-- INTERMEDIATE ASYMMETRIC EVALUATION
local function EvaluateSwimmingState(reason)
    if isProcessingSwap or not ns.isStartupScanComplete then return end

    local currentSwimming = GetWaterContextDiagnostics()

    if currentSwimming and exitDebounceTimer then
        exitDebounceTimer:Cancel()
        exitDebounceTimer = nil
    end

    -- Allow BAG_UPDATE_DELAYED and Aura Timeouts to bypass standard state match filters
    if currentSwimming == lastConfirmedSwimmingState and reason ~= "aura-wait-finished" and reason ~= "BAG_UPDATE_DELAYED" then
        return
    end

    if currentSwimming then
        ns.Fishing.states.wasRecentlySwimming = true
        lastConfirmedSwimmingState = true
        ExecuteStabilizedGearChanges(reason, true)
    else
        if not exitDebounceTimer then
            exitDebounceTimer = C_Timer.After(EXIT_DEBOUNCE_DELAY, function()
                ns.Fishing.states.wasRecentlySwimming = false
                exitDebounceTimer = nil
                lastConfirmedSwimmingState = false
                ExecuteStabilizedGearChanges(reason, false)
            end)
        end
    end
end

-- EVENT REGISTER PIPELINE
function Fishing:CreateSurfaceTensionMonitor()
    if monitorFrame then return monitorFrame end
    Trace("Creating SurfaceTension monitor.")

    monitorFrame = CreateFrame("Frame")

    -- Core System Indicators
    monitorFrame:RegisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
    monitorFrame:RegisterEvent("MIRROR_TIMER_START")
    monitorFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    monitorFrame:RegisterEvent("UNIT_AURA")
    monitorFrame:RegisterEvent("BAG_UPDATE_DELAYED")

    -- STARTUP EVENTS
    monitorFrame:RegisterEvent("PLAYER_LOGIN")
    monitorFrame:RegisterEvent("SPELLS_CHANGED")
    monitorFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    monitorFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" and unit ~= "player" then return end

        -- Handle the initial loading screen handshake blocks
        if event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            if not ns.isStartupScanComplete then
                -- Add a micro-delay (0.5s) to guarantee the container data links are verified
                C_Timer.After(0.5, function()
                    if ns.isStartupScanComplete then return end

                    local underlightDecision = ns.precast.GetUnderlightAnglerEquipDecision()
                    if underlightDecision and underlightDecision.canEquip then
                        ns.isStartupScanComplete = true
                        Trace("Startup inventory match successful via " .. event .. ". Underlight Angler discovered.")

                        -- Synchronize baseline states now that structural assets are validated
                        lastConfirmedSwimmingState = GetWaterContextDiagnostics()
                        ns.Fishing.states.wasRecentlySwimming = lastConfirmedSwimmingState
                        ExecuteStabilizedGearChanges("Startup Synchronization Complete", lastConfirmedSwimmingState)
                    else
                        Trace("Inventory sync check frame passed (" .. event .. "). Waiting for remaining packets.")
                    end
                end)
            end
            return
        end

        EvaluateSwimmingState(event)
    end)

    ns.frames.surfaceTensionMonitor = monitorFrame
    return monitorFrame
end

function Fishing:RemoveSurfaceTensionMonitor()
    if monitorFrame then
        monitorFrame:UnregisterAllEvents()
        monitorFrame:SetScript("OnEvent", nil)
        monitorFrame = nil
        ns.frames.surfaceTensionMonitor = nil

        isAuraLockActive = false
        isProcessingSwap = false
        awaitingPrimaryClearHandshake = false
        currentTimerID = currentTimerID + 1
        if exitDebounceTimer then exitDebounceTimer:Cancel() exitDebounceTimer = nil end
        lastConfirmedSwimmingState = nil
        ns.Fishing.states.wasRecentlySwimming = nil
    end
    Trace("SurfaceTension monitor removed.")
end
