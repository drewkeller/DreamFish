local addonName, ns = ...
local Addon = ns.Addon

-- Array-of-entries (not hash maps) so declaration order here is authoritative for the options UI.
-- A category either has `sections` (nested inline groups) or `frames` directly (flat category).
ns.moduleDefaults["Fishing"].profile.fadeFrames = {
    {
        name = "Tackle Box",
        dreamfishDialogWhenFishing = true,
        dreamFishDialogAlphaWhenFishing = 1,
        dreamFishDialogAlphaWhenOther = 1,
    },
    { name = "Beware",
        sections = {
            { name = "ElvUI",
                validator = "IsElvUIActive",
                frames = {
                    { name = "ElvUF_Player_Castbar", enabled = false }, -- We want to make sure this is shown
                    { name = "ElvUI_LootFrame", enabled = false }, --keep this for fishing
                },
            },
        },
    },
    { name = "Action Bars",
        sections = {
            { name = "ElvUI",
                validator = "IsElvUIActive",
                frames = {
                    { name = "ElvUI_Bar1", enabled = true },
                    { name = "ElvUI_Bar2", enabled = true },
                    { name = "ElvUI_Bar3", enabled = true },
                    { name = "ElvUI_Bar4", enabled = true },
                    { name = "ElvUI_Bar5", enabled = true },
                    { name = "ElvUI_Bar6", enabled = true },
                    { name = "ElvUI_Bar7", enabled = true },
                    { name = "ElvUI_Bar8", enabled = true },
                    { name = "ElvUI_Bar9", enabled = true },
                    { name = "ElvUI_Bar10", enabled = true },
                    { name = "ElvUI_Bar13", enabled = true },
                    { name = "ElvUI_Bar14", enabled = true },
                    { name = "ElvUI_Bar15", enabled = true },
                    { name = "ElvUI_StanceBar", enabled = true },
                    { name = "ElvUI_PetBar", enabled = true },
                },
            },
        },
    },
    { name = "Chat & Text",
        sections = {
            { name = "Blizzard",
                frames = {
                    { name = "ChatFrame1", enabled = false },
                    { name = "ChatFrame2", enabled = true },
                    { name = "ChatFrame3", enabled = true },
                    { name = "ChatFrame4", enabled = true },
                    { name = "LeftChatPanel", enabled = false },
                    { name = "RightChatPanel", enabled = false },
                    { name = "LeftChatToggleButton", enabled = true },
                    { name = "RightChatToggleButton", enabled = true },
                },
            },
            { name = "ElvUI",
                validator = "IsElvUIActive",
                frames = {
                    { name = "ElvUI_BottomPanel", enabled = true },
                    { name = "ElvUI_TopPanel", enabled = true },
                    { name = "ElvUI_DataTextPanel_LeftChatDataPanelSlot1", enabled = true }, -- Data text panels
                    { name = "ElvUI_DataTextPanel_LeftChatDataPanelSlot2", enabled = true },
                    { name = "ElvUI_DataTextPanel_LeftChatDataPanelSlot3", enabled = true },
                    { name = "ElvUI_DataTextPanel_RightChatDataPanelSlot1", enabled = true },
                    { name = "ElvUI_DataTextPanel_RightChatDataPanelSlot2", enabled = true },
                    { name = "ElvUI_DataTextPanel_RightChatDataPanelSlot3", enabled = true },
                },
            },
        },
    },
    { name = "Minimap",
        sections = {
            { name = "Blizzard",
                frames = {
                    { name = "Minimap", enabled = true },
                    { name = "MinimapCluster", enabled = true },
                    { name = "GameTimeFrame", enabled = true },
                    { name = "MiniMapMailFrame", enabled = true },
                    { name = "MiniMapTracking", enabled = true },
                    { name = "QueueStatusButton", enabled = true },
                    { name = "QueueStatusMinimapButton", enabled = true },
                    { name = "GarrisonLandingPageMinimapButton", enabled = true },
                    { name = "ExpansionLandingPageMinimapButton", enabled = true },
                },
            },
            { name = "ElvUI",
                validator = "IsElvUIActive",
                frames = {
                    { name = "ElvUI_MinimapHolder", enabled = true },
                    { name = "ElvUI_DataTextPanel_MiniMapDataPanelSlot1", enabled = true },
                    { name = "ElvUI_DataTextPanel_MiniMapDataPanelSlot2", enabled = true },
                    { name = "ElvUI_DataTextPanel_MiniMapDataPanelSlot3", enabled = true },
                    { name = "AddonCompartmentFrame", enabled = true },
                },
            },
            { name = "Addon Buttons",
                generator = "GetMinimapButtonNames",
            }
        },
    },
    { name = "Unit Frames",
        sections = {
            { name = "Blizzard",
                frames = {
                    { name = "PlayerFrame", enabled = true },
                    { name = "CompactPlayerFrame", enabled = true },
                    { name = "TargetFrame", enabled = true },
                    { name = "FocusFrame", enabled = true },
                    { name = "PetFrame", enabled = true },
                    { name = "StanceBar", enabled = true },
                    { name = "StanceBarFrame", enabled = true },
                },
            },
            { name = "ElvUI",
                validator = "IsElvUIActive",
                frames = {
                    { name = "ElvUF_Player", enabled = true }, -- needs special handling to keep fishing castbar visible
                    { name = "ElvUF_Target", enabled = true },
                    { name = "ElvUF_Pet", enabled = true },
                    { name = "ElvUF_Focus", enabled = true },
                    { name = "ElvUF_TargetTarget", enabled = true },
                    { name = "ElvUF_Party", enabled = true },
                    { name = "ElvUF_Raid", enabled = true },
                    { name = "ElvUF_Boss", enabled = true },
                    { name = "ElvUF_Arena", enabled = true },
                },
            },
        },
    },
    { name = "HUD & Status",
        sections = {
            { name = "Blizzard",
                frames = {
                    { name = "BuffFrame", enabled = true },
                    { name = "DebuffFrame", enabled = true },
                    { name = "DeadlyDebuffFrame", enabled = true },
                },
            },
            { name = "ElvUI",
                validator = "IsElvUIActive",
                frames = {
                    { name = "ElvUI_PlayerBuffs", enabled = true },
                    { name = "ElvUI_PlayerDebuffs", enabled = true },
                },
            },
            {
                name = "Other",
                frames = {
                    { name = "TomTomCrazyArrow", enabled = true },
                    { name = "FTA_GuideArrow", enabled = true },
                },
            },
        },
    },
    { name = "Menus",
        sections = {
            { name = "Blizzard",
                frames = {
                    { name = "MainMenuBar", enabled = true },
                    { name = "MultiBarBottomLeft", enabled = true },
                    { name = "MultiBarBottomRight", enabled = true },
                    { name = "MultiBarLeft", enabled = true },
                    { name = "MultiBarRight", enabled = true },
                    { name = "MicroButtonAndBagsBar", enabled = true },
                    { name = "MicroMenuContainer", enabled = true },
                },
            },
            { name = "ElvUI",
                validator = "IsElvUIActive",
                frames = {
                    { name = "ElvUI_MicroBar", enabled = true },
                },
            },
        },
    },
    { name = "Data Panels",
        sections = {
            { name = "Blizzard",
                frames = {
                    { name = "StatusTrackingBarManager", enabled = true },
                    { name = "ObjectiveTrackerFrame", enabled = true },
                    { name = "UIWidgetTopCenterContainerFrame", enabled = true },
                    { name = "DamageMeter", enabled = true },
                    { name = "DamageMeterSessionWindow1", enabled = true },
                },
            },
            { name = "ElvUI", -- Data bars (these are not official names, I'm just using them to normalize processing)
                validator = "IsElvUIActive",
                frames = {
                    { name = "ElvDB_Experience", enabled = true },
                    { name = "ElvDB_Reputation", enabled = true },
                    { name = "ElvDB_Honor", enabled = true },
                    { name = "ElvDB_Azerite", enabled = true },
                    { name = "ElvDB_Threat", enabled = true },
                },
            },

        },
    },
    -- For adding custom frames
    {
        name = "Custom",
        frames = {},
    },
}

