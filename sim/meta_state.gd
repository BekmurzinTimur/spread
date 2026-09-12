class_name MetaState
extends RefCounted

## What the player carries between runs: one wallet and a set of purchase
## levels. Everything else about a run — the board, the orbs, the buffs found —
## is rebuilt at each ascension and none of it lives here.
##
## **`World` reads this and never writes it.** A run's earnings accumulate on
## `World.earned` and land here only when the player ascends, which is what keeps
## a run a pure function of the board it started with.

## One currency. Float, because deep colours pay far past int64.
var banked: float = 0.0

## Upgrade key -> levels owned. A key absent means zero, so a fresh state is an
## empty dictionary rather than a table of zeroes to keep in step.
var levels: Dictionary = {}

## Bumped by every mutator. Load-bearing: a purchase moves no board version, so
## this is what tells `World` its frontier and buff tally have gone stale.
var version: int = 0


# --- Queries ------------------------------------------------------------


func level_of(key: String) -> int:
	return int(levels.get(key, 0))


## An empty key is always unlocked — that is how Yield stays in the pool on the
## first run with nothing bought.
func is_unlocked(key: String) -> bool:
	if key.is_empty():
		return true
	return level_of(key) > 0


## Red is always open. Any other region, and its shop block, opens once its boss
## has been beaten and the run banked.
func region_open(region: int) -> bool:
	return region <= Regions.RED or is_unlocked(MetaUpgrades.region_key(region))


## What the next level costs, or -1 if it cannot be bought: maxed, or its block
## is still closed. Distinguishable from 0, which is a legitimate price.
func next_cost(key: String) -> float:
	var upgrade := MetaUpgrades.get_upgrade(key)
	if upgrade == null or not region_open(upgrade.region):
		return -1.0
	var level := level_of(key)
	if upgrade.is_maxed(level):
		return -1.0
	return upgrade.cost_at(level)


func can_afford(key: String) -> bool:
	var cost := next_cost(key)
	return cost >= 0 and banked >= cost


# --- Commands -----------------------------------------------------------


## Returns whether it happened, so a caller cannot spend without noticing it
## failed.
func buy(key: String) -> bool:
	if not can_afford(key):
		return false
	banked -= next_cost(key)
	levels[key] = level_of(key) + 1
	version += 1
	return true


## Back to a first-boot state: no wallet, nothing bought. The version still
## climbs so `World` re-resolves rather than keeping a frontier it no longer owns.
func reset() -> void:
	banked = 0.0
	levels.clear()
	version += 1


## A beaten boss, banked. Called by Main, never by World.
func open_region(region: int) -> void:
	if region <= Regions.RED or region_open(region):
		return
	levels[MetaUpgrades.region_key(region)] = 1
	version += 1


func deposit(amount: float) -> void:
	if amount <= 0.0:
		return
	banked = minf(banked + amount, MetaUpgrade.COST_CEILING)
	version += 1


# --- Serialisation ------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"banked": banked,
		"levels": levels.duplicate(),
	}


## ⚠️ **Levels are forced through `int()`, the wallet through `float()`.** JSON
## round-trips every number as a float.
## A save from an older, incompatible format starts the player over rather than
## refusing to boot — its keys name upgrades that no longer exist and its wallet
## was a per-tier array, so there is nothing in it worth salvaging.
const SAVE_VERSION := 2

static func from_dict(data: Dictionary) -> MetaState:
	var state := MetaState.new()
	if int(data.get("version", 0)) != SAVE_VERSION:
		return state

	var banked_value = data.get("banked", 0)
	if typeof(banked_value) not in [TYPE_INT, TYPE_FLOAT]:
		return state
	state.banked = minf(float(banked_value), MetaUpgrade.COST_CEILING)

	var stored = data.get("levels", {})
	if typeof(stored) == TYPE_DICTIONARY:
		for stored_key in stored:
			var key := String(stored_key)
			if key.begins_with(MetaUpgrades.LEGACY_REGION_PREFIX):
				key = "region_" + key.trim_prefix(MetaUpgrades.LEGACY_REGION_PREFIX)
			# Unknown keys are dropped rather than kept: a save from a build that
			# had an upgrade this one does not would otherwise resurrect it.
			if not MetaUpgrades.has(key) and not key in MetaUpgrades.REGION_KEYS:
				continue
			var level := int(stored[stored_key])
			if level > 0:
				state.levels[key] = level

	return state
