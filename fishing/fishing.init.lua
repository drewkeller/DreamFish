local addonName, ns = ...
local Addon = LibStub("AceAddon-3.0"):GetAddon(addonName)

local Fishing = Addon:NewModule("Fishing", ns.ModulePrototype, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")

ns.Fishing = ns.Fishing or {}
ns.precast = ns.precast or {}
ns.FishingInitializers = ns.FishingInitializers or {}

ns.fishing = ns.fishing or {}
ns.fishing.const = ns.fishing.const or {}
ns.fishing.state = ns.fishing.state or {}

