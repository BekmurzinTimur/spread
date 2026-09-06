extends SceneTree

## Dev tool: boots the game, plays a few scripted moves, and saves a PNG.
##   Godot --path . --script res://tests/screenshot.gd
## Needs a rendering context, so it cannot run with --headless.

## Enough for the generator to have fired several times, for orbs to be strung
## out along the route, and for the target to show real unlock progress without
## having been mined yet — a mined target unaims its generator and empties the
## board, which is the one thing the shot must not catch.
const TICKS_BEFORE_CAPTURE := 100

## How much of the board to open before the shot. Enough for a frontier ring, a
## couple of buried blocks, and a route with an interior to put a pump on.
const MINED_CELLS := 9

var _frames := 0
var _main: Node


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 2:
		var world = _main.world
		var start := _start_cell()
		# Open a patch around the start, so the shot shows a real mid-game board:
		# mined cells holding what the map buried, a pump on a route, and orbs in
		# flight. Mining is also what uncovers the ring of question-mark cells
		# around the edge. Derived from the start rather than a list of ids —
		# regenerating the map moves every one of them.
		for id in _nearest_to(start, MINED_CELLS):
			world.graph.unlock_cell(id)

		# The frontier cell farthest from the start: far enough out that the
		# route reads as a route, and unmined, so it shows its cost and arc.
		var target := _farthest_frontier(start)
		world.set_target(start, target)
		# A pump dropped mid-route, which is the whole point of it: on the line
		# rather than at either end of it.
		var pump := _block_on_a_mined_cell(BlockCatalog.PUMP)
		var route: PackedInt32Array = world.graph.find_path(start, target)
		if pump != -1 and route.size() > 3:
			world.swap_blocks(pump, route[route.size() - 3])
			# And a sphere parked next to that pump, so the shot shows the field
			# highlight and a boosted block rather than only the two original
			# types. Beside the route, not on it — a sphere occupies a cell and
			# would otherwise displace the pump it is there to help.
			var sphere := _block_on_a_mined_cell(BlockCatalog.SPHERE)
			if sphere != -1:
				for n in world.graph.get_cell(route[route.size() - 3]).neighbor_ids:
					var cell = world.graph.get_cell(n)
					if cell.is_unlocked and cell.block == null:
						world.swap_blocks(sphere, n)
						break

		# Step the simulation directly and then hold it, rather than letting it
		# run on wall-clock across the frames below. How many ticks elapse by
		# frame 190 depends on how fast the machine renders, which made the shot
		# differ run to run — once catching the board before the generator had
		# even fired. This lands on the same tick every time.
		for i in TICKS_BEFORE_CAPTURE:
			world.tick()
		_main.paused = true
		# Drop the leftover part-tick as well. Orbs are drawn interpolated by it,
		# so whatever real time passed before this frame would otherwise shift
		# every orb a fraction of a hop and make two runs differ.
		_main.set("_accumulator", 0.0)

		# Frame the discovered region rather than a fixed point: under fog most
		# of the map is not drawn, and a hardcoded camera lands on empty space.
		_frame_discovered()
		# The target cell: unmined, so it shows a question mark and its cost, and
		# part-fed, so it shows the unlock arc.
		_main.selected_id = target

	# A few frames for the camera move to take and the board to draw.
	if _frames < 12:
		return false

	var image := root.get_texture().get_image()
	image.save_png("res://screenshot.png")
	print("saved screenshot.png")
	return true


## The cell the map hands over already mined. Everything below is measured from
## it, so the script survives a regenerated map.
func _start_cell() -> int:
	var world = _main.world
	for id in world.graph.cell_ids:
		if world.graph.get_cell(id).is_unlocked:
			return id
	return -1


## The `count` cells closest to `from`, nearest first — the patch a player would
## plausibly have opened by now. Ties break on the lower id, like everything else.
func _nearest_to(from: int, count: int) -> Array[int]:
	var world = _main.world
	var ids: Array[int] = []
	for id in world.graph.cell_ids:
		if id != from:
			ids.append(id)
	ids.sort_custom(func(a, b):
		var da: int = world.graph.distance_unrestricted(from, a)
		var db: int = world.graph.distance_unrestricted(from, b)
		return a < b if da == db else da < db
	)
	return ids.slice(0, count)


## The uncovered, unmined cell farthest from the start: the one worth aiming at.
## Farthest, so the route reads as a route and the cell is dear enough to still
## be part-fed when the shot is taken.
func _farthest_frontier(from: int) -> int:
	var world = _main.world
	var best := -1
	var best_hops := -1
	for id in world.graph.cell_ids:
		var cell = world.graph.get_cell(id)
		if cell.is_unlocked or not world.graph.is_discovered(id):
			continue
		var hops: int = world.graph.distance(from, id)
		if hops > best_hops:
			best_hops = hops
			best = id
	return best


## A block of this type sitting on a mined cell, ready to be moved onto the
## route. -1 if the patch that was opened happened not to turn one up.
func _block_on_a_mined_cell(def_id: String) -> int:
	var world = _main.world
	for id in world.graph.cell_ids:
		var block = world.graph.get_cell(id).block
		if block != null and block.def.id == def_id:
			return id
	return -1


## Fit the camera to everything the player can currently see, with a margin, so
## the shot stays useful as the discovered region grows.
func _frame_discovered() -> void:
	var world = _main.world
	var bounds := Rect2()
	var found := false
	for id in world.graph.cell_ids:
		if not world.graph.is_discovered(id):
			continue
		var pos: Vector2 = world.graph.get_cell(id).position
		if found:
			bounds = bounds.expand(pos)
		else:
			bounds = Rect2(pos, Vector2.ZERO)
			found = true
	if not found:
		return

	var camera: Camera2D = _main.get_node("Camera2D")
	var viewport := Vector2(root.get_viewport().size) - Vector2(420, 140)
	var span := bounds.size + Vector2(160, 160)
	var fit: float = minf(viewport.x / span.x, viewport.y / span.y)
	camera.position = bounds.get_center()
	camera.zoom = Vector2(fit, fit)
