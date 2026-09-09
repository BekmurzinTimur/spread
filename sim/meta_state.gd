class_name MetaState
extends RefCounted

## What the player carries between runs: seven wallets and a set of purchase
## levels. Everything else about a run — the board, the orbs, the ledger — is
## rebuilt from scratch at each ascension and none of it lives here.
##
## Plain integers and nothing else, which is what makes it serialisable without
## walking anything and testable without a board. It is the meta layer's
## counterpart to `Block`: the mutable half, against `MetaUpgrade`'s static one.
##
## **`World` reads this and never writes it.** Currency is accumulated on the
## `World` for the run in progress (`World.earned`) and only lands here when the
## player ascends, which is what keeps a run a pure function of the board it
## started with. The one-way arrow is the same shape as `scenes/ -> sim/`.

## Banked currency, one wallet per tier. int64, because the deep bands are priced
## on a doubling curve that reaches 13 billion on a single cell and a wallet has
## to hold more than one of those.
var banked: PackedInt64Array = PackedInt64Array()

## Upgrade key -> how many levels are owned. A key absent means zero, so a fresh
## state is an empty dictionary rather than a table of zeroes that has to be kept
## in step with `MetaUpgrades`.
var levels: Dictionary = {}

## Bumped by every mutator, and load-bearing rather than diagnostic.
##
## `World._ensure_stats()` early-outs unless something says the board changed,
## and a purchase moves neither `unlock_version` nor `topology_version`. Comparing
## this catches every purchase whoever made it — the same argument `_stats_version`
## is built on, and for the same reason: a flag that has to be *remembered* is a
## flag that will be forgotten by the third caller.
var version: int = 0


func _init() -> void:
	banked.resize(Tiers.COUNT)
	banked.fill(0)


# --- Queries ------------------------------------------------------------


func level_of(key: String) -> int:
	return int(levels.get(key, 0))


## Whether a block type with this `unlock_key` is live. An empty key is always
## live — that is how `generator_red` and everything with nothing to buy stays
## working on the first run.
func is_unlocked(key: String) -> bool:
	if key.is_empty():
		return true
	return level_of(key) > 0


func wallet(tier: int) -> int:
	if tier < 0 or tier >= banked.size():
		return 0
	return banked[tier]


## What the next level of this upgrade costs, or -1 if there is no next level.
## The two answers are deliberately distinguishable: 0 is a legitimate price.
func next_cost(key: String) -> int:
	var upgrade := MetaUpgrades.get_upgrade(key)
	if upgrade == null:
		return -1
	var level := level_of(key)
	if level >= upgrade.max_level:
		return -1
	return upgrade.cost_at(level)


func can_afford(key: String) -> bool:
	var upgrade := MetaUpgrades.get_upgrade(key)
	if upgrade == null:
		return false
	var cost := next_cost(key)
	if cost < 0:
		return false
	return wallet(upgrade.currency_tier) >= cost


# --- Commands -----------------------------------------------------------


## Buy one level. Returns whether it happened, so a caller cannot spend without
## noticing it failed — the same shape as `emit_orb` returning whether it emitted.
func buy(key: String) -> bool:
	if not can_afford(key):
		return false
	var upgrade := MetaUpgrades.get_upgrade(key)
	banked[upgrade.currency_tier] -= next_cost(key)
	levels[key] = level_of(key) + 1
	version += 1
	return true


## Bank a run's earnings. Takes the whole per-tier array rather than one tier at
## a time so the deposit is one event with one version bump, which is what the
## ascension flow wants: persist once, not seven times.
func deposit(earned: PackedInt64Array) -> void:
	for tier in mini(earned.size(), banked.size()):
		banked[tier] += earned[tier]
	version += 1


# --- Bonuses ------------------------------------------------------------


## Fold every purchased stat into the board's bonus table. Called by
## `World._resolve_stats()` on a freshly-built `GlobalBonus`, before the challenge
## sum, so a meta bonus and a mined challenge land in the same fields and every
## existing `effective_*` reader picks both up with no further work.
##
## A pure read of this state — it must never write, because `_resolve_stats()` is
## rebuilt lazily from *every* stat query, including the HUD's several times a
## frame. That is the same rule that keeps the upkeep drain in a phase of its own.
func apply_to(global: GlobalBonus) -> void:
	for key in levels:
		var upgrade := MetaUpgrades.get_upgrade(String(key))
		if upgrade == null:
			continue
		var level := int(levels[key])
		if level <= 0:
			continue
		var total := upgrade.value_per_level * level
		match upgrade.family:
			MetaUpgrade.FAMILY_SOURCE_VALUE:
				global.add_for_tier(upgrade.effect_tier, total, 0)
			MetaUpgrade.FAMILY_SOURCE_RATE:
				global.add_for_tier(upgrade.effect_tier, 0, total)
			MetaUpgrade.FAMILY_REACH:
				global.hop_rate_percent += total


# --- Serialisation ------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"version": 1,
		"banked": Array(banked),
		"levels": levels.duplicate(),
	}


## ⚠️ **Every value is forced through `int()`.** JSON round-trips numbers as
## floats, and a float reaching `GlobalBonus` would put one in the economy —
## which the determinism contract names as an architectural decision rather than
## an implementation detail. `PackedInt64Array` coerces on assignment; a plain
## `Dictionary` does not, so `levels` is the one that would have slipped through.
static func from_dict(data: Dictionary) -> MetaState:
	var state := MetaState.new()

	var stored = data.get("banked", [])
	if typeof(stored) == TYPE_ARRAY:
		for tier in mini(stored.size(), state.banked.size()):
			state.banked[tier] = int(stored[tier])

	var stored_levels = data.get("levels", {})
	if typeof(stored_levels) == TYPE_DICTIONARY:
		for key in stored_levels:
			# Unknown keys are dropped rather than kept: a save written by a build
			# that had an upgrade this one does not would otherwise resurrect it
			# the day the key came back, at whatever level it was left at.
			if not MetaUpgrades.has(String(key)):
				continue
			var level := int(stored_levels[key])
			if level > 0:
				state.levels[String(key)] = level

	return state
