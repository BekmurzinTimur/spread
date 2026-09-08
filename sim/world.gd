class_name World
extends RefCounted

## The whole simulation. Pure data and integer arithmetic — no Godot nodes, no
## floats in the economy, no RNG. Runs headless.
##
## A tick has four phases, and each phase completes across all entities before
## the next begins. That is what makes iteration order irrelevant: stats resolve
## from scratch, generators read only their own timer, delivery writes only
## unlock progress, and nothing in the produce phase reads it. No double-buffering
## needed; test `tick_order_independent` holds this honest.

const TICK_HZ := 10
const TICK_SECONDS := 1.0 / float(TICK_HZ)

## Ticks to cross one edge. At 10 Hz this is one second per hop.
const TICKS_PER_HOP := 10

## Value of a freshly emitted orb. Deliberately *not* a ceiling: pumps add a
## percentage of it and stack, so a well-supported orb arrives worth more than it
## launched.
## Reach is something the player builds up, not a cap they top back up to.
const ORB_START_VALUE := 10

## Value an orb loses on entering each new cell it *travels through*. The
## destination is not one of them: an orb is delivered into its final cell rather
## than crossing it, so a cell next door receives the full launch value and
## arrival is `value - (hops - 1)`. This is the same rule that stops a pump firing
## on a target, applied to the other half of what entering a cell costs.
const DECAY_PER_HOP := 1

## How many waypoints one route may be bent through.
##
## A limit on how complicated a route may get, not an economy constant. It used
## to be the latter: a route could fold back through a corridor of pumps and
## collect every one of them again, each lap booking legitimately under
## `restored` where the ledger could never catch it, so this cap was the only
## thing bounding how much value one distant cell could be handed. That hole is
## closed at the source now — `Graph.find_chain` refuses a route that crosses
## itself — which leaves this free to be tuned for how much route-drawing the
## board should ask of a player.
const MAX_WAYPOINTS := 4

## Floor on a producer's effective interval — a **divide-by-zero guard, not a
## balance cap**. An interval of 0 is a generator emitting every tick and a
## division by zero in the view's cooldown arc, and this is what stops it.
##
## It used to be 5, and it used to bite: spheres subtracted flat ticks, so four
## of them hit the floor and every one after that was worth exactly nothing.
## Rates divide instead (`StatBonus.apply_rate`), so the curve approaches this
## without reaching it — on a base of 20 it takes +1900% to touch. Nothing on
## the board can currently get near it, which is the point.
const MIN_PRODUCE_INTERVAL := 1

## Ceiling on what one orb may be worth, and a **legibility guard, not a balance
## cap**. Amplifiers compound, so an orb's value is the one number in the economy
## with no natural bound; everything else is a sum of small integers. int64 has
## ample headroom — this sits three orders of magnitude under the board's dearest
## cell — so nothing here is protecting arithmetic. What it protects is the HUD's
## `%d`, the splash's size ratio, and a player's ability to read what landed.
##
## Applied through `World.clamp_orb_value()` and nowhere else, so the simulation
## and the aim preview cannot clamp differently.
const MAX_ORB_VALUE := 1_000_000_000

## Floor on a converter's effective cost, and the same kind of guard: a
## conversion that cost nothing would mint an orange orb every tick out of an
## empty bank.
const MIN_UPGRADE_COST := 1

var graph: Graph
var orbs: Array[Orb] = []
var tick_count: int = 0

## Whether unpinned aimable blocks point themselves at the nearest cell they can
## open. Read-only from outside; `set_auto_aim()` is the way in.
##
## The one piece of player-facing state that lives here rather than on `Main`,
## and the reason is the rule at the top of `architecture.md`: it writes block
## targets, so it is a simulation command and not a view mode. Keeping it in the
## scene tree would put a headless-untestable branch in front of `set_target`.
var auto_aim: bool = false

# --- Value ledger ---
# Invariant, checked by ledger_balanced() and asserted in tests:
#   produced + restored
#     == delivered + wasted + decayed + converted + burned + in_flight
var produced: int = 0    # value emitted by generators
var restored: int = 0    # value added back by pumps
var delivered: int = 0   # value that counted toward an unlock
var wasted: int = 0      # arrived but had nowhere useful to go
var decayed: int = 0     # lost to travel
var converted: int = 0   # consumed by an upgrader to mint a higher tier
var burned: int = 0      # consumed by an upkeep block to hold a global bonus up

# Diagnostic, not part of the value ledger: an evaporating orb is already at
# zero value, so its loss is fully accounted for under `decayed`.
var evaporated_orbs: int = 0

## Deliveries recorded for the view since it last drained. Write-only from the
## simulation's side: nothing in `sim/` ever reads it back, which is what keeps
## iteration order from leaking out of presentation and into the economy.
##
## Deliberately outside the order-independence contract. The list is order
## dependent in its *contents*, not just its order — two orbs of different tiers
## landing on a cell with 3 remaining, each worth 5, record (3, first) and
## (0, second), so which tier gets the 3 depends on which arrives first. No sort
## recovers that, and sorting would imply a property this only half has. The
## invariant that does hold, and that the tests pin, is that the amounts sum to
## `delivered`.
const MAX_DELIVERY_EVENTS := 256
var _delivery_events: Array[DeliveryEvent] = []

var _spawn_queue: Array[Orb] = []
var _has_dead: bool = false

## The radiated field: cell id -> StatBonus, for cells some sphere reaches. Cells
## nobody reaches are simply absent, so this stays small.
##
## Rebuilt wholesale by `_resolve_stats()` and never edited in place. Adjusting it
## incrementally — adding a sphere's deltas on placement and subtracting them on
## removal — is the obvious optimisation and it is wrong: every missed edge case
## leaves a permanent error in the table, and the drift is silent because there is
## nothing to compare against.
var _field: Dictionary = {}

## The board-wide bonuses, summed across every challenge the player has mined.
## The other half of what `_resolve_stats()` builds, and rebuilt wholesale beside
## `_field` for the same reasons.
##
## Kept apart from `_field` rather than folded into it as a bonus every cell
## carries, because the two are invalidated by different things and read at
## different times: a global is read by `emit_orb` with no cell in hand at all.
var _global: GlobalBonus = GlobalBonus.new()

## Set whenever something could have moved a sphere or changed which cells hold
## blocks. Read through `_ensure_stats()`, so the table is rebuilt at most once
## per change rather than once per query.
var _stats_dirty: bool = true

## The `graph.unlock_version` the field was last built against. Swaps go through
## `swap_blocks` and can set the flag directly, but mining has callers outside
## World — MapLoader's starting cells, the tests' `_place()` — so the flag alone
## would miss them. Comparing the version catches every one, whoever called it.
var _stats_version: int = -1

## The `graph.topology_version` the field was last built against. Separate from
## the above because a teleport link and a mined cell are different events — see
## `_ensure_stats()`.
var _topology_version: int = -1

## Teleport groups currently wired, `link_group -> [lo_id, hi_id]`. The record of
## what `resolve_links()` last did, so it can take an edge down again when an end
## moves.
var _links: Dictionary = {}


func _init(p_graph: Graph) -> void:
	graph = p_graph
	# The map may start with cells already mined, and two of them may be the ends
	# of a teleport pair. Nothing else would notice: `MapLoader` mines through the
	# graph directly, so the two event sites below never fire for a starting cell.
	resolve_links()


# --- Simulation ---------------------------------------------------------


func tick() -> void:
	tick_count += 1
	_phase_upkeep()
	_phase_resolve_stats()
	_phase_produce()
	_phase_transport()
	_phase_deliver()

	# Appended after transport, so an orb never moves on the tick it is born.
	if not _spawn_queue.is_empty():
		orbs.append_array(_spawn_queue)
		_spawn_queue.clear()

	if _has_dead:
		_compact_orbs()


