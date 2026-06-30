-- DreamFisher: Utility Functions

local addon = _G["DreamFisher"]

-- Core utility functions
local function Clamp(value, min, max)
    if value == nil then
        return min
    end
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local clone = {}
    for k, v in pairs(value) do
        clone[k] = DeepCopy(v)
    end
    return clone
end

local function CopyDefaults(source, target)
    for k, v in pairs(source) do
        if target[k] == nil then
            target[k] = DeepCopy(v)
        end
    end
end

local function PrintMessage(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF7FFFDADreamFisher|r " .. msg)
    end
end

local function DebugMessage(msg)
    if addon.db and addon.db.debugMode then
        PrintMessage("|cFF9ACDFF[debug]|r " .. tostring(msg))
    end
end

local function DebugStateMessage(msg)
    if addon.db and addon.db.debugMode and addon.db.debugState then
        DebugMessage(msg)
    end
end

-- Export to addon
addon.utils = {
    Clamp = Clamp,
    DeepCopy = DeepCopy,
    CopyDefaults = CopyDefaults,
    PrintMessage = PrintMessage,
    DebugMessage = DebugMessage,
    DebugStateMessage = DebugStateMessage,
}

-- Also expose at module level for backward compatibility
addon.Clamp = Clamp
addon.DeepCopy = DeepCopy
addon.CopyDefaults = CopyDefaults
addon.PrintMessage = PrintMessage
addon.DebugMessage = DebugMessage
addon.DebugStateMessage = DebugStateMessage
