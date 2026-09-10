class_name NodeCatalog

## Every buff type, in one place.
##
## Power and Speed are **additive** and keep the baseline moving; Crit and Split
## are **multiplicative** and are what let you outrun the cost curve. They sit in
## different rarity tables on purpose — see the dilution rule in `HexMap`.
##
## ⚠️ **The id strings are save keys and must never be renamed.** `MetaState.levels`
## is keyed by `unlock_<id>` / `level_<id>`, and `MetaState.from_dict` silently
## drops keys `MetaUpgrades` does not recognise — so renaming `"yield"` would wipe
## every player's purchases with no error anywhere. `display_name` is presentation
## only and is the safe half to change, which is why the two have drifted apart.

const YIELD := "yield"
const PULSE := "pulse"
const CRIT := "crit"
const SPLIT := "split"

## What one node of each type is worth. Levels stack for the whole run.
const YIELD_PER_LEVEL := 1      # +1 orb value
const PULSE_PER_LEVEL := 10     # +10% increased emission rate
const CRIT_PER_LEVEL := 500     # +5% chance of a x5 orb, in Rng.SCALE units
const SPLIT_PER_LEVEL := 500    # +5% chance a cell emits two orbs

## A keystone grants this many levels of one type at once.
const KEYSTONE_LEVELS := 3

static var _types: Dictionary = {}
static var _by_rarity: Dictionary = {}


static func _build() -> void:
	if not _types.is_empty():
		return
	var all: Array[NodeType] = [
		NodeType.make(YIELD, "Power", NodeType.COMMON, ""),
		NodeType.make(PULSE, "Speed", NodeType.COMMON, "unlock_pulse"),
		NodeType.make(CRIT, "Crit", NodeType.RARE, "unlock_crit"),
		NodeType.make(SPLIT, "Split", NodeType.RARE, "unlock_split"),
	]
	_by_rarity = {NodeType.COMMON: [], NodeType.RARE: []}
	for type in all:
		_types[type.id] = type
		_by_rarity[type.rarity].append(type)


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
