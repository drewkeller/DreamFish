# UI changes

Save changes as they are made "live" instead of saving when closing the window.
Change the "Save & Close" to "Close"
Remove the "X" button to close the window
Escape key should close the window

The window should remember its position between sessions

# TABS
Focus
	Focused Fishing Audio (checkbox)
	Patient Treasure alert (checkbox)
	Full bag monitor / alert (checkbox)
	Missing item alert (checkbox)
Tackle
	Rafts - when swimming or standing on water? or /df raft (Disabled, Anglers Fishing Raft, Tuskarr Dinghy)
	Bobbers - select which toy to use (Disabled, Bat Visage, Can of Worms, Carved Wooden Helm, Cat Head, Demon Noggin, Enchanted Bobber, Face of the Forest, Floating Totem, Replica Gondola, Tugboat, Wooden Pepe)
	Oversized bobber (checkbox) - Apply the toy when other toy bobber is in use (Reusable Oversized Bobber)
Buffs
	Buff items
Modes
	CASTING MODES (select):
		Right double click
		Right click with modifier
		Keyboard hotkey
		Single right click (double right click to start. ESC to stop)
			Should also exit for any of the reasons that cause audio ducking to exit
		Single right click (when DF window is open)
	Underlight Angler
		Equip when swimming, unequip when casting (checkbox)


# SLASH COMMANDS

Base commands:
	/df or /dreamfisher — Opens the configuration UI

Test/Debug commands:
(add) help - Show the list of commands
	testtreasure or tt — Test Patient Treasure alert
	testbagsfull or tbf — Test bags full alert
(remove)	testsound or ts — Test treasure alert audio
	testaudio or ta — Test audio focus (shows volume levels before and after audio ducking)
	audiostate or as — Show current audio state (ducking status, fishing flags, volume levels)
(add) duckaudio or da - Manually start audio ducking levels
	restoreaudio or ra — Manually restore audio to original levels
	debug or dbg — Toggle debug mode ON/OFF

Configuration commands:
	modifier <ALT|CTRL|SHIFT|NONE> — Set which modifier key is required for world right-click actions (default: NONE)
