class_name BlockCatalog

## Every block type in the game, in one place.
##
## Adding a block type is two edits: a behaviour script under sim/behaviors/,
## and an entry here. Nothing in World or the tick changes.

const GENERATOR := "generator"
const PUMP := "pump"
const SPHERE := "sphere"
const UPGRADER := "upgrader"

# The three challenges. Each is buried exactly once, and `tools/gen_map.py`
# asserts both the uniqueness and the order: Surge sits nearest the start and
# Lens furthest, so they arrive as milestones rather than all at once.
const CHALLENGE_SURGE := "challenge_surge"
const CHALLENGE_CURRENT := "challenge_current"
const CHALLENGE_LENS := "challenge_lens"

## One glyph for all three. A challenge is announced by its silhouette — the
## board draws it as a triangle — and told apart by colour, so a shared icon is
## the honest picture: what they have in common is what the player sees first.
const CHALLENGE_ICON := "res://assets/expand.svg"

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

	var upgrader := BlockDef.new()
	upgrader.id = UPGRADER
	upgrader.display_name = "Upgrader"
	upgrader.description = "Banks 60 delivered red, then launches one orange orb at its target."
	upgrader.needs_target = true
	# Anchored, like a generator. A movable converter parked beside the frontier
	# would make the orange leg of every route one hop long, which is the same
	# collapse movable generators caused for red.
	upgrader.movable = false
	# No interval: the clock is the player's red line. `upgrade_cost` is the
	# cooldown, denominated in delivered value instead of ticks.
	upgrader.produce_interval = 0
	upgrader.input_tier = Tiers.RED
	upgrader.output_tier = Tiers.ORANGE
	upgrader.upgrade_cost = 60
	# Painted by what it emits, on the generator's precedent — a source is its
	# output colour, whatever fills it.
	upgrader.color = Tiers.color_of(upgrader.output_tier)
	upgrader.icon_path = "res://assets/upgrade.svg"
	upgrader.behavior = UpgraderBehavior.new()
	_register(upgrader)

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
	sphere.icon_path = "res://assets/sphere.svg"
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

	# --- Challenges -----------------------------------------------------
	#
	# All three are anchored, aim at nothing, produce nothing and restore
	# nothing. That last part is not an oversight: it is what makes them immune
	# to a sphere for free. `effective_interval()` and `effective_restore()` both
	# bail on their `base <= 0` guard, so a sphere's field lands on the cell and
	# finds nothing to change. A flag saying "ignores fields" would be a second
	# way to spell a rule the numbers already enforce.
	#
	# They are anchored for a different reason than the generator is. A generator
	# has to stay put because moving it would trivialise decay; a challenge has
	# nothing to trivialise, because its bonus reaches the whole board from
	# anywhere. Making it movable would add a chore, not a choice.

	var surge := BlockDef.new()
	surge.id = CHALLENGE_SURGE
	surge.display_name = "Surge"
	surge.description = "Every generator on the board launches its orbs with +5 value."
	surge.color = Color("e0a850")
	surge.icon_path = CHALLENGE_ICON
	surge.needs_target = false
	surge.movable = false
	surge.is_challenge = true
	surge.global_orb_value_bonus = 5
	surge.behavior = ChallengeBehavior.new()
	_register(surge)

	var current := BlockDef.new()
	current.id = CHALLENGE_CURRENT
	current.display_name = "Current"
	current.description = "Every pump on the board restores +2 more."
	current.color = Color("35c6c0")
	current.icon_path = CHALLENGE_ICON
	current.needs_target = false
	current.movable = false
	current.is_challenge = true
	current.global_field_restore_bonus = 2
	current.behavior = ChallengeBehavior.new()
	_register(current)

	var lens := BlockDef.new()
	lens.id = CHALLENGE_LENS
	lens.display_name = "Lens"
	lens.description = "Every sphere on the board reaches 50% further."
	lens.color = Color("9d8cf5")
	lens.icon_path = CHALLENGE_ICON
	lens.needs_target = false
	lens.movable = false
	lens.is_challenge = true
	# The only multiplicative buff in the game. At the sphere's radius of 2 this
	# buys exactly one hop — 2 -> 3 — because GlobalBonus.scale_percent truncates
	# and a radius is a whole number of hops or nothing.
	lens.global_field_radius_percent = 50
	lens.behavior = ChallengeBehavior.new()
	_register(lens)


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