## Phase 0. Burn each upkeep block's trickle and update its latch.
##
## First, and outside the stat pass, for two separate reasons — both load-bearing:
##
## - It **cannot** live in `_resolve_stats()`. That has to stay a pure read of
##   board state, because it is rebuilt lazily from every effective-stat read,
##   including the HUD's queries between ticks. A resolve that also drained would
##   charge the player once per redraw.
## - It **cannot** live in `_phase_produce()` either. A generator asked to produce
##   before the upkeep block drained would read a different interval than one
##   asked after, and `test_tick_order_independent` would start failing on which
##   way `cell_ids` happened to be iterated.
##
## **This phase must not read an effective stat.** It reads only each block's own
## charge and its def's flat constants, so order within the phase is free. A drain
## that consulted `effective_*` would resolve `_global` from a `fuelled` set that
## later blocks in this same phase are still flipping — the Lens-before-sphere
## ordering bug, one level down. "Make the drain cheaper near a sphere" is the
## obvious future edit that would break this silently.
##
## The bank it reads was last written by the *previous* tick's deliver phase, so
## upkeep satisfaction is computed from the previous tick — the same latency shape
## as the upgrader's deliver-then-produce split.
##
## Touches no ledger bucket: the fuel was booked to `burned` when it arrived.
func _phase_upkeep() -> void:
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if not cell.is_unlocked or cell.block == null:
			continue
		var block := cell.block
		if not block.def.burns_upkeep():
			continue

		# On at the reserve, off only at empty. The gap between the two is the
		# hysteresis: a block fed around its drain rate sits wherever it already
		# was instead of flickering the whole board's generators.
		#
		# The two halves straddle the drain on purpose. Lighting up is judged on
		# the bank the player actually filled, *before* this tick spends from it —
		# otherwise a bank topped up to exactly the reserve would be one short the
		# instant it was measured and could never light at all. Going dark is
		# judged after, because that is when the money has run out.
		var was := block.fuelled
		if not block.fuelled and block.charge >= block.def.upkeep_reserve:
			block.fuelled = true

		block.charge = maxi(0, block.charge - block.def.upkeep_drain)

		if block.fuelled and block.charge <= 0:
			block.fuelled = false
		if block.fuelled != was:
			mark_stats_dirty()


## Phase 1. Everything downstream reads effective stats, so the field has to be
## correct before the first generator is asked to produce.
##
## Ahead of Produce rather than folded into it because a sphere's contribution is
## not a thing that *happens* on a tick — it is a condition the rest of the tick
## runs under. Resolving it inside the produce loop would make a generator's
## interval depend on whether its sphere was iterated first, which is exactly the
## order-dependence phase separation exists to prevent.
func _phase_resolve_stats() -> void:
	_ensure_stats()


## Rebuild the field from scratch if anything has moved since the last look.
##
## Called from the phase above and from every effective-stat read, because the
## view queries stats *between* ticks: the HUD and the aim preview both run
## `projected_arrival` every frame, and after the player swaps a sphere a
## tick-only rebuild would quote the old numbers for up to a tenth of a second —
## visible, and worse, disagreeing with what the board draws.
##
## Resolving mid-tick is safe for the same reason clearing the path cache
## mid-tick is: only mining and swapping dirty this, mining happens in the deliver
## phase, and nothing in deliver reads a stat. So a rebuild can never change a
## result within the tick it happens in — only the next one.
## `topology_version` is checked alongside `unlock_version` because a sphere's
## field is walked over `neighbor_ids`, so a teleport link genuinely moves it: two
## cells thirty hops apart become one hop apart and the field reaches through.
## That is intended — they are adjacent now, and pretending otherwise would need
## the field walk to know which edges are "real" — but it does mean the stats
## table goes stale on a link forming or an end being swapped, which is exactly
## what this second comparison catches.
func _ensure_stats() -> void:
	if not _stats_dirty and _stats_version == graph.unlock_version \
			and _topology_version == graph.topology_version:
		return
	_resolve_stats()
	_stats_dirty = false
	_stats_version = graph.unlock_version
	_topology_version = graph.topology_version


## Bring the graph's teleport edges into line with where the teleporters actually
## stand. Idempotent, so it is safe to over-call.
##
## **Event-driven, never per-tick, and that distinction is load-bearing.** Called
## from the two places that can move a teleporter — a cell being mined in the
## deliver phase, and `swap_blocks` — rather than scanned each tick. A per-tick
## rebuild would clear `_path_cache` every tick whether or not anything moved,
## defeating the cache outright, and it would put topology *inside* the tick where
## `test_tick_order_independent` would have something to say about it. Driven by
## events, a link only ever changes on a player action or a mine, so the tick
## never sees one form.
##
## Order-independent regardless: a group's pair is sorted before it is recorded, so
## whichever end `cell_ids` reaches first, the same edge comes out.
##
## A group links only when **both** ends are mined, which is also what makes the
## discovery question answer itself: a block exists only in a mined cell, and a
## mined cell is discovered, so the edge can never join anything the player has
## not already uncovered and `is_discovered()` needs no change at all.
func resolve_links() -> void:
	var desired: Dictionary = {}
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if not cell.is_unlocked or cell.block == null or not cell.block.def.links():
			continue
		var group: int = cell.block.def.link_group
		var ends: Array = desired.get(group, [])
		ends.append(id)
		desired[group] = ends

	# Take down what moved before putting up what replaced it, so a pair that
	# swapped with each other does not briefly look unchanged.
	for group in _links.keys():
		var ends: Array = desired.get(group, [])
		ends.sort()
		if ends.size() != 2 or ends != _links[group]:
			var old: Array = _links[group]
			graph.unlink_cells(old[0], old[1])
			_links.erase(group)

	for group in desired:
		var ends: Array = desired[group]
		# Exactly two. A group with one end mined is not yet a link, and a group
		# with three would be a map error rather than something to guess at.
		if ends.size() != 2 or _links.has(group):
			continue
		ends.sort()
		graph.link_cells(ends[0], ends[1])
		_links[group] = ends

	# A link moves a sphere's field as surely as moving the sphere would, because
	# the field walk follows `neighbor_ids`. `_ensure_stats` also compares
	# `topology_version`, so this is belt and braces rather than the only guard.
	mark_stats_dirty()


## Anything that could have moved a sphere, or changed which cells hold blocks.
## Cheap to over-call — the rebuild is deferred to the next read — so callers
## should err toward calling it.
func mark_stats_dirty() -> void:
	_stats_dirty = true


## Sum every mined challenge into `_global`, then walk every sphere's field
## outward and sum what lands on each cell.
##
## Order-independent by construction: both results are sums of integers, so they
## converge to the same tables however `cell_ids` is iterated. That is what lets
## `test_tick_order_independent` cover this phase for free.
##
## **The two sub-passes are ordered, and the order is forced.** A Lens widens
## every sphere's radius, so the field cannot be built until the globals are
## known — build them the other way round and whether a sphere reached three hops
## would depend on whether the Lens happened to be iterated first, which is
## exactly the order-dependence phase separation exists to prevent. Within each
## sub-pass order is still free.
##
## The walk ignores discovery and lock state. A sphere's field is a fact about the
## board, not about what the player has uncovered — making it fog-dependent would
## add an invalidation edge to mining and let an unrelated dig several hops away
## make a bonus blink on and off. Locked cells hold no Block, so they absorb the
## field harmlessly.
##
## Both sub-passes skip locked cells at the *source*: a challenge still buried
## grants nothing, exactly as a buried sphere radiates nothing. Mining it is the
## whole transaction, so it would be strange for the board to pay out first.
func _resolve_stats() -> void:
	_global = GlobalBonus.new()
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if not cell.is_unlocked or cell.block == null:
			continue
		var def := cell.block.def
		if not def.grants_global():
			continue
		# Asked of the *block*, not the def: a challenge grants unconditionally
		# once mined, but an upkeep block grants only while its latch is on. Pure
		# read of a flag phase 0 already settled, so this stays order-independent.
		if not cell.block.grants_global_now():
			continue
		_global.add(def.global_orb_value_bonus, def.global_field_restore_percent,
			def.global_field_radius_percent, def.global_rate_percent)

	_field = {}
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if not cell.is_unlocked or cell.block == null:
			continue
		var def := cell.block.def
		if not def.radiates():
			continue
		for target in graph.cells_within(id, _field_radius(def)):
			var bonus: StatBonus = _field.get(target)
			if bonus == null:
				bonus = StatBonus.new()
				_field[target] = bonus
			bonus.add(def.field_rate_percent, def.field_restore_percent,
				def.field_charge_percent)


