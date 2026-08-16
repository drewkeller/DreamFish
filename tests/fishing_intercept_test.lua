local mouseDownCallback
local preClickCallback
local clickCallback
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
local mouseHooked = false
local gameMouseActions = 0
local castStartedCount = 0
local secureAttributes = {}
local profile = {
    castByDoubleRightClick = true,
    castBySingleRightClickWhenFishing = false,
    castByHotkey = true,
}

local Fishing = {
    clickFrame = {},
}

function Fishing.clickFrame:SetScript(script, callback)
    if script == "PreClick" then
        preClickCallback = callback
    elseif script == "OnClick" then
        clickCallback = callback
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

function Fishing.clickFrame:ClearAllPoints()
    anchorsCleared = true
end

function Fishing.clickFrame:SetFrameStrata()
end

function Fishing.clickFrame:SetAttribute(name, value)
    secureAttributes[name] = value
end

function Fishing:IsEnabled()
    return true
end

function Fishing:IsHooked(frame, script)
    if frame == self.clickFrame and script == "PreClick" then
        return preClickCallback ~= nil
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

function Fishing:Debug()
end

function Fishing:SendMessage(message)
    table.insert(messages, message)
end

local DreamFish = {}

function DreamFish:GetModule(name)
    assert(name == "Fishing")
    return Fishing
end

function LibStub(name)
    assert(name == "AceAddon-3.0")
    return {
        GetAddon = function()
            return DreamFish
        end,
    }
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

function ClearOverrideBindings(frame)
    assert(frame == Fishing.clickFrame)
    bindingsCleared = true
end

local ns = {
    FishingDB = {
        global = {},
        profile = profile,
        char = {},
    },
    precast = {},
}
assert(loadfile("fishing/fishing.intercept.lua"))("DreamFish", ns)
assert(loadfile("fishing/states.lua"))("DreamFish", ns)
for _, initializer in ipairs(ns.FishingInitializers) do
    initializer()
end

function Fishing:OnCastStarted()
    castStartedCount = castStartedCount + 1
end

function Fishing:IsDoubleClick()
    return true
end

Fishing:HookMouseDown()
Fishing:HookPreClickWithHandler()

mouseDownCallback(WorldFrame, "LeftButton")
assert(castStartedCount == 0, "non-right clicks must bypass Fishing")
assert(gameMouseActions == 1, "non-right clicks must reach the game handler")

mouseDownCallback(WorldFrame, "RightButton")
assert(castStartedCount == 1, "enabled double-right-click must call OnCastStarted")

profile.castByDoubleRightClick = false
mouseDownCallback(WorldFrame, "RightButton")
assert(castStartedCount == 1, "disabled double-right-click must not call OnCastStarted")

preClickCallback(Fishing.clickFrame, "RightButton", true)
assert(castStartedCount == 2, "hotkey button-down must start the fishing session")
preClickCallback(Fishing.clickFrame, "RightButton", false)
assert(castStartedCount == 2, "hotkey button-up must not restart the fishing session")

profile.castByHotkey = false
preClickCallback(Fishing.clickFrame, "RightButton", true)
assert(gameMouseActions == 3, "right clicks must also continue to the game handler")

bindingsCleared = false
Fishing:HideClickFrame()
assert(bindingsCleared, "double-click-only mode must clear the temporary right-click override")

bindingsCleared = false
profile.castBySingleRightClickWhenFishing = true
Fishing:SetFishingState(ns.fishing.states.PRECASTING)
Fishing:HideClickFrame()
assert(not bindingsCleared, "single-right-click mode must retain the temporary right-click override")

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