local addonName, ns = ...
local Addon = ns.Addon

local ModulePrototype = {}
ns.ModulePrototype = ModulePrototype

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

function ModulePrototype:OnInitialize()
    local moduleName = self:GetName()

    self.config = self:GetModuleConfig()
    assert(type(self.config) == "table", "Module configuration must be a table")
    assert(self.config.moduleName, "Module configuration requires moduleName")
    assert(self.config.displayName, "Module configuration requires displayName")
    assert(self.config.dbKey, "Module configuration requires dbKey")

    self.db = Addon.db:RegisterNamespace(moduleName, {
        profile = {},
        char = {},
        global = {},
    })

    if self.db and ns.moduleDefaults and ns.moduleDefaults[moduleName] then
        local defaults = ns.moduleDefaults[moduleName]
        self.db:RegisterDefaults(defaults)
    end

    self:MergePendingTraceSources()

    -- Let the main module perform its logic first
    -- then call any listeners
    assert(self.db, "Module seems to have lost its database")
    assert(self.db.global, "Module must have a global section in its database")
    assert(self.db.profile, "Module must have a profile in its database")
    assert(self.db.char, "Module must have a char section in its database")
    if self.OnModuleInitialize then
        self:OnModuleInitialize()
    end
    --self:Debug("Firing " .. moduleName:upper() .. " OnModuleInitialize message for " .. tostring(self.config.moduleName))
    ns.ModulePrototype.FireRegisteredCallbacks(self, "OnModuleInitialize")

    self:SetEnabledState(self:IsModuleEnabled())
end

function ModulePrototype:OnEnable()
    assert(self.db, "Module seems to have lost its database")
    assert(self.db.global, "Module must have a global section in its database")
    assert(self.db.profile, "Module must have a profile in its database")
    assert(self.db.char, "Module must have a char section in its database")
    if self.OnModuleEnable then
        self:OnModuleEnable()
    end
    ns.ModulePrototype.FireRegisteredCallbacks(self, "OnModuleEnable")


    if self.OnModuleRegisterEvents then
        self:OnModuleRegisterEvents()
    end
    ns.ModulePrototype.FireRegisteredCallbacks(self, "OnModuleRegisterEvents")
end

function ModulePrototype:OnDisable()
    if self.OnModuleUnregisterEvents then
        self:OnModuleUnregisterEvents()
    end
    ns.ModulePrototype.FireRegisteredCallbacks(self, "OnModuleUnregisterEvents")

    if self.OnModuleDisable then
        self:OnModuleDisable()
    end
    ns.ModulePrototype.FireRegisteredCallbacks(self, "OnModuleDisable")
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

function ModulePrototype:GetDebugGroup()
    assert(self.config.moduleName, "Module configuration requires moduleName")
    assert(self.config.displayName, "Module configuration requires displayName")

    local Addon = ns.Addon
    local config = self.config
    local moduleName = config.moduleName
    local targetModule = Addon:GetModule(moduleName)

    -- Scan the module's registered trace sources dynamically
    local traceArgs = {}
    local orderIdx = 1

    if targetModule.registeredTraces then
        for sourceName, description in pairs(targetModule.registeredTraces) do
            traceArgs[sourceName] = {
                name = sourceName,
                desc = description, -- Adds a tooltip in the Blizzard UI
                type = "toggle",
                order = orderIdx,
            }
            orderIdx = orderIdx + 1
        end
    end

    local options = {
        debugTab = {
            order = 999,
            type = "group",
            name = "Debug",
            childGroups = config.childGroups or "tree",
            args = {
                debug = {
                    order = 1,
                    type = "toggle",
                    name = "Debug mode",
                    desc = "Enables debug output for the " .. config.displayName .. " module.",
                    get = function()
                        return targetModule.db.profile.debugEnabled
                    end,
                    set = function(_, value)
                        targetModule.db.profile.debugEnabled = value
                        local state = value and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
                        self:Info(config.displayName .. " debug mode is now " .. state .. ".")
                    end,
                },
                traceGroup ={
                    order = 2,
                    type = "group",
                    name = "Trace sources",
                    inline = true,
                    disabled = function() return not targetModule.db.profile.debugEnabled end,
                    get = function(info) return targetModule.db.profile.traces[info[#info]] end,
                    set = function(info, value)
                        targetModule.db.profile.traces[info[#info]] = value
                        local state = value and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
                        Addon:Print("Trace source '" .. info[#info] .. "' is now " .. state .. ".")
                    end,
                    args = traceArgs, -- Dynamically injected from the loop above
                },
            },
        },
    }

    return options
end

function ModulePrototype:GetOptionsTable()
    local config = self.config
    self.optionOrder = 0
    self.tabOrder = 0

    local optionsRoot = {
        name = config.displayName,
        type = "group",
        childGroups = config.childGroups or "tree",
        get = function(info)
            return self.db.profile[info[#info]]
        end,
        set = function(info, value)
            self.db.profile[info[#info]] = value
            if self.UpdateDisplayIfVisible then
                self:UpdateDisplayIfVisible()
            end
        end,
        args = {}
    }

    local moduleOptions = self:GetModuleOptions()
    local debugOptions = self:GetDebugGroup()

    -- put module tabs as children into the root args
    if moduleOptions then
        for key, value in pairs(moduleOptions) do
            optionsRoot.args[key] = value
        end
    end
    if debugOptions then
        for key, value in pairs(debugOptions) do
            optionsRoot.args[key] = value
        end
    end

    return optionsRoot
end

-- Inform the addon that all future NewModule calls should receive this blueprint
ns.Addon:SetDefaultModulePrototype(ModulePrototype)
