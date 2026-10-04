local addonName, ns = ...
local Addon = ns.Addon
local Fishing = ns.Fishing

local layoutCounter = 0
local function AutoOrder(nodeTable)
    layoutCounter = layoutCounter + 1
    nodeTable.order = layoutCounter
    return nodeTable
end

local function CreateCenteredSlider(parentGroup, key, displayName, defaultText, orderStart)
    parentGroup.args[key .. "spacer"] = {
        type = "description",
        name = " ",
        width = "full",
        order = orderStart,
    }
    -- 1. Left Spacing Gutter
    parentGroup.args[key .. "Left"] = {
        type = "description",
        name = " ",
        width = "relative",
        relWidth = 0.24,
        order = orderStart + 1,
    }

    -- 2. Centered Range Slider
    parentGroup.args[key] = {
        type = "range",
        name = string.format("%s |c66999999(Default: %s)|r", displayName, defaultText),
        desc = nil,
        min = 0,
        max = 100,
        step = 1,
        width = "relative",
        relWidth = 0.50,
        order = orderStart + 2,
        get = function()
            return Fishing.db.profile[key] or 50
        end,
        set = function(_, value)
            Fishing.db.profile[key] = value
        end,
    }

    -- 3. Right Spacing Gutter
    parentGroup.args[key .. "Right"] = {
        type = "description",
        name = " ",
        width = "relative",
        relWidth = 0.25,
        order = orderStart + 3,
    }
end

-- Registered once so Escape (CloseSpecialWindows) also turns off the frame stack tool.
local frameStackEscapeHooked = false
local function EnsureFrameStackClosesOnEscape()
    if frameStackEscapeHooked then return end
    frameStackEscapeHooked = true
    hooksecurefunc("CloseSpecialWindows", function()
        if FrameStackTooltip and FrameStackTooltip:IsShown() and SlashCmdList["FRAMESTACK"] then
            SlashCmdList["FRAMESTACK"]("")
        end
    end)
end

-- These are the exact CVars /fstack itself reads as defaults when toggled.
local function ApplyFrameStackFilters()
    SetCVar("fstack_showhidden", Fishing.db.profile.frameStackIncludeHidden)
    SetCVar("fstack_showregions", Fishing.db.profile.frameStackIncludeRegionsAndTextures)
    SetCVar("fstack_showanchors", Fishing.db.profile.frameStackIncludeAnchors)
end

-- FrameStackTooltip_Toggle only reads the CVars above when going hidden->shown, so a checkbox
-- change while the tool is already open needs an off/on cycle to actually take effect.
local function RefreshFrameStackIfShown()
    if FrameStackTooltip and FrameStackTooltip:IsShown() and SlashCmdList["FRAMESTACK"] then
        SlashCmdList["FRAMESTACK"]("")
        SlashCmdList["FRAMESTACK"]("")
    end
end

-- Holds the name grabbed from the fstack tool until the user commits it via customFrameInput.
local pendingCustomFrameName = ""
local function GrabSelectedFrameStackName()
    -- FrameStackTooltip_OnUpdate sets this global itself whenever ALT/RALT changes its highlight.
    local highlighted = _G.fsobj
    pendingCustomFrameName = (highlighted and highlighted.GetName and highlighted:GetName()) or ""
    local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange(addonName .. "_Fishing")
    end
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

local SESSION_TEXT = "A session is one or more casts. It begins with the first precast "
    .. "(initated by double click or hotkey) and ends when fishing is interrupted or "
    .. "expires due to idle timeout."


