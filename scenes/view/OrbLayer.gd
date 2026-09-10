extends Node2D

## Draws orbs in flight, interpolated between ticks.
##
## One hop each, so there is no route to follow — just a lerp from the frontier
## cell that fired to the locked cell it is opening, with a short trail behind
## it. A crit is visibly larger and brighter for the whole flight, because it was
## rolled at emission rather than at landing.

const RADIUS := 8.0
const CRIT_RADIUS := 15.0

const TRAIL_LENGTH := 0.22
const TRAIL_WIDTH := 4.0

var world: World

## How far into the current tick the frame is, 0..1. Set by Main so orbs move
## smoothly at 10 Hz.
var render_alpha: float = 0.0


func _draw() -> void:
	if world == null:
		return

	for orb in world.orbs:
		if orb.dead:
			continue
		var from := world.graph.get_cell(orb.from_id)
		var to := world.graph.get_cell(orb.to_id)
		if from == null or to == null:
			continue

		var t := clampf(
			(float(orb.ticks_in_hop) + render_alpha) / float(World.HOP_TICKS),
			0.0, 1.0)
		var at := from.position.lerp(to.position, t)
		var tail := from.position.lerp(to.position, maxf(0.0, t - TRAIL_LENGTH))

		var hue := Bands.color_of(to.band)
		var color := Color(1.0, 0.98, 0.9) if orb.is_crit else hue.lerp(Color.WHITE, 0.45)
		var radius := CRIT_RADIUS if orb.is_crit else RADIUS

		draw_line(tail, at, Color(color, 0.35), TRAIL_WIDTH, true)
		draw_circle(at, radius * 1.8, Color(color, 0.16))
		draw_circle(at, radius, color)
