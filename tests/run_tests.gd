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
		"test_pump_adds_flat_amount",
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
		"test_upgrader_banks_charge_while_idle",
		"test_upgrader_emits_one_orb_per_tick",
		"test_upgrader_ignores_passing_orbs",
		"test_upgrader_rejects_wrong_tier_input",
		"test_upgrader_cannot_be_swapped",
		"test_upgrader_marks_active_only_when_it_emits",
		"test_sphere_does_nothing_for_an_upgrader",
		"test_orange_cell_ignores_red_orbs",
		"test_cannot_aim_red_at_an_orange_cell",
		"test_can_aim_a_generator_at_an_upgrader",
		"test_cannot_aim_at_a_mined_cell_without_an_intake",
		"test_locked_cell_tint_follows_its_tier",

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
		"test_retarget_cancels_in_flight",
		"test_unlock_installs_map_block",
		"test_unlock_of_empty_cell_stays_empty",
		"test_unlock_unaims_generators",
		"test_unlock_cancels_orbs_to_that_target",
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
		"test_orb_weave_vanishes_at_cell_centres",
		"test_orb_weave_alternates_side_each_hop",
		"test_orb_weave_gives_each_source_its_own_lane",
		"test_path_determinism",
		"test_path_tie_break_is_lowest_id",
		"test_locked_cells_are_traversable",
		"test_projected_arrival_matches_reality",
		"test_fog_hides_undiscovered",
		"test_cannot_aim_at_undiscovered",
		"test_mining_expands_discovery",
		"test_routes_stay_inside_discovered",
		"test_shipped_map_routes_never_leave_the_light",
		"test_path_cache_invalidated_on_unlock",
		"test_shipped_map_opens_under_fog",
		"test_tick_order_independent",
		"test_value_conservation",
		"test_shipped_map_is_valid",
		"test_shipped_map_is_a_web",
		"test_shipped_map_challenges_are_unique_and_ordered",
		"test_shipped_map_orange_band_and_upgraders",
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


## The one cell the shipped map hands over already mined, found rather than
## assumed: it sits in the middle of the board, so its id moves whenever the
## lattice is regenerated and nothing should be pinned to a literal.
func _shipped_start(graph: Graph) -> int:
	for id in graph.cell_ids:
		if graph.get_cell(id).is_unlocked:
			return id
	return -1


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


## Launch one orb and run until it has resolved, one way or another.
func _launch_one(world: World, from_id: int, to_id: int) -> void:
	world.emit_orb(from_id, to_id, Tiers.RED)
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


func test_pump_adds_flat_amount() -> void:
	# A pump adds a fixed amount, it does not top the orb back up to where it
	# started. 12 hops with a pump at hop 5: 10 - 5 = 5 on reaching the pump,
	# +3 = 8, then six more crossed cells to arrive with 2.
	var world := _one_orb_world(13)
	_place(world, 5, BlockCatalog.PUMP)
	_launch_one(world, 0, 12)
	check_eq(world.delivered, 2, "pumped orb over 12 hops")
	check_eq(world.restored, 3, "the pump added its flat amount, not 5")
	check_eq(world.decayed, 11, "11 crossed cells")
	check_eq(world.evaporated_orbs, 0, "the pump saved it")
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
	# A pump cell nets +2 and a plain cell -1, so a chain only holds while its
	# pumps sit three hops apart or closer. Pumps at hops 3 and 6 return the orb
	# to full twice and carry it 12 hops — past its unaided range of 10.
	var world := _one_orb_world(13)
	_place(world, 3, BlockCatalog.PUMP)
	_place(world, 6, BlockCatalog.PUMP)
	_launch_one(world, 0, 12)
	check_eq(world.delivered, 5, "two pumps deliver 5 over 12 hops")
	check_eq(world.restored, 6, "both pumps fired")
	check_eq(world.evaporated_orbs, 0, "the chain held")
	check(world.ledger_balanced(), "ledger balanced")


