local addonName, ns = ...

local MessageSink = {}

MessageSink.__index = MessageSink

function MessageSink:new(module)
    local instance = setmetatable({}, self)
    instance.module = module
    return instance
end

function MessageSink:RegisterEvent(event, funcName)
    self.module.RegisterEvent(self, event, funcName)
end

function MessageSink:UnregisterEvent(event)
    self.module.UnregisterEvent(self, event)
end

function MessageSink:RegisterMessage(message, funcName)
    self.module.RegisterMessage(self, message, funcName)
end

function MessageSink:UnregisterMessage(message)
    self.module.UnregisterMessage(self, message)
end

ns.MessageSink = MessageSink
