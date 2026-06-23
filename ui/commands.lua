-- DreamFisher: Slash Commands

local addon = _G["DreamFisher"]
local PrintMessage = addon.PrintMessage

local function RegisterSlashCommands()
    SLASH_DREAMFISHER1 = "/df"
    SLASH_DREAMFISHER2 = "/dreamfisher"
    SlashCmdList["DREAMFISHER"] = function(msg)
        local command = string.lower(strtrim(msg or ""))
        if command == "help" or command == "h" or command == "?" then
            PrintMessage("|cFFFFD700Available Commands:|r")
            PrintMessage("  |cFF7FFFDAhelp, h, ?|r - Show this help message")
            PrintMessage("  |cFF7FFFDAtesttreasure, tt|r - Test Patient Treasure alert")
            PrintMessage("  |cFF7FFFDAtestbagsfull, tbf|r - Test bags full alert")
            PrintMessage("  |cFF7FFFDAtestaudio, ta|r - Test audio ducking (show before/after CVars)")
            PrintMessage("  |cFF7FFFDAaudiostate, as|r - Display current audio ducking state")
            PrintMessage("  |cFF7FFFDAduckaudio, da|r - Manually start audio ducking")
            PrintMessage("  |cFF7FFFDArestoreaudio, ra|r - Manually restore audio from ducking")
            PrintMessage("  |cFF7FFFDAdebug, dbg|r - Toggle debug mode on/off")
            PrintMessage("  |cFF7FFFDAmodifier <ALT|CTRL|SHIFT|NONE>|r - Set world right-click modifier")
            PrintMessage("  |cFF7FFFDA(no args)|r - Toggle config UI")
            return
        end
        if command == "testtreasure" or command == "tt" then
            addon.alerts.ShowPatientTreasureAlert("Test Trigger", true)
            PrintMessage("Triggered Patient Treasure alert test.")
            return
        end
        if command == "testbagsfull" or command == "tbf" then
            addon.alerts.ShowBagFullAlert(true)
            PrintMessage("Triggered bags full alert test.")
            return
        end
        if command == "testaudio" or command == "ta" then
            local amb = GetCVar("Sound_AmbienceVolume")
            local mus = GetCVar("Sound_MusicVolume")
            local dia = GetCVar("Sound_DialogVolume")
            PrintMessage("Audio before duck: Ambience=" .. tostring(amb) .. " Music=" .. tostring(mus) .. " Dialog=" .. tostring(dia))
            addon.audio.EnableFishingAudioFocus(true)
            local amb2 = GetCVar("Sound_AmbienceVolume")
            local mus2 = GetCVar("Sound_MusicVolume")
            local dia2 = GetCVar("Sound_DialogVolume")
            PrintMessage("Audio after duck:  Ambience=" .. tostring(amb2) .. " Music=" .. tostring(mus2) .. " Dialog=" .. tostring(dia2))
            return
        end
        if command == "audiostate" or command == "as" then
            local amb = GetCVar("Sound_AmbienceVolume")
            local mus = GetCVar("Sound_MusicVolume")
            local dia = GetCVar("Sound_DialogVolume")
            local remaining = 0
            if addon.state.audioRestoreAt then
                remaining = math.max(0, addon.state.audioRestoreAt - GetTime())
            end
            PrintMessage("Audio state: ducked=" .. tostring(addon.state.savedFishingAudioCVars ~= nil)
                .. " isFishing=" .. tostring(addon.state.isFishing)
                .. " bobberActive=" .. tostring(addon.state.isBobberActive)
                .. " lootInProgress=" .. tostring(addon.state.fishingLootInProgress)
                .. " restoreIn=" .. string.format("%.1f", remaining) .. "s")
            PrintMessage("CVars: Ambience=" .. tostring(amb) .. " Music=" .. tostring(mus) .. " Dialog=" .. tostring(dia))
            return
        end
        if command == "duckaudio" or command == "da" then
            addon.audio.EnableFishingAudioFocus(true)
            addon.state.audioRestoreAt = GetTime() + (addon.db.audioFocusLinger or addon.defaults.audioFocusLinger or 10)
            local amb = GetCVar("Sound_AmbienceVolume")
            local mus = GetCVar("Sound_MusicVolume")
            local dia = GetCVar("Sound_DialogVolume")
            PrintMessage("Audio ducking enabled. CVars: Ambience=" .. tostring(amb) .. " Music=" .. tostring(mus) .. " Dialog=" .. tostring(dia))
            return
        end
        if command == "restoreaudio" or command == "ra" then
            addon.audio.RestoreFishingAudioFocus()
            local amb = GetCVar("Sound_AmbienceVolume")
            local mus = GetCVar("Sound_MusicVolume")
            local dia = GetCVar("Sound_DialogVolume")
            PrintMessage("Audio restored: Ambience=" .. tostring(amb) .. " Music=" .. tostring(mus) .. " Dialog=" .. tostring(dia))
            return
        end
        if command == "debug" or command == "dbg" then
            addon.db.debugMode = not addon.db.debugMode
            PrintMessage("Debug mode: " .. (addon.db.debugMode and "ON" or "OFF"))
            return
        end
        local modifierArg = command:match("^modifier%s+(%S+)$")
        if modifierArg then
            local value = string.upper(modifierArg)
            if value == "ALT" or value == "CTRL" or value == "SHIFT" or value == "NONE" then
                addon.db.worldRightClickModifier = value
                addon.db.worldRightClickModifierUserSet = true
                PrintMessage("World right-click modifier set to: " .. value)
            else
                PrintMessage("Invalid modifier. Use: ALT, CTRL, SHIFT, or NONE")
            end
            return
        end
        addon:ToggleUI()
    end
end

-- Export to addon
addon.commands = addon.commands or {}
addon.commands.RegisterSlashCommands = RegisterSlashCommands
