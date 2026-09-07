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
## Whether this type is a challenge: expensive to mine, unique on the map, and
## worth announcing before it is dug up. The cell draws as a triangle and the
## generator asserts there is exactly one of each.
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


## Whether this block turns one tier into another — the id-free test `set_target`
## uses to decide that a *mined* cell is a legal destination, and that `_deliver`
## uses to decide an arrival is absorbed rather than wasted.
func converts() -> bool:
	return input_tier >= 0 and upgrade_cost > 0


## Whether this block burns a running cost to hold a board-wide bonus up. The
## id-free counterpart to `converts()`: both describe a block with an appetite,
## and they differ only in what the appetite buys.
func burns_upkeep() -> bool:
	return input_tier >= 0 and upkeep_drain > 0 and upkeep_reserve > 0


## Whether this block has an intake at all — the test for "a mined cell that is
## still a legal destination". There are two kinds now, a converter and an upkeep
## block, and everything that used to ask `converts()` about *delivery* wants
## this instead.
func has_intake() -> bool:
	return converts() or burns_upkeep()


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
