local addonName, ns = ...
local Addon = ns.Addon

ns.moduleDefaults = {}
--ns.moduleOptions = {}
ns.moduleConstants = {}
ns.moduleInitializers = {}

local function GetTraceOptions()
    local traceOptions = {}
    for source, _ in pairs(Addon.db.profile.traces) do
        traceOptions[source] = {
            order = 1,
            type = "toggle",
            name = source,
            desc = "Enables trace output for the " .. source .. " trace source.",
            get = function()
                return Addon.db.profile.traces[source]
            end,
            set = function(_, value)
                Addon.db.profile.traces[source] = value
                local state = value and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
                ns.Utils.Print("Trace source '" .. source .. "' is now " .. state .. ".")
            end,
        }
    end
    return traceOptions
end

local function GetOptions()
    local options = {
    name = "General",
    type = "group",
    args = {
        debugMode = {
            type = "toggle",
            name = "Enable Debug Mode",
            desc = "Enables debug mode for the addon, providing additional output for troubleshooting.",
            order = 1,
            width = "full",
            get = function(info) return Addon.db.profile.debugEnabled end,
            set = function(info, value)
                Addon.db.profile.debugEnabled = value
                if value then
                    Addon:Print("Debug Mode is now |cFF00FF00ON|r.")
                else
                    Addon:Print("Debug Mode is now |cFFFF0000OFF|r.")
                end
            end,
        },
        traceGroup ={
            order = 2,
            type = "group",
            name = "Trace sources",
            inline = true,
            args = GetTraceOptions(),
        },
        spacer = {
            order = 5,
            type = "description",
            name = " ",
            fontSize = "small",
        },
        modules = {
            order = 10,
            type = "group",
            name = "Modules",
            handler = ns.Addon,
            inline = true,
            childGroups = "tab", -- Displays sub-modules as tabs
            args = {
                fishingEnabled = {
                    type = "toggle",
                    name = "(deprecated) Enable Fishing",
                    desc = "Enables the Fishing module.",
                    order = 2,
                    width = "full",
                    get = function()
                        return ns.Fishing:IsModuleEnabled()
                    end,
                    set = function(_, value)
                        ns.Fishing:SetModuleEnabled(value)
                    end,
                },
                -- lootTrackerEnabled = {
                --     type = "toggle",
                --     name = "(deprecated) Enable Loot Tracker",
                --     desc = "Enables the Loot Tracker module.",
                --     order = 3,
                --     width = "full",
                --     get = function()
                --         return LootTracker:IsModuleEnabled()
                --     end,
                --     set = function(_, value)
                --         LootTracker:SetModuleEnabled(value)
                --     end,
                -- },
        --      }
            },
        },
    }
} -- options
    return options
end

-- Keeping it inside a function prevents it from occupying memory before initialization
function ns:GetOptionsTable()
    return GetOptions()
    -- return ns.options
    -- local options = {
    --     name = addonName,
    --     type = "group",
    --     args = {
    --         general = ns:GeneralOptions(),
    --         -- fishing = Fishing:GetOptionsTable(),
    --         -- lootTracker = LootTracker:GetOptionsTable(),
    --     }
    -- }

    -- local layoutSequence = {
    --     "general",
    --     "fishing",
    --     "lootTracker"
    -- }

    -- for index, key in ipairs(layoutSequence) do
    --     if options.args[key] then
    --         options.args[key].order = index * 10
    --     end
    -- end

    -- return options
end
