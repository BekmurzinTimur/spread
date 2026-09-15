class_name MetaUpgrade
extends RefCounted

## One purchasable upgrade: its price, its level cap and the colour block it sits
## in. What the player owns lives in `MetaState.levels`. One function prices a
## level, so the shop's preview and the purchase can never round differently.

## `max_level` of an upgrade that can be bought forever.
const UNCAPPED := -1

## Prices and the wallet saturate here, well short of float infinity.
const COST_CEILING := 1e300

var key: String = ""
var display_name: String = ""
var description: String = ""

## The shop block it lives in. Buyable once that region is open.
var region: int = Regions.RED

## The shop group it is drawn in, one of `MetaUpgrades.GROUP_*`.
var group: int = 0

## Shown as a question mark while its block is closed.
var hidden: bool = false

var max_level: int = UNCAPPED

## `cost_base x (cost_growth / 100) ^ level`.
var cost_base: int = 0
var cost_growth: int = 100


static func make(p_key: String, p_name: String, p_description: String,
		p_region: int, p_max_level: int, p_cost_base: int,
		p_cost_growth: int) -> MetaUpgrade:
	var upgrade := MetaUpgrade.new()
	upgrade.key = p_key
	upgrade.display_name = p_name
	upgrade.description = p_description
	upgrade.region = p_region
	upgrade.max_level = p_max_level
	upgrade.cost_base = p_cost_base
	upgrade.cost_growth = p_cost_growth
	return upgrade


## Floored each step, matching the integer prices it replaced.
func cost_at(level: int) -> float:
	var cost := float(cost_base)
	for _i in maxi(level, 0):
		cost = minf(floorf(cost * cost_growth / 100.0), COST_CEILING)
	return cost


func is_capped() -> bool:
	return max_level != UNCAPPED


func is_maxed(level: int) -> bool:
	return is_capped() and level >= max_level


## A one-off purchase: owned or not.
func is_unlock() -> bool:
	return max_level == 1
