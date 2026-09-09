local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

-- Fishing:CreateModuleOptions({
-- 	displayName = "Fishing",
-- 	dbKey = "fishing",
-- 	defaults = ns.Fishing.Defaults,
-- 	childGroups = "tree",
--     showEnableOption = false,
-- })

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

function Fishing:GetModuleConfig()
    return {
        moduleName = "Fishing",
        displayName = "Fishing",
        dbKey = "fishing",
        defaults = ns.moduleDefaults.Fishing,
        showEnableOption = false,
        childGroups = "tree",
    }
end

function Fishing:GetModuleOptions()
    local options = {
        modesTab = AddTab({
            type = "group",
            name = "Modes",
            args = {
                castingTriggers = AddOption({
                    type = "group",
                    name = "Casting triggers",
                    inline = true,
                    args = {
                        castByDoubleRightClick = AddOption({
                            type = "toggle",
                            name = "Double right click",
                            desc = "Double right click to begin fishing.",
                            width = "full",
                        }),
                        castBySingleRightClickWhenFishing = AddOption({
                            type = "toggle",
                            name = "Single right click (while fishing)",
                            desc = "Single right click to cast when already in fishing session.",
                            width = "full",
                            set = function(_, value)
                                Fishing.db.profile.castBySingleRightClickWhenFishing = value
                                if not value and Fishing.clickFrame and not InCombatLockdown() then
                                    ClearOverrideBindings(Fishing.clickFrame)
                                end
                            end,
                        }),
                        castByHotkey = AddOption({
                            type = "toggle",
                            name = "Hotkey",
                            desc = "Use a hotkey to begin fishing.",
                            width = "full",
                        }),
                        castHotkeyKeybind1 = AddOption({
                            type = "keybinding",
                            name = "",
                            desc = "Set the keybinding for the hotkey casting mode.",
                            width = 1.0,
                            get = function()
                                return Fishing:GetKeybindings()[1]
                            end,
                            set = function(_, value)
                                Fishing:SetKeybindings(value, nil)
                            end,
                        }),
                        castHotkeyKeybind2 = AddOption({
                            type = "keybinding",
                            name = "",
                            desc = "Set the keybinding for the hotkey casting mode.",
                            width = 1.0,
                            get = function()
                                return Fishing:GetKeybindings()[2]
                            end,
                            set = function(_, value)
                                Fishing:SetKeybindings(nil, value)
                            end,
                        }),
                    },
                }),
                reelingTriggers = AddOption({
                    type = "group",
                    name = "Reel/bobber triggers",
                    inline = true,
                    args = {
                        modeEasyStrikeNote = AddOption({
                            type = "description",
                            name = "|c80999999  Requirements for either EasyStrike:|r\n"
                                .. "|c80999999  1. Turn on \"Enable Interact Key\" (Game Options > Controls).|r\n"
                                .. "|c80999999  2. Set the \"Hotkey\" keybinding above.|r\n"
                                .. "|c80999999  3. Ensure another addon does not interfere while fishing.|r",
                            width = "full",
                        }),
                        strikeByRightClick = AddOption({
                            type = "toggle",
                            name = "EasyStrike (right click)",
                            desc = "When the bobber indicates a bite, right click anywhere or use the hotkey to hook, play, and land the fish.",
                            width = "full",
                        }),
                        strikeByRightClickNote = AddOption({
                            type = "description",
                            name = "      |c80999999Since this replaces the normal \"turn or action\" action|r\n"
                                .. "      |c80999999on the right mouse button, it may be a bit awkward if you|r\n"
                                .. "      |c80999999are used to using RMB to turn or start movement by|r\n"
                                .. "      |c80999999pressing RMB first.|r\n"
                                .. "      |c80999999However, you can still mouse-look using LMB and initiate|r\n"
                                .. "      |c80999999movement by holding down LMB first and then RMB.|r",
                        }),
                        strikeByHotkey = AddOption({
                            type = "toggle",
                            name = "EasyStrike (hotkey)",
                            desc = "Use a hotkey to hook, play, and land the fish when the bobber indicates a bite.",
                            width = "full",
                        }),
                    },
                }),
                spacer = AddOption({
                    type = "description",
                    name = " ",
                    fontSize = "small",
                }),
                lingerDuration = AddOption({
                    type = "range",
                    name = "Linger duration",
                    desc = "The number of seconds after a cast for the fishing session to expire, unless another cast is initiated.",
                    min = 0,
                    max = 60,
                    step = 1,
                    bigStep = 5,
                }),
            },
        }), -- Modes tab
        tackleTab = AddTab({
            type = "group",
            name = "Tackle",
            args = {
                raftSection = {
                    type = "group",
                    name = "  ",
                    desc = "Settings for auto-casting a raft when fishing.",
                    inline = true,
                    order = 1,
                    args = {
                        selectedRaftToy = {
                            type = "select",
                            name = "Raft",
                            desc = "Choose the raft to be used when fishing. Applied automatically when casting the fishing line.",
                            order = 1,
                            values = function()
                                return ns.Utils.BuildOwnedToyOptions(ns.Fishing.const.raftToyItemIDs, "No Raft")
                            end,
                            sorting = function()
                                return ns.Utils.BuildOwnedToySortingKeys(ns.Fishing.const.raftToyItemIDs, "No Raft")
                            end,
                            width = 1.5,
                        },
                        applyRaft = {
                            type = "execute",
                            name = "Apply",
                            desc = "Manually apply the selected raft now.",
                            order = 2,
                            func = "ApplyRaft",
                            width = 0.85,
                        },
                    },
                },
                bobberSection = {
                    type = "group",
                    name = "  ",
                    desc = "Settings for auto-casting a bobber when fishing.",
                    inline = true,
                    order = 2,
                    args = {
                        -- divider = {
                        --     type = "header",
                        --     name = "-----",
                        --     order = 0,
                        -- },
                        selectedBobberToy = {
                            type = "select",
                            name = "Bobber",
                            desc = "Choose the bobber to be used when fishing. Applied automatically when casting the fishing line.",
                            order = 1,
                            values = function()
                                return ns.Utils.BuildOwnedToyOptions(ns.Fishing.const.bobberToyItemIDs, "Standard Bobber")
                            end,
                            sorting = function()
                                return ns.Utils.BuildOwnedToySortingKeys(ns.Fishing.const.bobberToyItemIDs, "Standard Bobber")
                            end,
                            width = 1.5,
                        },
                        applyBobber = {
                            type = "execute",
                            name = "Apply",
                            desc = "Manually apply the selected bobber now.",
                            order = 2,
                            func = "ApplyBobber",
                            width = 0.85,
                        },
                        useOversizedBobber = {
                            type = "toggle",
                            name = "Use Oversized Bobber",
                            desc = "Also apply the oversized bobber to your selected bobber (adds another click to apply it)",
                            order = 3,
                            width = "full",
                        }
                    } -- Bobber section
                },
                openTackleWindow = {
                    type = "execute",
                    name = "Open Tackle Box",
                    desc = "Open a window to manage fishing tackle (poles, rafts, bobbers).",
                    order = 3,
                    func = function(info) Addon:OpenDialogWindow("DreamFishDialog") end,
                    width = "full",
                } -- Tackle manager button
            },
        }), -- Tackle tab
        focusTab = AddTab({
            type = "group",
            name = "Focus",
            args = {
                audioFocusEnabled = {
                    type = "toggle",
                    name = "Audio focus",
                    desc = "Reduces other sounds and focuses audio on fishing sounds, then restores when done fishing.",
                    order = 1,
                    width = "full",
                },
                frameFocusEnabled = {
                    type = "toggle",
                    name = "Auto fade frames",
                    desc = "Fade out visuals while fishing and fade them back in afterwards.",
                    order = 2,
                    width = "full",
                }

            }
        })
    }

    return options
end