## This def's field radius after any Lens, without ensuring stats first.
##
## Private and unguarded because `_resolve_stats()` calls it *while* building the
## tables: `_ensure_stats()` only clears the dirty flag after it returns, so
## going through the public wrapper here would recurse forever. `_global` is
## already final by the time the field sub-pass runs, which is what makes reading
## it directly correct rather than merely convenient.
func _field_radius(def: BlockDef) -> int:
	return GlobalBonus.scale_percent(def.field_radius, _global.field_radius_percent)


func _phase_produce() -> void:
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if not cell.is_unlocked or cell.block == null:
			continue
		cell.block.def.behavior.on_produce(self, cell, cell.block)


func _phase_transport() -> void:
	for orb in orbs:
		if orb.dead:
			continue

		orb.ticks_in_hop += 1
		if orb.ticks_in_hop < TICKS_PER_HOP:
			continue

		orb.ticks_in_hop = 0
		orb.hop_index += 1

		# The final cell charges nothing and grants nothing: an orb is delivered
		# into it rather than travelling through it. Skipping the whole step
		# rather than only the pump is what makes a neighbour receive the full
		# launch value, and it also means an orb that survived every cell on the
		# way always arrives with something.
		if orb.is_at_end():
			continue

		# Decay first, then the death check, then any pump. An orb entering a
		# pump cell on its last point of value does not make it to the pump.
		var loss := mini(DECAY_PER_HOP, orb.value)
		orb.value -= loss
		decayed += loss

		if orb.value <= 0:
			orb.dead = true
			_has_dead = true
			evaporated_orbs += 1
			continue

		# Nothing acts on an orb's *destination*, whenever it is reached — not
		# merely when it is the last cell of the route. `is_at_end()` above is an
		# index test, and a waypointed route may cross its own destination on the
		# way out to a waypoint, so the rule has to be stated about the cell
		# rather than about the position in the walk.
		#
		# Dormant rather than dead, like the wrong-colour delivery branch. No
		# block today turns this into free value: the only destinations that count
		# a delivery are a locked cell, which holds no block, and a mined
		# converter, which has no `on_orb_pass`. What is observable today is a
		# pump on a crossed destination inflating `restored`. It is closed here
		# rather than the day a type lands with both a pass hook and an intake,
		# because that bug would be a silent economy leak rather than a crash.
		#
		# A no-op on a shortest path, which never revisits a cell.
		if orb.path[orb.hop_index] == orb.destination_id():
			continue

		var cell := graph.get_cell(orb.path[orb.hop_index])
		if cell != null and cell.is_unlocked and cell.block != null:
			cell.block.def.behavior.on_orb_pass(self, cell, orb)


func _phase_deliver() -> void:
	for orb in orbs:
		if orb.dead or not orb.is_at_end():
			continue
		# Marked before delivering rather than after. This used to be load-bearing:
		# delivering can mine the cell, and the unaim that followed would sweep
		# this still-live orb into a cancel and count it twice. Nothing cancels
		# any more, so the order is now free either way — kept because nothing in
		# `_deliver` reads `dead` and an orb that has delivered is plainly done.
		orb.dead = true
		_has_dead = true
		_deliver(orb)


func _deliver(orb: Orb) -> void:
	# Before anything reads `orb.value` — the missing-cell branch included, so
	# every path out of this function sees the same number and the amplifier
	# cannot be skipped by a route that ends nowhere.
	_apply_amplifiers(orb)

	var cell := graph.get_cell(orb.destination_id())
	if cell == null:
		wasted += orb.value
		return

	if cell.is_unlocked:
		# A mined cell absorbs nothing on its own — but a block standing on it
		# may. This is the exact counterpart of `on_orb_pass`: that hook sees
		# every orb except the one stopping here, this one sees only that orb.
		# Everything without an intake returns 0 and the value wastes, which is
		# what every type but the upgrader still does.
		var taken := 0
		if cell.block != null:
			taken = cell.block.def.behavior.on_orb_deliver(self, cell, orb)
		if taken > 0:
			_record_delivery(cell.id, taken, orb.tier)
		wasted += orb.value - taken
		return

	# Wrong colour: the cell will not take it. Dormant rather than dead — the
	# only way to aim at a cell is through `set_target`, which refuses a tier
	# mismatch up front, and a cell's required tier never changes afterwards. It
	# stays because the ledger's correctness cannot rest on a guarantee made two
	# calls away, and because a future emitter that picks its own tier at run
	# time would reach this line on its first bug.
	if not cell.accepts_tier(orb.tier):
		wasted += orb.value
		return

	var used := mini(cell.unlock_remaining(), orb.value)
	cell.unlock_progress += used
	delivered += used
	wasted += orb.value - used
	# Recorded before the unlock cascade below, so events stay in the order the
	# things they describe happened in. A future cascade event — a "block went
	# idle" flash, say — then sorts after the delivery that caused it without
	# anyone having to remember why.
	_record_delivery(cell.id, used, orb.tier)
	if cell.unlock_progress >= cell.unlock_cost:
		# Through the graph, not the cell: mining uncovers this cell's neighbours
		# and so changes which routes exist.
		graph.unlock_cell(cell.id)
		# Mining installs whatever the map buried, which may be a sphere lighting
		# up a field, or an ordinary block that now stands inside one.
		mark_stats_dirty()
		# And it may be the second end of a teleport pair, which changes the edge
		# set. Safe here for the reason clearing the path cache here is safe:
		# nothing left in the deliver phase reads a route, and produce — the phase
		# that does — already ran.
		resolve_links()
		_unaim_everything_targeting(cell.id)
		# Last, and after the unaim rather than before it: mining is both the
		# only thing that changes which cell is nearest-and-still-locked *and*
		# the thing that releases the blocks that were feeding this one. Run
		# ahead of the unaim, the blocks it just freed would still be holding
		# targets pointing here and it would leave them alone.
		apply_auto_aim()


## A mined cell consumes nothing, so anything still aimed at it is pouring its
## whole output into waste. Mining therefore releases every block feeding the
## cell, and they idle until the player finds them something else to do — which
## is what the HUD's idle counter is for.
##
## **Only the targets are cleared. Orbs already in the air are left alone**, and
## land on the cell they were launched at — which is now mined, so they do
## nothing and their value wastes. An orb is committed once launched: it belongs
## to the board rather than to the route behind it, and calling it back would
## destroy value the player can watch travelling.
##
## Runs in the deliver phase, and order still does not matter — see the
## order-independence note in `architecture.md`. `delivered` is capped by
## `unlock_remaining()` and everything else wastes, so the split between the two
## is the same whichever orb lands first.
func _unaim_everything_targeting(cell_id: int) -> void:
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if cell.block == null:
			continue
		if cell.block.target_id == cell_id:
			cell.block.clear_target()
		# A ported block may be feeding the mined cell from one of several
		# outputs, and only that one should go. Dropping the whole rotation
		# because one destination finished would cost the player every other line
		# they had drawn from that distributor.
		cell.block.remove_port(cell_id)


func _compact_orbs() -> void:
	var alive: Array[Orb] = []
	for orb in orbs:
		if not orb.dead:
			alive.append(orb)
	orbs = alive
	_has_dead = false


# --- Called by behaviours -----------------------------------------------


