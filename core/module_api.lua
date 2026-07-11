-- DreamFisher: Module API Registry
-- Provides a stable place for modules to publish and consume APIs.

local addon = _G["DreamFisher"]
if not addon then
    return
end

addon.moduleAPI = addon.moduleAPI or {}
addon.moduleAPI._registry = addon.moduleAPI._registry or {}

local registry = addon.moduleAPI._registry

local function Register(name, api)
    if type(name) ~= "string" or name == "" then
        error("DreamFisher: module API name must be a non-empty string")
    end
    if type(api) ~= "table" then
        error("DreamFisher: module API must be a table for module '" .. tostring(name) .. "'")
    end
    registry[name] = api
    return api
end

local function Get(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return registry[name]
end

local function Require(name)
    local api = Get(name)
    if not api then
        error("DreamFisher: required module API is missing: " .. tostring(name))
    end
    return api
end

local function Has(name)
    return Get(name) ~= nil
end

addon.moduleAPI.Register = Register
addon.moduleAPI.Get = Get
addon.moduleAPI.Require = Require
addon.moduleAPI.Has = Has
