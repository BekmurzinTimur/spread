extends SceneTree

## Headless test suite for the simulation. No external dependency.
##
##   ./run_tests.sh
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Exits 1 on any failure.

## A test slower than this reports its duration beside the "ok", and the slowest
## is named at the end. Not a failure threshold — the suite has a few tests that
## legitimately walk all 950 cells of the shipped map — but a tripwire, because a
## nested loop over `cell_ids` costs nothing on a line graph and minutes on the
## real board, and it stays green the whole time.
const SLOW_TEST_MS := 250

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
		"test_pump_adds_a_percentage_of_launch_value",
		"test_pumps_are_additive_not_compounding",
		"test_pump_restore_rounds_up",
		"test_surge_makes_every_pump_stronger",
		"test_an_orb_in_flight_keeps_its_launch_value",
		"test_pump_not_applied_on_arrival",
		"test_decay_kills_before_pump",
		"test_pump_chain_extends_reach",
		"test_pump_spacing_decides_survival_not_value",
		"test_pump_stacks_without_ceiling",
		"test_sphere_speeds_generators_in_radius",
		"test_sphere_boosts_pump_restore",
		"test_sphere_bonus_is_flat_within_radius",
		"test_sphere_bonuses_stack",
		"test_sphere_interval_never_reaches_zero",
		"test_sphere_field_follows_a_swap",
		"test_sphere_field_appears_on_mining",
		"test_sphere_does_not_pulse",
		"test_challenge_surge_raises_launch_value",
		"test_challenge_current_boosts_pumps_only",
		"test_challenge_lens_widens_sphere_field",
		"test_challenge_grants_nothing_while_buried",
		"test_challenge_cannot_be_swapped",
		"test_challenge_ignores_a_sphere",
		"test_challenge_does_not_pulse",
		"test_challenge_is_known_before_it_is_mined",
		"test_global_buff_does_not_mark_pumps_boosted",
		"test_challenge_triangle_geometry",

		"test_upgrader_banks_red_and_emits_orange",
		"test_a_generator_of_every_colour_emits_its_own_tier",
		"test_a_generator_cannot_open_another_colour",
		"test_the_ladder_converts_one_step_at_a_time",
		"test_idle_cycling_walks_one_colour_at_a_time",
		"test_upgrader_banks_charge_while_idle",
		"test_upgrader_bank_caps_at_one_orb",
		"test_upgrader_overflow_is_wasted_not_recorded",
		"test_upgrader_ignores_passing_orbs",
		"test_upgrader_rejects_wrong_tier_input",
		"test_upgrader_cannot_be_swapped",
		"test_upgrader_marks_active_only_when_it_emits",
		"test_sphere_discounts_an_upgrader",
		"test_sphere_upgrade_cost_never_reaches_zero",
		"test_orange_cell_ignores_red_orbs",
		"test_cannot_aim_red_at_an_orange_cell",
		"test_can_aim_a_generator_at_an_upgrader",
		"test_cannot_aim_at_a_mined_cell_without_an_intake",
		"test_locked_cell_tint_follows_its_tier",
		"test_tier_tables_are_consistent",
		"test_tierless_blocks_are_neutral",
		"test_needs_target_and_movable_are_disjoint",

		"test_unlock_exact",
		"test_unlock_overshoot_is_wasted",
		"test_delivery_events_report_what_counted",
		"test_delivery_events_drain_empties",
		"test_delivery_events_are_bounded",
		"test_no_event_for_waste_into_mined_cell",
		"test_generator_marks_active_only_when_it_emits",
		"test_generator_with_no_route_never_marks",
		"test_pump_marks_active_when_an_orb_passes",
		"test_pump_at_a_route_end_never_marks",
		"test_activity_survives_a_swap",
		"test_no_target_idles",
		"test_unaimed_generator_banks_nothing",
		"test_self_target_rejected",
		"test_retarget_leaves_in_flight_orbs_alone",
		"test_an_orb_outlives_the_route_that_launched_it",
		"test_unlock_installs_map_block",
		"test_unlock_of_empty_cell_stays_empty",
		"test_unlock_unaims_generators",
		"test_unlock_leaves_orbs_flying_at_that_target",
		"test_an_orb_still_feeds_an_upgrader_mined_under_it",
		"test_cannot_aim_at_mined_cell",
		"test_idle_cells_of_lists_unaimed",
		"test_next_idle_after_wraps",
		"test_next_idle_after_empty",
		"test_swap_exchanges_blocks",
		"test_swap_into_empty_is_a_move",
		"test_swap_rejects_locked_cells",
		"test_generator_cannot_be_swapped",
		"test_swap_leaves_generator_orbs_alone",
		"test_swapped_pump_relays_from_new_cell",
		"test_camera_left_drag_pans",
		"test_camera_click_without_drag_does_not_pan",
		"test_camera_middle_drag_does_nothing",
		"test_camera_wheel_zooms_toward_cursor",
		"test_camera_visible_world_rect_tracks_pan_and_zoom",
		"test_orb_weave_vanishes_at_cell_centres",
		"test_orb_weave_alternates_side_each_hop",
		"test_orb_weave_gives_each_source_its_own_lane",
		"test_splash_shards_fan_evenly",
		"test_splash_expands_and_fades",
		"test_splash_drops_expired",
		"test_splash_respects_max_live",
		"test_splash_strength_is_clamped",
		"test_path_determinism",
		"test_path_tie_break_is_lowest_id",

		"test_waypoint_route_bends_through_the_via",
		"test_waypoint_legs_join_without_repeating_the_seam",
		"test_waypoint_route_is_empty_when_a_leg_is_unroutable",
		"test_waypoints_are_normalized_and_capped",
		"test_waypoint_route_costs_the_extra_hops",
		"test_waypoint_route_reaches_a_pump_it_would_otherwise_miss",
		"test_a_route_that_crosses_its_own_destination_is_refused",
		"test_a_route_that_crosses_itself_is_refused",
		"test_can_route_through_refuses_a_crossing",
		"test_a_chain_aims_as_it_is_drawn",
		"test_cells_with_def_in_rect_finds_the_same_type",
		"test_cells_with_def_in_rect_distinguishes_tiers",
		"test_cells_with_def_in_rect_is_ascending",
		"test_batch_aim_applies_to_every_source",
		"test_batch_aim_leaves_a_failed_source_on_its_old_target",
		"test_batch_aim_counts_a_source_already_on_that_route",
		"test_batch_unaim_clears_every_source",
		"test_count_routable_through_is_the_group_gate",
		"test_waypoint_route_reresolves_as_fog_lifts",
		"test_cannot_aim_through_an_undiscovered_waypoint",
		"test_same_target_new_waypoints_keeps_in_flight_orbs",

		"test_locked_cells_are_traversable",
		"test_projected_arrival_matches_reality",
		"test_fog_hides_undiscovered",
		"test_cannot_aim_at_undiscovered",
		"test_mining_expands_discovery",
		"test_routes_stay_inside_discovered",
		"test_shipped_map_routes_never_leave_the_light",
		"test_path_cache_invalidated_on_unlock",
		"test_shipped_map_opens_under_fog",
		"test_upkeep_banks_red_and_lights_the_buff",
		"test_upkeep_grants_nothing_while_dry",
		"test_upkeep_grants_nothing_while_buried",
		"test_upkeep_drain_empties_the_bank_and_goes_dark",
		"test_upkeep_hysteresis_does_not_strobe",
		"test_upkeep_books_intake_as_burned",
		"test_upkeep_ignores_passing_orbs",
		"test_upkeep_rejects_wrong_tier_input",
		"test_can_aim_a_generator_at_an_upkeep",
		"test_upkeep_can_be_swapped_and_keeps_its_fuel",
		"test_upkeep_buff_does_not_mark_generators_boosted",
		"test_sphere_still_pays_off_under_upkeep",

		"test_tick_order_independent",
		"test_value_conservation",
		"test_shipped_map_is_valid",
		"test_shipped_map_is_a_web",
		"test_shipped_map_challenges_are_unique_per_band",
		"test_shipped_map_challenges_cost_more_than_their_neighbours",
		"test_shipped_map_tier_ladder",
		"test_shipped_map_sources_are_payable_in_an_earlier_colour",
		"test_shipped_map_upkeeps_are_shallow_and_movable",
	]

	print("")
	var slowest := 0
	var slowest_name := ""
	for name in tests:
		_current = name
		_current_failed = false
		var started := Time.get_ticks_msec()
		call(name)
		var took := Time.get_ticks_msec() - started
		if took > slowest:
			slowest = took
			slowest_name = name
		if _current_failed:
			_failed += 1
		else:
			_passed += 1
			# Timings only for the ones worth noticing. The shipped-map tests walk
			# every cell on a 950-cell board, so one careless nested loop turns a
			# ten-second suite into a coffee break — and it does so silently,
			# because the test still passes. SLOW_TEST_MS is the tripwire.
			if took >= SLOW_TEST_MS:
				print("  %s ok  (%d ms)" % [_pad(name), took])
			else:
				print("  %s %s" % [_pad(name), "ok"])

	print("")
	if slowest >= SLOW_TEST_MS:
		print("slowest: %s (%d ms)" % [slowest_name, slowest])
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


## The one cell the shipped map hands over already mined, found rather than
## assumed: it sits in the middle of the board, so its id moves whenever the
## lattice is regenerated and nothing should be pinned to a literal.
func _shipped_start(graph: Graph) -> int:
	for id in graph.cell_ids:
		if graph.get_cell(id).is_unlocked:
			return id
	return -1


## One unweighted BFS over the whole map, returning `[cell, hops]` for the cell
## furthest from `from_id`. Ignores discovery, like everything else asking what
## the *map* is rather than what the player has uncovered.
##
## Walks `neighbor_ids` directly instead of going through `Graph`, because the
## only route query that ignores discovery is `find_path_unrestricted`, and that
## one is uncached — a caller wanting every distance from one source would pay a
## fresh BFS per destination. This pays one for all of them, which is what makes
## a double-sweep diameter affordable on a nine-hundred-cell board.
func _farthest_from(graph: Graph, from_id: int) -> Array:
	var seen := {from_id: 0}
	var queue: Array[int] = [from_id]
	var head := 0
	var best_id := from_id
	var best_hops := 0
	while head < queue.size():
		var id: int = queue[head]
		head += 1
		var hops: int = seen[id]
		if hops > best_hops:
			best_hops = hops
			best_id = id
		for n in graph.get_cell(id).neighbor_ids:
			if not seen.has(n):
				seen[n] = hops + 1
				queue.append(n)
	return [best_id, best_hops]


## Mine a scaffold of alternating cells so the whole line is discovered.
##
## Routing only crosses discovered ground, so a line with just cell 0 mined is
## routable exactly one hop — which would make every decay test measure nothing.
## Mining every second cell opens the line while leaving the ones between them
## locked, so the traversal tests still cross locked ground for real.
##
## The final cell is always left locked, because that is where deliveries land
## and value delivered into an already-mined cell is merely wasted. When the
## final cell has an even id its predecessor is mined instead, so it still ends
## up next to something mined and therefore discovered.
##
## Mined cells here are empty — the line buries nothing — so they neither pump
## nor produce, and every decay figure is exactly what it was before fog.
func _discover_line(graph: Graph) -> void:
	var last: int = graph.cell_ids[graph.cell_ids.size() - 1]
	for id in graph.cell_ids:
		if id != last and (id % 2 == 0 or id == last - 1):
			graph.unlock_cell(id)


## A line of `count` cells with a generator on cell 0 aimed at the last cell.
## Every cell is locked with a huge cost so it never unlocks mid-test and changes
## the routing situation, save for the discovery scaffold above.
func _line_world(count: int, unlock_cost: int = 1000000) -> World:
	var graph := MapLoader.line_graph(count)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = unlock_cost
	# Set before mining: unlocking is what installs the buried block.
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	var world := World.new(graph)
	world.set_target(0, count - 1)
	return world


## A line of `count` cells with no generator at all, so a test can launch
## exactly one orb and read the ledger without other orbs in flight polluting
## the aggregate counters. Locked at a cost high enough that nothing unlocks
## mid-test, save for the discovery scaffold above.
func _one_orb_world(count: int) -> World:
	var graph := MapLoader.line_graph(count)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 1000000
	_discover_line(graph)
	return World.new(graph)


## What one pump restores to an orb launched at the base value, derived the way
## the simulation derives it rather than pinned at a literal — so retuning the
## percentage retunes every test that spends it. The arithmetic each test asserts
## is spelled out in its comment, which is the part that must not silently drift.
func _pump_restore() -> int:
	return StatBonus.percent_of(World.ORB_START_VALUE,
		BlockCatalog.get_def(BlockCatalog.PUMP).restore_percent)


## Launch one orb and run until it has resolved, one way or another. The tier
## defaults to red because most tests are about travel rather than colour, and
## travel is the same for all seven.
func _launch_one(world: World, from_id: int, to_id: int,
		tier: int = Tiers.RED) -> void:
	world.emit_orb(from_id, to_id, tier)
	var hops := world.graph.distance(from_id, to_id)
	_run(world, hops * World.TICKS_PER_HOP + 2)


## Bury a block in a cell and mine it immediately, bypassing the cost. Used to
## place pumps mid-line in tests. Works on a cell the scaffold already mined:
## clearing `block` first lets the idempotent unlock install the new one.
func _place(world: World, cell_id: int, def_id: String) -> void:
	var cell := world.graph.get_cell(cell_id)
	cell.initial_block_id = def_id
	cell.block = null
	world.graph.unlock_cell(cell_id)


func _run(world: World, ticks: int) -> void:
	for i in ticks:
		world.tick()


## Enough ticks for one orb to be produced and cross the whole line.
func _ticks_for_one_delivery(hops: int) -> int:
	return BlockCatalog.get_def(BlockCatalog.GENERATOR).produce_interval \
		+ hops * World.TICKS_PER_HOP + 2


# --- Tests: decay -------------------------------------------------------


func test_decay_over_hops() -> void:
	# 5 hops. Orb starts at 10 and loses 1 per cell it crosses — four of them,
	# since the destination is delivered into rather than crossed — so it arrives
	# with 6. A neighbour one hop away receives the full 10.
	var world := _one_orb_world(6)
	_launch_one(world, 0, 5)
	check_eq(world.delivered, 6, "one orb over 5 hops")
	check_eq(world.decayed, 4, "4 crossed cells, not 5")

	var next_door := _one_orb_world(2)
	_launch_one(next_door, 0, 1)
	check_eq(next_door.delivered, World.ORB_START_VALUE, "a neighbour gets full value")
	check_eq(next_door.decayed, 0, "nothing was crossed")
	check(next_door.ledger_balanced(), "ledger balanced")
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


func test_pump_adds_a_percentage_of_launch_value() -> void:
	# A pump adds a percentage of what the orb launched with, not a top-up to
	# where it started. 12 hops with a pump at hop 5: 10 - 5 = 5 on reaching the
	# pump, +2 = 7, then six more crossed cells to arrive with 1.
	var restore := _pump_restore()
	check_eq(restore, 2, "20% of a 10-value orb, so the arithmetic below reads")

	var world := _one_orb_world(13)
	_place(world, 5, BlockCatalog.PUMP)
	_launch_one(world, 0, 12)
	check_eq(world.delivered, 1, "pumped orb over 12 hops")
	check_eq(world.restored, restore, "the pump added its percentage, not 5")
	check_eq(world.decayed, 11, "11 crossed cells")
	check_eq(world.evaporated_orbs, 0, "the pump saved it")
	check(world.ledger_balanced(), "ledger balanced")


func test_pumps_are_additive_not_compounding() -> void:
	# The property that distinguishes a percentage of the *launch* value from a
	# percentage of the current one. Both pumps see a different value as the orb
	# passes — 9 at the first, 10 at the second — and both restore the same
	# amount, so a route's arrival is a sum and cannot depend on pump order.
	var restore := _pump_restore()

	var world := _one_orb_world(6)
	_place(world, 1, BlockCatalog.PUMP)
	_place(world, 2, BlockCatalog.PUMP)
	_launch_one(world, 0, 5)
	check_eq(world.restored, restore * 2, "two pumps restored twice one pump")

	# Compounding would be 10 -> 9 -> 10.8 -> 11.8 -> 14.16, and would land
	# something other than this whatever the rounding.
	check_eq(world.delivered, World.ORB_START_VALUE - 4 + restore * 2,
		"arrival is launch - crossed cells + the sum of the pumps")
	check(world.ledger_balanced(), "ledger balanced")


func test_pump_restore_rounds_up() -> void:
	# Rounding is in the player's favour, which only shows on a percentage that
	# does not divide evenly. A sphere takes the pump to 30%, and 30% of a plain
	# 10-value orb is 3 exactly — so the orb has to be a Surge orb (15) for the
	# fraction to appear: 30% of 15 is 4.5, and the player gets 5.
	var world := _one_orb_world(9)
	_place(world, 1, BlockCatalog.PUMP)
	_place(world, 2, BlockCatalog.SPHERE)
	_place(world, 6, BlockCatalog.CHALLENGE_SURGE)

	var pump := world.graph.get_cell(1)
	check_eq(world.effective_restore_percent(pump), 30, "20% base, +10 from the sphere")
	check_eq(world.effective_orb_value(), 15, "and the Surge is raising the launch value")
	check_eq(world.restore_for(pump, world.effective_orb_value()), 5,
		"4.5 rounds up, not down")

	_launch_one(world, 0, 5)
	check_eq(world.restored, 5, "and that is what the orb actually received")
	check(world.ledger_balanced(), "ledger balanced")


func test_surge_makes_every_pump_stronger() -> void:
	# The point of a percentage restore. A Surge raises what an orb launches with,
	# and because a pump gives back a share of that, mining one buys reach twice:
	# once at the generator, and again at every pump on the route. No sphere is
	# anywhere near, so this is the launch value doing it and nothing else.
	var plain := _one_orb_world(9)
	_place(plain, 1, BlockCatalog.PUMP)
	_launch_one(plain, 0, 5)

	var surged := _one_orb_world(9)
	_place(surged, 1, BlockCatalog.PUMP)
	_place(surged, 6, BlockCatalog.CHALLENGE_SURGE)
	_launch_one(surged, 0, 5)

	check_eq(plain.restored, 2, "20% of 10")
	check_eq(surged.restored, 3, "20% of 15")
	check_eq(surged.effective_restore_percent(surged.graph.get_cell(1)),
		plain.effective_restore_percent(plain.graph.get_cell(1)),
		"the pump's percentage is untouched — only what it is a percentage of moved")
	check(surged.ledger_balanced(), "ledger balanced")


func test_an_orb_in_flight_keeps_its_launch_value() -> void:
	# The launch value is stamped on the orb at emission, so a Surge mined while
	# an orb is on its way does not retroactively re-price it. Asking the world
	# for `effective_orb_value()` at each pump instead would, and would make an
	# orb's arrival depend on when the player happened to finish a cell.
	var world := _one_orb_world(9)
	_place(world, 4, BlockCatalog.PUMP)
	world.emit_orb(0, 8, Tiers.RED)
	_run(world, World.TICKS_PER_HOP + 2)

	_place(world, 6, BlockCatalog.CHALLENGE_SURGE)
	check_eq(world.effective_orb_value(), 15, "the Surge is live for anything emitted now")

	_run(world, 8 * World.TICKS_PER_HOP + 2)
	check_eq(world.restored, 2, "but the orb already in flight was pumped on its own 10")
	check(world.ledger_balanced(), "ledger balanced")


func test_pump_not_applied_on_arrival() -> void:
	# A pump sitting on the destination must not fire. Over 5 hops the orb
	# still arrives with 6, exactly as if the pump were not there — otherwise
	# parking a pump on a target would make every delivery land at full value.
	var world := _one_orb_world(6)
	_place(world, 5, BlockCatalog.PUMP)
	_launch_one(world, 0, 5)
	check_eq(world.restored, 0, "pump on the target never fired")
	check_eq(world.wasted, 6, "arrived with 6, not 13")
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
	# A pump cell nets +1 and a plain cell -1, so a chain only holds while its
	# pumps sit two hops apart or closer. Pumps at hops 3 and 6 still carry the
	# orb 12 hops — past its unaided range of 10 — they just bleed on the way.
	var restore := _pump_restore()
	var world := _one_orb_world(13)
	_place(world, 3, BlockCatalog.PUMP)
	_place(world, 6, BlockCatalog.PUMP)
	_launch_one(world, 0, 12)
	check_eq(world.delivered, 3, "two pumps deliver 3 over 12 hops")
	check_eq(world.restored, restore * 2, "both pumps fired")
	check_eq(world.evaporated_orbs, 0, "the chain held")
	check(world.ledger_balanced(), "ledger balanced")


