local addonName, ns = ...
local Addon = ns.Addon

function Addon:PlayWarningCue()
    if type(PlaySound) == "function" and SOUNDKIT then
        local cue = SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.UI_RaidBossEmoteWarning
        if cue then
            PlaySound(cue, "Master")
        end
    end
end
