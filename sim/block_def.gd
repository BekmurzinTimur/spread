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

## Whether the player aims this block at a destination cell.
@export var needs_target: bool = false

# --- Source ---
## Ticks between emissions. Only meaningful when the behaviour produces.
@export var produce_interval: int = 0
@export var output_tier: int = Tiers.RED

# --- Path modifier ---
## Value returned to an orb passing through, capped at World.ORB_MAX_VALUE.
@export var restore_amount: int = 0

## Shared, stateless. Set by the catalog.
var behavior: BlockBehavior = null