local function BuildModesTab(order)
    layoutCounter = 0
    return {
        type = "group",
        name = "Modes",
        order = order,
        args = {
            triggers = AutoOrder({
                type = "group",
                name = "Triggers",
                args = {
                    castingTriggers = AutoOrder({
                        type = "group",
                        name = "Casting triggers",
                        inline = true,
                        args = {
                            castByDoubleRightClick = AutoOrder({
                                type = "toggle",
                                name = "Double right click",
                                desc = "Double right click to begin a session or to cast.\n" .. SESSION_TEXT,
                                width = "full",
                            }),
                            castBySingleRightClickWhenFishing = AutoOrder({
                                type = "toggle",
                                name = "Single right click (while in a \"session\")",
                                desc = "Single right click to cast when already in fishing session.\n" .. SESSION_TEXT,
                                width = "full",
                                set = function(_, value)
                                    Fishing.db.profile.castBySingleRightClickWhenFishing = value
                                    if not value and Fishing.clickFrame and not InCombatLockdown() then
                                        ClearOverrideBindings(Fishing.clickFrame)
                                    end
                                end,
                            }),
                            castByHotkey = AutoOrder({
                                type = "toggle",
                                name = "Hotkey",
                                desc = "Use a hotkey to begin a session or to cast.\n" .. SESSION_TEXT,
                                width = "full",
                            }),
                            castHotkeyKeybind1 = AutoOrder({
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
                            castHotkeyKeybind2 = AutoOrder({
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
                    reelingTriggers = AutoOrder({
                        type = "group",
                        name = "Reel/bobber triggers",
                        inline = true,
                        args = {
                            modeEasyStrikeNote = AutoOrder({
                                type = "description",
                                name = "|c80999999  Requirements for any EasyStrike:|r\n"
                                    .. "|c80999999  1. Turn on \"Enable Interact Key\" (Game Options > Controls).|r\n"
                                    .. "|c80999999  2. Ensure another addon does not interfere while fishing.|r\n"
                                    .. "|c80999999  * (For hotkey mode) Set the \"Hotkey\" keybinding above.|r\n",
                                width = "full",
                            }),
                            strikeByDoubleRightClick = AutoOrder({
                                type = "toggle",
                                name = "EasyStrike (double right click)",
                                desc = "When the bobber indicates a bite, double right click in an empty area of the screen to hook, play, and land the fish.",
                                width = "full",
                            }),
                            strikeByRightClick = AutoOrder({
                                type = "toggle",
                                name = "EasyStrike (right click)",
                                desc = "When the bobber indicates a bite, right click  in an empty area of the screen to hook, play, and land the fish.",
                                width = "full",
                            }),
                            strikeByRightClickNote = AutoOrder({
                                type = "description",
                                name = "      |c80999999Since this replaces the normal \"turn or action\" action|r\n"
                                    .. "      |c80999999on the right mouse button, it may be a bit awkward if you|r\n"
                                    .. "      |c80999999are used to using RMB to turn or start movement by|r\n"
                                    .. "      |c80999999pressing RMB first.|r\n"
                                    .. "      |c80999999However, you can still mouse-look using LMB and initiate|r\n"
                                    .. "      |c80999999movement by holding down LMB first and then RMB.|r",
                            }),
                            strikeByHotkey = AutoOrder({
                                type = "toggle",
                                name = "EasyStrike (hotkey)",
                                desc = "Use a hotkey to hook, play, and land the fish when the bobber indicates a bite.",
                                width = "full",
                            }),
                        },
                    }),
                },
            }),
            sessionExits = AutoOrder({
                type = "group",
                name = "Session Exits",
                order = 2,
                args = {
                    movementCancelsFishing = AutoOrder({
                        type = "toggle",
                        name = "Exit session on movement",
                        desc = "Enable exiting the fishing session when movement is detected.",
                        width = "full",
                        get = function()
                            return Fishing.db.profile.movementCancelsFishing or false
                        end,
                        set = function(_, value)
                            Fishing.db.profile.movementCancelsFishing = value
                        end,
                    }),
                    movementAmountToCancelFishing = AutoOrder({
                        type = "range",
                        name = "Distance",
                        desc = "The movement distance required to cancel the fishing session.",
                        min = 0,
                        max = 100,
                        step = 1,
                        bigStep = 5,
                        disabled = function()
                            return Fishing.db.profile.movementCancelsFishing == false
                        end,
                        get = function()
                            return Fishing.db.profile.movementAmountToCancelFishing or 0
                        end,
                        set = function(_, value)
                            Fishing.db.profile.movementAmountToCancelFishing = value
                        end,
                    }),
                    spacer1 = AutoOrder({
                        type = "description",
                        name = " ",
                        fontSize = "small",
                    }),
                    lingerExpirationEnabled = AutoOrder({
                        type = "toggle",
                        name = "Exit session if idle",
                        desc = "Enable the fishing session to expire after a period of idle time.",
                        width = "full",
                        get = function()
                            return Fishing.db.profile.lingerExpirationEnabled or false
                        end,
                        set = function(_, value)
                            Fishing.db.profile.lingerExpirationEnabled = value
                            if not value then
                                if type(Fishing.CancelLingerTimer) == "function" then
                                    Fishing:CancelLingerTimer()
                                end
                            elseif Fishing.IsFishingState and ns.Fishing and ns.Fishing.states then
                                if Fishing:IsFishingState(ns.Fishing.states.LINGERING) and type(Fishing.StartLinger) == "function" then
                                    Fishing:StartLinger()
                                end
                            end
                        end,
                    }),
                    lingerDuration = AutoOrder({
                        type = "range",
                        name = "Idle time",
                        desc = "The number of seconds of idle time for the fishing session to expire.",
                        min = 0,
                        max = 60,
                        step = 1,
                        bigStep = 5,
                        disabled = function()
                            return Fishing.db.profile.lingerExpirationEnabled == false
                        end,
                        get = function()
                            return Fishing.db.profile.lingerDuration or 10
                        end,
                        set = function(_, value)
                            Fishing.db.profile.lingerDuration = value
                            if Fishing.db.profile.lingerExpirationEnabled and Fishing.IsFishingState and ns.Fishing and ns.Fishing.states then
                                if Fishing:IsFishingState(ns.Fishing.states.LINGERING) and type(Fishing.StartLinger) == "function" then
                                    Fishing:StartLinger()
                                end
                            end
                        end,
                    }),
                },
            }),
        },
    }
end

local function BuildTackleTab(order)
    layoutCounter = 0
    return {
        type = "group",
        name = "Tackle",
        order = order,
        args = {
            openTackleWindow = {
                type = "execute",
                name = "Open Tackle Box",
                desc = "Open a window to manage fishing tackle (poles, rafts, bobbers).",
                func = function(info) Addon:OpenDialogWindow("DreamFishDialog") end,
                width = "full",
            } -- Tackle manager button
        },
    }
end

local function BuildAudioFocusTab(order)
    local tab = {
        type = "group",
        name = "Audio Focus",
        order = order,
        args = {
            audioFocusEnabled = {
                type = "toggle",
                name = "Audio focus",
                desc = "Reduces other sounds and focuses audio on fishing sounds, then restores when done fishing.",
                width = "full",
                order = 1,
            },
            spacer = {
                type = "description",
                name = " ",
                fontSize = "medium",
                order = 2,
            },
            audioDuckingLevels = {
                type = "group",
                name = "Volume",
                inline = true,
                order = 3,
                args = {
                    description = {
                        type = "description",
                        name = "\n"
                            .. "|c66999999When a fishing session starts, the volume of each channel is checked and reduced as follows.|r\n"
                            .. "|c66999999   A value of 0 means completely muted.\n|r"
                            .. "|c66999999   35% means the volume is reduced to 35% of the original volume.\n|r"
                            .. "|c66999999   100% means no reduction from the original volume.|r",
                        order = 1,
                    },
                    -- Sliders (below) are inserted here
                },
            },
        },
    }
    local group = tab.args.audioDuckingLevels
    CreateCenteredSlider(group, "ambienceDuckingLevel", "Ambience", "35%", 10)
    CreateCenteredSlider(group, "musicDuckingLevel",    "Music",    "20%", 20)
    CreateCenteredSlider(group, "dialogDuckingLevel",   "Dialog",   "50%", 30)

    return tab
end

local function AddFrameFadeControlButtons(args)
    args.forceHide = {
        type = "execute",
        name = "Start Faded Mode",
        desc = "Hide frames according to frame selections.",
        width = "relative",
        relWidth = 0.49,
        order = 1,
        func = function()
            Fishing:ForceHidden()
        end
    }
    args.forceShow = {
        type = "execute",
        name = "Show Frames",
        desc = "Show all frames.",
        width = "relative",
        relWidth = 0.49,
        order = 2,
        func = function()
            Fishing:ForceVisible()
        end
    }
    args.tickDescription = {
        type = "description",
        name = "\n|c66999999A ticked box indicates that the frame will be faded/hidden when the fade mode is active.|r\n ",
        width = "relative",
        relWidth = 0.95,
        order = 3,
    }
end

local function BuildFrameToggleArgs(frameEntries)
    local args = {}
    for _, frameEntry in ipairs(frameEntries) do
        args[frameEntry.name] = AutoOrder({
            type = "toggle",
            name = frameEntry.name,
            width = "full",
            get = function() return frameEntry.enabled end,
            set = function(_, value)
                frameEntry.enabled = value
                if frameEntry.enabledStore then
                    frameEntry.enabledStore[frameEntry.name] = value
                end
                Fishing:SetFrameFadeState(frameEntry.name, value)
            end,
        })
    end
    return args
end

local function IsFadeSectionVisible(sectionEntry)
    if not sectionEntry.validator then
        return true
    end
    local validator = Fishing[sectionEntry.validator]
    return type(validator) ~= "function" or validator(Fishing)
end

local function GetFadeSectionFrames(sectionEntry)
    if sectionEntry.generator then
        local generator = Fishing[sectionEntry.generator]
        if type(generator) ~= "function" then
            return {}
        end
        sectionEntry.generatedEnabled = sectionEntry.generatedEnabled or {}
        local frameEntries = {}
        for _, frameName in ipairs(generator(Fishing) or {}) do
            local name = type(frameName) == "table" and frameName.name or frameName
            if name and name ~= "" then
                frameEntries[#frameEntries + 1] = {
                    name = name,
                    enabled = sectionEntry.generatedEnabled[name] ~= false,
                    enabledStore = sectionEntry.generatedEnabled,
                }
            end
        end
        return frameEntries
    end
    return sectionEntry.frames or {}
end

local FindFadeCategory

local function BuildFrameFadeSections(parentArgs)
    parentArgs.tackleBoxSection = AutoOrder({
        type = "group",
        name = "Tackle Box",
        inline = false,
        args = {
            dreamfishDialogWhenFishing = AutoOrder({
                type = "group",
                name = " ",
                inline = true,
                args = {
                    showWhenFishing = {
                        type = "toggle",
                        name = "Show tackle box when fishing",
                        width = "full",
                        order = 1,
                        get = function() return FindFadeCategory("Tackle Box").dreamfishDialogWhenFishing end,
                        set = function(_, value)
                            FindFadeCategory("Tackle Box").dreamfishDialogWhenFishing = value
                            if Fishing.RefreshDreamFishDialogFade then
                                Fishing:RefreshDreamFishDialogFade()
                            end
                        end,
                    },
                    alphaWhenFishingLeft = {
                        type = "description", name = " ", desc = "", width = "relative", relWidth = 0.24,
                        order = 2,
                    },
                    alphaWhenFishing = {
                        type = "range",
                        name = "Alpha",
                        desc = "",
                        width = "relative",
                        relWidth = 0.50,
                        min = 0,
                        max = 1,
                        step = 0.01,
                        order = 3,
                        get = function() return FindFadeCategory("Tackle Box").dreamFishDialogAlphaWhenFishing end,
                        set = function(_, value)
                            FindFadeCategory("Tackle Box").dreamFishDialogAlphaWhenFishing = value
                            if Fishing.RefreshDreamFishDialogFade then
                                Fishing:RefreshDreamFishDialogFade()
                            end
                        end,
                    },
                    alphaWhenFishingRight = {
                        type = "description", name = " ", desc = "", width = "relative", relWidth = 0.24,
                        order = 4,
                    },
                    opacityWithMouseover = {
                        type = "toggle",
                        name = "Apply full opacity when mouse is over",
                        width = "full",
                        order = 5,
                        get = function()
                            local cat = FindFadeCategory("Tackle Box")
                            return cat and cat.opacityWithMouseover or false
                        end,
                        set = function(_, value)
                            local cat = FindFadeCategory("Tackle Box")
                            if cat then
                                cat.opacityWithMouseover = value
                                if Fishing.RefreshDreamFishDialogFade then
                                    Fishing:RefreshDreamFishDialogFade()
                                end
                            end
                        end,
                    }
                },
            }),
            spacer1 = AutoOrder({
                type = "description", name = " ", desc = "", width = "full", fontSize = "large",
            }),
            spacer2 = AutoOrder({
                type = "description", name = " ", desc = "", width = "full", fontSize = "large",
            }),
            dreamfishDialogWhenOther = AutoOrder({
                type = "group",
                name = " ",
                inline = true,
                args = {
                    alphaLeft = {
                        type = "description", name = " ", desc = "", width = "relative", relWidth = 0.24,
                        order = 1,
                    },
                    alphaWhenOther = {
                        type = "range",
                        name = "Alpha |c66999999(not fishing)|r",
                        desc = "",
                        order = 2,
                        width = "relative",
                        relWidth = 0.50,
                        min = 0,
                        max = 1,
                        step = 0.01,
                        get = function() return FindFadeCategory("Tackle Box").dreamFishDialogAlphaWhenOther end,
                        set = function(_, value)
                            FindFadeCategory("Tackle Box").dreamFishDialogAlphaWhenOther = value
                            if Fishing.RefreshDreamFishDialogFade then
                                Fishing:RefreshDreamFishDialogFade()
                            end
                        end,
                    },
                    alphaRight = {
                        type = "description", name = " ", desc = "", width = "relative", relWidth = 0.24,
                        order = 3,
                    },
                },
            }),
        }
    })

    for _, categoryEntry in ipairs(Fishing.db.profile.fadeFrames) do
        if categoryEntry.name ~= "Custom" and categoryEntry.name ~= "Tackle Box" then

            local categoryArgs
            parentArgs[categoryEntry.name] = AutoOrder({
                type = "group",
                name = categoryEntry.name,
                inline = false,
                args = {
                    frameCheckboxArea = {
                        type = "group",
                        name = "",
                        inline = true,
                        order = 4,
                    }
                },
            })
            AddFrameFadeControlButtons(parentArgs[categoryEntry.name].args)

            if categoryEntry.sections then
                categoryArgs = {}
                for _, sectionEntry in ipairs(categoryEntry.sections) do
                    if IsFadeSectionVisible(sectionEntry) then
                        categoryArgs[sectionEntry.name] = AutoOrder({
                            type = "group",
                            name = sectionEntry.name,
                            inline = true,
                            args = BuildFrameToggleArgs(GetFadeSectionFrames(sectionEntry)),
                        })
                    end
                end
            else
                categoryArgs = BuildFrameToggleArgs(GetFadeSectionFrames(categoryEntry))
            end
            parentArgs[categoryEntry.name].args.frameCheckboxArea.args = categoryArgs
        end
    end
end

FindFadeCategory = function(categoryName)
    for _, categoryEntry in ipairs(Fishing.db.profile.fadeFrames) do
        if categoryEntry.name == categoryName then
            return categoryEntry
        end
    end
end

local function ToggleFrameStackMode()
    -- 1. Force load the background debug files using the correct current API
    if not C_AddOns.IsAddOnLoaded("Blizzard_DebugTools") then
        C_AddOns.LoadAddOn("Blizzard_DebugTools")
    end
    EnsureFrameStackClosesOnEscape()
    ApplyFrameStackFilters()

    -- 2. Launch the inspector window safely via the official system command route
    if SlashCmdList["FRAMESTACK"] then
        SlashCmdList["FRAMESTACK"]("")
    else
        print("|cFFFF0000[DreamFish]|r Error: FrameStack command registry is missing.")
    end
end

local function BuildCustomFrameFadeSection(parentArgs)
    local customCategory = FindFadeCategory("Custom")

    local childOrder = 1
    local function AddChild(item)
        childOrder = childOrder + 1
        item.order = childOrder
        return item
    end

    local function AddCustomFrame(name)
        pendingCustomFrameName = "" -- Always clear the line input text box after saving
        if name and name ~= "" then
            for _, frameEntry in ipairs(customCategory.frames) do
                if frameEntry.name == name then
                    return -- already tracked
                end
            end
            table.insert(customCategory.frames, { name = name, enabled = true })
            Fishing:SetFrameFadeState(name, true)
        end
    end

    local customFrameSection = AutoOrder({
        type = "group",
        name = "Custom",
        inline = false,
        args = {
            notes = AddChild({
                type = "description",
                name = "|c99CCCCCCSee frame controls and tools on main Frame Fade page.|r\n ",
                width = "full",
            }),
            frameStackToggle = AddChild({
                type = "execute",
                name = "1. Click to toggle frame stack tool",
                desc = "Turn on the frame stack tool and hover over the frame/area you want to identify.",
                width = "full",
                func = function()
                    ToggleFrameStackMode()
                end
            }),
            frameStackInstruction = AddChild({
                type = "description",
                name = "2. Hover over the frame you want to identify using the Frame Stack Tool and press ALT/right ALT to select it in the tool.",
                width = "full",
            }),
            grabSelectedFrameStack = AddChild({
                type = "execute",
                name = "3. Click to copy selected frame name to box below",
                desc = "Grab the frame currently highlighted in the frame stack tool (Alt/Right Alt to cycle its highlight) and load its name below.",
                width = "full",
                func = function()
                    GrabSelectedFrameStackName()
                    ToggleFrameStackMode()
                end,
            }),
            customFrameInput = AddChild({
                type = "input",
                name = "Add Custom Frame Name",
                desc = "You can use the Frame Stack Tool to find a frame's name (Alt/Right Alt to cycle its highlight) and click the button above to grab the name into this box.",
                width = "relative",
                relWidth = 0.75,
                get = function() return pendingCustomFrameName end,
                set = function(_, value) AddCustomFrame(value) end,
            }),
            addCustomFrame = AddChild({
                type = "execute",
                name = "4. Add",
                desc = "Add the frame name typed above to the custom fade list.",
                width = "relative",
                relWidth = 0.24,
                func = function() AddCustomFrame(pendingCustomFrameName) end,
            }),
            -- A simple button loop list to allow deleting custom frames easily
            removeCustomDesc = AddChild({
                type = "description",
                name = " ",
                width = "full",
                fontSize = "medium"
            }),
        },
    })

    -- Explicit order keeps each toggle paired with its Remove button on the same row;
    -- without it, AceConfig falls back to alphabetical-by-name and splits the pairs apart.
    for _, frameEntry in ipairs(customCategory.frames) do
        customFrameSection.args[frameEntry.name] = AddChild({
            type = "toggle",
            name = frameEntry.name,
            width = "relative",
            relWidth = 0.75,
            get = function() return frameEntry.enabled end,
            set = function(_, value)
                frameEntry.enabled = value
                Fishing:SetFrameFadeState(frameEntry.name, value)
            end,
        })
        customFrameSection.args[frameEntry.name .. "_Remove"] = AddChild({
            type = "execute",
            name = "X",
            desc = "Remove " .. frameEntry.name .. " from the custom fade list.",
            width = "relative",
            relWidth = 0.24,
            func = function()
                Fishing:SetFrameFadeState(frameEntry.name, false)
                for idx, entry in ipairs(customCategory.frames) do
                    if entry.name == frameEntry.name then
                        table.remove(customCategory.frames, idx)
                        break
                    end
                end
            end
        })
    end

    parentArgs.customFrameSection = customFrameSection
end

local function BuildFrameFadeTab(order)
    layoutCounter = 0
    local frameFadeTab = {
        type = "group",
        name = "Frame Fade",
        order = order,
        args = {
            frameFocusEnabled = {
                type = "toggle",
                name = "Enable frame fade",
                desc = "Automatically fade out configured frames while fishing to reduce screen clutter for a more immersive experience.\n"
                    .. "Expand the categories below the main Frame Fade section to configure individual frame fade settings.",
                width = "full",
                order = 0,
                get = function() return Fishing.db.profile.frameFocusEnabled end,
                set = function(_, value)
                    Fishing.db.profile.frameFocusEnabled = value
                    Fishing:RefreshFade()
                end,
            },
            frameToolsSpacer = AutoOrder({
                type = "description", name = " ", fontSize = "large",
            }),
            frameControls = AutoOrder({
                type = "group",
                name = "Frame Controls",
                inline = true,
                args = {
                    forceHide = AutoOrder({
                        type = "execute",
                        name = "Start Faded Mode",
                        desc = "Hide frames according to frame selections.",
                        width = "relative",
                        relWidth = 0.49,
                        func = function()
                            Fishing:ForceHidden()
                        end
                    }),
                    forceShow = AutoOrder({
                        type = "execute",
                        name = "Show Frames",
                        desc = "Show all frames.",
                        width = "relative",
                        relWidth = 0.49,
                        func = function()
                            Fishing:ForceVisible()
                        end
                    }),
                    windowCommands = AutoOrder({
                        type = "description",
                        name = "\n"
                            .. "|cFF999999Slash Commands|r\n"
                            .. "   /df show |cFF999999(to show frames)|r\n"
                            .. "   /df fade |cFF999999(to hide frames)|r",
                    })
                }
            }),
            frameSpacer = AutoOrder({
                type = "description",
                name = " ",
            }),
            frameStackTool = AutoOrder({
                type = "group",
                name = "Frame Stack Tool Options",
                inline = true,
                args = {
                    frameStackToggle = AutoOrder({
                        type = "execute",
                        name = "Toggle Frame Stack Tool",
                        desc = "Turn on the frame stack tool and hover over the frame/area you want to identify.\n"
                            .. "Especially useful for adding custom frames (see Custom section).",
                        width = "full",
                        func = function()
                            ToggleFrameStackMode()
                        end
                    }),
                    frameStackIncludeHidden = AutoOrder({
                        type = "toggle",
                        name = "Include hidden frames",
                        desc = "Include hidden frames in the frame stack tool.",
                        width = "full",
                        set = function(_, value)
                            Fishing.db.profile.frameStackIncludeHidden = value
                            ApplyFrameStackFilters()
                            RefreshFrameStackIfShown()
                        end,
                    }),
                    frameStackIncludeRegionsAndTextures = AutoOrder({
                        type = "toggle",
                        name = "Include regions and textures",
                        desc = "Include regions and textures in the frame stack tool.",
                        width = "full",
                        set = function(_, value)
                            Fishing.db.profile.frameStackIncludeRegionsAndTextures = value
                            ApplyFrameStackFilters()
                            RefreshFrameStackIfShown()
                        end,
                    }),
                    frameStackIncludeAnchors = AutoOrder({
                        type = "toggle",
                        name = "Include anchors",
                        desc = "Include anchor points in the frame stack tool.",
                        width = "full",
                        set = function(_, value)
                            Fishing.db.profile.frameStackIncludeAnchors = value
                            ApplyFrameStackFilters()
                            RefreshFrameStackIfShown()
                        end,
                    }),
                },
            }),
        }
    }
    BuildFrameFadeSections(frameFadeTab.args)
    BuildCustomFrameFadeSection(frameFadeTab.args)
    return frameFadeTab
end

function Fishing:GetModuleOptions()
    local options = {
        modesTab = BuildModesTab(1),
        tackleTab = BuildTackleTab(2),
        focusTab = BuildAudioFocusTab(3),
        frameFadeTab = BuildFrameFadeTab(4),
    }

    return options
end