## Queue an orb from `from_id` to `to_id`. Silently does nothing if there is no
## route through discovered ground, so an unreachable target simply idles rather
## than leaking value.
## Returns whether an orb was actually queued, so a caller can tell "I fired"
## from "I had nowhere to fire" — the difference between a generator worth
## pulsing on the board and one quietly doing nothing.
## `value` overrides what the orb launches with. Left at -1 — which every
## generator and every upgrader does — the orb is worth `effective_orb_value()`,
## so a Surge raises it and nothing else has to know. A caller that passes a
## number is saying *this orb is worth what I banked*, which is the compressor and
## currently nothing else.
##
## Two consequences of overriding, both deliberate rather than gaps:
##
## - `launch_value` is stamped at the same number, so every pump on the route
##   restores a percentage **of that**. A pump corridor under a compressed orb is
##   worth far more per hop than the same corridor under an ordinary one. That is
##   the launch-value rule working as designed.
## - `effective_orb_value()` is bypassed, so **a Surge does not touch an overridden
##   orb.** A Surge raises what a *generator* launches with; a compressor launches
##   with what was routed into it.
func emit_orb(from_id: int, to_id: int, tier: int, via := PackedInt32Array(),
		value := -1) -> bool:
	# Resolved fresh at every emission rather than remembered, so a route bent
	# through waypoints picks up any shortcut the fog has since uncovered.
	var path := resolve_route(from_id, to_id, via)
	if path.size() < 2:
		return false

	# Effective, not the constant: a mined Surge raises what every generator on
	# the board launches with. Booked under `produced` at the same value it was
	# created with, so the ledger sees exactly what entered the economy — and that
	# stays true of an overridden value, which is booked at whatever it actually
	# was rather than at what a generator would have emitted.
	var launched := effective_orb_value() if value < 0 else value

	var orb := Orb.new()
	orb.value = launched
	# Stamped here and never again: every pump on the route is a percentage of
	# this number, so it has to be the value the orb was actually born with.
	orb.launch_value = launched
	orb.tier = tier
	orb.path = path
	orb.source_id = from_id
	_spawn_queue.append(orb)
	produced += launched
	return true


## Uncapped, so pumps stack: an orb crossing three of them is worth three times
## the restore more than one that crossed none. Without a ceiling the whole
## amount always lands, so `restored` takes it directly.
func restore_orb(orb: Orb, amount: int) -> void:
	if amount <= 0:
		return
	orb.value += amount
	restored += amount


## Spend the amplifiers this orb counted during transport, once, at delivery.
##
## **The one compounding term in the economy, and the one place it resolves.**
## `AmplifierBehavior` deliberately does no arithmetic of its own: multiplication
## does not commute with the pump's additive restore, so scaling an orb where the
## amplifier was met would make arrival depend on the order the route met its
## blocks. Counted there and spent here, the result is a function of
## `(value, amplifiers)` alone — order-independent by construction, which is what
## lets the ledger and `test_tick_order_independent` stay quiet about it.
##
## **No new bucket.** An amplifier creates value in transport exactly as a pump
## does, so the gain goes through `restore_orb` and books under `restored`. This
## is the *"a mechanic that changes how much flows through an existing path is
## exempt"* rule, and going through `restore_orb` rather than writing `orb.value`
## directly is what keeps the two halves — the value and the booking — from ever
## drifting apart.
##
## Steps rather than one `pow()`: the arithmetic is integer, and truncating once
## per amplifier is the only way `arrival_along()` can promise the same number
## without duplicating a rounding rule. `MAX_ORB_VALUE` clamps the result for
## legibility rather than correctness — int64 has ample headroom, but an orb worth
## more than the board's dearest cell tells the player nothing.
##
## ⚠️ **The percentage is one economy-wide number, not a per-def one.** The orb
## carries a *count*, so by the time the exponent is spent there is no def left to
## read it from — which is the price of the order-independence above, and cheap,
## because a second amplifier strength would have to compound against the first
## and there is nowhere left to say in what order. `BlockDef.amplify_percent`
## still declares it, so `amplifies()` stays an id-free predicate and the HUD has
## a number to print; `test_amplifiers_share_one_percent` is what stops the two
## drifting apart the day a second amplifying def is registered.
func _apply_amplifiers(orb: Orb) -> void:
	if orb.amplifiers <= 0:
		return
	var running := orb.value
	for _i in orb.amplifiers:
		var bumped := clamp_orb_value(
			running * (100 + BlockCatalog.AMPLIFY_PERCENT) / 100)
		restore_orb(orb, bumped - running)
		running = bumped


## The legibility ceiling on a single orb's value, applied wherever amplifiers
## compound. Shared by `_apply_amplifiers` and `arrival_along` so the preview and
## the simulation cannot clamp differently —
## `test_projected_arrival_matches_reality` is what would catch it if they did.
static func clamp_orb_value(value: int) -> int:
	return mini(value, MAX_ORB_VALUE)


## Book value taken out of circulation by a converter. The orb it came from is
## already being retired by the deliver phase, so this only has to record the
## sink; the higher tier it pays for enters separately through `emit_orb`.
##
## A behaviour that absorbs must call this. Returning a non-zero amount from
## `on_orb_deliver` without it leaks value straight past the ledger, and
## `test_value_conservation` is what says so.
func absorb_value(amount: int) -> void:
	if amount <= 0:
		return
	converted += amount


## Book value taken out of circulation to fuel an upkeep block. The mirror of
## `absorb_value`, and a separate bucket because it buys something different:
## converted value comes back as a higher tier, burned value does not come back
## at all.
##
## Booked at *intake*, the moment the orb lands, not tick by tick as the bank
## drains. So the fuel bank sits outside the ledger entirely and the drain touches
## no bucket at all.
##
## The fuel bank is uncapped, and that is a **design choice, not a constraint**.
## This note used to claim a cap was impossible here — that the overshoot would
## have to split between `burned` and `wasted` on a path returning a single
## number. The upgrader's cap disproved it: the behaviour returns what it took,
## `_deliver` wastes the difference, and the split falls out for free. So the same
## mechanism is available the day upkeep wants it. It does not: over-feeding an
## upkeep block is how the player buys run time, and a battery with a lid is just
## a smaller battery.
func burn_value(amount: int) -> void:
	if amount <= 0:
		return
	burned += amount


# --- Delivery events, for the view --------------------------------------


## Note a delivery so the view can animate it. Nothing here affects the economy:
## `used` has already been booked under `delivered` by the caller.
##
## Oldest-first eviction at the cap. Overflow means either nobody is draining —
## headless, so nothing is watching and which end goes is moot — or a frame
## swallowed hundreds of ticks, in which case the newest events are the ones
## nearest the frame about to be drawn. Showing the *oldest* 256 of a catch-up
## batch would spray numbers describing a board state that is already gone.
func _record_delivery(cell_id: int, amount: int, tier: int) -> void:
	if amount <= 0:
		return
	if _delivery_events.size() >= MAX_DELIVERY_EVENTS:
		_delivery_events.remove_at(0)
	_delivery_events.append(DeliveryEvent.new(cell_id, amount, tier, tick_count))


## Hand over everything recorded since the last call, and start a new list.
##
## Drained rather than cleared each tick, because a frame can run many ticks
## before it draws: three or so at speed 16, and up to MAX_TICKS_PER_FRAME after
## a stall. Clearing per tick would show the player one delivery in three at high
## speed. The buffer accumulates across ticks and only the reader empties it.
##
## Exactly one caller — `Main`, once a frame. A second drainer would silently
## starve the first.
func take_delivery_events() -> Array[DeliveryEvent]:
	var events := _delivery_events
	_delivery_events = []
	return events


# --- Player commands ----------------------------------------------------


## Blocks cannot be created or destroyed — only moved, and only the movable ones.
## Two mined cells may exchange contents at any distance; swapping against an
## empty cell is a move.
##
## An anchored block refuses the swap from either side: a generator can be
## neither picked up nor displaced by something arriving.
func can_swap(a_id: int, b_id: int) -> bool:
	if a_id == b_id:
		return false
	var a := graph.get_cell(a_id)
	var b := graph.get_cell(b_id)
	if a == null or b == null:
		return false
	if not a.is_unlocked or not b.is_unlocked:
		return false
	if a.block != null and not a.block.def.movable:
		return false
	if b.block != null and not b.block.def.movable:
		return false
	# Trading two empty cells is a no-op, not a move.
	return a.block != null or b.block != null