func test_pump_spacing_decides_survival_not_value() -> void:
	# What spacing controls is whether the orb lives, not what it arrives with:
	# arrival is 10 - (hops - 1) + restore * pumps whatever the gaps look like. A
	# pump cell nets +1 and a plain cell -1, so a chain holds at two hops apart
	# and bleeds a point per segment at three — over a long enough line, out.
	#
	# Same 29-hop route both ways. Two apart: fourteen pumps, arrives with 10.
	var tight := _one_orb_world(30)
	for hop in [2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28]:
		_place(tight, hop, BlockCatalog.PUMP)
	_launch_one(tight, 0, 29)
	check_eq(tight.delivered, 10, "a two-hop chain holds over 29 hops")
	check_eq(tight.evaporated_orbs, 0, "and nothing evaporated")
	check(tight.ledger_balanced(), "ledger balanced")

	# Three apart: nine pumps, and the orb bleeds out on the last stretch.
	var loose := _one_orb_world(30)
	for hop in [3, 6, 9, 12, 15, 18, 21, 24, 27]:
		_place(loose, hop, BlockCatalog.PUMP)
	_launch_one(loose, 0, 29)
	check_eq(loose.delivered, 0, "a three-hop chain does not reach")
	check_eq(loose.evaporated_orbs, 1, "the orb bled out before the last pump")
	check(loose.ledger_balanced(), "ledger balanced")


func test_pump_stacks_without_ceiling() -> void:
	# Pumps stack with no ceiling, so a well-supported orb arrives worth more
	# than it launched with. Pumps at hops 1 and 2: 9 -> 11, then 10 -> 12, then
	# one crossed cell and a free arrival, for 11.
	var restore := _pump_restore()
	var world := _one_orb_world(5)
	_place(world, 1, BlockCatalog.PUMP)
	_place(world, 2, BlockCatalog.PUMP)
	_launch_one(world, 0, 4)
	check_eq(world.delivered, 11, "arrived worth more than a fresh orb")
	check(world.delivered > World.ORB_START_VALUE, "the launch value is not a cap")
	check_eq(world.restored, restore * 2, "both pumps added their full amount")
	check(world.ledger_balanced(), "ledger balanced")


# --- Tests: spheres -----------------------------------------------------


## Base numbers, read from the catalog rather than pinned, so tuning the sphere
## retunes the tests with it. The arithmetic each test asserts is spelled out in
## its comment, which is the part that must not silently change.
func _sphere_def() -> BlockDef:
	return BlockCatalog.get_def(BlockCatalog.SPHERE)


func test_sphere_speeds_generators_in_radius() -> void:
	# The generator on cell 0 fires every `interval` ticks; a sphere one hop away
	# gives it `field_rate_percent` increased rate, which divides that interval.
	# Counted in orbs produced over a fixed budget rather than in ticks, because
	# emission count is what the player actually feels.
	var base: int = BlockCatalog.get_def(BlockCatalog.GENERATOR).produce_interval
	var boosted: int = StatBonus.apply_rate(base, _sphere_def().field_rate_percent)

	var plain := _line_world(6)
	_run(plain, base * 4)
	var plain_orbs: int = plain.produced / World.ORB_START_VALUE

	var sphered := _line_world(6)
	_place(sphered, 1, BlockCatalog.SPHERE)
	_run(sphered, base * 4)
	var sphered_orbs: int = sphered.produced / World.ORB_START_VALUE

	check_eq(plain_orbs, base * 4 / base, "the unaided generator fired on its base interval")
	check_eq(sphered_orbs, base * 4 / boosted, "the sphere shortened the interval")
	check(sphered_orbs > plain_orbs, "a sphere in range means more orbs")


func test_sphere_boosts_pump_restore() -> void:
	# One pump at hop 1 on a 4-hop line. Unaided it restores its base percentage
	# of the launch value; with a sphere adjacent it restores base + the field's
	# percentage points, and the whole difference lands in the delivered value.
	var launch := World.ORB_START_VALUE
	var pump_base: int = StatBonus.percent_of(launch,
		BlockCatalog.get_def(BlockCatalog.PUMP).restore_percent)
	var bonus: int = StatBonus.percent_of(launch,
		BlockCatalog.get_def(BlockCatalog.PUMP).restore_percent
			+ _sphere_def().field_restore_percent) - pump_base
	check(bonus > 0, "a sphere is meant to be worth something to a pump")

	var plain := _one_orb_world(5)
	_place(plain, 1, BlockCatalog.PUMP)
	_launch_one(plain, 0, 4)

	var sphered := _one_orb_world(5)
	_place(sphered, 1, BlockCatalog.PUMP)
	_place(sphered, 2, BlockCatalog.SPHERE)
	_launch_one(sphered, 0, 4)

	check_eq(plain.restored, pump_base, "the unaided pump restored its base amount")
	check_eq(sphered.restored, pump_base + bonus, "the sphere strengthened the pump")
	check_eq(sphered.delivered, plain.delivered + bonus, "and the orb arrived with it")
	check(sphered.ledger_balanced(), "ledger balanced")


func test_sphere_bonus_is_flat_within_radius() -> void:
	# Flat inside the radius and absent outside it — no falloff. The sphere sits
	# on cell 0; a pump at exactly `radius` hops is boosted, one at radius + 1 is
	# not, and the one in between gets the same full amount as the far edge.
	var radius: int = _sphere_def().field_radius
	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_percent
	var bonus: int = _sphere_def().field_restore_percent

	var world := _one_orb_world(radius + 4)
	_place(world, 0, BlockCatalog.SPHERE)
	for hop in range(1, radius + 2):
		_place(world, hop, BlockCatalog.PUMP)

	for hop in range(1, radius + 1):
		check_eq(world.effective_restore_percent(world.graph.get_cell(hop)), pump_base + bonus,
			"a pump %d hops out is inside the field" % hop)
	check_eq(world.effective_restore_percent(world.graph.get_cell(radius + 1)), pump_base,
		"a pump one hop past the radius gets nothing")


func test_sphere_bonuses_stack() -> void:
	# Two spheres reaching the same pump contribute twice. A field that saturated
	# would make the second sphere worthless, which is the mistake the pump's flat
	# restore already avoids.
	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_percent
	var bonus: int = _sphere_def().field_restore_percent

	var world := _one_orb_world(6)
	_place(world, 2, BlockCatalog.PUMP)
	_place(world, 1, BlockCatalog.SPHERE)
	_place(world, 3, BlockCatalog.SPHERE)
	check_eq(world.effective_restore_percent(world.graph.get_cell(2)), pump_base + bonus * 2,
		"both spheres reach the pump")


func test_sphere_interval_never_reaches_zero() -> void:
	# The property that replaced the old floor. Flat tick subtraction hit zero, so
	# it needed a clamp — and the clamp made every sphere past the fourth worth
	# literally nothing. An increased rate divides instead, so the interval keeps
	# falling and never lands on zero however many spheres reach the cell.
	#
	# The generator sits mid-line rather than on cell 0, because a line end has
	# only two cells within radius. Surrounded, it can be reached by four.
	var world := _one_orb_world(9)
	_place(world, 4, BlockCatalog.GENERATOR)
	var generator := world.graph.get_cell(4)
	var base: int = generator.block.def.produce_interval

	var previous := base
	for id in [2, 3, 5, 6]:
		_place(world, id, BlockCatalog.SPHERE)
		var now: int = world.effective_interval(generator)
		# The strict inequality is the point: under the old floor the fourth
		# sphere here bought nothing at all.
		check(now < previous, "sphere on %d shortened the interval further (%d -> %d)"
			% [id, previous, now])
		check(now > 0, "and it never reaches zero")
		previous = now

	# Four spheres is +100% increased, so exactly half the base — well clear of
	# the guard, which is now unreachable in play rather than a balance cap.
	check_eq(previous, StatBonus.apply_rate(base, 4 * _sphere_def().field_rate_percent),
		"four spheres sum to one divisor rather than compounding")
	check(previous > World.MIN_PRODUCE_INTERVAL,
		"and the floor is nowhere near being hit")


func test_sphere_field_follows_a_swap() -> void:
	# Moving a sphere moves its field. This is the case an incrementally-mutated
	# stats table gets wrong: the bonus has to vanish from the old position and
	# appear at the new one, with nothing left behind.
	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_percent
	var bonus: int = _sphere_def().field_restore_percent

	# Pumps far enough apart that one sphere can only ever reach one of them.
	var world := _one_orb_world(12)
	_place(world, 1, BlockCatalog.PUMP)
	_place(world, 9, BlockCatalog.PUMP)
	_place(world, 2, BlockCatalog.SPHERE)

	check_eq(world.effective_restore_percent(world.graph.get_cell(1)), pump_base + bonus,
		"the near pump starts boosted")
	check_eq(world.effective_restore_percent(world.graph.get_cell(9)), pump_base,
		"the far pump starts unboosted")

	# Cell 8 is mined and empty, so this is a move rather than an exchange.
	check(world.swap_blocks(2, 8), "the sphere moved")
	check_eq(world.effective_restore_percent(world.graph.get_cell(1)), pump_base,
		"the old position lost the bonus")
	check_eq(world.effective_restore_percent(world.graph.get_cell(9)), pump_base + bonus,
		"and the new one gained it")


func test_sphere_field_appears_on_mining() -> void:
	# A sphere buried in a locked cell radiates nothing — it is not installed yet.
	# Mining the cell is what lights the field, and the stats table has to notice
	# even though mining goes through the graph rather than through World.
	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_percent
	var bonus: int = _sphere_def().field_restore_percent

	var world := _one_orb_world(6)
	_place(world, 1, BlockCatalog.PUMP)

	var buried := world.graph.get_cell(2)
	buried.initial_block_id = BlockCatalog.SPHERE
	buried.is_unlocked = false
	check_eq(world.effective_restore_percent(world.graph.get_cell(1)), pump_base,
		"a buried sphere radiates nothing")

	world.graph.unlock_cell(2)
	check_eq(world.effective_restore_percent(world.graph.get_cell(1)), pump_base + bonus,
		"mining it lights the field")


func test_sphere_does_not_pulse() -> void:
	# A sphere acts on no tick — its contribution is continuous — so there is no
	# instant to flash and it must never mark itself active. The view shows its
	# field instead.
	var world := _line_world(6)
	_place(world, 1, BlockCatalog.SPHERE)
	_run(world, 100)
	check_eq(world.graph.get_cell(1).block.last_active_tick, -1,
		"the sphere never marked itself active")


# --- Tests: challenges --------------------------------------------------
#
# Board-wide buffs, granted by mining a challenge cell. Where a sphere's bonus is
# keyed by position, these are read by every consumer on the map, so the thing
# worth pinning is that they apply *everywhere* and only once mined.


func test_challenge_surge_raises_launch_value() -> void:
	# A Surge raises what every generator launches with, and `produced` books the
	# larger figure — the ledger has to see the value that actually entered the
	# economy, not the constant it would have been.
	var bonus: int = BlockCatalog.get_def(BlockCatalog.CHALLENGE_SURGE) \
		.global_orb_value_bonus

	var world := _one_orb_world(6)
	check_eq(world.effective_orb_value(), World.ORB_START_VALUE,
		"no challenge mined, so the base value stands")

	_place(world, 2, BlockCatalog.CHALLENGE_SURGE)
	check_eq(world.effective_orb_value(), World.ORB_START_VALUE + bonus,
		"the Surge raised the launch value")

	# 5 hops, so the extra value survives the trip intact.
	_launch_one(world, 0, 5)
	check_eq(world.produced, World.ORB_START_VALUE + bonus,
		"produced books what was actually emitted")
	check_eq(world.delivered, World.ORB_START_VALUE + bonus - 4,
		"and the orb carried it the whole way")
	check(world.ledger_balanced(), "ledger balanced")


func test_challenge_current_boosts_pumps_only() -> void:
	# A Current adds percentage points to every pump on the board, wherever it is
	# and with no sphere anywhere. Blocks that restore nothing are untouched: the
	# bonus is folded in through `base_restore_percent`, which bails on a base of 0.
	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_percent
	var bonus: int = BlockCatalog.get_def(BlockCatalog.CHALLENGE_CURRENT) \
		.global_field_restore_percent

	var world := _one_orb_world(8)
	_place(world, 1, BlockCatalog.PUMP)
	# Far enough from the pump that no field could reach it even if it had one.
	_place(world, 6, BlockCatalog.CHALLENGE_CURRENT)

	check_eq(world.effective_restore_percent(world.graph.get_cell(1)), pump_base + bonus,
		"a pump nowhere near the challenge still gets the bonus")
	check_eq(world.effective_restore_percent(world.graph.get_cell(6)), 0,
		"the challenge itself restores nothing")

	_launch_one(world, 0, 5)
	check_eq(world.restored,
		StatBonus.percent_of(World.ORB_START_VALUE, pump_base + bonus),
		"the pump restored the boosted amount")
	check(world.ledger_balanced(), "ledger balanced")


func test_challenge_lens_widens_sphere_field() -> void:
	# A Lens scales every sphere's radius by a percentage — the only multiplicative
	# buff in the game. At the sphere's radius of 2 that buys exactly one hop, so a
	# pump at 3 hops comes inside the field and one at 4 stays out.
	var radius: int = _sphere_def().field_radius
	var percent: int = BlockCatalog.get_def(BlockCatalog.CHALLENGE_LENS) \
		.global_field_radius_percent
	var widened := GlobalBonus.scale_percent(radius, percent)
	check(widened > radius, "the Lens is meant to widen the field")

	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_percent
	var bonus: int = _sphere_def().field_restore_percent

	var world := _one_orb_world(widened + 4)
	_place(world, 0, BlockCatalog.SPHERE)
	for hop in range(1, widened + 2):
		_place(world, hop, BlockCatalog.PUMP)

	check_eq(world.effective_restore_percent(world.graph.get_cell(widened)), pump_base,
		"before the Lens, a pump at the widened radius is out of range")

	_place(world, widened + 2, BlockCatalog.CHALLENGE_LENS)

	check_eq(world.effective_field_radius(_sphere_def()), widened,
		"the Lens widened the reported radius")
	check_eq(world.effective_restore_percent(world.graph.get_cell(widened)), pump_base + bonus,
		"and the pump at that radius is now inside the field")
	check_eq(world.effective_restore_percent(world.graph.get_cell(widened + 1)), pump_base,
		"one hop past the widened radius still gets nothing")


func test_challenge_grants_nothing_while_buried() -> void:
	# Mining is the whole transaction, so the board must not pay out first. The
	# same rule a buried sphere follows, checked on the global half of the pass.
	var world := _one_orb_world(6)
	world.graph.get_cell(3).initial_block_id = BlockCatalog.CHALLENGE_SURGE
	world.mark_stats_dirty()
	check_eq(world.effective_orb_value(), World.ORB_START_VALUE,
		"a buried challenge grants nothing")

	world.graph.unlock_cell(3)
	check(world.effective_orb_value() > World.ORB_START_VALUE,
		"mining it turns the buff on")


func test_challenge_cannot_be_swapped() -> void:
	# Anchored from both sides, like a generator: it can neither be picked up nor
	# displaced by something arriving.
	var world := _one_orb_world(6)
	_place(world, 2, BlockCatalog.CHALLENGE_SURGE)
	_place(world, 4, BlockCatalog.PUMP)

	check(not world.can_swap(2, 4), "a challenge cannot be picked up")
	check(not world.can_swap(4, 2), "and nothing can be swapped onto it")

	world.swap_blocks(2, 4)
	check_eq(world.graph.get_cell(2).block.def.id, BlockCatalog.CHALLENGE_SURGE,
		"the challenge stayed put")
	check_eq(world.graph.get_cell(4).block.def.id, BlockCatalog.PUMP,
		"and so did the pump")


func test_challenge_ignores_a_sphere() -> void:
	# A challenge declares no interval and no restore, so a sphere's field lands on
	# its cell and finds nothing to change. This is what "cannot be buffed by a
	# sphere" means in practice — no flag enforces it, the numbers do.
	var world := _one_orb_world(6)
	_place(world, 2, BlockCatalog.CHALLENGE_SURGE)
	var before: int = world.effective_orb_value()

	_place(world, 1, BlockCatalog.SPHERE)

	check_eq(world.effective_orb_value(), before,
		"a sphere next to a challenge changes nothing about it")
	check_eq(world.effective_interval(world.graph.get_cell(2)), 0,
		"a challenge has no interval to shorten")
	check_eq(world.effective_restore_percent(world.graph.get_cell(2)), 0,
		"and no restore to raise")
	check(not world.is_boosted(2), "so it is never drawn as boosted")


func test_challenge_does_not_pulse() -> void:
	# Continuous, like a sphere: there is no instant to flash, so it must never
	# mark itself active.
	var world := _line_world(6)
	_place(world, 2, BlockCatalog.CHALLENGE_SURGE)
	_run(world, 100)
	check_eq(world.graph.get_cell(2).block.last_active_tick, -1,
		"the challenge never marked itself active")


func test_challenge_is_known_before_it_is_mined() -> void:
	# The category is public, the identity is not. A player must be able to see
	# that a triangle is worth saving for; seeing *which* one would remove the
	# reason to dig it.
	var world := _one_orb_world(6)
	var cell := world.graph.get_cell(3)
	cell.initial_block_id = BlockCatalog.CHALLENGE_LENS

	check(cell.is_challenge(), "a buried challenge announces itself")
	check(not cell.is_unlocked, "and is still unmined")
	check(not world.graph.get_cell(2).is_challenge(), "an empty cell does not")

	world.graph.unlock_cell(3)
	check(cell.is_challenge(), "and it stays a challenge once mined")

	var plain := world.graph.get_cell(1)
	plain.initial_block_id = BlockCatalog.PUMP
	check(not plain.is_challenge(), "an ordinary buried block is not a challenge")


func test_global_buff_does_not_mark_pumps_boosted() -> void:
	# The boost ring means "a sphere reaches here". A global reaches everywhere,
	# which is the same as nowhere for a mark whose job is to point at one — so a
	# Current must not light up every pump on the board.
	var world := _one_orb_world(8)
	_place(world, 1, BlockCatalog.PUMP)
	_place(world, 6, BlockCatalog.CHALLENGE_CURRENT)

	check(world.effective_restore_percent(world.graph.get_cell(1))
		> BlockCatalog.get_def(BlockCatalog.PUMP).restore_percent,
		"the pump really is restoring more than its base")
	check(not world.is_boosted(1), "but no sphere is doing it, so no ring")

	_place(world, 2, BlockCatalog.SPHERE)
	check(world.is_boosted(1), "a real sphere still marks it")


func test_challenge_triangle_geometry() -> void:
	# The board's only non-circular cell. Pure geometry, so it is checked here
	# rather than on a screenshot.
	var view = load("res://scenes/view/GraphView.gd")
	var centre := Vector2(100.0, 50.0)
	var radius := 20.0
	var points: PackedVector2Array = view.triangle_points(centre, radius)

	check_eq(points.size(), 3, "a triangle has three corners")
	for p in points:
		check(absf(centre.distance_to(p) - radius) < 0.001,
			"every corner sits on the circumradius")
	# Point-up: the first corner is directly above the centre, and the other two
	# are below it. Screen space, so -y is up.
	check(absf(points[0].x - centre.x) < 0.001, "the first corner is centred")
	check(points[0].y < centre.y, "and points up")
	check(points[1].y > centre.y and points[2].y > centre.y,
		"the other two form the base")


# --- Tests: tiers and the upgrader --------------------------------------


## A line with an upgrader on cell 1, mined, and no generator — so a test can
## feed it by hand and read the ledger without a producer's output muddying the
## aggregate counters. Cell 0 is mined so it can emit; everything else is priced
## out of reach so nothing unlocks mid-test.
##
## `_discover_line` mines the even cells, so cell 1 has to be mined explicitly.
func _upgrader_world(count: int, def_id: String = BlockCatalog.UPGRADER) -> World:
	var graph := MapLoader.line_graph(count)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 1000000
	graph.get_cell(1).initial_block_id = def_id
	_discover_line(graph)
	graph.unlock_cell(1)
	return World.new(graph)


## The charge banked on a cell, for readability at the call sites below.
func _charge_of(world: World, cell_id: int) -> int:
	return world.graph.get_cell(cell_id).block.charge


