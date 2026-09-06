extends SceneTree

## Headless test suite for the simulation. No external dependency.
##
##   ./run_tests.sh
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Exits 1 on any failure.

var _passed := 0
var _failed := 0
var _current := ""
var _current_failed := false
var _done := false


## Tests run on the first frame rather than in _initialize, because nodes added
## during _initialize are not yet inside the tree — which the camera cases need
## for viewport queries.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run_all()
	return true


func _run_all() -> void:
	var tests: Array[String] = [
		"test_decay_over_hops",
		"test_orb_evaporates",
		"test_pump_restores",
		"test_pump_not_applied_on_arrival",
		"test_decay_kills_before_pump",
		"test_pump_chain_extends_reach",
		"test_unlock_exact",
		"test_unlock_overshoot_is_wasted",
		"test_no_target_idles",
		"test_unaimed_generator_banks_nothing",
		"test_self_target_rejected",
		"test_retarget_cancels_in_flight",
		"test_unlock_installs_map_block",
		"test_unlock_of_empty_cell_stays_empty",
		"test_swap_exchanges_blocks",
		"test_swap_into_empty_is_a_move",
		"test_swap_rejects_locked_cells",
		"test_swap_cancels_in_flight",
		"test_swap_clears_self_target",
		"test_swapped_generator_keeps_working",
		"test_camera_left_drag_pans",
		"test_camera_click_without_drag_does_not_pan",
		"test_camera_middle_drag_does_nothing",
		"test_camera_wheel_zooms_toward_cursor",
		"test_path_determinism",
		"test_path_tie_break_is_lowest_id",
		"test_locked_cells_are_traversable",
		"test_projected_arrival_matches_reality",
		"test_tick_order_independent",
		"test_value_conservation",
		"test_shipped_map_is_valid",
		"test_shipped_map_is_a_web",
	]

	print("")
	for name in tests:
		_current = name
		_current_failed = false
		call(name)
		if _current_failed:
			_failed += 1
		else:
			_passed += 1
			print("  %s %s" % [_pad(name), "ok"])

	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --- Assertions ---------------------------------------------------------


func _pad(s: String) -> String:
	return (s + " ").rpad(44, ".")


func _fail(message: String) -> void:
	if not _current_failed:
		print("  %s FAILED" % _pad(_current))
	_current_failed = true
	print("      %s" % message)


func check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func check_eq(actual, expected, message: String) -> void:
	if actual != expected:
		_fail("%s — expected %s, got %s" % [message, expected, actual])


# --- Helpers ------------------------------------------------------------


## A line of `count` cells with a generator on cell 0 aimed at the last cell.
## Cell 0 is pre-mined; every other cell is locked with a huge cost so it never
## unlocks mid-test and changes the routing situation.
func _line_world(count: int, unlock_cost: int = 1000000) -> World:
	var graph := MapLoader.line_graph(count)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = unlock_cost
	var origin := graph.get_cell(0)
	origin.initial_block_id = BlockCatalog.GENERATOR
	origin.unlock()
	var world := World.new(graph)
	world.set_target(0, count - 1)
	return world


## A line of `count` cells with no generator at all, so a test can launch
## exactly one orb and read the ledger without other orbs in flight polluting
## the aggregate counters. Every cell but the first is locked, with a cost high
## enough that it never unlocks mid-test.
func _one_orb_world(count: int) -> World:
	var graph := MapLoader.line_graph(count)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 1000000
	var origin := graph.get_cell(0)
	origin.is_unlocked = true
	origin.unlock_progress = origin.unlock_cost
	return World.new(graph)


## Launch one orb and run until it has resolved, one way or another.
func _launch_one(world: World, from_id: int, to_id: int) -> void:
	world.emit_orb(from_id, to_id, Tiers.RED)
	var hops := world.graph.distance(from_id, to_id)
	_run(world, hops * World.TICKS_PER_HOP + 2)


