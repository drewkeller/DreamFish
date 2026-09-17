local modules = {}
local frameCreated = false
local registeredEvents = {}
local preparedActionCount = 0
local bindingsApplied = false
local frameRemoved = false
local tackleTabRegistered = false
local mounted = false
local swimming = false
local alertMessages = {}
local underlightEquipReasons = {}
local releaseClickCaptureCount = 0

local DreamFish = {
    db = {
        profile = {
            debugMode = false,
            fishing = {
                moduleEnabled = true,
                debug = false,
                castBySingleRightClickWhenFishing = false,
                strikeByRightClick = true,
                strikeByHotkey = true,
                lingerExpirationEnabled = true,
                lingerDuration = 10,
            },
        },
        char = {
            fishing = {},
        },
    },
}

function DreamFish:NewModule(name, prototype)
    local module = setmetatable({}, { __index = self.defaultModulePrototype })

    function module:GetName()
        return name
    end

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

function DreamFish:Alert(_, message)
    table.insert(alertMessages, message)
end

function DreamFish:SetDefaultModulePrototype(prototype)
    self.defaultModulePrototype = prototype
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

function LibStub(name, silent)
    if name == "AceAddon-3.0" then
        return {
            GetAddon = function()
                return DreamFish
            end,
        }
    end
    if silent then
        return nil
    end
    assert(name == "AceAddon-3.0")
end

function DreamFish.db:RegisterNamespace(name)
    assert(name == "Fishing", "unexpected namespace: " .. tostring(name))
    return {
        profile = DreamFish.db.profile.fishing,
        char = DreamFish.db.char.fishing,
        global = {},
        RegisterDefaults = function()
        end,
    }
end

local namespace = {
    Addon = DreamFish,
    SystemColor = { YELLOW = "yellow" },
    moduleConstants = {},
    moduleDefaults = {},
    Utils = {
        DebugModuleSource = function()
        end,
        BuildOwnedToyOptions = function()
            return DreamFish:BuildOwnedToyOptions()
        end,
        BuildOwnedToySortingKeys = function()
            return DreamFish:BuildOwnedToyOptionsKeys()
        end,
    },
    logLevel = { DEBUG = 0 },
}
assert(loadfile("module/prototype.lua"))("DreamFish", namespace)
assert(loadfile("module/debug.lua"))("DreamFish", namespace)
assert(loadfile("module/callbacks.lua"))("DreamFish", namespace)
assert(loadfile("fishing/_constants.lua"))("DreamFish", namespace)
assert(loadfile("fishing/_defaults.lua"))("DreamFish", namespace)
assert(loadfile("fishing/_defaults_framefade.lua"))("DreamFish", namespace)
assert(loadfile("fishing/_options.lua"))("DreamFish", namespace)
assert(loadfile("fishing/fishing.lua"))("DreamFish", namespace)
assert(loadfile("fishing/states.lua"))("DreamFish", namespace)

namespace.precast.EquipUnderlightAnglerAfterFishing = function(reason)
    table.insert(underlightEquipReasons, reason)
end
namespace.precast.GetRaftUseDecision = function()
    return { hasToy = true, auraRemaining = 30, blockedByShapeshift = false }
end

local Fishing = DreamFish:GetModule("Fishing")

