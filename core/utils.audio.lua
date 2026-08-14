local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

function DreamFish:PlayWarningCue()
    if type(PlaySound) == "function" and SOUNDKIT then
        local cue = SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.UI_RaidBossEmoteWarning
        if cue then
            PlaySound(cue, "Master")
        end
    end
end
