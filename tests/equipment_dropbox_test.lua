local noop = function() end
local frames = {}
local constructor
local equippedItemID = 1001
local bag, bagSlot
local targeting = false
local inCombat = false
local cursorItemID
local clearedCursor = false
local menuCount = 0
local pickupCount = 0
local combatDriverFrame

local function CreateRegion()
    return setmetatable({}, { __index = function() return noop end })
end

function CreateFrame(frameType, name, parent, template)
    local frame = { scripts = {}, attributes = {}, events = {}, template = template }
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:SetAttribute(key, value)
        assert(not inCombat, "secure target attributes must not change in combat")
        self.attributes[key] = value
    end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:GetFrameLevel() return 1 end
    frame.CreateTexture = CreateRegion
    frame.CreateFontString = CreateRegion
    setmetatable(frame, { __index = function() return noop end })
    table.insert(frames, frame)
    return frame
end

local aceGUI = {
    RegisterWidgetType = function(_, name, callback, version)
        assert(name == "DreamFishEquipmentPreview" and version == 3)
        constructor = callback
    end,
    RegisterAsWidget = function() end,
}
function LibStub() return aceGUI end
function GetInventoryItemID(...) return equippedItemID end
function InCombatLockdown() return inCombat end
function RegisterStateDriver(frame, state, condition)
    assert(state == "combat" and condition == "[combat] combat; nocombat")
    combatDriverFrame = frame
end
function SpellIsTargeting() return targeting end
function GetCursorInfo()
    if cursorItemID then return "item", cursorItemID end
end
function ClearCursor() clearedCursor = true; cursorItemID = nil end
function IsShiftKeyDown() return true end
function UIDropDownMenu_Initialize(...) end
function ToggleDropDownMenu(...) menuCount = menuCount + 1 end
C_Item = {
    GetItemIconByID = function() return 1 end,
    PickupItem = function() pickupCount = pickupCount + 1 end,
}
local namespace = {
    Addon = { Debug = noop },
    Utils = { FindItemInBags = function() return bag, bagSlot end },
}
assert(loadfile("ui/equipmentDropBox.lua"))("DreamFish", namespace)
local widget = constructor()
local button = frames[2]
local eventFrame = frames[4]
assert(button.template:find("SecureActionButtonTemplate", 1, true))
assert(button.attributes.useOnKeyDown == false, "targeting must execute on release")
widget:SetText("1001")
widget:SetList({})
assert(button.attributes["*target-slot1"] == 28 and button.attributes["*target-bag1"] == nil,
    "equipped pole must target its inventory slot")
assert(button.attributes.type == nil and button.attributes.type1 == nil,
    "button must not have an item-use or equip action")

targeting = true
button.scripts.OnMouseUp(button, "LeftButton")
assert(menuCount == 0 and widget.itemID == 1001, "lure targeting must not open the menu")
cursorItemID = 9999
button.scripts.OnReceiveDrag()
button.scripts.OnDragStart()
button.scripts.OnMouseUp(button, "RightButton")
assert(widget.itemID == 1001 and not clearedCursor and pickupCount == 0,
    "targeting must not assign, remove, clear the cursor, or drag the pole")
cursorItemID = nil

equippedItemID = 2002
bag, bagSlot = 0, 5
eventFrame.scripts.OnEvent(eventFrame, "BAG_UPDATE_DELAYED")
assert(button.attributes["*target-bag1"] == 0 and button.attributes["*target-slot1"] == 5,
    "bagged pole must target its physical bag location, including backpack bag zero")
bagSlot = 6
button.scripts.PreClick(button, "LeftButton")
assert(button.attributes["*target-slot1"] == 6, "click must refresh moved bag items")
bag, bagSlot = nil, nil
eventFrame.scripts.OnEvent(eventFrame, "BAG_UPDATE_DELAYED")
assert(button.attributes["*target-slot1"] == nil and button.attributes["*target-bag1"] == nil,
    "missing poles must not retain a target for another item")

equippedItemID = 1001
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_EQUIPMENT_CHANGED", 28)
inCombat = true
local compileSnippet = loadstring or rawget(_G, "load")
local combatSnippet = assert(compileSnippet("return function(self, newstate) "
    .. button.attributes["_onstate-combat"] .. " end"))()
combatSnippet({ SetAttribute = function(_, key, value) button.attributes[key] = value end }, "combat")
assert(combatDriverFrame == button and button.attributes["*target-slot1"] == nil
    and button.attributes["*target-bag1"] == nil,
    "combat must securely disable stale bag targets")
eventFrame.scripts.OnEvent(eventFrame, "BAG_UPDATE_DELAYED")
button.scripts.PreClick(button, "LeftButton")
inCombat = false
equippedItemID = 0
bag, bagSlot = 1, 3
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(button.attributes["*target-bag1"] == 1 and button.attributes["*target-slot1"] == 3,
    "target location must refresh after combat")

targeting = false
button.scripts.OnMouseUp(button, "LeftButton")
assert(menuCount == 1, "normal clicks must still open the menu")
cursorItemID = 2002
button.scripts.OnMouseUp(button, "LeftButton")
assert(widget.itemID == 2002 and clearedCursor, "normal cursor assignment must still work")
button.scripts.OnMouseUp(button, "RightButton")
assert(widget.itemID == nil, "shift-right-click must still clear the assignment")
widget:SetText("1001")
widget:OnRelease()
assert(button.attributes["*target-slot1"] == nil and button.attributes["*target-bag1"] == nil,
    "released pooled widgets must not retain targeting attributes")
assert(not eventFrame.events.BAG_UPDATE_DELAYED and not eventFrame.events.PLAYER_REGEN_ENABLED)
widget:OnAcquire()
assert(eventFrame.events.BAG_UPDATE_DELAYED and eventFrame.events.PLAYER_REGEN_ENABLED)
print("equipment_dropbox_test: passed")