## Bury a block in a cell and mine it immediately, bypassing the cost. Used to
## place pumps mid-line in tests.
func _place(world: World, cell_id: int, def_id: String) -> void:
	var cell := world.graph.get_cell(cell_id)
	cell.initial_block_id = def_id
	cell.block = null
	cell.unlock()


func _run(world: World, ticks: int) -> void:
	for i in ticks:
		world.tick()


## Enough ticks for one orb to be produced and cross the whole line.
func _ticks_for_one_delivery(hops: int) -> int:
	return BlockCatalog.get_def(BlockCatalog.GENERATOR).produce_interval \
		+ hops * World.TICKS_PER_HOP + 2


# --- Tests: decay -------------------------------------------------------


func test_decay_over_hops() -> void:
	# 5 hops. Orb starts at 10, loses 1 per hop, arrives with 5.
	var world := _one_orb_world(6)
	_launch_one(world, 0, 5)
	check_eq(world.delivered, 5, "one orb over 5 hops")
	check_eq(world.decayed, 5, "5 hops of decay")
	check_eq(world.evaporated_orbs, 0, "nothing should evaporate")
	check(world.ledger_balanced(), "ledger balanced")


func test_orb_evaporates() -> void:
	# 12 hops. The orb runs out of value at hop 10 and never lands.
	var world := _one_orb_world(13)
	_launch_one(world, 0, 12)
	check_eq(world.delivered, 0, "nothing reaches 12 hops unaided")
	check_eq(world.evaporated_orbs, 1, "the orb evaporated")
	check_eq(world.decayed, 10, "all 10 value went to decay")
	check(world.ledger_balanced(), "ledger balanced")


func test_pump_restores() -> void:
	# 12 hops with a pump at hop 5: 10 -> 5 on reaching the pump, restored to
	# 10, then 7 more hops to arrive with 3.
	var world := _one_orb_world(13)
	_place(world, 5, BlockCatalog.PUMP)
	_launch_one(world, 0, 12)
	check_eq(world.delivered, 3, "pumped orb over 12 hops")
	check_eq(world.restored, 5, "pump topped 5 back up")
	check_eq(world.decayed, 12, "12 hops of decay")
	check_eq(world.evaporated_orbs, 0, "the pump saved it")
	check(world.ledger_balanced(), "ledger balanced")


func test_pump_not_applied_on_arrival() -> void:
	# A pump sitting on the destination must not fire. Over 5 hops the orb
	# still arrives with 5, exactly as if the pump were not there — otherwise
	# parking a pump on a target would make every delivery land at full value.
	var world := _one_orb_world(6)
	_place(world, 5, BlockCatalog.PUMP)
	_launch_one(world, 0, 5)
	check_eq(world.restored, 0, "pump on the target never fired")
	check_eq(world.wasted, 5, "arrived with 5, not 10")
	check(world.ledger_balanced(), "ledger balanced")


func test_decay_kills_before_pump() -> void:
	# Pump at hop 10, where the orb's value hits exactly 0. Decay is applied
	# before the pump, so the orb dies rather than being rescued.
	var world := _one_orb_world(15)
	_place(world, 10, BlockCatalog.PUMP)
	_launch_one(world, 0, 14)
	check_eq(world.evaporated_orbs, 1, "orb died on entering the pump cell")
	check_eq(world.restored, 0, "pump never fired")
	check_eq(world.delivered, 0, "nothing arrived")
	check(world.ledger_balanced(), "ledger balanced")


func test_pump_chain_extends_reach() -> void:
	# Two pumps, 9 hops apart, carry an orb 20 hops — twice its unaided range.
	var world := _one_orb_world(21)
	_place(world, 9, BlockCatalog.PUMP)
	_place(world, 18, BlockCatalog.PUMP)
	_launch_one(world, 0, 20)
	check_eq(world.delivered, 8, "two pumps deliver 8 over 20 hops")
	check_eq(world.restored, 18, "both pumps fired at full effect")
	check_eq(world.evaporated_orbs, 0, "the chain held")
	check(world.ledger_balanced(), "ledger balanced")


