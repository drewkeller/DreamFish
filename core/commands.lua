local addonName, ns = ...
local Addon = ns.Addon

local DialogName = addonName .. "Dialog"

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

function Addon:RegisterChatCommands()
    Addon:RegisterChatCommand("dreamfish", "SlashCommand")
    Addon:RegisterChatCommand("df", "SlashCommand")
end

function Addon:SlashCommand(input)
    local cleanInput = input and input:trim():lower() or ""

    if cleanInput == "" then
        -- Open graphical option frame if typed completely bare
        Settings.OpenToCategory(self.optionsCategoryID or (self.optionsFrame and self.optionsFrame.name) or "Addon")
        -- keep/reopen tackle box window, but only if it was already open
        local AceConfigDialog = LibStub("AceConfigDialog-3.0")
        if AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames[DialogName] then
            C_Timer.After(0.01, function()
                Addon:OpenDialogWindow(DialogName)
            end)
        end

    elseif cleanInput == "tackle" then
        --Addon:OpenDialogWindow(DialogName, "buffsTab")
        Addon:OpenDialogWindow(DialogName, "polesTab")
    else
        -- Pass all other sub-arguments straight to the AceConfig command interpreter engine
        -- Note: We pass the original 'input' string here to preserve case sensitivity for other commands
        LibStub("AceConfigCmd-3.0"):HandleCommand("df", addonName, NormalizeSlashInput(input))
    end
end