func test_pump_spacing_decides_survival_not_value() -> void:
	# What spacing controls is whether the orb lives, not what it arrives with:
	# arrival is 10 - (hops - 1) + 3 * pumps whatever the gaps look like. A pump
	# cell nets +2 and a plain cell -1, so a chain holds at three hops apart and
	# bleeds a point per segment at four — over a long enough line, out.
	#
	# Same 29-hop route both ways. Three apart: nine pumps, arrives with 9.
	var tight := _one_orb_world(30)
	for hop in [3, 6, 9, 12, 15, 18, 21, 24, 27]:
		_place(tight, hop, BlockCatalog.PUMP)
	_launch_one(tight, 0, 29)
	check_eq(tight.delivered, 9, "a three-hop chain holds over 29 hops")
	check_eq(tight.evaporated_orbs, 0, "and nothing evaporated")
	check(tight.ledger_balanced(), "ledger balanced")

	# Four apart: seven pumps, and the orb bleeds out on the last stretch.
	var loose := _one_orb_world(30)
	for hop in [4, 8, 12, 16, 20, 24, 28]:
		_place(loose, hop, BlockCatalog.PUMP)
	_launch_one(loose, 0, 29)
	check_eq(loose.delivered, 0, "a four-hop chain does not reach")
	check_eq(loose.evaporated_orbs, 1, "the orb bled out before the last pump")
	check(loose.ledger_balanced(), "ledger balanced")


func test_pump_stacks_without_ceiling() -> void:
	# Pumps stack with no ceiling, so a well-supported orb arrives worth more
	# than it launched with. Pumps at hops 1 and 2: 9 -> 12, then 11 -> 14, then
	# one crossed cell and a free arrival, for 13.
	var world := _one_orb_world(5)
	_place(world, 1, BlockCatalog.PUMP)
	_place(world, 2, BlockCatalog.PUMP)
	_launch_one(world, 0, 4)
	check_eq(world.delivered, 13, "arrived worth more than a fresh orb")
	check(world.delivered > World.ORB_START_VALUE, "the launch value is not a cap")
	check_eq(world.restored, 6, "both pumps added their full amount")
	check(world.ledger_balanced(), "ledger balanced")


# --- Tests: spheres -----------------------------------------------------


## Base numbers, read from the catalog rather than pinned, so tuning the sphere
## retunes the tests with it. The arithmetic each test asserts is spelled out in
## its comment, which is the part that must not silently change.
func _sphere_def() -> BlockDef:
	return BlockCatalog.get_def(BlockCatalog.SPHERE)


func test_sphere_speeds_generators_in_radius() -> void:
	# The generator on cell 0 fires every `interval` ticks; a sphere one hop away
	# takes `field_interval_bonus` ticks off that. Counted in orbs produced over a
	# fixed budget rather than in ticks, because emission count is what the player
	# actually feels.
	var base: int = BlockCatalog.get_def(BlockCatalog.GENERATOR).produce_interval
	var boosted: int = base + _sphere_def().field_interval_bonus

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
	# One pump at hop 1 on a 4-hop line. Unaided it restores its base amount; with
	# a sphere adjacent it restores base + field_restore_bonus, and the whole
	# difference lands in the delivered value.
	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_amount
	var bonus: int = _sphere_def().field_restore_bonus

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
	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_amount
	var bonus: int = _sphere_def().field_restore_bonus

	var world := _one_orb_world(radius + 4)
	_place(world, 0, BlockCatalog.SPHERE)
	for hop in range(1, radius + 2):
		_place(world, hop, BlockCatalog.PUMP)

	for hop in range(1, radius + 1):
		check_eq(world.effective_restore(world.graph.get_cell(hop)), pump_base + bonus,
			"a pump %d hops out is inside the field" % hop)
	check_eq(world.effective_restore(world.graph.get_cell(radius + 1)), pump_base,
		"a pump one hop past the radius gets nothing")


