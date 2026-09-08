local addonName, ns = ...
local Addon = ns.Addon
local LootTracker = ns.LootTracker

local tabOrder = 0
local optionOrder = 0

local function AddTab(tab)
    assert(type(tab) == "table", "Module tab must be a table")

    tabOrder = (tabOrder or 0) + 1
    tab.order = tabOrder
    optionOrder = 0
    return tab
end

local function AddOption(option)
    assert(type(option) == "table", "Module option must be a table")

    optionOrder = (optionOrder or 0) + 1
    option.order = optionOrder
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

function LootTracker:GetLootModeSelectionList()
    local selectionList = {}
    for _, mode in ipairs(LootTracker.const.LootModes) do
        selectionList[mode.id] = mode.name
    end
    return selectionList
end

function LootTracker:GetLootModeSelectionOrder()
    local orderedList = {}
    for _, mode in ipairs(LootTracker.const.LootModes) do
        table.insert(orderedList, mode.id)
    end
    return orderedList
end

local function GetSituationValues(situationKey)
    return function(info)
        return LootTracker.db.profile[situationKey][info[#info]]
    end
end

local function SetSituationValues(situationKey)
    return function(info, value)
        LootTracker.db.profile[situationKey][info[#info]] = value
    end
end

function LootTracker:GetModuleOptions()
    local options = {
        lootModeTab = AddTab({
            type = "group",
            name = "Loot Modes",
            args = {
                lootModeWhenFishing = AddOption({
                    type = "group",
                    name = "Loot mode when fishing",
                    desc = "Loot mode settings to use when fishing.",
                    width = "normal",
                    inline = true,
                    get = GetSituationValues("lootModeWhenFishing"),
                    set = SetSituationValues("lootModeWhenFishing"),
                    args = {
                        lootMode = AddOption({
                            type = "select",
                            name = "",
                            desc = "The loot mode to use when fishing.",
                            width = "full",
                            values = LootTracker:GetLootModeSelectionList(),
                            sorting = LootTracker:GetLootModeSelectionOrder(),
                        }),
                        ignoreJunk = AddOption({
                            type = "toggle",
                            name = "Managed: Ignore junk items",
                            desc = "When checked, junk-quality items are not automatically looted.",
                            width = "full",
                            disabled = function()
                                local situation = LootTracker.db.profile.lootModeWhenFishing
                                return not (situation.lootMode == "managed")
                            end,
                        }),
                        indentSpacer = AddOption({
                            type = "description",
                            name = " ",
                            width = 0.15, -- Tweak this decimal to adjust how far right the box shifts
                        }),
                        stayOpenForJunk = AddOption({
                            type = "toggle",
                            name = "Keep loot window open if it has junk",
                            desc = "If the loot window contains unlooted items to ignore, keep the window open.\n"
                                .. "If unchecked (see warning below), the loot window auto-closes even it if contains unlooted junk.",
                            width = 1.8,
                            disabled = function()
                                local situation = LootTracker.db.profile.lootModeWhenFishing
                                return not (situation.lootMode == "managed" and situation.ignoreJunk)
                            end,
                        }),
                    }
                }),
                spacer1 = AddOption({
                    type = "description",
                    name = " ",
                    fontSize = "medium",
                }),
                lootModeWhenOther = AddOption({
                    type = "group",
                    name = "Loot mode when not fishing",
                    inline = true,
                    get = GetSituationValues("lootModeWhenOther"),
                    set = SetSituationValues("lootModeWhenOther"),
                    args = {
                        lootMode = AddOption({
                            type = "select",
                            name = "",
                            desc = "The loot mode to use when not fishing.",
                            width = "full",
                            values = LootTracker:GetLootModeSelectionList(),
                            sorting = LootTracker:GetLootModeSelectionOrder(),
                        }),
                        ignoreJunk = AddOption({
                            type = "toggle",
                            name = "Managed: Ignore junk items",
                            desc = "When checked, junk-quality items are not automatically looted.",
                            width = "full",
                            disabled = function()
                                local situation = LootTracker.db.profile.lootModeWhenOther
                                return not (situation.lootMode == "managed")
                            end,
                        }),
                        indentSpacer2 = AddOption({
                            type = "description",
                            name = " ",
                            width = 0.15, -- Tweak this decimal to adjust how far right the box shifts
                        }),
                        stayOpenForJunk = AddOption({
                            type = "toggle",
                            name = "Keep loot window open if it has junk",
                            desc = "If the loot window contains unlooted items to ignore, keep the window open.\n"
                                .. "If unchecked (see warning below), the loot window auto-closes even it if contains unlooted junk.",
                            width = 1.8,
                            disabled = function()
                                local situation = LootTracker.db.profile.lootModeWhenOther
                                return not (situation.lootMode == "managed" and situation.ignoreJunk)
                            end,
                        }),
                    },
                }),
                spacerLootNote = AddOption({
                    type = "description",
                    name = " ",
                    fontSize = "medium",
                }),
                indentLootModeNote = AddOption({
                    type = "description",
                    name = " ",
                    width = "relative",
                    relWidth = 0.05,
                }),
                lootModeNote = AddOption({
                    type = "description",
                    name = "WARNING:\n"
                        .. "|cFF999999In some cases (like fishing) when the window closes, the loot is GONE FOREVER.|r\n"
                        .. "|cFF999999In other cases, you might still be able to loot it from the body, chest, etc.|r",
                    width = "relative",
                    relWidth = 0.9,
                }),
                spacerLootDelay = AddOption({
                    type = "description",
                    name = " ",
                    fontSize = "large",
                }),
                lootDelay = AddOption({
                    type = "range",
                    name = "Managed Loot Delay (milliseconds)",
                    desc = "Delay before looting so the window is visible. Yes, you can set this to 0 for \"instant\" looting.",
                    min = 0,
                    max = 5000,
                    step = 50,
                    width = "full",
                }),
            }
        }),
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