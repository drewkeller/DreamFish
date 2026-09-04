local addonName, ns = ...

function ns.Utils.PlayWarningCue()
    if type(PlaySound) == "function" and SOUNDKIT then
        local cue = SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.UI_RaidBossEmoteWarning
        if cue then
            PlaySound(cue, "Master")
        end
    end
end

function ns.Utils.CloneAudioTriplet(values)
    if type(values) ~= "table" then
        return nil
    end
    return {
        ambience = values.ambience,
        music = values.music,
        dialog = values.dialog,
    }
end

