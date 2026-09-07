local printedMessages = {}
local modules = {}

local DreamFish = {
    db = {
        profile = {
            debugMode = false,
            sample = {
                moduleEnabled = false,
                debug = false,
            },
        },
        char = {
            sample = {
                count = 0,
            },
        },
    },
}

function DreamFish:Print(...)
    table.insert(printedMessages, { ... })
end

function DreamFish:SetDefaultModulePrototype(prototype)
    self.defaultModulePrototype = prototype
end

function DreamFish:GetModule(name)
    return assert(modules[name], "module not found: " .. tostring(name))
end

function DreamFish.db:RegisterNamespace(name)
    local namespace = {
        profile = DreamFish.db.profile[name],
        char = DreamFish.db.char[name],
        global = {},
        RegisterDefaults = function()
        end,
    }
    return namespace
end

function LibStub(name)
    assert(name == "AceAddon-3.0")
    return {
        GetAddon = function()
            return DreamFish
        end,
    }
end

local namespace = {
    Addon = DreamFish,
    moduleDefaults = {},
    Utils = { DebugModuleSource = function()
    end },
    logLevel = { INFO = 1, TRACE = 2, DEBUG = 3, ALERT = 4 },
}
assert(loadfile("core/module_prototype.lua"))("DreamFish", namespace)

namespace.moduleDefaults.sample = {
    profile = {
        moduleEnabled = true,
        debugEnabled = false,
    },
}
local module = setmetatable({ initialized = false }, { __index = namespace.ModulePrototype })
modules.sample = module

function module:GetName()
    return "sample"
end

function module:GetModuleConfig()
    return {
        moduleName = "sample",
        displayName = "Sample Module",
        dbKey = "sample",
    }
end

function module:SetEnabledState(enabled)
    self.enabled = enabled
end

function module:Enable()
    self.enabled = true
end

function module:Disable()
    self.enabled = false
end

function module:OnModuleInitialize()
    self.initialized = true
end

function module:GetModuleOptions()
    return {
        sampleOption = self:AddOption({
            type = "toggle",
            name = "Sample option",
        }),
        secondOption = self:AddOption({
            type = "toggle",
            name = "Second option",
        }),
    }
end

module:OnInitialize()

assert(module.config.displayName == "Sample Module", "module configuration was not loaded")
assert(module.config.dbKey == "sample", "module database key was not loaded")
assert(module.enabled == false, "saved module state was not applied")
assert(module.initialized, "module initialization hook was not called")

local options = module:GetOptionsTable()
assert(options.args.sampleOption, "module-specific options were not included")
assert(options.args.debugTab.args.debug, "standard module debug option is missing")
assert(options.args.sampleOption.order == 1, "first module option has the wrong order")
assert(options.args.secondOption.order == 2, "second module option has the wrong order")

local rebuiltOptions = module:GetOptionsTable()
assert(rebuiltOptions.args.sampleOption.order == 1, "option order did not reset on rebuild")
assert(rebuiltOptions.args.secondOption.order == 2, "second option order changed on rebuild")

module:SetModuleEnabled(true)
assert(module:IsModuleEnabled(), "enable option did not update the profile")
assert(module.enabled, "enable option did not enable the module")

DreamFish.db.profile.sample.debugEnabled = true
module:Debug("test message")
assert(#printedMessages == 0, "debug output must use the debug utility")

print("module_prototype_test: passed")