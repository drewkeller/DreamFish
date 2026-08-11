local printedMessages = {}

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

function LibStub(name)
    assert(name == "AceAddon-3.0")
    return {
        GetAddon = function()
            return DreamFish
        end,
    }
end

local namespace = {}
assert(loadfile("core/module_prototype.lua"))("DreamFish", namespace)

local defaults = {
    profile = {
        sample = {
            moduleEnabled = true,
            debug = false,
        },
    },
}
local module = setmetatable({ initialized = false }, { __index = namespace.ModulePrototype })

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

module:Configure({
    displayName = "Sample Module",
    dbKey = "sample",
    defaults = defaults,
})

local secondDefaults = {
    profile = {
        second = {
            moduleEnabled = true,
        },
    },
}
local secondModule = setmetatable({}, { __index = namespace.ModulePrototype })
secondModule:Configure({
    displayName = "Second Module",
    dbKey = "second",
    defaults = secondDefaults,
})

module:OnInitialize()

assert(namespace.DatabaseDefaults.profile.sample.moduleEnabled, "first module defaults were not composed")
assert(namespace.DatabaseDefaults.profile.second.moduleEnabled, "second module defaults replaced the first module")
assert(module.enabled == false, "saved module state was not applied")
assert(module.initialized, "module initialization hook was not called")

local options = module:GetOptionsTable()
assert(options.args.moduleOptions.args.sampleOption, "module-specific options were not included")
assert(options.args.moduleOptions.args.debug, "standard module options were not included")
assert(options.args.moduleOptions.disabled(), "disabled module options should be inactive")
assert(options.args.moduleOptions.args.sampleOption.order == 1, "first module option has the wrong order")
assert(options.args.moduleOptions.args.secondOption.order == 2, "second module option has the wrong order")

local rebuiltOptions = module:GetOptionsTable()
assert(rebuiltOptions.args.moduleOptions.args.sampleOption.order == 1, "option order did not reset on rebuild")
assert(rebuiltOptions.args.moduleOptions.args.secondOption.order == 2, "second option order changed on rebuild")

options.args.moduleEnabled.set(nil, true)
assert(module:IsModuleEnabled(), "enable option did not update the profile")
assert(module.enabled, "enable option did not enable the module")

DreamFish.db.profile.sample.debug = true
module:Debug("test message")
assert(#printedMessages == 1, "module debug setting did not emit output")

print("module_prototype_test: passed")