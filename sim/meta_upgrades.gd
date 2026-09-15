class_name MetaUpgrades

## Every ascension purchase. Built once, static, never mutated, and the only
## sanctioned way to name an upgrade.
##
## Each upgrade sits in a colour block, buyable once that colour's boss has fallen,
## and in a type group, which is how the shop draws it. Region keys are saved in
## `MetaState` but never sold.
##
## ⚠️ Keys are save keys and must never be renamed. A buff-unlock key is also the
## `NodeType.unlock_key` it releases.

const GENERATOR_CHANCE := "generator_chance"
const RAM_UNLOCK := "unlock_ram"
const RAM_POWER := "ram_power"
const VISION := "vision"
const CRIT_MULTIPLIER := "crit_multiplier"
const SPLASH_STRENGTH := "splash_strength"
const SPLASH_BOUNCE := "splash_bounce"
const RAM_SPLASH := "ram_splash"
const RAM_BOUNCE := "ram_bounce"
const RAM_SPLASH_BOUNCE := "ram_splash_bounce"
const BOUNCE_STRENGTH := "bounce_strength"
const BOUNCE_SKILL := "bounce_skill"
const OVERCHARGE := "overcharge"
const ORB_MULTIPLIER := "orb_multiplier"
const RAM_CHARGE := "ram_charge"
const BOUNTY := "bounty"

const REGION_KEYS: PackedStringArray = [
	"region_red", "region_orange", "region_yellow", "region_green",
	"region_teal", "region_blue", "region_purple",
]

## Saves written before regions were named keep their open regions.
const LEGACY_REGION_PREFIX := "band_"

## Shop groups, in draw order.
const GROUP_POWER := 0
const GROUP_SPEED := 1
const GROUP_CRIT := 2
const GROUP_BOUNCE := 3
const GROUP_SPLASH := 4
const GROUP_RAM := 5
const GROUP_ECONOMY := 6
const GROUP_COUNT := 7
const GROUP_NAMES: PackedStringArray = [
	"Power", "Speed", "Crit", "Bounce", "Splash", "Ram", "Economy",
]


static func unlock_key(node_id: String) -> String:
	return "unlock_%s" % node_id


## Levels of one buff type, applied from the first cell of the run. Red keeps the
## bare key; other colours' tiers are suffixed.
static func node_level_key(node_id: String, region: int = Regions.RED) -> String:
	if region == Regions.RED:
		return "level_%s" % node_id
	return "level_%s_%s" % [node_id, Regions.name_of(region).to_lower()]


static func region_key(region: int) -> String:
	return REGION_KEYS[region]


## Every bought level of a buff type, summed across colour tiers.
static func bought_levels(meta: MetaState, node_id: String) -> int:
	var total := 0
	for region in Regions.COUNT:
		total += meta.level_of(node_level_key(node_id, region)) \
			* NodeCatalog.levels_in_region(node_id, region)
	return total


# --- Balance ------------------------------------------------------------
# Growth is a percentage: 150 makes each level cost 1.5x the last.

## Five levels take the chance from 0% to 100%. The first level must stay within
## what a stalled run 1 banks — `test_run_one_funds_the_first_purchase`.
const GENERATOR_CHANCE_COST := 5
const GENERATOR_CHANCE_GROWTH := 500
const GENERATOR_CHANCE_MAX := 5

## Red is hand-priced.
const PULSE_UNLOCK_COST := 25
const POWER_COST := 15
const PULSE_LEVEL_COST := 18
const RAM_UNLOCK_COST := 50
const RAM_POWER_COST := 40
const RAM_POWER_GROWTH := 180
## Capped so the ram's effective share of a cell stays well under 100%, or it feeds itself.
const RAM_POWER_MAX := 2
const VISION_COST := 20
const VISION_GROWTH := 200

## Past red, prices are counted in a per-colour unit.
const PRICE_UNIT_FIRST := 2048
const PRICE_UNIT_GROWTH := 25
const POWER_PRICE_CELLS := 10
const UNLOCK_PRICE_CELLS := 50
const LEVEL_PRICE_CELLS := 20
const STRENGTH_PRICE_CELLS := 100

const LEVEL_GROWTH := 140
## Red's Power and Speed levels climb faster, so the red boss takes a few runs.
const RED_LEVEL_GROWTH := 160
## Bounce is hand-priced far above its block: an expensive mechanic.
const BOUNCE_UNLOCK_COST := 100_000_000_000_000        # 1e14
const BOUNCE_LEVEL_COST := 1_000_000_000_000_000       # 1e15
const BOUNCE_STRENGTH_COST := 100_000_000_000_000      # 1e14
const BOUNCE_SKILL_COST := 1_000_000_000_000_000       # 1e15
const BOUNCE_GROWTH := 1000
const BOUNCE_STRENGTH_GROWTH := 400

