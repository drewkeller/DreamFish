local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local ModulePrototype = {}
ns.ModulePrototype = ModulePrototype

function ModulePrototype:Configure(config)
    assert(type(config) == "table", "Module configuration must be a table")
    assert(config.displayName, "Module configuration requires displayName")
    assert(config.dbKey, "Module configuration requires dbKey")
    assert(config.defaults, "Module configuration requires defaults")

    self.moduleConfig = config
    return self
end

function ModulePrototype:GetProfileDB()
    return DreamFish.db.profile[self.moduleConfig.dbKey]
end

function ModulePrototype:GetCharDB()
    return DreamFish.db.char[self.moduleConfig.dbKey]
end

function ModulePrototype:IsModuleEnabled()
    return self:GetProfileDB().moduleEnabled
end

function ModulePrototype:SetModuleEnabled(enabled)
    self:GetProfileDB().moduleEnabled = enabled

    if enabled then
        self:Enable()
    else
        self:Disable()
    end
end

function ModulePrototype:Debug(message, ...)
    local profile = self:GetProfileDB()
    if DreamFish.db.profile.debugMode or profile.debug then
        DreamFish:Print("|cFF9ACDFF[" .. self.moduleConfig.displayName .. "]|r ", message, ...)
    end
end

function ModulePrototype:OnInitialize()
    DreamFish.db:RegisterDefaults(self.moduleConfig.defaults)
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
                return self:GetProfileDB().debug
            end,
            set = function(_, value)
                self:GetProfileDB().debug = value
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

function ModulePrototype:GetOptionsTable()
    local profile = function()
        return self:GetProfileDB()
    end
    local config = self.moduleConfig
    local moduleOptions = self:GetStandardModuleOptions()

    for key, option in pairs(self:GetModuleOptions()) do
        moduleOptions[key] = option
    end

    return {
        name = config.displayName,
        type = "group",
        get = function(info)
            return profile()[info[#info]]
        end,
        set = function(info, value)
            profile()[info[#info]] = value
            if self.UpdateDisplayIfVisible then
                self:UpdateDisplayIfVisible()
            end
        end,
        args = {
            moduleEnabled = {
                order = 0,
                type = "toggle",
                name = "Enable " .. config.displayName,
                desc = "Enables the " .. config.displayName .. " module.",
                get = function()
                    return self:IsModuleEnabled()
                end,
                set = function(_, value)
                    self:SetModuleEnabled(value)
                end,
            },
            moduleOptions = {
                order = 3,
                type = "group",
                name = " ",
                inline = true,
                disabled = function()
                    return not self:IsModuleEnabled()
                end,
                args = moduleOptions,
            },
        },
    }
end
