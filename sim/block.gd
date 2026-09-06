class_name Block
extends RefCounted

## An installed block: a definition plus its mutable runtime state.
## The cell is the real estate; the block is the tenant.

var def: BlockDef

## Aimed destination cell id, or -1 for unaimed (idle).
var target_id: int = -1

## Ticks accumulated toward the next emission.
var timer: int = 0


func _init(p_def: BlockDef) -> void:
	def = p_def


func has_target() -> bool:
	return target_id != -1
