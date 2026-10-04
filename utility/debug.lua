local addonName, ns = ...
local Addon = ns.Addon
local Utils = {}
ns.Utils = Utils

local MAX_LOG_ENTRIES = 1000
local log = {}

local function Timestamp()
    local uptimeSeconds = GetTime()
    local ms = math.floor((uptimeSeconds % 1) * 1000)
    local totalSecs = math.floor(uptimeSeconds)
    local h = math.floor(totalSecs / 3600)
    local m = math.floor((totalSecs % 3600) / 60)
    local s = totalSecs % 60
    return string.format("%d:%02d:%02d.%03d", h, m, s, ms)
end

local function FormatLogValue(value, seen)
    if type(value) ~= "table" then
        return tostring(value)
    end

    seen = seen or {}
    if seen[value] then
        return "<cycle>"
    end
    seen[value] = true

    local entries = {}
    for key, entry in pairs(value) do
        table.insert(entries, "[" .. FormatLogValue(key, seen) .. "]=" .. FormatLogValue(entry, seen))
    end
    seen[value] = nil

    return "{" .. table.concat(entries, ", ") .. "}"
end

function Addon:GetLogDB()
    local globalLogName = addonName .. "Log"
    if not _G[globalLogName] then
        _G[globalLogName] = {}
    end
    return _G[globalLogName]
end

local function Log(msg, ...)
    if not msg then
        return
    end

    local timestamp = Timestamp()

    local output = timestamp .. ": " .. msg
    if select("#", ...) > 0 then
        local extra = {}
        for i = 1, select("#", ...) do
            table.insert(extra, tostring(select(i, ...)))
        end
        output = output .. " " .. table.concat(extra, " ")
    end

    local logDB = Addon:GetLogDB()
    table.insert(logDB, output)
    if #logDB > MAX_LOG_ENTRIES then
        table.remove(logDB, 1)
    end
end
ns.Utils.Log = Log

local function IsDebugEnabled(module)
    local profile = module and module.db and module.db.profile
    return profile and (profile.debugEnabled or profile.debugMode)
end

local function LogSourceWithStack(level, module, source, stackTrace, msg, ...)
    if not IsDebugEnabled(module) or not source or not msg then
        return
    end

    local output = "[" .. ns.logLevelInfo[level].name .. "][" .. tostring(source) .. "] " .. tostring(msg)
    if select("#", ...) > 0 then
        local extra = {}
        for i = 1, select("#", ...) do
            table.insert(extra, tostring(select(i, ...)))
        end
        output = output .. " " .. table.concat(extra, " ")
    end
    if stackTrace then
        output = output .. "\n" .. tostring(stackTrace)
    end

    Log(output)
end

local function LogSource(level, module, source, msg, ...)
    if not IsDebugEnabled(module) then
        return
    end
    LogSourceWithStack(level, module, source, nil, msg, ...)
end

function ns.Utils.IsCoreLoaded()
    if Addon then return true end

    local success, addonObj = pcall(LibStub("AceAddon-3.0").GetAddon, LibStub("AceAddon-3.0"), addonName)
    if success and addonObj then
        Addon = addonObj
        return true
    end

    return false
end

-- Print to log: none
-- Print to chat: addonName and message
-- For messages that have  already been loggged.
local function PrintModuleNoLog(module, prefix, colorHex, msg, ...)
    if prefix == "" then print("addonName: " .. addonName) end
    prefix = prefix or ("|cFF9ACDFF[" .. addonName .. "]|r ")

    local output = msg
    if select("#", ...) > 0 then
        local extra = {}
        for i = 1, select("#", ...) do
            table.insert(extra, tostring(select(i, ...)))
        end
        output = output .. " " .. table.concat(extra, " ")
    end

    local colorStart = colorHex and "|cFF" .. colorHex or ""
    local colorEnd = colorHex and "|r" or ""
    local timestamp = IsDebugEnabled(module) and (Timestamp() .. ": ") or ""
    DEFAULT_CHAT_FRAME:AddMessage(string.format("%s%s %s%s%s", timestamp, prefix, colorStart, output, colorEnd))
end

local function PrintNoLog(prefix, colorHex, msg, ...)
    PrintModuleNoLog(Addon, prefix, colorHex, msg, ...)
end
ns.Utils.PrintNoLog = PrintNoLog

-- Print to log: timestap and message
-- Print to chat: addonName and message
function Addon:Print(msg, ...)
    local prefix = "|cFF9ACDFF[" .. addonName .. "]|r"
    local output = msg

    if select("#", ...) > 0 then
        local extra = {}
        for i = 1, select("#", ...) do
            table.insert(extra, tostring(select(i, ...)))
        end
        output = output .. " " .. table.concat(extra, " ")
    end

    Log(output)
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. " " .. output)
end

-- Print to log: "timestamp: [Debug] message"
-- Print to chat: "[Debug] message"
-- Intended for core debugging. Normally, modules should use self:Debug()
-- function ns.Utils.Debug(msg, ...)
--     if Addon and Addon.db then
--         if Addon.db.profile.debugEnabled then
--             local prefix = "|cFF9ACDFF[Debug]|r"
--             local output = tostring(msg)
--             Log("[Debug]", output, ...)
--             PrintNoLog(prefix, nil, output, ...)
--         end
--     end
-- end

