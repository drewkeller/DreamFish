local addonName, ns = ...
local Addon = ns.Addon

ns.AddonInitializers = ns.AddonInitializers or {}

function InitializeTraceSources(self)
    if self.pendingTraceSources then
        for _, source in ipairs(self.pendingTraceSources) do
            self:RegisterTraceSource(source)
        end
        self.pendingTraceSources = nil
    end
end

function Addon:CallAddonInitializers()
    self.db.global.windowPositions = self.db.global.windowPositions or {}

    for _, initializerFunc in ipairs(ns.AddonInitializers) do
        initializerFunc(self)
    end

    InitializeTraceSources(self)
end

function Addon:RegisterTraceSource(source)
    if not self.db or not self.db.profile then
        -- Modules often register trace sources at file-load time, before OnInitialize runs
        self.pendingTraceSources = self.pendingTraceSources or {}
        table.insert(self.pendingTraceSources, source)
        return
    end
    if not self.db.profile.traceMode then
        self.db.profile.traceMode = {}
    end
    if not self.db.profile.traceMode[source] then
        self.db.profile.traceMode[source] = false
    end
end

--ns.AddonInitializers = ns.AddonInitializers or {}
