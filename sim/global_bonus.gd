class_name GlobalBonus
extends RefCounted

## The bonuses that apply to the whole board, summed across every challenge block
## the player has mined. Plain integers — no floats anywhere in the economy.
##
## This is the board-wide counterpart to StatBonus. The distinction is *where a
## bonus is read*, not how big it is: a StatBonus is keyed by cell id and only
## the block standing on that cell sees it, while a GlobalBonus is read by every
## consumer on the map regardless of position. That is why a challenge block is
## anchored and a sphere is not — a sphere's value is in where you put it, and a
## challenge has no "where" to speak of.
##
## Rebuilt wholesale by `World._resolve_stats()`, never edited in place, for the
## same reason the field is: a sum of integers converges to the same total
## however `cell_ids` is iterated, so the phase stays order-independent and there
## is no accumulated drift to chase.

## Added to ORB_START_VALUE, so every generator on the board launches richer.
var orb_value_delta: int = 0

## Percentage points added to every path modifier's restore, on top of any
## sphere field. The Current is the only source, and it upgrades the pump's
## percentage rather than handing out flat value — so it is worth more on a
## board where orbs launch richer, exactly like the pump itself.
var restore_percent_delta: int = 0

## Percentage added to every radiating block's field radius. 50 means +50%.
var field_radius_percent: int = 0

## *Increased* rate for every producer on the board, in percentage points,
## accumulating upward like `StatBonus.rate_percent_delta` and resolved through
## the same `StatBonus.apply_rate()`.
##
## The one global that is *not* permanent: an upkeep block contributes this only
## while it is fuelled, which is why the stats pass asks the block and not just
## the def. Everything else here is a mined challenge and stays granted forever.
##
## There is deliberately no board-wide *charge* term to match the field's. A
## sphere discounts a converter; nothing on the board discounts every converter
## at once, and an unused field in a sum every consumer reads is clutter. The day
## something grants one it lands here beside this.
var rate_percent_delta: int = 0


## Orb value bought per tier through ascension, on top of `orb_value_delta`. A
## Surge raises every colour at once; a meta upgrade raises the one it was bought
## for, so the two axes cannot be one field.
var orb_value_by_tier: PackedInt32Array = PackedInt32Array()

## *Increased* rate per tier, summed into the same total `rate_percent_delta`
## feeds so the whole lot still divides exactly once — see `rate_percent_for()`.
var rate_percent_by_tier: PackedInt32Array = PackedInt32Array()

## *Increased* travel rate for every orb on the board, resolved through
## `StatBonus.apply_rate()` against `World.TICKS_PER_HOP`.
##
## Deliberately not per tier. Hop duration is a property of the board rather than
## of what is crossing it, and an orb carries no reference to the upgrade that
## sped it up — the same argument that makes `BlockCatalog.AMPLIFY_PERCENT`
## economy-wide rather than per-def.
var hop_rate_percent: int = 0


func _init() -> void:
	orb_value_by_tier.resize(Tiers.COUNT)
	orb_value_by_tier.fill(0)
	rate_percent_by_tier.resize(Tiers.COUNT)
	rate_percent_by_tier.fill(0)


func add(orb_value: int, restore_percent: int, radius_percent: int, rate_percent: int) -> void:
	orb_value_delta += orb_value
	restore_percent_delta += restore_percent
	field_radius_percent += radius_percent
	rate_percent_delta += rate_percent


## Seeded by the meta layer, ahead of the challenge sum in `_resolve_stats()`.
##
## A separate method rather than a widened `add()`: that one has a fixed four-arg
## signature called from the challenge pass, and folding seven more arguments
## into it would make every challenge call site carry parameters it has no
## opinion about.
func add_for_tier(tier: int, orb_value: int, rate_percent: int) -> void:
	if tier < 0 or tier >= orb_value_by_tier.size():
		return
	orb_value_by_tier[tier] += orb_value
	rate_percent_by_tier[tier] += rate_percent


## What a generator of this tier adds to `ORB_START_VALUE`: the board-wide term
## plus its own. A caller with no tier in hand is a bug — see
## `World.effective_orb_value()`.
func orb_value_for(tier: int) -> int:
	if tier < 0 or tier >= orb_value_by_tier.size():
		return orb_value_delta
	return orb_value_delta + orb_value_by_tier[tier]


## Increased rate reaching a producer of this tier, board-wide term included.
##
## Returned as a single number precisely so its caller can add the sphere's field
## to it and divide **once**. Two divisions truncate twice and give a different,
## order-dependent answer — see `StatBonus.apply_rate()`.
func rate_percent_for(tier: int) -> int:
	if tier < 0 or tier >= rate_percent_by_tier.size():
		return rate_percent_delta
	return rate_percent_delta + rate_percent_by_tier[tier]


## Scale a base by an accumulated percentage. The first multiplicative buff in
## the game, and it is fixed here for the same reason `StatBonus.combine()` fixes
## the flat order: with integer arithmetic the order is not associative, so a
## rule rediscovered at each call site drifts silently as the map changes.
##
## Deliberately *not* part of `combine()`. That function resolves a stat against
## a field; this one scales a radius, which is an input to building the field in
## the first place. Folding them together would put a cycle in the stats pass.
##
## Truncating division rounds down, which keeps the buff honest: a radius only
## grows once the percentage actually buys a whole hop.
static func scale_percent(base: int, percent: int) -> int:
	return (base * (100 + percent)) / 100
