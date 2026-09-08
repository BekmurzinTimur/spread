class_name BlockDef
extends Resource

## Static, shared per-type data for a block. One instance per block type,
## declared in BlockCatalog.
##
## This is a Resource so the catalog can later be replaced by inspector-tunable
## .tres files without any consumer change.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var color: Color = Color.WHITE

## Path to this type's glyph, drawn tinted with `color`. A plain string, so the
## simulation still references no Godot texture or node — the view loads it.
@export var icon_path: String = ""

## Whether the player aims this block at a destination cell.
@export var needs_target: bool = false

## How many outputs this block may hold at once. 0 for everything with a single
## `target_id`, which is every type but the distributor.
##
## ⚠️ **`needs_target`, `movable` and `has_ports()` are pairwise disjoint, and the
## right-click gesture depends on it.** Each names one reading of a click — aim it,
## move it, toggle an output — so a def answering to two would make one click mean
## two things. It used to be a two-way rule between the first pair;
## `test_target_movable_and_ports_are_pairwise_disjoint` is the three-way version.
@export var max_ports: int = 0

## Whether swapping may relocate this block. Generators are anchored where the
## map buried them: swapping is free, instant and unlimited in range, so a
## movable generator could always be parked one hop from the frontier and every
## delivery would land at the full launch value, which reduced decay to a formality. Anchoring
## them is what makes a pump chain the way to extend reach.
@export var movable: bool = true

# --- Source ---
## Ticks between emissions. Only meaningful when the behaviour produces.
@export var produce_interval: int = 0
@export var output_tier: int = Tiers.RED

# --- Converter ---
## Which tier this block accepts as a *delivery*, or -1 if it accepts nothing.
## An upgrader is the target of a generator: orbs of this tier that end their
## route here are absorbed rather than wasted.
##
## Deliberately distinct from `restore_percent`, which acts on orbs passing
## *through*. A converter consumes what arrives; a pump helps along what does
## not stop.
@export var input_tier: int = -1

## How much input value buys one output orb. The upgrader's cooldown, measured
## in delivered value instead of ticks — which is the whole idea: it works like
## a generator whose timer the player has to fill.
@export var upgrade_cost: int = 0

# --- Compressor ---
## Delivered value banked before this block launches one orb of the **same** tier
## worth that whole bank. 0 for everything that does not compress.
##
## Deliberately its own field rather than a reuse of `upgrade_cost`, and the
## reason is the sphere. `effective_upgrade_cost()` applies `field_charge_percent`,
## so a compressor priced in `upgrade_cost` would bank *less* near a sphere and
## therefore emit a **smaller** orb — backwards for a block whose entire purpose is
## fewer, bigger orbs. Standing outside the `converts()` family is what keeps a
## compressor's output size a property of the block rather than of whatever
## happens to be parked beside it.
##
## The cost of that choice is paid in `has_intake()` and `charge_meter_max()`,
## which both have to name `compresses()` explicitly — see the notes there.
@export var compress_cost: int = 0

# --- Upkeep ---
## Value burned from the bank every tick this block sits on a mined cell. The
## running cost of holding its board-wide bonus up.
##
## A flat constant on purpose. The drain is resolved in a phase of its own that
## runs before any stat does, so it must never depend on an effective stat —
## see `World._phase_upkeep()`.
@export var upkeep_drain: int = 0

## Bank level that switches the bonus on. A threshold, not a cap: the bank keeps
## accepting past it, and the surplus buys a longer run before it goes dark.
##
## The bonus switches *off* only at an empty bank, never back at this level. That
## gap is the whole anti-strobe rule — a block held at exactly the drain rate
## would otherwise flicker its bonus across the entire board every few ticks.
@export var upkeep_reserve: int = 0

# --- Path modifier ---
## Percentage of an orb's *launch* value added to it on the way through. 20 means
## +20%. Uncapped, and pumps along a route stack, so this is what one of them
## contributes, not a level it restores to.
##
## Of the launch value rather than the orb's current value, which is what keeps
## multiple pumps additive: three of them add 60% of what the orb was born with,
## in any order, rather than compounding into a route-order-dependent number.
## `World.restore_for()` is the only place this is turned into value.
@export var restore_percent: int = 0

