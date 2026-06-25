# Project
Write an addon for World of Warcraft (retail version, currently Midnight expansion patch 12.0.7).
The addon is to provide features related to the game's Fishing profession and offer quality of life enhancements
to the fishing experience.
Name the addon "DreamFisher".

# Core Features
* Right double click to cast
* Click bobber to loot
* Auto-loot while fishing. Restore previous auto-loot setting when done fishing.
* Enhance the sound of catching a fish
* Suppress sounds of catches from other players
* Automatically use items that provide fishing buffs, such as Hollow Grouper fish for a skill buff or Root Crabs which for a perception buff, in order to keep the buff active.
    - Per-item buff duration tracking from real aura data:
        When a buff item is used, the addon snapshots helpful auras and watches UNIT_AURA.
        If a new/refreshed aura is detected, it stores item -> aura spell mapping and observed duration.
        Future refresh checks use actual remaining aura time when available; otherwise they fall back to that item’s configured refresh seconds.
    - Runtime refresh behavior while fishing:
        Fishing OnUpdate runs buff refresh checks on a throttle.
        Uses one item at a time, tracks last use per item, and avoids casting conflicts.

## Future Core Features
* Provide an alert when a treasure chest is caught
* Provide an alert when your bag is low on space (less than 2 slots)
* Show on screen: fishing skill, increase of skill due to buffs, other active buffs related to fishing
* Track current inventory of an item that can be caught
* Track current amount of currency that can be caught while fishing (such as Shard of DundUn)

# UI Features
The addon provies an interface window with the following features.
* Checkbox to enable the temporary autoloot feature (enabled by default)
* Checkbox to enable enhanced "fish hooked" sound (enabled by default)
* Checkbox to enable treasure chest alert (enabled by default)
* Two boxes (24x24 pixels) for setting buff items. They are set by dragging and dropping an item from the bag.
* An entry box for each buff item to set a time (seconds) to throw the item in the water and refresh the buff (don't need this if the buff time can be determined from the item)
* An entry box to set the number of slots for the low bag space warning


# Feature Details

## Fishing mode
Fishing mode can be started by the following methods:
    (checkbox) Double right click
    (checkbox) "Fishing Mode" Hotkey (special "hotkey entry" box and label)
    (checkbox) DreamFishing window open
    (button)   "Start fishing mode" (when fishing mode is active, says "Stop fishing mode")
    (command)  /df start
When entering fishing mode
    Duck audio
    (optionally) Open fishing mode "window" (a non-intrusive window)

While fishing mode is active:
    Casting is initiated by single right click or a hotkey (not mutually exclusive)
    Looting is accoomplished by single right click or the same hotkey
    The normal casting logic still applies (check for raft, bobber, buffs)
    The normal alerts logic still applies (full bags, treasure, etc)
    (?) Show light blue, higly transparent screen background

Fishing mode is cancelled by:
    Combat
    Movement (to be tested, maybe we can continue fishing mode through movement)
    "Fishing Mode" hotkey (if hotkey is enabled)
    Closing DreamFishing window (if enabled)
    Clicking the "Stop fishing mode" button
    Pressing Escape key
    /df stop

When exiting fishing mode
    Restore audio levels

## Casting modes (outside of Fishing mode)
Initiating a cast can be done by any of the following
    (checkbox) Double right click
    (checkbox) Single right click (when DreamFishing window is open)
    (checkbox) "Cast" hotkey special "hotkey entry" box and label)

## Buffs
* Choose an appropriate buff
    - some buffs can stack with each other and some should be mutually exclusive
    - don't apply buffs if they don't stack
    - prioritize?

