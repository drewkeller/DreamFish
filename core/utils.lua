local addonName, ns = ...
local Addon = nil
local Utils = {}
ns.Utils = Utils

function ns.Utils.IsCoreLoaded()
    if Addon then return true end

    local success, addonObj = pcall(LibStub("AceAddon-3.0").GetAddon, LibStub("AceAddon-3.0"), addonName)
    if success and addonObj then
        Addon = addonObj
        return true
    end

    return false
end

function ns.Utils.Print(msg, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF9ACDFF[" .. addonName .. "]|r " .. tostring(msg), ...)
end

-- Intended for core debugging. Normally, modules should use self:Debug()
function ns.Utils.Debug(msg, ...)
    if Addon and Addon.db then
        if Addon.db.profile.debugEnabled then
            ns.Utils.Print("|cFF9ACDFF[Debug]|r " .. tostring(msg), ...)
        end
    end
end

function ns.Utils.Dump(msg, item, ...)
    if type(msg) == "table" then
        DevTools_Dump(msg)
    else
        ns.Utils.Print("|cFF9ACDFF[Dump]|r ", msg, ...)
    end
    if type(item) == "table" then
        DevTools_Dump(item)
    else
        ns.Utils.Print("|cFF9ACDFF[Dump]|r ", msg, item, ...)
    end
end

function ns.Utils.DebugDump(msg, item, ...)
    if Addon and Addon.db then
        if Addon.db.profile.debugEnabled then
            ns.Utils.Dump(msg, item, ...)
        end
    end
end

function ns.Utils.Alert(msg, ...)
    if ns.Utils.IsCoreLoaded() and Addon then
        ns.Utils.PlayWarningCue()
    end
    RaidWarningUtil.AddMessage(msg, ChatTypeInfo["SYSTEM"])
end

function ns.Utils.CoreTrace(source, msg, ...)
    if not (Addon and Addon.db) then
        return
    end

    if not source or not msg then
        return
    end

    if Addon.db.profile.traces[source] then
        ns.Utils.Print("|cFF999999[" .. source .. "]|r ", msg, ...)
    end
end

function ns.Utils.FormatDuration(seconds)
    local n = tonumber(seconds)
    if not n or n < 0 then
        return "unknown"
    end
    local rounded = math.floor(n + 0.5)
    local minutes = math.floor(rounded / 60)
    local secs = rounded % 60
    if minutes > 0 then
        return tostring(minutes) .. "m " .. tostring(secs) .. "s"
    end
    return tostring(secs) .. "s"
end

function ns.Utils.GetDebugItemLabel(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return "unknown"
    end
    local name = C_Item.GetItemInfo(numeric)
    if name and name ~= "" then
        return tostring(name) .. " (" .. tostring(numeric) .. ")"
    end
    return "item:" .. tostring(numeric)
end

function ns.Utils.GetDebugCooldownText(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return "cooldown=unknown"
    end

    local start, duration, enabled = C_Item.GetItemCooldown(numeric)
    if not enabled or enabled == 0 then
        return "cooldown=disabled"
    end
    if not start or not duration or duration <= 0 then
        return "cooldown=ready"
    end

    local remaining = math.max(0, (start + duration) - GetTime())
    return "cooldownRemaining=" .. string.format("%.1fs", remaining)
end

