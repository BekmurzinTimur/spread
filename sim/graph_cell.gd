class_name GraphCell
extends RefCounted

## A position in the network. Exists from the start of the game and holds
## whatever the map buried in it; mining reveals that block, and from then on
## the player can swap it elsewhere. Locked cells are still traversable — they
## simply offer no support to orbs crossing them.

var id: int = -1
var position: Vector2 = Vector2.ZERO

## Sorted ascending, so BFS expansion order — and therefore path tie-breaking —
## is deterministic.
var neighbor_ids: PackedInt32Array = PackedInt32Array()

var is_unlocked: bool = false
var unlock_cost: int = 0
var unlock_progress: int = 0

## Which colour of orb this cell will accept toward its unlock. Static map data.
##
## This is how a second currency is expressed. Value is never banked anywhere in
## Spread — it flows and is spent on arrival — so a "currency" cannot be a
## stockpile. It is a fact about what a cell will take, and the board is the
## ledger. An orange cell ignores red entirely, so reaching one means owning an
## upgrader and a route out of it.
##
## Unlike `initial_block_id` this is *not* concealed: the view tints a locked
## cell by it. That leaks nothing, because it describes the price rather than
## the prize.
var required_tier: int = Tiers.RED

## What the map buried here, or "" for an empty cell. Static map data — never
## mutated. Concealed until the cell is mined: a locked cell draws a question
## mark, so this is read only by `apply_unlock()` and by `is_challenge()` below.
## Once mined, `block` takes over, and the two diverge the moment the player
## swaps.
var initial_block_id: String = ""

var block: Block = null


func has_block() -> bool:
	return block != null


## Whether a challenge is buried here, or standing here already.
##
## This is the one sanctioned read of `initial_block_id` from outside
## `apply_unlock()`, and it is safe because it answers a *category* and not an
## identity: the view learns that this cell is worth a triangle and a steep
## price, and cannot learn which of the three challenges it will get. Knowing a
## hard thing is coming is the point; knowing what it pays out would remove the
## reason to dig it.
##
## Derived rather than stored, like `Graph.is_discovered()`, so there is nothing
## to keep in sync, nothing extra to serialise, and no way for a challenge cell
## to forget it is one. Reading `block` first matters: a mined cell is described
## by what stands on it, which is also what makes this keep working if a future
## challenge type is ever movable.
func is_challenge() -> bool:
	if block != null:
		return block.def.is_challenge
	var def := BlockCatalog.get_def(initial_block_id)
	return def != null and def.is_challenge


## Whether an orb of this tier counts toward mining this cell. Anything else
## that arrives is wasted.
func accepts_tier(tier: int) -> bool:
	return tier == required_tier


func unlock_remaining() -> int:
	return maxi(0, unlock_cost - unlock_progress)


## Mine this cell: it becomes usable and yields whatever the map buried in it.
## This is the only way a block ever comes into existence, so the supply of
## generators and pumps is fixed by the map and the player can only rearrange
## them. Idempotent, and never overwrites a block already sitting here.
##
## Do not call this directly — go through `Graph.unlock_cell()`. Mining grows the
## discovered set, which changes what routes exist, and Graph has to drop its
## path cache when that happens. The name is deliberately not `unlock()` so a
## call site that bypasses the funnel fails loudly instead of silently leaving a
## stale cache behind.
func apply_unlock() -> void:
	is_unlocked = true
	unlock_progress = maxi(unlock_progress, unlock_cost)
	if block != null or initial_block_id.is_empty():
		return
	var def := BlockCatalog.get_def(initial_block_id)
	if def != null:
		block = Block.new(def)
