@tool
class_name HexPanel
extends Control

## A pointy-top hexagon filling the rect, like the board's. Hover and clicks follow its outline.

@export var fill_color := Color(0.45, 0.2, 0.2):
	set(value):
		if fill_color != value:
			fill_color = value
			queue_redraw()

@export var outline_color := Color(0.9, 0.4, 0.4):
	set(value):
		if outline_color != value:
			outline_color = value
			queue_redraw()

@export_range(0.0, 16.0) var outline_width := 4.0:
	set(value):
		outline_width = value
		queue_redraw()


## Share of the hex filled from the top down with `readiness_color`.
@export_range(0.0, 1.0) var readiness := 0.0:
	set(value):
		if readiness != value:
			readiness = value
			queue_redraw()

@export var readiness_color := Color(0.6, 0.3, 0.3):
	set(value):
		if readiness_color != value:
			readiness_color = value
			queue_redraw()


func _draw() -> void:
	var points := _points()
	draw_colored_polygon(points, fill_color)
	if readiness >= 1.0:
		draw_colored_polygon(points, readiness_color)
	elif readiness > 0.0:
		# Clipped to the hex, so the fill never overflows it.
		var top := points[0].y
		var bottom := lerpf(top, points[3].y, readiness)
		var band := PackedVector2Array([Vector2(0.0, top), Vector2(size.x, top),
			Vector2(size.x, bottom), Vector2(0.0, bottom)])
		for part in Geometry2D.intersect_polygons(points, band):
			draw_colored_polygon(part, readiness_color)
	if outline_width > 0.0:
		points.append(points[0])
		draw_polyline(points, outline_color, outline_width, true)


func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, _points())


func _points() -> PackedVector2Array:
	var centre := size * 0.5
	var radius := minf(size.x / sqrt(3.0), size.y * 0.5) - outline_width * 0.5
	var points := PackedVector2Array()
	for i in 6:
		var angle := TAU * float(i) / 6.0 - PI * 0.5
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points
