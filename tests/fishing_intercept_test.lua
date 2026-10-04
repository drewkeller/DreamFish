local mouseDownCallback
local preClickCallback
local clickCallback
local postClickCallback
local messages = {}
local bindingsCleared = false
local clickEnabled = true
local motionEnabled = true
local mouseEnabled = true
local frameHidden = false
local anchorsCleared = false
local clicksRegistered = true
local clicksPropagated = false
local motionPropagated = false
local cleanupCallback
local cleanupRegistered = false
local inCombat = false
local shiftKeyDown = false
local controlKeyDown = false
local altKeyDown = false
local leftMouseDown = false
local rightMouseDown = false
local currentTime = 0
local mouseHooked = false
local gameMouseActions = 0
local castStartedCount = 0
local secureAttributes = {}
local scheduledCallbacks = {}
local profile = {
    castByDoubleRightClick = true,
    castBySingleRightClickWhenFishing = false,
    castByHotkey = true,
    strikeByRightClick = false,
    strikeByDoubleRightClick = true,
    selectedRaftToy = 85500,
}
local markedRaftToyID
local rightClickStrikeBindingMode

local Fishing = {
    clickFrame = {},
}

function Fishing.clickFrame:SetScript(script, callback)
    if script == "PreClick" then
        preClickCallback = callback
    elseif script == "OnClick" then
        clickCallback = callback
    elseif script == "PostClick" then
        postClickCallback = callback
    end
end

function Fishing.clickFrame:RegisterForClicks(...)
    clicksRegistered = select("#", ...) > 0
end

function Fishing.clickFrame:SetPropagateMouseClicks(enabled)
    clicksPropagated = enabled
end

function Fishing.clickFrame:SetPropagateMouseMotion(enabled)
    motionPropagated = enabled
end

function Fishing.clickFrame:SetMouseClickEnabled(enabled)
    clickEnabled = enabled
end

function Fishing.clickFrame:SetMouseMotionEnabled(enabled)
    motionEnabled = enabled
end

function Fishing.clickFrame:EnableMouse(enabled)
    mouseEnabled = enabled
end

function Fishing.clickFrame:Hide()
    frameHidden = true
end

function Fishing.clickFrame:Show()
    frameHidden = false
end

function Fishing.clickFrame:ClearAllPoints()
    anchorsCleared = true
end

function Fishing.clickFrame:SetFrameStrata()
end

function Fishing.clickFrame:SetAttribute(name, value)
    secureAttributes[name] = value
end

function Fishing.clickFrame:GetAttribute(name)
    return secureAttributes[name]
end

function Fishing:IsEnabled()
    return true
end

function Fishing:IsHooked(frame, script)
    if frame == self.clickFrame and script == "PreClick" then
        return preClickCallback ~= nil
    end
    if frame == self.clickFrame and script == "PostClick" then
        return postClickCallback ~= nil
    end

    assert(frame == WorldFrame)
    assert(script == "OnMouseDown")
    return mouseHooked
end

function Fishing:SecureHookScript(frame, script, handler)
    if frame == self.clickFrame and script == "PreClick" then
        preClickCallback = handler
        return
    end

    assert(frame == WorldFrame)
    assert(script == "OnMouseDown")
    mouseDownCallback = function(...)
        gameMouseActions = gameMouseActions + 1
        self[handler](self, ...)
    end
    mouseHooked = true
end

function Fishing:Unhook(frame, script)
    assert(frame == WorldFrame)
    assert(script == "OnMouseDown")
    mouseHooked = false
    mouseDownCallback = nil
end

function Fishing:RegisterTraceSource()
end

function Fishing:Trace()
end

function Fishing:ArmRightClickStrike()
    rightClickStrikeBindingMode = profile.strikeByRightClick and "interact" or "native"
end

function Fishing:UseNativeRightClickStrike()
    rightClickStrikeBindingMode = "interact"
end

function Fishing:RegisterOnModuleInitialize(func)
    self.onInitializeFuncs = self.onInitializeFuncs or {}
    table.insert(self.onInitializeFuncs, func)
end

function Fishing:SendMessage(message)
    table.insert(messages, message)
end

function Fishing:ScheduleTimer(callback, delay)
    if type(callback) == "function" then
        table.insert(scheduledCallbacks, callback)
    end
    return {}
end

function Fishing:CancelTimer()
end

