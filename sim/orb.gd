class_name Orb
extends RefCounted

## A packet of resource in flight. All value arithmetic is integer.

var value: int = 0

## What this orb was emitted with, before any decay or pump. Stamped once at
## emission and never written again.
##
## A pump restores a percentage *of this*, not of the current value, which is
## what makes pumps along a route additive rather than compounding — three of
## them add 60% of the launch value in any order. Carrying it on the orb rather
## than asking the world for `effective_orb_value()` at each pump is also what
## stops a Surge mined mid-flight from retroactively re-pricing an orb already
## on its way.
var launch_value: int = 0

var tier: int = Tiers.RED

## Full cell-id route, inclusive of both endpoints. Resolved once at spawn.
var path: PackedInt32Array = PackedInt32Array()

## Index into `path` of the cell the orb has most recently reached.
var hop_index: int = 0

## Ticks spent on the edge between path[hop_index] and path[hop_index + 1].
var ticks_in_hop: int = 0

## Cell that emitted this orb. Nothing in the simulation reads it — an orb is
## committed once launched, so its source has no further say over it. The view
## keys its weave lanes off this, so one source's output travels as one strand.
var source_id: int = -1

## Marked instead of removed mid-tick; the world compacts once per tick.
var dead: bool = false


func current_cell_id() -> int:
	return path[hop_index]


func next_cell_id() -> int:
	if is_at_end():
		return path[hop_index]
	return path[hop_index + 1]


func destination_id() -> int:
	return path[path.size() - 1]


func is_at_end() -> bool:
	return hop_index >= path.size() - 1


## Hops still to cross. Useful for UI ("this orb will arrive with N").
func hops_remaining() -> int:
	return (path.size() - 1) - hop_index
