local addonName, ns = ...

ns.DreamFish = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")


local globalDB, profileDB, charDB
ns.AddonInitializers = ns.AddonInitializers or {}

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
end

--ns.AddonInitializers = ns.AddonInitializers or {}
