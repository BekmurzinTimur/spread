@tool
class_name RamMeter
extends Control

## The ram pool as a radial meter. The pool has no cap, so the arc turns once per
## order of magnitude and the number under it is the truth.

@export var radius := 92.0:
	set(value):
		radius = value
		queue_redraw()

@export var width := 18.0:
	set(value):
		width = value
		queue_redraw()

@export var track_color := Color(0.18, 0.2, 0.24)
@export var charged_color := Color(1.0, 0.97, 0.85)
@export var empty_color := Color(0.42, 0.46, 0.54)

@export var damage: float = 0.0:
	set(value):
		if damage != value:
			damage = value
			queue_redraw()


func _process(_delta: float) -> void:
	# The glow pulses while charged.
	if damage > 0:
		queue_redraw()


func current_color() -> Color:
	return charged_color if damage > 0 else empty_color


func _draw() -> void:
	var centre := size * 0.5
	draw_arc(centre, radius, 0.0, TAU, 48, track_color, width, true)
	if damage <= 0:
		return
	var pulse := 0.72 + 0.28 * sin(float(Time.get_ticks_msec()) * 0.004)
	draw_circle(centre, radius + 12.0, Color(charged_color, 0.10 * pulse))
	var turns := fmod(log(float(damage)) / log(10.0), 1.0)
	draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * turns, 48, charged_color,
		width, true)


func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= radius + width
