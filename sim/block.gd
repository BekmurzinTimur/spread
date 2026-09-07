class_name Block
extends RefCounted

## An installed block: a definition plus its mutable runtime state.
## The cell is the real estate; the block is the tenant.

var def: BlockDef

## Aimed destination cell id, or -1 for unaimed (idle).
var target_id: int = -1

## Cells the route must pass through on its way to `target_id`, in order.
##
## A list of *constraints*, not a resolved path. Storing the waypoints rather
## than the walk is what lets a route re-resolve for free: discovery only ever
## grows, so a leg can get shorter but never disappear, and there is nothing to
## invalidate when the fog lifts. Storing the walk instead would freeze a route
## the day it was drawn and quietly keep taking the long way round.
##
## Empty for the overwhelming majority of blocks, which take the shortest path.
var route_via: PackedInt32Array = PackedInt32Array()

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

## Whether an upkeep block's bonus is currently switched on.
##
## A latch, not a comparison: it turns on when `charge` reaches the def's reserve
## and off only when the bank is empty. Recomputing it from `charge` at each read
## would strobe the bonus across the whole board for a block held at exactly its
## drain rate, which is the failure mode hysteresis exists to prevent.
##
## Written only by `World._phase_upkeep()`, in a phase that runs before anything
## reads a stat. It travels with the block through a swap, alongside `charge`,
## which is the right answer for free — a fuelled block picked up and put down
## somewhere else is still fuelled.
var fuelled: bool = false


func _init(p_def: BlockDef) -> void:
	def = p_def


func has_target() -> bool:
	return target_id != -1


func has_waypoints() -> bool:
	return not route_via.is_empty()


## Whether this block's board-wide bonus counts *right now*. The id-free
## predicate the stats pass walks, so no type test leaks into it: everything
## except an upkeep block grants unconditionally once mined, and an upkeep block
## grants only while its latch is on.
func grants_global_now() -> bool:
	return not def.burns_upkeep() or fuelled


## Drop the aim and the route together. The two are one decision, so anything
## that clears a target has to come through here — a `target_id = -1` on its own
## leaves a stale via-list behind, to be silently reapplied the next time the
## player aims this block somewhere new.
func clear_target() -> void:
	target_id = -1
	route_via = PackedInt32Array()


func mark_active(tick: int) -> void:
	last_active_tick = tick


## Ticks since this block last acted, or -1 if it never has. The view turns this
## into a pulse that decays; a large number is a block sitting idle on a dead
## route, which is worth seeing too.
func ticks_since_active(now: int) -> int:
	if last_active_tick < 0:
		return -1
	return now - last_active_tick