# --- Tests: unlocking ---------------------------------------------------


func test_unlock_exact() -> void:
	# 2 hops, so each orb arrives with 8. A cost of 24 needs exactly 3 orbs and
	# leaves nothing wasted.
	var graph := MapLoader.line_graph(3)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	graph.get_cell(0).unlock()
	graph.get_cell(2).unlock_cost = 24
	var world := World.new(graph)
	world.set_target(0, 2)

	_run(world, _ticks_for_one_delivery(2) + 2 * 20)
	check(graph.get_cell(2).is_unlocked, "cell 2 unlocked")
	check_eq(graph.get_cell(2).unlock_progress, 24, "progress landed exactly")
	check_eq(world.delivered, 24, "all delivered value counted")
	check_eq(world.wasted, 0, "no overshoot")


func test_unlock_overshoot_is_wasted() -> void:
	# Cost 20, orbs arrive with 8: 8 + 8 + 8 overshoots by 4.
	var graph := MapLoader.line_graph(3)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	graph.get_cell(0).unlock()
	graph.get_cell(2).unlock_cost = 20
	var world := World.new(graph)
	world.set_target(0, 2)

	_run(world, _ticks_for_one_delivery(2) + 2 * 20)
	check(graph.get_cell(2).is_unlocked, "cell 2 unlocked")
	check_eq(world.delivered, 20, "only the needed value counted")
	check_eq(world.wasted, 4, "overshoot recorded as waste")
	check(world.ledger_balanced(), "ledger balanced")


# --- Tests: aiming ------------------------------------------------------


func test_no_target_idles() -> void:
	var graph := MapLoader.line_graph(5)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	graph.get_cell(0).unlock()
	var world := World.new(graph)

	_run(world, 500)
	check_eq(world.produced, 0, "unaimed generator produced nothing")
	check_eq(world.live_orb_count(), 0, "no orbs exist")


func test_unaimed_generator_banks_nothing() -> void:
	# Idling must not accumulate timer, or aiming would fire a free orb.
	var graph := MapLoader.line_graph(5)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	graph.get_cell(0).unlock()
	var world := World.new(graph)

	_run(world, 500)
	world.set_target(0, 4)
	var interval := BlockCatalog.get_def(BlockCatalog.GENERATOR).produce_interval
	_run(world, interval - 1)
	check_eq(world.produced, 0, "no orb before the full interval elapses")
	world.tick()
	check_eq(world.produced, World.ORB_MAX_VALUE, "exactly one orb on the interval tick")


func test_self_target_rejected() -> void:
	var world := _line_world(5)
	check(not world.set_target(0, 0), "cannot aim a cell at itself")
	check_eq(world.graph.get_cell(0).block.target_id, 4, "target unchanged")


func test_retarget_cancels_in_flight() -> void:
	var world := _line_world(10)
	_run(world, _ticks_for_one_delivery(9) - 30)  # orbs mid-flight
	var in_flight := world.in_flight_value()
	check(in_flight > 0, "there are orbs in flight to cancel")

	world.set_target(0, 5)
	check_eq(world.cancelled, in_flight, "all in-flight value was cancelled")
	check_eq(world.in_flight_value(), 0, "nothing survived the retarget")
	check(world.ledger_balanced(), "ledger balanced after cancel")


# --- Tests: mining and swapping -----------------------------------------


func test_unlock_installs_map_block() -> void:
	# Mining a cell yields whatever the map buried in it — the only way a block
	# ever comes into existence.
	var graph := MapLoader.line_graph(3)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	graph.get_cell(0).unlock()
	graph.get_cell(2).unlock_cost = 8
	graph.get_cell(2).initial_block_id = BlockCatalog.PUMP
	var world := World.new(graph)
	world.set_target(0, 2)

	check_eq(graph.get_cell(2).block, null, "buried block is not usable while locked")
	_run(world, _ticks_for_one_delivery(2))
	check(graph.get_cell(2).is_unlocked, "cell 2 was mined")
	check(graph.get_cell(2).has_block(), "mining yielded a block")
	check_eq(graph.get_cell(2).block.def.id, BlockCatalog.PUMP, "and it is the buried one")


