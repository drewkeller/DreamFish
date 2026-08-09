local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local LootTracker = DreamFish:GetModule("LootTracker")
local Fishing = DreamFish:GetModule("Fishing")

function ns:GeneralOptions()
    local options = {
        name = "General",
        type = "group",
        args = {
            header = {
                type = "header",
                name = "General Settings",
                order = 0,
            },
            spacer = {
                type = "description",
                name = " ",
                order = 1,
                fontSize = "small",
            },
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
        }
    }
    return options
end
-- Keeping it inside a function prevents it from occupying memory before initialization
function ns:GetOptionsTable()
    local options = {
        name = "DreamFish",
        type = "group",
        args = {
            general = ns:GeneralOptions(),
            fishing = Fishing:GetOptionsTable(),
            lootTracker = LootTracker:GetOptionsTable(),
        }
    }

    local layoutSequence = {
        "general",
        "fishing",
        "lootTracker"
    }

    for index, key in ipairs(layoutSequence) do
        if options.args[key] then
            options.args[key].order = index * 10
        end
    end

    return options
end
