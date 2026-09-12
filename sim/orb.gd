class_name Orb
extends RefCounted

## A packet in flight. Float value, exactly one hop.
##
## No route and no path index: an orb leaves a frontier cell for an adjacent
## locked one and that is the whole journey. Decay went with the routing it
## existed to gate.

var value: float = 0.0

var from_id: int = -1
var to_id: int = -1

## Rolled at emission, not at landing, so the view can draw a crit larger and
## brighter for the whole of its flight.
var is_crit: bool = false

## Also rolled at emission. On landing, the target's neighbours take a share.
var is_splash: bool = false

var ticks_in_hop: int = 0

## How early in its tick it was emitted, 0..999. View-only: staggers orbs born
## in the same tick.
var lead_permille: int = 0

## Marked instead of removed mid-tick; the world compacts once per tick.
var dead: bool = false
