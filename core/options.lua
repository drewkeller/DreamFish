local addonName, ns = ...
local Addon = LibStub("AceAddon-3.0"):GetAddon(addonName)
local LootTracker = Addon:GetModule("LootTracker")
local Fishing = Addon:GetModule("Fishing")

function ns:GeneralOptions()
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
                get = function(info) return Addon.db.profile.debugMode end,
                set = function(info, value)
                    Addon.db.profile.debugMode = value
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
                args = (function()
                    if not Addon.db or not Addon.db.profile or not Addon.db.profile.traceMode then
                        return {}
                    end
                    local traceArgs = {}
                    for source, _ in pairs(Addon.db.profile.traceMode) do
                        traceArgs[source] = {
                            order = 1,
                            type = "toggle",
                            name = source,
                            desc = "Enables trace output for the " .. source .. " trace source.",
                            get = function()
                                return Addon.db.profile.traceMode[source]
                            end,
                            set = function(_, value)
                                Addon.db.profile.traceMode[source] = value
                                local state = value and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
                                Addon:Print("Trace source '" .. source .. "' is now " .. state .. ".")
                            end,
                        }
                    end
                    return traceArgs
                end)(),
            },
            spacer = {
                order = 5,
                type = "description",
                name = " ",
                fontSize = "small",
            },
            modulesGroup = {
                type = "group",
                name = "Modules",
                order = 10,
                inline = true,
                args = {
                    fishingEnabled = {
                        type = "toggle",
                        name = "Enable Fishing",
                        desc = "Enables the Fishing module.",
                        order = 2,
                        width = "full",
                        get = function()
                            return Fishing:IsModuleEnabled()
                        end,
                        set = function(_, value)
                            Fishing:SetModuleEnabled(value)
                        end,
                    },
                    lootTrackerEnabled = {
                        type = "toggle",
                        name = "Enable Loot Tracker",
                        desc = "Enables the Loot Tracker module.",
                        order = 3,
                        width = "full",
                        get = function()
                            return LootTracker:IsModuleEnabled()
                        end,
                        set = function(_, value)
                            LootTracker:SetModuleEnabled(value)
                        end,
                    },
                }
            },
        }
    }
    return options
end
-- Keeping it inside a function prevents it from occupying memory before initialization
function ns:GetOptionsTable()
    return ns:GeneralOptions()
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