func test_upgrader_banks_red_and_emits_orange() -> void:
	# Six full red orbs is exactly the 60 an upgrader needs. The proof that what
	# came out was orange is that it opened a cell only orange can open — a red
	# orb arriving there counts for nothing, as the test below pins.
	var world := _upgrader_world(4)
	world.graph.get_cell(3).required_tier = Tiers.ORANGE
	check(world.set_target(1, 3), "the upgrader aims at the orange cell")

	for i in 6:
		_launch_one(world, 0, 1)
	check_eq(world.converted, 60, "six full orbs bank exactly the upgrade cost")
	check_eq(world.delivered, 0, "absorbing into a block is not delivering")

	# 2 hops out, so the orange orb crosses one cell and arrives with 9.
	_run(world, 2 * World.TICKS_PER_HOP + 2)
	check_eq(world.graph.get_cell(3).unlock_progress, 9,
		"the minted orange orb opened a cell red cannot touch")
	check_eq(_charge_of(world, 1), 0, "and the charge was spent")
	check(world.ledger_balanced(), "ledger balanced across the conversion")


func test_a_generator_of_every_colour_emits_its_own_tier() -> void:
	# Every colour has generators of its own now, so income does not have to run
	# through a converter. The rule this pins is that a generator's colour is a
	# property of its *type* and reaches the orb it emits — nothing downstream
	# passes a tier in, so a family member wired to the wrong `output_tier` would
	# emit red and only show up as a cell that mysteriously refuses to open.
	for tier in Tiers.COUNT:
		var graph := MapLoader.line_graph(3)
		for id in graph.cell_ids:
			graph.get_cell(id).unlock_cost = 1000000
		graph.get_cell(0).initial_block_id = BlockCatalog.generator_id(tier)
		_discover_line(graph)
		var world := World.new(graph)

		# A cell that takes exactly this colour, which is the only thing that can
		# tell the seven apart from outside.
		world.graph.get_cell(2).required_tier = tier
		world.graph.get_cell(2).unlock_cost = 9
		check(world.set_target(0, 2),
			"the %s generator may aim at a %s cell" % [Tiers.name_of(tier),
				Tiers.name_of(tier)])

		_run(world, _ticks_for_one_delivery(2))
		check_eq(world.graph.get_cell(2).unlock_progress, 9,
			"a %s orb arrived and counted" % Tiers.name_of(tier))
		check(world.ledger_balanced(), "ledger balanced for %s" % Tiers.name_of(tier))


func test_a_generator_cannot_open_another_colour() -> void:
	# The other half of the rule above, and the reason the ladder gates anything
	# at all: a source may only open cells of the colour it makes. Checked one
	# step in each direction, because "wrong colour" has to mean wrong rather
	# than merely lower.
	var graph := MapLoader.line_graph(3)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 1000000
	graph.get_cell(0).initial_block_id = BlockCatalog.generator_id(Tiers.GREEN)
	_discover_line(graph)
	var world := World.new(graph)

	world.graph.get_cell(2).required_tier = Tiers.TEAL
	check(not world.set_target(0, 2),
		"a green generator is refused a teal cell, one colour up")
	world.graph.get_cell(2).required_tier = Tiers.YELLOW
	check(not world.set_target(0, 2),
		"and a yellow one, one colour down")
	world.graph.get_cell(2).required_tier = Tiers.GREEN
	check(world.set_target(0, 2), "its own colour is the one it opens")


func test_the_ladder_converts_one_step_at_a_time() -> void:
	# A chain: red into an orange upgrader, orange into a yellow one. What this
	# pins is that a step of the ladder accepts *only* its input colour — the
	# yellow upgrader must refuse the red that feeds the one before it, or the
	# chain collapses into a single hop and the middle colour is decoration.
	var world := _upgrader_world(4, BlockCatalog.upgrader_id(Tiers.YELLOW))
	var cost: int = BlockCatalog.get_def(BlockCatalog.UPGRADER).upgrade_cost

	for i in 6:
		_launch_one(world, 0, 1, Tiers.RED)
	check_eq(world.converted, 0, "a yellow upgrader banks none of the red sent to it")
	check_eq(_charge_of(world, 1), 0, "nothing reached its bank")

	for i in 6:
		_launch_one(world, 0, 1, Tiers.ORANGE)
	check_eq(world.converted, cost, "the orange it does eat banks in full")

	# And what comes out is yellow: it opens a yellow cell, which neither the red
	# nor the orange that paid for it could have touched.
	world.graph.get_cell(3).required_tier = Tiers.YELLOW
	check(world.set_target(1, 3), "the yellow upgrader aims at a yellow cell")
	_run(world, 2 * World.TICKS_PER_HOP + 2)
	check_eq(world.graph.get_cell(3).unlock_progress, 9,
		"the minted yellow orb opened a cell nothing below it could")
	check(world.ledger_balanced(), "ledger balanced across two colours")


func test_idle_cycling_walks_one_colour_at_a_time() -> void:
	# The idle indicator is keyed by block *type*, and there are seven generator
	# types now. Clicking the red button must walk the red generators and skip a
	# teal one standing idle beside them, or the jump lands somewhere the player
	# did not ask to go.
	var graph := MapLoader.line_graph(6)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 1000000
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	graph.get_cell(2).initial_block_id = BlockCatalog.generator_id(Tiers.TEAL)
	graph.get_cell(4).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	var world := World.new(graph)

	check_eq(world.idle_cells_of(BlockCatalog.GENERATOR), PackedInt32Array([0, 4]),
		"the red generators are idle, and only them")
	check_eq(world.idle_cells_of(BlockCatalog.generator_id(Tiers.TEAL)),
		PackedInt32Array([2]), "the teal one counts under its own colour")
	check_eq(world.next_idle_after(BlockCatalog.GENERATOR, 0), 4,
		"cycling red skips the teal generator between them")


func test_upgrader_banks_charge_while_idle() -> void:
	# Unaimed, it still absorbs. Mining unaims whatever was pointed at the cell,
	# so an upgrader that refused orbs while idle would throw away everything in
	# flight during that window.
	var world := _upgrader_world(4)
	for i in 3:
		_launch_one(world, 0, 1)
	check_eq(world.converted, 30, "an idle upgrader still banks what arrives")
	check_eq(_charge_of(world, 1), 30, "and holds it")
	check_eq(world.live_orb_count(), 0, "having emitted nothing")

	# Aim it, top it up, and the banked charge is still there to spend.
	world.graph.get_cell(3).required_tier = Tiers.ORANGE
	check(world.set_target(1, 3), "aimed after the fact")
	for i in 3:
		_launch_one(world, 0, 1)
	check_eq(_charge_of(world, 1), 0, "the charge banked while idle was not lost")


func test_upgrader_bank_caps_at_one_orb() -> void:
	# Twelve orbs would once have been two full charges banked. The bank now holds
	# room for exactly one output orb, so the second six are refused at the intake
	# and waste — an unfed converter can no longer stockpile out of sight.
	var world := _upgrader_world(4)
	for i in 12:
		_launch_one(world, 0, 1)
	check_eq(_charge_of(world, 1), 60, "one charge banked, and no more")
	check_eq(world.converted, 60, "only what fitted was converted")
	check_eq(world.wasted, 60, "the rest wasted rather than banked")
	check(world.ledger_balanced(), "and the overflow stayed inside the ledger")

	world.graph.get_cell(3).required_tier = Tiers.ORANGE
	check(world.set_target(1, 3), "aimed")
	world.tick()
	check_eq(world.live_orb_count(), 1, "the banked charge leaves as one orb")
	check_eq(_charge_of(world, 1), 0, "and the bank is empty behind it")
	world.tick()
	check_eq(world.live_orb_count(), 1, "with nothing left to emit a second")


func test_upgrader_overflow_is_wasted_not_recorded() -> void:
	# The partial-absorb path, at the boundary. A bank at 55 has room for 5, so a
	# 10-value orb splits: 5 converted, 5 wasted. What the delivery-event channel
	# reports must be the 5 that counted, not the 10 that arrived — the number the
	# board floats has to match the arc's jump.
	var world := _upgrader_world(4)
	for i in 5:
		_launch_one(world, 0, 1)
	world.graph.get_cell(1).block.charge = 55
	world.take_delivery_events()

	var before_wasted := world.wasted
	_launch_one(world, 0, 1)
	check_eq(_charge_of(world, 1), 60, "the bank filled to the cap exactly")
	check_eq(world.wasted - before_wasted, 5, "the half that would not fit wasted")

	var events := world.take_delivery_events()
	check_eq(events.size(), 1, "one delivery recorded")
	if events.size() == 1:
		check_eq(events[0].amount, 5, "recorded at what counted, not what arrived")

	# And a full bank refuses outright rather than absorbing zero-value-for-free.
	before_wasted = world.wasted
	_launch_one(world, 0, 1)
	check_eq(_charge_of(world, 1), 60, "a full bank takes nothing")
	check_eq(world.wasted - before_wasted, 10, "the whole orb wasted")
	check_eq(world.take_delivery_events().size(), 0, "and nothing was recorded")
	check(world.ledger_balanced(), "ledger balanced across both refusals")


func test_upgrader_ignores_passing_orbs() -> void:
	# The deliver hook is the exact counterpart of `on_orb_pass`: it sees only
	# the orb that stops here. An orb merely routed across an upgrader is
	# untouched, so a converter cannot be used as a toll gate on someone else's
	# line.
	var world := _upgrader_world(4)
	_launch_one(world, 0, 3)
	check_eq(world.converted, 0, "a passing orb was not absorbed")
	check_eq(_charge_of(world, 1), 0, "and banked nothing")
	check_eq(world.graph.get_cell(3).unlock_progress, 8,
		"it carried on and delivered, 2 cells crossed")


func test_upgrader_rejects_wrong_tier_input() -> void:
	# An upgrader takes red. Orange arriving at one is not banked — it wastes,
	# the way delivery into any mined cell without a matching intake does.
	var world := _upgrader_world(4)
	world.emit_orb(0, 1, Tiers.ORANGE)
	_run(world, World.TICKS_PER_HOP + 2)
	check_eq(world.converted, 0, "orange is not what this upgrader eats")
	check_eq(world.wasted, World.ORB_START_VALUE, "so the whole value wasted")
	check(world.ledger_balanced(), "ledger balanced")


func test_upgrader_cannot_be_swapped() -> void:
	# Anchored, like a generator. A movable converter parked beside the frontier
	# would collapse the orange leg of every route to one hop.
	var world := _upgrader_world(4)
	_place(world, 2, BlockCatalog.PUMP)
	check(not world.can_swap(1, 2), "an upgrader cannot be picked up")
	check(not world.can_swap(2, 1), "nor displaced by something arriving")


func test_upgrader_marks_active_only_when_it_emits() -> void:
	# Absorbing is not acting. The pulse marks the moment an orb leaves, which
	# is what a generator's does, so a converter being fed but unable to fire
	# reads as idle rather than busy.
	var world := _upgrader_world(4)
	world.graph.get_cell(3).required_tier = Tiers.ORANGE
	check(world.set_target(1, 3), "aimed")
	for i in 5:
		_launch_one(world, 0, 1)
	check_eq(_charge_of(world, 1), 50, "banked, but short of the cost")
	check_eq(world.graph.get_cell(1).block.last_active_tick, -1,
		"absorbing alone never pulsed it")

	_launch_one(world, 0, 1)
	check(world.graph.get_cell(1).block.last_active_tick > 0,
		"the emission did")


func test_sphere_discounts_an_upgrader() -> void:
	# A converter's clock is denominated in delivered value rather than ticks, so
	# the sphere's charge axis is the same buff its rate axis is: it charges
	# faster. Asymptotic like the interval, so it never reaches zero.
	var upgrader_def := BlockCatalog.get_def(BlockCatalog.UPGRADER)
	var discounted: int = StatBonus.apply_rate(upgrader_def.upgrade_cost,
		_sphere_def().field_charge_percent)
	check(discounted < upgrader_def.upgrade_cost, "the discount is a real one")

	var world := _upgrader_world(4)
	_place(world, 2, BlockCatalog.SPHERE)
	world.graph.get_cell(3).required_tier = Tiers.ORANGE
	check(world.set_target(1, 3), "aimed")

	var upgrader := world.graph.get_cell(1)
	check(world.field_cells(2).has(1), "the sphere's field reaches the upgrader")
	check_eq(world.effective_upgrade_cost(upgrader), discounted,
		"so its cost is discounted")
	check_eq(world.base_upgrade_cost(upgrader), upgrader_def.upgrade_cost,
		"and the baseline still reports what it would cost alone")
	# A converter is finally a block a sphere changes, so the board rings it like
	# every other buffed cell.
	check(world.is_boosted(1), "and the cell is marked boosted")

	# Five orbs is 50 delivered — short of the base 60, but past the discounted
	# cost, so the converter fires where it previously would have sat waiting.
	check(50 >= discounted and 50 < upgrader_def.upgrade_cost,
		"the test really does straddle the two costs")
	for i in 5:
		_launch_one(world, 0, 1)
	# The cap is the discounted cost, so the fifth orb is the one that is split:
	# it banks the last of the room and the remainder wastes. A sphere therefore
	# buys throughput and *tightens* the bank at the same time, which is the one
	# interaction between the two features worth pinning.
	check_eq(world.converted, discounted, "it banked exactly the discounted cost")
	check_eq(world.wasted, 50 - discounted, "and the overshoot wasted")
	check_eq(_charge_of(world, 1), 0, "the emission then emptied the bank")
	check_eq(world.live_orb_count(), 1, "and one orange orb is on its way")
	check(world.ledger_balanced(), "ledger balanced")


func test_sphere_upgrade_cost_never_reaches_zero() -> void:
	# The upgrader's half of `test_sphere_interval_never_reaches_zero`. Stacking
	# spheres keeps making a conversion cheaper without ever making it free, which
	# is what an increased rate buys over a flat discount.
	var world := _upgrader_world(4)
	var upgrader := world.graph.get_cell(1)
	var previous: int = world.base_upgrade_cost(upgrader)

	for id in [0, 2, 3]:
		_place(world, id, BlockCatalog.SPHERE)
		var now: int = world.effective_upgrade_cost(upgrader)
		check(now < previous, "sphere on %d cut the cost further (%d -> %d)"
			% [id, previous, now])
		check(now >= World.MIN_UPGRADE_COST, "and a conversion is never free")
		previous = now


func test_orange_cell_ignores_red_orbs() -> void:
	# The gate itself. A cell states the colour it takes, and anything else
	# arriving counts for nothing rather than counting a little.
	var world := _upgrader_world(4)
	world.graph.get_cell(3).required_tier = Tiers.ORANGE
	_launch_one(world, 0, 3)
	check_eq(world.graph.get_cell(3).unlock_progress, 0, "red bought no progress")
	check_eq(world.delivered, 0, "and counted as delivered nowhere")
	check_eq(world.wasted, 8, "the whole arrival wasted")
	check(world.ledger_balanced(), "ledger balanced")


func test_cannot_aim_red_at_an_orange_cell() -> void:
	# Refused up front rather than allowed and wasted, so the board teaches the
	# rule instead of quietly eating the output. Same shape as the refusals for a
	# mined target and a fogged one.
	var world := _one_orb_world(4)
	_place(world, 0, BlockCatalog.GENERATOR)
	world.graph.get_cell(3).required_tier = Tiers.ORANGE

	check(not world.can_aim_at(0, 3), "a red source cannot aim at an orange cell")
	check(not world.set_target(0, 3), "and set_target refuses it")
	check_eq(world.graph.get_cell(0).block.target_id, -1, "so it stays idle")
	check(world.set_target(0, 1), "a red cell at the same distance is fine")


func test_can_aim_a_generator_at_an_upgrader() -> void:
	# The one exception to "a mined cell is never a target": a mined cell holding
	# a converter that takes this colour. Without it no upgrader is ever fed.
	var world := _upgrader_world(4)
	_place(world, 0, BlockCatalog.GENERATOR)
	check(world.can_aim_at(0, 1), "a mined cell with a matching intake is a target")
	check(world.set_target(0, 1), "and the aim is accepted")


func test_cannot_aim_at_a_mined_cell_without_an_intake() -> void:
	# The default is still refusal. Cell 2 is mined and empty, and cell 1 holds
	# an upgrader that takes red but not orange.
	var world := _upgrader_world(4)
	_place(world, 0, BlockCatalog.GENERATOR)
	check(not world.can_aim_at(0, 2), "a mined empty cell is not a target")

	_place(world, 2, BlockCatalog.PUMP)
	check(not world.can_aim_at(0, 2), "and neither is a mined pump")


func test_locked_cell_tint_follows_its_tier() -> void:
	# The board says which colour a cell takes by how it is drawn. Pure colour
	# maths, so it is checked here rather than on a screenshot — the same way the
	# challenge triangle's geometry is.
	var view = load("res://scenes/view/GraphView.gd")
	var red: Color = view._gate_fill(Tiers.color_of(Tiers.RED))
	var orange: Color = view._gate_fill(Tiers.color_of(Tiers.ORANGE))
	check(red != orange, "two tiers do not draw the same fill")

	# Blended toward the dark locked palette rather than used raw, so unmined
	# ground stays quieter than the blocks working on top of it.
	var raw := Tiers.color_of(Tiers.ORANGE)
	check(orange.v < raw.v, "the fill is darker than the tier colour itself")
	check(view._gate_label(raw).v > orange.v, "and the label is brighter than the fill")

	# Every pair of tiers, not just the first two. Seven colours on one board is
	# where a near-duplicate becomes possible, and the fill is the most muted of
	# the three blends — so if two tiers are distinguishable here they are
	# distinguishable everywhere.
	for a in Tiers.COUNT:
		for b in range(a + 1, Tiers.COUNT):
			check(view._gate_fill(Tiers.color_of(a)) != view._gate_fill(Tiers.color_of(b)),
				"%s and %s draw different fills"
					% [Tiers.name_of(a), Tiers.name_of(b)])


func test_tier_tables_are_consistent() -> void:
	# Nothing else in the suite reads these tables, and an entry left behind when
	# a tier is inserted is silent: `color_of` would answer WHITE and `from_name`
	# would fall back to red, so a whole band of the map would quietly open to the
	# starting colour.
	check_eq(Tiers.NAMES.size(), Tiers.COUNT, "a name for every tier")
	check_eq(Tiers.COLORS.size(), Tiers.COUNT, "a colour for every tier")

	for tier in Tiers.COUNT:
		check_eq(Tiers.from_name(Tiers.name_of(tier)), tier,
			"%s survives a round trip through its name" % Tiers.name_of(tier))

	# The colours are the board's only hues — every block that carries no tier is
	# painted from a neutral ramp — so a tier colour that reads as grey would put
	# a resource in the same visual language as a pump. Saturation is what says
	# "this is a colour"; 0.35 is well below any of the seven and well above the
	# neutrals, which sit under 0.15.
	for tier in Tiers.COUNT:
		var color := Tiers.color_of(tier)
		check(color.s > 0.35,
			"%s is a colour rather than a grey (saturation %.2f)"
				% [Tiers.name_of(tier), color.s])

	# And they have to be told apart from each other. Compared in hue rather than
	# RGB distance, because hue is what a player reads at a glance on a board
	# where every cell is the same size and shape.
	for a in Tiers.COUNT:
		for b in range(a + 1, Tiers.COUNT):
			var gap: float = absf(Tiers.color_of(a).h - Tiers.color_of(b).h)
			gap = minf(gap, 1.0 - gap)  # hue wraps
			check(gap > 0.03,
				"%s and %s are far enough apart in hue (%.3f)"
					% [Tiers.name_of(a), Tiers.name_of(b), gap])


func test_tierless_blocks_are_neutral() -> void:
	# The other half of the rule above: a pump, a sphere and an upkeep block act
	# on orbs of every colour, so none of them may claim one. This is what the
	# board's palette means — a hue on screen is always a resource — and it is
	# exactly the kind of rule that decays silently, because a block painted a
	# tier colour looks fine on its own and only misleads next to the tier.
	for id in [BlockCatalog.PUMP, BlockCatalog.SPHERE, BlockCatalog.UPKEEP]:
		var def := BlockCatalog.get_def(id)
		check(def.color.s < 0.15,
			"%s is painted a neutral (saturation %.2f)" % [id, def.color.s])

	# A generator and an upgrader are the opposite case: they *are* their output
	# colour, which is how a board says at a glance what a source makes.
	for tier in Tiers.COUNT:
		check_eq(BlockCatalog.get_def(BlockCatalog.generator_id(tier)).color,
			Tiers.color_of(tier),
			"the %s generator is painted its own colour" % Tiers.name_of(tier))


