local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local ModulePrototype = {}
ns.ModulePrototype = ModulePrototype

local function MergeDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if target[key] == nil then
                target[key] = {}
            end

            assert(type(target[key]) == "table", "Module default conflicts with existing default: " .. key)
            MergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function ModulePrototype:Configure(config)
    assert(type(config) == "table", "Module configuration must be a table")
    assert(config.displayName, "Module configuration requires displayName")
    assert(config.dbKey, "Module configuration requires dbKey")
    assert(config.defaults, "Module configuration requires defaults")

    self.moduleConfig = config
    ns.DatabaseDefaults = ns.DatabaseDefaults or {}
    MergeDefaults(ns.DatabaseDefaults, config.defaults)
    return self
end

function ModulePrototype:IsModuleEnabled()
    return self.db and self.db.profile and self.db.profile.moduleEnabled or false
end

function ModulePrototype:SetModuleEnabled(enabled)
    self.db = self.db or {}
    self.db.profile = self.db.profile or {}
    self.db.profile.moduleEnabled = enabled

    if enabled then
        self:Enable()
    else
        self:Disable()
    end
end

function ModulePrototype:Debug(message, ...)
    if self.db and self.db.profile and self.db.profile.debug then
        DreamFish:Print("|cFF9ACDFF[" .. self.moduleConfig.displayName .. "]|r ", message, ...)
    end
end

function ModulePrototype:Trace(source, msg, ...)
    if self.db and self.db.profile and self.db.profile.traceMode and self.db.profile.traceMode[source] then
        DreamFish:Print("|cFF999999[" .. source .. "]|r ", msg, ...)
    end
end

function ModulePrototype:RegisterTraceSource(source)
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

function ModulePrototype:OnInitialize()
    local addonDB = DreamFish and DreamFish.db

    if addonDB and type(addonDB.RegisterNamespace) == "function" then
        self.db = addonDB:RegisterNamespace(self.moduleConfig.dbKey, self.moduleConfig.defaults)
    else
        local defaults = self.moduleConfig.defaults or {}
        local profileDefaults = type(defaults.profile) == "table"
            and (defaults.profile[self.moduleConfig.dbKey] or defaults.profile)
            or {}
        local charDefaults = type(defaults.char) == "table"
            and (defaults.char[self.moduleConfig.dbKey] or defaults.char)
            or {}
        local globalDefaults = type(defaults.global) == "table"
            and (defaults.global[self.moduleConfig.dbKey] or defaults.global)
            or {}

        local profileNamespace = {}
        local charNamespace = {}
        local globalNamespace = {}

        if addonDB then
            addonDB.profile = type(addonDB.profile) == "table" and addonDB.profile or {}
            addonDB.char = type(addonDB.char) == "table" and addonDB.char or {}
            addonDB.global = type(addonDB.global) == "table" and addonDB.global or {}

            profileNamespace = type(addonDB.profile[self.moduleConfig.dbKey]) == "table"
                and addonDB.profile[self.moduleConfig.dbKey]
                or {}
            charNamespace = type(addonDB.char[self.moduleConfig.dbKey]) == "table"
                and addonDB.char[self.moduleConfig.dbKey]
                or {}
            globalNamespace = type(addonDB.global[self.moduleConfig.dbKey]) == "table"
                and addonDB.global[self.moduleConfig.dbKey]
                or {}

            addonDB.profile[self.moduleConfig.dbKey] = profileNamespace
            addonDB.char[self.moduleConfig.dbKey] = charNamespace
            addonDB.global[self.moduleConfig.dbKey] = globalNamespace
        end

        self.db = {
            profile = profileNamespace,
            char = charNamespace,
            global = globalNamespace,
        }
        MergeDefaults(self.db.profile, profileDefaults)
        MergeDefaults(self.db.char, charDefaults)
        MergeDefaults(self.db.global, globalDefaults)
    end

    self.db = self.db or {}
    self.db.profile = self.db.profile or {}
    self.db.char = self.db.char or {}
    self.db.global = self.db.global or {}

    if self.pendingTraceSources then
        for _, source in ipairs(self.pendingTraceSources) do
            self:RegisterTraceSource(source)
            self:Debug("Adding trace source '" .. source .. "' from pending list")
        end
        self.pendingTraceSources = nil
    end

    self:SetEnabledState(self:IsModuleEnabled())

    if self.OnModuleInitialize then
        self:OnModuleInitialize()
    end