func test_unlock_of_empty_cell_stays_empty() -> void:
	var graph := MapLoader.line_graph(3)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	graph.get_cell(0).unlock()
	graph.get_cell(2).unlock_cost = 8
	var world := World.new(graph)
	world.set_target(0, 2)

	_run(world, _ticks_for_one_delivery(2))
	check(graph.get_cell(2).is_unlocked, "cell 2 was mined")
	check_eq(graph.get_cell(2).block, null, "an empty cell mines to an empty cell")
	check(world.can_swap(0, 2), "but it can still receive a swap")


func test_swap_exchanges_blocks() -> void:
	var world := _line_world(6)
	_place(world, 3, BlockCatalog.PUMP)

	check(world.swap_blocks(0, 3), "swap accepted")
	check_eq(world.graph.get_cell(0).block.def.id, BlockCatalog.PUMP, "cell 0 now holds the pump")
	check_eq(world.graph.get_cell(3).block.def.id, BlockCatalog.GENERATOR, "cell 3 now holds the generator")


func test_swap_into_empty_is_a_move() -> void:
	var world := _line_world(6)
	var destination := world.graph.get_cell(3)
	destination.unlock()
	check_eq(destination.block, null, "destination starts empty")

	check(world.swap_blocks(0, 3), "swap accepted")
	check_eq(world.graph.get_cell(0).block, null, "source is now empty")
	check_eq(destination.block.def.id, BlockCatalog.GENERATOR, "block moved across")


func test_swap_rejects_locked_cells() -> void:
	var world := _line_world(6)
	check(not world.can_swap(0, 3), "cell 3 has not been mined")
	check(not world.swap_blocks(0, 3), "swap refused")
	check_eq(world.graph.get_cell(0).block.def.id, BlockCatalog.GENERATOR, "source untouched")
	check_eq(world.graph.get_cell(3).block, null, "destination untouched")

	# Two empty mined cells have nothing to trade.
	world.graph.get_cell(3).unlock()
	world.graph.get_cell(4).unlock()
	check(not world.can_swap(3, 4), "two empty cells is a no-op, not a move")
	check(not world.can_swap(0, 0), "a cell cannot swap with itself")


func test_swap_cancels_in_flight() -> void:
	# An orb belongs to the route that launched it, so moving either end of a
	# swap must not leave orphaned orbs flying along a stale path.
	var world := _line_world(10)
	_place(world, 4, BlockCatalog.PUMP)
	_run(world, _ticks_for_one_delivery(9) - 30)
	var in_flight := world.in_flight_value()
	check(in_flight > 0, "there are orbs in flight to cancel")

	check(world.swap_blocks(0, 4), "swap accepted")
	check_eq(world.cancelled, in_flight, "all in-flight value was cancelled")
	check_eq(world.in_flight_value(), 0, "nothing survived the swap")
	check(world.ledger_balanced(), "ledger balanced after swap")


func test_swap_clears_self_target() -> void:
	# A generator aimed at cell 3, swapped onto cell 3, would end up aimed at
	# itself — which set_target refuses on the way in, so the swap path has to
	# enforce it on the way out.
	var world := _line_world(6)
	world.set_target(0, 3)
	_place(world, 3, BlockCatalog.PUMP)

	check(world.swap_blocks(0, 3), "swap accepted")
	var moved: Block = world.graph.get_cell(3).block
	check_eq(moved.def.id, BlockCatalog.GENERATOR, "generator landed on cell 3")
	check_eq(moved.target_id, -1, "its self-target was dropped")
	check(not moved.has_target(), "so it idles rather than aiming at itself")


