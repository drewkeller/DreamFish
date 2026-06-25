# UI changes

Save changes as they are made "live".
Use an "X" button at top right to close the window
Escape key should close the window

The window should remember its position between sessions

# TABS
Focus
	Focused Fishing Audio (checkbox)
	Patient Treasure alert (checkbox)
	Full bag monitor / alert (checkbox)
	Missing item alert (checkbox)
	Audio sliders for adjusting audio when fishing:

Tackle
	Rafts - when swimming or standing on water? or /df raft (Disabled, Anglers Fishing Raft, Tuskarr Dinghy)
	Bobbers - select which toy to use (Disabled, Bat Visage, Can of Worms, Carved Wooden Helm, Cat Head, Demon Noggin, Enchanted Bobber, Face of the Forest, Floating Totem, Replica Gondola, Tugboat, Wooden Pepe)
	Oversized bobber (checkbox) - Apply the toy when other toy bobber is in use (Reusable Oversized Bobber)
Buffs
	Buff items
Modes
	CASTING MODES (select):
	 	Mutually exclusive:
			Right double click
			Single right click (double right click to start. ESC to stop)
				Should also exit for any of the reasons that cause audio ducking to exit
		To be removed:
			Right click with modifier (SHIFT, CTRL, ALT)
		Keyboard hotkey (not currently implemented)
		Single right click (when DF window is open)
	Underlight Angler
		Equip when swimming, unequip when casting (checkbox)


# SLASH COMMANDS
/df help          - Show all commands (or /df h or /df ?)
/df testtreasure  - Test Patient Treasure alert (/df tt)
/df testbagsfull  - Test bags full alert (/df tbf)
/df testaudio     - Test audio ducking with before/after CVars (/df ta)
/df audiostate    - Display current audio ducking state (/df as)
/df duckaudio     - Manually start audio ducking (/df da) 🆕
/df restoreaudio  - Manually restore audio (/df ra)
/df debug         - Toggle debug mode (/df dbg)
/df raft          - Apply the selected raft
/df               - Toggle config UI
