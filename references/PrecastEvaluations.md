
 # Choosing the next buff

 During a pre-cast, the next buff item is chosen in this order:

1. Higher-level pre-cast actions run first
	* Fishing pole equip (instant cast, but some delay before it becomes equipped)
	* Raft (1.5s cast time)
	* Bobber (toy) (1s cast time)
	* Oversized bobber (1.5s cast time)
	* Consumables (some are instant, some have cast times)
	If one of the above non-zero cast time items is used, the consumable buff selector is skipped for that click because some consumables also have non-zero cast times which would interrupt any cast already in progress. Anything with a cast time makes it exclusive with anything else with a cast time.

2. Consumable buff categories are checked in fixed priority order:
	fooddrink -> lure -> bait -> bobber -> other consumable

3. Within a category, configured order wins.
	Scan the charDB[category] buff items from top to bottom and return the first candidate that:
		* Is enabled
		* Is not excluded
		* Is considered due
		* Is not on cooldown
		* Exists in the bags
		* Lure, if fishing pole equipped
		* Bait, if there is not already a bait

# When a buff is "due"

An item is considered due when the buff is expected to expire soon or cannot be reliably confirmed as active.

The checks happen in this order.

1. Food/drink transient block:
	After using a food or drink, the item is temporarily treated as active for 10 seconds. During that window it is not due and no other casting action should be attempted to prevent interrupting the eating or drinking.

2. Recent-use protection
	If the item was used within the last 5 seconds, it is not due. This prevents the same aura from being selected again before the game has populated its aura state.

3. Recent-aura protection
	If this item has a known aura and a different item was used within the last 5 seconds that is expected to produce the same aura, this item is not due.

4. Tracked aura remaining time
	If remaining time an aura can be determined, the item is due when:
		`remainingTime <= refreshLeadTime`
    where
    * `remainingTime` is `math.max(0, aura.expirationTime - GetTime())`
	* `refreshLeadTime` is the larger of:
		* 10% of the known duration, clamped between 3 and 15 seconds
		* The cast-safety window: maximum fishing cast time (20s) plus buff refresh safety time (2s)

5. Known spell, missing aura
	If the item has a known spell but its aura is not currently visible:
		* It is considered not due if it was used recently enough that the known duration should still be active.

6. Unknown-duration suppression
	If the item has been marked as unsafe to reapply because its duration is unknown, it is not due.
	This happens if the item is used and a valid aura is not detected within 20 seconds or could not determine duration from the aura.
	The suppression is persisted in the database: `buffUnknownDurationSuppressed[itemID] = true`
	The suppression is cleared if 1) A later observation successfullly identifies the aura and duration or 2) The item is removed from configuration.

7. No aura and cast-time evaluation
	During pre-cast, `requireAuraForCast` is true:
		* An item never used before is considered due so it can be probed
		* An item with a pending aura observation is temporarily withheld
		* An item previously used (with known duration) but still lacking an aura is considered due for another probe (based on elapsed time since its last use).

8. Visible aura with known duration
	If an aura exists but no remaining-time tracking is available, the fallback is elapsed time since the item was last used:
		`elapsedTime >= knownDuration`

# Fishing pole selection

1. If outside of a fishing context, the Underlight Angler is equipped, assuming it is available, etc.
2. Within a fishing context, the primary fishing pole is equipped, assuming it is available, etc.
3.