func test_sphere_bonuses_stack() -> void:
	# Two spheres reaching the same pump contribute twice. A field that saturated
	# would make the second sphere worthless, which is the mistake the pump's flat
	# restore already avoids.
	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_amount
	var bonus: int = _sphere_def().field_restore_bonus

	var world := _one_orb_world(6)
	_place(world, 2, BlockCatalog.PUMP)
	_place(world, 1, BlockCatalog.SPHERE)
	_place(world, 3, BlockCatalog.SPHERE)
	check_eq(world.effective_restore(world.graph.get_cell(2)), pump_base + bonus * 2,
		"both spheres reach the pump")


func test_sphere_interval_never_reaches_zero() -> void:
	# Enough spheres to drive the interval below zero if nothing stopped them. A
	# zero interval is a generator emitting every tick and a divide by zero in the
	# view's cooldown arc, so the floor is load-bearing rather than tidy.
	#
	# The generator sits mid-line rather than on cell 0, because a line end only
	# has two cells within radius and two spheres are not enough to reach the
	# floor. Surrounded on both sides it gets four, for 20 - 16 = 4 before the
	# clamp.
	var world := _one_orb_world(9)
	_place(world, 4, BlockCatalog.GENERATOR)
	for id in [2, 3, 5, 6]:
		_place(world, id, BlockCatalog.SPHERE)

	var generator := world.graph.get_cell(4)
	var raw: int = generator.block.def.produce_interval \
		+ 4 * _sphere_def().field_interval_bonus
	check(raw < World.MIN_PRODUCE_INTERVAL, "the test really does overshoot the floor")
	check_eq(world.effective_interval(generator), World.MIN_PRODUCE_INTERVAL,
		"clamped at the floor")
	check(world.effective_interval(generator) > 0, "and never reaches zero")


func test_sphere_field_follows_a_swap() -> void:
	# Moving a sphere moves its field. This is the case an incrementally-mutated
	# stats table gets wrong: the bonus has to vanish from the old position and
	# appear at the new one, with nothing left behind.
	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_amount
	var bonus: int = _sphere_def().field_restore_bonus

	# Pumps far enough apart that one sphere can only ever reach one of them.
	var world := _one_orb_world(12)
	_place(world, 1, BlockCatalog.PUMP)
	_place(world, 9, BlockCatalog.PUMP)
	_place(world, 2, BlockCatalog.SPHERE)

	check_eq(world.effective_restore(world.graph.get_cell(1)), pump_base + bonus,
		"the near pump starts boosted")
	check_eq(world.effective_restore(world.graph.get_cell(9)), pump_base,
		"the far pump starts unboosted")

	# Cell 8 is mined and empty, so this is a move rather than an exchange.
	check(world.swap_blocks(2, 8), "the sphere moved")
	check_eq(world.effective_restore(world.graph.get_cell(1)), pump_base,
		"the old position lost the bonus")
	check_eq(world.effective_restore(world.graph.get_cell(9)), pump_base + bonus,
		"and the new one gained it")


