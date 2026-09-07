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


func add(orb_value: int, restore_percent: int, radius_percent: int, rate_percent: int) -> void:
	orb_value_delta += orb_value
	restore_percent_delta += restore_percent
	field_radius_percent += radius_percent
	rate_percent_delta += rate_percent


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
