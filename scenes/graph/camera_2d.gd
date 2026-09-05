extends Camera2D

@export var zoom_speed: float = 0.1
@export var zoom_min: float = 0.5
@export var zoom_max: float = 3.0

var dragging: bool = false
var drag_start_mouse: Vector2
var drag_start_position: Vector2

func _ready() -> void:
	position_smoothing_enabled = false

func _unhandled_input(event: InputEvent) -> void:
	# --- Zoom with mouse wheel (regular mouse) ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(get_global_mouse_position(), 1.0 - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(get_global_mouse_position(), 1.0 + zoom_speed)

		# --- Drag panning (left mouse button) ---
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_start_mouse = get_viewport().get_mouse_position()
				drag_start_position = position
			else:
				dragging = false

	if event is InputEventMouseMotion and dragging:
		var mouse_delta: Vector2 = get_viewport().get_mouse_position() - drag_start_mouse
		position = drag_start_position - mouse_delta / zoom

	# --- Zoom with trackpad two-finger scroll (macOS) ---
	if event is InputEventPanGesture:
		var factor: float = 1.0 - event.delta.y * zoom_speed
		_zoom_at(event.position, factor)

	# --- Zoom with trackpad pinch gesture ---
	if event is InputEventMagnifyGesture:
		_zoom_at(get_viewport().get_mouse_position(), 1.0 / event.factor)

func _zoom_at(target_pos: Vector2, zoom_factor: float) -> void:
	var new_zoom: Vector2 = zoom * zoom_factor
	new_zoom.x = clamp(new_zoom.x, zoom_min, zoom_max)
	new_zoom.y = clamp(new_zoom.y, zoom_min, zoom_max)

	var before: Vector2 = get_global_mouse_position()
	zoom = new_zoom
	var after: Vector2 = get_global_mouse_position()
	position += before - after
