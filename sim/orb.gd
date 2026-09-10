class_name Orb
extends RefCounted

## A packet in flight. Integer value, exactly one hop.
##
## No route and no path index: an orb leaves a frontier cell for an adjacent
## locked one and that is the whole journey. Decay went with the routing it
## existed to gate.

var value: int = 0

var from_id: int = -1
var to_id: int = -1

## Rolled at emission, not at landing, so the view can draw a crit larger and
## brighter for the whole of its flight.
var is_crit: bool = false

var ticks_in_hop: int = 0

## Marked instead of removed mid-tick; the world compacts once per tick.
var dead: bool = false