function Addon:DumpToLog(msg, item, ...)
    Log("[DumpToLog]", FormatLogValue(msg), FormatLogValue(item), ...)
end

function Addon:Dump(msg, item)
    local prefix = "|cFF9ACDFF[" .. addonName .. "]|r"
    PrintNoLog(prefix, nil, FormatLogValue(msg), FormatLogValue(item))
end

function Addon:PrintLootMessage(msg)
    for index = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame"..index]

        if frame then
            -- Get the chat message types received by this specific window
            local messageTypes = { GetChatWindowMessages(index) }

            -- Check if this window is configured to display "LOOT" messages
            for _, msgType in ipairs(messageTypes) do
                if msgType == "LOOT" then
                    -- Print the message locally to this specific window
                    frame:AddMessage("|cFF9ACDFFDreamFish|r " .. tostring(msg))
                    break
                end
            end
        end
    end
end

function Addon:Alert(systemColor, msg, ...)
    local prefix = "|cFF9ACDFF[" .. addonName .. "]|r"
    local blizzName = type(systemColor) == "table" and systemColor.blizzName or nil
    -- RaidWarningUtil.AddMessage indexes colorInfo without a nil check
    local colorInfo = (blizzName and ChatTypeInfo[blizzName]) or ChatTypeInfo["RAID_WARNING"]
    RaidWarningUtil.AddMessage(msg, colorInfo)
    PrintNoLog(prefix, nil, msg, ...)
    LogSource(ns.logLevel.INFO, Addon, "Alert", msg, ...)
end

function Addon:AlertWithSound(systemColor, msg, ...)
    if ns.Utils.IsCoreLoaded() and Addon then
        ns.Utils.PlayWarningCue()
    end
    Addon:Alert(systemColor, msg, ...)
end

function ns.Utils.DebugModuleSourceWithStack(level, module, source, stackTrace, msg, ...)
    if not (module and msg) then
        return
    end

    local logLevelInfo = ns.logLevelInfo[level]
    local colorHex = logLevelInfo.color
    local prefixName = addonName
    if source and source ~= "" then
        prefixName = source
    end
    local prefix = source and string.format("|cFF%s[%s]|r", colorHex, prefixName) or ""
    local hasProfile = module and module.db and module.db.profile

    if source and level <= ns.logLevel.TRACE then
        LogSource(level, module, source, msg, ...)
        if hasProfile and module.db.profile.traces and module.db.profile.traces[source] then
            PrintModuleNoLog(module, prefix, "999999", msg, ...)
        end
    elseif level <= ns.logLevel.DEBUG then
        LogSource(level, module, source, msg, ...)
        if IsDebugEnabled(module) then
            PrintModuleNoLog(module, prefix, nil, msg, ...)
        end
    elseif level <= ns.logLevel.INFO then
        LogSource(level, module, source, msg, ...)
        PrintModuleNoLog(module, prefix, nil, msg, ...)
    elseif level <= ns.logLevel.WARNING then
        LogSource(level, module, source, msg, ...)
        PrintModuleNoLog(module, prefix, colorHex, msg, ...)
    elseif level <= ns.logLevel.ERROR then
        LogSourceWithStack(level, module, source, stackTrace, msg, ...)
        PrintModuleNoLog(module, prefix, colorHex, msg, ...)
    end
end

function ns.Utils.DebugModuleSource(level, module, source, msg, ...)
    ns.Utils.DebugModuleSourceWithStack(level, module, source, nil, msg, ...)
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

function ns.Utils.ItemName(itemID)
    if type(C_Item.GetItemInfo) == "function" then
        local itemName = C_Item.GetItemInfo(itemID)
        return itemName or ("Unknown Item " .. tostring(itemID))
    end
    return "Unknown Item " .. tostring(itemID)
end

function ns.Utils.ItemLink(itemID)
    if type(C_Item.GetItemInfo) == "function" then
        local itemName, itemLink = C_Item.GetItemInfo(itemID)
        return itemLink or itemName or ("Unknown Item " .. tostring(itemID))
    end
    return  "Unknown Item " .. tostring(itemID)
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

-- ==========================================
-- Optional Integration with BugGrabber
-- ==========================================

local function OnBugGrabbed(callback, errObj)
    if not errObj then return end

    local lowerAddonName = string.lower(addonName)
    local message = errObj.message and string.lower(errObj.message) or ""
    local stack = errObj.stack and string.lower(errObj.stack) or ""

    local isMyBug = string.find(message, lowerAddonName, 1, true) or string.find(stack, lowerAddonName, 1, true)

    if isMyBug then
        ns.Utils.DebugModuleSourceWithStack("ERROR", addonName, addonName, errObj.stack, errObj.message)
    end
end

-- Activate only if the player runs BugGrabber/BugSack
local BugGrabber = _G.BugGrabber
if BugGrabber and type(BugGrabber.RegisterCallback) == "function" then
    BugGrabber.RegisterCallback(addonName, "BugGrabber_BugGrabbed", OnBugGrabbed)
end
