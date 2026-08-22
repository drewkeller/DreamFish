local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local LootTracker = DreamFish:GetModule("LootTracker")
local Fishing = DreamFish:GetModule("Fishing")

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
                get = function(info) return DreamFish.db.profile.debugMode end,
                set = function(info, value)
                    DreamFish.db.profile.debugMode = value
                    if value then
                        DreamFish:Print("Debug Mode is now |cFF00FF00ON|r.")
                    else
                        DreamFish:Print("Debug Mode is now |cFFFF0000OFF|r.")
                    end
                end,
            },
            traceGroup ={
                order = 2,
                type = "group",
                name = "Trace sources",
                inline = true,
                args = (function()
                    if not DreamFish.db or not DreamFish.db.profile or not DreamFish.db.profile.traceMode then
                        return {}
                    end
                    local traceArgs = {}
                    for source, _ in pairs(DreamFish.db.profile.traceMode) do
                        traceArgs[source] = {
                            order = 1,
                            type = "toggle",
                            name = source,
                            desc = "Enables trace output for the " .. source .. " trace source.",
                            get = function()
                                return DreamFish.db.profile.traceMode[source]
                            end,
                            set = function(_, value)
                                DreamFish.db.profile.traceMode[source] = value
                                local state = value and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
                                DreamFish:Print("Trace source '" .. source .. "' is now " .. state .. ".")
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
    --     name = "DreamFish",
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
