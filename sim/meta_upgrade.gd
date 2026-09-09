class_name MetaUpgrade
extends RefCounted

## One purchasable ascension upgrade: what it costs, what it does, and how many
## times it may be bought.
##
## This is the meta layer's `BlockDef` — static per-type data, held once in
## `MetaUpgrades` and never mutated. What the player has actually bought lives in
## `MetaState.levels`, exactly as a block's mutable state lives on `Block` rather
## than on its def.
##
## Plain integers throughout, for the same reason the rest of `sim/` is: a cost
## curve that rounded differently between the shop's preview and the purchase
## would let a player see one price and be charged another.

## Which family this belongs to. Read only by the shop, to group cards under a
## heading — nothing in the simulation branches on it.
const FAMILY_SOURCE_VALUE := 0
const FAMILY_SOURCE_RATE := 1
const FAMILY_REACH := 2
const FAMILY_BLOCK := 3
const FAMILY_TIER_SOURCE := 4

const FAMILY_NAMES: PackedStringArray = [
	"Sources — value", "Sources — speed", "Reach", "Block types", "Tiers"
]

var key: String = ""
var display_name: String = ""
var description: String = ""
var family: int = FAMILY_BLOCK

## Which wallet pays for this. The load-bearing case is the tier-source family:
## an orange generator is paid for in **red**, because orange currency comes from
## mining orange cells and that needs an orange source to exist first. Charging a
## tier's own currency for the thing that first produces it is a deadlock, and it
## is the same shape as the map generator's "no source behind a gate deeper than
## what it makes" rule one level up.
var currency_tier: int = Tiers.RED

## How many times this may be bought. 1 for a one-off unlock, so `level_of()`
## reads as a boolean for those and `is_unlocked()` needs no separate table.
var max_level: int = 1

## `cost_base × cost_growth ^ level`, so the price of the *next* level climbs
## geometrically. Integer exponentiation — see `cost_at()`.
var cost_base: int = 0
var cost_growth: int = 1

## Which tier the effect lands on, or -1 for a board-wide one. Distinct from
## `currency_tier`: a tier-source unlock is paid in red and acts on orange.
var effect_tier: int = -1

## How much one level is worth, in whatever unit the family deals in — orb value
## for SOURCE_VALUE, percentage points of increased rate for SOURCE_RATE and
## REACH, and unused by the two unlock families.
var value_per_level: int = 0

## An unlock upgrade's `key` **is** the `BlockDef.unlock_key` it releases, rather
## than a list of ids it names. One string, one source of truth: a def cannot
## reference an upgrade that does not exist, and an upgrade cannot claim a def
## that does not point back at it. `test_every_unlock_key_has_an_upgrade` is a
## plain lookup because of it.
##
## Several defs may share one key — all seven compressors do, and all three
## challenges — which is what makes "unlock compressors" one purchase rather than
## seven.


## What the next level costs, given how many are already owned. Returns 0 for a
## fully-bought upgrade, which callers must check with `max_level` rather than by
## testing the price — 0 also being a legitimate price for a free upgrade.
func cost_at(level: int) -> int:
	if level < 0:
		return cost_base
	var cost := cost_base
	for _i in level:
		cost *= cost_growth
	return cost


## Whether this upgrade is a one-off unlock rather than a levelled stat. The shop
## draws the two differently — a toggle against a "level 3 / 10" readout — and it
## is derived rather than stored so the two can never disagree.
func is_unlock() -> bool:
	return max_level <= 1
