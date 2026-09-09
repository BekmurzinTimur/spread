class_name MetaUpgrades

## Every ascension upgrade, in one place. The meta layer's `BlockCatalog`: built
## once, static, never mutated, and the only sanctioned way to name an upgrade.
##
## Like the generator and upgrader families one level down, the per-tier families
## are built in a **loop over `Tiers.COUNT`** rather than declared one at a time,
## so a tier added to `Tiers` cannot arrive without the upgrades that go with it.
##
## ⚠️ **An upgrade's key is also the `BlockDef.unlock_key` it releases.** A block
## type whose key names no upgrade here can never be bought, which means it stays
## inert for the whole game with no error anywhere — the same silent death
## `has_intake()` carries a warning about. `test_every_unlock_key_has_an_upgrade`
## is the guard, and it is the first thing to check if a block type will not come
## alive.

# --- Keys ---------------------------------------------------------------

## Block-type unlocks. These strings are duplicated as `unlock_key` in
## `BlockCatalog`, which is what the guard test above exists to police.
const PUMP := "pump"
const SPHERE := "sphere"
const UPKEEP := "upkeep"
const AMPLIFIER := "amplifier"
const COMPRESSOR := "compressor"
const DISTRIBUTOR := "distributor"
const TELEPORTER := "teleporter"
const CHALLENGE := "challenge"

## The one board-wide reach upgrade.
const ORB_SPEED := "orb_speed"


static func source_value_key(tier: int) -> String:
	return "gen_value_%s" % Tiers.name_of(tier)


static func source_rate_key(tier: int) -> String:
	return "gen_rate_%s" % Tiers.name_of(tier)


## Matches `BlockCatalog.generator_id(tier)`'s shape deliberately: the upgrade
## that releases a generator family is named after it.
static func generator_key(tier: int) -> String:
	return "generator_%s" % Tiers.name_of(tier)


static func upgrader_key(output_tier: int) -> String:
	return "upgrader_%s" % Tiers.name_of(output_tier)


# --- Balance ------------------------------------------------------------

## +2 orb value per level, ten levels, paid in the tier it acts on.
const SOURCE_VALUE_PER_LEVEL := 2
const SOURCE_VALUE_MAX := 10
const SOURCE_VALUE_COST := 200
const SOURCE_VALUE_GROWTH := 3

## +20% increased rate per level. An *increased rate*, not a flat tick cut, so it
## stacks into the same divisor a sphere does and never reaches a floor — see
## `StatBonus.apply_rate()`.
const SOURCE_RATE_PER_LEVEL := 20
const SOURCE_RATE_MAX := 10
const SOURCE_RATE_COST := 300
const SOURCE_RATE_GROWTH := 3

## +25% increased hop rate per level: 10 ticks per hop toward the floor of 2.
## Paid in red, because reach is what the opening is short of.
const ORB_SPEED_PER_LEVEL := 25
const ORB_SPEED_MAX := 6
const ORB_SPEED_COST := 500
const ORB_SPEED_GROWTH := 4

## One-off block unlocks, all paid in red and ordered by how much they change a
## run. The pump is deliberately cheap — it is the first thing a red clear should
## buy, and the mechanic the whole opening is missing without it.
const BLOCK_COSTS := {
	PUMP: 1000,
	SPHERE: 4000,
	UPKEEP: 12000,
	AMPLIFIER: 30000,
	COMPRESSOR: 60000,
	DISTRIBUTOR: 60000,
	TELEPORTER: 100000,
	CHALLENGE: 150000,
}

## A tier's two sources, paid in the tier **below**. Flat rather than climbing,
## because each rung is charged in its own currency and those are already on
## wildly different scales — the deep bands are priced on a doubling curve.
const GENERATOR_UNLOCK_COST := 25000
const UPGRADER_UNLOCK_COST := 50000


static var _upgrades: Dictionary = {}
static var _order: PackedStringArray = PackedStringArray()