## The precondition of the whole right-click gesture. Right-click aims what can
## be aimed and moves what can be moved, and it can only carry both meanings
## because no block answers to both: generators and upgraders are anchored, pumps
## and spheres and upkeep blocks take no target, challenges are neither.
##
## Nothing enforces this except the catalog being written that way in three
## separate places, and the failure is silent rather than loud — a block that was
## both would simply make one click mean two things, with `Main._on_aim_click`
## picking the aim branch and the swap quietly unreachable. So it is pinned here
## rather than trusted.
##
## The view leans on it too: `_draw_aim_preview` and `_draw_swap_preview` are
## mutually exclusive by exactly this property, which is why their order in
## `GraphView._draw()` arbitrates nothing.
func test_needs_target_and_movable_are_disjoint() -> void:
	var aimable := 0
	var movable := 0
	for id in BlockCatalog.ids():
		var def := BlockCatalog.get_def(id)
		check(not (def.needs_target and def.movable),
			"%s is aimable or movable, not both" % id)
		if def.needs_target:
			aimable += 1
		if def.movable:
			movable += 1

	# Both sides are non-empty, or the property would hold vacuously and the test
	# would keep passing after a refactor that emptied one of them.
	check(aimable > 0, "something on the board is aimed (%d)" % aimable)
	check(movable > 0, "something on the board is movable (%d)" % movable)


# --- Tests: unlocking ---------------------------------------------------


func test_unlock_exact() -> void:
	# 2 hops, so each orb crosses one cell and arrives with 9. A cost of 27 needs
	# exactly 3 orbs and leaves nothing wasted.
	var graph := MapLoader.line_graph(3)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	graph.get_cell(2).unlock_cost = 27
	var world := World.new(graph)
	world.set_target(0, 2)

	_run(world, _ticks_for_one_delivery(2) + 2 * 20)
	check(graph.get_cell(2).is_unlocked, "cell 2 unlocked")
	check_eq(graph.get_cell(2).unlock_progress, 27, "progress landed exactly")
	check_eq(world.delivered, 27, "all delivered value counted")
	check_eq(world.wasted, 0, "no overshoot")


func test_unlock_overshoot_is_wasted() -> void:
	# Cost 20, orbs arrive with 9: 9 + 9 + 9 overshoots by 7.
	var graph := MapLoader.line_graph(3)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	graph.get_cell(2).unlock_cost = 20
	var world := World.new(graph)
	world.set_target(0, 2)

	_run(world, _ticks_for_one_delivery(2) + 2 * 20)
	check(graph.get_cell(2).is_unlocked, "cell 2 unlocked")
	check_eq(world.delivered, 20, "only the needed value counted")
	check_eq(world.wasted, 7, "overshoot recorded as waste")
	check(world.ledger_balanced(), "ledger balanced")


# --- Tests: delivery events (presentation only) -------------------------


## The same run as test_unlock_overshoot_is_wasted, watched through the event
## channel: cost 20, orbs arriving with 8, so the third one counts for 4.
##
## The events must report what *counted*, not what was carried — that is what
## makes the number on screen match the arc's jump.
func test_delivery_events_report_what_counted() -> void:
	var graph := MapLoader.line_graph(3)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	graph.get_cell(2).unlock_cost = 20
	var world := World.new(graph)
	world.set_target(0, 2)

	var amounts: Array[int] = []
	for i in _ticks_for_one_delivery(2) + 2 * 20:
		world.tick()
		for event in world.take_delivery_events():
			check_eq(event.cell_id, 2, "the event names the cell that was fed")
			check_eq(event.tier, Tiers.RED, "and the tier that arrived")
			amounts.append(event.amount)

	check_eq(amounts, [9, 9, 2] as Array[int], "each event is what counted, not what was carried")

	# The invariant worth pinning. The list's *order* is not order-independent and
	# deliberately never will be, but its sum is the same addition the ledger
	# made — so this catches recording orb.value instead of used, recording on
	# the wasted branch, and double-recording.
	var total := 0
	for amount in amounts:
		total += amount
	check_eq(total, world.delivered + world.converted + world.burned,
		"the events sum to exactly what the ledger counted")
	check_eq(world.wasted, 7, "and the overshoot stayed out of them")
	check_eq(world.converted, 0, "nothing was converted in this run")


func test_delivery_events_drain_empties() -> void:
	var world := _line_world(3, 20)
	_run(world, _ticks_for_one_delivery(2))

	check(world.take_delivery_events().size() > 0, "a delivery was recorded")
	check_eq(world.take_delivery_events().size(), 0, "draining empties the buffer")


## The headless suite runs thousands of ticks with nobody draining. Without a cap
## this array is a leak that only shows up in long runs.
func test_delivery_events_are_bounded() -> void:
	var world := _busy_world()
	_run(world, 2000)
	check(world.take_delivery_events().size() <= World.MAX_DELIVERY_EVENTS,
		"an undrained buffer stays bounded")


## Value landing on a cell that is already mined is pure waste, and waste is a
## different message. A "+0" floating over a finished cell would be worse than
## silence.
func test_no_event_for_waste_into_mined_cell() -> void:
	var world := _line_world(3, 20)
	_run(world, _ticks_for_one_delivery(2))
	world.take_delivery_events()

	# Mine the destination out from under the orbs already on their way.
	world.graph.unlock_cell(2)
	var wasted_before := world.wasted
	_run(world, 3 * 20)

	check(world.wasted > wasted_before, "value did land on the mined cell")
	check_eq(world.take_delivery_events().size(), 0, "but nothing was announced")


# --- Tests: block activity (drives the pulse, presentation only) ---------


## Running the cycle is not acting. The mark has to land on the tick an orb
## actually leaves, or a generator would pulse every tick it merely counted.
func test_generator_marks_active_only_when_it_emits() -> void:
	var world := _line_world(3, 20)
	var gen: Block = world.graph.get_cell(0).block
	check_eq(gen.last_active_tick, -1, "a block that has never fired carries no mark")
	check_eq(gen.ticks_since_active(world.tick_count), -1, "and no age either")

	var interval := gen.def.produce_interval
	_run(world, interval - 1)
	check_eq(gen.last_active_tick, -1, "counting toward an emission is not acting")

	world.tick()
	check_eq(gen.last_active_tick, interval, "the emitting tick is the one that counts")
	check_eq(gen.ticks_since_active(world.tick_count), 0, "and it reads as just now")


## A generator whose target it cannot route to still runs its cycle — the timer
## resets — but nothing leaves the cell, so nothing should pulse. This is why
## emit_orb reports whether it emitted.
func test_generator_with_no_route_never_marks() -> void:
	var world := _line_world(3, 20)
	var gen: Block = world.graph.get_cell(0).block
	# Set behind set_target's back: it refuses an unroutable target, which is
	# exactly the guard being tested underneath it.
	gen.target_id = 999

	var produced_before := world.produced
	_run(world, gen.def.produce_interval * 3)
	check_eq(world.produced, produced_before, "nothing was emitted")
	check_eq(gen.last_active_tick, -1, "so the generator never read as active")


func test_pump_marks_active_when_an_orb_passes() -> void:
	var world := _one_orb_world(5)
	_place(world, 2, BlockCatalog.PUMP)
	var pump: Block = world.graph.get_cell(2).block
	check_eq(pump.last_active_tick, -1, "nothing has passed yet")

	_launch_one(world, 0, 4)
	check_eq(world.restored, _pump_restore(), "the pump really did restore")
	check(pump.last_active_tick > 0, "and passing through marked it active")


## Blocks never act on an orb's final cell, so the pulse must not fire there
## either. A pump parked on a target is doing nothing, and has to look like it.
func test_pump_at_a_route_end_never_marks() -> void:
	var world := _one_orb_world(5)
	_place(world, 2, BlockCatalog.PUMP)
	var pump: Block = world.graph.get_cell(2).block

	_launch_one(world, 0, 2)
	check_eq(world.restored, 0, "a pump does not fire on an orb's final cell")
	check_eq(pump.last_active_tick, -1, "so it never reads as active")


## The mark lives on the block, not the cell, so a pulse follows the block to
## wherever the player moves it — which is where the activity actually went.
func test_activity_survives_a_swap() -> void:
	var world := _one_orb_world(5)
	_place(world, 2, BlockCatalog.PUMP)
	_launch_one(world, 0, 4)

	var marked: int = world.graph.get_cell(2).block.last_active_tick
	check(marked > 0, "the pump acted before the swap")

	check(world.swap_blocks(2, 3), "the swap was accepted")
	check_eq(world.graph.get_cell(2).block, null, "the pump left its old cell")
	check_eq(world.graph.get_cell(3).block.last_active_tick, marked,
		"and took its activity with it")


# --- Tests: aiming ------------------------------------------------------


func test_no_target_idles() -> void:
	var graph := MapLoader.line_graph(5)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	var world := World.new(graph)

	_run(world, 500)
	check_eq(world.produced, 0, "unaimed generator produced nothing")
	check_eq(world.live_orb_count(), 0, "no orbs exist")


func test_unaimed_generator_banks_nothing() -> void:
	# Idling must not accumulate timer, or aiming would fire a free orb.
	var graph := MapLoader.line_graph(5)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	var world := World.new(graph)

	_run(world, 500)
	world.set_target(0, 4)
	var interval := BlockCatalog.get_def(BlockCatalog.GENERATOR).produce_interval
	_run(world, interval - 1)
	check_eq(world.produced, 0, "no orb before the full interval elapses")
	world.tick()
	check_eq(world.produced, World.ORB_START_VALUE, "exactly one orb on the interval tick")


func test_self_target_rejected() -> void:
	var world := _line_world(5)
	check(not world.set_target(0, 0), "cannot aim a cell at itself")
	check_eq(world.graph.get_cell(0).block.target_id, 4, "target unchanged")


func test_retarget_leaves_in_flight_orbs_alone() -> void:
	# An orb is committed once launched. Retargeting redirects the *next* one; the
	# ones already crossing the board keep the path they were given.
	var world := _line_world(10)
	_run(world, _ticks_for_one_delivery(9) - 30)  # orbs mid-flight
	var in_flight := world.in_flight_value()
	var live := world.live_orb_count()
	check(in_flight > 0, "there are orbs in flight when the route changes")

	world.set_target(0, 5)
	check_eq(world.in_flight_value(), in_flight, "not a point of it was destroyed")
	check_eq(world.live_orb_count(), live, "and every orb is still flying")
	check(world.ledger_balanced(), "ledger balanced after the retarget")


func test_an_orb_outlives_the_route_that_launched_it() -> void:
	# The orb finishes the journey it set out on, at the old destination, and
	# arrives with exactly what the original path predicts — so retargeting moved
	# nothing about it, not even its value.
	var world := _one_orb_world(6)
	var original := world.resolve_route(0, 5, PackedInt32Array())
	check(world.emit_orb(0, 5, Tiers.RED, PackedInt32Array()), "an orb sets out for cell 5")
	_run(world, 2 * World.TICKS_PER_HOP)

	# Retarget the source somewhere else entirely, mid-flight.
	_place(world, 0, BlockCatalog.GENERATOR)
	check(world.set_target(0, 3), "the source is re-aimed at cell 3")
	check_eq(world.live_orb_count(), 1, "the orb in flight is untouched")

	_run(world, 4 * World.TICKS_PER_HOP + 2)
	# Read off the old destination's own progress rather than `delivered`, so the
	# re-aimed generator's later orbs — which land on cell 3 — cannot muddy it.
	check_eq(world.graph.get_cell(5).unlock_progress, world.arrival_along(original),
		"it landed at its original destination, worth what that path promised")
	check(world.ledger_balanced(), "ledger balanced")


# --- Tests: idle blocks -------------------------------------------------


func test_unlock_unaims_generators() -> void:
	# A mined cell consumes nothing, so a generator left aiming at one would pour
	# its entire output into waste. Mining releases it instead.
	var graph := MapLoader.line_graph(3)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	graph.get_cell(2).unlock_cost = 8
	var world := World.new(graph)
	check(world.set_target(0, 2), "aimed at cell 2")

	_run(world, _ticks_for_one_delivery(2))
	check(graph.get_cell(2).is_unlocked, "cell 2 was mined")
	check_eq(graph.get_cell(0).block.target_id, -1, "the generator was unaimed")
	check(not graph.get_cell(0).block.has_target(), "so it reads as idle")

	var produced := world.produced
	_run(world, 200)
	check_eq(world.produced, produced, "and emits nothing further")
	check(world.ledger_balanced(), "ledger balanced")


func test_unlock_leaves_orbs_flying_at_that_target() -> void:
	# Mining clears the targets but calls nothing back. Orbs already heading for
	# the cell arrive at a mined one, do nothing, and waste — which is the whole
	# of "an orb is committed once launched", seen from the other end.
	#
	# The ledger check is the real assertion. The orb that completes the unlock is
	# mid-delivery when the cascade runs, and double-counting it there is the
	# obvious way to write this wrong.
	var graph := MapLoader.line_graph(7)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	graph.get_cell(6).unlock_cost = 8
	var world := World.new(graph)
	check(world.set_target(0, 6), "aimed at the far end")

	var ticks := 0
	while not graph.get_cell(6).is_unlocked and ticks < 500:
		world.tick()
		ticks += 1

	check(graph.get_cell(6).is_unlocked, "cell 6 was mined")
	check_eq(graph.get_cell(0).block.target_id, -1, "the generator was unaimed")
	check(world.live_orb_count() > 0, "orbs still in flight were left flying")
	check(world.ledger_balanced(), "ledger balanced — nothing counted twice")

	# Let them arrive. The cell is mined and holds nothing with an intake, so
	# every one of them does nothing and its value wastes.
	var wasted_before := world.wasted
	_run(world, 7 * World.TICKS_PER_HOP + 2)
	check_eq(world.live_orb_count(), 0, "they all landed rather than lingering")
	check(world.wasted > wasted_before, "and their value wasted on arrival")
	check(world.ledger_balanced(), "ledger still balanced once they landed")


func test_an_orb_still_feeds_an_upgrader_mined_under_it() -> void:
	# The intake exception, and the one case where landing on a mined cell is not
	# a waste. A converter has an appetite, so an orb that was already in the air
	# when the converter's own cell finished is banked rather than thrown away —
	# otherwise a player would lose everything on the way at the exact moment the
	# thing they were digging for came online.
	var graph := MapLoader.line_graph(7)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	graph.get_cell(6).initial_block_id = BlockCatalog.UPGRADER
	_discover_line(graph)
	graph.get_cell(6).unlock_cost = 8
	var world := World.new(graph)
	check(world.set_target(0, 6), "aimed at the cell the upgrader is buried in")

	var ticks := 0
	while not graph.get_cell(6).is_unlocked and ticks < 500:
		world.tick()
		ticks += 1
	check(graph.get_cell(6).is_unlocked, "the upgrader's cell was mined")
	check(world.live_orb_count() > 0, "and orbs were still on their way to it")

	var converted_before := world.converted
	_run(world, 7 * World.TICKS_PER_HOP + 2)
	check(world.converted > converted_before,
		"the upgrader banked them instead of wasting them")
	check(graph.get_cell(6).block.charge > 0, "and the charge is really there")
	check(world.ledger_balanced(), "ledger balanced")


func test_cannot_aim_at_mined_cell() -> void:
	# The same rule as above, applied at the other entry point: without it the
	# player can simply re-aim at the cell they have just finished.
	var world := _line_world(6)
	check(world.graph.get_cell(2).is_unlocked, "cell 2 is mined")
	check(not world.set_target(0, 2), "cannot aim at a cell that consumes nothing")
	check_eq(world.graph.get_cell(0).block.target_id, 5, "the existing target survived")


func test_idle_cells_of_lists_unaimed() -> void:
	var graph := MapLoader.line_graph(7)
	for id in [0, 2, 4]:
		graph.get_cell(id).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	var world := World.new(graph)
	_place(world, 5, BlockCatalog.PUMP)

	check_eq(world.idle_cells_of(BlockCatalog.GENERATOR), PackedInt32Array([0, 2, 4]),
		"every unaimed generator is listed, ascending")
	check(world.set_target(2, 6), "aim the middle one")
	check_eq(world.idle_cells_of(BlockCatalog.GENERATOR), PackedInt32Array([0, 4]),
		"an aimed generator is not idle")
	check_eq(world.idle_cells_of(BlockCatalog.PUMP), PackedInt32Array(),
		"a pump takes no target, so it never counts as idle")


func test_next_idle_after_wraps() -> void:
	var graph := MapLoader.line_graph(7)
	for id in [0, 2, 4]:
		graph.get_cell(id).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	var world := World.new(graph)

	check_eq(world.next_idle_after(BlockCatalog.GENERATOR, -1), 0, "starts at the first")
	check_eq(world.next_idle_after(BlockCatalog.GENERATOR, 0), 2, "then the next")
	check_eq(world.next_idle_after(BlockCatalog.GENERATOR, 2), 4, "and the next")
	check_eq(world.next_idle_after(BlockCatalog.GENERATOR, 4), 0, "then wraps to the first")
	# The cursor can point at a cell that stopped being idle between clicks.
	check_eq(world.next_idle_after(BlockCatalog.GENERATOR, 1), 2, "a stale cursor still advances")


func test_next_idle_after_empty() -> void:
	var world := _line_world(6)  # its one generator is aimed at the far end
	check_eq(world.idle_cells_of(BlockCatalog.GENERATOR), PackedInt32Array(),
		"the only generator is aimed")
	check_eq(world.next_idle_after(BlockCatalog.GENERATOR, -1), -1, "nothing to jump to")
	check_eq(world.next_idle_after(BlockCatalog.PUMP, -1), -1, "and no pump ever idles")


# --- Tests: mining and swapping -----------------------------------------


func test_unlock_installs_map_block() -> void:
	# Mining a cell yields whatever the map buried in it — the only way a block
	# ever comes into existence.
	var graph := MapLoader.line_graph(3)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
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
	_discover_line(graph)
	graph.get_cell(2).unlock_cost = 8
	var world := World.new(graph)
	world.set_target(0, 2)

	_run(world, _ticks_for_one_delivery(2))
	check(graph.get_cell(2).is_unlocked, "cell 2 was mined")
	check_eq(graph.get_cell(2).block, null, "an empty cell mines to an empty cell")
	# It can still receive a swap — from a movable block. Not from cell 0's
	# generator, which is anchored.
	_place(world, 1, BlockCatalog.PUMP)
	check(world.can_swap(1, 2), "but it can still receive a swap")
	check(not world.can_swap(0, 2), "though not the anchored generator")


func test_swap_exchanges_blocks() -> void:
	# Two movable blocks trade places. Cell 0's generator is anchored, so the
	# pumps do the moving.
	var world := _line_world(8)
	_place(world, 3, BlockCatalog.PUMP)
	world.graph.unlock_cell(5)

	check(world.swap_blocks(3, 5), "swap accepted")
	check_eq(world.graph.get_cell(3).block, null, "cell 3 gave up its pump")
	check_eq(world.graph.get_cell(5).block.def.id, BlockCatalog.PUMP, "cell 5 now holds it")


func test_swap_into_empty_is_a_move() -> void:
	var world := _line_world(8)
	_place(world, 3, BlockCatalog.PUMP)
	var destination := world.graph.get_cell(5)
	world.graph.unlock_cell(5)
	check_eq(destination.block, null, "destination starts empty")

	check(world.swap_blocks(3, 5), "swap accepted")
	check_eq(world.graph.get_cell(3).block, null, "source is now empty")
	check_eq(destination.block.def.id, BlockCatalog.PUMP, "block moved across")


func test_swap_rejects_locked_cells() -> void:
	var world := _line_world(8)
	_place(world, 3, BlockCatalog.PUMP)
	check(not world.can_swap(3, 7), "cell 7 has not been mined")
	check(not world.swap_blocks(3, 7), "swap refused")
	check_eq(world.graph.get_cell(3).block.def.id, BlockCatalog.PUMP, "source untouched")
	check_eq(world.graph.get_cell(7).block, null, "destination untouched")

	# Two empty mined cells have nothing to trade.
	world.graph.unlock_cell(5)
	world.graph.unlock_cell(7)
	check(not world.can_swap(5, 7), "two empty cells is a no-op, not a move")
	check(not world.can_swap(3, 3), "a cell cannot swap with itself")


func test_generator_cannot_be_swapped() -> void:
	# Generators are anchored where the map buried them. Swapping is free,
	# instant and unlimited in range, so a movable generator could always be
	# parked one hop from the frontier and every delivery would land at 9 of 10.
	# The refusal has to hold from both sides: a generator can be neither picked
	# up nor displaced by something arriving.
	var world := _line_world(8)
	_place(world, 3, BlockCatalog.PUMP)
	world.graph.unlock_cell(5)

	check(not world.can_swap(0, 3), "a generator cannot be traded for a pump")
	check(not world.can_swap(3, 0), "and the refusal is symmetric")
	check(not world.can_swap(0, 5), "nor moved into an empty mined cell")
	check(not world.swap_blocks(0, 3), "swap_blocks refuses it too")

	check_eq(world.graph.get_cell(0).block.def.id, BlockCatalog.GENERATOR, "generator stayed put")
	check_eq(world.graph.get_cell(3).block.def.id, BlockCatalog.PUMP, "and the pump did too")


