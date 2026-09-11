extends SceneTree

## Headless test suite. No external dependency.
##
##   ./run_tests.sh
##
## Exits 1 on any failure.
##
## **Deliberately small.** A test earns its place only when it pins an invariant
## that is invisible on screen and silent when broken. Everything you can see by
## playing — the frontier breathing, the vision ranges, the lance arc, every
## juice event — is checked by looking at it, not from here.

## A test slower than this reports its duration. Not a failure threshold, a
## tripwire: a nested loop over `cell_ids` costs nothing on a line graph and
## minutes on the full board, and it stays green the whole time.
const SLOW_TEST_MS := 250

var _passed := 0
var _failed := 0
var _current := ""
var _current_failed := false
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run_all()
	return true


func _run_all() -> void:
	var tests: Array[String] = [
		"test_ledger_balances",
		"test_tick_order_independent",
		"test_region_wall",
		"test_rate_is_one_divisor",
		"test_rolls_are_pure",
		"test_slots_are_fixed",
		"test_a_dud_frontier_ends_the_run",
		"test_run_one_funds_the_first_purchase",
		"test_ram_spends_only_what_it_lands",
		"test_ram_pool_empties_on_a_full_shot",
		"test_ram_is_affordable_early",
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


## A small board with every buff type unlocked and levelled, so crits fire and
## splits fork inside the runs below rather than sitting at zero chance.
func _busy_world(radius: int = 6) -> World:
	var meta := MetaState.new()
	meta.levels[MetaUpgrades.GENERATOR_CHANCE] = 2
	for id in NodeCatalog.ids():
		meta.levels[MetaUpgrades.unlock_key(String(id))] = 1
		meta.levels[MetaUpgrades.node_level_key(String(id))] = 4
	var graph := HexMap.build(radius)
	HexMap.place_nodes(graph, 99, meta)
	return World.new(graph, meta, 99)


func _run(world: World, ticks: int) -> void:
	for _i in ticks:
		world.tick()


# --- Tests --------------------------------------------------------------


## produced == delivered + wasted + in_flight, every tick, while cells mine,
## crits fire and splits fork. The one invariant that fails silently: a
## behaviour that creates or destroys value without booking it looks fine on
## screen forever.
func test_ledger_balances() -> void:
	var world := _busy_world()
	var crits := 0
	var rams := 0
	for i in 2000:
		world.tick()
		# Ram damage enters as `produced` and lands in the same step, so it has to
		# stay inside the invariant just as an orb does.
		if i % 250 == 249:
			for id in world.graph.cell_ids:
				if world.can_ram_at(id):
					rams += 1 if world.fire_ram(id) else 0
					break
		for event in world.take_delivery_events():
			if event.is_crit:
				crits += 1
		if not world.ledger_balanced():
			_fail("ledger broke on tick %d: produced %d, delivered %d, wasted %d, in flight %d"
				% [i + 1, world.produced, world.delivered, world.wasted,
					world.in_flight_value()])
			return
	check(world.mined_count() > 1, "the board should have grown")
	check(crits > 0, "crits should have fired during the run")
	check(rams > 0, "rams should have fired during the run")


## The same world run with `cell_ids` reversed must reach the same board. This
## is what stops a phase reading state another block writes in the same phase —
## if it starts failing, the fix is a new phase, not a special case.
func test_tick_order_independent() -> void:
	var forward := _busy_world()
	var backward := _busy_world()

	var reversed: Array[int] = []
	for id in backward.graph.cell_ids:
		reversed.append(id)
	reversed.reverse()
	backward.graph.cell_ids = PackedInt32Array(reversed)

	_run(forward, 600)
	_run(backward, 600)

	check_eq(backward.produced, forward.produced, "produced")
	check_eq(backward.delivered, forward.delivered, "delivered")
	check_eq(backward.wasted, forward.wasted, "wasted")
	check_eq(backward.earned, forward.earned, "earned")
	check_eq(backward.generators(), forward.generators(), "generators")
	check_eq(backward.ram_power, forward.ram_power, "ram power")

	for id in forward.graph.cell_ids:
		var a: GraphCell = forward.graph.cells[id]
		var b: GraphCell = backward.graph.cells[id]
		if a.progress != b.progress or a.is_mined != b.is_mined \
				or a.is_generator != b.is_generator:
			_fail("cell %d diverged: %d/%s/%s vs %d/%s/%s"
				% [id, a.progress, a.is_mined, a.is_generator,
					b.progress, b.is_mined, b.is_generator])
			return

	for id in NodeCatalog.ids():
		check_eq(backward.buffs.level_of(String(id)),
			forward.buffs.level_of(String(id)), "buff level %s" % id)


## One region rule for the frontier, the ram and the shop. Getting any of it wrong
## is invisible until a run stalls or runs away.
func test_region_wall() -> void:
	var meta := MetaState.new()
	var graph := HexMap.build(Regions.REGION_LAST_HOP[Regions.RED] + 2)
	var world := World.new(graph, meta, 1)
	world.ram_power = 1_000_000

	# Find a red cell on the region boundary and the orange cell beyond it.
	var red_edge := -1
	var orange := -1
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if cell.region != Regions.ORANGE:
			continue
		for n in cell.neighbor_ids:
			if graph.cells[n].region == Regions.RED:
				red_edge = n
				orange = id
				break
		if orange >= 0:
			break
	check(orange >= 0, "the board should have a red/orange boundary")
	if orange < 0:
		return

	graph.mine_cell(red_edge)

	# 1. An unbought region refuses the frontier and the ram.
	check(not world.is_mineable(graph.cells[orange]),
		"an unbought region must refuse the frontier")
	check(not world.can_ram_at(orange), "an unbought region must refuse the ram")

	# 2. A mined cell in that region does not open it.
	for n in graph.cells[orange].neighbor_ids:
		if graph.cells[n].region == Regions.ORANGE:
			graph.mine_cell(n)
			break
	check(not world.is_mineable(graph.cells[orange]),
		"a mined orange cell must not open orange")

	# 3. The shop block behind the wall sells nothing.
	var crit := MetaUpgrades.unlock_key(NodeCatalog.CRIT)
	check_eq(meta.next_cost(crit), -1, "a closed block must not sell")

	# 4. Buying the region opens it to both, and opens its block.
	meta.levels[MetaUpgrades.region_key(Regions.ORANGE)] = 1
	meta.version += 1
	check(world.is_mineable(graph.cells[orange]) and world.can_ram_at(orange),
		"a bought region must open to the frontier and the ram")
	check(meta.next_cost(crit) > 0, "an open block must sell")


## Power and Pulse are both increased rates, so they sum into one divisor.
## Dividing twice truncates twice and quietly loses a tick — invisible, and it
## makes every buff past the first worth slightly less than it says.
func test_rate_is_one_divisor() -> void:
	var meta := MetaState.new()
	meta.levels[MetaUpgrades.unlock_key(NodeCatalog.PULSE)] = 1
	meta.levels[MetaUpgrades.node_level_key(NodeCatalog.PULSE)] = 5
	var world := World.new(Graph.line(60), meta, 1)
	# Mined through the graph rather than the deliver phase, so the generator
	# flag has to be set by hand — power counts generators, not mined cells.
	for i in 25:
		world.graph.cells[i].is_generator = true
		world.graph.mine_cell(i)

	var power := world.generators()
	var pulse := world.buffs.level_of(NodeCatalog.PULSE) * NodeCatalog.PULSE_PER_LEVEL
	var increased := power * World.RATE_PER_GENERATOR + pulse
	var once := World.BASE_INTERVAL * 100 / (100 + increased)
	var twice := (World.BASE_INTERVAL * 100 / (100 + power * World.RATE_PER_GENERATOR)) \
		* 100 / (100 + pulse)

	check_eq(world.effective_interval(), maxi(World.MIN_INTERVAL, once),
		"the interval must resolve in one division")
	check(once != twice, "the test board must be one where the two differ")


## Every roll is a pure function of its keys. If this ever became a stream,
## order-independence would break intermittently and nothing else would say so.
func test_rolls_are_pure() -> void:
	check_eq(Rng.roll(7, 1, 2, 3), Rng.roll(7, 1, 2, 3), "same keys, same roll")
	check(Rng.roll(7, 1, 2, 3) != Rng.roll(8, 1, 2, 3), "the seed must matter")
	check(Rng.roll(7, 1, 2, 3) != Rng.roll(7, 2, 1, 3), "key order must matter")

	var spread: Dictionary = {}
	for i in 400:
		spread[Rng.roll(1, i)] = true
	check(spread.size() > 380, "rolls must not collide in bulk")

	for i in 200:
		var value := Rng.roll(5, i, 3)
		check(value >= 0 and value < Rng.SCALE, "roll %d out of range" % value)


## The dilution rule: a purchase must never lower your expected run. The board
## decides how many commons, rares and keystones exist; ascension changes only
## which types can fill a slot, so unlocking a rare fills empty slots rather
## than taking commons away.
func test_slots_are_fixed() -> void:
	var poor := MetaState.new()
	var rich := MetaState.new()
	for id in NodeCatalog.ids():
		rich.levels[MetaUpgrades.unlock_key(String(id))] = 1

	var a := HexMap.build(8)
	var b := HexMap.build(8)
	HexMap.place_nodes(a, 42, poor)
	HexMap.place_nodes(b, 42, rich)

	var commons_a := 0
	var commons_b := 0
	var rares_b := 0
	for id in a.cell_ids:
		var cell_a: GraphCell = a.cells[id]
		var cell_b: GraphCell = b.cells[id]
		if cell_a.node_tier() == 1:
			commons_a += 1
		if cell_b.node_tier() == 1:
			commons_b += 1
		if cell_b.node_tier() == 2:
			rares_b += 1
		# A slot the poor board could not fill must be empty, never demoted to a
		# commoner type — that is what makes the guarantee structural.
		if cell_a.has_node():
			check_eq(cell_a.node_tier(), cell_b.node_tier(),
				"cell %d changed rarity on a purchase" % id)

	check_eq(commons_a, commons_b, "unlocking a rare must not cost a common")
	check(rares_b > 0, "the rich board should hold rares")


## ⚠️ Stalling is the ascension trigger, not a bug. At 0% generator chance the
## centre mines its six neighbours, every one is a dud, the centre stops being
## frontier and the run is over. There is deliberately no fallback emitter — one
## used to keep an arbitrary rim cell firing, which made run 1 unreadable.
func test_a_dud_frontier_ends_the_run() -> void:
	# A negative level drives the chance to zero, which `buy()` cannot reach but
	# a test can — every cell mined from here is a dud.
	var meta := MetaState.new()
	meta.levels[MetaUpgrades.GENERATOR_CHANCE] = -9
	var graph := HexMap.build(4)
	var world := World.new(graph, meta, 5)
	check_eq(world.generator_chance(), 0, "the chance should be pinned to zero")

	for i in 6000:
		world.tick()
		if world.frontier().is_empty():
			break

	check(world.frontier().is_empty(),
		"a board of nothing but duds must stall rather than crawl")
	check_eq(world.mined_count(), 7,
		"the centre and its six neighbours, and then nothing more")
	check_eq(world.generators(), 1, "only the seeded centre is a generator")


## The other half of the same rule: the run must pay for the way out of it. A
## stalled run 1 has to bank at least the first level of generator chance, or
## the loop dead-ends with nothing to buy.
func test_run_one_funds_the_first_purchase() -> void:
	var meta := MetaState.new()
	var graph := HexMap.build(4)
	var world := World.new(graph, meta, 5)
	check_eq(world.generator_chance(), 0, "run 1 starts at zero")

	for i in 6000:
		world.tick()
		if world.frontier().is_empty():
			break

	var cost := meta.next_cost(MetaUpgrades.GENERATOR_CHANCE)
	check(world.earned >= cost,
		"a stalled run banked %d but the first generator level costs %d"
			% [world.earned, cost])


## ⚠️ The pool is charged only for what it lands. Overkill used to evaporate the
## whole bank silently — invisible on screen, and sprung hardest by the early
## player with the least to spare.
func test_ram_spends_only_what_it_lands() -> void:
	var world := _busy_world()
	_run(world, 400)

	# A cheap target the pool can overkill: the least-remaining unmined cell.
	var target := -1
	for id in world.graph.cell_ids:
		var cell: GraphCell = world.graph.cells[id]
		if cell.is_mined or not world.is_mineable(cell):
			continue
		if target < 0 or cell.remaining() < world.graph.cells[target].remaining():
			target = id
	check(target >= 0, "the board should have something to ram")
	if target < 0:
		return

	# Forced rather than saved for: the spend semantics are what is under test,
	# and the banking rate has its own test. `_busy_world` buys no ram levels, so
	# damage and pool are the same number here.
	var remaining: int = world.graph.cells[target].remaining()
	check(remaining > 0, "the target should still need something")
	world.ram_power = remaining * 3

	var produced_before := world.produced
	var delivered_before := world.delivered
	var wasted_before := world.wasted
	check(world.fire_ram(target), "the ram should fire")

	check(world.ram_power > 0, "an overkill must leave the pool something back")
	check_eq(world.wasted, wasted_before, "the ram must never waste")
	check_eq(world.produced - produced_before, remaining, "produced by what landed")
	check_eq(world.delivered - delivered_before, remaining, "delivered what landed")
	check(world.ledger_balanced(), "the ledger must survive a partial ram")


## The rounding guard on the refund. A full-strength shot has to leave the pool
## on exactly zero at every upgrade level, or a crumb accrues on every shot.
func test_ram_pool_empties_on_a_full_shot() -> void:
	for level in [0, 6]:
		var meta := MetaState.new()
		meta.levels[MetaUpgrades.RAM_POWER] = level
		for region in range(Regions.ORANGE, Regions.COUNT):
			meta.levels[MetaUpgrades.region_key(region)] = 1
		var graph := HexMap.build(24)
		var world := World.new(graph, meta, 3)
		world.ram_power = 5_000

		# The dearest cell on the board absorbs any pool this test can build.
		var target := -1
		for id in graph.cell_ids:
			var cell: GraphCell = graph.cells[id]
			if not cell.is_mined \
					and (target < 0 or cell.cost > graph.cells[target].cost):
				target = id
		check(world.fire_ram(target), "the ram should fire at level %d" % level)
		check_eq(world.ram_power, 0,
			"a full shot must empty the pool exactly, at level %d" % level)


## The balance guard: mined out to radius 3, the pool has to pay for one cell of
## the ring in front of it.
func test_ram_is_affordable_early() -> void:
	var meta := MetaState.new()
	var graph := HexMap.build(8)
	var world := World.new(graph, meta, 11)

	# Straight through `_mine` rather than `graph.mine_cell`, because the banking
	# is what is under test and only the world half of the pair does it. Mined
	# directly rather than played out: this is about the rate, not about whether
	# the frontier could have got there.
	for id in graph.cell_ids:
		if graph.cells[id].hops <= 3:
			world._mine(graph.cells[id])

	var hop_four_cost := HexMap.hop_costs(4)[4]
	check(world.ram_damage() >= hop_four_cost,
		"radius 3 banked %d, which cannot pay for a hop-4 cell at %d"
			% [world.ram_damage(), hop_four_cost])
