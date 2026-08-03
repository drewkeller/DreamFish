local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local LootTracker = DreamFish:GetModule("LootTracker", true) or DreamFish:NewModule("LootTracker", "AceConsole-3.0", "AceEvent-3.0")

ns.LootTracker = { Defaults = {
    profile = {
        lootTracker = {
            minQualityFilter = 0,
            moduleEnabled = true,
            showWindowOnStartup = false,
            windowVisible = true,
            windowPos = {
                point = "CENTER",
                xOfs = 0,
                yOfs = 0,
                width = 280,
                height = 340,
            }
        }
    },
    char = {
        lootTracker = {
            itemsLooted = 0,
            lootedItems = {},
            lootedCurrencies = {},
        }
    }
} }

function LootTracker:GetOptionsTable()
    local options = {
        name = "Loot Tracker",
        type = "group",
        get = function(info) return DreamFish.db.profile.lootTracker[info[#info]] end,
        set = function(info, value)
            DreamFish.db.profile.lootTracker[info[#info]] = value
            LootTracker:UpdateDisplayIfVisible()
        end,
        args = {
            moduleEnabled = {
                order = 0,
                type = "toggle",
                name = "Enable Loot tracker",
                desc = "Enables the loot tracker module and its associated UI window.",
                get = function(info) return DreamFish.db.profile.lootTracker.moduleEnabled end,
                set = function(info, value)
                    DreamFish:Print("Loot Tracker module enabling: " .. tostring(value))
                    DreamFish.db.profile.lootTracker.moduleEnabled = value
                    if value then
                        DreamFish:EnableModule("LootTracker")
                    else
                        DreamFish:DisableModule("LootTracker")
                    end
                end,
            },
            moduleOptions = {
                order = 3,
                type = "group",
                name = " ",
                inline = true,
                disabled = function() return not DreamFish.db.profile.lootTracker.moduleEnabled end,
                args = {
                    header = {
                        order = 1,
                        type = "header",
                        name = "Loot Tracker",
                    },
                    spacer = {
                        order = 2,
                        type = "description",
                        name = " ",
                        fontSize = "small",
                    },
                    showWindowOnStartup = {
                        order = 3,
                        type = "toggle",
                        name = "Show loot tracker on login",
                        desc = "Automatically displays the tracker frame canvas when you log into the character.",
                        width = "full",
                    },
                    minQualityFilter = {
                        order = 4,
                        type = "select",
                        name = "Minimum quality filter",
                        desc = "Filters your text layout view logs based on item rarity rankings.",
                        width = 3,
                        values = {
                            [0] = "|cFF9d9d9dPoor (Gray)|r",
                            [1] = "|cFFFFFFFFCommon (White)|r",
                            [2] = "|cFF1eff00Uncommon (Green)|r",
                            [3] = "|cFF0070ddRare (Blue)|r",
                            [4] = "|cFFa335eeEpic (Purple)|r",
                        },
                    },
                    toggleUiButton = {
                        order = 5,
                        type = "execute",
                        name = "Toggle Tracker Window",
                        width = 2,
                        func = function()
                            LootTracker:ToggleTrackerWindow()
                        end,
                    }
                }
            }
        }
    }
    return options
end
