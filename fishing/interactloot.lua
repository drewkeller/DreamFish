-- DreamFish: Hooked-fish interact action helpers

local addon = _G["DreamFish"]
local DebugMessage = addon.DebugMessage
addon.fishing = addon.fishing or {}

local KNOWN_BOBBER_NPC_IDS = {
    [216204] = true,
    [265572] = true,
    [124736] = true,
    [261797] = true,
}

local function ApplySessionStateRequired(nextState, reason)
    if not addon.RequireFishingAPI then
        error("DreamFish: RequireFishingAPI helper is required for interact loot state transitions")
    end
    local fishing = addon.RequireFishingAPI()
    if not (fishing and type(fishing.ApplySessionState) == "function") then
        error("DreamFish: ApplySessionState is required for interact loot state transitions")
    end
    fishing.ApplySessionState(nextState, reason)
end

local function GetInteractOverrideFrame()
    if addon.frames and addon.frames.interactOverride then
        return addon.frames.interactOverride
    end
    if type(CreateFrame) ~= "function" then
        return nil
    end
    addon.frames = addon.frames or {}
    addon.frames.interactOverride = CreateFrame("Frame", "DreamFishInteractOverrideFrame", UIParent)
    return addon.frames.interactOverride
end

local function ArmNativeInteractOverride(durationSeconds)
    if InCombatLockdown() or type(GetBindingKey) ~= "function" then
        return false
    end
    if type(SetOverrideBinding) ~= "function" or type(ClearOverrideBindings) ~= "function" then
        return false
    end

    local owner = GetInteractOverrideFrame()
    if not owner then
        return false
    end

    ClearOverrideBindings(owner)
    local boundKeys = { GetBindingKey("CLICK DreamFishSecureFishingButton:RightButton") }
    local applied = false
    for _, key in ipairs(boundKeys) do
        if type(key) == "string" and key ~= "" then
            SetOverrideBinding(owner, true, key, "INTERACTTARGET")
            applied = true
        end
    end

    -- Keep native right-click interact available while hooked.
    SetOverrideBinding(owner, true, "BUTTON2", "INTERACTTARGET")
    applied = true

    if not applied then
        return false
    end

    addon.state.interactOverrideActive = true
    local now = (type(GetTime) == "function") and GetTime() or 0
    if durationSeconds and tonumber(durationSeconds) and tonumber(durationSeconds) > 0 then
        addon.state.interactOverrideExpiresAt = now + tonumber(durationSeconds)
    else
        addon.state.interactOverrideExpiresAt = 0
    end
    owner:SetScript("OnUpdate", function(self)
        if not addon.RequireFishingAPI then
            error("DreamFish: RequireFishingAPI helper is required for interact override upkeep")
        end
        local fishing = addon.RequireFishingAPI()
        if InCombatLockdown() then
            return
        end
        local t = (type(GetTime) == "function") and GetTime() or 0
        local moving = (type(IsPlayerMoving) == "function") and IsPlayerMoving() or false
        local stillHooked = fishing and fishing.IsHookedLootMode and fishing.IsHookedLootMode()
        local expiresAt = tonumber(addon.state.interactOverrideExpiresAt) or 0
        local expired = expiresAt > 0 and t >= expiresAt
        if moving or expired or not stillHooked then
            ClearOverrideBindings(self)
            self:SetScript("OnUpdate", nil)
            addon.state.interactOverrideExpiresAt = 0
            addon.state.interactOverrideActive = false
            addon.state.interactAcquireExpiresAt = 0
            if moving then
                DebugMessage("Cleared native interact override due to movement")
            end
        end
    end)
    return true
end

local function ClearNativeInteractOverride()
    if type(ClearOverrideBindings) ~= "function" then
        return
    end
    local owner = GetInteractOverrideFrame()
    if not owner then
        return
    end
    if not InCombatLockdown() then
        ClearOverrideBindings(owner)
        owner:SetScript("OnUpdate", nil)
    end
    addon.state.interactOverrideExpiresAt = 0
    addon.state.interactOverrideActive = false
    addon.state.interactAcquireExpiresAt = 0
end

local function GetUnitNameSafe(unit)
    if type(UnitName) ~= "function" then
        return nil
    end
    local name = UnitName(unit)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function GetUnitGUIDSafe(unit)
    if type(UnitGUID) ~= "function" then
        return nil
    end
    local guid = UnitGUID(unit)
    if type(guid) == "string" and guid ~= "" then
        return guid
    end
    return nil