func test_swap_leaves_generator_orbs_alone() -> void:
	# swap_blocks cancels orbs launched from either end, but no orb can be
	# launched from a cell a swap is allowed to touch: the generator is the only
	# block that emits, and it is anchored. Moving a pump under a live route
	# must therefore leave the traffic flying.
	var world := _line_world(10)
	_place(world, 4, BlockCatalog.PUMP)
	world.graph.unlock_cell(6)
	_run(world, _ticks_for_one_delivery(9) - 30)
	var in_flight := world.in_flight_value()
	check(in_flight > 0, "there are orbs in flight")

	check(world.swap_blocks(4, 6), "the pump moved")
	check_eq(world.in_flight_value(), in_flight, "every orb survived the swap")
	check(world.ledger_balanced(), "ledger balanced after swap")


func test_swapped_pump_relays_from_new_cell() -> void:
	# A pump acts on the cell it currently occupies, not the one it was buried
	# in. Moved from hop 8 — too far out to help — to hop 3, it starts relaying.
	var world := _one_orb_world(13)
	_place(world, 8, BlockCatalog.PUMP)
	world.graph.unlock_cell(3)
	check(world.swap_blocks(8, 3), "pump moved to hop 3")
	check_eq(world.graph.get_cell(3).block.def.id, BlockCatalog.PUMP, "it landed there")
	check_eq(world.graph.get_cell(8).block, null, "and left nothing behind")

	_launch_one(world, 0, 12)
	check_eq(world.restored, _pump_restore(), "the pump fired from its new cell")
	check_eq(world.delivered, 1, "10 - 11 crossed cells + 2 = 1")
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


## The "on screen" half of the double-click group. Pinned here rather than left
## in `Main` because this is the one piece of input the suite can drive, and the
## rect is the only new geometry in the feature.
func test_camera_visible_world_rect_tracks_pan_and_zoom() -> void:
	var camera = _camera()
	var viewport: Vector2 = camera.get_viewport_rect().size

	# At zoom 1 the rect is the viewport, centred on the camera.
	var rect: Rect2 = camera.visible_world_rect()
	check_eq(rect.size, viewport, "one world unit per pixel at zoom 1")
	check(rect.get_center().distance_to(camera.global_position) < 0.01,
		"centred on the camera (%s)" % rect.get_center())

	# Panning translates it and nothing else.
	camera.position = Vector2(500, -250)
	var moved: Rect2 = camera.visible_world_rect()
	check_eq(moved.size, rect.size, "panning does not resize the view")
	check(moved.get_center().distance_to(Vector2(500, -250)) < 0.01,
		"it followed the camera (%s)" % moved.get_center())

	# Zooming out shows more board, in exact proportion. This is the direction
	# that matters: a player zooms out to gather a colour's generators into one
	# group, so the rect has to grow with the view rather than stay pinned.
	camera.zoom = Vector2(0.5, 0.5)
	var wide: Rect2 = camera.visible_world_rect()
	check_eq(wide.size, viewport / 0.5, "half the zoom shows twice the board")
	check(wide.get_center().distance_to(moved.get_center()) < 0.01,
		"about the same centre (%s)" % wide.get_center())

	camera.queue_free()


# --- Tests: the orb weave -----------------------------------------------
#
# Orbs are drawn off the straight edge line, on a lateral sine, so that several
# generators feeding one corridor read as separate strands instead of stacking
# into a single dot. Presentation only — the economy never sees it — but two of
# the three properties below are load-bearing enough to pin.


## Untyped for the same reason `_camera()` is: the script's own `_weave_offset`
## and `_lane_of` are invisible to the static Node2D type.
func _orb_layer():
	return load("res://scenes/view/OrbLayer.gd").new()


func _weaving_orb(source_id: int, hop_index: int):
	var orb := Orb.new()
	orb.source_id = source_id
	orb.hop_index = hop_index
	return orb


func test_orb_weave_vanishes_at_cell_centres() -> void:
	# The property the whole scheme rests on. The perpendicular flips wherever a
	# route turns a corner, so if the offset were not exactly zero as an orb
	# touches a cell, every turn would jump it sideways — and an orb would not
	# land on the cell it delivers into.
	var layer = _orb_layer()
	var lane: float = layer._lane_of(7)
	check(lane != 0.0, "the orb under test is actually on an offset lane")

	var from := Vector2(0, 0)
	var to := Vector2(190, 0)
	for hop in 4:
		var orb = _weaving_orb(7, hop)
		var entry: Vector2 = layer._weave_offset(orb, from, to, 0.0)
		var exit: Vector2 = layer._weave_offset(orb, from, to, 1.0)
		check(entry.length() < 0.001, "hop %d: zero offset entering the cell" % hop)
		check(exit.length() < 0.001, "hop %d: zero offset leaving the cell" % hop)
	layer.free()


func test_orb_weave_alternates_side_each_hop() -> void:
	# What makes a route read as a snake rather than as the same bulge repeated.
	var layer = _orb_layer()
	var from := Vector2(0, 0)
	var to := Vector2(190, 0)

	var previous := 0.0
	for hop in 5:
		var orb = _weaving_orb(7, hop)
		var mid: Vector2 = layer._weave_offset(orb, from, to, 0.5)
		check(mid.length() > 0.001, "hop %d: the orb actually left the line" % hop)
		if hop > 0:
			check(signf(mid.y) != signf(previous), "hop %d swung to the other side" % hop)
		previous = mid.y
	layer.free()


func test_orb_weave_gives_each_source_its_own_lane() -> void:
	# The reason the feature exists: two generators feeding one corridor must not
	# be drawn on top of each other. Lanes are handed out first-come, so as many
	# distinct sources as there are lanes get distinct lanes — no id arithmetic,
	# which would collide in clumps because cell ids are assigned row-major.
	var layer = _orb_layer()
	var seen := {}
	for source_id in [4, 11, 43, 52, 53]:
		var lane: float = layer._lane_of(source_id)
		check(not seen.has(lane), "source %d got an unused lane" % source_id)
		seen[lane] = true
		check(absf(lane) <= 1.0, "source %d stays within the amplitude" % source_id)
		# No lane may be zero, or that source's orbs would not weave at all.
		check(lane != 0.0, "source %d actually weaves" % source_id)

	# And a source keeps its lane, or an orb would change strand mid-flight.
	check_eq(layer._lane_of(11), layer._lane_of(11), "a source's lane is stable")
	layer.free()


# --- Tests: the delivery splash (presentation only) ----------------------
#
# The burst a delivery leaves at the cell that absorbed it. Presentation only —
# the simulation never sees it, and the layer is fed from the same drained
# delivery events the floating numbers come from. What is pinned here is the
# geometry, which is static and pure for exactly this reason, and the two bounds
# that stop a busy board from growing an unbounded array.


func _splash_layer() -> Node2D:
	var layer: Node2D = load("res://scenes/view/SplashLayer.gd").new()
	return layer


func test_splash_shards_fan_evenly() -> void:
	var view = load("res://scenes/view/SplashLayer.gd")
	var seen: Array[float] = []
	for i in view.SHARDS:
		var offset: Vector2 = view.shard_offset(i, 0.0, 1.0, 1.0)
		check(offset.length() > 0.0, "shard %d actually travels" % i)
		# Distinct directions: two shards on one bearing would read as one.
		var angle := offset.angle()
		for other in seen:
			check(absf(angle - other) > 0.01, "shard %d has its own bearing" % i)
		seen.append(angle)

	# The fan is a whole ring rather than a cone, so a burst reads the same
	# whichever way the orb came in — there is no arrival direction on the board.
	var first: Vector2 = view.shard_offset(0, 0.0, 1.0, 1.0)
	var opposite: Vector2 = view.shard_offset(view.SHARDS / 2, 0.0, 1.0, 1.0)
	check(first.normalized().dot(opposite.normalized()) < 0.0,
		"shards go opposite ways round the ring")

	# Rotating the base angle rotates the whole figure and nothing else. This is
	# the one thing the per-splash randf() does, so it is worth pinning that it
	# cannot change the shape.
	var turned: Vector2 = view.shard_offset(0, PI * 0.5, 1.0, 1.0)
	check(absf(turned.length() - first.length()) < 0.001,
		"a rotated shard travels the same distance")


func test_splash_expands_and_fades() -> void:
	var view = load("res://scenes/view/SplashLayer.gd")

	# Both halves of the figure move outward together, and neither ever doubles
	# back — a shard that retreated would read as being sucked in.
	var last_ring: float = view.ring_radius(0.0, 1.0)
	var last_shard: float = view.shard_offset(0, 0.0, 0.0, 1.0).length()
	for step in range(1, 11):
		var k := float(step) / 10.0
		var ring: float = view.ring_radius(k, 1.0)
		var shard: float = view.shard_offset(0, 0.0, k, 1.0).length()
		check(ring >= last_ring, "the ring never shrinks (k=%.1f)" % k)
		check(shard >= last_shard, "a shard never retreats (k=%.1f)" % k)
		last_ring = ring
		last_shard = shard

	check(last_ring > view.ring_radius(0.0, 1.0), "the ring actually expands")

	# Opaque while it is being read, gone by the end. Fading from birth reads as
	# a glitch rather than an impact, which is what HOLD is for.
	check_eq(view.fade(0.0), 1.0, "full opacity at birth")
	check_eq(view.fade(view.HOLD * 0.5), 1.0, "still full inside the hold")
	check_eq(view.fade(1.0), 0.0, "gone at the end of its life")
	check(view.fade(0.75) < view.fade(view.HOLD), "and fades monotonically between")

	# Strength scales the figure without changing its shape.
	check(view.ring_radius(1.0, 1.5) > view.ring_radius(1.0, 1.0),
		"a bigger delivery throws a bigger ring")
	check(view.shard_offset(0, 0.0, 1.0, 1.5).length()
		> view.shard_offset(0, 0.0, 1.0, 1.0).length(),
		"and bigger shards")


func test_splash_drops_expired() -> void:
	var layer := _splash_layer()

	layer.spawn(Vector2.ZERO, Color.RED)
	check_eq(layer.live_count(), 1, "a splash is in the air")

	layer.advance(layer.LIFETIME * 0.5)
	check_eq(layer.live_count(), 1, "still alive halfway through")

	layer.advance(layer.LIFETIME)
	check_eq(layer.live_count(), 0, "and gone past its lifetime")

	# Back-dating past the lifetime is refused rather than shown late. A frame
	# that catches many ticks up hands over a whole batch at once, and the oldest
	# of them describe something that already finished happening.
	layer.spawn(Vector2.ZERO, Color.RED, 1.0, layer.LIFETIME)
	check_eq(layer.live_count(), 0, "an already-expired splash is never born")

	layer.free()


func test_splash_respects_max_live() -> void:
	var layer := _splash_layer()

	# At 16x a single frame can drain dozens of deliveries, and a splash costs
	# more to draw than a number does. The cap has to degrade into dropped
	# bursts — invisible on a board that busy — rather than into an array that
	# grows for as long as the game runs.
	for i in layer.MAX_LIVE + 50:
		layer.spawn(Vector2(i, 0), Color.RED)
	check_eq(layer.live_count(), layer.MAX_LIVE, "the cap holds")

	# And it recovers: once the burst has aged out, new ones are taken again.
	layer.advance(layer.LIFETIME)
	check_eq(layer.live_count(), 0, "all expired together")
	layer.spawn(Vector2.ZERO, Color.RED)
	check_eq(layer.live_count(), 1, "and the layer accepts work again")

	layer.free()


func test_splash_strength_is_clamped() -> void:
	var view = load("res://scenes/view/SplashLayer.gd")
	# `Main` divides the delivered amount by an orb's launch value, which is
	# unbounded on both sides: a 1-value trickle into an almost-finished cell,
	# or a heavily pumped orb landing whole. Neither may reach the drawing.
	check(view.MIN_STRENGTH > 0.0, "a trickle still leaves a visible mark")
	check(view.MAX_STRENGTH < 2.0,
		"and a fat delivery does not throw shards onto the neighbouring cells")

	var layer := _splash_layer()
	layer.spawn(Vector2.ZERO, Color.RED, 0.0)
	layer.spawn(Vector2.ZERO, Color.RED, 99.0)
	check_eq(layer.live_count(), 2, "both were accepted, clamped rather than refused")
	layer.free()


# --- Tests: pathing -----------------------------------------------------


func test_path_determinism() -> void:
	# Two independent loads of the same map must route identically. Checked in two
	# passes, and the split is what keeps it affordable on a 950-cell board.
	#
	# The **mechanism** is checked exhaustively: routing is a BFS whose only
	# ordering input is `neighbor_ids`, so if those match cell for cell after
	# `finalize()`, every route on the two graphs matches by construction. That is
	# O(V) and total.
	#
	# The **behaviour** is then checked on a strided sample of pairs rather than
	# all of them. All-pairs used to be the whole test, and it was Θ(V³) in node
	# visits — V² pairs, each a fresh BFS, because `find_path_unrestricted` is
	# uncached. At 230 cells that was seconds; at 950 it was eight minutes, and it
	# passed the entire time, which is the worst way for a suite to rot. A sample
	# loses nothing real here: unstable neighbour ordering would not perturb one
	# route in a thousand, it would perturb nearly all of them, so a couple of
	# thousand pairs spread across the board catches it on the first one. The
	# stride is fixed, not random — a determinism test that samples randomly is a
	# determinism test that fails intermittently.
	var a := MapLoader.load_from_file("res://data/map_01.json")
	var b := MapLoader.load_from_file("res://data/map_01.json")
	check(a != null and b != null, "map loaded")
	if a == null or b == null:
		return

	check_eq(a.cell_ids, b.cell_ids, "the two loads agree on which cells exist")
	for id in a.cell_ids:
		if a.get_cell(id).neighbor_ids != b.get_cell(id).neighbor_ids:
			_fail("cell %d's neighbours differ between loads" % id)
			return

	const STRIDE := 23
	var sample: Array[int] = []
	for i in range(0, a.cell_ids.size(), STRIDE):
		sample.append(a.cell_ids[i])
	check(sample.size() > 20, "the sample spans the board")

	for from_id in sample:
		for to_id in sample:
			if a.find_path_unrestricted(from_id, to_id) \
					!= b.find_path_unrestricted(from_id, to_id):
				_fail("path %d->%d differs between loads" % [from_id, to_id])
				return
			if a.find_path(from_id, to_id) != b.find_path(from_id, to_id):
				_fail("discovered path %d->%d differs between loads" % [from_id, to_id])
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
	# Mining the two ends discovers all four, so this exercises the restricted
	# BFS the game actually routes on. The discovery filter removes candidates
	# but never reorders them, so the tie-break must be untouched.
	graph.unlock_cell(0)
	graph.unlock_cell(3)

	check_eq(graph.find_path(0, 3), PackedInt32Array([0, 1, 3]), "route through lowest id")
	check_eq(graph.distance(0, 3), 2, "two hops")


# --- Tests: waypoints ---------------------------------------------------
#
# A waypoint is a constraint on a route, not a stored path. These pin the three
# things that follow from that: the route really does bend, it costs the extra
# hops, and it re-resolves as the fog lifts rather than staying frozen.


## A diamond: 0 -> {1, 2} -> 3. The shortest route takes the lowest-id
## neighbour, so cell 2 is only ever reached by asking for it.
##
## Cells 0-2 are mined so blocks can stand on them; cell 3 is left locked and
## expensive, because it is the destination — an orb delivered into a *mined*
## cell with no intake is wasted rather than counted, and every arrival test here
## wants to read `delivered`.
func _diamond_graph() -> Graph:
	var graph := Graph.new()
	for i in 4:
		var cell := GraphCell.new()
		cell.id = i
		cell.position = Vector2(i * 100.0, 0.0)
		cell.unlock_cost = 1000000
		graph.add_cell(cell)
	graph.get_cell(0).neighbor_ids = PackedInt32Array([1, 2])
	graph.get_cell(1).neighbor_ids = PackedInt32Array([0, 3])
	graph.get_cell(2).neighbor_ids = PackedInt32Array([0, 3])
	graph.get_cell(3).neighbor_ids = PackedInt32Array([1, 2])
	graph.finalize()
	for i in 3:
		graph.unlock_cell(i)
	return graph


func test_waypoint_route_bends_through_the_via() -> void:
	var graph := _diamond_graph()
	check_eq(graph.find_path(0, 3), PackedInt32Array([0, 1, 3]),
		"left alone, the route takes the lowest-id neighbour")
	check_eq(graph.find_path_via(0, PackedInt32Array([2]), 3), PackedInt32Array([0, 2, 3]),
		"a waypoint on cell 2 bends it the other way round")
	check_eq(graph.find_path_via(0, PackedInt32Array(), 3), PackedInt32Array([0, 1, 3]),
		"and an empty via is exactly the shortest path")


func test_waypoint_legs_join_without_repeating_the_seam() -> void:
	# Two legs meeting at cell 2 must produce one cell 2, not two. A doubled seam
	# would be a zero-length hop the orb spends a full TICKS_PER_HOP crossing.
	var graph := MapLoader.line_graph(6)
	for id in graph.cell_ids:
		graph.unlock_cell(id)
	check_eq(graph.find_path_via(0, PackedInt32Array([2]), 4),
		PackedInt32Array([0, 1, 2, 3, 4]), "the seam appears once")
	# A route is a simple path. Folding back would collect every pump on the way
	# out a second time on the way home, and each lap books under `restored`, so
	# the ledger could never catch it. Refused instead of charged for.
	check_eq(graph.find_path_via(0, PackedInt32Array([4]), 2), PackedInt32Array(),
		"a fold-back is refused rather than doubling back")
	check(graph.legs_routable(0, PackedInt32Array([4, 2])),
		"and it is refused for crossing itself, not for an unroutable leg")


func test_waypoint_route_is_empty_when_a_leg_is_unroutable() -> void:
	# A loop with one corner left fogged: 0-4-3 is the shortcut, 0-1-2-3 the long
	# way. Mining 1 and 2 discovers both ends and leaves cell 4 dark.
	var graph := Graph.new()
	for i in 5:
		var cell := GraphCell.new()
		cell.id = i
		graph.add_cell(cell)
	graph.get_cell(0).neighbor_ids = PackedInt32Array([1, 4])
	graph.get_cell(1).neighbor_ids = PackedInt32Array([0, 2])
	graph.get_cell(2).neighbor_ids = PackedInt32Array([1, 3])
	graph.get_cell(3).neighbor_ids = PackedInt32Array([2, 4])
	graph.get_cell(4).neighbor_ids = PackedInt32Array([0, 3])
	graph.finalize()
	graph.unlock_cell(1)
	graph.unlock_cell(2)

	check(not graph.is_discovered(4), "cell 4 is still dark")
	check(graph.find_path(0, 3).size() >= 2, "cell 3 is reachable the long way")
	check_eq(graph.find_path_via(0, PackedInt32Array([4]), 3), PackedInt32Array(),
		"but routing through the dark is refused, so the whole route is empty")


func test_waypoints_are_normalized_and_capped() -> void:
	# Spellings that mean the same route must collapse to the same list, or
	# set_target's early-out reads a no-op as a change and cancels in flight.
	check_eq(World.normalize_via(0, 5, PackedInt32Array([0, 1, 1, 2, 5])),
		PackedInt32Array([1, 2]),
		"the source, a consecutive repeat and a trailing target all drop out")
	check_eq(World.normalize_via(0, 9, PackedInt32Array([1, 2, 3, 4, 5, 6])),
		PackedInt32Array([1, 2, 3, 4]),
		"and the list is capped at MAX_WAYPOINTS")
	# A non-consecutive repeat survives normalising, because this is syntactic
	# tidy-up and not a legality check — the route it describes is then refused by
	# the router. Dropping it here instead would silently rewrite the player's
	# route into a different one that happens to be legal.
	check_eq(World.normalize_via(0, 5, PackedInt32Array([1, 2, 1])),
		PackedInt32Array([1, 2, 1]), "a non-consecutive repeat survives normalising")
	var graph := MapLoader.line_graph(6)
	for id in graph.cell_ids:
		graph.unlock_cell(id)
	check_eq(graph.find_path_via(0, PackedInt32Array([1, 2, 1]), 5),
		PackedInt32Array(), "and the route it names is refused for crossing itself")


