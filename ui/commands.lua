-- DreamFisher: Slash Commands

local addon = _G["DreamFisher"]
local PrintMessage = addon.PrintMessage

local function GetCurrentSessionFlagsRequired()
    if not (addon.fishing and addon.fishing.GetCurrentSessionFlags) then
        error("DreamFisher: GetCurrentSessionFlags is required for command diagnostics")
    end
    return addon.fishing.GetCurrentSessionFlags()
end

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
            PrintMessage("  |cFF7FFFDAcast|r - Show secure cast macro helper")
            PrintMessage("  |cFF7FFFDAinteractsetup, is|r - Show hooked-interact setup checklist")
            PrintMessage("  |cFF7FFFDAinteractdiag, id|r - Show live interact target diagnostics")
            PrintMessage("  |cFF7FFFDAraft|r - Apply the selected raft")
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
            local sessionState = addon.state and addon.state.fishingSessionState or "IDLE"
            local flags = GetCurrentSessionFlagsRequired()
            local remaining = 0
            if addon.state.audioRestoreAt then
                remaining = math.max(0, addon.state.audioRestoreAt - GetTime())
            end
            PrintMessage("Audio state: ducked=" .. tostring(addon.state.savedFishingAudioCVars ~= nil)
                .. " sessionState=" .. tostring(sessionState)
                .. " flags={isFishing=" .. tostring(flags.isFishing)
                .. ", isBobberActive=" .. tostring(flags.isBobberActive)
                .. ", lootInProgress=" .. tostring(flags.fishingLootInProgress) .. "}"
                .. " restoreIn=" .. string.format("%.1f", remaining) .. "s")
            PrintMessage("CVars: Ambience=" .. tostring(amb) .. " Music=" .. tostring(mus) .. " Dialog=" .. tostring(dia))
            return
        end
        if command == "duckaudio" or command == "da" then
            addon.audio.EnableFishingAudioFocus(true)
            addon.state.audioRestoreAt = GetTime() + (addon.db.focusedAudioLinger or addon.defaults.focusedAudioLinger or 10)
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
        if command == "cast" then
            if addon.fishing and addon.fishing.HandleCastCommand then
                addon.fishing.HandleCastCommand()
                PrintMessage("Use keybind or macro /click DreamFisherSecureFishingButton RightButton")
            end
            return
        end
        if command == "interactsetup" or command == "is" then
            PrintMessage("Hooked-interact setup checklist:")
            PrintMessage("  1) Bind an Interact key in Game Menu > Options > Keybindings")
            PrintMessage("  2) Enable game interact/soft-target assistance options")
            PrintMessage("  3) Avoid conflicting addons that override world right-click")
            PrintMessage("  4) Enable 'Use same trigger to interact when fish is hooked' in /df > Modes")
            return
        end
        if command == "interactdiag" or command == "id" then
            if addon.fishing and addon.fishing.GetInteractDiagnostics and addon.fishing.FormatInteractDiagnostics then
                local diag = addon.fishing.GetInteractDiagnostics()
                PrintMessage("Interact diag: " .. addon.fishing.FormatInteractDiagnostics(diag))
            else
                PrintMessage("Interact diagnostics unavailable")
            end
            local flags = GetCurrentSessionFlagsRequired()
            PrintMessage("State: sessionState=" .. tostring(addon.state and addon.state.fishingSessionState)
                .. " flags={isFishing=" .. tostring(flags.isFishing)
                .. ", isBobberActive=" .. tostring(flags.isBobberActive)
                .. ", lootInProgress=" .. tostring(flags.fishingLootInProgress) .. "}")
            return
        end
        if command == "raft" then
            PrintMessage("Raft toy usage requires a secure click. Use the Tackle tab's Apply Raft button.")
            return
        end
        addon:ToggleUI()
    end
end

-- Export to addon
addon.commands = addon.commands or {}
addon.commands.RegisterSlashCommands = RegisterSlashCommands