func test_sphere_field_appears_on_mining() -> void:
	# A sphere buried in a locked cell radiates nothing — it is not installed yet.
	# Mining the cell is what lights the field, and the stats table has to notice
	# even though mining goes through the graph rather than through World.
	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_amount
	var bonus: int = _sphere_def().field_restore_bonus

	var world := _one_orb_world(6)
	_place(world, 1, BlockCatalog.PUMP)

	var buried := world.graph.get_cell(2)
	buried.initial_block_id = BlockCatalog.SPHERE
	buried.is_unlocked = false
	check_eq(world.effective_restore(world.graph.get_cell(1)), pump_base,
		"a buried sphere radiates nothing")

	world.graph.unlock_cell(2)
	check_eq(world.effective_restore(world.graph.get_cell(1)), pump_base + bonus,
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
	# A Current adds to every pump on the board, wherever it is and with no sphere
	# anywhere. Blocks that restore nothing are untouched: the bonus is folded in
	# through `base_restore`, which bails on a base of 0.
	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_amount
	var bonus: int = BlockCatalog.get_def(BlockCatalog.CHALLENGE_CURRENT) \
		.global_field_restore_bonus

	var world := _one_orb_world(8)
	_place(world, 1, BlockCatalog.PUMP)
	# Far enough from the pump that no field could reach it even if it had one.
	_place(world, 6, BlockCatalog.CHALLENGE_CURRENT)

	check_eq(world.effective_restore(world.graph.get_cell(1)), pump_base + bonus,
		"a pump nowhere near the challenge still gets the bonus")
	check_eq(world.effective_restore(world.graph.get_cell(6)), 0,
		"the challenge itself restores nothing")

	_launch_one(world, 0, 5)
	check_eq(world.restored, pump_base + bonus, "the pump restored the boosted amount")
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

	var pump_base: int = BlockCatalog.get_def(BlockCatalog.PUMP).restore_amount
	var bonus: int = _sphere_def().field_restore_bonus

	var world := _one_orb_world(widened + 4)
	_place(world, 0, BlockCatalog.SPHERE)
	for hop in range(1, widened + 2):
		_place(world, hop, BlockCatalog.PUMP)

	check_eq(world.effective_restore(world.graph.get_cell(widened)), pump_base,
		"before the Lens, a pump at the widened radius is out of range")

	_place(world, widened + 2, BlockCatalog.CHALLENGE_LENS)

	check_eq(world.effective_field_radius(_sphere_def()), widened,
		"the Lens widened the reported radius")
	check_eq(world.effective_restore(world.graph.get_cell(widened)), pump_base + bonus,
		"and the pump at that radius is now inside the field")
	check_eq(world.effective_restore(world.graph.get_cell(widened + 1)), pump_base,
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
	check_eq(world.effective_restore(world.graph.get_cell(2)), 0,
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

	check(world.effective_restore(world.graph.get_cell(1))
		> BlockCatalog.get_def(BlockCatalog.PUMP).restore_amount,
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
func _upgrader_world(count: int) -> World:
	var graph := MapLoader.line_graph(count)
	for id in graph.cell_ids:
		graph.get_cell(id).unlock_cost = 1000000
	graph.get_cell(1).initial_block_id = BlockCatalog.UPGRADER
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


func test_upgrader_emits_one_orb_per_tick() -> void:
	# Twelve orbs is two full charges. They must leave as two orbs on two ticks,
	# not as one clump: charge carries over rather than being flushed.
	var world := _upgrader_world(4)
	for i in 12:
		_launch_one(world, 0, 1)
	check_eq(_charge_of(world, 1), 120, "two full charges banked while idle")

	world.graph.get_cell(3).required_tier = Tiers.ORANGE
	check(world.set_target(1, 3), "aimed")
	world.tick()
	check_eq(world.live_orb_count(), 1, "one orb on the first tick")
	check_eq(_charge_of(world, 1), 60, "one charge spent, one carried over")
	world.tick()
	check_eq(world.live_orb_count(), 2, "the second orb on the next tick")
	check_eq(_charge_of(world, 1), 0, "and the bank is empty")


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


func test_sphere_does_nothing_for_an_upgrader() -> void:
	# A converter has no interval to shorten and no restore to raise, so a sphere
	# parked next to one is wasted. Deliberate: discounting `upgrade_cost` would
	# be a third field-bonus axis, and it is a decision to take on its own.
	var world := _upgrader_world(4)
	_place(world, 2, BlockCatalog.SPHERE)
	world.graph.get_cell(3).required_tier = Tiers.ORANGE
	check(world.set_target(1, 3), "aimed")

	# The field genuinely covers the cell — this is not a test that missed.
	check(world.field_cells(2).has(1), "the sphere's field does reach the upgrader")
	# But nothing on the upgrader reads it, so the board does not ring the cell.
	# `is_boosted` means "this block is running on different numbers", and a
	# converter has no interval and no restore for a sphere to change.
	check(not world.is_boosted(1),
		"a converter has no stat a sphere can touch, so it is not marked boosted")

	for i in 5:
		_launch_one(world, 0, 1)
	check_eq(_charge_of(world, 1), 50, "still 50 of 60 — the field bought nothing")
	check_eq(world.live_orb_count(), 0, "and nothing was emitted early")


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


# --- Tests: unlocking ---------------------------------------------------


func test_unlock_exact() -> void:
	# 2 hops, so each orb arrives with 8. A cost of 24 needs exactly 3 orbs and
	# leaves nothing wasted.
	var graph := MapLoader.line_graph(3)
	graph.get_cell(0).initial_block_id = BlockCatalog.GENERATOR
	_discover_line(graph)
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
	_discover_line(graph)
	graph.get_cell(2).unlock_cost = 20
	var world := World.new(graph)
	world.set_target(0, 2)

	_run(world, _ticks_for_one_delivery(2) + 2 * 20)
	check(graph.get_cell(2).is_unlocked, "cell 2 unlocked")
	check_eq(world.delivered, 20, "only the needed value counted")
	check_eq(world.wasted, 4, "overshoot recorded as waste")
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

	check_eq(amounts, [8, 8, 4] as Array[int], "each event is what counted, not what was carried")

	# The invariant worth pinning. The list's *order* is not order-independent and
	# deliberately never will be, but its sum is the same addition the ledger
	# made — so this catches recording orb.value instead of used, recording on
	# the wasted branch, and double-recording.
	var total := 0
	for amount in amounts:
		total += amount
	check_eq(total, world.delivered + world.converted,
		"the events sum to exactly what the ledger counted")
	check_eq(world.wasted, 4, "and the overshoot stayed out of them")
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
	check_eq(world.restored, pump.def.restore_amount, "the pump really did restore")
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


func test_retarget_cancels_in_flight() -> void:
	var world := _line_world(10)
	_run(world, _ticks_for_one_delivery(9) - 30)  # orbs mid-flight
	var in_flight := world.in_flight_value()
	check(in_flight > 0, "there are orbs in flight to cancel")

	world.set_target(0, 5)
	check_eq(world.cancelled, in_flight, "all in-flight value was cancelled")
	check_eq(world.in_flight_value(), 0, "nothing survived the retarget")
	check(world.ledger_balanced(), "ledger balanced after cancel")


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


func test_unlock_cancels_orbs_to_that_target() -> void:
	# The route ends the moment the cell is mined, and an orb belongs to the route
	# that launched it — so whatever is still flying at it is cancelled rather
	# than left to land somewhere that consumes nothing.
	#
	# The ledger check is the real assertion. The orb that completes the unlock is
	# mid-delivery when the cancel sweep runs, and counting it in both places is
	# the obvious way to write this wrong.
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
	check(world.cancelled > 0, "orbs still in flight were cancelled")
	check_eq(world.live_orb_count(), 0, "none were left flying at a finished cell")
	check(world.ledger_balanced(), "ledger balanced — nothing counted twice")


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
	check_eq(world.cancelled, 0, "nothing was cancelled")
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
	check_eq(world.restored, 3, "the pump fired from its new cell")
	check_eq(world.delivered, 1, "10 - 12 hops + 3 = 1")
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


# --- Tests: pathing -----------------------------------------------------


func test_path_determinism() -> void:
	var a := MapLoader.load_from_file("res://data/map_01.json")
	var b := MapLoader.load_from_file("res://data/map_01.json")
	check(a != null and b != null, "map loaded")
	if a == null or b == null:
		return
	for from_id in a.cell_ids:
		for to_id in a.cell_ids:
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


func test_locked_cells_are_traversable() -> void:
	# Locked cells cost nothing extra to cross — they simply offer no support.
	# What a cell needs in order to carry an orb is to have been *discovered*,
	# which is a different thing from having been mined.
	var world := _one_orb_world(6)
	for id in [1, 3]:
		check(not world.graph.get_cell(id).is_unlocked, "cell %d is locked" % id)
		check(world.graph.is_discovered(id), "cell %d is discovered anyway" % id)
	_launch_one(world, 0, 5)
	check_eq(world.delivered, 5, "orb crossed the locked cells")


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
	check_eq(shuffled.unlocked_count(), ordered.unlocked_count(), "cells unlocked")
	for id in ordered.graph.cell_ids:
		check_eq(
			shuffled.graph.get_cell(id).unlock_progress,
			ordered.graph.get_cell(id).unlock_progress,
			"cell %d progress" % id
		)
	# A converter's bank is state the deliver phase writes and the produce phase
	# reads a tick later, which is exactly the shape that breaks if the two are
	# ever folded together. Compared cell by cell rather than in aggregate: the
	# totals could agree while the charge sat on the wrong block.
	for id in ordered.graph.cell_ids:
		var block := ordered.graph.get_cell(id).block
		if block != null and block.def.converts():
			check_eq(
				shuffled.graph.get_cell(id).block.charge, block.charge,
				"cell %d charge" % id
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
			_fail("ledger broke at tick %d: produced %d + restored %d != delivered %d + wasted %d + decayed %d + cancelled %d + converted %d + in flight %d"
				% [world.tick_count, world.produced, world.restored, world.delivered,
					world.wasted, world.decayed, world.cancelled, world.converted,
					world.in_flight_value()])
			return
	check(world.produced > 0, "the run actually produced something")
	check(world.restored > 0, "pumps actually fired")
	check(world.cancelled > 0, "route changes actually cancelled orbs")
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
		"and the orange it minted reached a cell only orange can open")


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
	# Priced out of reach on purpose. At the going rate of 30 + id it would
	# unlock a few hundred ticks in, which unaims the upgrader and leaves the
	# rest of the run covering none of this.
	graph.get_cell(15).required_tier = Tiers.ORANGE
	graph.get_cell(15).unlock_cost = 1000000
	# Open the line up before aiming across it — routes do not cross fog.
	_discover_line(graph)
	graph.unlock_cell(17)
	graph.unlock_cell(19)
	graph.unlock_cell(18)
	graph.unlock_cell(10)

	var world := World.new(graph)
	# Odd targets: the scaffold mines the even cells, and value delivered into an
	# already-mined cell is wasted rather than counted, which would make the run
	# far less busy than it looks.
	world.set_target(0, 5)
	# Into the upgrader on 10 rather than at a locked cell: a mined cell with an
	# intake is a legal target, and this is the only aim in the suite's busy world
	# that exercises it.
	world.set_target(6, 10)
	world.set_target(10, 15)
	world.set_target(14, 21)
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

	# Shape assertions are about the map, not about what has been uncovered yet.
	var diameter := 0
	for a in graph.cell_ids:
		for b in graph.cell_ids:
			diameter = maxi(diameter, graph.distance_unrestricted(a, b))
	check(diameter >= 12, "diameter %d is long enough that decay bites" % diameter)

	# At least one pump must sit inside the unaided frontier, or the first one
	# can never be acquired and the map is unwinnable from the opening move.
	for id in graph.cell_ids:
		if graph.get_cell(id).initial_block_id == BlockCatalog.PUMP \
				and world.arrival_along(graph.find_path_unrestricted(start, id)) > 0:
			reachable_pumps += 1
	check(reachable_pumps > 0, "a first pump is minable without already having one")


func test_shipped_map_challenges_are_unique_and_ordered() -> void:
	# `gen_map.py` asserts both of these when it writes the map; this re-checks
	# them on what actually shipped, so a hand-edited or stale map_01.json fails
	# here rather than quietly halving a buff the balance assumes is granted once.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return

	var start := _shipped_start(graph)
	var ids: Array[String] = [
		BlockCatalog.CHALLENGE_SURGE,
		BlockCatalog.CHALLENGE_CURRENT,
		BlockCatalog.CHALLENGE_LENS,
	]

	var previous := -1
	for block_id in ids:
		var found: Array[int] = []
		for id in graph.cell_ids:
			if graph.get_cell(id).initial_block_id == block_id:
				found.append(id)
		check_eq(found.size(), 1, "exactly one %s on the board" % block_id)
		if found.is_empty():
			return
		# Strictly further out than the one before it, so they arrive as
		# milestones rather than all at once.
		var hops := graph.distance_unrestricted(start, found[0])
		check(hops > previous,
			"%s at %d hops is further out than the previous challenge at %d"
				% [block_id, hops, previous])
		previous = hops

		var cell := graph.get_cell(found[0])
		check(cell.is_challenge(), "%s reads as a challenge before it is mined" % block_id)
		check(not cell.block.def.movable if cell.block != null else true,
			"%s is anchored" % block_id)

		# Expensive, measured against an ordinary cell the same distance out
		# rather than against a pinned number — the cost ramp lives in
		# `gen_map.py`, so recomputing it here would be a second copy to drift.
		#
		# The comparison cell must demand the same colour. Orange cells are
		# priced on a divided curve, so a red challenge measured against an
		# orange neighbour would be comparing two different currencies and would
		# pass for the wrong reason.
		var plain_cost := -1
		for id in graph.cell_ids:
			var other := graph.get_cell(id)
			if not other.is_challenge() and id != start \
					and other.required_tier == cell.required_tier \
					and graph.distance_unrestricted(start, id) == hops:
				plain_cost = other.unlock_cost
				break
		check(plain_cost > 0,
			"an ordinary %s cell sits %d hops out to compare against"
				% [Tiers.name_of(cell.required_tier), hops])
		if plain_cost > 0:
			check(cell.unlock_cost > plain_cost,
				"%s costs %d, well above the %d an ordinary cell at %d hops costs"
					% [block_id, cell.unlock_cost, plain_cost, hops])


func test_shipped_map_orange_band_and_upgraders() -> void:
	# `gen_map.py` asserts the gate's shape when it writes the map; this
	# re-checks it on what shipped, so a stale or hand-edited map_01.json fails
	# here rather than quietly shutting the rim behind a colour nothing can make.
	var graph := MapLoader.load_from_file("res://data/map_01.json")
	if graph == null:
		_fail("map_01.json did not load")
		return

	var start := _shipped_start(graph)
	var orange := 0
	var banded := 0
	var upgraders: Array[int] = []
	var deepest_red := 0
	for id in graph.cell_ids:
		var cell := graph.get_cell(id)
		var hops := graph.distance_unrestricted(start, id)
		if cell.required_tier == Tiers.ORANGE:
			orange += 1
			check(hops >= 2, "cell %d is orange only %d hops out" % [id, hops])
			if hops < 8:
				banded += 1
		else:
			deepest_red = maxi(deepest_red, hops)
		if cell.initial_block_id == BlockCatalog.UPGRADER:
			upgraders.append(id)

	check(orange > 0, "the map ships orange cells at all")
	check(banded > 0,
		"orange appears as a scatter before the rim, not only as a wall past it")
	check(not upgraders.is_empty(), "the map ships upgraders to make orange with")

	# The deadlock check, and the one worth having. An orange-gated upgrader can
	# only be paid for in orange, which only an upgrader can make.
	for id in upgraders:
		var cell := graph.get_cell(id)
		check_eq(cell.required_tier, Tiers.RED,
			"cell %d buries an upgrader behind a gate only it could open" % id)
		check(not BlockCatalog.get_def(BlockCatalog.UPGRADER).movable,
			"upgraders are anchored")

	# Red must not reach the rim, or the second tier is decorative: the whole
	# point is that the outer board is shut until a converter is running.
	var radius := 0
	for id in graph.cell_ids:
		radius = maxi(radius, graph.distance_unrestricted(start, id))
	check(deepest_red < radius,
		("the furthest red cell is %d hops out against a radius of %d — orange "
			+ "gates nothing") % [deepest_red, radius])
