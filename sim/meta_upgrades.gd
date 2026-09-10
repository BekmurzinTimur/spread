class_name MetaUpgrades

## Every ascension purchase, in one place. Built once, static, never mutated,
## and the only sanctioned way to name an upgrade.
##
## ⚠️ A buff-unlock key is also the `NodeType.unlock_key` it releases. A type
## whose key names no upgrade here can never be bought, and fails silently.
##
## Prices are a first pass against one measured number: a full red clear pays
## 2,631,600.

const GENERATOR_CHANCE := "generator_chance"
const RAM_POWER := "ram_power"
const VISION := "vision"


## The upgrade that puts a buff type into the board's table. Matches the
## `unlock_key` declared in `NodeCatalog`.
static func unlock_key(node_id: String) -> String:
	return "unlock_%s" % node_id


## +1 level of one buff type, applied from the first cell of the run.
static func node_level_key(node_id: String) -> String:
	return "level_%s" % node_id


static func band_key(band: int) -> String:
	return "band_%s" % Bands.NAMES[band].to_lower()


# --- Balance ------------------------------------------------------------

const UNLOCK_COSTS := {
	NodeCatalog.PULSE: 1_000,
	NodeCatalog.CRIT: 6_000,
	NodeCatalog.SPLIT: 10_000,
}

## ⚠️ Growth was 3, which put level 4 at 40,500 — past what a mid run banks, so
## the family died after three purchases. At 2 the whole ten-level ladder costs
## 818,400, which is roughly one good red run.
const NODE_LEVEL_MAX := 10
const NODE_LEVEL_COST := 300
const NODE_LEVEL_GROWTH := 2

## Ten levels take the generator chance from 0% to 100%. The spine of the whole
## game, and every level visibly changes the run — see the measured table at
## `World.GENERATOR_CHANCE`.
##
## ⚠️ **The floor under this number is what run 1 actually banks.** With no
## fallback emitter, a 0%-chance run mines the centre's six neighbours and stops
## — six cells at `50 x 1^3`, so **300 banked, every time**. Priced at 300 the
## loop worked only by exact coincidence; at 100 the first level is affordable
## out of one stalled run with change left over.
## `test_run_one_funds_the_first_purchase` is the guard, and it fails the day the
## cost curve or the band table moves.
const GENERATOR_CHANCE_COST := 100
const GENERATOR_CHANCE_MAX := 10

const RAM_POWER_COST := 4_000
const RAM_POWER_MAX := 6
const VISION_COST := 2_000
const VISION_MAX := 5

## ⚠️ **Priced against what a run actually banks, not against a full clear.** A
## full red clear pays 2,631,600, but nothing before the late runs comes close —
## measured, a 50%-chance run banks ~65,000 and a 70% one ~188,000. Orange at a
## quarter of a full clear meant several near-perfect reds before the second
## colour existed. At 250,000 it lands around run 5, which is the intended shape:
## early ascensions are short and frequent, and each one buys something.
const BAND_COSTS: PackedInt64Array = [
	0, 250_000, 900_000, 2_600_000, 6_000_000, 7_000_000, 17_600_000
]

static var _upgrades: Dictionary = {}
static var _order: Array[String] = []


static func _build() -> void:
	if not _upgrades.is_empty():
		return

	# First card in the shop, because it is the one that changes how the game
	# plays rather than how fast it goes.
	_add(MetaUpgrade.make(GENERATOR_CHANCE, "Generator chance",
		"+10% chance a mined cell becomes a generator.",
		MetaUpgrade.FAMILY_GENERATOR, GENERATOR_CHANCE_MAX,
		GENERATOR_CHANCE_COST, 2, 10))

	for node_id in NodeCatalog.ids():
		var id := String(node_id)
		var type := NodeCatalog.get_type(id)
		if UNLOCK_COSTS.has(id):
			_add(MetaUpgrade.make(
				unlock_key(id), "Unlock %s" % type.display_name,
				"%s nodes start appearing on the board." % type.display_name,
				MetaUpgrade.FAMILY_UNLOCK, 1, UNLOCK_COSTS[id], 1, 0))

	for node_id in NodeCatalog.ids():
		var id := String(node_id)
		var type := NodeCatalog.get_type(id)
		_add(MetaUpgrade.make(
			node_level_key(id), "%s level" % type.display_name,
			"Start every run with an extra level of %s." % type.display_name,
			MetaUpgrade.FAMILY_NODE_LEVEL, NODE_LEVEL_MAX,
			NODE_LEVEL_COST, NODE_LEVEL_GROWTH, 1))

	_add(MetaUpgrade.make(RAM_POWER, "Ram power",
		"+25% damage when you ram.",
		MetaUpgrade.FAMILY_RAM, RAM_POWER_MAX, RAM_POWER_COST, 2, 25))
	_add(MetaUpgrade.make(VISION, "Vision",
		"+1 hop of sight, for both names and glows.",
		MetaUpgrade.FAMILY_VISION, VISION_MAX, VISION_COST, 2, 1))

	for band in range(Bands.ORANGE, Bands.COUNT):
		_add(MetaUpgrade.make(band_key(band), "Unlock %s" % Bands.name_of(band),
			"The frontier may mine into the %s band." % Bands.name_of(band),
			MetaUpgrade.FAMILY_BAND, 1, BAND_COSTS[band], 1, 0))


static func _add(upgrade: MetaUpgrade) -> void:
	_upgrades[upgrade.key] = upgrade
	_order.append(upgrade.key)


static func get_upgrade(key: String) -> MetaUpgrade:
	_build()
	return _upgrades.get(key)


static func has(key: String) -> bool:
	_build()
	return _upgrades.has(key)


## Every upgrade in declaration order, which is the order the shop draws them.
static func all() -> Array[String]:
	_build()
	return _order
