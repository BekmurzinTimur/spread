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

## What the map buried here, or "" for an empty cell. Static map data — never
## mutated, and the source of truth for drawing a *locked* cell. Once mined,
## `block` takes over, and the two diverge the moment the player swaps.
var initial_block_id: String = ""

var block: Block = null


func has_block() -> bool:
	return block != null


func unlock_remaining() -> int:
	return maxi(0, unlock_cost - unlock_progress)


## Mine this cell: it becomes usable and yields whatever the map buried in it.
## This is the only way a block ever comes into existence, so the supply of
## generators and pumps is fixed by the map and the player can only rearrange
## them. Idempotent, and never overwrites a block already sitting here.
func unlock() -> void:
	is_unlocked = true
	unlock_progress = maxi(unlock_progress, unlock_cost)
	if block != null or initial_block_id.is_empty():
		return
	var def := BlockCatalog.get_def(initial_block_id)
	if def != null:
		block = Block.new(def)