static func _ensure_built() -> void:
	if not _upgrades.is_empty():
		return

	# Per-tier source stats, red included: red generators are live from the first
	# run, so red is the one colour whose stat upgrades are useful immediately.
	for tier in Tiers.COUNT:
		var value := MetaUpgrade.new()
		value.key = source_value_key(tier)
		value.display_name = "%s orb value" % Tiers.name_of(tier).capitalize()
		value.description = "+%d to what every %s generator launches with." \
			% [SOURCE_VALUE_PER_LEVEL, Tiers.name_of(tier)]
		value.family = MetaUpgrade.FAMILY_SOURCE_VALUE
		value.currency_tier = tier
		value.effect_tier = tier
		value.max_level = SOURCE_VALUE_MAX
		value.cost_base = SOURCE_VALUE_COST
		value.cost_growth = SOURCE_VALUE_GROWTH
		value.value_per_level = SOURCE_VALUE_PER_LEVEL
		_register(value)

		var rate := MetaUpgrade.new()
		rate.key = source_rate_key(tier)
		rate.display_name = "%s generator speed" % Tiers.name_of(tier).capitalize()
		rate.description = "+%d%% increased rate for every %s generator." \
			% [SOURCE_RATE_PER_LEVEL, Tiers.name_of(tier)]
		rate.family = MetaUpgrade.FAMILY_SOURCE_RATE
		rate.currency_tier = tier
		rate.effect_tier = tier
		rate.max_level = SOURCE_RATE_MAX
		rate.cost_base = SOURCE_RATE_COST
		rate.cost_growth = SOURCE_RATE_GROWTH
		rate.value_per_level = SOURCE_RATE_PER_LEVEL
		_register(rate)

	var speed := MetaUpgrade.new()
	speed.key = ORB_SPEED
	speed.display_name = "Orb speed"
	speed.description = "+%d%% increased travel rate. Orbs cross a hop sooner; " \
		% ORB_SPEED_PER_LEVEL + "what they arrive with is unchanged."
	speed.family = MetaUpgrade.FAMILY_REACH
	speed.currency_tier = Tiers.RED
	speed.max_level = ORB_SPEED_MAX
	speed.cost_base = ORB_SPEED_COST
	speed.cost_growth = ORB_SPEED_GROWTH
	speed.value_per_level = ORB_SPEED_PER_LEVEL
	_register(speed)

	_register_block(PUMP, "Pumps",
		"Buried pumps come alive: +20% of an orb's launch value, passing through.")
	_register_block(SPHERE, "Spheres",
		"Buried spheres come alive: everything within 2 hops runs on better numbers.")
	_register_block(UPKEEP, "Upkeep blocks",
		"Buried upkeep blocks come alive: burn red to speed every generator you own.")
	_register_block(AMPLIFIER, "Amplifiers",
		"Buried amplifiers come alive: x1.5 on an orb passing through, compounding.")
	_register_block(COMPRESSOR, "Compressors",
		"Buried compressors come alive: bank 100 of a colour, ship it as one orb.")
	_register_block(DISTRIBUTOR, "Distributors",
		"Buried distributors come alive: one line feeding up to four fronts.")
	_register_block(TELEPORTER, "Teleporters",
		"Buried teleporters come alive: a mined pair puts two cells one hop apart.")
	_register_block(CHALLENGE, "Challenges",
		"Buried challenges come alive: mining one grants a permanent board-wide buff.")

	# Every colour above red needs its two sources bought before it can be worked
	# at all, and both are charged in the colour **below** — the bootstrap rule.
	for tier in range(Tiers.RED + 1, Tiers.COUNT):
		var gen := MetaUpgrade.new()
		gen.key = generator_key(tier)
		gen.display_name = "%s generators" % Tiers.name_of(tier).capitalize()
		gen.description = "The buried %s generator comes alive." % Tiers.name_of(tier)
		gen.family = MetaUpgrade.FAMILY_TIER_SOURCE
		gen.currency_tier = tier - 1
		gen.effect_tier = tier
		gen.cost_base = GENERATOR_UNLOCK_COST
		_register(gen)

		var up := MetaUpgrade.new()
		up.key = upgrader_key(tier)
		up.display_name = "%s upgraders" % Tiers.name_of(tier).capitalize()
		up.description = "Buried %s -> %s converters come alive." \
			% [Tiers.name_of(tier - 1), Tiers.name_of(tier)]
		up.family = MetaUpgrade.FAMILY_TIER_SOURCE
		up.currency_tier = tier - 1
		up.effect_tier = tier
		up.cost_base = UPGRADER_UNLOCK_COST
		_register(up)


static func _register_block(key: String, display_name: String, description: String) -> void:
	var upgrade := MetaUpgrade.new()
	upgrade.key = key
	upgrade.display_name = display_name
	upgrade.description = description
	upgrade.family = MetaUpgrade.FAMILY_BLOCK
	upgrade.currency_tier = Tiers.RED
	upgrade.cost_base = int(BLOCK_COSTS[key])
	_register(upgrade)


static func _register(upgrade: MetaUpgrade) -> void:
	_upgrades[upgrade.key] = upgrade
	_order.append(upgrade.key)


static func get_upgrade(key: String) -> MetaUpgrade:
	_ensure_built()
	return _upgrades.get(key)


static func has(key: String) -> bool:
	_ensure_built()
	return _upgrades.has(key)


## Every key, in registration order — which is the order the shop draws them, so
## the grouping is decided here rather than by a sort in the view.
static func keys() -> PackedStringArray:
	_ensure_built()
	return _order
