class_name BlockCatalog

## Every block type in the game, in one place.
##
## Adding a block type is two edits: a behaviour script under sim/behaviors/,
## and an entry here. Nothing in World or the tick changes.

const GENERATOR := "generator"
const PUMP := "pump"
const SPHERE := "sphere"

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

	var sphere := BlockDef.new()
	sphere.id = SPHERE
	sphere.display_name = "Sphere"
	sphere.description = "Radiates a bonus to every block within 2 hops: faster generators, stronger pumps."
	# Like the pump, a sphere carries no tier of its own — it modifies whatever is
	# near it, whatever colour that turns out to be — so its colour sits outside
	# the tier ramp and away from the pump's teal.
	sphere.color = Color("9d8cf5")
	sphere.icon_path = "res://assets/expand.svg"
	sphere.needs_target = false
	# Flat and additive, so spheres stack the way pumps do: a block reached by two
	# of them gets both bonuses. A saturating field would make the second sphere
	# you place worth nothing, which is the mistake the pump already avoids.
	#
	# The eventual rule is "everything *weaker* than them nearby", but that needs a
	# second tier to compare against — with only RED in the game it is a condition
	# nothing can fail. The tier gate lands with the upgrader.
	sphere.field_radius = 2
	sphere.field_interval_bonus = -4
	sphere.field_restore_bonus = 1
	sphere.behavior = SphereBehavior.new()
	_register(sphere)


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
