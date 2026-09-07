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

## Close enough to read the opening handful of cells. The player zooms out as the
## discovered region grows.
const START_ZOOM := 1.0

@onready var _camera: Camera2D = $Camera2D
@onready var _graph_view: Node2D = $Board/GraphView
@onready var _orb_layer: Node2D = $Board/OrbLayer
@onready var _float_layer: Node2D = $Board/FloatingTextLayer
@onready var _hud: Control = $UI/HUD

var world: World

var selected_id: int = -1
var hovered_id: int = -1

## Swapping is the one remaining two-step interaction: pick a source cell, then
## click a second to complete. Aiming used to be another; it is now a direct
## right-click on the destination, so it needs no mode.
var swapping: bool = false

## Cells the route being drawn must pass through, in the order they were
## shift-right-clicked. Lives here rather than on the block because it is a
## half-built command: the block's own `route_via` is whatever was last
## committed, and this is the chain the player is still extending.
var pending_via: PackedInt32Array = PackedInt32Array()

var paused: bool = false
var speed: int = 1

var _accumulator: float = 0.0

## Block type id -> the idle cell the player was last sent to, so repeated
## clicks on one indicator walk through them rather than sticking on the first.
var _idle_cursor: Dictionary = {}


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

	# Drained here and nowhere else: take_delivery_events() empties the buffer, so
	# a second caller would starve the first. In particular this must not live in
	# a _draw(), which the engine may run more than once per frame.
	_spawn_delivery_texts()

	# How far into the current tick we are. GraphView uses it for generator
	# cooldowns only — unlock progress moves on deliveries, which are events with
	# nothing in between to interpolate.
	var alpha := clampf(_accumulator / World.TICK_SECONDS, 0.0, 1.0)

	_graph_view.selected_id = selected_id
	_graph_view.hovered_id = hovered_id
	_graph_view.swapping = swapping
	_graph_view.pending_via = pending_via
	_graph_view.render_alpha = alpha
	_graph_view.queue_redraw()

	_orb_layer.render_alpha = alpha
	_orb_layer.queue_redraw()

	# Aged with real time, not simulated time, so a number already in the air
	# finishes its arc while the game is paused rather than hanging there.
	_float_layer.advance(delta)
	_float_layer.queue_redraw()

	_hud.refresh()


## Turn the tick's deliveries into floating numbers. This is the whole sim→view
## translation: the simulation records plain data and never reaches out, the text
## layer knows nothing about orbs or cells, and Main joins the two.
##
## The number is what actually counted toward the unlock, so it always matches
## the progress arc's jump — an orb worth 11 landing on a cell needing 3 reads
## "+3", and the overshoot is not announced because it went nowhere.
func _spawn_delivery_texts() -> void:
	for event in world.take_delivery_events():
		var cell := world.graph.get_cell(event.cell_id)
		if cell == null:
			continue
		# Back-dated by how long ago the delivery actually happened. Usually zero
		# — the drain follows the tick that recorded it — but a frame that caught
		# several ticks up would otherwise start them all together and print them
		# on top of each other. This is the only thing draining destroys, which is
		# why the event carries its tick.
		var age := float(world.tick_count - event.tick) * World.TICK_SECONDS
		_float_layer.spawn(
			"+%d" % event.amount,
			Tiers.color_of(event.tier),
			cell.position + Vector2(0.0, -_graph_view.CELL_RADIUS - 6.0),
			age
		)


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
			_on_aim_click(_cell_at(_camera.screen_to_world(event.position)),
				event.shift_pressed)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				cancel_pending()
				selected_id = -1
			KEY_BACKSPACE:
				# Backs a waypoint chain out one step at a time, so a misclick
				# costs one cell rather than the whole route. Right-click used to
				# do this; it now aims, so the undo needs a key of its own.
				if not pending_via.is_empty():
					pending_via.remove_at(pending_via.size() - 1)
			KEY_SPACE:
				paused = not paused
			KEY_1:
				speed = 1
			KEY_2:
				speed = 4
			KEY_3:
				speed = 16
			KEY_S:
				begin_swap()


func _on_click(cell_id: int) -> void:
	if swapping:
		if cell_id != -1:
			world.swap_blocks(selected_id, cell_id)
		swapping = false
		return

	# Selecting something else abandons the chain drawn from the old cell, or it
	# would leak onto the next block the player picks up.
	if cell_id != selected_id:
		pending_via = PackedInt32Array()
	selected_id = cell_id


