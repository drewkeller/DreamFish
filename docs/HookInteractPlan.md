## Plan: Hook Interact Small-Code Spike

Plan generation: approx 60 credits
Plan implementation: approx 30 credits
Overcoming technical issues in game to get it to work: 349 credits over 20 debugging iterations (17.5 credits per attempt)
This was done in a feature branch in order to limit the area being worked on.

Implement an opt-in hooked-fish interact mode with minimal touch points: add a small isolated interact module, branch once in cast action configuration, and add a user Setup section that documents required in-game soft-target/interact settings.

**Steps**
1. Phase 1: Baseline and scope lock
2. Confirm secure cast path and bobber state lifecycle are stable in current branch and keep default behavior unchanged.
3. Lock scope: when feature flag is enabled and bobber-active state is true, configure interact action instead of cast action.
4. Phase 2: Isolated module
5. Add fishing/interactloot.lua to own only hooked-loot gating and secure-frame interact action setup.
6. Export minimal API through addon.fishing for the cast module to call. Parallel with Step 7.
7. Add default feature flag in core/init.lua with safe default false. Parallel with Step 6.
8. Register new module in DreamFisher.toc in deterministic load order. Depends on Step 5.
9. Phase 3: Minimal integration
10. Add one early guarded branch in fishing/casting.lua inside ConfigureFishingClickAction to delegate to interact setup and return.
11. Leave all non-hooked cast, buff, and timing logic unchanged.
12. Phase 4: UI and discoverability
13. Add a toggle in ui/config.lua for hooked-loot interact mode.
14. Add brief discoverability text in ui/commands.lua if needed.
15. Phase 4b: Setup documentation
16. Add a Setup section explaining required game settings: interact key bind, soft-target/interact enabled, and likely right-click conflict sources.
17. Mirror a short setup checklist in user-facing help text so misconfiguration can be self-diagnosed.
18. Phase 5: Tests and validation
19. Extend tests/casting_modes_test.lua for branch gating scenarios: feature off, feature on without bobber-active, feature on with bobber-active.
20. Add focused coverage for interact branch gate behavior in an existing or new test file.
21. Run run_tests.sh and verify no regressions.
22. Perform in-game checks for cast path, hooked interact path, loot-close reset, and movement/combat edge behavior.
23. Validate Setup instructions by following them on a clean profile and confirming expected behavior.

**Relevant files**
- f:/Games/World of Warcraft/Addons/DreamFisher/fishing/casting.lua — single guarded handoff in ConfigureFishingClickAction.
- f:/Games/World of Warcraft/Addons/DreamFisher/fishing/interactloot.lua — new isolated interact setup logic.
- f:/Games/World of Warcraft/Addons/DreamFisher/fishing/state.lua — reuse existing bobber-active lifecycle only.
- f:/Games/World of Warcraft/Addons/DreamFisher/core/init.lua — default feature flag.
- f:/Games/World of Warcraft/Addons/DreamFisher/DreamFisher.toc — load order registration.
- f:/Games/World of Warcraft/Addons/DreamFisher/ui/config.lua — UI toggle.
- f:/Games/World of Warcraft/Addons/DreamFisher/ui/commands.lua — optional setup/help discoverability.
- f:/Games/World of Warcraft/Addons/DreamFisher/UI requirements.md — add setup guidance section.
- f:/Games/World of Warcraft/Addons/DreamFisher/Requirements.md — reflect setup prerequisites in feature requirements.
- f:/Games/World of Warcraft/Addons/DreamFisher/tests/casting_modes_test.lua — branch behavior tests.

**Verification**
1. Execute run_tests.sh and confirm full pass.
2. Execute targeted casting mode tests during iteration.
3. Manually verify feature off path is unchanged.
4. Manually verify feature on plus bobber-active uses interact path.
5. Verify loot lifecycle transitions remain correct.
6. Verify setup checklist is sufficient for a fresh profile to achieve working behavior.

**Decisions**
- Include: small-code opt-in interact mode and explicit Setup documentation.
- Exclude: broad casting refactor or changing default user behavior.
- Assumption: game client exposes required interact and soft-target options for the user build.

**Further Considerations**
1. Keep Setup section concise and troubleshooting-first.
2. Add one debug line when interact branch is selected for field validation.
3. Define fallback behavior if interact target cannot be acquired.


## Implementation

Implemented the plan end-to-end in code, UI/help text, docs, and tests.

**What Changed**

1. Added hooked-interact module:
    `interactloot.lua`

2. Integrated an early opt-in hooked branch into fishing click configuration:
    `casting.lua`

3. Added default config flag:
    `init.lua`
    * New default: enableHookedLoot = false

4. Registered new module in load order:
    `DreamFisher.toc`

5. Added UI toggle and setup hint text in Modes tab:
    `config.lua`
    * New checkbox: “Use same trigger to interact when fish is hooked”

6. Added slash help/setup discoverability:
    `commands.lua`
    * New command: /df interactsetup (alias /df is)

7. Added setup requirements to docs:
    `Requirements.md`
    `UI requirements.md`

8. Added test coverage for new branch behavior:
    `casting_modes_test.lua`
    * New tests for enabled/disabled hooked interact behavior

9. Plan file already copied to project:
    `HookInteractPlan.md`

**Behavior**

    * When enableHookedLoot is on and bobber-active state is true, secure fishing action is configured as interact macro (/interact).
    *   Otherwise existing cast/buff logic remains unchanged.

**Validation**

1. Targeted test run passed:
    lua casting_modes_test.lua
    21 passed, 0 failed
    Full suite passed:
    run_tests.sh
    All test groups PASS, including updated casting suite

## Explanation of requirements for "soft-target/interact settings"

These are the settings needed for the bobber interaction to work, i.e. catching the fish when it is hooked (before looting it).

1. Enable Interact Key
* In Keybindings, bind an Interact action (often called Interact With Target / Interact With Mouseover depending on version/UI text).

2. Enable Soft Targeting for Interact
* In Combat/Controls settings, enable soft targeting so nearby valid objects can be auto-selected for interaction.
* This is what lets a single press find the bobber/fishing interaction target without a manual click.

3. Keep auto-loot behavior aligned with your addon expectation
* If your flow assumes quick loot-close/reset, users should keep Auto Loot in the expected state (or rely on your addon’s temporary override behavior).
* Avoid conflicting click-cast addons/settings on Right Click
* If another addon hijacks right-click world interactions, your secure click path may not reach Interact.

**Practical user-facing checklist (short version):**
1. Bind Interact key.
2. Turn on soft targeting/interact assistance.
3. Test once: cast, wait for bite, press same key/right-click trigger, confirm loot opens and closes.