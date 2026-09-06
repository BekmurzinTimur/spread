extends Node2D

## Owns the simulation and drives it on a fixed tick, independent of frame rate.
##
## The World is a plain object, not an autoload and not a node, so the whole
## economy stays testable headlessly. Everything below this line is presentation
## and input; it reads the sim and issues commands, never reaches inside it.

const MAP_PATH := "res://data/map_01.json"

## Guards against a spiral of death after a stall (or a breakpoint) — we drop
## simulated time rather than trying to catch up unboundedly.
const MAX_TICKS_PER_FRAME := 240

@onready var _camera: Camera2D = $Camera2D
@onready var _graph_view: Node2D = $Board/GraphView
@onready var _orb_layer: Node2D = $Board/OrbLayer
@onready var _hud: Control = $UI/HUD

var world: World

var selected_id: int = -1
var hovered_id: int = -1

## Two-step interactions: pick a source cell, then click a second cell to
## complete. Mutually exclusive.
var aiming: bool = false
var swapping: bool = false

var paused: bool = false
var speed: int = 1

var _accumulator: float = 0.0


func _ready() -> void:
	var graph := MapLoader.load_from_file(MAP_PATH)
	if graph == null:
		push_error("Main: failed to load %s" % MAP_PATH)
		return

	world = World.new(graph)
	_graph_view.world = world
	_orb_layer.world = world
	_hud.setup(self)

	_frame_camera_on_start()


func _process(delta: float) -> void:
	if world == null:
		return

	if not paused:
		_accumulator += delta * float(speed)
		var steps := 0
		while _accumulator >= World.TICK_SECONDS and steps < MAX_TICKS_PER_FRAME:
			world.tick()
			_accumulator -= World.TICK_SECONDS
			steps += 1
		if steps == MAX_TICKS_PER_FRAME:
			_accumulator = 0.0

	_graph_view.selected_id = selected_id
	_graph_view.hovered_id = hovered_id
	_graph_view.aiming = aiming
	_graph_view.swapping = swapping
	_graph_view.queue_redraw()

	_orb_layer.render_alpha = clampf(_accumulator / World.TICK_SECONDS, 0.0, 1.0)
	_orb_layer.queue_redraw()

	_hud.refresh()


# --- Input --------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return

	if event is InputEventMouseMotion:
		hovered_id = _cell_at(_camera.screen_to_world(event.position))
		return

	if event is InputEventMouseButton:
		# Selection happens on release, not press, and only when the camera did
		# not treat this press as a drag — left-drag pans, a clean left click
		# selects. The camera sets `panned` on motion, which always precedes
		# this release, so the handshake does not depend on input ordering.
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if not _camera.panned:
				_on_click(_cell_at(_camera.screen_to_world(event.position)))
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_pending()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				cancel_pending()
				selected_id = -1
			KEY_SPACE:
				paused = not paused
			KEY_1:
				speed = 1
			KEY_2:
				speed = 4
			KEY_3:
				speed = 16
			KEY_A:
				begin_aim()
			KEY_S:
				begin_swap()


func _on_click(cell_id: int) -> void:
	if aiming:
		# A click on empty space, or an unroutable target, just cancels.
		if cell_id != -1:
			world.set_target(selected_id, cell_id)
		aiming = false
		return

	if swapping:
		if cell_id != -1:
			world.swap_blocks(selected_id, cell_id)
		swapping = false
		return

	selected_id = cell_id


## Nearest cell under the cursor, or -1. Cheap linear scan — the map is small,
## and this avoids a collision shape per cell.
func _cell_at(world_pos: Vector2) -> int:
	var radius: float = _graph_view.CELL_RADIUS * 1.35
	var best_id := -1
	var best_distance := radius * radius
	for id in world.graph.cell_ids:
		var d := world.graph.get_cell(id).position.distance_squared_to(world_pos)
		if d < best_distance:
			best_distance = d
			best_id = id
	return best_id


# --- Commands issued by the HUD ----------------------------------------


func selected_cell() -> GraphCell:
	if selected_id == -1 or world == null:
		return null
	return world.graph.get_cell(selected_id)


func begin_aim() -> void:
	var cell := selected_cell()
	if cell != null and cell.block != null and cell.block.def.needs_target:
		swapping = false
		aiming = true


## Start a swap from the selected cell. Valid from any mined cell — including
## an empty one, so a block can be pulled toward you as well as pushed away.
func begin_swap() -> void:
	var cell := selected_cell()
	if cell != null and cell.is_unlocked:
		aiming = false
		swapping = true


func cancel_pending() -> void:
	aiming = false
	swapping = false


func toggle_pause() -> void:
	paused = not paused


func set_speed(value: int) -> void:
	speed = value


func _frame_camera_on_start() -> void:
	var start := world.graph.get_cell(world.graph.cell_ids[0])
	if start != null:
		_camera.position = start.position + Vector2(360, 0)
	_camera.zoom = Vector2(0.6, 0.6)
