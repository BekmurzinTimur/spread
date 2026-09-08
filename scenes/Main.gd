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
@onready var _splash_layer: Node2D = $Board/SplashLayer
@onready var _float_layer: Node2D = $Board/FloatingTextLayer
@onready var _hud: Control = $UI/HUD

var world: World

var selected_id: int = -1
var hovered_id: int = -1

## The cells a group command applies to, or empty for an ordinary selection.
##
## `selected_id` stays the group's **primary** — the cell that was double-clicked
## — so the side panel, the sphere-field focus and everything else that inspects
## one cell keep working with no notion of a group at all. Invariant: this is
## either empty, or its first entry is `selected_id`.
##
## A group of one is stored as no group, so "empty in the ordinary case" is
## literally true and a lone generator never draws group chrome.
var selected_ids: PackedInt32Array = PackedInt32Array()

## Set by the press that formed a group; consumed by the very next left release.
## See the double-click handshake in `_unhandled_input`.
var _suppress_next_click: bool = false

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
	# a second caller would starve the first. That matters more now than it did,
	# because one drain feeds two layers — a splash and a number — and a second
	# drainer would not halve the marks, it would take all of one kind and none of
	# the other. In particular this must not live in a _draw(), which the engine
	# may run more than once per frame.
	_spawn_delivery_effects()

	# How far into the current tick we are. GraphView uses it for generator
	# cooldowns only — unlock progress moves on deliveries, which are events with
	# nothing in between to interpolate.
	var alpha := clampf(_accumulator / World.TICK_SECONDS, 0.0, 1.0)

	_graph_view.selected_id = selected_id
	_graph_view.selected_ids = selected_ids
	_graph_view.hovered_id = hovered_id
	_graph_view.pending_via = pending_via
	_graph_view.render_alpha = alpha
	_graph_view.queue_redraw()

	_orb_layer.render_alpha = alpha
	_orb_layer.queue_redraw()

	# Both aged with real time, not simulated time, so a mark already in the air
	# finishes its arc while the game is paused rather than hanging there.
	_splash_layer.advance(delta)
	_splash_layer.queue_redraw()

	_float_layer.advance(delta)
	_float_layer.queue_redraw()

	_hud.refresh()


