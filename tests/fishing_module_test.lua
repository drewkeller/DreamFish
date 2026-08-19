local modules = {}
local frameCreated = false
local registeredEvents = {}
local preparedActionCount = 0
local bindingsApplied = false
local frameRemoved = false
local tackleTabRegistered = false
local mounted = false
local underlightEquipReasons = {}

local DreamFish = {
    db = {
        profile = {
            debugMode = false,
            fishing = {
                moduleEnabled = true,
                debug = false,
                castBySingleRightClickWhenFishing = false,
                easyStrike = true,
            },
        },
        char = {
            fishing = {},
        },
    },
}

function DreamFish:NewModule(name, prototype)
    local module = setmetatable({}, { __index = prototype })

    function module:SetEnabledState(enabled)
        self.enabled = enabled
    end

    function module:Enable()
        self.enabled = true
    end

    function module:Disable()
        self.enabled = false
    end

    modules[name] = module
    return module
end

function DreamFish:GetModule(name)
    return assert(modules[name], "module not found: " .. name)
end

function DreamFish:Print()
end

function DreamFish:BuildOwnedToyOptions()
    return {
        [0] = "No Raft",
        [85500] = "Angler's Fishing Raft",
    }
end

function DreamFish:BuildOwnedToyOptionsKeys()
    return {}
end

function LibStub(name)
    assert(name == "AceAddon-3.0")
    return {
        GetAddon = function()
            return DreamFish
        end,
    }
end

local namespace = {}
assert(loadfile("core/module_prototype.lua"))("DreamFish", namespace)
assert(loadfile("fishing/fishing.init.lua"))("DreamFish", namespace)
assert(loadfile("fishing/fishing.const.lua"))("DreamFish", namespace)
assert(loadfile("fishing/fishing.options.lua"))("DreamFish", namespace)
assert(loadfile("fishing/states.lua"))("DreamFish", namespace)
assert(loadfile("fishing/fishing.lua"))("DreamFish", namespace)

namespace.precast.EquipUnderlightAnglerAfterFishing = function(reason)
    table.insert(underlightEquipReasons, reason)
end

local Fishing = DreamFish:GetModule("Fishing")

namespace.ui = {
    TackleWindow = {
        RegisterTab = function(_, tab)
            assert(tab.id == "poles", "Fishing registered the wrong tackle tab")
            tackleTabRegistered = true
        end,
    },
}

function Fishing:CreateClickFrame()
    frameCreated = true
    self.clickFrame = {
        GetName = function()
            return "DreamFishSecureFishingFrame"
        end,
        Show = function()
        end,
        SetAttribute = function()
        end,
    }
end

function Fishing:RegisterEvent(event)
    registeredEvents[event] = true
end

function Fishing:ApplyKeybinding()
    bindingsApplied = true
end

function Fishing:PrepareFishingClickAction()
    preparedActionCount = preparedActionCount + 1
end

function Fishing:RefreshPoleBorders()
end

function Fishing:WatchStrikeKey()
end

function Fishing:StopWatchingStrikeKey()
end

function GetBindingKey()
    return "NUMPAD0"
end

function SetOverrideBinding()
end

function Fishing:UnregisterEvent(event)
    registeredEvents[event] = nil
end

function Fishing:RemoveClickFrame()
    frameRemoved = true
end

function Fishing:ReleaseClickCapture()
end

function Fishing:SendMessage()
end

function SetOverrideBindingClick()
end

function InCombatLockdown()
    return false
end

function ClearOverrideBindings()
end

function IsMounted()
    return mounted
end

Fishing:OnInitialize()
Fishing:OnEnable()

assert(Fishing.moduleConfig.displayName == "Fishing", "display name was not configured")
assert(Fishing.moduleConfig.dbKey == "fishing", "database key was not configured")
assert(namespace.DatabaseDefaults.profile.fishing.moduleEnabled, "Fishing defaults were not composed")
assert(Fishing.enabled, "Fishing did not use its saved enabled state")
assert(tackleTabRegistered, "enabling Fishing did not register its tackle tab")
assert(frameCreated, "enabling Fishing did not create the secure frame")
assert(registeredEvents.PLAYER_REGEN_ENABLED, "enabling Fishing did not register its combat event")
assert(registeredEvents.PLAYER_EQUIPMENT_CHANGED, "enabling Fishing did not register its equipment refresh event")
assert(registeredEvents.UNIT_AURA, "enabling Fishing did not register its aura refresh event")
assert(registeredEvents.UNIT_SPELLCAST_START, "enabling Fishing did not register its spellcast start event")
assert(registeredEvents.UNIT_SPELLCAST_CHANNEL_START, "enabling Fishing did not register its spellcast channel event")
assert(registeredEvents.UNIT_SPELLCAST_SUCCEEDED, "enabling Fishing did not register its spellcast success event")
assert(registeredEvents.PLAYER_MOUNT_DISPLAY_CHANGED, "enabling Fishing did not register its mount event")
assert(bindingsApplied, "enabling Fishing did not apply its keybinding")
assert(preparedActionCount == 1, "enabling Fishing did not prepare its secure fishing action")

