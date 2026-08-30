local addonName, ns = ...
local Addon = ns.Addon
local LootTracker = ns.LootTracker

local function AddTab(tab)
    tab.order = tab.order or 1
    tab.args = tab.args or {}
    return tab
end

local function AddOption(option)
    option.order = option.order or 1
    return option
end

function LootTracker:GetModuleConfig()
    return {
        moduleName = "LootTracker",
        displayName = "Loot Tracker",
        dbKey = "lootTracker",
        defaults = ns.moduleDefaults.LootTracker,
        showEnableOption = false,
        childGroups = "tree",
    }
end

function LootTracker:GetModuleOptions()
    local options = {
        windowTab = AddTab({
            type = "group",
            name = "Window",
            args = {
                showWindowOnStartup = AddOption({
                    type = "toggle",
                    name = "Show loot tracker on login",
                    desc = "Automatically displays the tracker frame canvas when you log into the character.",
                    width = "full",
                }),
                minQualityFilter = AddOption({
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
                }),
                toggleUiButton = AddOption({
                    type = "execute",
                    name = "Toggle Tracker Window",
                    width = 2,
                    func = function()
                        ns.Addon:GetModule("LootTracker"):ToggleTrackerWindow()
                    end,
                }),
            }
        }), -- Window tab
    }
    return options
end