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
## delivery would land at 9 of 10, which reduced decay to a formality. Anchoring
## them is what makes a pump chain the way to extend reach.
@export var movable: bool = true

# --- Source ---
## Ticks between emissions. Only meaningful when the behaviour produces.
@export var produce_interval: int = 0
@export var output_tier: int = Tiers.RED

# --- Path modifier ---
## Value added to an orb passing through. Flat and uncapped — pumps along a route
## stack, so this is what one of them contributes, not a level it restores to.
@export var restore_amount: int = 0

# --- Radiated field ---
## How many hops this block's bonuses reach. 0 for a block that radiates nothing,
## which is every type but the sphere.
##
## Measured in hops rather than pixels because the board is a graph: two cells
## drawn close together may be far apart through the network, and the bonus
## follows the edges.
@export var field_radius: int = 0

## Ticks taken off the interval of every producer in range. Negative speeds them
## up; the sum is clamped by World.MIN_PRODUCE_INTERVAL so a stack of spheres
## cannot drive an interval to zero.
@export var field_interval_bonus: int = 0

## Added to the restore amount of every path modifier in range.
@export var field_restore_bonus: int = 0


## Whether this block radiates anything at all — the test the stats pass uses to
## decide what to walk out from, rather than checking for the sphere by id.
func radiates() -> bool:
	return field_radius > 0 \
		and (field_interval_bonus != 0 or field_restore_bonus != 0)

## Shared, stateless. Set by the catalog.
var behavior: BlockBehavior = null