Fishing:OnCastStarted()
assert(preparedActionCount == 2, "starting Fishing must configure the secure action exactly once")
Fishing:OnEquipmentChanged(nil, "player")
assert(preparedActionCount == 3, "PRECASTING refresh must reconfigure the secure action")
assert(namespace.fishing.state.current == namespace.fishing.states.PRECASTING,
    "starting a cast did not enter PRECASTING")
Fishing:HandleFishingSpellcast("UNIT_SPELLCAST_START", "player", "cast-guid", namespace.fishing.const.fishingSpellID)
assert(namespace.fishing.state.current == namespace.fishing.states.WAITING_FOR_BITE,
    "Fishing spellcast did not arm the bobber strike")
Fishing:OnEquipmentChanged(nil, "player")
assert(preparedActionCount == 3, "refresh while waiting for a bite must not reconfigure the secure action")
local cancelledFor
local setFishingState = Fishing.SetFishingState
function Fishing:SetFishingState(state, reason)
    cancelledFor = reason
    return setFishingState(self, state, reason)
end

Fishing:CancelFishingForMovement()
assert(namespace.fishing.state.current == namespace.fishing.states.IDLE,
    "movement cancellation did not return Fishing to IDLE")
assert(cancelledFor == "cancelled: movement", "movement cancellation used the wrong reason")
assert(underlightEquipReasons[#underlightEquipReasons] == "cancelled: movement",
    "movement cancellation did not request Underlight Angler equip")

Fishing:OnCastStarted()
Fishing:CancelFishingForCombat()
assert(cancelledFor == "cancelled: combat", "combat cancellation used the wrong reason")
assert(underlightEquipReasons[#underlightEquipReasons] == "cancelled: combat",
    "combat cancellation did not request Underlight Angler equip")

Fishing:OnCastStarted()
mounted = false
Fishing:CancelFishingForMount()
assert(namespace.fishing.state.current == namespace.fishing.states.PRECASTING,
    "dismount must not cancel fishing")

mounted = true
Fishing:CancelFishingForMount()
assert(namespace.fishing.state.current == namespace.fishing.states.IDLE,
    "mounting did not cancel fishing")
assert(cancelledFor == "cancelled: mounted", "mount cancellation used the wrong reason")

Fishing:OnModuleDisable()

assert(next(registeredEvents) == nil, "disabling Fishing did not unregister its events")
assert(frameRemoved, "disabling Fishing did not remove the secure frame")

local options = Fishing:GetOptionsTable()
assert(options.name == "Fishing", "Fishing options group was not created")
assert(options.args.moduleEnabled, "Fishing enable option is missing")
assert(options.childGroups == "tab", "Fishing options must render child groups as tabs")
assert(options.args.modesTab, "Modes tab is missing from the Fishing tab group")
assert(options.args.tackleTab, "Tackle tab is missing from the Fishing tab group")
assert(options.args.modesTab.type == "group", "Modes tab is not an AceConfig group")
assert(options.args.tackleTab.type == "group", "Tackle tab is not an AceConfig group")
assert(options.args.moduleOptions == nil, "Fishing tabs must not be nested in an inline module group")
assert(options.args.modesTab.args.castingTriggers.args.castBySingleRightClickWhenFishing,
    "single-right-click option is missing")
local raftValues = options.args.tackleTab.args.raftSection.args.selectedRaftToy.values
if type(raftValues) == "function" then
    raftValues = raftValues()
end
assert(type(raftValues) == "table", "Raft select values should resolve to a table")
assert(raftValues[0] == "No Raft", "Raft select is missing its default label")
assert(raftValues[85500] == "Angler's Fishing Raft", "Raft select values must be label strings")

print("fishing_module_test: passed")