func test_swapped_generator_keeps_working() -> void:
	# After a move the generator produces from its new cell, along the new
	# shorter path — 2 hops instead of 5, so orbs arrive with 8 not 5.
	var world := _line_world(6)
	world.graph.get_cell(3).unlock()
	check(world.swap_blocks(0, 3), "generator moved to cell 3")
	check(world.set_target(3, 5), "re-aimed from its new home")

	var before := world.delivered
	_run(world, _ticks_for_one_delivery(2))
	check(world.delivered > before, "it is producing again")
	check_eq(world.delivered - before, 8, "over 2 hops, not the original 5")
	check(world.ledger_balanced(), "ledger balanced")


# --- Tests: camera ------------------------------------------------------
#
# These guard a regression: panning was moved off the left button to free it
# for selection, which left trackpad users unable to pan at all. They run
# headless because the camera reads positions off the event rather than from
# get_viewport().get_mouse_position() — the real mouse does not follow
# synthetic events, so the old viewport-querying version was untestable.


## Untyped on purpose: the static Camera2D type knows nothing about the
## script's own `panned` and `screen_to_world`, so access has to stay dynamic.
func _camera():
	var camera = load("res://scenes/camera_2d.gd").new()
	root.add_child(camera)
	camera.position = Vector2.ZERO
	camera.zoom = Vector2.ONE
	return camera


