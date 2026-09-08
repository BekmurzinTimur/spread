class_name BlockCatalog

## Every block type in the game, in one place.
##
## Adding a block type is two edits: a behaviour script under sim/behaviors/,
## and an entry here. Nothing in World or the tick changes.

## The red generator and the red -> orange upgrader, which are what a test or a
## caller means when it says "a generator" without qualifying it. Aliases into
## the families below rather than types of their own: there is one generator per
## tier and one upgrader per step up the ladder, and nothing outside these two
## constants should name a family member literally — use `generator_id()` and
## `upgrader_id()`.
const GENERATOR := "generator_red"
const UPGRADER := "upgrader_orange"

const PUMP := "pump"
const SPHERE := "sphere"
const UPKEEP := "upkeep"
const AMPLIFIER := "amplifier"

# The three challenges. One of each is buried in every colour band, and
# `tools/gen_map.py` asserts both that and the order: within a band they are
# interchangeable, but a band never gets two of the same.
const CHALLENGE_SURGE := "challenge_surge"
const CHALLENGE_CURRENT := "challenge_current"
const CHALLENGE_LENS := "challenge_lens"

## Blocks that carry no tier of their own are painted from a neutral ramp, and
## these are the whole of it. Colour on the board means exactly one thing — which
## resource tier is this — so a pump, a sphere and an upkeep block, which act on
## orbs of *any* colour, must not claim a hue. They are told apart by their glyph
## and by brightness instead.
const COLOR_PUMP := Color("b9c2cf")
const COLOR_SPHERE := Color("8f97a6")
const COLOR_UPKEEP := Color("dde2e9")
const COLOR_AMPLIFIER := Color("a4adbb")
const COLOR_TELEPORTER := Color("c8d0dc")

## How many teleport pairs the catalog registers. Each is **one def buried twice**
## — both ends share a `link_group` by sharing a definition — so this is a count
## of defs, and `tools/gen_map.py` places two cells for every one of them.
const TELEPORTER_PAIRS := 3

## How much an amplifier multiplies an orb it passes: 50 means ×1.5, so two are
## ×2.25 and the curve is super-linear in the number passed rather than in
## distance. The counterpart to the pump's `restore_percent`, and the one
## compounding term in the economy.
##
## ⚠️ **Economy-wide, not per-def, and `World._apply_amplifiers` reads it from
## here rather than off the block.** An orb carries a count of the amplifiers it
## crossed, not a running value — that is what makes arrival independent of the
## order it met them — so by the time the exponent is spent there is no def to ask.
## Every amplifying def must therefore carry this same number, which
## `test_amplifiers_share_one_percent` holds.
const AMPLIFY_PERCENT := 50

## Delivered value that buys one orb of the next tier up, the same at every step
## of the ladder. `tools/gen_map.py` duplicates this number — see the warning
## beside its copy.
const UPGRADE_COST := 60

## Delivered value a compressor banks before launching it back as **one orb worth
## all of it**, the same at every colour.
##
## Ten ordinary orbs in, one 100-value orb out. Decay is charged per orb rather
## than per unit of value, so that orb survives about a hundred hops where the ten
## that paid for it would each have died at eleven — which is the whole mechanic,
## and it is a consequence of the decay rule rather than a new one.
##
## The lever to pull if long hauls feel too cheap or too slow: raising it makes
## the block rarer to fire and further-reaching at once, since the bank is also
## the orb.
const COMPRESS_COST := 100

## How many outputs one distributor may feed at once.
##
## Four, matching `World.MAX_WAYPOINTS`, and for a related reason: it is a cap on
## how complicated one block's plan may get rather than an economy number. A
## distributor emits one orb per full bank however many ports it has, so more of
## them divide the same throughput rather than multiplying it — nothing here is
## load-bearing for the ledger.
const DISTRIBUTOR_PORTS := 4


## One glyph for all three. A challenge is announced by its silhouette — the
## board draws it as a triangle — so a shared icon is the honest picture: what
## they have in common is what the player sees first. The three are told apart by
## name in the panel, not on the board, which is the right amount of information
## while their effects are still placeholders.
const CHALLENGE_ICON := "res://assets/glowing-artifact.svg"

static var _defs: Dictionary = {}
static var _order: PackedStringArray = PackedStringArray()