-- Mimic AceDB's defaults merge for the fadeFrames tree (not modeled by the RegisterNamespace stub above).
local function DeepCopy(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == "table" and DeepCopy(value) or value
    end
    return copy
end
DreamFish.db.profile.fishing.fadeFrames = DeepCopy(namespace.moduleDefaults.Fishing.profile.fadeFrames)


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
    local attributes = {}
    self.clickFrame = {
        GetName = function()
            return "DreamFishSecureFishingFrame"
        end,
        Show = function()
        end,
        SetAttribute = function(_, key, value)
            attributes[key] = value
        end,
        GetAttribute = function(_, key)
            return attributes[key]
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

function Fishing:CheckEnabledBuffItemsDepleted()
end

function Fishing:CheckAndEquipUnderlightAngler(reason)
    namespace.precast.EquipUnderlightAnglerAfterFishing(reason)
end

function Fishing:WatchStrikeKey()
end

function Fishing:StopWatchingStrikeKey()
end

function Fishing:StartMouseButtonWatch()
end

function Fishing:StopMouseButtonWatch()
end

function Fishing:Debug()
end

function Fishing:Trace()
end

function Fishing:RegisterMessage()
end

function Fishing:UnregisterMessage()
end

function GetBindingKey()
    return "NUMPAD0"
end

function SetOverrideBinding()
end

function IsMouseButtonDown()
    return false
end

function CreateFrame()
    return {}
end

function Fishing:UnregisterEvent(event)
    registeredEvents[event] = nil
end

function Fishing:RemoveClickFrame()
    frameRemoved = true
end

function Fishing:RemoveCastBar()
end

function Fishing:ReleaseClickCapture()
    releaseClickCaptureCount = releaseClickCaptureCount + 1
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

function IsSwimming()
    return swimming
end

Fishing:OnInitialize()
Fishing:OnEnable()

assert(Fishing.config.displayName == "Fishing", "display name was not configured")
assert(Fishing.config.dbKey == "fishing", "database key was not configured")
assert(Fishing.enabled, "Fishing did not use its saved enabled state")
assert(frameCreated, "enabling Fishing did not create the secure frame")
assert(registeredEvents.PLAYER_REGEN_ENABLED, "enabling Fishing did not register its combat event")
assert(registeredEvents.PLAYER_EQUIPMENT_CHANGED, "enabling Fishing did not register its equipment refresh event")
assert(registeredEvents.UNIT_AURA, "enabling Fishing did not register its aura refresh event")
assert(registeredEvents.UNIT_SPELLCAST_START, "enabling Fishing did not register its spellcast start event")
assert(registeredEvents.UNIT_SPELLCAST_SUCCEEDED, "enabling Fishing did not register its spellcast success event")
assert(registeredEvents.PLAYER_MOUNT_DISPLAY_CHANGED, "enabling Fishing did not register its mount event")
assert(bindingsApplied, "enabling Fishing did not apply its keybinding")
assert(preparedActionCount == 0, "enabling Fishing must not prepare a cast action before a fishing session starts")

Fishing:OnCastStarted()
assert(preparedActionCount == 1, "starting Fishing must configure the secure action exactly once")
FISHINGTOOLSLOT = 20
Fishing:OnEquipmentChanged(nil, FISHINGTOOLSLOT)
assert(preparedActionCount == 2, "PRECASTING refresh must reconfigure the secure action")
assert(Fishing.state.current == namespace.Fishing.states.PRECASTING,
    "starting a cast did not enter PRECASTING")
Fishing:OnSpellcastChannelEnded(nil, "player", "stale-cast-guid", namespace.Fishing.const.fishingSpellID)
assert(Fishing.state.current == namespace.Fishing.states.PRECASTING,
    "a delayed channel stop must not cancel an unconfirmed cast")
Fishing:OnSpellcastChannelStarted(nil, "player", "cast-guid", namespace.Fishing.const.fishingSpellID)
assert(releaseClickCaptureCount == 1,
    "confirming a fishing cast must close the temporary full-screen click capture")
assert(Fishing.state.current == namespace.Fishing.states.WAITING_FOR_BITE,
    "confirming a fishing cast must arm bobber interaction")
Fishing:OnEquipmentChanged(nil, FISHINGTOOLSLOT)
assert(preparedActionCount == 2, "refresh while waiting for a bite must not reconfigure the secure action")
local cancelledFor
local setFishingState = Fishing.SetFishingState
function Fishing:SetFishingState(state, reason)
    cancelledFor = reason
    return setFishingState(self, state, reason)
end

Fishing:OnMovementStarted()
assert(Fishing.state.current == namespace.Fishing.states.IDLE,
    "movement cancellation did not return Fishing to IDLE")
assert(cancelledFor == "cancelled: movement started", "movement cancellation used the wrong reason")
assert(underlightEquipReasons[#underlightEquipReasons] == "cancelled: movement started",
    "movement cancellation did not request Underlight Angler equip")

Fishing:OnCastStarted()
Fishing:OnCombatStarted()
assert(cancelledFor == "cancelled: combat started", "combat cancellation used the wrong reason")
assert(underlightEquipReasons[#underlightEquipReasons] == "cancelled: combat started",
    "combat cancellation did not request Underlight Angler equip")

Fishing:OnCastStarted()
mounted = false
Fishing:OnMountDisplayChanged()
assert(Fishing.state.current == namespace.Fishing.states.PRECASTING,
    "dismount must not cancel fishing")

mounted = true
Fishing:OnMountDisplayChanged()
assert(Fishing.state.current == namespace.Fishing.states.IDLE,
    "mounting did not cancel fishing")
assert(cancelledFor == "cancelled: mounted", "mount cancellation used the wrong reason")

mounted = false
Fishing:OnMountDisplayChanged()
assert(underlightEquipReasons[#underlightEquipReasons] == "dismounted",
    "dismount did not retry the Underlight Angler equip")

Fishing:OnModuleDisable()

assert(next(registeredEvents) == nil, "disabling Fishing did not unregister its events")
assert(frameRemoved, "disabling Fishing did not remove the secure frame")

local options = Fishing:GetOptionsTable()
assert(options.name == "Fishing", "Fishing options group was not created")
assert(options.childGroups == "tree", "Fishing options must render child groups in the navigation tree")
assert(options.args.modesTab, "Modes tab is missing from the Fishing tab group")
assert(options.args.tackleTab, "Tackle tab is missing from the Fishing tab group")
assert(options.args.modesTab.type == "group", "Modes tab is not an AceConfig group")
assert(options.args.tackleTab.type == "group", "Tackle tab is not an AceConfig group")
assert(options.args.modesTab.args.castingTriggers.args.castBySingleRightClickWhenFishing,
    "single-right-click option is missing")
assert(options.args.tackleTab.args.raftSection == nil,
    "Raft controls should be configured from the DreamFish dialog, not the Fishing options tab")
assert(options.args.tackleTab.args.bobberSection == nil,
    "Bobber controls should be configured from the DreamFish dialog, not the Fishing options tab")

local tackleFadeArgs = options.args.frameFadeTab.args.tackleBoxSection.args.dreamfishDialogWhenFishing.args
assert(tackleFadeArgs.opacityWithMouseover, "opacityWithMouseover option is missing from tackleBoxSection")
assert(tackleFadeArgs.opacityWithMouseover.get() == true, "opacityWithMouseover default value should be true")
tackleFadeArgs.opacityWithMouseover.set(nil, false)
assert(tackleFadeArgs.opacityWithMouseover.get() == false, "opacityWithMouseover should be false after set")
tackleFadeArgs.opacityWithMouseover.set(nil, true)
assert(tackleFadeArgs.opacityWithMouseover.get() == true, "opacityWithMouseover should be true after set")

local lingerExpirationOption = options.args.modesTab.args.lingerExpirationEnabled
local lingerDurationOption = options.args.modesTab.args.lingerDuration
assert(lingerExpirationOption, "lingerExpirationEnabled option is missing from modesTab")
assert(lingerDurationOption, "lingerDuration option is missing from modesTab")
assert(lingerExpirationOption.get() == true, "lingerExpirationEnabled default value should be true")
assert(lingerDurationOption.get() == 10, "lingerDuration default value should be 10")
assert(lingerDurationOption.disabled() == false, "lingerDuration should not be disabled when lingerExpirationEnabled is true")

lingerExpirationOption.set(nil, false)
assert(lingerExpirationOption.get() == false, "lingerExpirationEnabled should be false after set")
assert(lingerDurationOption.disabled() == true, "lingerDuration should be disabled when lingerExpirationEnabled is false")

lingerExpirationOption.set(nil, true)
assert(lingerExpirationOption.get() == true, "lingerExpirationEnabled should be true after set")
assert(lingerDurationOption.disabled() == false, "lingerDuration should not be disabled when lingerExpirationEnabled is true")

-- Test precast linger timer execution
local scheduledTimerCallback = nil
local scheduledTimerDelay = nil
local cancelledTimers = 0
function Fishing:ScheduleTimer(callback, delay)
    scheduledTimerCallback = callback
    scheduledTimerDelay = delay
    return { id = "testTimer" }
end
function Fishing:CancelTimer(timer)
    cancelledTimers = cancelledTimers + 1
end

Fishing.enabled = true
Fishing.db.profile.lingerDuration = 15
Fishing.db.profile.lingerExpirationEnabled = true

Fishing:SetFishingState(namespace.Fishing.states.PRECASTING)
Fishing:StartPrecastLingerTimer()
assert(scheduledTimerDelay == 15, "precast linger timer should use lingerDuration")
assert(type(scheduledTimerCallback) == "function", "precast linger timer callback should be scheduled")

-- Firing callback while in PRECASTING should end fishing session normally
scheduledTimerCallback()
assert(Fishing.state.current == namespace.Fishing.states.IDLE, "precast linger expiration must transition to IDLE")

-- When lingerExpirationEnabled is false, StartPrecastLingerTimer should cancel and not schedule
scheduledTimerCallback = nil
scheduledTimerDelay = nil
Fishing.db.profile.lingerExpirationEnabled = false
Fishing:SetFishingState(namespace.Fishing.states.PRECASTING)
Fishing:StartPrecastLingerTimer()
assert(scheduledTimerCallback == nil, "StartPrecastLingerTimer must not schedule when lingerExpirationEnabled is false")

scheduledTimerCallback = nil
scheduledTimerDelay = nil
cancelledFor = nil
alertMessages = {}
namespace.precast.GetRaftUseDecision = function()
    return { hasToy = true, ready = true, shouldApply = true, blockedByShapeshift = false }
end
local preparedBeforeSwimming = preparedActionCount
Fishing.state.precastStartedSwimming = false
Fishing.state.precastSwimmingAlerted = false
Fishing.state.pendingBuffUse = { uses = { { itemID = 262650, category = "lure" } } }
Fishing.state.precastConsumableSnapshot = { generation = 1, effectSpellIDs = {}, decisionMade = true }
Fishing:SetFishingState(namespace.Fishing.states.PRECASTING)
Fishing:StartPrecastSwimmingWatch()
assert(scheduledTimerDelay == 0.1, "precast swimming watch should poll shortly after PRECAST starts")
assert(type(scheduledTimerCallback) == "function", "precast swimming watch callback should be scheduled")
swimming = true
scheduledTimerCallback()
assert(Fishing.state.current == namespace.Fishing.states.PRECASTING,
    "swimming during PRECAST should keep the session in PRECASTING so raft can be armed")
assert(cancelledFor == nil, "swimming during PRECAST must not cancel the fishing session")
assert(preparedActionCount == preparedBeforeSwimming + 1,
    "swimming during PRECAST should re-run preparation to allow raft arming")
assert(Fishing.state.pendingBuffUse == nil,
    "swimming during PRECAST should clear unexecuted consumable decisions before raft rearm")
assert(Fishing.state.precastConsumableSnapshot == nil,
    "swimming during PRECAST should clear the stale consumable snapshot")
assert(Fishing.state.precastStartedSwimming == true,
    "precast swimming watch should record that swimming has been handled")
assert(alertMessages[1] == "You are swimming. Use the raft to continue fishing.",
    "swimming during PRECAST should alert the player to use the raft before the aura is present")
swimming = false

alertMessages = {}
namespace.precast.GetRaftUseDecision = function()
    return { hasToy = true, ready = true, shouldApply = true, blockedByShapeshift = false }
end
Fishing.state.precastSwimmingAlerted = false
Fishing.state.precastSwimmingGuidanceKind = nil
Fishing:ShowPrecastSwimmingGuidance()
assert(alertMessages[1] == "You are swimming. Use the raft to continue fishing.",
    "swimming guidance should say use the raft when the raft aura is not present yet")
namespace.precast.GetRaftUseDecision = function()
    return { hasToy = true, ready = false, recentlyUsed = true, blockedByShapeshift = false }
end
Fishing:ShowPrecastSwimmingGuidance()
assert(#alertMessages == 1,
    "swimming guidance should not downgrade from use raft to waiting for raft")
namespace.precast.GetRaftUseDecision = function()
    return { hasToy = true, auraRemaining = 30, blockedByShapeshift = false }
end
Fishing:ShowPrecastSwimmingGuidance({ allowClimb = true })
assert(alertMessages[2] == "You are swimming. Climb on the raft to continue fishing.",
    "swimming guidance should upgrade to climb once the raft aura is present")
Fishing:ShowPrecastSwimmingGuidance({ allowClimb = true })
assert(alertMessages[3] == "You are swimming. Climb on the raft to continue fishing.",
    "player attempts while still swimming should repeat climb guidance")

print("fishing_module_test: passed")