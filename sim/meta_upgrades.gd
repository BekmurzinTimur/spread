class_name MetaUpgrades

## Every ascension purchase, grouped into one block per colour. Built once,
## static, never mutated, and the only sanctioned way to name an upgrade.
##
## Every block sells a Power tier and one unique; "Mine <colour>" lives in the
## block before the colour it opens.
##
## ⚠️ Keys are save keys and must never be renamed. A buff-unlock key is also the
## `NodeType.unlock_key` it releases.

const GENERATOR_CHANCE := "generator_chance"
const RAM_POWER := "ram_power"
const VISION := "vision"
const CRIT_MULTIPLIER := "crit_multiplier"
const SPLASH_STRENGTH := "splash_strength"
const OVERCHARGE := "overcharge"
const RAM_CHARGE := "ram_charge"
const BOUNTY := "bounty"

const REGION_KEYS: PackedStringArray = [
	"region_red", "region_orange", "region_yellow", "region_green",
	"region_teal", "region_blue", "region_purple",
]

## Saves written before regions were named keep their "Mine <colour>" purchases.
const LEGACY_REGION_PREFIX := "band_"


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

## Ten levels take the chance from 0% to 100%. The first level must stay within
## what a stalled run 1 banks — `test_run_one_funds_the_first_purchase`.
const GENERATOR_CHANCE_COST := 100
const GENERATOR_CHANCE_GROWTH := 150
const GENERATOR_CHANCE_MAX := 10

## Red is hand-priced.
const PULSE_UNLOCK_COST := 300
const POWER_COST := 200
const PULSE_LEVEL_COST := 250
const RAM_POWER_COST := 500
const RAM_POWER_GROWTH := 180
const VISION_COST := 400
const VISION_GROWTH := 200

## Past red, prices are this share of what clearing the previous region pays.
const POWER_PRICE_PERCENT := 10
const UNLOCK_PRICE_PERCENT := 75
const LEVEL_PRICE_PERCENT := 45
const STRENGTH_PRICE_PERCENT := 120

const LEVEL_GROWTH := 160
const STRENGTH_GROWTH := 200

## "Mine <region>" costs this share of what clearing the region before it pays.
const REGION_PRICE_PERCENT := 50

static var _upgrades: Dictionary = {}
static var _order: Array[String] = []
static var _by_region: Array = []


static func _build() -> void:
	if not _upgrades.is_empty():
		return
	for region in Regions.COUNT:
		_by_region.append([] as Array[String])

	var red := Regions.RED
	_add(MetaUpgrade.make(GENERATOR_CHANCE, "Generator chance",
		"+10% chance a cell is a generator.", red, GENERATOR_CHANCE_MAX,
		GENERATOR_CHANCE_COST, GENERATOR_CHANCE_GROWTH))
	_add_unlock(red, NodeCatalog.PULSE, PULSE_UNLOCK_COST)
	_add_power(red, POWER_COST)
	_add_level(red, NodeCatalog.PULSE, PULSE_LEVEL_COST)
	_add(MetaUpgrade.make(RAM_POWER, "Ram power", "+25% ram damage.", red,
		MetaUpgrade.UNCAPPED, RAM_POWER_COST, RAM_POWER_GROWTH))
	_add(MetaUpgrade.make(VISION, "Vision", "+1 hop of sight.", red,
		MetaUpgrade.UNCAPPED, VISION_COST, VISION_GROWTH))
	_add_region(Regions.ORANGE)

	var orange := Regions.ORANGE
	_add_power(orange)
	_add_unlock(orange, NodeCatalog.CRIT)
	_add_level(orange, NodeCatalog.CRIT)
	_add_strength(orange, CRIT_MULTIPLIER, "Crit multiplier",
		"Crits are worth +1x more.")
	_add_region(Regions.YELLOW)

	var yellow := Regions.YELLOW
	_add_power(yellow)
	_add_unlock(yellow, NodeCatalog.SPLIT)
	_add_level(yellow, NodeCatalog.SPLIT)
	_add_region(Regions.GREEN)

	var green := Regions.GREEN
	_add_power(green)
	_add_unlock(green, NodeCatalog.SPLASH)
	_add_level(green, NodeCatalog.SPLASH)
	_add_strength(green, SPLASH_STRENGTH, "Splash strength",
		"Splashes hit for +25% more.")
	_add_region(Regions.TEAL)

	_add_power(Regions.TEAL)
	_add_strength(Regions.TEAL, OVERCHARGE, "Overcharge",
		"+1% orb value per 100 generators.")
	_add_region(Regions.BLUE)

	_add_power(Regions.BLUE)
	_add_strength(Regions.BLUE, RAM_CHARGE, "Ram charge",
		"Ram banks +5% more of each cell.")
	_add_region(Regions.PURPLE)

	_add_power(Regions.PURPLE)
	_add_strength(Regions.PURPLE, BOUNTY, "Bounty",
		"+10% currency from mined cells.")


## A share of what clearing the region before this one pays.
static func _block_price(region: int, percent: int) -> int:
	return HexMap.region_value(region - 1) * percent / 100


static func _add_power(region: int, cost: int = -1) -> void:
	if cost < 0:
		cost = _block_price(region, POWER_PRICE_PERCENT)
	var amount := NodeCatalog.levels_in_region(NodeCatalog.YIELD, region)
	_add(MetaUpgrade.make(node_level_key(NodeCatalog.YIELD, region),
		"Power +%d" % amount, "Start runs with +%d orb value." % amount, region,
		MetaUpgrade.UNCAPPED, cost, LEVEL_GROWTH))


static func _add_unlock(region: int, node_id: String, cost: int = -1) -> void:
	if cost < 0:
		cost = _block_price(region, UNLOCK_PRICE_PERCENT)
	var type := NodeCatalog.get_type(node_id)
	_add(MetaUpgrade.make(unlock_key(node_id), "Unlock %s" % type.display_name,
		"%s nodes appear on the board." % type.display_name, region, 1, cost, 100))


static func _add_level(region: int, node_id: String, cost: int = -1) -> void:
	if cost < 0:
		cost = _block_price(region, LEVEL_PRICE_PERCENT)
	var type := NodeCatalog.get_type(node_id)
	_add(MetaUpgrade.make(node_level_key(node_id), "%s level" % type.display_name,
		"Start runs with +1 %s." % type.display_name, region,
		MetaUpgrade.UNCAPPED, cost, LEVEL_GROWTH))


static func _add_strength(region: int, key: String, name: String,
		description: String) -> void:
	_add(MetaUpgrade.make(key, name, description, region, MetaUpgrade.UNCAPPED,
		_block_price(region, STRENGTH_PRICE_PERCENT), STRENGTH_GROWTH))


## Sold in the block before the region it opens.
static func _add_region(region: int) -> void:
	var name := Regions.name_of(region)
	_add(MetaUpgrade.make(region_key(region), "Mine %s" % name,
		"Frontier and ram may mine %s." % name, region - 1, 1,
		HexMap.region_value(region - 1) * REGION_PRICE_PERCENT / 100, 100))


static func _add(upgrade: MetaUpgrade) -> void:
	_upgrades[upgrade.key] = upgrade
	_order.append(upgrade.key)
	_by_region[upgrade.region].append(upgrade.key)


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


## One colour block, in the order the shop draws it.
static func in_region(region: int) -> Array[String]:
	_build()
	return _by_region[region]
