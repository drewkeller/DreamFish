local calls = {
    forceHidden = 0,
    forceVisible = 0,
}

string.trim = function(value)
    return value:match("^%s*(.-)%s*$")
end

local Fishing = {
    ForceHidden = function()
        calls.forceHidden = calls.forceHidden + 1
    end,
    ForceVisible = function()
        calls.forceVisible = calls.forceVisible + 1
    end,
}

local Addon = {}

function Addon:GetModule(name)
    assert(name == "Fishing", "unexpected module: " .. tostring(name))
    return Fishing
end

assert(loadfile("core/commands.lua"))("DreamFish", { Addon = Addon })

Addon:SlashCommand("show")
assert(calls.forceVisible == 1, "/df show should force frames visible")
assert(calls.forceHidden == 0, "/df show should not hide frames")

Addon:SlashCommand("fade")
assert(calls.forceHidden == 1, "/df fade should force frames hidden")
assert(calls.forceVisible == 1, "/df fade should not show frames")

print("commands_test: passed")