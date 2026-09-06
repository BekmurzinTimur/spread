class_name StatBonus
extends RefCounted

## The bonuses radiating onto one cell, summed across every sphere that reaches
## it. Plain integers — no floats anywhere in the economy.
##
## This is the *field*, not a resolved stat: it says what the board contributes
## at this position, and knows nothing about which block happens to sit here.
## Applying it to a base is `combine()` below. Keeping the two apart means moving
## a pump between two cells needs no rebuild — only moving a sphere does.
##
## Deltas are flat and additive, which is why they stack: two spheres reaching
## the same cell contribute twice. The pump was made flat and stacking for the
## same reason — a bonus that saturates makes the second one you place worthless.

## Ticks off a producer's interval. Negative is faster, so this accumulates
## downward.
var interval_delta: int = 0

## Added to a path modifier's restore amount.
var restore_delta: int = 0


func add(interval: int, restore: int) -> void:
	interval_delta += interval
	restore_delta += restore


## The one place a base stat and a field are combined, so the order is fixed
## once rather than rediscovered at each call site.
##
## Only the flat term exists today. When percentage and multiplicative buffs
## land — spheres that scale rather than subtract, upkeep buffs — they go here
## and nowhere else, in this order:
##
##     (base + Σflat) × (1 + Σpct) × Πmult
##
## Fixing it now is the cheap half of the problem. The expensive half is that
## with integer arithmetic the order is not associative: a different order gives
## different numbers, and they would drift silently as the map changed.
static func combine(base: int, flat: int, minimum: int = 0) -> int:
	return maxi(minimum, base + flat)
