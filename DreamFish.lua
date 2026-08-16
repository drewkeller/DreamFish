-- The second return value (ns) is a private table shared across files
local addonName, ns = ...
local DreamFish = ns.DreamFish

function DreamFish:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("DreamFishDB", ns.DatabaseDefaults, true)
    -- Register a function ref (not a pre-built table) so the options are rebuilt fresh each time the
    -- dialog opens, after module modules have finished OnInitialize and registered their trace sources.
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, function()
        return ns:GetOptionsTable()
    end)
    self.optionsFrame, self.optionsCategoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, addonName)

    self:Print("Loaded profile: " .. self.db:GetCurrentProfile())
end

function DreamFish:OnEnable()
    ns.RegisterChatCommands()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function DreamFish:PLAYER_ENTERING_WORLD(event, isLogin, isReload)
    self:Print("Hello World from DreamFish!")
end