end

local function GetNpcIDFromGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local unitType, _, _, _, npcID = guid:match("^([^-]+)-([^-]+)-([^-]+)-([^-]+)-([^-]+)-(.+)$")
    if (unitType == "Creature" or unitType == "Vehicle") and npcID then
        local numeric = tonumber(npcID)
        if numeric and numeric > 0 then
            return numeric
        end
    end
    return nil
end

local function IsFishingBobberName(name)
    return type(name) == "string" and name == "Fishing Bobber"
end

local function GetInteractDiagnostics()
    local softExists = (type(UnitExists) == "function") and UnitExists("softinteract") and true or false
    local targetExists = (type(UnitExists) == "function") and UnitExists("target") and true or false
    local mouseoverExists = (type(UnitExists) == "function") and UnitExists("mouseover") and true or false
    local softGUID = GetUnitGUIDSafe("softinteract")
    local targetGUID = GetUnitGUIDSafe("target")
    local mouseoverGUID = GetUnitGUIDSafe("mouseover")
    local softNpcID = GetNpcIDFromGUID(softGUID)
    local targetNpcID = GetNpcIDFromGUID(targetGUID)
    local mouseoverNpcID = GetNpcIDFromGUID(mouseoverGUID)
    return {
        softExists = softExists,
        softName = GetUnitNameSafe("softinteract"),
        softGUID = softGUID,
        softNpcID = softNpcID,
        targetExists = targetExists,
        targetName = GetUnitNameSafe("target"),
        targetGUID = targetGUID,
        targetNpcID = targetNpcID,
        mouseoverExists = mouseoverExists,
        mouseoverName = GetUnitNameSafe("mouseover"),
        mouseoverGUID = mouseoverGUID,
        mouseoverNpcID = mouseoverNpcID,
    }
end

local function FormatInteractDiagnostics(diag)
    if type(diag) ~= "table" then
        return "interactDiag=unavailable"
    end
    return "soft=" .. tostring(diag.softExists)
        .. "(" .. tostring(diag.softName or "-") .. ")"
        .. " softNpcID=" .. tostring(diag.softNpcID or "-")
        .. " target=" .. tostring(diag.targetExists)
        .. "(" .. tostring(diag.targetName or "-") .. ")"
        .. " targetNpcID=" .. tostring(diag.targetNpcID or "-")
        .. " mouseover=" .. tostring(diag.mouseoverExists)
        .. "(" .. tostring(diag.mouseoverName or "-") .. ")"
        .. " mouseoverNpcID=" .. tostring(diag.mouseoverNpcID or "-")
end

local function IsHookedLootMode()
    if not addon.RequireFishingAPI then
        error("DreamFish: RequireFishingAPI helper is required for hooked loot mode")
    end
    local fishing = addon.RequireFishingAPI()

    if not addon.db or not addon.db.easyStrike or not addon.state then
        return false
    end

    if not (fishing and fishing.IsHookedWindowSessionState and fishing.IsSessionState) then
        error("DreamFish: IsHookedWindowSessionState and IsSessionState are required for hooked loot mode")
    end

    local now = (type(GetTime) == "function") and GetTime() or 0
    local graceUntil = tonumber(addon.state.fishingStartGraceUntil) or 0

    local hookedWindowStateReady = fishing.IsHookedWindowSessionState() and (now >= graceUntil)
    local fallbackHookWindow = false

    if fishing.IsSessionState("CASTING") and not fishing.IsSessionState("LOOTING") then
        -- Some clients do not reliably emit the expected hooked-window transition in secure-click hotkey paths.
        -- Treat post-cast state (after start grace) as a hooked-interact fallback window.
        fallbackHookWindow = now >= graceUntil
    end

    return hookedWindowStateReady or fallbackHookWindow
end

