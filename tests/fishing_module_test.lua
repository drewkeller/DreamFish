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
local notifiedConfigTables = {}
local rightClickStrikeBinding
local nativeRightClickStrikeBinding
local modifiedRightClickBindings = {}

local DreamFish = {
    db = {
        profile = {
            debugMode = false,
            fishing = {
                moduleEnabled = true,
                debug = false,
                castBySingleRightClickWhenFishing = false,
                strikeByRightClick = false,
                strikeByDoubleRightClick = true,
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
    if name == "AceConfigRegistry-3.0" then
        return {
            NotifyChange = function(_, appName)
                table.insert(notifiedConfigTables, appName)
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

function SetOverrideBinding(owner, priority, key, command)
    if key == "BUTTON2" then
        nativeRightClickStrikeBinding = {
            owner = owner,
            priority = priority,
            key = key,
            command = command,
        }
    elseif key and key:find("BUTTON2", 1, true) then
        modifiedRightClickBindings[key] = {
            owner = owner,
            command = command,
        }
    end
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

function SetOverrideBindingClick(owner, priority, key, frameName, mouseButton)
    if key == "BUTTON2" then
        rightClickStrikeBinding = {
            owner = owner,
            priority = priority,
            key = key,
            frameName = frameName,
            mouseButton = mouseButton,
        }
    end
end

function InCombatLockdown()
    return false
end

function ClearOverrideBindings(owner)
    if nativeRightClickStrikeBinding and nativeRightClickStrikeBinding.owner == owner then
        nativeRightClickStrikeBinding = nil
    end
    for key, binding in pairs(modifiedRightClickBindings) do
        if binding.owner == owner then
            modifiedRightClickBindings[key] = nil
        end
    end
    if rightClickStrikeBinding and rightClickStrikeBinding.owner == owner then
        rightClickStrikeBinding = nil
    end
end

function IsMounted()
    return mounted
end

function IsSwimmingOrSubmerged()
    return swimming
end

function GetTime()
    return 100
end

namespace.Utils.IsSwimmingOrSubmerged = IsSwimmingOrSubmerged

Fishing:OnInitialize()
Fishing:OnEnable()

assert(Fishing.config.displayName == "Fishing", "display name was not configured")
assert(Fishing.config.dbKey == "fishing", "database key was not configured")
assert(Fishing.enabled, "Fishing did not use its saved enabled state")
assert(frameCreated, "enabling Fishing did not create the secure frame")
assert(registeredEvents.PLAYER_REGEN_ENABLED, "enabling Fishing did not register its combat event")
assert(registeredEvents.PLAYER_EQUIPMENT_CHANGED, "enabling Fishing did not register its equipment refresh event")
assert(registeredEvents.BAG_UPDATE_DELAYED, "enabling Fishing did not register its bag refresh event")
assert(registeredEvents.UNIT_AURA, "enabling Fishing did not register its aura refresh event")
assert(registeredEvents.UNIT_SPELLCAST_START, "enabling Fishing did not register its spellcast start event")
assert(registeredEvents.UNIT_SPELLCAST_SUCCEEDED, "enabling Fishing did not register its spellcast success event")
assert(registeredEvents.PLAYER_MOUNT_DISPLAY_CHANGED, "enabling Fishing did not register its mount event")
assert(bindingsApplied, "enabling Fishing did not apply its keybinding")
assert(preparedActionCount == 0, "enabling Fishing must not prepare a cast action before a fishing session starts")

Fishing:OnBagUpdateDelayed()
assert(notifiedConfigTables[#notifiedConfigTables] == "DreamFishDialog",
    "bag changes must refresh the tackle dialog's pole controls")

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
rightClickStrikeBinding = nil
nativeRightClickStrikeBinding = nil
Fishing:ArmRightClickStrike()
assert(not rightClickStrikeBinding and not nativeRightClickStrikeBinding,
    "double-right-click-only mode must preserve the native right-click binding")
Fishing:UseNativeRightClickStrike()
assert(nativeRightClickStrikeBinding and nativeRightClickStrikeBinding.command == "INTERACTTARGET",
    "double-right-click mode must create an owner to arm native interaction for the second click")
Fishing:ArmRightClickStrike()
assert(not nativeRightClickStrikeBinding,
    "double-right-click mode must remove the temporary interaction override")
Fishing.db.profile.strikeByRightClick = true
Fishing:ArmRightClickStrike()
assert(nativeRightClickStrikeBinding and nativeRightClickStrikeBinding.command == "INTERACTTARGET",
    "single-right-click strike must use the native INTERACTTARGET binding")
for _, key in ipairs({ "SHIFT-BUTTON2", "CTRL-BUTTON2", "ALT-BUTTON2", "CTRL-SHIFT-BUTTON2",
    "CTRL-ALT-BUTTON2", "SHIFT-ALT-BUTTON2", "CTRL-SHIFT-ALT-BUTTON2" }) do
    assert(modifiedRightClickBindings[key] and modifiedRightClickBindings[key].command == "TURNORACTION",
        key .. " must pass through to the native turn/action behavior")
end
Fishing.db.profile.strikeByRightClick = false
Fishing:ArmRightClickStrike()
assert(not nativeRightClickStrikeBinding,
    "double-right-click strike must clear the native interaction override")
Fishing:OnEquipmentChanged(nil, FISHINGTOOLSLOT)
assert(preparedActionCount == 2, "refresh while waiting for a bite must not reconfigure the secure action")
local cancelledFor
local setFishingState = Fishing.SetFishingState
function Fishing:SetFishingState(state, reason)
    cancelledFor = reason
    return setFishingState(self, state, reason)
end

Fishing:OnCastStarted()
Fishing:OnCombatStarted()
assert(cancelledFor == "cancelled: combat started", "combat cancellation used the wrong reason")

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

local sessionExitOptions = options.args.modesTab.args.sessionExits.args
local strikeOptions = options.args.modesTab.args.triggers.args.reelingTriggers.args
strikeOptions.strikeByRightClick.set(nil, true)
assert(Fishing.db.profile.strikeByRightClick and not Fishing.db.profile.strikeByDoubleRightClick,
    "enabling single-click strike must disable double-click strike")
strikeOptions.strikeByDoubleRightClick.set(nil, true)
assert(Fishing.db.profile.strikeByDoubleRightClick and not Fishing.db.profile.strikeByRightClick,
    "enabling double-click strike must disable single-click strike")

local lingerExpirationOption = sessionExitOptions.lingerExpirationEnabled
local lingerDurationOption = sessionExitOptions.lingerDuration
assert(lingerExpirationOption, "lingerExpirationEnabled option is missing from sessionExits")
assert(lingerDurationOption, "lingerDuration option is missing from sessionExits")
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

-- A delayed stop from a previous cast must not linger a newer cast.
Fishing.state.castAttempt = 41
Fishing:SetFishingState(namespace.Fishing.states.WAITING_FOR_BITE)
Fishing:OnSpellcastChannelEnded(nil, "player", "previous-cast-guid", namespace.Fishing.const.fishingSpellID)
local staleChannelStopCallback = scheduledTimerCallback
assert(type(staleChannelStopCallback) == "function", "channel stop should defer linger while waiting for loot")
Fishing:OnCastStarted("recast before delayed cleanup")
Fishing:OnSpellcastChannelStarted(nil, "player", "new-cast-guid", namespace.Fishing.const.fishingSpellID)
staleChannelStopCallback()
assert(Fishing.state.current == namespace.Fishing.states.WAITING_FOR_BITE,
    "a delayed channel stop from the previous cast must not end a newer cast")

Fishing.enabled = true
Fishing.db.profile.lingerDuration = 15
Fishing.db.profile.lingerExpirationEnabled = true

Fishing:SetFishingState(namespace.Fishing.states.PRECASTING)
Fishing:RefreshPrecastLingerTimer()
assert(scheduledTimerDelay == 3, "precast fallback timer should start with a three-second delay")
assert(type(scheduledTimerCallback) == "function", "precast linger timer callback should be scheduled")

-- Firing the fallback while in PRECASTING should enter LINGERING.
scheduledTimerCallback()
assert(Fishing.state.current == namespace.Fishing.states.LINGERING,
    "precast fallback expiration must transition to LINGERING")

-- The fallback remains active even when LINGERING expiration is disabled.
scheduledTimerCallback = nil
scheduledTimerDelay = nil
Fishing.db.profile.lingerExpirationEnabled = false
Fishing:SetFishingState(namespace.Fishing.states.PRECASTING)
Fishing:RefreshPrecastLingerTimer(3)
assert(scheduledTimerDelay == 3, "precast fallback should not depend on linger expiration settings")

namespace.Fishing.const.knownBuffItems = { [180993] = { castTime = 1500 } }
Fishing.state.precastArmedItemIDs = { 180993 }
Fishing.state.precastItemSpellStarted = {}
C_Item = { GetItemSpell = function() return 12345 end }
Fishing:OnSpellCastStarted("UNIT_SPELLCAST_START", "player", nil, 12345)
assert(scheduledTimerDelay == 4.5,
    "using an armed item should add its cast time to the three-second fallback")

local cancelledForNoCast = nil
local originalCancelFishingSession = Fishing.CancelFishingSession
Fishing.CancelFishingSession = function(_, reason)
    cancelledForNoCast = reason
end
Fishing.state.current = namespace.Fishing.states.PRECASTING
Fishing.state.castAttempt = 17
Fishing.state.castStartConfirmationAttempt = nil
Fishing.state.pendingBuffUse = nil
Fishing.state.isEquippingPrimaryPole = false
Fishing.state.lingerTimer = { id = "precastFallback" }
Fishing:AwaitFishingCastStart()
assert(type(scheduledTimerCallback) == "function",
    "cast-start confirmation timer should be scheduled")
scheduledTimerCallback()
assert(cancelledForNoCast == nil,
    "cast-start confirmation must defer to the active PRECAST fallback timer")
Fishing.CancelFishingSession = originalCancelFishingSession
Fishing.state.lingerTimer = nil

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
Fishing.state.precastSwimmingGuidanceKind = nil
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
assert(alertMessages[1] == "Cast again for a raft.",
    "swimming during PRECAST should alert the player to use the raft before the aura is present")
swimming = false
scheduledTimerCallback()
assert(preparedActionCount == preparedBeforeSwimming + 2,
    "leaving swimming during PRECAST should re-arm the fishing action")
assert(Fishing.state.precastStartedSwimming == false,
    "precast swimming watch should record that the player climbed out of the water")
assert(type(scheduledTimerCallback) == "function" and scheduledTimerDelay == 0.1,
    "precast swimming watch should keep polling until PRECAST ends")

alertMessages = {}
namespace.precast.GetRaftUseDecision = function()
    return { hasToy = true, ready = true, shouldApply = true, blockedByShapeshift = false }
end
Fishing.state.precastSwimmingAlerted = false
Fishing.state.precastSwimmingGuidanceKind = nil
Fishing:ShowPrecastSwimmingGuidance()
assert(alertMessages[1] == "Cast again for a raft.",
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
assert(alertMessages[2] == "Jump to board the raft and continue fishing.",
    "swimming guidance should upgrade to climb once the raft aura is present")
Fishing:ShowPrecastSwimmingGuidance({ allowClimb = true })
assert(alertMessages[3] == "Jump to board the raft and continue fishing.",
    "player attempts while still swimming should repeat climb guidance")

print("fishing_module_test: passed")