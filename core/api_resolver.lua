-- DreamFish: Shared module API resolvers
-- Centralize registry-first resolution with safe fallback paths.

local addon = _G["DreamFish"]
if not addon then
    return
end

local function ResolveModuleAPI(moduleName, fallbackField)
    if addon.moduleAPI and addon.moduleAPI.Get then
        local api = addon.moduleAPI.Get(moduleName)
        if api then
            return api
        end
    end

    if type(fallbackField) == "string" and fallbackField ~= "" then
        return addon[fallbackField]
    end

    return nil
end

local function RequireModuleAPI(moduleName, fallbackField)
    local api = ResolveModuleAPI(moduleName, fallbackField)
    if not api then
        error("DreamFish: required module API is missing: " .. tostring(moduleName))
    end
    return api
end

local function GetFishingAPI()
    return ResolveModuleAPI("fishing", "fishing")
end

local function GetAudioAPI()
    return ResolveModuleAPI("audio", "audio")
end

local function GetAlertsAPI()
    return ResolveModuleAPI("alerts", "alerts")
end

local function GetUIFocusAPI()
    return ResolveModuleAPI("uiFocus", "uiFocus")
end

local function RequireFishingAPI()
    return RequireModuleAPI("fishing", "fishing")
end

local function RequireAudioAPI()
    return RequireModuleAPI("audio", "audio")
end

local function RequireAlertsAPI()
    return RequireModuleAPI("alerts", "alerts")
end

local function RequireUIFocusAPI()
    return RequireModuleAPI("uiFocus", "uiFocus")
end

addon.ResolveModuleAPI = ResolveModuleAPI
addon.RequireModuleAPI = RequireModuleAPI
addon.GetFishingAPI = GetFishingAPI
addon.GetAudioAPI = GetAudioAPI
addon.GetAlertsAPI = GetAlertsAPI
addon.GetUIFocusAPI = GetUIFocusAPI
addon.RequireFishingAPI = RequireFishingAPI
addon.RequireAudioAPI = RequireAudioAPI
addon.RequireAlertsAPI = RequireAlertsAPI
addon.RequireUIFocusAPI = RequireUIFocusAPI
