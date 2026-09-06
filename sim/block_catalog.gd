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
	generator.color = Tiers.color_of(Tiers.RED)
	generator.needs_target = true
	generator.produce_interval = 20
	generator.output_tier = Tiers.RED
	generator.behavior = GeneratorBehavior.new()
	_register(generator)

	var pump := BlockDef.new()
	pump.id = PUMP
	pump.display_name = "Pump"
	pump.description = "Restores orbs passing through back to full value."
	pump.color = Color("35c6c0")
	pump.needs_target = false
	pump.restore_amount = 10
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