## Right-click: aim the selected block at this cell. Shift extends the route
## through it instead.
##
## Aiming has no mode. Left-click is selection and right-click was free, so a
## block is aimed by picking it up and right-clicking where it should fire —
## which is one click rather than three, and leaves nothing to cancel.
func _on_aim_click(cell_id: int, shift: bool) -> void:
	if swapping:
		# Right-click still backs out of a swap, which is the one mode left.
		cancel_pending()
		return

	var source := selected_cell()
	if source == null or source.block == null or not source.block.def.needs_target:
		return
	if cell_id == -1 or cell_id == selected_id:
		return

	if not shift:
		if world.set_target(selected_id, cell_id, pending_via):
			pending_via = PackedInt32Array()
		return

	if pending_via.size() >= World.MAX_WAYPOINTS:
		return
	var candidate := pending_via.duplicate()
	candidate.append(cell_id)
	# Refused as it is clicked rather than at commit time, so the player never
	# builds a chain that turns out to be unroutable — or to cross itself — only
	# at the end. `can_route_through` resolves the same walk `set_target` will.
	if not world.can_route_through(selected_id, candidate):
		return
	pending_via = candidate

	# A chain aims as it is drawn: the moment a cell added to it is a legal
	# destination the block fires at it, rather than waiting for a committing
	# click that may never come. If it is not one — a mined cell with no intake,
	# or the wrong colour — `set_target` refuses and it stays a pure waypoint
	# with the previous target untouched. Letting the simulation's own verdict
	# decide keeps the rules in one place.
	#
	# The whole chain is passed, trailing cell and all: `normalize_via` drops the
	# entry that merely names the target, so the block stores the waypoints and
	# nothing else. The chain itself is kept here so the next shift-click extends
	# past this destination rather than starting over.
	world.set_target(selected_id, cell_id, pending_via)


## Nearest discovered cell under the cursor, or -1. Cheap linear scan — the map
## is small, and this avoids a collision shape per cell.
##
## Undiscovered cells are skipped, so ground the player has not uncovered cannot
## be hovered or selected. It is not drawn either, and clicking an invisible cell
## would be the one way to find out something is there.
func _cell_at(world_pos: Vector2) -> int:
	var radius: float = _graph_view.CELL_RADIUS * 1.35
	var best_id := -1
	var best_distance := radius * radius
	for id in world.graph.cell_ids:
		if not world.graph.is_discovered(id):
			continue
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


## Whether the selected cell holds something that can be aimed. The view and the
## HUD both key off this — there is no aim *mode* any more, so "is this block
## aimable" is the whole of the state that used to be a flag.
func can_aim_selection() -> bool:
	var cell := selected_cell()
	return cell != null and cell.block != null and cell.block.def.needs_target


## Start a swap from the selected cell. Valid from any mined cell — including
## an empty one, so a block can be pulled toward you as well as pushed away.
func begin_swap() -> void:
	var cell := selected_cell()
	if cell != null and cell.is_unlocked:
		swapping = true
		pending_via = PackedInt32Array()


## Jump to the next block of this type that is sitting idle, and select it so the
## panel opens on it and a right-click aims it straight away.
##
## The camera is moved outright rather than eased: camera_2d.gd disables position
## smoothing on purpose, and turning it back on would leave the camera tests
## asserting against a position still in motion.
func focus_next_idle(def_id: String) -> void:
	if world == null:
		return
	var last: int = _idle_cursor.get(def_id, -1)
	var next: int = world.next_idle_after(def_id, last)
	if next == -1:
		_idle_cursor.erase(def_id)
		return

	_idle_cursor[def_id] = next
	cancel_pending()
	selected_id = next
	_camera.position = world.graph.get_cell(next).position


func cancel_pending() -> void:
	swapping = false
	pending_via = PackedInt32Array()


func toggle_pause() -> void:
	paused = not paused


func set_speed(value: int) -> void:
	speed = value


## Frame what the player can actually see. At the start that is one generator and
## its neighbours, so the old fixed offset and wide zoom — which framed a fully
## visible map — would open on a speck adrift in empty space.
func _frame_camera_on_start() -> void:
	var bounds := Rect2()
	var found := false
	for id in world.graph.cell_ids:
		if not world.graph.is_discovered(id):
			continue
		var pos := world.graph.get_cell(id).position
		if found:
			bounds = bounds.expand(pos)
		else:
			bounds = Rect2(pos, Vector2.ZERO)
			found = true

	if not found:
		return
	_camera.position = bounds.get_center()
	_camera.zoom = Vector2(START_ZOOM, START_ZOOM)
