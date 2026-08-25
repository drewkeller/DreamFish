local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

ns.LootTracker = { Defaults = {
    profile = {
        moduleEnabled = true,
        debug = false,
        -- start of non-prototype options
        minQualityFilter = 0,
        showWindowOnStartup = false,
        windowVisible = true,
        windowPos = {
            point = "CENTER",
            xOfs = 0,
            yOfs = 0,
            width = 280,
            height = 340,
        }
    },
    char = {
        itemsLooted = 0,
        lootedItems = {},
        lootedCurrencies = {},
    }
} }

local LootTracker = DreamFish:NewModule("LootTracker", ns.ModulePrototype, "AceConsole-3.0", "AceEvent-3.0")
LootTracker:Configure({
    displayName = "Loot Tracker",
    dbKey = "lootTracker",
    defaults = ns.LootTracker.Defaults,
    showEnableOption = false,
    childGroups = "tree",
})

function LootTracker:GetModuleOptions()
    return {
        windowTab = self:AddTab({
            type = "group",
            name = "Window",
            args = {
                showWindowOnStartup = self:AddOption({
                    type = "toggle",
                    name = "Show loot tracker on login",
                    desc = "Automatically displays the tracker frame canvas when you log into the character.",
                    width = "full",
                }),
                minQualityFilter = self:AddOption({
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
                toggleUiButton = self:AddOption({
                    type = "execute",
                    name = "Toggle Tracker Window",
                    width = 2,
                    func = function()
                        self:ToggleTrackerWindow()
                    end,
                }),
            }
        }),
    }
end
