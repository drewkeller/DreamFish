-- The second return value (ns) is a private table shared across files
local addonName, ns = ...
local DreamFish = ns.DreamFish

function DreamFish:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("DreamFishDB", ns.DatabaseDefaults, true)
    local options = ns.GetOptionsTable()
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, options)
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