local DreamFish = {}

function DreamFish:GetModule(name)
    assert(name == "Fishing")
    return Fishing
end

function DreamFish:Print()
end

function LibStub(name, silent)
    if name == "AceAddon-3.0" then
        return {
            GetAddon = function()
                return DreamFish
            end,
        }
    end
    if silent then
        return nil
    end
    assert(name == "AceAddon-3.0")
end

UIParent = {}
WorldFrame = {}

function CreateFrame(frameType)
    assert(frameType == "Frame")

    return {
        SetScript = function(_, _, callback)
            cleanupCallback = callback
        end,
        RegisterEvent = function(_, event)
            assert(event == "PLAYER_REGEN_ENABLED")
            cleanupRegistered = true
        end,
        UnregisterEvent = function(_, event)
            assert(event == "PLAYER_REGEN_ENABLED")
            cleanupRegistered = false
        end,
    }
end

function InCombatLockdown()
    return inCombat
end

function GetTime()
    return currentTime
end

function IsShiftKeyDown()
    return shiftKeyDown
end

function IsControlKeyDown()
    return controlKeyDown
end

function IsAltKeyDown()
    return altKeyDown
end

function IsMouseButtonDown(button)
    return button == "LeftButton" and leftMouseDown
        or button == "RightButton" and rightMouseDown
end

function IsModifiedClick(action)
    return false
end

function UnitGUID(unit)
    return nil
end

function ClearOverrideBindings(frame)
    assert(frame == Fishing.clickFrame)
    bindingsCleared = true
end

local ns = {
    Addon = DreamFish,
    Fishing = Fishing,
    FishingDB = {
        global = {},
        profile = profile,
        char = {},
    },
    precast = {},
}
ns.precast.MarkRaftUse = function(toyID)
    markedRaftToyID = toyID
end
Fishing.db = ns.FishingDB
assert(loadfile("fishing/intercept.lua"))("DreamFish", ns)
assert(loadfile("fishing/states.lua"))("DreamFish", ns)
for _, initializer in ipairs(Fishing.onInitializeFuncs) do
    initializer(Fishing)
end

function Fishing:OnCastStarted()
    castStartedCount = castStartedCount + 1
end

function Fishing:PrepareFishingClickAction()
    secureAttributes.type = "spell"
end

function Fishing:AwaitFishingCastStart()
    local castAttempt = self.state.castAttempt or 1
    if self.state.castStartConfirmationAttempt == castAttempt then return end

    self.state.castStartConfirmationAttempt = castAttempt
    self:ScheduleTimer(function()
        if self.state.castStartConfirmationAttempt ~= castAttempt then return end
            self.state.castStartConfirmationAttempt = nil
        if self:IsFishingState(ns.Fishing.states.PRECASTING)
            and not self.state.pendingBuffUse
            and not self.state.isEquippingPrimaryPole then
            self:CancelFishingSession("fishing cast did not start")
        end
    end, 0.5)
end

function Fishing:CancelFishingSession(reason)
    self:SetFishingState(ns.Fishing.states.IDLE)
    self:ReleaseClickCapture()
end

Fishing:HookMouseDown()
Fishing:HookPreClickWithHandler()
Fishing:HookPostClickWithHandler()

mouseDownCallback(WorldFrame, "LeftButton")
assert(castStartedCount == 0, "non-right clicks must bypass Fishing")
assert(gameMouseActions == 1, "non-right clicks must reach the game handler")

mouseDownCallback(WorldFrame, "RightButton")
assert(castStartedCount == 1, "enabled double-right-click must call OnCastStarted")

profile.castByDoubleRightClick = false
mouseDownCallback(WorldFrame, "RightButton")
assert(castStartedCount == 1, "disabled double-right-click must not call OnCastStarted")

profile.castBySingleRightClickWhenFishing = true
Fishing:SetFishingState(ns.Fishing.states.PRECASTING)
secureAttributes.type = "spell"
currentTime = 1
mouseDownCallback(WorldFrame, "RightButton")
assert(castStartedCount == 2, "first single click during fishing must start a cast")

