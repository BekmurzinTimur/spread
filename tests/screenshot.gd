extends SceneTree

## Dev tool: boots the game, plays a few scripted moves, and saves a PNG.
##   Godot --path . --script res://tests/screenshot.gd
## Needs a rendering context, so it cannot run with --headless.

## Enough for the generator to have fired several times, for orbs to be strung
## out along the route, and for the target to show real unlock progress without
## having been mined yet.
const TICKS_BEFORE_CAPTURE := 140

var _frames := 0
var _main: Node


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 2:
		var world = _main.world
		# Mine a wedge out of the top-left corner, so the shot shows a real
		# mid-game board: mined cells holding what the map buried, a relocated
		# pump, and orbs in flight. Mining is also what uncovers the ring of
		# question-mark cells around the edge.
		for id in [1, 7, 2, 8, 13, 14, 3, 9]:
			world.graph.unlock_cell(id)
		# Pump pulled out of cell 2 and dropped mid-route, which is the whole
		# point of it: on the line rather than at either end of it.
		world.swap_blocks(2, 14)
		# Cell 20 is on the frontier and buries a generator — the thing worth
		# reaching, and far enough out that the route reads as a route.
		world.set_target(0, 20)

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
		_main.selected_id = 20

	# A few frames for the camera move to take and the board to draw.
	if _frames < 12:
		return false

	var image := root.get_texture().get_image()
	image.save_png("res://screenshot.png")
	print("saved screenshot.png")
	return true


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