local function ConfigureInteractLootAction(frame)
    if not frame then
        return false
    end

    local targetMacroLines = {}
    local seenNames = {}
    local function AddTargetName(name)
        if type(name) ~= "string" or name == "" or seenNames[name] then
            return
        end
        seenNames[name] = true
        table.insert(targetMacroLines, "/targetexact " .. name)
    end

    local selectedBobberToy = addon.db and tonumber(addon.db.selectedBobberToy) or nil
    if selectedBobberToy and selectedBobberToy > 0 and type(GetItemInfo) == "function" then
        AddTargetName(GetItemInfo(selectedBobberToy))
    end
    AddTargetName("Fishing Bobber")

    local diag = GetInteractDiagnostics()
    local foundKnownNpcID = diag.softNpcID or diag.targetNpcID or diag.mouseoverNpcID
    local matchedKnownNpc = (diag.softNpcID and KNOWN_BOBBER_NPC_IDS[diag.softNpcID])
        or (diag.targetNpcID and KNOWN_BOBBER_NPC_IDS[diag.targetNpcID])
        or (diag.mouseoverNpcID and KNOWN_BOBBER_NPC_IDS[diag.mouseoverNpcID])
    local foundFishingBobberName = IsFishingBobberName(diag.softName)
        or IsFishingBobberName(diag.targetName)
        or IsFishingBobberName(diag.mouseoverName)
    if matchedKnownNpc or foundFishingBobberName then
        DebugMessage("Hooked diagnostics: bobber candidate found "
            .. "knownNpc=" .. tostring(matchedKnownNpc and true or false)
            .. " anyNpcID=" .. tostring(foundKnownNpcID or "-")
            .. " byName=" .. tostring(foundFishingBobberName)
            .. " " .. FormatInteractDiagnostics(diag))
    end
    local hasAnyInteractUnit = diag.softExists or diag.targetExists or diag.mouseoverExists
    local hasSoftInteractNameOnly = (not hasAnyInteractUnit)
        and type(diag.softName) == "string"
        and diag.softName ~= ""
    local now = (type(GetTime) == "function") and GetTime() or 0
    local acquireExpiresAt = tonumber(addon.state and addon.state.interactAcquireExpiresAt) or 0
    local inAcquireWindow = acquireExpiresAt > now

    if hasSoftInteractNameOnly then
        ApplySessionStateRequired("WAITING_FOR_LOOT_WINDOW", "hooked-soft-name-acquire-interact")
        frame:SetAttribute("type", "macro")
        frame:SetAttribute("macrotext", table.concat(targetMacroLines, "\n") .. "\n/interact")
        frame:SetAttribute("spell", nil)
        frame:SetAttribute("dreamfisher_duebuff", nil)
        DebugMessage("Fishing click using hooked soft-name acquire+interact "
            .. FormatInteractDiagnostics(diag))
        return true
    end

    -- Some clients need one keypress to acquire bobber target, then one keypress to interact.
    -- Keep target acquisition macro armed until an interactable unit actually exists.
    if type(UnitExists) == "function" and (not hasAnyInteractUnit) then
        ApplySessionStateRequired("WAITING_FOR_STRIKE", "hooked-target-acquire")
        if addon.state and (not inAcquireWindow) then
            addon.state.interactAcquireExpiresAt = now + 2.5
        end

        frame:SetAttribute("type", "macro")
        frame:SetAttribute("macrotext", table.concat(targetMacroLines, "\n"))
        frame:SetAttribute("spell", nil)
        frame:SetAttribute("dreamfisher_duebuff", nil)
        local armedNativeInteract = false
        if not inAcquireWindow then
            armedNativeInteract = ArmNativeInteractOverride(2.5)
            DebugMessage("Fishing click primed hooked target acquisition "
                .. FormatInteractDiagnostics(diag)
                .. " nativeOverride=" .. tostring(armedNativeInteract))
        else
            DebugMessage("Fishing click continuing hooked target acquisition "
                .. FormatInteractDiagnostics(diag))
        end
        return true
    end

    ApplySessionStateRequired("WAITING_FOR_LOOT_WINDOW", "hooked-direct-interact")
    frame:SetAttribute("type", "macro")
    frame:SetAttribute("macrotext", "/interact")
    frame:SetAttribute("spell", nil)
    frame:SetAttribute("dreamfisher_duebuff", nil)
    if addon.state then
        addon.state.interactAcquireExpiresAt = 0
    end
    DebugMessage("Fishing click configured for hooked-fish interact "
        .. FormatInteractDiagnostics(diag))
    return true
end

addon.fishing.IsHookedLootMode = IsHookedLootMode
addon.fishing.ConfigureInteractLootAction = ConfigureInteractLootAction
addon.fishing.GetInteractDiagnostics = GetInteractDiagnostics
addon.fishing.FormatInteractDiagnostics = FormatInteractDiagnostics
addon.fishing.ArmNativeInteractOverride = ArmNativeInteractOverride
addon.fishing.ClearNativeInteractOverride = ClearNativeInteractOverride