## The generator that emits this tier, and the upgrader that converts *into* it.
## There is no upgrader into RED — nothing converts into the bottom of the ladder
## — so `upgrader_id(Tiers.RED)` names a block that does not exist, and
## `get_def()` answers null for it like any other unknown id.
static func generator_id(tier: int) -> String:
	return "generator_%s" % Tiers.name_of(tier)


static func upgrader_id(output_tier: int) -> String:
	return "upgrader_%s" % Tiers.name_of(output_tier)


## The compressor that banks and re-emits this tier. One per colour, because a
## compressor neither climbs nor descends the ladder — it takes a colour and gives
## the same colour back — so unlike the upgrader family there is one for red too.
static func compressor_id(tier: int) -> String:
	return "compressor_%s" % Tiers.name_of(tier)


## The distributor that relays this tier. One per colour, red included, for the
## compressor's reason: it hands back the colour it was given.
static func distributor_id(tier: int) -> String:
	return "distributor_%s" % Tiers.name_of(tier)


## The two ends of teleport pair `group` share this one def. Buried twice by the
## map, and linked by `World` once both cells are mined.
static func teleporter_id(group: int) -> String:
	return "teleporter_%d" % group


static func _ensure_built() -> void:
	if not _defs.is_empty():
		return

	# --- The generator family -------------------------------------------
	#
	# One per tier, and every one of them on the same interval. A colour is not
	# scarce because its generator is slow; it is scarce because of *where the map
	# buried it*, which is the same thing that makes red's placement matter. That
	# keeps the ladder a question about reach rather than about arithmetic.
	#
	# Built in a loop rather than written out seven times, so a tier added to
	# `Tiers` cannot arrive without the generator that emits it.
	for tier in Tiers.COUNT:
		var generator := BlockDef.new()
		generator.id = generator_id(tier)
		generator.display_name = "%s Generator" % Tiers.name_of(tier).capitalize()
		generator.description = "Emits a full %s orb at its aimed target on a fixed interval." \
			% Tiers.name_of(tier)
		generator.needs_target = true
		# Anchored: found where the map buried it, and never moved after. See
		# BlockDef.movable for why the game falls apart without this.
		generator.movable = false
		generator.produce_interval = 20
		generator.output_tier = tier
		# Taken from the tier rather than hardcoded, which is what lets one loop
		# paint all seven.
		generator.color = Tiers.color_of(tier)
		generator.icon_path = "res://assets/power-generator.svg"
		generator.behavior = GeneratorBehavior.new()
		_register(generator)

	# --- The upgrader family ---------------------------------------------
	#
	# One per step up the ladder, red -> orange through blue -> purple. With a
	# generator for every colour a converter is no longer *the* mint, and that is
	# the point of the type now: it is a **positional** source. Where the map
	# buried the two teal generators decides where teal is cheap; an upgrader is
	# how you make teal somewhere else, out of the red income you already have.
	#
	# Uniform `upgrade_cost` across the ladder, because with uniform generators
	# there is no scarcity ramp for it to mirror. It is the first number to
	# revisit if converters turn out not to be worth their red line.
	for tier in range(Tiers.RED + 1, Tiers.COUNT):
		var upgrader := BlockDef.new()
		upgrader.id = upgrader_id(tier)
		upgrader.display_name = "%s Upgrader" % Tiers.name_of(tier).capitalize()
		upgrader.description = "Banks %d delivered %s, then launches one %s orb at its target." \
			% [UPGRADE_COST, Tiers.name_of(tier - 1), Tiers.name_of(tier)]
		upgrader.needs_target = true
		# Anchored, like a generator. A movable converter parked beside the
		# frontier would make the upper leg of every route one hop long, which is
		# the same collapse movable generators caused for red.
		upgrader.movable = false
		# No interval: the clock is the player's line into it. `upgrade_cost` is
		# the cooldown, denominated in delivered value instead of ticks.
		upgrader.produce_interval = 0
		upgrader.input_tier = tier - 1
		upgrader.output_tier = tier
		upgrader.upgrade_cost = UPGRADE_COST
		# Painted by what it emits, on the generator's precedent — a source is its
		# output colour, whatever fills it.
		upgrader.color = Tiers.color_of(tier)
		upgrader.icon_path = "res://assets/upgrade.svg"
		upgrader.behavior = UpgraderBehavior.new()
		_register(upgrader)

	# --- The compressor family -------------------------------------------
	#
	# One per colour, and **including red**, unlike the upgraders: a compressor
	# does not move up the ladder, it takes a colour and hands the same colour
	# back. Seven rather than six, built in the same loop shape so a new tier
	# cannot arrive without one.
	#
	# Decay is charged per orb rather than per unit of value, and this family is
	# what that rule is worth to a player. Ten 10-value orbs die over twenty hops;
	# one 100-value orb arrives with 81. So a compressor is the second answer to
	# reach beside the pump, and a different one: a pump adds a hop of survival to
	# every route through it, a compressor makes distance nearly free and charges
	# in latency and granularity instead.
	#
	# Uniform `COMPRESS_COST` across the seven for the upgrader's reason — every
	# colour launches and decays identically, so there is no scarcity ramp for the
	# price to mirror.
	for tier in Tiers.COUNT:
		var compressor := BlockDef.new()
		compressor.id = compressor_id(tier)
		compressor.display_name = "%s Compressor" % Tiers.name_of(tier).capitalize()
		compressor.description = "Banks %d delivered %s, then launches it as one %s orb worth all of it." \
			% [COMPRESS_COST, Tiers.name_of(tier), Tiers.name_of(tier)]
		compressor.needs_target = true
		# Anchored, for the upgrader's reason. A movable compressor parked one hop
		# from the frontier would delete the expensive half of every long haul,
		# which is the distance the block exists to make survivable.
		compressor.movable = false
		compressor.produce_interval = 0
		# The same tier in and out. That single line is the whole difference from
		# an upgrader, and it is what `compresses()` reads the board by.
		compressor.input_tier = tier
		compressor.output_tier = tier
		# ⚠️ `compress_cost`, never `upgrade_cost`. Priced in the latter this block
		# would be inside `converts()` and would pick up the sphere's charge
		# discount — banking less near a sphere and so emitting a *smaller* orb,
		# which is backwards for the one block whose point is a bigger one.
		compressor.compress_cost = COMPRESS_COST
		compressor.color = Tiers.color_of(tier)
		compressor.icon_path = "res://assets/compress.svg"
		compressor.behavior = CompressorBehavior.new()
		_register(compressor)

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
	# The brightest of the three neutrals. An upkeep block emits nothing and so
	# carries no tier, but it is the one of the three that can go *dark*, and a
	# light block reads its "dry" state most clearly.
	upkeep.color = COLOR_UPKEEP
	upkeep.icon_path = "res://assets/energy-tank.svg"
	upkeep.behavior = UpkeepBehavior.new()
	_register(upkeep)

	var pump := BlockDef.new()
	pump.id = PUMP
	pump.display_name = "Pump"
	pump.description = "Adds +20% of an orb's launch value on the way through. Stacks along a route."
	# A pump carries no tier of its own — it is a path modifier, and anything of
	# any colour may pass through it — so it takes a neutral rather than a hue.
	# It used to be teal, which is now a tier: a block that helps every colour
	# along must not look like one of them.
	pump.color = COLOR_PUMP
	pump.icon_path = "res://assets/energise.svg"
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

	var amplifier := BlockDef.new()
	amplifier.id = AMPLIFIER
	amplifier.display_name = "Amplifier"
	amplifier.description = "Multiplies an orb by 1.5 on the way through. Compounds along a route."
	# Neutral, for the pump's reason: it acts on orbs of every colour, so it must
	# not claim one. A shade between the pump and the sphere, since it sits between
	# them in what it does — a path modifier, like the pump, but a stronger one.
	amplifier.color = COLOR_AMPLIFIER
	amplifier.icon_path = "res://assets/amplify.svg"
	amplifier.needs_target = false
	# ⚠️ Amplify, never restore, and never both. A def carrying both would be
	# pumped *and* amplified by `arrival_along`'s single pass over the route;
	# `test_restore_and_amplify_are_disjoint` refuses that shape outright.
	#
	# This is a multiplier where the pump is an addend, which is what makes income
	# super-linear rather than linear in the support on a route: two pumps on a
	# plain orb are +4, two amplifiers are ×2.25. The number lives in
	# `AMPLIFY_PERCENT` because the simulation resolves it from a count — see the
	# warning there.
	amplifier.amplify_percent = AMPLIFY_PERCENT
	amplifier.behavior = AmplifierBehavior.new()
	_register(amplifier)

	# --- The distributor family --------------------------------------------
	#
	# One per colour, like the compressors and for the same reason: it hands back
	# the colour it was given, so there is no missing bottom rung.
	#
	# A generator points at one cell, so opening four at once has always meant four
	# generators or four trips back to the same one. This is the block that turns a
	# single supply line into a frontier — it banks one orb's worth and sends it to
	# the next output in rotation.
	#
	# ⚠️ `needs_target = false` **and** `movable = false`. It is neither aimed nor
	# swapped: its `max_ports` gives right-click a third reading, and the three
	# flags are pairwise disjoint so a click still means exactly one thing.
	# `test_target_movable_and_ports_are_pairwise_disjoint` holds that.
	for tier in Tiers.COUNT:
		var distributor := BlockDef.new()
		distributor.id = distributor_id(tier)
		distributor.display_name = "%s Distributor" % Tiers.name_of(tier).capitalize()
		distributor.description = "Splits one %s line across up to %d outputs, one orb at a time." \
			% [Tiers.name_of(tier), DISTRIBUTOR_PORTS]
		distributor.needs_target = false
		# Anchored, for the upgrader's reason: a movable fan-out parked at the
		# frontier would make every one of its outputs a one-hop delivery.
		distributor.movable = false
		distributor.produce_interval = 0
		distributor.input_tier = tier
		distributor.output_tier = tier
		distributor.max_ports = DISTRIBUTOR_PORTS
		distributor.color = Tiers.color_of(tier)
		distributor.icon_path = "res://assets/distribute.svg"
		distributor.behavior = DistributorBehavior.new()
		_register(distributor)

	# --- The teleport pairs ------------------------------------------------
	#
	# One def per pair, buried twice by the map. Both ends share a `link_group`
	# because they share a *definition*, so there is no per-block pairing state to
	# keep in sync through a swap and nothing extra to serialise.
	#
	# Movable and target-less, which is what keeps `needs_target` and `movable`
	# disjoint and right-click unambiguous. A teleporter that had to be *pointed*
	# at its partner would make one click mean two things — see `BlockDef.link_group`.
	for group in TELEPORTER_PAIRS:
		var teleporter := BlockDef.new()
		teleporter.id = teleporter_id(group)
		teleporter.display_name = "Teleporter %d" % (group + 1)
		teleporter.description = "One end of a pair. Once both ends are mined, the cells they stand on are one hop apart."
		# Neutral, for the pump's reason: any colour may cross a teleport link, so
		# it must not look like one of them. The lightest of the greys — a link is
		# the most structural thing a block can do to the board.
		teleporter.color = COLOR_TELEPORTER
		teleporter.icon_path = "res://assets/teleport.svg"
		teleporter.needs_target = false
		teleporter.link_group = group
		teleporter.behavior = TeleporterBehavior.new()
		_register(teleporter)

	var sphere := BlockDef.new()
	sphere.id = SPHERE
	sphere.display_name = "Sphere"
	sphere.description = "Radiates a bonus to every block within 2 hops: 25% faster generators and upgraders, stronger pumps."
	# Like the pump, a sphere carries no tier of its own — it modifies whatever is
	# near it, whatever colour that turns out to be — so it takes a neutral too,
	# a step darker than the pump's so the two read apart at a glance.
	sphere.color = COLOR_SPHERE
	sphere.icon_path = "res://assets/ball-glow.svg"
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
	#
	# One of each is buried in **every colour band**, so the same three bonuses
	# stack up to seven times over a full clear. That is deliberate for now — the
	# three effects are placeholders until they differentiate per band — and it is
	# the reason the per-instance numbers below are the first thing to retune when
	# they do. See the note in `gamedesign.md`.
	#
	# Their colours are neutral, and the board mostly does not use them: a mined
	# challenge is drawn in the tier colour of the cell it was gated at, so the
	# monument stays tied to the band it came out of. These three are what the HUD
	# panel paints, and they differ only in brightness — colour on the board means
	# a tier, and a challenge is not one.

	var surge := BlockDef.new()
	surge.id = CHALLENGE_SURGE
	surge.display_name = "Surge"
	surge.description = "Every generator on the board launches its orbs with +5 value."
	surge.color = Color("e8ecf2")
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
	current.color = Color("c3cbd6")
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
	lens.color = Color("9ba3b1")
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
