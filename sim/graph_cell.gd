class_name GraphCell
extends RefCounted

## One position on the board. Cells never move and are never created at runtime.

var id: int = -1
var position: Vector2 = Vector2.ZERO

## Sorted ascending, so emission order and every BFS tie-break is deterministic.
var neighbor_ids: PackedInt32Array = PackedInt32Array()

## Hops from the centre, and the depth region that follows from it. Both fixed at
## board build — the board is the same place every run.
var hops: int = 0
var region: int = Regions.RED

var cost: int = 0
var progress: int = 0
var is_mined: bool = false

## Rolled once when the cell is mined. A generator emits and is worth power; a
## dud is inert ground. Raising the odds is a shop purchase.
var is_generator: bool = false

## What is buried here: a `NodeCatalog` id, or "" for nothing. Randomised per
## run. `node_levels` is 1 for an ordinary node and 3 for a keystone.
var node_id: String = ""
var node_levels: int = 0

## Ticks until this cell emits again. Read and written only by this cell, which
## is what keeps the produce phase order-independent.
var emit_timer: int = 0


func remaining() -> int:
	return maxi(0, cost - progress)


func has_node() -> bool:
	return not node_id.is_empty()


func is_keystone() -> bool:
	return node_levels >= NodeCatalog.KEYSTONE_LEVELS


## Levels mining this cell grants, scaled by its region.
func node_grant() -> int:
	return node_levels * NodeCatalog.levels_in_region(node_id, region)


## 0 nothing, 1 common, 2 rare, 3 keystone. What the glow is sized by — the
## board's second colour channel, and the only thing visible at range.
func node_tier() -> int:
	if not has_node():
		return 0
	if is_keystone():
		return 3
	var type := NodeCatalog.get_type(node_id)
	return 1 if type == null or type.rarity == NodeType.COMMON else 2


## Mine this cell. Go through `Graph.mine_cell()` rather than calling this —
## mining changes the frontier, which the world caches. Idempotent.
func apply_mine() -> void:
	is_mined = true
	progress = maxi(progress, cost)
