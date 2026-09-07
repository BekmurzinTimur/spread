extends Camera2D

## Pan with a left-button drag, zoom toward the cursor.
##
## Left-drag and left-click-to-select share a button, so this script owns the
## distinction: `panned` says whether the current press has moved far enough to
## count as a drag. Main reads it on release and only selects when it is false.
## Motion events always precede the release in time, so that handshake does not
## depend on _unhandled_input ordering.
##
## Positions come off the event rather than from
## get_viewport().get_mouse_position() so the camera can be driven by synthetic
## events in headless tests — the viewport's real mouse does not follow those.

@export var zoom_speed: float = 0.1
## Low enough to frame the whole board. The honeycomb spans roughly 7,200 x 6,300
## world units, so anything above ~0.15 leaves a corner of the map permanently out
## of view — and "where is my idle purple generator" is a question the player has
## to be able to answer by zooming out rather than only through the idle
## indicator. This is a **board-size** constant in disguise: it moves whenever
## COLS/ROWS in `tools/gen_map.py` do.
@export var zoom_min: float = 0.13
@export var zoom_max: float = 3.0

## Pixels of movement before a press stops being a click and becomes a drag.
@export var drag_threshold: float = 4.0

## True once the current (or most recent) left press has moved past the
## threshold. Read by Main to suppress the click that ends a drag.
var panned: bool = false

var _dragging: bool = false
var _press_screen_position: Vector2 = Vector2.ZERO
var _press_camera_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_at(event.position, 1.0 - zoom_speed)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_at(event.position, 1.0 + zoom_speed)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_begin_drag(event.position)
				else:
					_dragging = false
		return

	if event is InputEventMouseMotion and _dragging:
		var moved: Vector2 = event.position - _press_screen_position
		if not panned and moved.length() > drag_threshold:
			panned = true
		if panned:
			position = _press_camera_position - moved / zoom
		return

	# Trackpad two-finger scroll.
	if event is InputEventPanGesture:
		zoom_at(event.position, 1.0 - event.delta.y * zoom_speed)
		return

	# Trackpad pinch.
	if event is InputEventMagnifyGesture:
		zoom_at(event.position, 1.0 / event.factor)


func _begin_drag(screen_position: Vector2) -> void:
	_dragging = true
	panned = false
	_press_screen_position = screen_position
	_press_camera_position = position


## Zoom so that the world point under `screen_position` stays put.
func zoom_at(screen_position: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_position)
	zoom = Vector2(
		clampf(zoom.x * factor, zoom_min, zoom_max),
		clampf(zoom.y * factor, zoom_min, zoom_max)
	)
	position += before - screen_to_world(screen_position)


## Derived from the camera's own transform rather than the viewport's canvas
## transform or get_screen_center_position(), both of which are only refreshed
## when the camera next processes — reading either back immediately after
## assigning `position` gives a stale centre and breaks zoom-toward-cursor.
## `global_position` has no such lag, so the mapping is exact the instant zoom
## changes, and it works headless.
##
## Assumes the default anchor mode with no rotation, offset or limits, which is
## how this camera is configured.
func screen_to_world(screen_position: Vector2) -> Vector2:
	return global_position + (screen_position - get_viewport_rect().size * 0.5) / zoom


## The world-space rectangle currently on screen.
##
## Lives here rather than in `Main` because this script already owns the screen↔
## world bridge, and so this inherits both `screen_to_world`'s headless-safety and
## its assumptions — default anchor, no rotation, no offset, no limits. It is also
## the only piece of input with headless coverage, so putting the one new bit of
## geometry here means it gets pinned rather than eyeballed.
##
## What it is for: a double-click selects every block of one type *on screen*, so
## the group is something the player can see and check rather than a board-wide
## command issued blind. This is the "on screen" half of that.
func visible_world_rect() -> Rect2:
	return Rect2(screen_to_world(Vector2.ZERO), get_viewport_rect().size / zoom)