## Turn the tick's deliveries into the two marks a delivery leaves: a burst at the
## cell and a number over it. This is the whole sim→view translation — the
## simulation records plain data and never reaches out, neither layer knows
## anything about orbs or cells, and Main joins them.
##
## Both marks come from one event, and neither layer is told which kind of
## delivery it was. A cell being mined, an upgrader charging and an upkeep block
## refuelling all read the same, which is right: they are the same act, and the
## thing that differs — where the value went — is what the cell itself draws.
##
## The number is what actually counted toward the unlock, so it always matches
## the progress arc's jump — an orb worth 11 landing on a cell needing 3 reads
## "+3", and the overshoot is not announced because it went nowhere. The splash
## is sized by that same figure, so a burst that looks small is a delivery that
## counted for little rather than one that was worth little.
func _spawn_delivery_effects() -> void:
	var orb_value := float(world.effective_orb_value())
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
		var color := Tiers.color_of(event.tier)

		# Measured against what an orb launches with *now*, so a Surged board does
		# not turn every ordinary delivery into a maximum-size burst. The layer
		# clamps the result, so a zero orb value here could only ever flatten the
		# scale rather than divide by zero — but it cannot be zero anyway.
		_splash_layer.spawn(cell.position, color, float(event.amount) / orb_value, age)

		_float_layer.spawn(
			"+%d" % event.amount,
			color,
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
		# A double-click arrives on the **press** of the second click, and there
		# is no marker on the release that follows — so a group has to be formed
		# here and the release it drags behind it suppressed, or `_on_click`
		# collapses the group straight back to one cell.
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed \
				and event.double_click:
			_on_double_click(_cell_at(_camera.screen_to_world(event.position)))
			return

		# Selection happens on release, not press, and only when the camera did
		# not treat this press as a drag — left-drag pans, a clean left click
		# selects. The camera sets `panned` on motion, which always precedes
		# this release, so the handshake does not depend on input ordering.
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# Cleared on *any* left release, before the `panned` test and whether
			# or not it was set. A drag begun on the group-forming press would
			# otherwise leave it armed and eat the next, unrelated click. The two
			# verdicts stay independent: the camera resets `panned` on that same
			# press, so dragging after forming a group pans without dissolving it.
			var suppressed := _suppress_next_click
			_suppress_next_click = false
			if not suppressed and not _camera.panned:
				_on_click(_cell_at(_camera.screen_to_world(event.position)))
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_on_aim_click(_cell_at(_camera.screen_to_world(event.position)),
				event.shift_pressed)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				clear_waypoints()
				selected_id = -1
				selected_ids = PackedInt32Array()
			KEY_BACKSPACE:
				# Backs a waypoint chain out one step at a time, so a misclick
				# costs one cell rather than the whole route. Right-click used to
				# do this; it now aims, so the undo needs a key of its own.
				if not pending_via.is_empty():
					pending_via.remove_at(pending_via.size() - 1)
			KEY_A:
				toggle_auto_aim()
			KEY_SPACE:
				paused = not paused
			KEY_1:
				speed = 1
			KEY_2:
				speed = 4
			KEY_3:
				speed = 16


func _on_click(cell_id: int) -> void:
	# Selecting something else abandons the chain drawn from the old cell, or it
	# would leak onto the next block the player picks up.
	if cell_id != selected_id:
		pending_via = PackedInt32Array()
	selected_id = cell_id
	# Any ordinary click dissolves a group. There is no way to add one cell to a
	# group or take one out, which is deliberate: the group is defined by a rule
	# — this type, on this screen — and hand-editing it would make it a thing to
	# maintain rather than a thing to form and use.
	selected_ids = PackedInt32Array()


## Double-click an aimable block and every block of the same type visible on
## screen joins the selection, so one right-click aims all of them and one
## shift-chain bends all their routes.
##
## "Same type" is `def.id`, which for a generator is exactly "same tier" — the
## catalog registers one generator def per tier — and generalises to the
## upgraders for free. A block that takes no target falls through to ordinary
## selection: there is nothing to aim, so a group would do nothing.
##
## Bounded by what is on screen rather than by the whole board, deliberately. A
## group is something the player can see and check before committing to it; a
## board-wide select would quietly rope in generators behind ground cleared
## twenty hops ago and re-aim them from a decision made off-screen. Zooming out
## is how you widen it, which keeps "what will this affect" answerable by looking.
func _on_double_click(cell_id: int) -> void:
	if cell_id == -1:
		return
	var cell := world.graph.get_cell(cell_id)
	if cell == null or cell.block == null \
			or not (cell.block.def.needs_target or cell.block.def.has_ports()):
		# Not suppressed: the release that follows selects this cell the ordinary
		# way, so a double-click on a pump is just a click on a pump.
		return

	var found: PackedInt32Array = world.cells_with_def_in_rect(
		cell.block.def.id, _camera.visible_world_rect())
	if found.size() < 2:
		return  # a group of one is no group; leave the plain click to do its work

	if cell_id != selected_id:
		pending_via = PackedInt32Array()
	selected_id = cell_id
	selected_ids = _primary_first(found, cell_id)
	_suppress_next_click = true


## `ids` with `primary` moved to the front. The one place the "the group's first
## entry is `selected_id`" invariant is established, so there is a single line to
## check it against.
static func _primary_first(ids: PackedInt32Array, primary: int) -> PackedInt32Array:
	var out := PackedInt32Array([primary])
	for id in ids:
		if id != primary:
			out.append(id)
	return out


## Every cell an aim command applies to: the group when one is up, the primary
## otherwise. One accessor, so no aim path has to branch on group-versus-single —
## and the single case runs the same code it always did, because a batch of one
## is the old call.
func aim_targets() -> PackedInt32Array:
	if not selected_ids.is_empty():
		return selected_ids
	if selected_id == -1:
		return PackedInt32Array()
	return PackedInt32Array([selected_id])


## Right-click: do what the selected cell does with a destination. Shift extends
## the route through it instead.
##
## Nothing here has a mode. Left-click is selection and right-click was free, so
## a block is aimed — or moved — by picking it up and right-clicking where it
## should go, which is one click rather than three and leaves nothing to cancel.
##
## **There are three readings now, and they can never collide**, because
## `needs_target`, `movable` and `has_ports()` are pairwise disjoint across the
## catalog: generators, upgraders and compressors are aimed and anchored; pumps,
## amplifiers, spheres, teleporters and upkeep blocks are moved and take no
## target; a distributor has ports and is neither. So the fork below is total, and
## a selection never has two meanings for one click.
## `test_target_movable_and_ports_are_pairwise_disjoint` is what holds that.
##
## The ports branch sits **ahead of** the swap fallback rather than after it. A
## distributor is `movable = false`, so falling through would hand it to
## `_on_swap_click`, where `can_swap` refuses everything anchored — the gesture
## would silently do nothing and the block would be inert on the board.
func _on_aim_click(cell_id: int, shift: bool) -> void:
	var source := selected_cell()
	if source == null:
		return
	if source.block != null and source.block.def.has_ports():
		_on_port_click(cell_id, shift)
		return
	if source.block == null or not source.block.def.needs_target:
		# Nothing to aim, so this is the swap gesture. Shift is the bend-a-route
		# modifier and means nothing here — deliberately inert rather than
		# aliased to a plain swap, because a stray shift should not fling a pump
		# across the board.
		if not shift:
			_on_swap_click(cell_id)
		return
	if cell_id == -1 or cell_id == selected_id:
		return

	# The group when one is up, the primary alone otherwise. A batch of one is
	# the old single-block call, so nothing below branches on which it is.
	var sources := aim_targets()

	if not shift:
		# Partial success: the sources that can take this target do, and the ones
		# that cannot keep the route they already had. That policy lives in
		# `set_target_batch` and nowhere else.
		if world.set_target_batch(sources, cell_id, pending_via) > 0:
			pending_via = PackedInt32Array()
		return

	if pending_via.size() >= World.MAX_WAYPOINTS:
		return
	var candidate := pending_via.duplicate()
	candidate.append(cell_id)
	# Refused as it is clicked rather than at commit time, so the player never
	# builds a chain that turns out to be unroutable — or to cross itself — only
	# at the end. `count_routable_through` resolves the same walks `set_target`
	# will. For a group the bar is "somebody can walk it" rather than "everybody
	# can": a corner that splits the group is a legal thing to draw, and the
	# preview shows the split before it is committed to.
	if world.count_routable_through(sources, candidate) == 0:
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
	world.set_target_batch(sources, cell_id, pending_via)


## Right-click with a ported block selected: add this cell as an output, or drop
## it if it is already one.
##
## **A toggle, so there is still no mode.** The other two gestures set something;
## this one flips it, which is the only shape that lets a player both build and
## unpick a fan-out with the one button they already have. Nothing to arm, nothing
## to cancel, and the same right-click that made an output removes it.
##
## Shift extends the chain exactly as it does for an aim, and for the same reason:
## a distributor's outputs are routes like any other and deserve the same
## waypoints. The chain clears on a successful toggle so the next output starts
## from the block again rather than inheriting the last one's corners.
func _on_port_click(cell_id: int, shift: bool) -> void:
	if cell_id == -1 or cell_id == selected_id:
		return
	var sources := aim_targets()

	if not shift:
		if world.toggle_port_batch(sources, cell_id, pending_via) > 0:
			pending_via = PackedInt32Array()
		return

	if pending_via.size() >= World.MAX_WAYPOINTS:
		return
	var candidate := pending_via.duplicate()
	candidate.append(cell_id)
	if world.count_routable_through(sources, candidate) == 0:
		return
	pending_via = candidate
	if world.toggle_port_batch(sources, cell_id, pending_via) > 0:
		pending_via = PackedInt32Array()


## Right-click with something movable selected: trade contents with this cell.
##
## Valid from any mined cell, empty included — `can_swap` treats an empty end as
## a move, so an empty selection *pulls* a block toward you rather than pushing
## one away, and both directions read the same.
##
## Immediate and unconfirmed. What stands in for a confirmation is that the board
## has already drawn the line and the refusal under the cursor before the click,
## that `can_swap` refuses everything anchored, and that a swap is its own undo —
## right-click back and the two cells trade again.
##
## **Selection follows the block**, so moves chain: right-click, right-click
## again, and a pump walks across the board without ever being re-selected. That
## is the point of dropping the mode — one click per move — and leaving the
## selection behind would have cost a click back for every hop.
##
## Following the *block* rather than the clicked cell is what makes the pull
## direction work. A push moves the block from here to there, so the selection
## goes with it. A pull brings a block *to* the selected cell, and there the
## clicked cell is the one left empty — chasing it would strand the selection on
## nothing and break the chain the moment it started. So the direction is decided
## before the swap, by whether this cell had anything to give.
func _on_swap_click(cell_id: int) -> void:
	if cell_id == -1 or cell_id == selected_id:
		return
	var pushing: bool = selected_cell().block != null
	if world.swap_blocks(selected_id, cell_id) and pushing:
		selected_id = cell_id


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
	return cell != null and cell.block != null \
		and (cell.block.def.needs_target or cell.block.def.has_ports())


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
	clear_waypoints()
	selected_id = next
	# The indicator sends you to one cell, so it hands back a single selection.
	# Double-clicking it is then how you pick up the rest of that colour.
	selected_ids = PackedInt32Array()
	_camera.position = world.graph.get_cell(next).position


## Drop the half-drawn waypoint chain. Named for the one thing it does now: it
## used to also cancel the swap mode, and there is no mode left to cancel.
func clear_waypoints() -> void:
	pending_via = PackedInt32Array()


func toggle_pause() -> void:
	paused = not paused


## Hand the unpinned blocks over to auto-aim, or take them back.
##
## A thin caller: the flag and the pass both live in `World`, because both write
## block targets and both are worth testing headlessly.
func toggle_auto_aim() -> void:
	world.set_auto_aim(not world.auto_aim)


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
