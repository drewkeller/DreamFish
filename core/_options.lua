local addonName, ns = ...
local Addon = ns.Addon

ns.moduleDefaults = {}
--ns.moduleOptions = {}
ns.moduleConstants = {}

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
                Addon:Print("Trace source '" .. source .. "' is now " .. state .. ".")
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
        modules = {
            order = 1,
            type = "group",
            name = "Modules",
            handler = ns.Addon,
            inline = true,
            childGroups = "tab", -- Displays sub-modules as tabs
            args = {
                fishingEnabled = {
                    type = "toggle",
                    name = "Enable Fishing",
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
                lootTrackerEnabled = {
                    type = "toggle",
                    name = "Enable Loot Tracker",
                    desc = "Enables the Loot Tracker module.",
                    order = 3,
                    width = "full",
                    get = function()
                        return ns.LootTracker:IsModuleEnabled()
                    end,
                    set = function(_, value)
                        ns.LootTracker:SetModuleEnabled(value)
                    end,
                },
            },
        },
        spacer = {
            order = 5,
            type = "description",
            name = " ",
            fontSize = "small",
        },
        debugMode = {
            type = "toggle",
            name = "Enable Debug Mode",
            desc = "Enables debug mode for the addon, providing additional output for troubleshooting.",
            order = 100,
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
            order = 110,
            type = "group",
            name = "Trace sources",
            inline = true,
            args = GetTraceOptions(),
        },
        log = {
            order = 120,
            type = "group",
            name = "Log Management",
            desc = "Commands for managing the addon log",
            inline = true,
            cmdHidden = false, -- Makes it discoverable via /df help
            args = {
                clear = {
                    type = "execute",
                    name = "Clear Log",
                    desc = "Clears all stored entries in the DreamFish log.",
                    order = 1,
                    func = function()
                        local logDB = Addon:GetLogDB()
                        table.wipe(logDB)
                        Addon:RefreshLogViewer()
                        Addon:Print("Log has been cleared.")
                    end,
                },
                view = {
                    type = "execute",
                    name = "View / Copy Log",
                    desc = "Opens the log in a selectable text box for copying.",
                    order = 2,
                    func = function()
                        Addon:OpenLogViewer()
                    end,
                },
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
