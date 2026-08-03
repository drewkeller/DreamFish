local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

-- Check if the input command is a known alias and normalize it to the corresponding full command path
local function NormalizeSlashInput(input)
    local command, rest = input:match("^(%S+)%s*(.*)$")
    if not command then
        return input
    end

    local aliases = {
        debug = "general debugMode",
        debugmode = "general debugMode",
    }

    local normalized = aliases[command:lower()]
    if not normalized then
        return input
    end

    if rest ~= "" then
        return normalized .. " " .. rest
    end

    return normalized
end

function ns:RegisterChatCommands()
    DreamFish:RegisterChatCommand("dreamfish", "SlashCommand")
    DreamFish:RegisterChatCommand("df", "SlashCommand")
end

function DreamFish:SlashCommand(input)
    if not input or input:trim() == "" then
        -- Open graphical option frame if typed completely bare
        Settings.OpenToCategory(self.optionsCategoryID or (self.optionsFrame and self.optionsFrame.name) or "DreamFish")
    else
        -- Pass all sub-arguments straight to the AceConfig command interpreter engine
        LibStub("AceConfigCmd-3.0"):HandleCommand("df", "DreamFish", NormalizeSlashInput(input))
    end
end
