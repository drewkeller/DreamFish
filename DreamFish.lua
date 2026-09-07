-- The second return value (ns) is a private table shared across files
local addonName, ns = ...
local Addon = ns.Addon
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local DialogName = addonName .. "Dialog"

local function RefreshConfigUI()
    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
end

local function MergeOptionsTables(self)
    local options = ns.options
    options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

    -- Merge submodule options into the main options table
    for moduleName, optionTable in pairs(ns.moduleOptions) do
        options.args.modules.args[moduleName] = optionTable
    end
end

function Addon:Error(sourceName, msg, ...)
    assert(msg, "Error message cannot be nil")
    if not sourceName then sourceName = addonName end
    ns.Utils.DebugModuleSource(ns.logLevel.ERROR, self, sourceName, msg, ...)
end

function Addon:Warning(sourceName, msg, ...)
    assert(msg, "Warning message cannot be nil")
    if not sourceName then sourceName = addonName end
    ns.Utils.DebugModuleSource(ns.logLevel.WARNING, self, sourceName, msg, ...)
end

function Addon:Print(msg, ...)
    ns.Utils.DebugModuleSource(ns.logLevel.INFO, self, addonName, msg, ...)
end

function Addon:Info(msg, ...)
    ns.Utils.DebugModuleSource(ns.logLevel.INFO, self, addonName, msg, ...)
end

function Addon:TraceCore(sourceName, msg, ...)
    if not (self.db and self.db.profile and self.db.profile.traces) then
        return
    end
    if self.db.profile.traces[sourceName] then
        ns.Utils.DebugModuleSource(ns.logLevel.TRACE, self, sourceName, msg, ...)
    end
end

function Addon:Debug(message, ...)
    if self.db and self.db.profile and self.db.profile.debugEnabled then
        --ns.Utils.DebugModuleSource(ns.logLevel.DEBUG, self, sourceName, msg, ...)
        ns.Utils.DebugModuleSource(ns.logLevel.DEBUG, self, addonName, message, ...)
    end
end

function Addon:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New(addonName .. "DB", ns.DatabaseDefaults, true)

    -- Set up logging in second SavedVariables table
    self.logDB = self:GetLogDB()
    Addon.logDB = self.logDB
    table.wipe(self.logDB)
    self:Info("Log database initialized") -- with " .. tostring(#self.logDB) .. " entries.")

    --MergeOptionsTables(self)
    self:InitializeTraceSources()

    -- Generate profile options table and register it
    self.profileOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName .. "_Profile", self.profileOptions)

    -- Register a function ref (not a pre-built table) so the options are rebuilt fresh each time the
    -- dialog opens, after modules have finished OnInitialize and registered their trace sources.
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

    self.db.RegisterCallback(self, "OnProfileChanged", RefreshConfigUI)
    self.db.RegisterCallback(self, "OnProfileCopied", RefreshConfigUI)
    self.db.RegisterCallback(self, "OnProfileReset", RefreshConfigUI)
end

function Addon:OnEnable()
    self:RegisterChatCommands()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- for development
    if self.db.profile.debugEnabled then
        C_Timer.After(1, function()
            Addon:OpenDialogWindow("DreamFishDialog")
        end)
    end
end

function Addon:PLAYER_ENTERING_WORLD(event, isLogin, isReload)
    self:Print("Hello World from " .. addonName .. "!")
end
