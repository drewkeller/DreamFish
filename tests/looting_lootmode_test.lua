local autoLootDefault = "1"
local setCVarCalls = {}
local scheduledCallbacks = {}
local lootSlots = {}
local lootedNames = {}
local closeLootCalls = 0
local warnings = {}
local registeredEvents = {}
local frameEventHandler
local messageHandlers = {}
local unregisteredMessages = {}
local initializeCallback
local enableCallback
local disableCallback

local function setLootSlots(items)
    lootSlots = items
    lootedNames = {}
    closeLootCalls = 0
end

local function assertEquals(actual, expected, message)
    assert(actual == expected, message .. "; expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function assertTableEquals(actual, expected, message)
    assert(#actual == #expected, message .. "; wrong item count")
    for index, value in ipairs(expected) do
        assertEquals(actual[index], value, message .. "; wrong value at index " .. tostring(index))
    end
end

local function item(name, quality, locked)
    return {
        name = name,
        quality = quality,
        locked = locked or false,
        itemLink = "|Hitem:12345:0:0:0|h[" .. name .. "]|h",
    }
end

local LootTracker = {
    db = {
        profile = {
            lootModeWhenFishing = { lootMode = "none", ignoreJunk = false, stayOpenForJunk = true },
            lootModeWhenOther = { lootMode = "none", ignoreJunk = false, stayOpenForJunk = true },
            lootDelay = 0,
        },
    },
}

function LootTracker:RegisterTraceSource()
end

function LootTracker:Trace()
end

function LootTracker:RegisterOnModuleInitialize(callback)
    initializeCallback = callback
end

function LootTracker:RegisterOnModuleEnable(callback)
    enableCallback = callback
end

function LootTracker:RegisterOnModuleDisable(callback)
    disableCallback = callback
end

local Addon = {}

function Addon:GetModule(name)
    assert(name == "LootTracker", "unexpected module: " .. tostring(name))
    return LootTracker
end

function Addon:Trace()
end

function Addon:Warning(_, message)
    table.insert(warnings, message)
end

function Addon:RegisterMessage(message, handler)
    messageHandlers[message] = handler
end

function Addon:UnregisterMessage(message)
    unregisteredMessages[message] = true
end

function GetCVar(name)
    assert(name == "autoLootDefault")
    return autoLootDefault
end

function SetCVar(name, value)
    assert(name == "autoLootDefault")
    autoLootDefault = value
    table.insert(setCVarCalls, value)
end

function CreateFrame()
    local frame = {}

    function frame:RegisterEvent(event)
        registeredEvents[event] = true
    end

    function frame:SetScript(script, callback)
        assert(script == "OnEvent")
        frameEventHandler = callback
    end

    return frame
end

C_Timer = {
    After = function(delay, callback)
        table.insert(scheduledCallbacks, { delay = delay, callback = callback })
    end,
}

function GetNumLootItems()
    local count = 0
    for _, loot in ipairs(lootSlots) do
        if not loot.cleared then
            count = count + 1
        end
    end
    return count
end

function GetLootSlotInfo(slot)
    local loot = lootSlots[slot]
    if not loot or loot.cleared then
        return nil
    end
    return "icon", loot.name, 1, nil, loot.quality, loot.locked, false, nil, false, false
end

function GetLootSlotLink(slot)
    local loot = lootSlots[slot]
    return loot and not loot.cleared and loot.itemLink or nil
end

-- Live clients do not shrink the loot window synchronously: LootSlot only sends the request
-- and the slot stays occupied until the server confirms. Model that by marking the slot
-- cleared instead of removing it, so slots never shift during a loot pass.
function LootSlot(slot)
    local loot = assert(lootSlots[slot], "attempted to loot an unavailable slot")
    assert(not loot.cleared, "attempted to loot an already-looted slot")
    table.insert(lootedNames, loot.name)
    loot.cleared = true
end

function CloseLoot()
    closeLootCalls = closeLootCalls + 1
end

local namespace = {
    Addon = Addon,
    LootTracker = LootTracker,
}

namespace.LootTracker.const = {
    LootModes = {
        { id = "none", value = 1 },
        { id = "manual", value = 2 },
        { id = "native", value = 3 },
        { id = "managed", value = 4 },
    },
}

assert(loadfile("looting/lootmode.lua"))("DreamFish", namespace)
assert(initializeCallback, "loot mode initializer was not registered")
assert(enableCallback, "loot mode enable callback was not registered")
assert(disableCallback, "loot mode disable callback was not registered")

initializeCallback(LootTracker)
enableCallback(LootTracker)

assert(registeredEvents.LOOT_READY, "LOOT_READY was not registered")
assert(registeredEvents.LOOT_CLOSED, "LOOT_CLOSED was not registered")
assert(frameEventHandler, "loot frame event handler was not registered")

local function sendFishingMessage(message)
    local handler = assert(messageHandlers[message], "missing message handler for " .. message)
    handler(LootTracker)
end

local function fireLootReady()
    frameEventHandler(nil, "LOOT_READY")
end

local function fireLootClosed()
    frameEventHandler(nil, "LOOT_CLOSED")
end

local function runScheduledCallback(index)
    local scheduled = assert(scheduledCallbacks[index], "missing scheduled callback")
    scheduled.callback()
end

autoLootDefault = "0"
LootTracker.db.profile.lootModeWhenOther.lootMode = "none"
LootTracker.db.profile.lootModeWhenFishing.lootMode = "none"
sendFishingMessage("FISHING_SESSION_STARTED")
assertEquals(autoLootDefault, "0", "none fishing mode must preserve the current native setting")
sendFishingMessage("FISHING_SESSION_ENDED")
assertEquals(autoLootDefault, "0", "none non-fishing mode must preserve the current native setting")

autoLootDefault = "1"
LootTracker.db.profile.lootModeWhenOther.lootMode = "none"
LootTracker.db.profile.lootModeWhenFishing.lootMode = "manual"
sendFishingMessage("FISHING_SESSION_STARTED")
assertEquals(autoLootDefault, "0", "manual fishing mode must disable native auto-loot")
sendFishingMessage("FISHING_SESSION_ENDED")
assertEquals(autoLootDefault, "1", "exiting an override for none must restore the saved native setting")

LootTracker.db.profile.lootModeWhenFishing.lootMode = "native"
sendFishingMessage("FISHING_SESSION_STARTED")
assertEquals(autoLootDefault, "1", "native fishing mode must enable native auto-loot")
sendFishingMessage("FISHING_SESSION_ENDED")

LootTracker.db.profile.lootModeWhenFishing.lootMode = "managed"
sendFishingMessage("FISHING_SESSION_STARTED")
assertEquals(autoLootDefault, "0", "managed fishing mode must disable native auto-loot")
sendFishingMessage("FISHING_SESSION_ENDED")
assertEquals(autoLootDefault, "1", "exiting managed mode must restore the saved native setting")

LootTracker.db.profile.lootModeWhenOther.lootMode = "managed"
LootTracker.db.profile.lootModeWhenOther.ignoreJunk = false
LootTracker.db.profile.lootModeWhenOther.stayOpenForJunk = true
LootTracker.db.profile.lootDelay = 0
setLootSlots({ item("First", 1), item("Second", 2) })
fireLootReady()
assertTableEquals(lootedNames, { "First", "Second" }, "managed loot must follow displayed item order")
assertEquals(GetNumLootItems(), 0, "managed loot must clear every slot")
assertEquals(closeLootCalls, 1, "fully looted windows must close")
fireLootClosed()

LootTracker.db.profile.lootModeWhenOther.ignoreJunk = true
LootTracker.db.profile.lootModeWhenOther.stayOpenForJunk = true
setLootSlots({ item("Junk", 0), item("Valuable", 2) })
fireLootReady()
assertTableEquals(lootedNames, { "Valuable" }, "managed mode must loot valuable items after retained junk")
assertEquals(lootSlots[1].name, "Junk", "ignored junk must remain in the loot window")
assertEquals(closeLootCalls, 0, "managed mode must keep a junk-containing window open when configured")
fireLootClosed()

LootTracker.db.profile.lootModeWhenOther.stayOpenForJunk = false
setLootSlots({ item("Junk", 0) })
fireLootReady()
assertEquals(closeLootCalls, 1, "managed mode must close a junk-containing window when configured")
fireLootClosed()

LootTracker.db.profile.lootModeWhenOther.ignoreJunk = false
setLootSlots({ item("Junk", 0) })
fireLootReady()
assertTableEquals(lootedNames, { "Junk" }, "managed mode must loot junk when junk skipping is disabled")
fireLootClosed()

LootTracker.db.profile.lootModeWhenOther.ignoreJunk = false
setLootSlots({ item("Locked", 2, true) })
fireLootReady()
assertEquals(#lootedNames, 0, "managed mode must not loot locked items")
assertEquals(closeLootCalls, 0, "managed mode must keep a locked-item window open")
fireLootClosed()

LootTracker.db.profile.lootDelay = 150
setLootSlots({ item("Delayed", 2) })
fireLootReady()
local scheduledIndex = #scheduledCallbacks
assertEquals(scheduledCallbacks[scheduledIndex].delay, 0.15, "loot delay must convert milliseconds to seconds")
assertEquals(#lootedNames, 0, "delayed loot must not run immediately")
runScheduledCallback(scheduledIndex)
assertTableEquals(lootedNames, { "Delayed" }, "delayed managed loot must run after its timer")
fireLootClosed()

-- The client fires LOOT_READY and LOOT_CLOSED multiple times for a single loot window;
-- the duplicate events must be ignored instead of handling the same window again.
LootTracker.db.profile.lootDelay = 0
setLootSlots({ item("Duplicated", 2) })
fireLootReady()
assertTableEquals(lootedNames, { "Duplicated" }, "first LOOT_READY must loot the window")
assertEquals(closeLootCalls, 1, "first LOOT_READY must close the window")
table.insert(lootSlots, item("Sneaky", 2))
fireLootReady()
assertTableEquals(lootedNames, { "Duplicated" }, "duplicate LOOT_READY must not handle the window again")
assertEquals(closeLootCalls, 1, "duplicate LOOT_READY must not close the window again")
fireLootClosed()
fireLootClosed()

setLootSlots({ item("NextWindow", 2) })
fireLootReady()
assertTableEquals(lootedNames, { "NextWindow" }, "LOOT_READY after LOOT_CLOSED must be handled normally")
fireLootClosed()

LootTracker.db.profile.lootModeWhenOther.lootMode = "none"
setLootSlots({ item("Unmanaged", 2) })
local scheduledCount = #scheduledCallbacks
fireLootReady()
assertEquals(#lootedNames, 0, "non-managed modes must not handle loot")
assertEquals(#scheduledCallbacks, scheduledCount, "non-managed modes must not schedule loot")

disableCallback(LootTracker)
assert(unregisteredMessages.FISHING_SESSION_STARTED, "disable must unregister the fishing-start message")
assert(unregisteredMessages.FISHING_SESSION_ENDED, "disable must unregister the fishing-end message")
assertEquals(autoLootDefault, "1", "disable must restore the saved native auto-loot setting")

print("looting_lootmode_test: passed")