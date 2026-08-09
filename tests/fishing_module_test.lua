local modules = {}

local DreamFish = {
    db = {
        profile = {
            debugMode = false,
            fishing = {
                moduleEnabled = true,
                debug = false,
            },
        },
        char = {
            fishing = {},
        },
    },
}

function DreamFish:NewModule(name, prototype)
    local module = setmetatable({}, { __index = prototype })

    function module:SetEnabledState(enabled)
        self.enabled = enabled
    end

    function module:Enable()
        self.enabled = true
    end

    function module:Disable()
        self.enabled = false
    end

    modules[name] = module
    return module
end

function DreamFish:GetModule(name)
    return assert(modules[name], "module not found: " .. name)
end

function DreamFish:Print()
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
assert(loadfile("fishing/fishing.options.lua"))("DreamFish", namespace)
assert(loadfile("fishing/fishing.lua"))("DreamFish", namespace)

local Fishing = DreamFish:GetModule("Fishing")
Fishing:OnInitialize()

assert(Fishing.moduleConfig.displayName == "Fishing", "display name was not configured")
assert(Fishing.moduleConfig.dbKey == "fishing", "database key was not configured")
assert(namespace.DatabaseDefaults.profile.fishing.moduleEnabled, "Fishing defaults were not composed")
assert(Fishing:GetProfileDB() == DreamFish.db.profile.fishing, "profile DB lookup failed")
assert(Fishing:GetCharDB() == DreamFish.db.char.fishing, "character DB lookup failed")
assert(Fishing.enabled, "Fishing did not use its saved enabled state")

local options = Fishing:GetOptionsTable()
assert(options.name == "Fishing", "Fishing options group was not created")
assert(options.args.moduleEnabled, "Fishing enable option is missing")
assert(options.args.moduleOptions.args.debug, "Fishing debug option is missing")

print("fishing_module_test: passed")