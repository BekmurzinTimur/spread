class_name BlockCatalog

## Every block type in the game, in one place.
##
## Adding a block type is two edits: a behaviour script under sim/behaviors/,
## and an entry here. Nothing in World or the tick changes.

const GENERATOR := "generator"
const PUMP := "pump"

static var _defs: Dictionary = {}
static var _order: PackedStringArray = PackedStringArray()


static func _ensure_built() -> void:
	if not _defs.is_empty():
		return

	var generator := BlockDef.new()
	generator.id = GENERATOR
	generator.display_name = "Generator"
	generator.description = "Emits a full orb at its aimed target on a fixed interval."
	generator.needs_target = true
	# Anchored: found where the map buried it, and never moved after. See
	# BlockDef.movable for why the game falls apart without this.
	generator.movable = false
	generator.produce_interval = 20
	generator.output_tier = Tiers.RED
	# Taken from the tier rather than hardcoded, so a generator added for a
	# higher tier is painted in that tier's colour without a second edit.
	generator.color = Tiers.color_of(generator.output_tier)
	generator.icon_path = "res://assets/lightning-frequency.svg"
	generator.behavior = GeneratorBehavior.new()
	_register(generator)

	var pump := BlockDef.new()
	pump.id = PUMP
	pump.display_name = "Pump"
	pump.description = "Adds a flat +3 to orbs passing through. Stacks along a route."
	# A pump carries no tier of its own — it is a path modifier, and anything of
	# any colour may pass through it — so it keeps a colour outside the tier ramp.
	pump.color = Color("35c6c0")
	pump.icon_path = "res://assets/growth.svg"
	pump.needs_target = false
	# Flat and uncapped, so pumps stack. A pump cell nets +2 (decay first, then
	# this), a plain cell -1 — so a line only sustains itself indefinitely if its
	# pumps sit three hops apart or closer.
	pump.restore_amount = 3
	pump.behavior = PumpBehavior.new()
	_register(pump)


static func _register(def: BlockDef) -> void:
	_defs[def.id] = def
	_order.append(def.id)


static func get_def(id: String) -> BlockDef:
	_ensure_built()
	if _defs.has(id):
		return _defs[id]
	return null


static func has_def(id: String) -> bool:
	_ensure_built()
	return _defs.has(id)


## Declaration order, for stable UI listing.
static func ids() -> PackedStringArray:
	_ensure_built()
	return _order
