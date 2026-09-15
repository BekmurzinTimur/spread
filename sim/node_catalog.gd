class_name NodeCatalog

## Every buff type, in one place.
##
## Power and Speed are **additive** and keep the baseline moving; Crit, Splash and
## Bounce are **multiplicative** and are what let you outrun the cost curve. They sit
## in different rarity tables on purpose — see the dilution rule in `HexMap`.
##
## ⚠️ **The id strings are save keys and must never be renamed.** `MetaState.levels`
## is keyed by `unlock_<id>` / `level_<id>`, and `MetaState.from_dict` silently
## drops keys `MetaUpgrades` does not recognise — so renaming `"yield"` would wipe
## every player's purchases with no error anywhere. `display_name` is presentation
## only and is the safe half to change, which is why the two have drifted apart.

const YIELD := "yield"
const PULSE := "pulse"
const CRIT := "crit"
const BOUNCE := "bounce"
const SPLASH := "splash"

## What one node of each type is worth. Levels stack for the whole run.
const YIELD_PER_LEVEL := 1      # +1 orb value
const PULSE_PER_LEVEL := 5     # +10% increased emission rate
const SPLASH_PER_LEVEL := 500   # +5% chance an orb splashes its target's neighbours
# Bounce: +1 bounce per level, keystone-only.

## Crit chance has diminishing returns toward the cap, in Rng.SCALE units.
## Level 1 is 5%, level 9 is 25%.
const CRIT_CHANCE_CAP := 5000
const CRIT_HALF_LEVELS := 9


static func crit_chance(levels: int) -> int:
	if levels <= 0:
		return 0
	return CRIT_CHANCE_CAP * levels / (levels + CRIT_HALF_LEVELS)


## Node tiers, as the glow sizes them. 0 is no node.
const TIER_COMMON := 1
const TIER_RARE := 2
const TIER_KEYSTONE := 3

## A keystone grants this many levels of a non-Power type at once.
const KEYSTONE_LEVELS := 10

## Power levels one node, or one shop purchase, is worth in each region.
const POWER_BY_REGION: PackedInt32Array = [
	1, 10, 100, 1e3, 1e4, 1e5, 1e6,
]

## A Power node multiplies its region's Power by its tier: none, common, rare, keystone.
const POWER_BY_TIER: PackedInt32Array = [0, 1, 3, 30]

static var _types: Dictionary = {}
static var _by_rarity: Dictionary = {}


static func _build() -> void:
	if not _types.is_empty():
		return
	var all: Array[NodeType] = [
		NodeType.make(YIELD, "Power", NodeType.COMMON, ""),
		NodeType.make(PULSE, "Speed", NodeType.COMMON, "unlock_pulse"),
		NodeType.make(CRIT, "Crit", NodeType.RARE, "unlock_crit"),
		NodeType.make(BOUNCE, "Bounce", NodeType.KEYSTONE, "unlock_bounce"),
		NodeType.make(SPLASH, "Splash", NodeType.RARE, "unlock_splash"),
	]
	_by_rarity = {NodeType.COMMON: [], NodeType.RARE: [], NodeType.KEYSTONE: []}
	for type in all:
		_types[type.id] = type
		_by_rarity[type.rarity].append(type)


## Levels one node of this type grants in a region. Only Power scales; chances
## would saturate.
static func levels_in_region(id: String, region: int) -> int:
	return POWER_BY_REGION[region] if id == YIELD else 1


## Levels a found node grants, by tier and region.
static func grant(id: String, tier: int, region: int) -> int:
	if id == YIELD:
		return POWER_BY_TIER[tier] * POWER_BY_REGION[region]
	if id == BOUNCE:
		return 1
	return KEYSTONE_LEVELS if tier == TIER_KEYSTONE else 1


static func get_type(id: String) -> NodeType:
	_build()
	return _types.get(id)


static func ids() -> Array:
	_build()
	return _types.keys()


## Every type of one rarity, in a fixed order. Filtered to what the player has
## bought, because a type does not appear on the board until it is unlocked.
static func unlocked_of_rarity(rarity: int, meta: MetaState) -> Array:
	_build()
	var out: Array[NodeType] = []
	for type in _by_rarity[rarity]:
		if meta == null or meta.is_unlocked(type.unlock_key):
			out.append(type)
	return out