end

function ModulePrototype:OnEnable()
    self:Debug("Enabling")

    if self.OnModuleEnable then
        self:OnModuleEnable()
    end
end

function ModulePrototype:OnDisable()
    if self.OnModuleDisable then
        self:OnModuleDisable()
    end

    self:Debug("Disabled")
end

function ModulePrototype:GetStandardModuleOptions()
    local config = self.moduleConfig

    return {
        header = {
            order = 10,
            type = "header",
            name = config.displayName,
        },
        debug = {
            order = 20,
            type = "toggle",
            name = "Debug mode",
            desc = "Enables debug output for the " .. config.displayName .. " module.",
            get = function()
                return self.db.profile.debug
            end,
            set = function(_, value)
                self.db.profile.debug = value
                local state = value and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
                DreamFish:Print(config.displayName .. " debug mode is now " .. state .. ".")
            end,
        },
        traceGroup = {
            order = 25,
            type = "group",
            name = "Trace sources",
            inline = true,
            args = (function()
                if not self.db or not self.db.profile or not self.db.profile.traceMode then
                    return {}
                end
                local traceArgs = {}
                for source, _ in pairs(self.db.profile.traceMode) do
                    traceArgs[source] = {
                        order = 1,
                        type = "toggle",
                        name = source,
                        desc = "Enables trace output for the " .. source .. " trace source.",
                        get = function()
                            return self.db.profile.traceMode[source]
                        end,
                        set = function(_, value)
                            self.db.profile.traceMode[source] = value
                            local state = value and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
                            DreamFish:Print(config.displayName .. " trace source '" .. source .. "' is now " .. state .. ".")
                        end,
                    }
                end
                return traceArgs
            end)(),
        },
        spacer = {
            order = 30,
            type = "description",
            name = " ",
            fontSize = "small",
        },
    }
end

function ModulePrototype:AddTab(tab)
    assert(type(tab) == "table", "Module tab must be a table")

    self.tabOrder = (self.tabOrder or 0) + 1
    tab.order = self.tabOrder
    return tab
end

function ModulePrototype:AddOption(option)
    assert(type(option) == "table", "Module option must be a table")

    self.optionOrder = (self.optionOrder or 0) + 1
    option.order = self.optionOrder
    return option
end

function ModulePrototype:GetOptionsTable()
    local config = self.moduleConfig
    local moduleOptions = self:GetStandardModuleOptions()
    self.optionOrder = 0
    self.tabOrder = 0

    for key, option in pairs(self:GetModuleOptions()) do
        moduleOptions[key] = option
    end

    local moduleEnabled = function()
        return self:IsModuleEnabled()
    end

    local args = {
        moduleEnabled = {
            order = 0,
            type = "toggle",
            name = "Enable " .. config.displayName,
            desc = "Enables the " .. config.displayName .. " module.",
            get = moduleEnabled,
            set = function(_, value)
                self:SetModuleEnabled(value)
            end,
        },
    }

    if config.childGroups then
        for key, option in pairs(moduleOptions) do
            if option.type == "group" and option.disabled == nil then
                option.disabled = function()
                    return not moduleEnabled()
                end
            end
            args[key] = option
        end
    else
        args.moduleOptions = {
            order = 3,
            type = "group",
            name = " ",
            inline = true,
            disabled = function()
                return not moduleEnabled()
            end,
            args = moduleOptions,
        }
    end

    return {
        name = config.displayName,
        type = "group",
        childGroups = config.childGroups,
        get = function(info)
            return self.db.profile[info[#info]]
        end,
        set = function(info, value)
            self.db.profile[info[#info]] = value
            if self.UpdateDisplayIfVisible then
                self:UpdateDisplayIfVisible()
            end
        end,
        args = args,
    }
end
