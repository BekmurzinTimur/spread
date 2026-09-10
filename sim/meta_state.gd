class_name MetaState
extends RefCounted

## What the player carries between runs: one wallet and a set of purchase
## levels. Everything else about a run — the board, the orbs, the buffs found —
## is rebuilt at each ascension and none of it lives here.
##
## **`World` reads this and never writes it.** A run's earnings accumulate on
## `World.earned` and land here only when the player ascends, which is what keeps
## a run a pure function of the board it started with.

## One currency now. int64 because a deep-band clear pays into the millions.
var banked: int = 0

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


## What the next level costs, or -1 if there is no next level. Distinguishable
## from 0, which is a legitimate price.
func next_cost(key: String) -> int:
	var upgrade := MetaUpgrades.get_upgrade(key)
	if upgrade == null:
		return -1
	var level := level_of(key)
	if level >= upgrade.max_level:
		return -1
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
	banked = 0
	levels.clear()
	version += 1


func deposit(amount: int) -> void:
	if amount <= 0:
		return
	banked += amount
	version += 1


# --- Serialisation ------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"banked": banked,
		"levels": levels.duplicate(),
	}


## ⚠️ **Every value is forced through `int()`.** JSON round-trips numbers as
## floats, and a float reaching the economy would break the determinism contract.
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
	state.banked = int(banked_value)

	var stored = data.get("levels", {})
	if typeof(stored) == TYPE_DICTIONARY:
		for key in stored:
			# Unknown keys are dropped rather than kept: a save from a build that
			# had an upgrade this one does not would otherwise resurrect it.
			if not MetaUpgrades.has(String(key)):
				continue
			var level := int(stored[key])
			if level > 0:
				state.levels[String(key)] = level

	return state