## Percentage an orb's value is *multiplied* by for each of these it passes
## through. 50 means ×1.5, so two of them are ×2.25. The one compounding term in
## the economy, and the counterpart to `restore_percent`: a pump adds a share of
## what the orb was born with, an amplifier scales what it is actually carrying.
##
## ⚠️ **A block must not set both.** `World.arrival_along()` reads them in one
## pass and a def carrying both would be pumped *and* amplified — the preview
## would still agree with the simulation, but the two effects were designed as
## alternatives and nothing else in the codebase expects a block to be both.
## `test_restore_and_amplify_are_disjoint` pins it.
##
## Nothing turns this into value at the cell it is met. `Orb.amplifiers` is
## incremented instead and the whole exponent is resolved once at delivery, which
## is what keeps arrival independent of the order the route met its blocks — see
## the comment on that field.
@export var amplify_percent: int = 0

# --- Teleporter ---
## Which pair this block belongs to. -1 for everything that is not a teleporter.
##
## The pairing is **map-baked rather than aimed**, and that is a deliberate dodge
## around the right-click gesture. `needs_target` and `movable` are disjoint
## across the catalog and the whole of `Main._on_aim_click` rests on it, so a
## teleporter that had to be *pointed* at its partner would make one click mean
## two things. Belonging to a group instead, a teleporter is an ordinary movable
## block: you relocate both ends by swapping, and the link follows.
##
## Two blocks share a group by sharing a **def** — the catalog registers one def
## per pair and the map buries it twice — so there is no per-block state to keep
## in sync and nothing extra to serialise.
@export var link_group: int = -1

# --- Radiated field ---
## How many hops this block's bonuses reach. 0 for a block that radiates nothing,
## which is every type but the sphere.
##
## Measured in hops rather than pixels because the board is a graph: two cells
## drawn close together may be far apart through the network, and the bonus
## follows the edges.
@export var field_radius: int = 0

## *Increased* rate for every producer in range, in percentage points. 25 means
## they work 25% faster, and `StatBonus.apply_rate()` turns the accumulated sum
## into an interval — a curve that approaches zero without reaching it, so this
## stacks indefinitely and needs no cap to stay sane.
@export var field_rate_percent: int = 0

## Percentage points added to the restore of every path modifier in range. The
## restore is a percentage, so a field raises the percentage: +10 takes a pump
## from 20% to 30%.
@export var field_restore_percent: int = 0

## *Increased* charge rate for every converter in range, in percentage points.
## A converter's clock is denominated in delivered value, so charging faster is
## the same thing as costing less: 25 takes an upgrade cost of 60 down to 48,
## through the same `StatBonus.apply_rate()` the interval uses.
##
## Its own field rather than a second reader of `field_rate_percent`, so the
## discount can be tuned apart from generator speed — they buff different halves
## of the economy and there is no reason they should move together.
@export var field_charge_percent: int = 0

# --- Board-wide bonus ---
## Whether this type is a challenge: expensive to mine, worth announcing before
## it is dug up, and buried once in every colour band. The cell draws as a
## triangle and the map generator asserts one of each per band.
##
## Kept separate from `grants_global()` because they answer different questions.
## This one is about presentation and map validation; that one is about what the
## stats pass has to walk. A future block could grant a global bonus without
## being a challenge, or be a challenge that grants something else entirely.
@export var is_challenge: bool = false

## Added to ORB_START_VALUE for every generator on the board.
@export var global_orb_value_bonus: int = 0

## Percentage points added to every path modifier's restore, on top of any
## sphere field. Upgrades the pump's percentage rather than handing out flat
## value, so it is worth more the richer orbs launch.
@export var global_field_restore_percent: int = 0

## Percentage added to every radiating block's field radius. 50 means +50%.
@export var global_field_radius_percent: int = 0

## *Increased* rate for every producer on the board, in percentage points, like
## `field_rate_percent` and resolved through the same `StatBonus.apply_rate()`.
## The two are summed before the division, so a block standing in a sphere's
## field on a board with this lit gets one divisor, not two.
@export var global_rate_percent: int = 0


## Whether this block radiates anything at all — the test the stats pass uses to
## decide what to walk out from, rather than checking for the sphere by id.
func radiates() -> bool:
	return field_radius > 0 \
		and (field_rate_percent != 0 or field_restore_percent != 0
			or field_charge_percent != 0)


## Whether this block emits orbs on a clock of its own — the id-free test for a
## generator, in the same spirit as `converts()` and `radiates()`. A converter
## emits too, but its clock is the player's delivery line rather than an interval,
## so it answers false here and true to `converts()`.
##
## Exists because there is no longer *a* generator to check for by id: there is
## one per tier, and any scan that names `BlockCatalog.GENERATOR` now silently
## counts a seventh of them.
func produces() -> bool:
	return produce_interval > 0


