local messages = {}
local addon = { db = { profile = { debugEnabled = false, debugMode = false } } }
local namespace = {
    Addon = addon,
    logLevel = { TRACE = 1, DEBUG = 2, INFO = 3, WARNING = 4, ERROR = 5 },
    logLevelInfo = {
        { name = "TRACE", color = "999999" },
        { name = "DEBUG", color = "FFFFFF" },
        { name = "INFO", color = "FFFFFF" },
        { name = "WARNING", color = "FFFF00" },
        { name = "ERROR", color = "FF0000" },
    },
}

function GetTime()
    return 3661.125
end

DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, message)
        table.insert(messages, message)
    end,
}

assert(loadfile("utility/debug.lua"))("DreamFish", namespace)

local module = { db = { profile = {
    debugEnabled = false,
    debugMode = false,
    traces = { sample = true },
} } }
local timestamp = "1:01:01.125: "

local function Emit(level, stack)
    namespace.Utils.DebugModuleSourceWithStack(level, module, "sample", stack, "message", "extra")
end

for _, level in ipairs({ 1, 2, 3, 4, 5 }) do
    Emit(level, "stack trace")
end
assert(#addon:GetLogDB() == 0, "disabled module debug must suppress source logs at every level")
assert(#messages == 4, "trace, info, warning and error chat output must remain available")
for _, message in ipairs(messages) do
    assert(message:sub(1, #timestamp) ~= timestamp, "disabled module debug must omit chat timestamps")
    assert(message:find("message extra", 1, true), "message arguments must be preserved")
end

addon.db.profile.debugEnabled = true
Emit(namespace.logLevel.INFO)
assert(#addon:GetLogDB() == 0, "addon debug must not enable a disabled module's source logs")
assert(messages[#messages]:sub(1, #timestamp) ~= timestamp, "module timestamps must not use addon debug")
addon.db.profile.debugEnabled = false

for _, flag in ipairs({ "debugEnabled", "debugMode" }) do
    module.db.profile[flag] = true
    local before = #addon:GetLogDB()
    for _, level in ipairs({ 1, 2, 3, 4, 5 }) do
        Emit(level, "stack trace")
        assert(messages[#messages]:sub(1, #timestamp) == timestamp, flag .. " must enable module timestamps")
    end
    assert(#addon:GetLogDB() == before + 5, flag .. " must enable source logs at every level")
    assert(addon:GetLogDB()[before + 1]:find("[TRACE][sample] message extra", 1, true),
        "source log formatting must be preserved")
    assert(addon:GetLogDB()[before + 5]:find("\nstack trace", 1, true), "error logs must retain the stack")
    module.db.profile[flag] = false
end

namespace.Utils.PrintNoLog(nil, nil, "plain", "extra")
assert(messages[#messages]:sub(1, #timestamp) ~= timestamp, "PrintNoLog must omit timestamps with debug off")
assert(messages[#messages]:find("plain extra", 1, true), "PrintNoLog must preserve its public arguments")
for _, flag in ipairs({ "debugEnabled", "debugMode" }) do
    addon.db.profile[flag] = true
    namespace.Utils.PrintNoLog(nil, nil, "plain")
    assert(messages[#messages]:sub(1, #timestamp) == timestamp, flag .. " must enable PrintNoLog timestamps")
    addon.db.profile[flag] = false
end

namespace.Utils.DebugModuleSource(namespace.logLevel.INFO, {}, "sample", "no profile")
assert(messages[#messages]:sub(1, #timestamp) ~= timestamp, "missing profiles must omit timestamps")

print("utility_debug_test: passed")