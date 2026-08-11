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
    return self.db.profile.moduleEnabled
end

function ModulePrototype:SetModuleEnabled(enabled)
    self.db.profile.moduleEnabled = enabled

    if enabled then
        self:Enable()
    else
        self:Disable()
    end
end

function ModulePrototype:Debug(message, ...)
    if self.db.profile.debug then
        DreamFish:Print("|cFF9ACDFF[" .. self.moduleConfig.displayName .. "]|r ", message, ...)
    end
end

function ModulePrototype:OnInitialize()
    self.db = DreamFish.db.RegisterNamespace(self.moduleConfig.dbKey, self.moduleConfig.defaults)
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
