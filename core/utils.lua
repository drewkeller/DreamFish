local addonName, ns = ...
local Addon = ns.Addon
local Utils = {}
ns.Utils = Utils

function Addon:Alert(msg, ...)
    Addon:PlayWarningCue()
    RaidWarningUtil.AddMessage(msg, ChatTypeInfo["SYSTEM"])
end

function Addon:Debug(msg, ...)
    if self.db.profile.debugMode then
        self:Print("|cFF9ACDFF[Debug]|r ", msg, ...)
    end
end

function ns.Utils.Trace(module, source, msg, ...)
    if not (Addon and Addon.db and Addon.db.profile and Addon.db.profile.moduleEnabled) then
        return
    end

    if not (module and module.db and module.db.profile.traces) then return end

    if module.db and module.db.profile and module.db.profile.traceMode and module.db.profile.traceMode[source] then
        Addon:Print("|cFF999999[" .. source .. "]|r ", msg, ...)
    end
end

function Addon:FormatDuration(seconds)
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

function Addon:GetDebugItemLabel(itemID)
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

function Addon:GetDebugCooldownText(itemID)
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

