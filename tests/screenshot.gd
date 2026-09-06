extends SceneTree

## Dev tool: boots the game, plays a few scripted moves, and saves a PNG.
##   Godot --path . --script res://tests/screenshot.gd
## Needs a rendering context, so it cannot run with --headless.

var _frames := 0
var _main: Node


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 2:
		var world = _main.world
		# Mine out the home cluster and a route into the north cluster, so the
		# shot shows a real mid-game board: mined cells holding what the map
		# buried, a relocated pump, and orbs in flight.
		for id in [1, 2, 3, 5, 6, 9, 8]:
			world.graph.get_cell(id).unlock()
		world.swap_blocks(3, 2)          # pump pulled out toward the frontier
		world.set_target(0, 11)
		_main.selected_id = 0
		_main.speed = 4

	if _frames == 190:
		# Close in on the home cluster with a swap pending, to check that
		# buried glyphs and costs are legible at a normal working zoom.
		_main.get_node("Camera2D").position = Vector2(700, 500)
		_main.get_node("Camera2D").zoom = Vector2(0.9, 0.9)
		_main.selected_id = 16
		_main.hovered_id = 13

	if _frames < 200:
		return false

	var image := root.get_texture().get_image()
	image.save_png("res://screenshot.png")
	print("saved screenshot.png")
	return true
