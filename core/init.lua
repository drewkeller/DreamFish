local addonName, ns = ...
DreamFish = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
ns.DreamFish = DreamFish


local globalDB, profileDB, charDB
ns.AddonInitializers = ns.AddonInitializers or {}

function InitializeTraceSources(self)
    if self.pendingTraceSources then
        for _, source in ipairs(self.pendingTraceSources) do
            self:RegisterTraceSource(source)
        end
        self.pendingTraceSources = nil
    end
end

function ns.CallAddonInitializers(self)
    -- access the database within "Fishing" functions using self.db
    -- In local functions, use ns.DreamFishDB
    ns.DreamFishDB = self.db

    globalDB = ns.DreamFishDB.global
    profileDB = ns.DreamFishDB.profile
    charDB = ns.DreamFishDB.char

    globalDB.windowPositions = globalDB.windowPositions or {}

    for _, initializerFunc in ipairs(ns.AddonInitializers) do
        initializerFunc(self)
    end

    InitializeTraceSources(self)
end

function DreamFish:RegisterTraceSource(source)
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
