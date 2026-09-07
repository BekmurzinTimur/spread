class_name BlockCatalog

## Every block type in the game, in one place.
##
## Adding a block type is two edits: a behaviour script under sim/behaviors/,
## and an entry here. Nothing in World or the tick changes.

const GENERATOR := "generator"
const PUMP := "pump"
const SPHERE := "sphere"
const UPGRADER := "upgrader"
const UPKEEP := "upkeep"

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

	var upkeep := BlockDef.new()
	upkeep.id = UPKEEP
	upkeep.display_name = "Upkeep"
	upkeep.description = "Burns 1 red per tick from its bank. While fuelled, every generator on the board runs 25% faster."
	upkeep.needs_target = false
	# Movable, unlike a challenge, and that is the point of the type. A challenge
	# is anchored because its bonus reaches everywhere from anywhere; this one has
	# to be fed, so where it sits — next to a generator that can spare the output —
	# is a real decision.
	upkeep.movable = true
	upkeep.input_tier = Tiers.RED
	# 1 per tick against a generator's 10 per 20 ticks: one upkeep block costs the
	# output of two dedicated generators. It has to be a commitment, or holding
	# one up is a formality rather than a trade.
	upkeep.upkeep_drain = 1
	# 200 ticks of dwell at that drain — 20 seconds, still over a second at 16x,
	# so the bonus never flickers. Also the cold-start price: 20 orbs before it
	# lights up at all.
	upkeep.upkeep_reserve = 200
	# Deliberately the same number as the sphere's field bonus, and it stays that
	# way now both are rates. An upkeep block is a sphere for the whole board, as
	# long as you keep paying for it. At 20 -> 16 a generator goes from 0.500 to
	# 0.625 value per tick, so it pays for its own drain at four aimed generators
	# — a real mid-game unlock on a board of ten, not free and not impossible.
	#
	# Summed with any sphere field before the one division, so two of these lit
	# beside a sphere is +75% and 20 -> 11, rather than three separate divisions.
	upkeep.global_rate_percent = 25
	# Its own hue: not a tier colour (it emits nothing), not the pump's teal, not
	# the sphere's violet.
	upkeep.color = Color("d97f4a")
	upkeep.icon_path = "res://assets/lightning-frequency.svg"
	upkeep.behavior = UpkeepBehavior.new()
	_register(upkeep)

	var pump := BlockDef.new()
	pump.id = PUMP
	pump.display_name = "Pump"
	pump.description = "Adds +20% of an orb's launch value on the way through. Stacks along a route."
	# A pump carries no tier of its own — it is a path modifier, and anything of
	# any colour may pass through it — so it keeps a colour outside the tier ramp.
	pump.color = Color("35c6c0")
	pump.icon_path = "res://assets/growth.svg"
	pump.needs_target = false
	# A percentage of the orb's launch value, uncapped, so pumps stack — and it is
	# summed across pumps rather than compounded, so the order they sit in on a
	# route cannot matter. On a plain 10-value orb this is +2, so a pump cell nets
	# +1 (decay first, then this) against a plain cell's -1: a line sustains itself
	# indefinitely only if its pumps sit two hops apart or closer.
	#
	# Percentage rather than flat so a pump is worth more on a richer orb — a
	# mined Surge now buys reach twice, once at the generator and again at every
	# pump on the route.
	pump.restore_percent = 20
	pump.behavior = PumpBehavior.new()
	_register(pump)

	var sphere := BlockDef.new()
	sphere.id = SPHERE
	sphere.display_name = "Sphere"
	sphere.description = "Radiates a bonus to every block within 2 hops: 25% faster generators and upgraders, stronger pumps."
	# Like the pump, a sphere carries no tier of its own — it modifies whatever is
	# near it, whatever colour that turns out to be — so its colour sits outside
	# the tier ramp and away from the pump's teal.
	sphere.color = Color("9d8cf5")
	sphere.icon_path = "res://assets/sphere.svg"
	sphere.needs_target = false
	# Additive, so spheres stack the way pumps do: a block reached by two of them
	# gets both bonuses. A saturating field would make the second sphere
	# you place worth nothing, which is the mistake the pump already avoids.
	#
	# The eventual rule is "everything *weaker* than them nearby", but that needs a
	# second tier to compare against — with only RED in the game it is a condition
	# nothing can fail. The tier gate lands with the upgrader.
	sphere.field_radius = 2
	# An *increased rate*, not a tick discount, so this stacks forever without
	# ever reaching zero — see StatBonus.apply_rate(). 25 is chosen to reproduce
	# the flat -4 it replaced exactly: on a base of 20 the first sphere still
	# gives 16. Only the tail changes, from a hard stop at four spheres to a
	# curve that keeps paying: 16, 13, 11, 10, 8...
	sphere.field_rate_percent = 25
	# The same treatment for a converter, whose clock is denominated in delivered
	# value rather than ticks: 60 -> 48 -> 40 -> 34, approaching 1 and never 0.
	#
	# Its own number rather than a second reader of `field_rate_percent`. A
	# sphere used to do nothing at all for an upgrader, and the reason given was
	# that a discount would be a third field axis worth deciding on its own — so
	# it gets one, and the two can be tuned apart.
	sphere.field_charge_percent = 25
	# Percentage points, since that is the unit a pump's restore is in now: this
	# takes one from 20% to 30%, which is +1 on a plain orb exactly as the old
	# flat bonus was. Ten rather than five so two spheres are visibly worth more
	# than one — at five, the ceiling rounding would swallow the second.
	sphere.field_restore_percent = 10
	sphere.behavior = SphereBehavior.new()
	_register(sphere)

	# --- Challenges -----------------------------------------------------
	#
	# All three are anchored, aim at nothing, produce nothing and restore
	# nothing, and convert nothing. That last part is not an oversight: it is what
	# makes them immune to a sphere for free. `effective_interval()`,
	# `effective_restore_percent()` and `effective_upgrade_cost()` all bail on
	# their `base <= 0` guard, so a sphere's field lands on the cell and finds
	# nothing to change. A flag saying "ignores fields" would be a second way to
	# spell a rule the numbers already enforce.
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
	current.description = "Every pump on the board restores +20% more."
	current.color = Color("35c6c0")
	current.icon_path = CHALLENGE_ICON
	current.needs_target = false
	current.movable = false
	current.is_challenge = true
	# Percentage points, and deliberately the pump's own base again: mining a
	# Current doubles what every pump on the board is worth rather than adding a
	# fixed number of points to it.
	current.global_field_restore_percent = 20
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
