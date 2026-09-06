extends Node2D

## Draws every orb in a single pass.
##
## The simulation moves orbs in whole ticks; `render_alpha` is the fraction of
## the current tick already elapsed, so orbs glide instead of stepping. Nothing
## here feeds back into the simulation — the view is free to be frame-rate
## dependent because the economy is not.

## Radius at full value; shrinks as an orb decays, so a dying orb reads as one.
const MAX_RADIUS := 8.0
const MIN_RADIUS := 2.5

var world: World
var render_alpha: float = 0.0


func _draw() -> void:
	if world == null:
		return
	for orb in world.orbs:
		if orb.dead:
			continue
		var from := world.graph.get_cell(orb.current_cell_id())
		var to := world.graph.get_cell(orb.next_cell_id())
		if from == null or to == null:
			continue

		var t := (float(orb.ticks_in_hop) + render_alpha) / float(World.TICKS_PER_HOP)
		var pos := from.position.lerp(to.position, clampf(t, 0.0, 1.0))

		var fullness := float(orb.value) / float(World.ORB_MAX_VALUE)
		var radius: float = lerpf(MIN_RADIUS, MAX_RADIUS, fullness)
		var color := Tiers.color_of(orb.tier)

		draw_circle(pos, radius + 2.0, Color(color, 0.20))
		draw_circle(pos, radius, color)
