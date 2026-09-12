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

var cost: float = 0.0
## Cost before a keystone's markup.
var base_cost: float = 0.0
var progress: float = 0.0

## The tunnel cell guarding the next colour. Mining it opens that colour.
var is_boss: bool = false
var is_mined: bool = false

## Rolled once when the cell is mined. A generator emits and is worth power; a
## dud is inert ground. Raising the odds is a shop purchase.
var is_generator: bool = false

## What is buried here: a `NodeCatalog` id, or "" for nothing. Randomised per
## run. `tier` is a `NodeCatalog.TIER_*`, fixed by the slot.
var node_id: String = ""
var tier: int = 0

## Emission charge left before this cell emits again. Read and written only by
## this cell, which is what keeps the produce phase order-independent.
var emit_countdown: int = 0


func remaining() -> float:
	return maxf(0.0, cost - progress)


## Lands up to `amount` and returns what counted. The finishing hit snaps to
## `cost`, since huge floats can round a hair short of it.
func absorb(amount: float) -> float:
	var need := remaining()
	if amount >= need:
		progress = cost
		return need
	progress += amount
	return amount


func has_node() -> bool:
	return not node_id.is_empty()


func is_keystone() -> bool:
	return has_node() and tier == NodeCatalog.TIER_KEYSTONE


## Levels mining this cell grants, scaled by its tier and region.
func node_grant() -> int:
	return NodeCatalog.grant(node_id, tier, region)


## 0 nothing, 1 common, 2 rare, 3 keystone. What the glow is sized by — the
## board's second colour channel, and the only thing visible at range.
func node_tier() -> int:
	return tier if has_node() else 0


## Mine this cell. Go through `Graph.mine_cell()` rather than calling this —
## mining changes the frontier, which the world caches. Idempotent.
func apply_mine() -> void:
	is_mined = true
	progress = maxf(progress, cost)
