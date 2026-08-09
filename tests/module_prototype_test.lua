local registeredDefaults
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

function DreamFish.db:RegisterDefaults(defaults)
    registeredDefaults = defaults
end

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
        sampleOption = {
            type = "toggle",
            name = "Sample option",
        },
    }
end

module:Configure({
    displayName = "Sample Module",
    dbKey = "sample",
    defaults = defaults,
})
module:OnInitialize()

assert(registeredDefaults == defaults, "module defaults were not registered")
assert(module:GetProfileDB() == DreamFish.db.profile.sample, "profile DB lookup failed")
assert(module:GetCharDB() == DreamFish.db.char.sample, "character DB lookup failed")
assert(module.enabled == false, "saved module state was not applied")
assert(module.initialized, "module initialization hook was not called")

local options = module:GetOptionsTable()
assert(options.args.moduleOptions.args.sampleOption, "module-specific options were not included")
assert(options.args.moduleOptions.args.debug, "standard module options were not included")
assert(options.args.moduleOptions.disabled(), "disabled module options should be inactive")

options.args.moduleEnabled.set(nil, true)
assert(module:IsModuleEnabled(), "enable option did not update the profile")
assert(module.enabled, "enable option did not enable the module")

DreamFish.db.profile.sample.debug = true
module:Debug("test message")
assert(#printedMessages == 1, "module debug setting did not emit output")

print("module_prototype_test: passed")