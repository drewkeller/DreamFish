-- The second return value (ns) is a private table shared across files
local addonName, ns = ...
Addon = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
ns.Addon = Addon
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local DialogName = addonName .. "Dialog"

local function RefreshConfigUI()
    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
end

function Addon:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New(addonName .. "DB", ns.DatabaseDefaults, true)

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
    local Fishing = Addon:GetModule("Fishing")
    local LootTracker = Addon:GetModule("LootTracker")

    AceConfig:RegisterOptionsTable(addonName .. "_Fishing", function()
        return Fishing:GetOptionsTable()
    end)
    AceConfig:RegisterOptionsTable(addonName .. "_LootTracker", function()
        return LootTracker:GetOptionsTable()
    end)

    AceConfig:RegisterOptionsTable(DialogName, ns.DialogOptions)
    AceConfigDialog:SetDefaultSize(DialogName, 400, 700)
    Addon:SetDefaultPosition(DialogName, 50, 1080)

    -- Nest these items as subcategories below the addon's main menu item
    AceConfigDialog:AddToBlizOptions(addonName .. "_Fishing", "Fishing", addonName)
    AceConfigDialog:AddToBlizOptions(addonName .. "_LootTracker", "Loot Tracker", addonName)
    AceConfigDialog:AddToBlizOptions(addonName .. "_Profile", "Profiles", addonName)

    self:Print("Loaded profile: " .. self.db:GetCurrentProfile())
    self:CallAddonInitializers()

    self.db.RegisterCallback(self, "OnProfileChanged", RefreshConfigUI)
    self.db.RegisterCallback(self, "OnProfileCopied", RefreshConfigUI)
    self.db.RegisterCallback(self, "OnProfileReset", RefreshConfigUI)
end

function Addon:OnEnable()
    self:RegisterChatCommands()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function Addon:PLAYER_ENTERING_WORLD(event, isLogin, isReload)
    self:Print("Hello World from " .. addonName .. "!")
end
