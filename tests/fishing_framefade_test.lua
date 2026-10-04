local secretAlpha = setmetatable({}, {
    __lt = function() error("secret alpha compared") end,
    __le = function() error("secret alpha compared") end,
})

function issecretvalue(value)
    return rawequal(value, secretAlpha)
end

function LibStub()
    return nil
end

local fadeOutCount, fadeInCount, removeCount = 0, 0, 0

function UIFrameFadeRemoveFrame(frame)
    assert(frame, "missing frame passed to fade removal")
    removeCount = removeCount + 1
end

function UIFrameFadeOut(frame, duration, startAlpha, endAlpha)
    assert(not rawequal(startAlpha, secretAlpha), "secret alpha passed to fade-out")
    assert(startAlpha == frame.alpha)
    fadeOutCount = fadeOutCount + 1
    frame.alpha = endAlpha
end

function UIFrameFadeIn(frame, duration, startAlpha, endAlpha)
    assert(not rawequal(startAlpha, secretAlpha), "secret alpha passed to fade-in")
    assert(startAlpha == frame.alpha)
    fadeInCount = fadeInCount + 1
    frame.alpha = endAlpha
end

local function NewFrame(alpha)
    return {
        alpha = alpha,
        clickEnabled = true,
        IsShown = function() return true end,
        GetAlpha = function(self) return self.alpha end,
        SetAlpha = function(self, value) self.alpha = value end,
        Show = function() end,
        SetMouseClickEnabled = function(self, enabled) self.clickEnabled = enabled end,
    }
end

local function LoadFishing()
    local sink = {}
    local fishing = {
        db = {
            global = {}, char = {},
            profile = {
                frameFocusEnabled = true,
                fadeFrames = {{ frames = {
                    { name = "ElvUF_Target", enabled = true },
                    { name = "ReadableFrame", enabled = true },
                    { name = "MissingFrame", enabled = true },
                } }},
            },
        },
        RegisterTraceSource = function() end,
        Trace = function() end,
        DebugSource = function() end,
        RegisterOnModuleInitialize = function(self, callback) callback(self) end,
        RegisterOnModuleEnable = function() end,
        RegisterOnModuleRegisterEvents = function() end,
        RegisterOnModuleUnregisterEvents = function() end,
        RegisterOnModuleDisable = function() end,
    }
    local namespace = {
        Fishing = fishing,
        MessageSink = { new = function() return sink end },
    }
    assert(loadfile("fishing/framefade.lua"))("DreamFish", namespace)
    return fishing, sink
end

ElvUF_Target = NewFrame(secretAlpha)
ReadableFrame = NewFrame(0.7)
local fishing, sink = LoadFishing()
sink:FISHING_SESSION_STARTED()
assert(fadeOutCount == 1, "readable frame should still fade")
assert(ElvUF_Target.clickEnabled, "secret frame should remain untouched")
assert(removeCount == 1, "secret and missing frames should not cancel fades")
ElvUF_Target.alpha = 0.6
sink:FISHING_SESSION_ENDED()
assert(fadeInCount == 1, "secret frame should not have a cached baseline")
assert(ElvUF_Target.alpha == 0.6)
assert(ReadableFrame.alpha == 0.7, "original alpha should be restored")
assert(ReadableFrame.clickEnabled)

ElvUF_Target = NewFrame(0.8)
fishing, sink = LoadFishing()
sink:FISHING_SESSION_STARTED()
ElvUF_Target.alpha = secretAlpha
local previousFadeInCount, previousRemoveCount = fadeInCount, removeCount
sink:FISHING_SESSION_ENDED()
assert(fadeInCount == previousFadeInCount + 1, "secret fade-in should be skipped")
assert(removeCount == previousRemoveCount + 1, "secret fade-in should not cancel timers")
assert(rawequal(ElvUF_Target.alpha, secretAlpha))

issecretvalue = nil
ElvUF_Target = NewFrame(0.8)
fishing, sink = LoadFishing()
sink:FISHING_SESSION_STARTED()
sink:FISHING_SESSION_ENDED()
assert(ElvUF_Target.alpha == 0.8, "clients without secret-value API should still fade")

print("fishing_framefade_test.lua: OK")