func test_waypoint_route_costs_the_extra_hops() -> void:
	# The bent route is longer, so it arrives with less, and the preview agrees
	# with the delivery exactly.
	var graph := _diamond_graph()
	var world := World.new(graph)

	var direct := world.resolve_route(0, 3, PackedInt32Array())
	var bent := world.resolve_route(0, 3, PackedInt32Array([2]))
	check_eq(direct.size(), bent.size(), "on a diamond both ways round are 2 hops")

	world.emit_orb(0, 3, Tiers.RED, PackedInt32Array([2]))
	_run(world, 2 * World.TICKS_PER_HOP + 2)
	check_eq(world.delivered, world.arrival_along(bent),
		"the delivery matches what the preview promised for that exact route")
	check(world.ledger_balanced(), "ledger balanced")


func test_waypoint_route_reaches_a_pump_it_would_otherwise_miss() -> void:
	# The whole point of the feature. The shortest route passes an empty cell;
	# bending it through the pump is worth a pump's restore for no extra hops.
	var graph := _diamond_graph()
	var world := World.new(graph)
	_place(world, 2, BlockCatalog.PUMP)

	world.emit_orb(0, 3, Tiers.RED, PackedInt32Array())
	_run(world, 2 * World.TICKS_PER_HOP + 2)
	var straight := world.delivered
	check_eq(world.restored, 0, "the shortest way round misses the pump entirely")

	var bent_world := World.new(_diamond_graph())
	_place(bent_world, 2, BlockCatalog.PUMP)
	bent_world.emit_orb(0, 3, Tiers.RED, PackedInt32Array([2]))
	_run(bent_world, 2 * World.TICKS_PER_HOP + 2)
	check_eq(bent_world.restored, _pump_restore(), "bent through it, the pump fires")
	check_eq(bent_world.delivered, straight + _pump_restore(),
		"and the orb lands worth a pump's restore more")
	check(bent_world.ledger_balanced(), "ledger balanced")


func test_a_route_that_crosses_its_own_destination_is_refused() -> void:
	# A waypoint out past the destination used to bend the route back over it,
	# which is what forced the destination guard in transport to be stated about
	# the *cell* rather than about `is_at_end()`. A route is a simple path now, so
	# the whole shape is refused up front instead.
	#
	# The guard in `_phase_transport` stays, dormant rather than dead — the same
	# reason the wrong-colour delivery branch stays. The ledger's correctness must
	# not rest on a guarantee made two calls away.
	var world := _one_orb_world(7)
	_place(world, 2, BlockCatalog.PUMP)

	check(world.graph.legs_routable(0, PackedInt32Array([5, 2])),
		"both legs route on their own")
	check_eq(world.resolve_route(0, 2, PackedInt32Array([5])), PackedInt32Array(),
		"but the walk would cross cell 2 twice, so there is no route")
	check(not world.can_aim_at(0, 2, PackedInt32Array([5])),
		"aiming along it is refused")
	check(not world.emit_orb(0, 2, Tiers.RED, PackedInt32Array([5])),
		"and nothing is emitted down a route that does not exist")
	check_eq(world.produced, 0, "so no value entered the economy")
	check(world.ledger_balanced(), "ledger balanced")


func test_a_route_that_crosses_itself_is_refused() -> void:
	# The rule in its plainest form. A waypoint behind the source sends the route
	# back over ground it has already covered, collecting every pump on it twice —
	# and each lap books legitimately under `restored`, so the ledger could never
	# catch it. Refused at the router, which is the one place it is decided.
	var graph := MapLoader.line_graph(8)
	for id in graph.cell_ids:
		graph.unlock_cell(id)
	graph.get_cell(6).is_unlocked = false
	var world := World.new(graph)
	_place(world, 2, BlockCatalog.GENERATOR)

	check(graph.find_path(2, 6).size() >= 2, "cell 6 routes on its own")
	check(graph.find_path(0, 6).size() >= 2, "and so does the leg back out to it")
	check_eq(world.resolve_route(2, 6, PackedInt32Array([0])), PackedInt32Array(),
		"but going back to cell 0 first would recross 1 and 2, so there is no route")
	check(not world.can_aim_at(2, 6, PackedInt32Array([0])),
		"can_aim_at refuses it")
	check(not world.set_target(2, 6, PackedInt32Array([0])),
		"and so does set_target")
	check(not world.graph.get_cell(2).block.has_target(),
		"the block is left unaimed rather than half-aimed")

	# The same destination without the crossing waypoint is fine, so it is the
	# overlap being refused and not the target.
	check(world.set_target(2, 6), "the direct route to the same cell is allowed")


func test_can_route_through_refuses_a_crossing() -> void:
	# The view refuses a waypoint as it is clicked rather than at commit time, and
	# it has to reach the same verdict `set_target` will — a second copy of the
	# rules here is how the board ends up offering a route the simulation refuses.
	var graph := MapLoader.line_graph(8)
	for id in graph.cell_ids:
		graph.unlock_cell(id)
	var world := World.new(graph)

	check(world.can_route_through(2, PackedInt32Array()),
		"an empty chain is trivially fine")
	check(world.can_route_through(2, PackedInt32Array([4])),
		"and so is a single reachable stop")
	check(world.can_route_through(2, PackedInt32Array([4, 6])),
		"as is a chain that keeps going the same way")
	check(not world.can_route_through(2, PackedInt32Array([4, 0])),
		"but doubling back over the first leg is refused")


## The chain the right-click flow builds: every shift-click extends the route,
## and the block re-aims at each new cell that can legally take an orb. Pinned at
## the `World` level, which is the contract — `Main`'s input has no headless
## coverage and this is what it calls.
##
## The same argument covers the group commands below. `Main` cannot be driven
## headlessly, so the double-click's *logic* was pushed down here where it can be
## — the rect query, the batch aim and the group's routing gate — leaving `Main`
## a thin caller. The one part that could not come down here is the visible-rect
## geometry, and that went to the camera, which does have coverage.
func test_a_chain_aims_as_it_is_drawn() -> void:
	var graph := MapLoader.line_graph(8)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 1000000
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
	graph.unlock_cell(0)
	var world := World.new(graph)
	var block := graph.get_cell(0).block

	# First shift-click: cell 3 is locked and takes red, so it becomes the target
	# outright. The trailing entry naming the target normalises away, leaving no
	# waypoints at all.
	check(world.set_target(0, 3, PackedInt32Array([3])), "the first stop is aimed at")
	check_eq(block.target_id, 3, "it is the destination")
	check(not block.has_waypoints(), "and it is not also a waypoint")

	# Second shift-click: cell 5 takes over as the destination and cell 3 drops
	# back to being somewhere the orb passes through.
	check(world.set_target(0, 5, PackedInt32Array([3, 5])), "the next stop takes over")
	check_eq(block.target_id, 5, "the destination moved on")
	check_eq(block.route_via, PackedInt32Array([3]), "and the old one is now a waypoint")
	check_eq(world.block_route(0), PackedInt32Array([0, 1, 2, 3, 4, 5]),
		"the resolved route runs through both")

	# A stop that cannot take an orb is refused and changes nothing — in the view
	# it stays a pending waypoint with the previous target untouched.
	graph.unlock_cell(7)
	check(not world.set_target(0, 7, PackedInt32Array([3, 5, 7])),
		"a mined cell with no intake is not a destination")
	check_eq(block.target_id, 5, "so the block is still aimed where it was")


# --- Tests: selecting and aiming a group --------------------------------


## A line of 10 with sources on cells 0 and 6, mirroring what a double-click
## hands the batch: two blocks of one type, far enough apart that a shared
## waypoint chain is walkable from one and doubles back from the other.
##
## Mined: 0,1,2,3,5,6,7. Locked but discovered: 4 and 8, so there are two legal
## red destinations to tell apart. Cell 9 is left **undiscovered** — cell 8 is
## never mined — so it is the chain nobody can route through.
func _group_world() -> World:
	var graph := MapLoader.line_graph(10)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 1000000
	for id in [0, 1, 2, 3, 5, 6, 7]:
		graph.unlock_cell(id)
	var world := World.new(graph)
	_place(world, 0, BlockCatalog.GENERATOR)
	_place(world, 6, BlockCatalog.GENERATOR)
	return world


func test_cells_with_def_in_rect_finds_the_same_type() -> void:
	# `line_graph` spaces cells 100 apart along y=0, so the rect below spans
	# x 150..650 and catches cells 2, 4 and 6 exactly.
	var world := _line_world(10)
	for id in [2, 4, 6]:
		_place(world, id, BlockCatalog.PUMP)
	_place(world, 8, BlockCatalog.SPHERE)
	var area := Rect2(Vector2(150, -50), Vector2(500, 100))

	check_eq(world.cells_with_def_in_rect(BlockCatalog.PUMP, area),
		PackedInt32Array([2, 4, 6]),
		"the pumps inside the rect, and only those")
	check_eq(world.cells_with_def_in_rect(BlockCatalog.SPHERE, area),
		PackedInt32Array(),
		"the sphere is in range of nothing — it is the wrong type, not far away")
	check_eq(world.cells_with_def_in_rect(BlockCatalog.SPHERE,
			Rect2(Vector2(-50, -50), Vector2(1000, 100))),
		PackedInt32Array([8]),
		"and a rect wide enough does find it")

	# The geometry bites as well as the type: a rect stopping short of cell 6
	# drops it and keeps the rest.
	check_eq(world.cells_with_def_in_rect(BlockCatalog.PUMP,
			Rect2(Vector2(150, -50), Vector2(350, 100))),
		PackedInt32Array([2, 4]),
		"a narrower rect excludes the pump outside it")


func test_cells_with_def_in_rect_distinguishes_tiers() -> void:
	# The feature's whole semantic: "all the same-tier generators" is "all the
	# blocks sharing a def id", because the catalog registers one generator def
	# per tier. If these two ever answered the same query, a double-click would
	# rope in every colour on screen.
	var world := _line_world(6)
	_place(world, 2, BlockCatalog.generator_id(Tiers.RED))
	_place(world, 4, BlockCatalog.generator_id(Tiers.ORANGE))
	var area := Rect2(Vector2(-50, -50), Vector2(1000, 100))

	check_eq(world.cells_with_def_in_rect(BlockCatalog.generator_id(Tiers.RED), area),
		PackedInt32Array([0, 2]),
		"the red generators — cell 0 is the line's own, cell 2 the one placed")
	check_eq(world.cells_with_def_in_rect(BlockCatalog.generator_id(Tiers.ORANGE), area),
		PackedInt32Array([4]),
		"and the orange one is a different type entirely")


func test_cells_with_def_in_rect_is_ascending() -> void:
	# Reversed the way `test_tick_order_independent` reverses it. A group's
	# primary is its first entry, so a selection that changed which cell that was
	# because of iteration order would be a real bug — and an invisible one.
	var world := _line_world(10)
	for id in [2, 4, 6]:
		_place(world, id, BlockCatalog.PUMP)

	var ids: Array[int] = []
	for id in world.graph.cell_ids:
		ids.append(id)
	ids.reverse()
	world.graph.cell_ids = PackedInt32Array(ids)

	check_eq(world.cells_with_def_in_rect(BlockCatalog.PUMP,
			Rect2(Vector2(-50, -50), Vector2(1000, 100))),
		PackedInt32Array([2, 4, 6]),
		"still ascending with the graph iterated backwards")


func test_batch_aim_applies_to_every_source() -> void:
	var world := _group_world()

	check_eq(world.set_target_batch(PackedInt32Array([0, 6]), 4), 2,
		"both sources took the target")
	check_eq(world.graph.get_cell(0).block.target_id, 4, "the first is aimed")
	check_eq(world.graph.get_cell(6).block.target_id, 4, "and so is the second")


## The partial-success policy, which is the one rule the batch owns.
func test_batch_aim_leaves_a_failed_source_on_its_old_target() -> void:
	var world := _group_world()

	# Cell 6 starts with a route of its own, and the point of the test is that it
	# still has it at the end.
	check(world.set_target(6, 4), "the second source is already working")

	# Aimed at 8 through waypoint 2. From cell 0 that is 0→2→8, a simple path.
	# From cell 6 it is 6→5→4→3→2 and then 2→3→4→5→6→7→8, which re-crosses four
	# cells — refused by the simple-path rule.
	var aimed: int = world.set_target_batch(PackedInt32Array([0, 6]), 8,
		PackedInt32Array([2]))

	check_eq(aimed, 1, "one of the two could take the shared chain")
	check_eq(world.graph.get_cell(0).block.target_id, 8, "the one that could is aimed")
	check_eq(world.graph.get_cell(0).block.route_via, PackedInt32Array([2]),
		"through the waypoint it was given")
	check_eq(world.graph.get_cell(6).block.target_id, 4,
		"and the one that could not still has the target it had")
	check(not world.graph.get_cell(6).block.has_waypoints(),
		"with its old route untouched, not half-rewritten")


func test_batch_aim_counts_a_source_already_on_that_route() -> void:
	# The count is "how many are aimed here now", not "how many changed". Main
	# clears its half-drawn chain on any success, and a group where every source
	# was already aimed correctly must not read as a total failure.
	var world := _group_world()
	check(world.set_target(0, 4), "one source is already aimed there")

	check_eq(world.set_target_batch(PackedInt32Array([0, 6]), 4), 2,
		"both count, including the one that did not have to move")


func test_batch_unaim_clears_every_source() -> void:
	var world := _group_world()
	check_eq(world.set_target_batch(PackedInt32Array([0, 6]), 4), 2, "aimed")

	check_eq(world.set_target_batch(PackedInt32Array([0, 6]), -1), 2,
		"-1 flows through the batch like any other target")
	check(not world.graph.get_cell(0).block.has_target(), "the first is idle")
	check(not world.graph.get_cell(6).block.has_target(), "and so is the second")


func test_count_routable_through_is_the_group_gate() -> void:
	# A shared chain that splits the group is legal to draw — the sources that can
	# walk it get aimed and the rest keep what they had — so the view refuses a
	# corner only when nobody can take it.
	var world := _group_world()
	var splits := PackedInt32Array([2, 8])

	check_eq(world.count_routable_through(PackedInt32Array([0, 6]), splits), 1,
		"cell 0 can walk 0→2→8; cell 6 would double back over its own leg")
	check_eq(world.count_routable_through(PackedInt32Array([0, 6]),
			PackedInt32Array([9])), 0,
		"cell 9 is undiscovered, so nobody can route through it")

	# For a single source this is the old question with the old answer, which is
	# what lets Main run a group and a lone block down one code path.
	for via in [splits, PackedInt32Array([9]), PackedInt32Array([2])]:
		check_eq(world.count_routable_through(PackedInt32Array([6]), via) == 1,
			world.can_route_through(6, via),
			"a group of one agrees with can_route_through")


func test_waypoint_route_reresolves_as_fog_lifts() -> void:
	# The via-list is a constraint, not a frozen path. Uncovering a shortcut on
	# one leg has to shorten the route without anyone invalidating anything.
	#
	# 0-1-2-3 is the long way to cell 3; 0-4-3 is the shortcut. Cell 5 hangs off
	# both 2 and 3 so it stays discoverable while cell 4 is dark.
	var graph := Graph.new()
	for i in 6:
		var cell := GraphCell.new()
		cell.id = i
		cell.unlock_cost = 1000000
		graph.add_cell(cell)
	graph.get_cell(0).neighbor_ids = PackedInt32Array([1, 4])
	graph.get_cell(1).neighbor_ids = PackedInt32Array([0, 2])
	graph.get_cell(2).neighbor_ids = PackedInt32Array([1, 3, 5])
	graph.get_cell(3).neighbor_ids = PackedInt32Array([2, 4, 5])
	graph.get_cell(4).neighbor_ids = PackedInt32Array([0, 3])
	graph.get_cell(5).neighbor_ids = PackedInt32Array([2, 3])
	graph.finalize()
	graph.unlock_cell(1)
	graph.unlock_cell(2)
	var world := World.new(graph)

	check(not graph.is_discovered(4), "the shortcut is dark to begin with")
	var before := world.resolve_route(0, 5, PackedInt32Array([3]))
	check_eq(before, PackedInt32Array([0, 1, 2, 3, 5]), "so the route takes the long way")

	graph.unlock_cell(3)
	check(graph.is_discovered(4), "mining cell 3 uncovers the shortcut")
	var after := world.resolve_route(0, 5, PackedInt32Array([3]))
	check_eq(after, PackedInt32Array([0, 4, 3, 5]),
		"and the same via-list now resolves through it")
	check(after.size() < before.size(), "a route can only ever get shorter")


func test_cannot_aim_through_an_undiscovered_waypoint() -> void:
	# Aiming into the dark is a simulation rule, not a UI one, and it has to hold
	# for a cell the route merely passes through as much as for the destination.
	# On a line, mining 0-2 lights cell 3 and leaves everything past it dark.
	var graph := MapLoader.line_graph(6)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 1000000
	for id in [0, 1, 2]:
		graph.unlock_cell(id)
	var world := World.new(graph)
	_place(world, 0, BlockCatalog.GENERATOR)

	check(graph.is_discovered(3), "cell 3 is lit")
	check(not graph.is_discovered(4), "cell 4 is dark")
	check(world.can_aim_at(0, 3), "cell 3 is a legal target")
	check(not world.can_aim_at(0, 3, PackedInt32Array([4])),
		"but not through a waypoint nobody has uncovered")
	check(not world.set_target(0, 3, PackedInt32Array([4])), "and set_target refuses it")
	check(not world.graph.get_cell(0).block.has_target(), "leaving the block unaimed")


func test_same_target_new_waypoints_keeps_in_flight_orbs() -> void:
	# Rebending a live route is a real change even though the destination did not
	# move, and the early-out has to see that — but it changes only what the
	# *next* orb does. What is already on the old route stays on it.
	var world := World.new(_diamond_graph())
	_place(world, 0, BlockCatalog.GENERATOR)
	check(world.set_target(0, 3), "aimed the direct way")
	_run(world, 25)
	var live := world.live_orb_count()
	var in_flight := world.in_flight_value()
	check(live > 0, "an orb is in flight")

	check(world.set_target(0, 3, PackedInt32Array([2])), "rebent onto the other side")
	check_eq(world.graph.get_cell(0).block.route_via, PackedInt32Array([2]),
		"the block took the new route for its next orb")
	check_eq(world.live_orb_count(), live, "and the orbs on the old one kept flying")
	check_eq(world.in_flight_value(), in_flight, "with their value untouched")

	check(world.set_target(0, 3, PackedInt32Array([2])), "setting the same route again")
	check_eq(world.live_orb_count(), live, "is a no-op and disturbs nothing")
	check(world.ledger_balanced(), "ledger balanced")


func test_locked_cells_are_traversable() -> void:
	# Locked cells cost nothing extra to cross — they simply offer no support.
	# What a cell needs in order to carry an orb is to have been *discovered*,
	# which is a different thing from having been mined.
	var world := _one_orb_world(6)
	for id in [1, 3]:
		check(not world.graph.get_cell(id).is_unlocked, "cell %d is locked" % id)
		check(world.graph.is_discovered(id), "cell %d is discovered anyway" % id)
	_launch_one(world, 0, 5)
	check_eq(world.delivered, 6, "orb crossed the locked cells")


func test_projected_arrival_matches_reality() -> void:
	# The UI preview reimplements the decay walk, so it must agree with the
	# simulation exactly — including past the death range, where it returns 0.
	#
	# Run with and without a sphere on the route. `arrival_along` has to read the
	# *effective* restore, and this is the test that catches it reading the base:
	# without the sphere pass, a preview quoting base amounts would agree with a
	# simulation that also quoted them, and both would be wrong together.
	#
	# The Surge pass is the same argument one level up: `arrival_along` seeds from
	# `effective_orb_value()`, and seeded from the constant it would agree with
	# nothing. It also moves the death range, which is why the hop list runs past
	# where an unaided orb dies.
	for hops in [1, 3, 5, 9, 10, 12, 20]:
		for pumps in [[], [5], [9, 18]]:
			for sphere in [-1, 4]:
				for surge in [-1, 2]:
					var world := _one_orb_world(hops + 1)
					for p in pumps:
						if p < hops:
							_place(world, p, BlockCatalog.PUMP)
					# Never on the source or the destination: a block on the final
					# cell never acts, and the source is not entered at all.
					if sphere > 0 and sphere < hops and not pumps.has(sphere):
						_place(world, sphere, BlockCatalog.SPHERE)
					if surge > 0 and surge < hops and not pumps.has(surge) \
							and surge != sphere:
						_place(world, surge, BlockCatalog.CHALLENGE_SURGE)
					var projected := world.projected_arrival(0, hops)
					_launch_one(world, 0, hops)
					if projected != world.delivered:
						_fail("%d hops, pumps %s, sphere %d, surge %d — projected %d, delivered %d"
							% [hops, pumps, sphere, surge, projected, world.delivered])
						return
					if not world.ledger_balanced():
						_fail("%d hops, pumps %s, sphere %d, surge %d — ledger broke"
							% [hops, pumps, sphere, surge])
						return


