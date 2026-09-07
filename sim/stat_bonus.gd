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
## Deltas are additive, which is why they stack: two spheres reaching the same
## cell contribute twice. The pump's restore stacks along a route for the same
## reason — a bonus that saturates makes the second one you place worthless.

## *Increased* rate for a producer, in percentage points, so this accumulates
## **upward** — the opposite of the tick delta it replaced, and the easiest thing
## here to get backwards. 25 means the block works 25% faster; `apply_rate()`
## below turns it into an interval.
var rate_percent_delta: int = 0

## Percentage points added to a path modifier's restore. The stat itself is a
## percentage of an orb's launch value, so a field contributes points to it
## rather than value: 10 here takes a pump from 20% to 30%.
var restore_percent_delta: int = 0

## *Increased* charge rate for a converter, in percentage points, accumulating
## upward like `rate_percent_delta`. A converter's clock is denominated in
## delivered value rather than ticks, so charging faster means costing less:
## this is a discount on `upgrade_cost`, resolved through the same `apply_rate()`.
var charge_percent_delta: int = 0


func add(rate_percent: int, restore_percent: int, charge_percent: int) -> void:
	rate_percent_delta += rate_percent
	restore_percent_delta += restore_percent
	charge_percent_delta += charge_percent


## The one place a base stat and a field are combined, so the order is fixed
## once rather than rediscovered at each call site.
##
## Deliberately flat-only, and it stays that way. The pump's restore is the one
## stat resolved here: a field contributes percentage *points* to it, which are
## summed like any other flat term and only become value later, in `percent_of()`.
##
## The rate axis is **not** folded in. An increased rate divides rather than
## scales, so putting it here would make one function answer two questions — the
## same argument that keeps `GlobalBonus.scale_percent()` separate. It has its own
## fixed point, `apply_rate()` below.
##
## Fixing the order in one place is the cheap half of the problem. The expensive
## half is that with integer arithmetic the order is not associative: a different
## order gives different numbers, and they would drift silently as the map
## changed.
static func combine(base: int, flat: int, minimum: int = 0) -> int:
	return maxi(minimum, base + flat)


## The one place an accumulated *increased rate* becomes a resolved stat, for the
## same reason `combine()` is the one place a flat field is applied.
##
##     final = base / (1 + Σincreased / 100)
##
## Path of Exile's cooldown-recovery curve, and it is chosen for its shape: it is
## asymptotic, so bonuses stack forever without ever reaching zero. The flat
## subtraction this replaced needed a floor to stop it hitting zero, and that
## floor made every buff past the fourth worth exactly nothing.
##
## `minimum` is therefore a divide-by-zero guard rather than a balance cap — on a
## base of 20 it takes +1900% to touch it.
##
## Truncating division rounds **down**, which is the player's favour for every
## stat this serves: a shorter interval and a cheaper conversion are both good.
## That is `percent_of()`'s round-up reasoning applied to a stat that runs the
## other way, not a contradiction of it.
##
## **The sum happens before the division, always.** Two sources of +25% are
## `base × 100 / 150`, never `apply_rate(apply_rate(base, 25), 25)` — dividing
## twice truncates twice and is a different, order-dependent number.
static func apply_rate(base: int, increased: int, minimum: int = 1) -> int:
	if base <= 0:
		return 0
	# Clamped so a hypothetical -100% or worse cannot divide by zero or flip the
	# sign. Nothing grants a negative rate today; the guard costs nothing.
	var divisor := maxi(1, 100 + increased)
	@warning_ignore("integer_division")
	var scaled := (base * 100) / divisor
	return maxi(minimum, scaled)


## A percentage of a base, rounded **up** — the player's favour. The pump's
## restore is the one stat resolved this way: the percentage is summed here (see
## `restore_percent_delta`) and applied to an orb's launch value exactly once.
##
## Deliberately the opposite of `GlobalBonus.scale_percent()`, which truncates.
## The two are not inconsistent: a radius is a whole number of hops and only
## grows once the buff genuinely buys one, while a restore is value handed to
## the player and a fraction of a point is worth more to them than to nobody.
##
## Fixed here for the same reason `combine()` is fixed: with integer arithmetic
## a rounding rule rediscovered at each call site drifts silently.
static func percent_of(base: int, percent: int) -> int:
	if base <= 0 or percent <= 0:
		return 0
	return (base * percent + 99) / 100