currentTime = 1.1
mouseDownCallback(WorldFrame, "RightButton")
assert(castStartedCount == 2, "second click during single-click fishing must be suppressed")
assert(secureAttributes.type == "macro", "suppressed click must replace the secure action with a no-op macro")
assert(not clicksPropagated, "suppressed click must not propagate to the game")
Fishing:HideClickFrame()
assert(clicksPropagated, "suppressed click cleanup must restore mouse propagation")
profile.castBySingleRightClickWhenFishing = false
Fishing:SetFishingState(ns.Fishing.states.IDLE)

preClickCallback(Fishing.clickFrame, "RightButton", true)
assert(castStartedCount == 3, "hotkey button-down must start the fishing session")
preClickCallback(Fishing.clickFrame, "RightButton", false)
assert(castStartedCount == 3, "hotkey button-up must not restart the fishing session")

Fishing:SetFishingState(ns.Fishing.states.WAITING_FOR_BITE)
secureAttributes.type = "macro"
secureAttributes.macrotext = "/interact"
preClickCallback(Fishing.clickFrame, "RightButton", false)
assert(secureAttributes.type == nil and secureAttributes.macrotext == nil,
    "a stray bobber interaction frame release must clear the captured action")

Fishing:SetFishingState(ns.Fishing.states.PRECASTING)
Fishing.state.castAttempt = 1
Fishing.state.isEquippingPrimaryPole = false
postClickCallback(Fishing.clickFrame, "RightButton", false)
assert(Fishing:IsFishingState(ns.Fishing.states.PRECASTING),
    "secure click release must wait for spellcast confirmation")