# --- Tests: discovery ---------------------------------------------------


func test_fog_hides_undiscovered() -> void:
	# The opening position: one mined generator and its immediate neighbours.
	# Everything else is not merely undrawn, it is unroutable.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return

	var start_id := _shipped_start(graph)
	check(start_id != -1, "the map ships exactly one cell already mined")
	if start_id == -1:
		return
	var start := graph.get_cell(start_id)

	var discovered: Array[int] = []
	for id in graph.cell_ids:
		if graph.is_discovered(id):
			discovered.append(id)

	var expected: Array[int] = [start_id]
	for n in start.neighbor_ids:
		expected.append(n)
	expected.sort()
	check_eq(discovered, expected, "only the start and its neighbours are visible")
	check(discovered.size() < graph.size(), "most of the map is still hidden")


func test_cannot_aim_at_undiscovered() -> void:
	# Enforced in the simulation rather than only in the UI: find_path refuses to
	# route through fog, and set_target rejects anything it cannot route to.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return
	var world := World.new(graph)

	var start := _shipped_start(graph)
	var frontier: int = graph.get_cell(start).neighbor_ids[0]
	check(world.set_target(start, frontier), "a discovered neighbour is a legal target")

	var fogged := -1
	for id in graph.cell_ids:
		if not graph.is_discovered(id):
			fogged = id
			break
	check(fogged != -1, "the map has undiscovered cells to test against")
	check(not world.set_target(start, fogged), "cannot aim into the dark")
	check_eq(graph.get_cell(start).block.target_id, frontier, "the old target survived")
	check_eq(world.projected_arrival(start, fogged), 0, "and nothing could arrive there")


func test_mining_expands_discovery() -> void:
	# Mining is what pushes the frontier outward: the cell's own neighbours
	# become visible, which is the whole discovery loop.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return

	var frontier: int = graph.get_cell(_shipped_start(graph)).neighbor_ids[0]
	var beyond := -1
	for n in graph.get_cell(frontier).neighbor_ids:
		if not graph.is_discovered(n):
			beyond = n
			break
	check(beyond != -1, "the frontier cell has something hidden behind it")
	if beyond == -1:
		return

	graph.unlock_cell(frontier)
	check(graph.is_discovered(beyond), "mining uncovered what lay beyond")
	check(not graph.get_cell(beyond).is_unlocked, "but did not mine it")


func test_routes_stay_inside_discovered() -> void:
	# The reason fog cannot just be a drawing filter: where the true shortest
	# path runs through cells the player has never seen, routing has to take the
	# long way round instead.
	#
	# Built on a synthetic graph rather than the shipped map. On a hex lattice
	# the discovered region is fat enough that the restricted and unrestricted
	# routes almost always coincide, so a map-based version of this test would
	# assert a detour that the board does not reliably produce — and would start
	# passing or failing on map regeneration rather than on the rule it guards.
	#
	# A loop with a short side and a long one: 0-4-3 is two hops, 0-1-2-3 is
	# three. Mining 1 and 2 discovers both ends while leaving the shortcut at
	# cell 4 fogged.
	var graph := Graph.new()
	for i in 5:
		var cell := GraphCell.new()
		cell.id = i
		graph.add_cell(cell)
	graph.get_cell(0).neighbor_ids = PackedInt32Array([1, 4])
	graph.get_cell(1).neighbor_ids = PackedInt32Array([0, 2])
	graph.get_cell(2).neighbor_ids = PackedInt32Array([1, 3])
	graph.get_cell(3).neighbor_ids = PackedInt32Array([2, 4])
	graph.get_cell(4).neighbor_ids = PackedInt32Array([0, 3])
	graph.finalize()
	graph.unlock_cell(1)
	graph.unlock_cell(2)

	var unrestricted := graph.find_path_unrestricted(0, 3)
	var restricted := graph.find_path(0, 3)

	var through_fog := 0
	for id in unrestricted:
		if not graph.is_discovered(id):
			through_fog += 1
	check(through_fog > 0, "the unrestricted route really does cut through fog")

	check(restricted.size() >= 2, "cell 3 is still reachable through discovered ground")
	check(restricted != unrestricted, "so routing had to pick a different way round")
	for id in restricted:
		check(graph.is_discovered(id), "route step %d is discovered" % id)


func test_shipped_map_routes_never_leave_the_light() -> void:
	# The half of the rule that does still hold on the shipped map, checked
	# across a real opening rather than one hand-picked pair: whatever route the
	# game hands back, every step of it is ground the player has uncovered.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return
	var start := _shipped_start(graph)
	for id in graph.get_cell(start).neighbor_ids:
		graph.unlock_cell(id)

	var checked := 0
	for to_id in graph.cell_ids:
		var path := graph.find_path(start, to_id)
		if path.size() < 2:
			continue
		checked += 1
		for id in path:
			check(graph.is_discovered(id), "route %d->%d steps on %d, which is fogged" % [start, to_id, id])
	check(checked > 0, "some cells were routable at all")


func test_path_cache_invalidated_on_unlock() -> void:
	# Paths are cached, and mining changes which of them exist. Without the
	# invalidation in Graph.unlock_cell this returns the old route forever, and
	# nothing else in the suite would notice.
	#
	# A loop with a long side and a short one: 0-1-2-3 the long way round, or
	# 0-4-3 through the shortcut at cell 4.
	#
	# Mining only 1 and 2 leaves 0 and 3 discovered as their neighbours, while
	# cell 4 — which touches neither — stays fogged, so the first lookup is
	# forced the long way. Mining cell 0 then uncovers the shortcut.
	var graph := Graph.new()
	for i in 5:
		var cell := GraphCell.new()
		cell.id = i
		graph.add_cell(cell)
	graph.get_cell(0).neighbor_ids = PackedInt32Array([1, 4])
	graph.get_cell(1).neighbor_ids = PackedInt32Array([0, 2])
	graph.get_cell(2).neighbor_ids = PackedInt32Array([1, 3])
	graph.get_cell(3).neighbor_ids = PackedInt32Array([2, 4])
	graph.get_cell(4).neighbor_ids = PackedInt32Array([0, 3])
	graph.finalize()
	graph.unlock_cell(1)
	graph.unlock_cell(2)

	check(graph.is_discovered(0) and graph.is_discovered(3), "both ends are visible")
	check(not graph.is_discovered(4), "but the shortcut is still fogged")
	check_eq(graph.find_path(0, 3), PackedInt32Array([0, 1, 2, 3]), "forced the long way")

	graph.unlock_cell(0)
	check(graph.is_discovered(4), "mining cell 0 uncovered the shortcut")
	check_eq(graph.find_path(0, 3), PackedInt32Array([0, 4, 3]), "the shortcut is taken")


func test_shipped_map_opens_under_fog() -> void:
	# Restricted routing shortens effective reach, so the map has to still offer
	# a legal opening move: something visible, unmined, and worth feeding.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return
	var world := World.new(graph)

	var start := _shipped_start(graph)
	var openings := 0
	for id in graph.cell_ids:
		var cell := graph.get_cell(id)
		if cell.is_unlocked or not graph.is_discovered(id):
			continue
		if world.projected_arrival(start, id) > 0:
			openings += 1
	check(openings > 0, "the starting generator can reach something worth mining")


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
	check_eq(shuffled.converted, ordered.converted, "converted")
	check_eq(shuffled.burned, ordered.burned, "burned")
	check_eq(shuffled.unlocked_count(), ordered.unlocked_count(), "cells unlocked")
	for id in ordered.graph.cell_ids:
		check_eq(
			shuffled.graph.get_cell(id).unlock_progress,
			ordered.graph.get_cell(id).unlock_progress,
			"cell %d progress" % id
		)
	# A bank is state one phase writes and another reads a tick later, which is
	# exactly the shape that breaks if the two are ever folded together. Both
	# kinds of intake are compared — a converter's charge and an upkeep block's
	# fuel — cell by cell rather than in aggregate: the totals could agree while
	# the charge sat on the wrong block.
	for id in ordered.graph.cell_ids:
		var block := ordered.graph.get_cell(id).block
		if block != null and block.def.has_intake():
			check_eq(
				shuffled.graph.get_cell(id).block.charge, block.charge,
				"cell %d charge" % id
			)
	# And the latch itself. A bonus that came on in one iteration order and not
	# the other would change every generator's interval board-wide, so this is
	# the single most load-bearing bit of state the upkeep phase owns.
	for id in ordered.graph.cell_ids:
		var block := ordered.graph.get_cell(id).block
		if block != null and block.def.burns_upkeep():
			check_eq(
				shuffled.graph.get_cell(id).block.fuelled, block.fuelled,
				"cell %d fuelled" % id
			)


func test_value_conservation() -> void:
	# The strong guarantee: over a long run with pumps firing, cells unlocking,
	# orbs evaporating and routes being changed, no value appears or vanishes
	# unaccounted for.
	var world := _busy_world()
	for i in 2000:
		world.tick()
		if i == 700:
			world.set_target(0, 13)
		if i == 1200:
			# Two pumps, not the generator: an anchored block refuses the swap,
			# and a refused swap would quietly drain the churn this test exists
			# to stress.
			if not world.swap_blocks(17, 19):
				_fail("the swap at tick 1200 was refused — the run lost its churn")
				return
		if not world.ledger_balanced():
			_fail("ledger broke at tick %d: produced %d + restored %d != delivered %d + wasted %d + decayed %d + converted %d + burned %d + in flight %d"
				% [world.tick_count, world.produced, world.restored, world.delivered,
					world.wasted, world.decayed, world.converted,
					world.burned, world.in_flight_value()])
			return
	check(world.produced > 0, "the run actually produced something")
	check(world.restored > 0, "pumps actually fired")
	# Orbs are never called back now, so the value that route changes and mining
	# used to destroy has to turn up somewhere. It lands on cells that finished
	# under it and wastes, which is the path this run has to have exercised.
	check(world.wasted > 0, "orbs outlived their routes and landed for nothing")
	# The sphere has to have been doing something, or this run covered the
	# stat-resolve phase in name only. Cheap to check and it fails loudly if the
	# radius is retuned or the sphere is moved off the pumps.
	check(world.is_boosted(17) or world.is_boosted(19),
		"the sphere boosted a pump — otherwise the run never exercised the field")
	# And the same guard for the global half of the pass. The Surge is the one
	# that touches the ledger, so a run where it silently did nothing would leave
	# `produced` covered only for the un-upgraded case.
	check(world.effective_orb_value() > World.ORB_START_VALUE,
		"the Surge raised the launch value — otherwise the run never exercised globals")
	check_eq(world.mined_challenges().size(), 3, "all three challenges were mined")
	# And the converter has to have been running, or the run covered the new sink
	# in name only — a `converted` that never moves balances trivially.
	check(world.converted > 0, "the upgrader absorbed red")
	check(world.graph.get_cell(15).unlock_progress > 0,
		"and the yellow at the end of the chain reached a cell only yellow can open")
	# The same guard for the other sink. A `burned` that never moves balances
	# trivially, and so does a latch that never flips.
	check(world.burned > 0, "the upkeep block absorbed red")
	check(not world.graph.get_cell(20).block.fuelled,
		"and outran its feed, so the run covered the latch going dark")
	# The waypointed route has to have survived the whole run, or it was never
	# under this invariant at all.
	check(world.graph.get_cell(10).block.has_waypoints(),
		"the waypointed orange route is still aimed")
	# Both converter defs have to have run, not just the first. A chain where the
	# second step never fires covers one conversion twice over.
	check(_charge_of(world, 12) > 0 or world.graph.get_cell(15).unlock_progress > 0,
		"the second step of the ladder took delivery of orange")


## A world with several generators, pumps, and reachable targets — enough
## activity for the invariant tests to be meaningful.
func _busy_world() -> World:
	var graph := MapLoader.line_graph(25)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 30 + id
	for id in [0, 6, 14]:
		graph.get_cell(id).initial_block_id = BlockCatalog.GENERATOR
	# Two pumps, so the run has a pair of movable blocks to swap. Generators are
	# anchored and cannot take part.
	# Both sit on the 14 -> 21 route and short of its final cell, so both fire.
	# Cell 21 stays locked because it is a target: aiming at a mined cell is
	# refused, and that would idle the generator instead.
	graph.get_cell(17).initial_block_id = BlockCatalog.PUMP
	graph.get_cell(19).initial_block_id = BlockCatalog.PUMP
	# A sphere reaching both pumps and the generator on 14, so the stat-resolve
	# phase is live for the whole run. This is what puts the sphere under the two
	# heavyweight invariants: the ledger has to stay balanced while a boosted pump
	# restores more, and the resolve pass has to be order-independent like every
	# other phase. Neither test would otherwise see a sphere at all.
	graph.get_cell(18).initial_block_id = BlockCatalog.SPHERE
	# All three challenges, so the global half of the stat-resolve pass is live
	# for the whole run and lands under the same two heavyweight invariants. The
	# Surge is the one that matters most here: it changes what every generator
	# emits, so the ledger has to stay balanced while `produced` books a figure
	# that is no longer the constant. The Lens widens the sphere above onto more
	# of the line, and the Current raises both pumps.
	graph.get_cell(2).initial_block_id = BlockCatalog.CHALLENGE_SURGE
	graph.get_cell(4).initial_block_id = BlockCatalog.CHALLENGE_CURRENT
	graph.get_cell(8).initial_block_id = BlockCatalog.CHALLENGE_LENS
	# An upgrader fed by the generator on 6, aimed at a cell only orange opens.
	# This is what puts the deliver hook and the `converted` bucket under both
	# heavyweight invariants, and neither would otherwise see a second tier at
	# all: the ledger has to stay balanced while value leaves circulation at one
	# cell and re-enters as a different colour at another, and the charge has to
	# accumulate the same way however the cells are iterated.
	graph.get_cell(10).initial_block_id = BlockCatalog.UPGRADER
	# And a second step of the ladder on 12, fed by the first. Two converter defs
	# rather than one, because a single scalar ledger spanning a conversion is the
	# claim most worth stressing: red leaves circulation at 10, comes back as
	# orange, leaves again at 12 and comes back as yellow, and the invariant has to
	# hold across all four crossings.
	graph.get_cell(12).initial_block_id = BlockCatalog.upgrader_id(Tiers.YELLOW)
	# Priced out of reach on purpose. At the going rate of 30 + id it would
	# unlock a few hundred ticks in, which unaims the upgrader and leaves the
	# rest of the run covering none of this.
	graph.get_cell(15).required_tier = Tiers.YELLOW
	graph.get_cell(15).unlock_cost = 1000000
	# An upkeep block on 20, fed by a fourth generator on 23. This is what puts
	# the drain phase, the `burned` bucket and the latch under both heavyweight
	# invariants: the ledger has to stay balanced while value leaves circulation
	# into a bank that is spent outside it, and the latch has to flip identically
	# however the cells are iterated.
	#
	# Both sit outside the sphere's reach and off the pump line, and that is the
	# whole point of where they are. The feed has to fall *short* of the drain —
	# 13 a delivery against 16 ticks of burn — so the run covers the latch going
	# both ways: lit from the primed bank at the start, dark around tick 1070 once
	# it runs out. Moved next to the sphere or onto the pumps it breaks even, the
	# latch never flips, and the run silently covers one state only.
	graph.get_cell(20).initial_block_id = BlockCatalog.UPKEEP
	graph.get_cell(23).initial_block_id = BlockCatalog.GENERATOR
	# A generator of a colour other than red, aimed at a cell of its own colour,
	# so both heavyweight invariants run with more than one tier actually in
	# flight. A tier is only a tag on an orb, but the gate it has to match is not:
	# a family member wired to the wrong output tier would idle here rather than
	# emit, and the run would quietly lose a third of its traffic.
	graph.get_cell(14).initial_block_id = BlockCatalog.generator_id(Tiers.TEAL)
	graph.get_cell(21).required_tier = Tiers.TEAL
	# Open the line up before aiming across it — routes do not cross fog.
	_discover_line(graph)
	graph.unlock_cell(17)
	graph.unlock_cell(19)
	graph.unlock_cell(18)
	graph.unlock_cell(10)
	graph.unlock_cell(12)
	# Primed rather than filled. One generator cannot outpace the drain — that is
	# the whole balance of the type — so a cold bank would never light at all and
	# the run would cover the latch in one state only. This value never entered
	# the economy through `emit_orb`, and the bank sits outside the ledger by
	# construction, so priming it moves no bucket and breaks no invariant.
	graph.get_cell(20).block.charge = BlockCatalog.get_def(
		BlockCatalog.UPKEEP).upkeep_reserve

	var world := World.new(graph)
	# Odd targets: the scaffold mines the even cells, and value delivered into an
	# already-mined cell is wasted rather than counted, which would make the run
	# far less busy than it looks.
	world.set_target(0, 5)
	# Into the upgrader on 10 rather than at a locked cell: a mined cell with an
	# intake is a legal target, and this is the only aim in the suite's busy world
	# that exercises it.
	world.set_target(6, 10)
	# Orange out of the first converter and into the second, which is the aim that
	# makes the ladder a chain rather than two unrelated blocks.
	#
	# Waypointed, which is the case worth putting under both invariants. On a line
	# the only legal via is one already on the way — a fold-back would cross itself
	# and be refused — so this bends through 11 and resolves to the same walk while
	# the block still carries a via-list. Its target is a mined cell with an
	# intake, so unlike every other aim here it lasts the whole run.
	world.set_target(10, 12, PackedInt32Array([11]))
	# And yellow out of the second, at a cell priced out of reach so this aim
	# survives the run too.
	world.set_target(12, 15)
	world.set_target(14, 21)
	world.set_target(23, 20)
	return world


# --- Tests: upkeep ------------------------------------------------------
#
# The first block that costs something to run. Two things are worth pinning
# hardest: that the bonus is real only while the bank holds out, and that it does
# not strobe at the boundary — a board-wide buff flickering every few ticks would
# be worse than no buff at all.


## A line with an upkeep block on cell 1, mined, and no generator — so a test can
## feed it by hand and read the ledger without a producer muddying the counters.
func _upkeep_world(count: int) -> World:
	var graph := MapLoader.line_graph(count)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 1000000
	graph.get_cell(1).initial_block_id = BlockCatalog.UPKEEP
	_discover_line(graph)
	graph.unlock_cell(1)
	return World.new(graph)


func _upkeep_def() -> BlockDef:
	return BlockCatalog.get_def(BlockCatalog.UPKEEP)


## Put fuel straight into an upkeep block's bank, so a test can set a level
## exactly rather than feeding orbs for minutes of simulated time.
##
## Deliberately does *not* touch the ledger. This value never entered the economy
## through `emit_orb`, so booking it to `burned` would invent a sink with no
## matching source and break the invariant. The bank sits outside the ledger by
## construction — fuel is booked when an orb lands, not while it drains — which is
## exactly what makes priming it safe.
func _fuel(world: World, cell_id: int, amount: int) -> void:
	world.graph.get_cell(cell_id).block.charge += amount


func test_upkeep_banks_red_and_lights_the_buff() -> void:
	var world := _upkeep_world(4)
	var def := _upkeep_def()
	_place(world, 3, BlockCatalog.GENERATOR)
	var generator := world.graph.get_cell(3)
	var base: int = BlockCatalog.get_def(BlockCatalog.GENERATOR).produce_interval

	check_eq(world.effective_interval(generator), base, "cold, the board runs at base speed")
	check(not world.graph.get_cell(1).block.fuelled, "and the block is dark")

	_fuel(world, 1, def.upkeep_reserve)
	world.tick()
	check(world.graph.get_cell(1).block.fuelled, "at the reserve it lights up")
	check_eq(world.effective_interval(generator),
		StatBonus.apply_rate(base, def.global_rate_percent),
		"and every generator on the board runs faster")
	check(world.ledger_balanced(), "ledger balanced")