func swap_blocks(a_id: int, b_id: int) -> bool:
	if not can_swap(a_id, b_id):
		return false

	var a := graph.get_cell(a_id)
	var b := graph.get_cell(b_id)

	# Nothing is done about orbs already in flight from either cell, and that is
	# the rule rather than an oversight: an orb is committed once launched. A
	# movable emitter landing later changes nothing here — its orbs would keep
	# flying too.
	var moved := a.block
	a.block = b.block
	b.block = moved

	# Either end may have been a sphere, and the block that arrives may now be
	# standing in a field the one that left was not. Dirtied unconditionally
	# rather than only when a sphere is involved: the check is two lookups and
	# getting it wrong leaves a stale bonus that nothing else would catch.
	mark_stats_dirty()

	# Either end may also have been half of a teleport pair, which makes this the
	# one player command that changes the *shape* of the graph rather than only
	# what stands on it. Resolved before the target check below, because moving a
	# link can make a route resolve that did not — a block must not be unaimed
	# against a topology that is one line out of date.
	resolve_links()

	# A block can land on the very cell it was aiming at. set_target refuses a
	# self-target on the way in; the same invariant has to hold on the way out.
	# Dormant for the same reason, and kept for the same one.
	_drop_invalid_target(a)
	_drop_invalid_target(b)
	_drop_invalid_ports(a)
	_drop_invalid_ports(b)

	# Aimable blocks are all anchored, so nothing that auto-aim manages moved
	# here — but a teleporter did, and the edge it carries changes what is
	# nearest for every block on the board. Recomputing wholesale is what makes
	# that cost one call rather than a rule about which swaps matter.
	apply_auto_aim()
	return true


func _drop_invalid_target(cell: GraphCell) -> void:
	if cell.block == null or not cell.block.has_target():
		return
	var target_id := cell.block.target_id
	# The whole chain, not just the endpoints: a block that moved may still reach
	# its target while no longer reaching one of its waypoints. Target and via go
	# together — a route silently repaired to something the player did not draw is
	# worse than an idle block, which the indicator will at least surface.
	if target_id == cell.id \
			or resolve_route(cell.id, target_id, cell.block.route_via).size() < 2:
		cell.block.clear_target()


## Add an output to a ported block, or drop the one already feeding this cell.
##
## **A toggle, which is what makes the gesture need no mode.** Right-click a cell
## the distributor does not feed and it becomes an output; right-click one it
## already feeds and that output goes. There is nothing to arm and nothing to
## cancel, which is the same standard the aim and swap gestures are held to.
##
## Returns whether anything changed, so the caller can clear a half-drawn waypoint
## chain on success exactly as `set_target_batch` lets it.
##
## **It adds no verdict of its own.** Legality is `can_aim_at`, the single answer
## the aim preview draws — a second rule here is how the board starts offering an
## output the simulation then refuses. What it adds is the port *cap*, which is
## not a legality question but a capacity one: a full block refuses a new output
## and says so by returning false.
func toggle_port(cell_id: int, target_id: int, via := PackedInt32Array()) -> bool:
	var cell := graph.get_cell(cell_id)
	if cell == null or cell.block == null or not cell.block.def.has_ports():
		return false
	if target_id == cell_id or target_id == -1:
		return false

	# Removal first, and without consulting `can_aim_at`. A port whose destination
	# has since become unroutable must still be removable, or the player is left
	# holding an output they can neither use nor clear.
	if cell.block.remove_port(target_id):
		return true

	if cell.block.ports.size() >= cell.block.def.max_ports:
		return false
	var route := normalize_via(cell_id, target_id, via)
	if not can_aim_at(cell_id, target_id, route):
		return false
	cell.block.ports.append(BlockPort.new(target_id, route))
	return true


## How many of these cells now feed `target_id`. The batch counterpart of
## `toggle_port`, in the shape `set_target_batch` established — a loop over the
## single command, with no verdict of its own and partial success as the policy.
func toggle_port_batch(cell_ids: PackedInt32Array, target_id: int,
		via := PackedInt32Array()) -> int:
	var changed := 0
	for id in cell_ids:
		if toggle_port(id, target_id, via):
			changed += 1
	return changed


## The ported counterpart of `_drop_invalid_target`, on the same argument: an
## output that no longer resolves is dropped rather than silently re-routed, and
## each is judged on its own so one dead port does not cost the others.
##
## Dormant while the distributor is anchored, exactly as its sibling is dormant
## while generators are — kept for the same reason, that the rule must not rest on
## a guarantee made elsewhere.
func _drop_invalid_ports(cell: GraphCell) -> void:
	if cell.block == null or not cell.block.has_any_port():
		return
	var kept: Array[BlockPort] = []
	for port in cell.block.ports:
		if port.target_id != cell.id \
				and resolve_route(cell.id, port.target_id, port.route_via).size() >= 2:
			kept.append(port)
	cell.block.ports = kept
	cell.block._clamp_cursor()


## The route a block on `cell_id` would send an orb along, bent through `via`.
## The single place a route is worked out, so `can_aim_at`, the HUD readout and
## the board's route drawing cannot disagree about where an orb actually goes.
func resolve_route(from_id: int, to_id: int, via: PackedInt32Array) -> PackedInt32Array:
	return graph.find_path_via(from_id, via, to_id)


## The resolved route of whatever stands on this cell, or empty if it is unaimed.
## The view's one call — it must never rebuild a route from the endpoints, which
## is how it used to draw a straight line under a bent one.
func block_route(cell_id: int) -> PackedInt32Array:
	var cell := graph.get_cell(cell_id)
	if cell == null or cell.block == null or not cell.block.has_target():
		return PackedInt32Array()
	return resolve_route(cell_id, cell.block.target_id, cell.block.route_via)


## Every route a block on `cell_id` currently sends orbs along — one entry for a
## single-target block, one per port for a distributor, none for an idle block.
##
## The view draws through this rather than `block_route`, so a block with several
## outputs shows all of them and one with a single target is unchanged: a list of
## one is the call that was already there.
func block_routes(cell_id: int) -> Array:
	var cell := graph.get_cell(cell_id)
	if cell == null or cell.block == null:
		return []
	if cell.block.has_any_port():
		var routes: Array = []
		for port in cell.block.ports:
			var route := resolve_route(cell_id, port.target_id, port.route_via)
			if route.size() >= 2:
				routes.append(route)
		return routes
	var single := block_route(cell_id)
	return [] if single.is_empty() else [single]


## Whether a partial waypoint chain resolves to a legal walk — every leg
## routable, and no cell crossed twice. Lets the view refuse an impossible
## waypoint as it is clicked rather than at commit time.
##
## Asks `find_chain` rather than checking legs itself, so it cannot disagree with
## the route `set_target` is about to resolve. A second copy of the rules here is
## how the board ends up offering a route the simulation then refuses.
func can_route_through(from_id: int, via: PackedInt32Array) -> bool:
	return not graph.find_chain(from_id, via).is_empty()


