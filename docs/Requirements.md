# Project
Write an addon for World of Warcraft (retail version, currently Midnight expansion patch 12.0.7).
The addon is to provide features related to the game's Fishing profession and offer quality of life enhancements
to the fishing experience.
Name the addon "DreamFish".

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
[x] Provide an alert when a treasure chest is caught
[x] Provide an alert when your bag is low on space (less than 2 slots)
[ ] Show on screen: fishing skill, increase of skill due to buffs, other active buffs related to fishing
[ ] Track current inventory of an item that can be caught
[ ] Track current amount of currency that can be caught while fishing (such as Shard of DundUn)
[ ] Trigger notifications when catching special items (allow player to enter item ids)
    - High attention: Full screen coloration, "treasure" alert sound
    - Medium attention: UI Info message, multiple "dings" or equivalent impact audio
    - Low attention: UI Info message, single "ding"
[ ] Add sliders so the player can configure how much to affect each audio channel when fishing
[x] Allow benefits of Underlight Angler when not fishing (walk on water, fast swimming)
[ ] Add a way for the player to choose additional frames to fade in/out (dropper? open window list?)
  [ ] Enable/disable each frame
  [ ] Set level of fade (alpha) for each frame
[ ] Add compatibility for profile (Buffs tab, especially)
[x] Managed auto-loot (temporarily disable auto-loot) so addon can manage looting
  [x] Auto-loot ignores junk items, i.e. "throw away junk" (so they don't fill up bags)
  [ ] Loot window closing delay
  [ ] Enable loot sounds
[ ] Make the fishing pole slot interactive so a lure can be applied manually to the pole
[ ] Visual focus: Add option to turn off nameplates

* Don't show missing buff items when logging in/changing zones

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

## Hooked Interact Setup
When the optional hooked-interact mode is enabled, users must configure game settings so a secure interact action can resolve the bobber:
    Bind an Interact key in game keybindings.
    Enable game interact/soft-target assistance options.
    Avoid conflicting addons or click-cast setups that override world right-click behavior.
    Enable the DreamFish mode toggle for same-trigger interact while bobber is active.

## Buffs
* Choose an appropriate buff (this section can be boiled down to tracking the auras applied by certain items)
    - some buffs can stack with each other and some should be mutually exclusive
    - don't apply buffs if they don't stack
    - prioritize?

Arcane Lure

## Bait
Bait increases the chance of catching a certain type of fish.
Only one of these auras can be applied at a time. If an aura already exists from a bait item, another bait item will not be applied.

| Bait                      | Item   | Spell  |Time | Expansion           |
|---------------------------|--------|--------|-----|---------------------|
| Aileron Seamoth Lure      | 198401 | 383093 | 30m | Dragonflight        |
| Cerulean Spinefish Lure   | 193896 | 375787 | 30m | Dragonflight        |
| Islefin Dorado Lure       | 198043 | 383095 | 30m | Dragonflight        |
| Scalebelly Mackerel Lure  | 193893 | 375779 | 30m | Dragonflight        |
| Temporal Dragonhead Lure  | 193895 | 375784 | 30m | Dragonflight        |
| Thousandbite Piranha Lure | 193894 | 375781 | 30m | Dragonflight        |
| Lost Sole Bait            | 173038 | 331688 | 30m | Shadowlands         |
| Elysian Thade Bait        | 173043 | 331698 | 30m | Shadowlands         |
| Silvergill Pike Bait      | 173040 | 310665 | 30m | Shadowlands         |
| Pocked Bonefish Bait      | 173041 | 331695 | 30m | Shadowlands         |
| Iridescent Amberjack Bait | 173039 | 331692 | 30m | Shadowlands         |
| Spinefin Piranha Bait     | 173042 | 331699 | 30m | Shadowlands         |
| Abyssal Gulper Eel Bait   | 110293 | 158038 | 10m | Warlords of Draenor |
| Blackwater Whiptail Bait  | 110294 | 158039 | 10m | Warlords of Draenor |
| Blind Lake Sturgeon Bait  | 110290 | 158035 | 10m | Warlords of Draenor |
| Fat Sleeper Bait          | 110289 | 158034 | 10m | Warlords of Draenor |
| Fire Ammonite Bait        | 110291 | 158036 | 10m | Warlords of Draenor |
| Jawless Skulker Bait      | 110274 | 158031 | 10m | Warlords of Draenor |
| Sea Scorpion Bait         | 110292 | 158037 | 10m | Warlords of Draenor |

There are a lot of Legion aura-producing baits to attract special fish. These are mainly related to catching fish for the `Bigger Fish to Fry` achievement (Warbound) or for empowering the `Underlight Angler`. Due to their specific requirements and rarity, the player may wish to handle these manually.
The ones that have lasting effects are 5 minutes (some are instant, acting as a trigger for something).
| Bait                      | Item   | Spell  |Time | Expansion           |
|---------------------------|--------|--------|-----|---------------------|
| Aromatic Murloc Slime     | 133702 | 201805 |  5m | Legion              |
| Pearlescent Conch         | 133703 | 201806 |  5m | Legion              |
| Rusty Queenfish Brooch    | 133704 | 201807 |  5m | Legion              |
| Salmon Lure               | 133710 | 201813 |  5m | Legion              |
| Frost Worm                | 133712 | 201815 |  5m | Legion              |
| Swollen Murloc Egg        | 133711 | 201814 |  5m | Legion              |
| Moosehorn Hook            | 133713 | 201816 |  5m | Legion              |
| Silverscale Minnow        | 133714 | 201817 |  5m | Legion              |
| Ancient Vrykul Ring       | 133715 | 201818 |  5m | Legion              |
| Soggy Drakescale          | 133716 | 201819 |  5m | Legion              |
| Rotten Fishbone           | 133705 | 201808 |  5m | Legion              |
| Nightmare Nightcrawler    | 133707 | 201810 |  5m | Legion              |
| Drowned Thistleleaf       | 133708 | 201811 |  5m | Legion              |
| Demonic Detritus          | 133720 | 201822 |  5m | Legion              |
| Enchanted Lure            | 133717 | 201820 |  5m | Legion              |
| Axefish Lure              | 133722 | 201823 |  5m | Legion              |
| Ravenous Fly              | 133795 | 202131 |  5m | Legion              |


## Lures
Lures add a temporary effect directly to the fishing pole.
Only one lure can be applied to the fishing pole at a time.
| Lure                          | Benefit   | Duration | Item   | Spell  |
| ----------------------------- | --------- | -------- | ------ | ------ |
| Glass Fishing Bobber          | +2 Skill  | 10m      | 67404  | 98849  |
| Shiny Bauble                  | +3 Skill  | 10m      | 6529   | 8087   |
| Nightcrawlers                 | +5 Skill  | 10m      | 6530   | 8088   |
| Aquadynamic Fish Lens         | +5 Skill  | 10m      | 6811   | 8532   |
| Bright Baubles                | +7 Skill  | 10m      | 6532   | 8090   |
| Flesh Eating Worm             | +7 Skill  | 10m      | 7307   | 9092   |
| Aquadynamic Fish Attractor    | +9 Skill  | 10m      | 6533   | 8089   |
| Sharpened Fish Hook           | +9 Skill  | 10m      | 3486   | 45731  |
| Feathered Lure                | +9 Skill  | 10m      | 6267   | 87646  |
| Glow Worm                     | +9 Skill  | 60m      | 4600   | 64401  |
| Heat-Treated Spinning Lure    | +10 Skill | 15m      | 6804   | 95244  |
| Day-Old Darkmoon Doughnut     | +10 Skill | 10m      | 124674 | 185587 |
| Worm Supreme                  | +10 Skill | 10m      | 118391 | 174471 |


## Bobber Selection
A bobber can be selected from a list. The first item on the list is not an actual item, but is the "Standard Bobber" in the game, which is what you get if you aren't applying a bobber. The rest of the list is dynamically created, based on what "Crate of Bobber" toys the player owns. The Reusable Oversized Bobber toy can be applied to any bobber, including the standard one, so applying the oversized bobber is offered as a separate option.


## Loot sound effects
The Core LootingSounds
* Gold / Coins: Triggers the iconic cha-ching jingle.
    SoundKit ID: 120 (Internal Constant: SOUNDKIT.LOOT_WINDOW_COIN_SOUND)
    File Path: sound/interface/lootwindowcoins.ogg
* Standard Items (Gear/Trash/Mats): Triggers a soft, leather-like sliding rustle.
    SoundKit ID: 118
    File Path: sound/interface/lootwindowopen.ogg
Specialized Looting & Collection Sounds
* Quest Item Pickup: A heavy metallic thud when gathering a physical object needed for a quest.
    SoundKit ID: 5115
* Transmog / Appearance Learned: A booming, magical echoing chime.
    SoundKit ID: 72097
* Toy Learned: A whimsical, magical popping sound.
    SoundKit ID: 65225
* Mount Learned: A triumphant horn blast.
    SoundKit ID: 43472
* Pet Learned: A short, upbeat magical twinkle.
    SoundKit ID: 39515
Mute:   /run MuteSoundFile(569593) MuteSoundFile(567431) print("Loot sounds suppressed!")
Unmute: /run UnmuteSoundFile(569593) UnmuteSoundFile(567431) print("Loot sounds restored!")