## Ram versions of orb cards cost this much more.
const RAM_PRICE_MULTIPLIER := 10

## Chance levels and strength cards multiply; they climb faster.
const CHANCE_LEVEL_GROWTH := 250
const STRENGTH_GROWTH := 250

## Splash levels stop at 100%. Crit is diminishing, so uncapped.
const CHANCE_LEVELS_MAX := 20
## Bounces keep at most 90% before the skill.
const BOUNCE_STRENGTH_MAX := 8
const RAM_CHARGE_MAX := 2

static var _upgrades: Dictionary = {}
static var _order: Array[String] = []
static var _by_group: Array = []


static func _build() -> void:
	if not _upgrades.is_empty():
		return
	for group in GROUP_COUNT:
		_by_group.append([] as Array[String])

	var red := Regions.RED
	_add(MetaUpgrade.make(GENERATOR_CHANCE, "Generator chance",
		"+20% chance a cell is a generator.", red, GENERATOR_CHANCE_MAX,
		GENERATOR_CHANCE_COST, GENERATOR_CHANCE_GROWTH), GROUP_ECONOMY)
	_add_unlock(red, NodeCatalog.PULSE, PULSE_UNLOCK_COST)
	_add_power(red, POWER_COST)
	_add_level(red, NodeCatalog.PULSE, PULSE_LEVEL_COST)
	_add(MetaUpgrade.make(RAM_UNLOCK, "Ram",
		"Bank ram damage. The Power hex throws it.", red, 1, RAM_UNLOCK_COST, 100),
		GROUP_RAM)
	_add(MetaUpgrade.make(RAM_POWER, "Ram power", "+25% ram damage.", red,
		RAM_POWER_MAX, RAM_POWER_COST, RAM_POWER_GROWTH), GROUP_RAM)

	var orange := Regions.ORANGE
	_add_power(orange)
	_add_strength(orange, GROUP_POWER, ORB_MULTIPLIER, "Orb value ×2", "Orbs are worth ×2.")
	_add_unlock(orange, NodeCatalog.CRIT)
	_add_level(orange, NodeCatalog.CRIT)
	_add_strength(orange, GROUP_CRIT, CRIT_MULTIPLIER, "Crit multiplier",
		"Crits are worth +1x more.")

	var yellow := Regions.YELLOW
	_add_power(yellow)
	_add_unlock(yellow, NodeCatalog.BOUNCE, BOUNCE_UNLOCK_COST)
	_add(MetaUpgrade.make(node_level_key(NodeCatalog.BOUNCE), "Bounce level",
		"Start runs with +1 bounce.", yellow, MetaUpgrade.UNCAPPED,
		BOUNCE_LEVEL_COST, BOUNCE_GROWTH), GROUP_BOUNCE)
	_add(MetaUpgrade.make(BOUNCE_STRENGTH, "Bounce strength",
		"Bounces keep +5% more value.", yellow, BOUNCE_STRENGTH_MAX,
		BOUNCE_STRENGTH_COST, BOUNCE_STRENGTH_GROWTH), GROUP_BOUNCE)
	_add(MetaUpgrade.make(BOUNCE_SKILL, "Glaive skill",
		"The Bounce skill adds +1 more bounce.", yellow, MetaUpgrade.UNCAPPED,
		BOUNCE_SKILL_COST, BOUNCE_GROWTH), GROUP_BOUNCE)
	_add(MetaUpgrade.make(RAM_BOUNCE, "Ram bounce", "The ram bounces like an orb.",
		yellow, 1, BOUNCE_UNLOCK_COST * RAM_PRICE_MULTIPLIER, 100), GROUP_RAM)

	var green := Regions.GREEN
	_add_power(green)
	_add_unlock(green, NodeCatalog.SPLASH)
	_add_level(green, NodeCatalog.SPLASH)
	_add_strength(green, GROUP_SPLASH, SPLASH_STRENGTH, "Splash strength",
		"Splashes hit for +25% more.")
	_add(MetaUpgrade.make(SPLASH_BOUNCE, "Splashing bounces",
		"Bounces can splash too.", green, 1,
		_block_price(green, UNLOCK_PRICE_CELLS), 100), GROUP_SPLASH)
	var ram_card_cost := _block_price(green, UNLOCK_PRICE_CELLS) * RAM_PRICE_MULTIPLIER
	_add(MetaUpgrade.make(RAM_SPLASH, "Ram splash", "The ram can splash like an orb.",
		green, 1, ram_card_cost, 100), GROUP_RAM)
	_add(MetaUpgrade.make(RAM_SPLASH_BOUNCE, "Ram splashing bounces",
		"Ram bounces can splash too.", green, 1, ram_card_cost, 100), GROUP_RAM)

	_add_power(Regions.TEAL)
	_add_strength(Regions.TEAL, GROUP_POWER, OVERCHARGE, "Overcharge",
		"+1% orb value per generator.")

	_add_power(Regions.BLUE)
	_add_strength(Regions.BLUE, GROUP_RAM, RAM_CHARGE, "Ram charge",
		"Ram banks +5% more of each cell.", RAM_CHARGE_MAX)

	_add_power(Regions.PURPLE)
	_add_strength(Regions.PURPLE, GROUP_ECONOMY, BOUNTY, "Bounty",
		"+10% currency from mined cells.")