func _press(button: MouseButton, at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.pressed = pressed
	return event


func _motion(at: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	return event


func test_camera_left_drag_pans() -> void:
	var camera = _camera()
	camera._unhandled_input(_press(MOUSE_BUTTON_LEFT, Vector2(400, 300), true))
	camera._unhandled_input(_motion(Vector2(340, 260)))
	camera._unhandled_input(_press(MOUSE_BUTTON_LEFT, Vector2(340, 260), false))

	check(camera.panned, "the drag registered as a pan")
	check_eq(camera.position, Vector2(60, 40), "camera followed the cursor")
	camera.queue_free()


func test_camera_click_without_drag_does_not_pan() -> void:
	# A click that wobbles a pixel or two must still select, not pan.
	var camera = _camera()
	camera._unhandled_input(_press(MOUSE_BUTTON_LEFT, Vector2(400, 300), true))
	camera._unhandled_input(_motion(Vector2(402, 301)))
	camera._unhandled_input(_press(MOUSE_BUTTON_LEFT, Vector2(402, 301), false))

	check(not camera.panned, "under the threshold, so Main will treat it as a click")
	check_eq(camera.position, Vector2.ZERO, "camera did not move")
	camera.queue_free()


func test_camera_middle_drag_does_nothing() -> void:
	var camera = _camera()
	camera._unhandled_input(_press(MOUSE_BUTTON_MIDDLE, Vector2(400, 300), true))
	camera._unhandled_input(_motion(Vector2(200, 100)))

	check(not camera.panned, "middle button is not a pan gesture")
	check_eq(camera.position, Vector2.ZERO, "camera did not move")
	camera.queue_free()


func test_camera_wheel_zooms_toward_cursor() -> void:
	# The defining property: the world point under the cursor stays under the
	# cursor across a zoom step.
	var camera = _camera()
	camera.position = Vector2(500, 250)
	var cursor := Vector2(1100, 700)
	var before: Vector2 = camera.screen_to_world(cursor)

	camera._unhandled_input(_press(MOUSE_BUTTON_WHEEL_UP, cursor, true))
	var after: Vector2 = camera.screen_to_world(cursor)
	check(camera.zoom.x != 1.0, "zoom actually changed")
	check(
		after.distance_to(before) < 0.01,
		"world point under the cursor held still (was %s, now %s)" % [before, after]
	)
	camera.queue_free()


# --- Tests: pathing -----------------------------------------------------


func test_path_determinism() -> void:
	var a := MapLoader.load_from_file("res://data/map_01.json")
	var b := MapLoader.load_from_file("res://data/map_01.json")
	check(a != null and b != null, "map loaded")
	if a == null or b == null:
		return
	for from_id in a.cell_ids:
		for to_id in a.cell_ids:
			if a.find_path(from_id, to_id) != b.find_path(from_id, to_id):
				_fail("path %d->%d differs between loads" % [from_id, to_id])
				return


func test_path_tie_break_is_lowest_id() -> void:
	# A diamond: 0 -> {1, 2} -> 3. Both routes are 2 hops; the lower-id
	# neighbour must always win.
	var graph := Graph.new()
	for i in 4:
		var cell := GraphCell.new()
		cell.id = i
		graph.add_cell(cell)
	graph.get_cell(0).neighbor_ids = PackedInt32Array([2, 1])  # deliberately unsorted
	graph.get_cell(1).neighbor_ids = PackedInt32Array([0, 3])
	graph.get_cell(2).neighbor_ids = PackedInt32Array([0, 3])
	graph.get_cell(3).neighbor_ids = PackedInt32Array([1, 2])
	graph.finalize()

	check_eq(graph.find_path(0, 3), PackedInt32Array([0, 1, 3]), "route through lowest id")
	check_eq(graph.distance(0, 3), 2, "two hops")


func test_locked_cells_are_traversable() -> void:
	# Every intermediate cell is locked; the orb must still cross them. Locked
	# cells cost nothing extra — they simply offer no support.
	var world := _one_orb_world(6)
	for id in [1, 2, 3, 4]:
		check(not world.graph.get_cell(id).is_unlocked, "cell %d is locked" % id)
	_launch_one(world, 0, 5)
	check_eq(world.delivered, 5, "orb crossed 4 locked cells")


func test_projected_arrival_matches_reality() -> void:
	# The UI preview reimplements the decay walk, so it must agree with the
	# simulation exactly — including past the death range, where it returns 0.
	for hops in [1, 3, 5, 9, 10, 12, 20]:
		for pumps in [[], [5], [9, 18]]:
			var world := _one_orb_world(hops + 1)
			for p in pumps:
				if p < hops:
					_place(world, p, BlockCatalog.PUMP)
			var projected := world.projected_arrival(0, hops)
			_launch_one(world, 0, hops)
			if projected != world.delivered:
				_fail("%d hops, pumps %s — projected %d, delivered %d"
					% [hops, pumps, projected, world.delivered])
				return
			if not world.ledger_balanced():
				_fail("%d hops, pumps %s — ledger broke" % [hops, pumps])
				return


# --- Tests: invariants --------------------------------------------------


func test_tick_order_independent() -> void:
	# Same map, same commands, but the simulation iterates cells in a shuffled
	# order. Every observable must come out identical.
	var ordered := _busy_world()
	var shuffled := _busy_world()

	var ids: Array[int] = []
	for id in shuffled.graph.cell_ids:
		ids.append(id)
	ids.reverse()
	shuffled.graph.cell_ids = PackedInt32Array(ids)

	_run(ordered, 1500)
	_run(shuffled, 1500)

	check_eq(shuffled.produced, ordered.produced, "produced")
	check_eq(shuffled.delivered, ordered.delivered, "delivered")
	check_eq(shuffled.wasted, ordered.wasted, "wasted")
	check_eq(shuffled.decayed, ordered.decayed, "decayed")
	check_eq(shuffled.restored, ordered.restored, "restored")
	check_eq(shuffled.evaporated_orbs, ordered.evaporated_orbs, "evaporated")
	check_eq(shuffled.unlocked_count(), ordered.unlocked_count(), "cells unlocked")
	for id in ordered.graph.cell_ids:
		check_eq(
			shuffled.graph.get_cell(id).unlock_progress,
			ordered.graph.get_cell(id).unlock_progress,
			"cell %d progress" % id
		)


func test_value_conservation() -> void:
	# The strong guarantee: over a long run with pumps firing, cells unlocking,
	# orbs evaporating and routes being changed, no value appears or vanishes
	# unaccounted for.
	var world := _busy_world()
	for i in 2000:
		world.tick()
		if i == 700:
			world.set_target(0, 12)
		if i == 1200:
			world.swap_blocks(0, 19)
		if not world.ledger_balanced():
			_fail("ledger broke at tick %d: produced %d + restored %d != delivered %d + wasted %d + decayed %d + cancelled %d + in flight %d"
				% [world.tick_count, world.produced, world.restored, world.delivered,
					world.wasted, world.decayed, world.cancelled, world.in_flight_value()])
			return
	check(world.produced > 0, "the run actually produced something")
	check(world.restored > 0, "pumps actually fired")
	check(world.cancelled > 0, "route changes actually cancelled orbs")


## A world with several generators, pumps, and reachable targets — enough
## activity for the invariant tests to be meaningful.
func _busy_world() -> World:
	var graph := MapLoader.line_graph(25)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 30 + id
	for id in [0, 6, 14]:
		graph.get_cell(id).initial_block_id = BlockCatalog.GENERATOR
		graph.get_cell(id).unlock()
	graph.get_cell(19).initial_block_id = BlockCatalog.PUMP
	graph.get_cell(19).unlock()

	var world := World.new(graph)
	world.set_target(0, 5)
	world.set_target(6, 11)
	world.set_target(14, 22)
	return world


# --- Tests: shipped content ---------------------------------------------


func test_shipped_map_is_valid() -> void:
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	check(graph != null, "map_01.json loaded")
	if graph == null:
		return
	check(graph.size() >= 20, "map has a meaningful number of cells")

	var sources: Array[int] = []
	for id in graph.cell_ids:
		var cell := graph.get_cell(id)
		check_eq(cell.neighbor_ids.is_empty(), false, "cell %d has neighbours" % id)
		if cell.is_unlocked and cell.has_block():
			sources.append(id)
		if not cell.initial_block_id.is_empty():
			check(
				BlockCatalog.has_def(cell.initial_block_id),
				"cell %d buries a known block" % id
			)
		# Edges must be symmetric after finalize.
		for n in cell.neighbor_ids:
			check(
				graph.get_cell(n).neighbor_ids.has(id),
				"edge %d-%d is symmetric" % [id, n]
			)
	check(not sources.is_empty(), "map ships at least one working generator")

	# Every cell must be reachable at all...
	var world := World.new(graph)
	var out_of_range := 0
	for id in graph.cell_ids:
		if id == sources[0]:
			continue
		check(graph.distance(sources[0], id) >= 0, "cell %d is reachable" % id)
		var best := 0
		for s in sources:
			best = maxi(best, world.projected_arrival(s, id))
		if best == 0:
			out_of_range += 1
	# ...but some must be out of unaided range, or pumps have no purpose.
	check(out_of_range > 0, "map has cells that need a pump chain to reach")


func test_shipped_map_is_a_web() -> void:
	# Guards the shape, not just the wiring: a short-diameter blob would make
	# decay irrelevant, and a degree-1 cell is a dead end rather than a web.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return

	var start := -1
	var generators := 0
	var pumps := 0
	var reachable_pumps := 0
	var world := World.new(graph)

	for id in graph.cell_ids:
		var cell := graph.get_cell(id)
		check(cell.neighbor_ids.size() >= 2, "cell %d has more than one route" % id)
		match cell.initial_block_id:
			BlockCatalog.GENERATOR:
				generators += 1
				if cell.is_unlocked:
					start = id
			BlockCatalog.PUMP:
				pumps += 1

	check(start != -1, "a starting generator is already mined")
	check(generators >= 3, "several generators exist to rearrange")
	check(pumps >= 4, "several pumps exist to rearrange")

	var diameter := 0
	for a in graph.cell_ids:
		for b in graph.cell_ids:
			diameter = maxi(diameter, graph.distance(a, b))
	check(diameter >= 12, "diameter %d is long enough that decay bites" % diameter)

	# At least one pump must sit inside the unaided frontier, or the first one
	# can never be acquired and the map is unwinnable from the opening move.
	for id in graph.cell_ids:
		if graph.get_cell(id).initial_block_id == BlockCatalog.PUMP \
				and world.projected_arrival(start, id) > 0:
			reachable_pumps += 1
	check(reachable_pumps > 0, "a first pump is minable without already having one")
