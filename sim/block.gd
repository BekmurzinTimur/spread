class_name Block
extends RefCounted

## An installed block: a definition plus its mutable runtime state.
## The cell is the real estate; the block is the tenant.

var def: BlockDef

## Aimed destination cell id, or -1 for unaimed (idle).
var target_id: int = -1

## Ticks accumulated toward the next emission.
var timer: int = 0

## Delivered value banked toward the next emission, for a converter.
##
## Kept separate from `timer` rather than reusing it: they are different units —
## ticks the world hands out for free, against value the player had to route
## here — and a block that ever did both would need both. An upgrader banks this
## whether or not it is aimed, so charge collected while idle is not lost.
var charge: int = 0

## The tick this block last actually did its thing — emitted an orb, restored
## one — or -1 if it never has. Presentation reads it to pulse the block on the
## board; nothing in the simulation branches on it.
##
## Behaviours set it themselves, through `mark_active()`, because only the
## behaviour knows what counts: a generator is asked to produce every tick but
## only fires on the twentieth, and a generator whose target has become
## unroutable does nothing at all.
##
## Order-independent for free. Every writer in a tick writes the same
## `tick_count`, so it converges to one value no matter how many blocks act or
## in what order. It lives on the block rather than the cell so a pulse follows
## a block through a swap, which is where the activity actually went.
var last_active_tick: int = -1


func _init(p_def: BlockDef) -> void:
	def = p_def


func has_target() -> bool:
	return target_id != -1


func mark_active(tick: int) -> void:
	last_active_tick = tick


## Ticks since this block last acted, or -1 if it never has. The view turns this
## into a pulse that decays; a large number is a block sitting idle on a dead
## route, which is worth seeing too.
func ticks_since_active(now: int) -> int:
	if last_active_tick < 0:
		return -1
	return now - last_active_tick