## Tidy a waypoint list into the canonical form the simulation stores.
##
## Drops entries that repeat the node immediately before them, and a trailing
## entry that merely names the target — both are no-ops that would otherwise make
## two identical routes compare unequal in `set_target`'s early-out.
##
## **Non-consecutive repeats are kept**, because this is syntactic tidy-up and
## not a legality check. A via-list that names a cell twice survives normalising
## and is then refused by `find_chain`, which is the one place the simple-path
## rule lives. Dropping the repeat here instead would silently rewrite the
## player's route into a different one that happens to be legal.
static func normalize_via(from_id: int, to_id: int, via: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var previous := from_id
	for stop in via:
		if stop == previous:
			continue
		out.append(stop)
		previous = stop
		if out.size() == MAX_WAYPOINTS:
			break
	while not out.is_empty() and out[out.size() - 1] == to_id:
		out.remove_at(out.size() - 1)
	return out


## Whether this block may legally be aimed at this cell, along this route.
## The single verdict `set_target` enforces and the view previews, so the board
## can never offer a route the simulation is about to refuse.
##
## Three ways to fail, and the last two are the tier rules:
##
## - **Unroutable.** Undiscovered ground needs no special case: `find_path`
##   refuses to route through fog, so aiming into the dark — or through a fogged
##   waypoint — falls out of this and stays a simulation rule rather than a UI
##   one.
## - **Wrong colour.** A locked cell states what it takes, and pouring red into
##   an orange cell would be pure waste. Refused up front rather than allowed and
##   wasted, so the board teaches the rule instead of quietly eating the output.
## - **A mined cell with no intake.** Mined cells consume nothing on their own,
##   so aiming at one used to be refused outright. That is now the *default*
##   rather than the rule: a mined cell holding a converter that takes this tier
##   is a legal target, and it is the only way a generator ever feeds an
##   upgrader.
##
## The tier rules apply to the **destination only**. A waypoint is somewhere the
## orb passes through, and a cell it merely crosses neither consumes it nor cares
## what colour it is — locked cells are traversable and mined ones take nothing
## on the way past.
func can_aim_at(cell_id: int, target_id: int, via := PackedInt32Array()) -> bool:
	var cell := graph.get_cell(cell_id)
	if cell == null or cell.block == null:
		return false
	var target := graph.get_cell(target_id)
	if target == null or target_id == cell_id:
		return false
	if resolve_route(cell_id, target_id, via).size() < 2:
		return false
	var tier := cell.block.def.output_tier
	if target.is_unlocked:
		return target.block != null and target.block.def.accepts_delivery(tier)
	return target.accepts_tier(tier)


## Aim a block, optionally bending its route through `via`. Pass -1 to unaim,
## which idles it and drops any waypoints with it.
##
## **Affects the next orb only.** Anything already in flight keeps the path it
## was launched with and lands where that path ends — an orb is committed once
## launched. So rebending a live route costs nothing already in the air, which is
## what makes drawing a waypoint chain click by click reasonable.
##
## `by_player` records the aim as an override auto-aim must not touch. It
## defaults to true because every caller but one is a player command;
## `apply_auto_aim()` is the exception and passes false.
func set_target(cell_id: int, target_id: int, via := PackedInt32Array(),
		by_player := true) -> bool:
	var cell := graph.get_cell(cell_id)
	if cell == null or cell.block == null or not cell.block.def.needs_target:
		return false
	if target_id == cell_id:
		return false

	# Normalized *before* the early-out below, so two spellings of the same route
	# compare equal and the no-op is recognised as one.
	var route := PackedInt32Array() if target_id == -1 \
		else normalize_via(cell_id, target_id, via)

	if target_id != -1 and not can_aim_at(cell_id, target_id, route):
		return false
	# Pinned *before* the no-op early-out below, and deliberately. Right-clicking
	# the cell a block is already auto-aimed at is a real command — "hold this
	# one" — and it is the natural way to ask for it. Recorded after the aim
	# itself is known to be legal, so a refused command pins nothing.
	if target_id != -1:
		cell.block.pinned = by_player
	# Same destination *and* same route is the no-op. Both halves are compared
	# because a rebend to the same cell is a real change to what the next orb
	# will do, even though the destination did not move.
	if cell.block.target_id == target_id and cell.block.route_via == route:
		return true

	if target_id == -1:
		cell.block.clear_target()
	else:
		cell.block.target_id = target_id
		cell.block.route_via = route
	return true


# --- Auto-aim -----------------------------------------------------------
#
# Aiming is the command the player gives most often and the one that carries a
# decision least often: the answer is nearly always "the nearest cell this
# block's colour can open". Auto-aim gives that answer for every block the player
# has not answered it for themselves.
#
# **Event-driven, never per tick**, exactly like `resolve_links()`. Which cell is
# nearest-and-still-locked changes only when a cell is mined, when a block moves,
# or when the toggle is flipped, so there are three call sites and the tick is
# not one of them. A per-tick pass would run a BFS per aimable block ten times a
# second for an answer that had not changed.
#
# **No ledger bucket and no new phase.** Auto-aim decides where an orb is sent,
# not whether one exists: everything it does goes through `set_target` and then
# through `emit_orb` like any hand-drawn route. It is the "a mechanic that
# changes how much flows through an existing path is exempt" rule, with even less
# to argue about than usual — it does not change how much flows either.


## Turn auto-aim on or off. Turning it on immediately picks up everything idle.
##
## Turning it **off** leaves every target exactly where it is. A toggle must not
## unaim the board: the routes auto-aim drew are still routes the player is
## watching work, and taking them away on the way out would make the toggle
## something to be afraid of rather than something to try.
func set_auto_aim(on: bool) -> void:
	auto_aim = on
	if on:
		apply_auto_aim()


## The nearest cell the block on `cell_id` could open, or -1 if there is none.
##
## Walks the board outward from the block through `graph.nearest_discovered`, so
## the first candidate that passes is the nearest one, and ties resolve through
## the same ascending-neighbour rule every route on the board already uses.
##
## `can_aim_at` stays the **single verdict**, as it is for `set_target` and the
## aim preview — auto-aim must never pick a target the simulation would refuse.
## The two cheap tests in front of it are a cost filter and not a second rule:
## they skip the mined and wrong-coloured cells, which is nearly all of them,
## without resolving a route for each.
func auto_target_for(cell_id: int) -> int:
	var cell := graph.get_cell(cell_id)
	if cell == null or cell.block == null or not cell.block.def.needs_target:
		return -1

	var tier := cell.block.def.output_tier
	return graph.nearest_discovered(cell_id, func(candidate: GraphCell) -> bool:
		if candidate.is_unlocked or not candidate.accepts_tier(tier):
			return false
		return can_aim_at(cell_id, candidate.id))


## Re-aim every unpinned aimable block at its nearest opening. A no-op while
## auto-aim is off.
##
## **Recomputed wholesale, never edited incrementally** — the same rule
## `_resolve_stats()` follows, and for the same payoff. It is what makes the pass
## safe inside the deliver phase: two orbs mining two cells on the same tick each
## run it, and both orders converge on the targets the final board implies, so
## `test_tick_order_independent` covers it for free. It also means there is no
## accumulated drift to chase and nothing to invalidate.
##
## Writes only each block's own target, and reads only the graph, so order within
## the pass is free as well.
func apply_auto_aim() -> void:
	if not auto_aim:
		return
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if cell.block == null or not cell.block.def.needs_target:
			continue
		if cell.block.pinned:
			continue
		var target := auto_target_for(id)
		if target == -1:
			cell.block.clear_target()
		else:
			set_target(id, target, PackedInt32Array(), false)


# --- Effective stats ----------------------------------------------------
#
# The only sanctioned way to read a stat that a sphere can change. Reading
# `block.def.produce_interval` or `block.def.restore_percent` directly gets the
# base number and silently ignores every sphere on the board — which is a bug
# that shows up as the HUD and the simulation disagreeing, not as a crash.
#
# No new ledger bucket. A faster generator emits more often and books it under
# `produced` in `emit_orb`; a stronger pump books the larger amount under
# `restored` in `restore_orb`. Both buckets already exist and both are already
# on the correct side of the invariant, so the sphere creates no value the ledger
# cannot see. This is worth stating because the standing rule is that a mechanic
# creating value adds a bucket — the reason this one is exempt is that it changes
# how much flows through existing paths, not where value comes from.
#
# Challenges are exempt for the same reason, including the Surge, which is the
# one that looks like it should not be. A richer orb is still booked at the value
# it was created with, because `emit_orb` books what it actually emitted rather
# than the constant — it moves where the dial is set, not where value enters.
#
# There are two baselines here, and confusing them is the mistake to avoid. The
# *base* is what the def declares. The *baseline* is that plus any global, and it
# is what a sphere is measured against: once a Current is mined every pump on the
# board restores 5, and a pump that is genuinely standing in no field must not be
# drawn as though it were. `base_*` below is the baseline; `effective_*` is the
# baseline plus the field.


## Value an orb launches with right now, after any Surge. `ORB_START_VALUE` is
## the base, not the answer, and this is the only sanctioned way to ask — reading
## the constant directly quotes an un-upgraded board.
##
## Still not a ceiling: pumps push an orb above this, as they always did.
func effective_orb_value() -> int:
	_ensure_stats()
	return ORB_START_VALUE + _global.orb_value_delta


## Ticks between emissions for this producer before any sphere, but after any
## global. The baseline a field is measured against — see the note above.
##
## Applying the global here is what keeps `is_boosted()` meaning *a sphere is
## doing this*: measured against the raw base instead, lighting one upkeep block
## would put the sphere ring on every generator on the board at once.
func base_interval(cell: GraphCell) -> int:
	if cell == null or cell.block == null:
		return 0
	var base := cell.block.def.produce_interval
	# Checked before the global, so a block with no interval at all keeps
	# returning 0 and `effective_interval` keeps bailing on it — which is what
	# makes a sphere and an upkeep block both free of any effect on a converter
	# or a challenge.
	if base <= 0:
		return 0
	_ensure_stats()
	return StatBonus.apply_rate(base, _global.rate_percent_delta, MIN_PRODUCE_INTERVAL)


## Percentage this path modifier restores before any sphere, but after any
## Current. In percentage points — `restore_for()` turns it into value.
func base_restore_percent(cell: GraphCell) -> int:
	if cell == null or cell.block == null:
		return 0
	var base := cell.block.def.restore_percent
	if base <= 0:
		return 0
	_ensure_stats()
	return StatBonus.combine(base, _global.restore_percent_delta)


## Ticks between emissions for the producer on this cell, after any spheres and
## any upkeep block. Floored at MIN_PRODUCE_INTERVAL. 0 for a cell with no
## producer, which callers already treat as "does not produce".
##
## **Built from the raw base, not from `base_interval()`.** The global and the
## field are both increased rates, and rates sum before they divide: a sphere on
## a board with an upkeep block lit is `20 × 100 / 150 = 13`, where dividing
## twice would truncate twice and give 12. So `base_interval()` is no longer an
## input here — it is an independently-computed baseline that `is_boosted()` and
## the HUD's "(was N)" measure against, and nothing else.
func effective_interval(cell: GraphCell) -> int:
	if cell == null or cell.block == null:
		return 0
	var base := cell.block.def.produce_interval
	if base <= 0:
		return 0
	_ensure_stats()
	var increased: int = _global.rate_percent_delta
	var bonus: StatBonus = _field.get(cell.id)
	if bonus != null:
		increased += bonus.rate_percent_delta
	return StatBonus.apply_rate(base, increased, MIN_PRODUCE_INTERVAL)


## Value this cell's path modifier adds to an orb passing through, after any
## spheres and any Current. Floored at 0 — a negative field must not turn a pump
## into a drain, which would put value into no bucket at all.
##
## The global is folded in through `base_restore_percent()` rather than added here, so a
## pump standing outside every field still gets it. An early return for "no field
## at this cell" would silently drop it for exactly the pumps nothing reaches.
func effective_restore_percent(cell: GraphCell) -> int:
	var base := base_restore_percent(cell)
	if base <= 0:
		return 0
	var bonus: StatBonus = _field.get(cell.id)
	if bonus == null:
		return base
	return StatBonus.combine(base, bonus.restore_percent_delta)


## Delivered value this converter banks per output orb, before any sphere. The
## baseline half of the pair, on the `base_interval()` precedent.
##
## There is no board-wide term to fold in — nothing grants an increased charge
## rate to every converter at once, and `GlobalBonus` deliberately carries no
## such field. The day one lands it goes in here, and this stops being a plain
## read of the def.
func base_upgrade_cost(cell: GraphCell) -> int:
	if cell == null or cell.block == null:
		return 0
	return cell.block.def.upgrade_cost


## Delivered value this converter banks per output orb, after any spheres.
## Floored at MIN_UPGRADE_COST, and 0 for a block that converts nothing — which
## is what keeps a sphere free of any effect on a generator, a pump, an upkeep
## block or a challenge, exactly as the `base <= 0` guard does for the interval.
##
## A converter's clock is denominated in delivered value rather than ticks, so a
## discount here is the same buff `effective_interval()` is: charging faster. It
## reads the charge axis rather than the rate one so the two can be tuned apart.
##
## Charge already banked is not re-priced — it is a count of value delivered, not
## a fraction of a cost. A sphere arriving mid-fill simply brings the finish line
## closer, and one leaving pushes it back out.
func effective_upgrade_cost(cell: GraphCell) -> int:
	var base := base_upgrade_cost(cell)
	if base <= 0:
		return 0
	_ensure_stats()
	var bonus: StatBonus = _field.get(cell.id)
	if bonus == null:
		return base
	return StatBonus.apply_rate(base, bonus.charge_percent_delta, MIN_UPGRADE_COST)


## What this block's charge meter holds when full, for the view's arc. Two
## different things fill one — a converter's next orb, an upkeep block's reserve
## — and 0 for a block with no meter at all, which the caller must guard against
## dividing by.
##
## `BlockDef.charge_meter_max()` is the un-buffed version and no longer the
## answer: a sphere discounts a converter's cost, so the arc has to fill toward
## the number the simulation will actually act on or it will visibly overshoot —
## the same argument that made the cooldown arc take a cell rather than a block.
func charge_meter_max(cell: GraphCell) -> int:
	if cell == null or cell.block == null:
		return 0
	if cell.block.def.converts():
		return effective_upgrade_cost(cell)
	# A distributor's bank is one output orb's worth, and what that is worth moves
	# with the board — a Surge raises it. So this one cannot come off the def
	# either, for the converter's reason rather than the compressor's.
	if cell.block.def.distributes():
		return effective_orb_value()
	return cell.block.def.charge_meter_max()


## What this cell's path modifier adds to an orb that launched with
## `launch_value`. The only place a restore percentage becomes value, so the
## rounding — up, in the player's favour — is fixed in one place and the aim
## preview cannot disagree with the simulation.
##
## Of the *launch* value, never the orb's current one. Two pumps therefore add
## the same amount as each other whatever order the route meets them in, which
## is what keeps transport order-independent and the arrival formula a sum.
func restore_for(cell: GraphCell, launch_value: int) -> int:
	return StatBonus.percent_of(launch_value, effective_restore_percent(cell))


## How many hops this block's field reaches, after any Lens.
func effective_field_radius(def: BlockDef) -> int:
	_ensure_stats()
	return _field_radius(def)


## Which cells this block's field reaches, ascending, or empty for a block that
## radiates nothing. The view draws the field from this, so what is highlighted
## is the same set the simulation actually buffs rather than a redrawn guess —
## which is why it goes through the same widened radius `_resolve_stats()` used.
func field_cells(cell_id: int) -> PackedInt32Array:
	var cell := graph.get_cell(cell_id)
	if cell == null or not cell.is_unlocked or cell.block == null \
			or not cell.block.def.radiates():
		return PackedInt32Array()
	return graph.cells_within(cell_id, effective_field_radius(cell.block.def))


## Whether the block on this cell is currently having a stat changed by a sphere.
## False for a cell inside a field whose block has nothing to buff — an empty
## cell, a challenge, or another sphere — because the point of the query is to
## mark blocks that are actually running on different numbers.
##
## Three stats can be changed now: the interval, the restore, and a converter's
## cost. The last one is why an upgrader in a field is finally marked — it used
## to be the one block a sphere reached and did nothing for.
##
## Measured against the baseline rather than the def's base, so a board-wide buff
## does not light this up on every pump at once. The ring means "a sphere reaches
## here", and a global reaches everywhere, which is the same as nowhere for a
## query whose job is to point at one.
func is_boosted(cell_id: int) -> bool:
	var cell := graph.get_cell(cell_id)
	if cell == null or cell.block == null:
		return false
	return effective_interval(cell) != base_interval(cell) \
		or effective_restore_percent(cell) != base_restore_percent(cell) \
		or effective_upgrade_cost(cell) != base_upgrade_cost(cell)


# --- Queries ------------------------------------------------------------


## Every challenge the player has mined, in ascending cell order.
##
## Lives here rather than in the HUD for the same reason `next_idle_after` does:
## it is a question about the board, the answer is worth a test, and a view that
## walked the graph itself would need a scene tree to check. Returns the defs
## because that is what a caller wants to display — the cell they sit on stops
## mattering the moment one is mined.
func mined_challenges() -> Array[BlockDef]:
	var found: Array[BlockDef] = []
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if cell.is_unlocked and cell.block != null and cell.block.def.is_challenge:
			found.append(cell.block.def)
	return found


## Every mined upkeep block on the board, as cells rather than defs — unlike a
## challenge, what the player needs to see is the live fuel level and the latch,
## and both of those live on the block.
func mined_upkeeps() -> Array[GraphCell]:
	var found: Array[GraphCell] = []
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if cell.is_unlocked and cell.block != null and cell.block.def.burns_upkeep():
			found.append(cell)
	return found


func in_flight_value() -> int:
	var total := 0
	for orb in orbs:
		if not orb.dead:
			total += orb.value
	return total


func live_orb_count() -> int:
	var count := 0
	for orb in orbs:
		if not orb.dead:
			count += 1
	return count


## The correctness contract for the whole economy.
##
## `converted` is a sink, and the upgrader is the only thing that fills it: red
## absorbed into a charge bank has left circulation for good. The orange that
## comes back out is not a return of it — it enters through `emit_orb` like any
## other emission and books under `produced`. That is what lets a single scalar
## ledger span two tiers: the sum is over abstract value, so a conversion is an
## ordinary sink on one side and an ordinary source on the other, and any leak
## in between fails here.
func ledger_balanced() -> bool:
	return produced + restored \
		== delivered + wasted + decayed + converted + burned + in_flight_value()


func unlocked_count() -> int:
	var count := 0
	for id in graph.cell_ids:
		if graph.cells[id].is_unlocked:
			count += 1
	return count


## Cells holding a block of this type that is aimed at nothing, ascending. Idle
## means what it means everywhere else in the UI: the block wants a target and
## has none. A block that takes no target — a pump — is never idle, because
## there is nothing for the player to do about it.
func idle_cells_of(def_id: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in cell_ids_sorted():
		var cell: GraphCell = graph.cells[id]
		if cell.block == null or cell.block.def.id != def_id:
			continue
		# Through the block rather than a `needs_target` check, so this one loop
		# serves both a generator with no target and a distributor with no ports.
		if cell.block.is_idle():
			out.append(id)
	return out


## The next idle cell of this type after `after_id`, wrapping round to the first.
## -1 when there are none. Pass -1 to start from the beginning.
##
## Lives here rather than in the view because the awkward parts — wrapping, and a
## cursor pointing at a cell that stopped being idle between clicks — are worth
## testing, and the view would need a whole scene tree to test.
func next_idle_after(def_id: String, after_id: int) -> int:
	var idle := idle_cells_of(def_id)
	if idle.is_empty():
		return -1
	for id in idle:
		if id > after_id:
			return id
	return idle[0]


## Discovered cells inside `area` holding a block of this type, ascending.
##
## The view hands in a world-space rectangle — what is currently on screen — and
## gets cell ids back. `Rect2` and `Vector2` are plain Variants and
## `GraphCell.position` is already a `Vector2`, so this stays on the right side of
## the one rule: the simulation still knows nothing of a viewport, a camera or a
## zoom, only of a region of the board.
##
## It lives here rather than in the view for the same reason `next_idle_after`
## does — the awkward parts are worth testing, and in the view they would need a
## whole scene tree to reach.
##
## Ascending through `cell_ids_sorted()`, so which cell a group calls its primary
## cannot depend on the iteration order the order-independence test reverses.
##
## Blocks live only in mined cells, which are always discovered, so the fog check
## cannot currently exclude anything. It is kept because this is a query the
## player's cursor drives, and every such query states the fog rule at its own
## boundary rather than inheriting it from somewhere else.
##
## `Rect2.has_point` is half-open, so a cell centred exactly on the right or
## bottom edge is out. Invisible in practice, and noted so it is not "fixed".
func cells_with_def_in_rect(def_id: String, area: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in cell_ids_sorted():
		if not graph.is_discovered(id):
			continue
		var cell: GraphCell = graph.cells[id]
		if cell.block == null or cell.block.def.id != def_id:
			continue
		if not area.has_point(cell.position):
			continue
		out.append(id)
	return out


## Aim every one of `cell_ids` at `target_id` along `via`, and answer how many are
## aimed there now. `-1` unaims the whole group, through the same path.
##
## **It adds no verdict.** This is a loop over `set_target`, which is a loop over
## `can_aim_at` — the single verdict the aim preview draws. A batch that filtered
## on a rule of its own is how the board starts offering a plan the simulation
## then refuses, one source at a time.
##
## **Partial success is the policy, and this is the one place it lives.** A source
## that fails — unroutable, or a shared waypoint chain that makes *its* route
## cross itself — is left untouched on the target it already had, rather than
## unaimed. A group command must never cost the player a route they already
## had; the worst it may do is decline to change one.
##
## Note what cannot split a group in practice: `can_aim_at` never consults decay,
## so a route an orb will not survive is a legal aim, drawn red, exactly as it is
## for a single block. And a group shares a `def.id` and therefore an
## `output_tier`, so the destination's colour gate answers the same for all of
## them. What is left is reachability and the simple-path rule.
##
## The count is "how many are aimed here now", not "how many changed": a source
## already on this exact route is a no-op `set_target` answers true to, and the
## caller — which clears its half-drawn chain on any success — wants the former.
func set_target_batch(cell_ids: PackedInt32Array, target_id: int,
		via := PackedInt32Array()) -> int:
	var aimed := 0
	for id in cell_ids:
		if set_target(id, target_id, via):
			aimed += 1
	return aimed


## How many of these sources could bend a route through this waypoint chain. The
## batch counterpart of `can_route_through`.
##
## The bar for a group is "somebody can walk it" rather than "everybody can": a
## shared chain that splits the group is a legal thing to draw — the ones that can
## take it are aimed, the rest keep what they had — so a corner is refused only
## when nobody can take it. For a single source this agrees with
## `can_route_through` exactly, which is what lets the view keep one code path for
## a group and a lone block.
func count_routable_through(cell_ids: PackedInt32Array, via: PackedInt32Array) -> int:
	var routable := 0
	for id in cell_ids:
		if can_route_through(id, via):
			routable += 1
	return routable


## Cell ids in ascending order. `graph.cell_ids` is normally already sorted, but
## the order-independence test deliberately reverses it, and a cycling UI must
## not change direction because of that.
func cell_ids_sorted() -> PackedInt32Array:
	var ids := PackedInt32Array(graph.cell_ids)
	ids.sort()
	return ids


func is_complete() -> bool:
	return unlocked_count() == graph.size()


## Value an orb launched now from `from_id` would arrive with, accounting for
## pumps along the route. 0 means it cannot get there — including when the target
## is still fogged, since `find_path` will not route through undiscovered ground.
## Drives the UI's route preview so the player can judge a route before
## committing to it.
func projected_arrival(from_id: int, to_id: int) -> int:
	return arrival_along(graph.find_path(from_id, to_id))


## What an orb would arrive with if it walked this exact route. Deliberately
## reimplements the transport rules — decay, then the death check, then a pump,
## over the route's interior only, since the final cell neither charges nor
## grants — so `test_projected_arrival_matches_reality` cross-checks it against
## real deliveries. Change transport, change this.
##
## Split out from `projected_arrival` so map validation can ask the same question
## about an unrestricted route without a third copy of the walk.
func arrival_along(path: PackedInt32Array) -> int:
	if path.size() < 2:
		return 0

	# Effective, not the constant, for the same reason the pump below is read
	# effective: a preview that quoted the base would under-promise every route
	# on a board where a Surge has been mined.
	var launch := effective_orb_value()
	var value := launch
	var amplifiers := 0
	var destination := path[path.size() - 1]
	for i in range(1, path.size() - 1):
		value -= DECAY_PER_HOP
		if value <= 0:
			return 0
		# The same destination rule transport enforces: a bent route may cross its
		# own destination, and nothing acts on it there either. Without this the
		# preview would promise a pump the simulation is about to skip.
		if path[i] == destination:
			continue
		var cell := graph.get_cell(path[i])
		if cell != null and cell.is_unlocked and cell.block != null:
			# Counted, not applied — the same split `AmplifierBehavior` makes, and
			# for the same reason: the exponent is spent once below, so what this
			# promises cannot depend on where in the route the amplifiers sat.
			if cell.block.def.amplifies():
				amplifiers += 1
			# Through `restore_for`, not the percentage: a preview that did its
			# own rounding would disagree with the simulation on every route
			# whose pumps do not divide evenly. `launch`, not `value`, for the
			# same reason transport uses the orb's launch value — pumps are a
			# sum, not a compound.
			value += restore_for(cell, launch)

	# The mirror of `_apply_amplifiers`, step for step and clamp for clamp. Two
	# loops that must truncate identically, which is why both go through
	# `clamp_orb_value` and neither owns a rounding rule of its own.
	for _i in amplifiers:
		value = clamp_orb_value(value * (100 + BlockCatalog.AMPLIFY_PERCENT) / 100)
	return value
