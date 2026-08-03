local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

function DreamFish:Debug(msg, ...)
    if self.db.profile.debugMode then
        self:Print("|cFF9ACDFF[Debug]|r ", msg, ...)
    end
end
