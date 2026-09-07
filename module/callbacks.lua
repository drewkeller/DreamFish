local addonName, ns = ...
local Addon = ns.Addon
local ModulePrototype = ns.ModulePrototype

local callbacks = {
    OnModuleInitialize = {},
    OnModuleEnable = {},
    OnModuleRegisterEvents = {},
    OnModuleUnregisterEvents = {},
    OnModuleDisable = {},
}

local function RegisterCallback(module, callbackType, callback)
    assert(type(callback) == "function", "Module callback must be a function")
    callbacks[callbackType][module] = callbacks[callbackType][module] or {}
    table.insert(callbacks[callbackType][module], callback)
end

function ModulePrototype:RegisterOnModuleInitialize(callback)
    RegisterCallback(self, "OnModuleInitialize", callback)
end

function ModulePrototype:RegisterOnModuleEnable(callback)
    RegisterCallback(self, "OnModuleEnable", callback)
end

function ModulePrototype:RegisterOnModuleRegisterEvents(callback)
    RegisterCallback(self, "OnModuleRegisterEvents", callback)
end

function ModulePrototype:RegisterOnModuleUnregisterEvents(callback)
    RegisterCallback(self, "OnModuleUnregisterEvents", callback)
end

function ModulePrototype:RegisterOnModuleDisable(callback)
    RegisterCallback(self, "OnModuleDisable", callback)
end

local function FireRegisteredCallbacks(self, callbackType, ...)
    local registered = callbacks[callbackType] and callbacks[callbackType][self]
    if registered then
        for _, callback in ipairs(registered) do
            callback(self, ...)
        end
    end
end

ModulePrototype.FireRegisteredCallbacks = FireRegisteredCallbacks