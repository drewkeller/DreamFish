local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)

local Fishing = DreamFish:NewModule("Fishing", ns.ModulePrototype, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")

ns.Fishing = ns.Fishing or {}
ns.precast = ns.precast or {}