## Whether this block multiplies an orb passing through it. The id-free
## counterpart to the `restore_percent > 0` test for a pump, and the predicate
## `World.arrival_along()` branches on so the preview and the tick agree.
func amplifies() -> bool:
	return amplify_percent > 0


## Whether this block turns one tier into another — the id-free test `set_target`
## uses to decide that a *mined* cell is a legal destination, and that `_deliver`
## uses to decide an arrival is absorbed rather than wasted.
func converts() -> bool:
	return input_tier >= 0 and upgrade_cost > 0


## Whether this block holds a list of outputs rather than a single target. The
## third reading of a right-click, and the id-free test `Main` branches on.
##
## Strictly about *outputs*. Whether the block also has an appetite is
## `distributes()` below — the two happen to coincide today, and keeping them
## apart is what stops a future ported block that emits from nothing being
## silently given an intake.
func has_ports() -> bool:
	return max_ports > 0


## Whether this block banks arriving value and relays it across its outputs.
##
## The distributor's entry into `has_intake()`, which it must have: without it
## `can_aim_at` refuses every aim at the block and nothing can ever feed it — the
## same silent death the compressor was one word away from.
func distributes() -> bool:
	return input_tier >= 0 and has_ports()


## Whether this block is one end of a teleport pair. The id-free test
## `World.resolve_links()` walks the board by.
func links() -> bool:
	return link_group >= 0


## Whether this block banks value and re-emits it as one larger orb of the same
## tier. The id-free test for a compressor.
##
## ⚠️ **Pointedly not a kind of `converts()`.** The two describe different
## appetites and are read by different machinery: `converts()` gates the sphere's
## charge discount and `effective_upgrade_cost()`, which a compressor must stay out
## of, while *delivery* questions go through `has_intake()`, which it must be in.
## Folding this into `converts()` would silently hand a compressor the discount the
## design excludes; leaving it out of `has_intake()` makes it unaimable and the
## whole block dead. Both mistakes are one word each.
func compresses() -> bool:
	return compress_cost > 0


## Whether this block burns a running cost to hold a board-wide bonus up. The
## id-free counterpart to `converts()`: both describe a block with an appetite,
## and they differ only in what the appetite buys.
func burns_upkeep() -> bool:
	return input_tier >= 0 and upkeep_drain > 0 and upkeep_reserve > 0


## Whether this block has an intake at all — the test for "a mined cell that is
## still a legal destination". There are four kinds now — a converter, an upkeep
## block, a compressor and a distributor — and everything that used to ask
## `converts()` about *delivery* wants this instead.
##
## ⚠️ **This is the predicate that makes a block aimable at all.** `can_aim_at`'s
## "a mined cell with a matching intake" rule is the only route by which anything
## may be pointed at mined ground, so a type with an appetite that is missing from
## this list can never be fed: `set_target` refuses it, `on_orb_deliver` never
## fires, and the block is dead on the board with no error anywhere. It is the
## first line to check when a new intake type appears to do nothing.
func has_intake() -> bool:
	return converts() or burns_upkeep() or compresses() or distributes()


## Whether this block will absorb an arriving orb of this tier. The one question
## the deliver phase asks about a mined destination.
func accepts_delivery(tier: int) -> bool:
	return has_intake() and tier == input_tier


## What a full charge meter holds *before any field*. Two different things fill
## it — a converter's next orb, an upkeep block's reserve — and 0 for everything
## with no meter at all, which the caller must guard against dividing by.
##
## No longer the answer for a converter: a sphere discounts `upgrade_cost`, so
## `World.charge_meter_max()` is what the view and the HUD must ask. This is the
## baseline behind it, on the `produce_interval` / `base_interval` precedent.
func charge_meter_max() -> int:
	if converts():
		return upgrade_cost
	if compresses():
		# The base *and* the answer, unlike the converter above. Nothing on the
		# board discounts a compressor, so `World.charge_meter_max()` has no
		# effective reading to prefer over this one and falls straight through.
		return compress_cost
	if burns_upkeep():
		return upkeep_reserve
	return 0


## Whether this block contributes anything board-wide — the same kind of id-free
## predicate as `radiates()`, for the other half of the stats pass.
func grants_global() -> bool:
	return global_orb_value_bonus != 0 \
		or global_field_restore_percent != 0 \
		or global_field_radius_percent != 0 \
		or global_rate_percent != 0

## Shared, stateless. Set by the catalog.
var behavior: BlockBehavior = null
