-- The second return value (ns) is a private table shared across files
local addonName, ns = ...
local DreamFish = ns.DreamFish

local function RefreshConfigUI()
    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
end

function DreamFish:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("DreamFishDB", ns.DatabaseDefaults, true)

    -- Generate profile options table and register it
    self.profileOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName .. "_Profile", self.profileOptions)

    -- Register a function ref (not a pre-built table) so the options are rebuilt fresh each time the
    -- dialog opens, after module modules have finished OnInitialize and registered their trace sources.
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, function()
        return ns:GetOptionsTable()
    end)

    -- Add config options to the Blizzard interface options dialog
    self.optionsFrame, self.optionsCategoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, addonName)

    -- Set up "live loading" of module options tables when the user opens the
    -- config dialog, so that modules can populate items dependent on OnInitialize
    -- before the options table is built.
    local Fishing = DreamFish:GetModule("Fishing")
    local LootTracker = DreamFish:GetModule("LootTracker")

    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName .. "_Fishing", function()
        return Fishing:GetOptionsTable()
    end)
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName .. "_LootTracker", function()
        return LootTracker:GetOptionsTable()
    end)

    LibStub("AceConfig-3.0"):RegisterOptionsTable("DreamFishDialog", ns.DreamFishDialogOptions)

    -- Nest these items as subcategories below the addon's main menu item
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName .. "_Fishing", "Fishing", addonName)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName .. "_LootTracker", "Loot Tracker", addonName)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName .. "_Profile", "Profiles", addonName)

    self:Print("Loaded profile: " .. self.db:GetCurrentProfile())
    ns.CallAddonInitializers(self)

    self.db.RegisterCallback("DreamFish", "OnProfileChanged", RefreshConfigUI)
    self.db.RegisterCallback("DreamFish", "OnProfileCopied", RefreshConfigUI)
    self.db.RegisterCallback("DreamFish", "OnProfileReset", RefreshConfigUI)
end

function DreamFish:OnEnable()
    ns.RegisterChatCommands()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function DreamFish:PLAYER_ENTERING_WORLD(event, isLogin, isReload)
    self:Print("Hello World from DreamFish!")
end