func test_upkeep_grants_nothing_while_dry() -> void:
	var world := _upkeep_world(4)
	var def := _upkeep_def()
	_place(world, 3, BlockCatalog.GENERATOR)
	var generator := world.graph.get_cell(3)
	var base: int = BlockCatalog.get_def(BlockCatalog.GENERATOR).produce_interval

	# One short of the reserve is still dark. The threshold is a threshold.
	_fuel(world, 1, def.upkeep_reserve - 1)
	world.tick()
	check(not world.graph.get_cell(1).block.fuelled, "one short of the reserve is not enough")
	check_eq(world.effective_interval(generator), base, "so the board is unchanged")


func test_upkeep_grants_nothing_while_buried() -> void:
	# Mining is the whole transaction; the board does not pay out first.
	var graph := MapLoader.line_graph(4)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 1000000
	graph.get_cell(1).initial_block_id = BlockCatalog.UPKEEP
	_discover_line(graph)
	var world := World.new(graph)
	_place(world, 3, BlockCatalog.GENERATOR)
	var base: int = BlockCatalog.get_def(BlockCatalog.GENERATOR).produce_interval

	check(not graph.get_cell(1).is_unlocked, "the upkeep block is still buried")
	check_eq(graph.get_cell(1).block, null, "so there is no block to fuel")
	world.tick()
	check_eq(world.effective_interval(world.graph.get_cell(3)), base,
		"and nothing on the board is faster for it")


func test_upkeep_drain_empties_the_bank_and_goes_dark() -> void:
	var world := _upkeep_world(4)
	var def := _upkeep_def()
	_fuel(world, 1, def.upkeep_reserve)
	world.tick()
	check(world.graph.get_cell(1).block.fuelled, "lit")

	# Exactly the dwell time the reserve buys, and one more tick to go dark.
	_run(world, def.upkeep_reserve / def.upkeep_drain)
	check_eq(_charge_of(world, 1), 0, "the bank ran out")
	check(not world.graph.get_cell(1).block.fuelled, "so the bonus went dark")

	_run(world, 50)
	check_eq(_charge_of(world, 1), 0, "and the drain does not push it negative")
	check(world.ledger_balanced(), "ledger balanced")


func test_upkeep_hysteresis_does_not_strobe() -> void:
	# The failure this exists to prevent. Fed at exactly its drain rate around the
	# threshold, a block whose bonus was recomputed from `charge >= reserve` would
	# flip the interval of every generator on the board every few ticks.
	#
	# The latch turns on at the reserve and off only at empty, so across a long
	# run held at the boundary the board-wide interval changes at most once.
	var world := _upkeep_world(4)
	var def := _upkeep_def()
	_place(world, 3, BlockCatalog.GENERATOR)
	var generator := world.graph.get_cell(3)

	# Park the bank one short of lighting up, then feed it in a rhythm that walks
	# it back and forth across the threshold: twice the drain every other tick.
	# A block that recomputed `charge >= reserve` each tick would flip on the way
	# up and off again on the way down, every other tick, for the whole run.
	_fuel(world, 1, def.upkeep_reserve - 1)
	var last := world.effective_interval(generator)
	var flips := 0
	for i in 1000:
		if i % 2 == 0:
			_fuel(world, 1, def.upkeep_drain * 2)
		world.tick()
		var now := world.effective_interval(generator)
		if now != last:
			flips += 1
			last = now

	check(world.graph.get_cell(1).block.fuelled, "it lit up and stayed lit")
	check(flips <= 1, "the board-wide interval settled instead of strobing (flips: %d)" % flips)

	# And the other edge: cut the feed off and it goes dark exactly once.
	for i in def.upkeep_reserve * 2:
		world.tick()
	check(not world.graph.get_cell(1).block.fuelled, "starved, it goes dark")
	check_eq(flips + 1, 2, "one transition each way over the whole run")
	check(world.ledger_balanced(), "ledger balanced")


func test_upkeep_books_intake_as_burned() -> void:
	# Its own bucket. Burned value does not come back at all, where converted
	# value comes back as a higher tier — so they cannot share one.
	var world := _upkeep_world(4)
	# One hop, so the orb crosses nothing and arrives with its full launch value.
	_launch_one(world, 0, 1)
	check_eq(world.burned, World.ORB_START_VALUE, "the whole arrival went into the bank")
	# Not the full 10: the drain has been running every tick since it landed, and
	# the bank is outside the ledger, so spending from it moves no bucket.
	var held := _charge_of(world, 1)
	check(held > 0 and held < World.ORB_START_VALUE,
		"and the bank holds it, less what has drained since (held: %d)" % held)
	check_eq(world.delivered, 0, "nothing counted toward an unlock")
	check_eq(world.converted, 0, "and nothing was converted")
	check_eq(world.wasted, 0, "the intake is total, so there is no overshoot")
	check(world.ledger_balanced(), "ledger balanced")


func test_upkeep_ignores_passing_orbs() -> void:
	# An orb merely routed across an upkeep block is untouched, so a converter
	# cannot be used as a toll gate on somebody else's line. Newly load-bearing:
	# waypoints make crossing a cell a deliberate act.
	var world := _upkeep_world(5)
	_launch_one(world, 0, 3)
	check_eq(_charge_of(world, 1), 0, "the block took nothing from an orb passing through")
	check_eq(world.burned, 0, "so nothing was burned")
	check(world.ledger_balanced(), "ledger balanced")


func test_upkeep_rejects_wrong_tier_input() -> void:
	var world := _upkeep_world(4)
	world.emit_orb(0, 1, Tiers.ORANGE)
	_run(world, World.TICKS_PER_HOP + 2)
	check_eq(_charge_of(world, 1), 0, "orange is not what this burns")
	check_eq(world.burned, 0, "nothing entered the bank")
	check_eq(world.wasted, World.ORB_START_VALUE, "and the arrival was wasted instead")
	check(world.ledger_balanced(), "ledger balanced")


func test_can_aim_a_generator_at_an_upkeep() -> void:
	# The `accepts_delivery` generalisation. A mined cell is a legal target when
	# something standing on it has an intake — and there are two kinds now.
	var world := _upkeep_world(4)
	_place(world, 0, BlockCatalog.GENERATOR)
	check(world.can_aim_at(0, 1), "a mined cell with an intake is a legal target")
	check(world.set_target(0, 1), "and set_target agrees")

	_place(world, 2, BlockCatalog.PUMP)
	check(not world.can_aim_at(0, 2), "a mined cell with no intake still is not")


func test_upkeep_can_be_swapped_and_keeps_its_fuel() -> void:
	# Movable, unlike a challenge and unlike an upgrader — being feedable is a
	# real placement decision, so the player has to be able to act on it. Fuel and
	# latch live on the block, so they travel with it for free.
	var world := _upkeep_world(6)
	var def := _upkeep_def()
	_fuel(world, 1, def.upkeep_reserve)
	world.tick()
	check(world.graph.get_cell(1).block.fuelled, "lit before the move")

	check(world.swap_blocks(1, 4), "an upkeep block can be picked up")
	check_eq(world.graph.get_cell(4).block.def.id, BlockCatalog.UPKEEP, "it landed on cell 4")
	check_eq(world.graph.get_cell(1).block, null, "and left nothing behind")
	check(world.graph.get_cell(4).block.fuelled, "it is still running after the move")
	check(_charge_of(world, 4) > 0, "with its bank intact")
	check(world.ledger_balanced(), "ledger balanced")


func test_upkeep_buff_does_not_mark_generators_boosted() -> void:
	# `is_boosted` means "a sphere is doing this", and the ring on the board says
	# so. A board-wide bonus is measured into the baseline instead, or mining one
	# upkeep block would light every generator on the map at once.
	var world := _upkeep_world(4)
	_place(world, 3, BlockCatalog.GENERATOR)
	_fuel(world, 1, _upkeep_def().upkeep_reserve)
	world.tick()

	var generator := world.graph.get_cell(3)
	check(world.effective_interval(generator) < BlockCatalog.get_def(
		BlockCatalog.GENERATOR).produce_interval, "the generator really is faster")
	check_eq(world.effective_interval(generator), world.base_interval(generator),
		"but the whole of it is in the baseline")
	check(not world.is_boosted(3), "so no sphere ring appears on it")


func test_sphere_still_pays_off_under_upkeep() -> void:
	# The one place the two built buffs interact, and the rule that governs it:
	# both are increased rates, and **rates sum before they divide**. A sphere on
	# a board with an upkeep block lit is one divisor of +50%, not two divisions
	# of +25% — which would truncate twice and quietly hand out a different
	# number depending on which buff was applied first.
	var world := _upkeep_world(8)
	_place(world, 5, BlockCatalog.GENERATOR)
	var generator := world.graph.get_cell(5)
	var upkeep_rate: int = _upkeep_def().global_rate_percent
	var sphere_rate: int = _sphere_def().field_rate_percent
	var base: int = BlockCatalog.get_def(BlockCatalog.GENERATOR).produce_interval

	_fuel(world, 1, _upkeep_def().upkeep_reserve)
	world.tick()
	check_eq(world.base_interval(generator), StatBonus.apply_rate(base, upkeep_rate),
		"the upkeep block moved the baseline")

	_place(world, 4, BlockCatalog.SPHERE)
	var with_sphere := world.effective_interval(generator)
	check(with_sphere < world.base_interval(generator),
		"and a sphere still buys more on top of it")
	check_eq(with_sphere, StatBonus.apply_rate(base, upkeep_rate + sphere_rate),
		"the two rates share one divisor")
	check(with_sphere >= World.MIN_PRODUCE_INTERVAL, "never below the floor")


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

	# Every cell must be reachable at all. These assertions describe what the map
	# *is*, so they ignore discovery — at load only the start and its neighbours
	# are uncovered, and routing through fog is refused by design.
	var world := World.new(graph)
	var out_of_range := 0
	for id in graph.cell_ids:
		if id == sources[0]:
			continue
		check(graph.distance_unrestricted(sources[0], id) >= 0, "cell %d is reachable" % id)
		var best := 0
		for s in sources:
			best = maxi(best, world.arrival_along(graph.find_path_unrestricted(s, id)))
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
		if cell.initial_block_id == BlockCatalog.PUMP:
			pumps += 1
			continue
		# Asked of the def rather than matched against an id. There is a generator
		# per colour now, so a `match` on BlockCatalog.GENERATOR would count a
		# seventh of them and quietly pass a board with one red source on it.
		var def := BlockCatalog.get_def(cell.initial_block_id)
		if def != null and def.produces():
			generators += 1
			if cell.is_unlocked:
				start = id

	check(start != -1, "a starting generator is already mined")
	check(generators >= 3, "several generators exist to rearrange")
	check(pumps >= 4, "several pumps exist to rearrange")

	# Shape assertions are about the map, not about what has been uncovered yet.
	#
	# Measured with a **double sweep** rather than all-pairs, and the reason is
	# cost: `find_path_unrestricted` is uncached, so the old nested loop ran one
	# BFS per ordered pair. At 230 cells that was 52,900 of them; the board is now
	# four times larger, which would have been 900,000 and turned an eleven-second
	# suite into a coffee break. Two sweeps is O(V+E) and the answer is a **lower
	# bound** on the diameter, which is all a `>=` assertion needs.
	var far: Array = _farthest_from(graph, graph.cell_ids[0])
	var diameter: int = _farthest_from(graph, far[0])[1]
	check(diameter >= 12, "diameter %d is long enough that decay bites" % diameter)

	# At least one pump must sit inside the unaided frontier, or the first one
	# can never be acquired and the map is unwinnable from the opening move.
	for id in graph.cell_ids:
		if graph.get_cell(id).initial_block_id == BlockCatalog.PUMP \
				and world.arrival_along(graph.find_path_unrestricted(start, id)) > 0:
			reachable_pumps += 1
	check(reachable_pumps > 0, "a first pump is minable without already having one")


func test_shipped_map_challenges_are_unique_per_band() -> void:
	# `gen_map.py` asserts this when it writes the map; this re-checks it on what
	# actually shipped, so a hand-edited or stale map_01.json fails here rather
	# than quietly doubling a bonus up inside one ring.
	#
	# Uniqueness used to be board-wide. There is one of each challenge in every
	# colour band now — the three effects are placeholders that repeat until they
	# differentiate — so what has to hold is that a *band* never gets two of the
	# same. Two Surges in one ring would be the same decision twice in a row,
	# which is what spreading them exists to avoid.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return

	var ids: Array[String] = [
		BlockCatalog.CHALLENGE_SURGE,
		BlockCatalog.CHALLENGE_CURRENT,
		BlockCatalog.CHALLENGE_LENS,
	]

	# tier -> block id -> how many. Every tier that has any challenge must have
	# exactly one of each.
	var by_tier: Dictionary = {}
	for id in graph.cell_ids:
		var cell := graph.get_cell(id)
		if not ids.has(cell.initial_block_id):
			continue
		var counts: Dictionary = by_tier.get(cell.required_tier, {})
		counts[cell.initial_block_id] = int(counts.get(cell.initial_block_id, 0)) + 1
		by_tier[cell.required_tier] = counts

		check(cell.is_challenge(),
			"%s at cell %d reads as a challenge before it is mined"
				% [cell.initial_block_id, id])

	check_eq(by_tier.size(), Tiers.COUNT,
		"every colour band buries challenges")
	for tier in by_tier:
		for block_id in ids:
			check_eq(int(by_tier[tier].get(block_id, 0)), 1,
				"exactly one %s in the %s band" % [block_id, Tiers.name_of(tier)])

	for block_id in ids:
		check(not BlockCatalog.get_def(block_id).movable,
			"%s is anchored" % block_id)


func test_shipped_map_challenges_cost_more_than_their_neighbours() -> void:
	# Expensive, measured against an ordinary cell the same distance out rather
	# than against a pinned number — the cost ramp lives in `gen_map.py`, so
	# recomputing it here would be a second copy to drift.
	#
	# The comparison cell has to demand the same colour. Every tier but red is
	# priced on a divided curve, so a green challenge measured against a teal
	# neighbour would be comparing two different currencies and would pass for the
	# wrong reason.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return

	var start := _shipped_start(graph)
	var compared := 0
	for id in graph.cell_ids:
		var cell := graph.get_cell(id)
		if not cell.is_challenge():
			continue
		var hops := graph.distance_unrestricted(start, id)
		var plain_cost := -1
		for other_id in graph.cell_ids:
			var other := graph.get_cell(other_id)
			if not other.is_challenge() and other_id != start \
					and other.required_tier == cell.required_tier \
					and graph.distance_unrestricted(start, other_id) == hops:
				plain_cost = other.unlock_cost
				break
		if plain_cost <= 0:
			continue  # nothing at that exact distance in that colour to compare
		compared += 1
		check(cell.unlock_cost > plain_cost,
			"%s at cell %d costs %d, above the %d an ordinary %s cell at %d hops costs"
				% [cell.initial_block_id, id, cell.unlock_cost, plain_cost,
					Tiers.name_of(cell.required_tier), hops])
	# Guards against the loop above passing vacuously: with narrow bands a
	# challenge can be the only cell of its colour at its exact hop count, and if
	# that were true of *all* of them this test would assert nothing.
	check(compared > 0,
		"at least one challenge had an ordinary cell of its colour to compare against")


func test_shipped_map_tier_ladder() -> void:
	# `gen_map.py` asserts the ladder's shape when it writes the map; this
	# re-checks it on what shipped, so a stale or hand-edited map_01.json fails
	# here rather than quietly opening the rim to the starting colour.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return

	var start := _shipped_start(graph)
	var radius := 0
	var deepest: Array[int] = []
	var shallowest: Array[int] = []
	for _i in Tiers.COUNT:
		deepest.append(-1)
		shallowest.append(1 << 30)
	for id in graph.cell_ids:
		var cell := graph.get_cell(id)
		var hops := graph.distance_unrestricted(start, id)
		radius = maxi(radius, hops)
		deepest[cell.required_tier] = maxi(deepest[cell.required_tier], hops)
		shallowest[cell.required_tier] = mini(shallowest[cell.required_tier], hops)

	# Every rung of the ladder is actually on the board. A colour with no cells
	# demanding it is a colour the player never has a reason to make.
	for tier in Tiers.COUNT:
		check(deepest[tier] >= 0,
			"the map ships cells that demand %s" % Tiers.name_of(tier))

	# The ladder climbs outward, and strictly. Each colour both starts and ends
	# further out than the one below it, which is what makes pushing the frontier
	# and climbing the ladder the same act.
	for tier in range(1, Tiers.COUNT):
		check(shallowest[tier] > shallowest[tier - 1],
			"%s starts further out than %s (%d vs %d hops)"
				% [Tiers.name_of(tier), Tiers.name_of(tier - 1),
					shallowest[tier], shallowest[tier - 1]])
		check(deepest[tier] > deepest[tier - 1],
			"%s reaches further out than %s (%d vs %d hops)"
				% [Tiers.name_of(tier), Tiers.name_of(tier - 1),
					deepest[tier], deepest[tier - 1]])

	# Red must not reach the rim, or the six colours above it are decorative: the
	# whole point is that the outer board is shut to the colour you start with.
	check(deepest[Tiers.RED] < radius,
		("the furthest red cell is %d hops out against a radius of %d — the "
			+ "ladder gates nothing") % [deepest[Tiers.RED], radius])

	# And a colour has to appear before its own band, or every boundary is a wall
	# met with no warning. `gen_map.py` calls this the scatter.
	var scattered := 0
	for id in graph.cell_ids:
		var cell := graph.get_cell(id)
		if cell.required_tier == Tiers.RED:
			continue
		if graph.distance_unrestricted(start, id) < shallowest[cell.required_tier] + 1:
			continue
		scattered += 1
	check(scattered > 0,
		"colours arrive as a scatter before the wall, not only as the wall")


func test_shipped_map_sources_are_payable_in_an_earlier_colour() -> void:
	# The deadlock check, and the one worth having. A source buried behind a gate
	# deeper than what it makes can only be paid for with the thing it is needed
	# to build.
	#
	# Two rules, and they differ by one step. An **upgrader** must sit at or below
	# its *input* colour, because the colour it makes is precisely what does not
	# exist yet. A **generator** may sit on its own colour — the other generator of
	# that colour, or an upgrader, can open it — but never deeper.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return

	var generators := 0
	var upgraders := 0
	for id in graph.cell_ids:
		var cell := graph.get_cell(id)
		var def := BlockCatalog.get_def(cell.initial_block_id)
		if def == null:
			continue
		if def.converts():
			upgraders += 1
			check(cell.required_tier <= def.input_tier,
				("cell %d buries an upgrader into %s behind a %s gate — nothing "
					+ "can pay for it before it exists")
					% [id, Tiers.name_of(def.output_tier),
						Tiers.name_of(cell.required_tier)])
			check(not def.movable, "%s is anchored" % def.id)
		elif def.produces():
			generators += 1
			check(cell.required_tier <= def.output_tier,
				("cell %d buries a %s generator behind a %s gate — it is locked "
					+ "behind a colour deeper than the one it makes")
					% [id, Tiers.name_of(def.output_tier),
						Tiers.name_of(cell.required_tier)])
			check(not def.movable, "%s is anchored" % def.id)

	# Every colour has generators of its own, which is what makes an upgrader a
	# *positional* source rather than the only mint. Counted rather than located:
	# where they sit is the search's business, that they exist at all is the rule.
	check(generators >= Tiers.COUNT,
		"the map ships generators for every colour (%d buried)" % generators)
	check(upgraders >= Tiers.COUNT - 1,
		"the map ships an upgrader for every step of the ladder (%d buried)"
			% upgraders)


func test_shipped_map_upkeeps_are_shallow_and_movable() -> void:
	# Same re-check on what shipped. An upkeep block burns red wherever it sits,
	# so one buried out in the deep bands could not be fed until a red line
	# already reached it — long after a faster generator was worth having. Not a
	# deadlock like the upgrader's, just a block the player would find useless.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return

	var upkeeps: Array[int] = []
	for id in graph.cell_ids:
		if graph.get_cell(id).initial_block_id == BlockCatalog.UPKEEP:
			upkeeps.append(id)

	check(not upkeeps.is_empty(), "the map ships upkeep blocks")
	var def := BlockCatalog.get_def(BlockCatalog.UPKEEP)
	for id in upkeeps:
		# One colour above what it eats. Red is where it wants to be; orange is
		# close enough that a red line reaches it while the buff still matters.
		check(graph.get_cell(id).required_tier <= def.input_tier + 1,
			"cell %d buries an upkeep block behind a %s gate"
				% [id, Tiers.name_of(graph.get_cell(id).required_tier)])
	# Movable, unlike every other board-wide bonus on the map. A challenge is
	# anchored because its bonus reaches everywhere from anywhere; this one has to
	# be fed, so where it sits is a decision the player has to be able to make.
	check(def.movable, "upkeep blocks can be moved")
