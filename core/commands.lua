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
    local cleanInput = input and input:trim():lower() or ""

    if cleanInput == "" then
        -- Open graphical option frame if typed completely bare
        Settings.OpenToCategory(self.optionsCategoryID or (self.optionsFrame and self.optionsFrame.name) or "DreamFish")

    elseif cleanInput == "tackle" then
        -- Open or toggle your specific tackle frame window
        -- if ns.ui.TackleWindow then
        --     ns.ui.TackleWindow:Show()
        -- else
        --     print("|cffff0000DreamFish Error:|r Tackle window frame not found.")
        -- end
        DreamFish:OpenDialogWindow("DreamFishDialog")

    else
        -- Pass all other sub-arguments straight to the AceConfig command interpreter engine
        -- Note: We pass the original 'input' string here to preserve case sensitivity for other commands
        LibStub("AceConfigCmd-3.0"):HandleCommand("df", "DreamFish", NormalizeSlashInput(input))
    end
end