assert(#scheduledCallbacks == 1, "failed cast recovery was not scheduled")
scheduledCallbacks[1]()
assert(Fishing:IsFishingState(ns.Fishing.states.IDLE),
    "unconfirmed fishing cast must reset the session to IDLE")

Fishing:SetFishingState(ns.Fishing.states.PRECASTING)
secureAttributes.dreamfish_precast_action = true
secureAttributes.macrotext = "/use item:85500"
postClickCallback(Fishing.clickFrame, "RightButton", false)
assert(#scheduledCallbacks == 1,
    "pre-cast item actions must not schedule failed fishing-cast recovery")
assert(markedRaftToyID == 85500, "clicked raft macro should mark raft recently used")
secureAttributes.dreamfish_precast_action = nil
secureAttributes.macrotext = nil

Fishing:SetFishingState(ns.Fishing.states.PRECASTING)
Fishing.state.pendingBuffUse = { executedAt = currentTime, uses = { { itemID = 238365, category = "other_consumable" } } }
secureAttributes.dreamfish_precast_action = true
secureAttributes.macrotext = "/use item:142528\n/cast [nochanneling] Fishing"
postClickCallback(Fishing.clickFrame, "RightButton", false)
assert(Fishing.state.pendingBuffUse == nil,
    "bobber-only macros must not mark unrelated pending consumables as executed")
secureAttributes.dreamfish_precast_action = nil
secureAttributes.macrotext = nil

profile.castByHotkey = false
local mouseActionsBeforeHotkey = gameMouseActions
preClickCallback(Fishing.clickFrame, "RightButton", true)
assert(gameMouseActions == mouseActionsBeforeHotkey, "only normal world right clicks must continue to the game handler")

profile.castByHotkey = true
rightMouseDown = true
leftMouseDown = true
preClickCallback(Fishing.clickFrame, "RightButton", true)
assert(castStartedCount == 3, "mixed left and right clicks must not trigger the hotkey")
assert(secureAttributes.type == nil, "mixed left and right clicks must clear the captured action")

secureAttributes.type = "macro"
leftMouseDown = false
shiftKeyDown = true
preClickCallback(Fishing.clickFrame, "RightButton", true)
assert(castStartedCount == 3, "modified right clicks must not trigger the hotkey")
assert(secureAttributes.type == nil, "modified right clicks must clear the captured action")

shiftKeyDown = false
rightMouseDown = false

Fishing:SetFishingState(ns.Fishing.states.WAITING_FOR_BITE)
currentTime = 10
mouseDownCallback(WorldFrame, "RightButton")
assert(rightClickStrikeBindingMode ~= "interact",
    "first double-right-click must leave native right-click behavior untouched")
local firstClickArmCallback = scheduledCallbacks[#scheduledCallbacks - 1]
assert(type(firstClickArmCallback) == "function", "native second-click binding was not scheduled")
firstClickArmCallback()
assert(rightClickStrikeBindingMode == "interact",
    "native interaction should arm after the first click event")
currentTime = 10.1
mouseDownCallback(WorldFrame, "RightButton")
assert(rightClickStrikeBindingMode == "interact",
    "second click must keep native interaction bound until its input dispatch completes")
local secondClickRearmCallback = scheduledCallbacks[#scheduledCallbacks]
assert(type(secondClickRearmCallback) == "function", "second-click binding restore was not scheduled")
secondClickRearmCallback()
assert(rightClickStrikeBindingMode == "native",
    "second click must restore native right-click behavior afterward")
currentTime = 12
mouseDownCallback(WorldFrame, "RightButton")
local timeoutArmCallback = scheduledCallbacks[#scheduledCallbacks - 1]
local timeoutRestoreCallback = scheduledCallbacks[#scheduledCallbacks]
timeoutArmCallback()
assert(rightClickStrikeBindingMode == "interact",
    "native interaction should be armed while waiting for a second click")
timeoutRestoreCallback()
assert(rightClickStrikeBindingMode == "native",
    "a single click must restore native right-click behavior after the double-click window")
currentTime = 12.3
mouseDownCallback(WorldFrame, "RightButton")
assert(rightClickStrikeBindingMode == "native",
    "clicks outside the double-click interval must not interact")
profile.strikeByRightClick = true
profile.strikeByDoubleRightClick = false
currentTime = 13
rightClickStrikeBindingMode = "single"
mouseDownCallback(WorldFrame, "RightButton")
assert(rightClickStrikeBindingMode == "single",
    "single-right-click mode must bypass double-click binding transitions")
profile.strikeByRightClick = false
Fishing:SetFishingState(ns.Fishing.states.IDLE)

bindingsCleared = false
Fishing:HideClickFrame()
assert(bindingsCleared, "double-click-only mode must clear the temporary right-click override")

bindingsCleared = false
profile.castBySingleRightClickWhenFishing = true
Fishing:SetFishingState(ns.Fishing.states.PRECASTING)
Fishing:HideClickFrame()
assert(not bindingsCleared, "single-right-click mode must retain the temporary right-click override")

bindingsCleared = false
clickEnabled = true
motionEnabled = true
mouseEnabled = true
frameHidden = false
Fishing:ReleaseClickCapture()
assert(bindingsCleared, "releasing capture must clear temporary right-click bindings")
assert(not clickEnabled, "releasing capture must disable mouse clicks")
assert(not motionEnabled, "releasing capture must disable mouse motion")
assert(not mouseEnabled, "releasing capture must disable generic mouse handling")
assert(frameHidden, "releasing capture must hide the click frame")

Fishing:RemoveClickFrame()

assert(not mouseHooked, "disabling Fishing must unhook WorldFrame mouse observation")
assert(bindingsCleared, "disabling Fishing must clear secure-frame bindings")
assert(not clicksRegistered, "disabling Fishing must clear registered frame clicks")
assert(clicksPropagated, "disabled Fishing frame must propagate mouse clicks")
assert(motionPropagated, "disabled Fishing frame must propagate mouse motion")
assert(clickCallback == nil, "disabling Fishing must remove the click handler")
assert(not clickEnabled, "disabling Fishing must disable mouse clicks")
assert(not motionEnabled, "disabling Fishing must disable mouse motion")
assert(not mouseEnabled, "disabling Fishing must disable generic mouse handling")
assert(frameHidden, "disabling Fishing must hide the secure frame")
assert(anchorsCleared, "disabling Fishing must remove the full-screen frame anchor")
assert(secureAttributes.type2 == nil, "disabling Fishing must clear the right-click action type")
assert(secureAttributes.macrotext2 == nil, "disabling Fishing must clear the right-click macro")

bindingsCleared = false
inCombat = true
Fishing:HookMouseDown()
Fishing:RemoveClickFrame()
assert(not mouseHooked, "combat disable must immediately unhook WorldFrame mouse observation")
assert(cleanupRegistered, "combat teardown must wait for PLAYER_REGEN_ENABLED")
assert(not bindingsCleared, "combat teardown must not mutate the secure frame")

inCombat = false
cleanupCallback()
assert(bindingsCleared, "deferred teardown did not clear secure-frame bindings")
assert(not cleanupRegistered, "deferred teardown did not unregister its cleanup event")

print("fishing_intercept_test: passed")