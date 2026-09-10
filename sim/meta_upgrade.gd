class_name MetaUpgrade
extends RefCounted

## One purchasable upgrade: what it costs, what it does, how many times it may
## be bought.
##
## The meta layer's static half. What the player has actually bought lives in
## `MetaState.levels`. Plain integers throughout, so the shop's preview and the
## purchase can never round differently.

const FAMILY_UNLOCK := 0
const FAMILY_NODE_LEVEL := 1
const FAMILY_GENERATOR := 2
const FAMILY_RAM := 3
const FAMILY_VISION := 4
const FAMILY_BAND := 5

const FAMILY_NAMES: PackedStringArray = [
	"Buff types", "Node levels", "Generators", "Ram", "Vision", "Bands"
]

var key: String = ""
var display_name: String = ""
var description: String = ""
var family: int = FAMILY_UNLOCK

## 1 for a one-off unlock, so `level_of()` reads as a boolean for those.
var max_level: int = 1

## `cost_base x cost_growth ^ level`.
var cost_base: int = 0
var cost_growth: int = 1

## What one level is worth, in whatever unit the family deals in.
var value_per_level: int = 0


static func make(p_key: String, p_name: String, p_description: String,
		p_family: int, p_max_level: int, p_cost_base: int,
		p_cost_growth: int, p_value: int) -> MetaUpgrade:
	var upgrade := MetaUpgrade.new()
	upgrade.key = p_key
	upgrade.display_name = p_name
	upgrade.description = p_description
	upgrade.family = p_family
	upgrade.max_level = p_max_level
	upgrade.cost_base = p_cost_base
	upgrade.cost_growth = p_cost_growth
	upgrade.value_per_level = p_value
	return upgrade


## Returns 0 for a fully-bought upgrade, which callers must detect with
## `max_level` rather than by testing the price — 0 is a legitimate price.
func cost_at(level: int) -> int:
	if level < 0:
		return cost_base
	var cost := cost_base
	for _i in level:
		cost *= cost_growth
	return cost


func is_unlock() -> bool:
	return max_level <= 1
