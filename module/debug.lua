local addonName, ns = ...
local Addon = ns.Addon
local ModulePrototype = ns.ModulePrototype

function ModulePrototype:RegisterTraceSource(sourceName, description)
    if not self.registeredTraces then self.registeredTraces = {} end

    self.registeredTraces[sourceName] = description or sourceName

    -- If the database namespace is already active, register the default toggle value
    if self.db and self.db.RegisterDefaults then
        local injection = { profile = { traces = { [sourceName] = false } } }
        self.db:RegisterDefaults(injection)
    end
end

function ModulePrototype:MergePendingTraceSources()
    assert(self.db and self.db.profile, "Database namespace must be initialized before finalizing pending trace sources")

    self.db.profile.traces = self.db.profile.traces or {}

    if self.pendingTraceSources then
        for _, source in ipairs(self.pendingTraceSources) do
            self:RegisterTraceSource(source)
        end
        self.pendingTraceSources = nil
    end
end

function ModulePrototype:Print(msg, ...)
    ns.Utils.DebugModuleSource(ns.logLevel.INFO, self, "", msg, ...)
end

function ModulePrototype:Trace(sourceName, msg, ...)
    if not (self.db and self.db.profile and self.db.profile.traces) then
        return
    end
    if self.db.profile.traces[sourceName] then
        ns.Utils.DebugModuleSource(ns.logLevel.TRACE, self, sourceName, msg, ...)
    end
end

function ModulePrototype:DebugSource(sourceName, msg, ...)
    if self.db and self.db.profile and self.db.profile.debugEnabled then
        ns.Utils.DebugModuleSource(ns.logLevel.DEBUG, self, sourceName, msg, ...)
    end
end

function ModulePrototype:Debug(msg, ...)
    if self.db and self.db.profile and self.db.profile.debugEnabled then
        --ns.Utils.DebugModuleSource(ns.logLevel.DEBUG, self, sourceName, msg, ...)
        ns.Utils.DebugModuleSource(ns.logLevel.DEBUG, self, self.config.moduleName, msg, ...)
    end
end

function ModulePrototype:Alert(msg, ...)
    ns.Utils.DebugModuleSource(ns.logLevel.ALERT, self, self.config.moduleName, msg, ...)
end
