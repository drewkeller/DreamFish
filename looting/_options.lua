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
        displayName = "Looting",
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

local function HasBagAlertEnabled()
    return LootTracker.db.profile.normalBagAlertEnabled or LootTracker.db.profile.reagentBagAlertEnabled
end

function LootTracker:GetModuleOptions()

    local function GetProfileValue(info)
        local value = LootTracker.db.profile[info[#info]]
        if info.type == "input" then
            return tostring(value or "")
        end
        return value -- toggle
    end

    local function SetProfileValue(info, value)
        if info.type == "input" then
            LootTracker.db.profile[info[#info]] = tonumber(value) or value
        else
            LootTracker.db.profile[info[#info]] = value -- toggle
        end
    end

    local options = {
        alertsTab = AddTab({
            type = "group",
            name = "Alerts",
            get = GetProfileValue,
            set = SetProfileValue,
            args = {
                fishingAlertGroup = AddOption({
                    type = "group",
                    name = "Fishing Alerts",
                    inline = true,
                    args = {
                        patientTreasureAlert = AddOption({
                            type = "toggle",
                            name = "Patient Treasure alert",
                            desc = "Enable or disable notifications for the Patient Treasure when fishing.",
                            width = "full",
                        }),
                    },
                }),
                bagAlertsSpacer = AddOption({
                    type = "description",
                    name = " ",
                    width = "full",
                    fontSize = "large",
                }),
                bagAlerts = AddOption({
                    type = "group",
                    name = "Bag Alerts",
                    inline = true,
                    args = {
                        normalBagAlertEnabled = AddOption({
                            type = "toggle",
                            name = "Bag monitor",
                            desc = "Monitors your bag space and alerts you when it is low (non-reagent slots).",
                            width = "normal",
                        }),
                        normalBagAlertThreshold = AddOption({
                            type = "input",
                            dialogControl = "EditBox",
                            name = "Threshold",
                            desc = "Minimum number of free bag slots before an alert is triggered (non-reagent slots).",
                            width = "half",
                            disabled = function() return not LootTracker.db.profile.normalBagAlertEnabled end
                        }),
                        reagentBagMonitorSpacer = AddOption({
                            type = "description",
                            name = " ",
                            width = "full",
                            fontSize = "small",
                        }),
                        reagentBagAlertEnabled = AddOption({
                            type = "toggle",
                            name = "Reagent monitor",
                            desc = "Monitors your reagent bag space and alerts you when it is low.",
                            width = "normal",
                        }),
                        reagentBagAlertThreshold = AddOption({
                            type = "input",
                            name = "Threshold",
                            desc = "Minimum number of free slots (reagent bags) before an alert is triggered.",
                            width = "half",
                            disabled = function() return not LootTracker.db.profile.reagentBagAlertEnabled end
                        }),
                        endSpacer = AddOption({
                            type = "description",
                            name = " ",
                            width = "full",
                            fontSize = "medium",
                        }),
                    },
                }),
                bagAlertOptions = AddOption({
                    type = "group",
                    name = "Bag Alert Options",
                    width = "full",
                    inline = true,
                    disabled = function() return not HasBagAlertEnabled() end,
                    args = {
                        bagAlertOnlyWhenFishing = AddOption({
                            type = "toggle",
                            name = "Only when fishing",
                            desc = "Only triggers bag alerts when you are fishing.",
                            width = "full",
                        }),
                        bagAlertPlaySound = AddOption({
                            type = "toggle",
                            name = "Play sound",
                            desc = "Plays a sound when a bag alert is triggered.",
                            width = "full",
                        }),
                        bagAlertShowFullScreen = AddOption({
                            type = "toggle",
                            name = "Show full-screen",
                            desc = "Displays a full-screen alert when a bag alert is triggered.",
                            width = "full",
                        }),
                        bagAlertThrottle = AddOption({
                            type = "input",
                            name = "Throttle",
                            desc = "Minimum number of seconds between bag alerts.",
                            width = "half",
                        }),
                    },
                }),
            },
        }),
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
                lootDelayRight = AddOption({
                    type = "description", name = " ", width = "relative", relWidth = 0.24,
                }),
                lootDelay = AddOption({
                    type = "range",
                    name = "Managed Loot Delay",
                    desc = "Delay in milliseconds before looting so the window is visible. Yes, you can set this to 0 for \"instant\" looting.",
                    min = 0,
                    max = 5000,
                    step = 50,
                    width = "relative",
                    relWidth = 0.50,
                }),
                lootDelayLeft = AddOption({
                    type = "description", name = " ", width = "relative", relWidth = 0.24,
                }),
            }
        }),
        windowTab = AddTab({
            type = "group",
            name = "Window",
            args = {
                showTrackerAs = AddOption({
                    type = "select",
                    name = "Show Tracker As",
                    desc = "Choose how the loot tracker is displayed.",
                    style = "radio",
                    width = "full",
                    values = {
                        ["window"] = "Standalone window",
                        ["tab"] = "Tab on dialog",
                    },
                    get = function() return LootTracker.db.profile.showTrackerAs end,
                    set = function(_, value)
                        LootTracker.db.profile.showTrackerAs = value
                        LootTracker:ApplyTrackerDisplayMode()
                    end,
                }),
                showWindowOnStartup = AddOption({
                    type = "toggle",
                    name = "Show loot tracker on login",
                    desc = "Automatically displays the tracker frame canvas when you log into the character.",
                    width = "full",
                }),
                spacerTrackWhen = AddOption({
                    type = "description", name = " ", width = "full",
                }),
                trackFishingLoot = AddOption({
                    type = "toggle",
                    name = "Track Fishing Loot",
                    desc = "Enable or disable tracking of loot when fishing.",
                    width = "full",
                }),
                trackNonFishingLoot = AddOption({
                    type = "toggle",
                    name = "Track Non-Fishing Loot",
                    desc = "Enable or disable tracking of loot when not fishing.",
                    width = "full",
                }),
                spacerLimitLootDataRows = AddOption({
                    type = "description", name = " ", width = "full",
                }),
                limitLootDataRows = AddOption({
                    get = function() return LootTracker.db.profile.limitLootDataRows end,
                    set = function(_, value)
                        LootTracker.db.profile.limitLootDataRows = value
                    end,
                    type = "range",
                    name = "Loot Data Limit",
                    desc = "The amount of loot tracking data to keep (number of rows). Once this limit is reached, new items are ignored.",
                    width = "full",
                    min = 1,
                    max = 500,
                    step = 1,
                }),
                spacerQuality = AddOption({
                    type = "description", name = " ", width = "full",
                }),
                minQualityFilter = AddOption({
                    get = function() return LootTracker.db.profile.minQualityFilter end,
                    set = function(_, value)
                        LootTracker.db.profile.minQualityFilter = value
                    end,
                    type = "select",
                    name = "Minimum quality filter",
                    desc = "Filters your text layout view logs based on item rarity rankings.",
                    width = "full",
                    values = {
                        [0] = "|cFF9d9d9dPoor (Gray)|r",
                        [1] = "|cFFFFFFFFCommon (White)|r",
                        [2] = "|cFF1eff00Uncommon (Green)|r",
                        [3] = "|cFF0070ddRare (Blue)|r",
                        [4] = "|cFFa335eeEpic (Purple)|r",
                    },
                }),
                spacerButton = AddOption({
                    type = "description", name = " ", width = "full",
                }),
                toggleUiButton = AddOption({
                    type = "execute",
                    name = "Show Tracker",
                    width = "full",
                    func = function()
                        ns.Addon:GetModule("LootTracker"):ShowTracker()
                    end,
                }),
            }
        }), -- Window tab
    }
    return options
end