## A multiple of the block's price unit: 2,048 in orange, ×25 per colour.
static func _block_price(region: int, cells: int) -> int:
	var unit := PRICE_UNIT_FIRST
	for _i in maxi(region - 1, 0):
		unit *= PRICE_UNIT_GROWTH
	return unit * cells


static func _group_of(node_id: String) -> int:
	match node_id:
		NodeCatalog.PULSE:
			return GROUP_SPEED
		NodeCatalog.CRIT:
			return GROUP_CRIT
		NodeCatalog.BOUNCE:
			return GROUP_BOUNCE
		NodeCatalog.SPLASH:
			return GROUP_SPLASH
	return GROUP_POWER


static func _add_power(region: int, cost: int = -1) -> void:
	if cost < 0:
		cost = _block_price(region, POWER_PRICE_CELLS)
	var amount := NodeCatalog.levels_in_region(NodeCatalog.YIELD, region)
	_add(MetaUpgrade.make(node_level_key(NodeCatalog.YIELD, region),
		"Power +%d" % amount, "Start runs with +%d orb value." % amount, region,
		MetaUpgrade.UNCAPPED, cost, _level_growth(region)), GROUP_POWER)


static func _add_unlock(region: int, node_id: String, cost: int = -1) -> void:
	if cost < 0:
		cost = _block_price(region, UNLOCK_PRICE_CELLS)
	var type := NodeCatalog.get_type(node_id)
	_add(MetaUpgrade.make(unlock_key(node_id), "Unlock %s" % type.display_name,
		"%s nodes appear on the board." % type.display_name, region, 1, cost, 100),
		_group_of(node_id))


static func _add_level(region: int, node_id: String, cost: int = -1) -> void:
	if cost < 0:
		cost = _block_price(region, LEVEL_PRICE_CELLS)
	var type := NodeCatalog.get_type(node_id)
	var common := type.rarity == NodeType.COMMON
	var capped := not common and node_id != NodeCatalog.CRIT
	_add(MetaUpgrade.make(node_level_key(node_id), "%s level" % type.display_name,
		"Start runs with +1 %s." % type.display_name, region,
		CHANCE_LEVELS_MAX if capped else MetaUpgrade.UNCAPPED, cost,
		_level_growth(region) if common else CHANCE_LEVEL_GROWTH), _group_of(node_id))


static func _level_growth(region: int) -> int:
	return RED_LEVEL_GROWTH if region == Regions.RED else LEVEL_GROWTH


static func _add_strength(region: int, group: int, key: String, name: String,
		description: String, max_level: int = MetaUpgrade.UNCAPPED) -> void:
	_add(MetaUpgrade.make(key, name, description, region, max_level,
		_block_price(region, STRENGTH_PRICE_CELLS), STRENGTH_GROWTH), group)


static func _add(upgrade: MetaUpgrade, group: int) -> void:
	upgrade.group = group
	_upgrades[upgrade.key] = upgrade
	_order.append(upgrade.key)
	_by_group[group].append(upgrade.key)


static func get_upgrade(key: String) -> MetaUpgrade:
	_build()
	return _upgrades.get(key)


static func has(key: String) -> bool:
	_build()
	return _upgrades.has(key)


## Every upgrade in declaration order.
static func all() -> Array[String]:
	_build()
	return _order


## One type group, red to purple, in the order the shop draws it.
static func in_group(group: int) -> Array[String]:
	_build()
	return _by_group[group]
