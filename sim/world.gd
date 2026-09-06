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

## Value of a freshly emitted orb. Deliberately *not* a ceiling: pumps add a flat
## amount and stack, so a well-supported orb arrives worth more than it launched.
## Reach is something the player builds up, not a cap they top back up to.
const ORB_START_VALUE := 10

## Value an orb loses on entering each new cell it *travels through*. The
## destination is not one of them: an orb is delivered into its final cell rather
## than crossing it, so a cell next door receives the full launch value and
## arrival is `value - (hops - 1)`. This is the same rule that stops a pump firing
## on a target, applied to the other half of what entering a cell costs.
const DECAY_PER_HOP := 1

## Floor on a producer's effective interval, however many spheres reach it. A
## stack of them would otherwise drive it to zero, which is a generator emitting
## every tick and a divide-by-zero in the view's cooldown arc.
const MIN_PRODUCE_INTERVAL := 5

var graph: Graph
var orbs: Array[Orb] = []
var tick_count: int = 0

# --- Value ledger ---
# Invariant, checked by ledger_balanced() and asserted in tests:
#   produced + restored == delivered + wasted + decayed + cancelled + in_flight
var produced: int = 0    # value emitted by generators
var restored: int = 0    # value added back by pumps
var delivered: int = 0   # value that counted toward an unlock
var wasted: int = 0      # arrived but had nowhere useful to go
var decayed: int = 0     # lost to travel
var cancelled: int = 0   # destroyed because a route was changed or removed
var converted: int = 0   # consumed by an upgrader to mint a higher tier

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


func _init(p_graph: Graph) -> void:
	graph = p_graph


# --- Simulation ---------------------------------------------------------


func tick() -> void:
	tick_count += 1
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
func _ensure_stats() -> void:
	if not _stats_dirty and _stats_version == graph.unlock_version:
		return
	_resolve_stats()
	_stats_dirty = false
	_stats_version = graph.unlock_version


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
		_global.add(def.global_orb_value_bonus, def.global_field_restore_bonus,
			def.global_field_radius_percent)

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
			bonus.add(def.field_interval_bonus, def.field_restore_bonus)


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

		var cell := graph.get_cell(orb.path[orb.hop_index])
		if cell != null and cell.is_unlocked and cell.block != null:
			cell.block.def.behavior.on_orb_pass(self, cell, orb)


func _phase_deliver() -> void:
	for orb in orbs:
		if orb.dead or not orb.is_at_end():
			continue
		# Marked before delivering, not after. Delivering can mine the cell, which
		# unaims every block feeding it and cancels their orbs — and this orb was
		# launched by one of them. Left alive, it would be swept up by that cancel
		# and counted again, on top of the delivery just recorded. Nothing in
		# _deliver reads `dead`, so moving the flag up is free.
		orb.dead = true
		_has_dead = true
		_deliver(orb)


func _deliver(orb: Orb) -> void:
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
	# things they describe happened in. A future cascade event — a "route
	# cancelled" flash, say — then sorts after the delivery that caused it
	# without anyone having to remember why.
	_record_delivery(cell.id, used, orb.tier)
	if cell.unlock_progress >= cell.unlock_cost:
		# Through the graph, not the cell: mining uncovers this cell's neighbours
		# and so changes which routes exist.
		graph.unlock_cell(cell.id)
		# Mining installs whatever the map buried, which may be a sphere lighting
		# up a field, or an ordinary block that now stands inside one.
		mark_stats_dirty()
		_unaim_everything_targeting(cell.id)


## A mined cell consumes nothing, so anything still aimed at it is pouring its
## whole output into waste. Mining therefore releases every block feeding the
## cell, and they idle until the player finds them something else to do — which
## is what the HUD's idle counter is for.
##
## In-flight orbs are cancelled rather than left to land. An orb belongs to the
## route that launched it, and this is that route ending; `set_target` cancels
## for the same reason when the player retargets by hand. The value is lost
## either way — it would only have been wasted on arrival — so this moves it
## between ledger buckets and adds none.
##
## Runs in the deliver phase, and order still does not matter: the unlock that
## triggers it happens exactly once no matter which orb crosses the threshold,
## and every orb bound for this cell ends up either delivered or cancelled with
## the same totals whichever lands first.
func _unaim_everything_targeting(cell_id: int) -> void:
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if cell.block == null or cell.block.target_id != cell_id:
			continue
		cell.block.target_id = -1
		_cancel_orbs_from(id)


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
func emit_orb(from_id: int, to_id: int, tier: int) -> bool:
	var path := graph.find_path(from_id, to_id)
	if path.size() < 2:
		return false

	# Effective, not the constant: a mined Surge raises what every generator on
	# the board launches with. Booked under `produced` at the same value it was
	# created with, so the ledger sees exactly what entered the economy.
	var value := effective_orb_value()

	var orb := Orb.new()
	orb.value = value
	orb.tier = tier
	orb.path = path
	orb.source_id = from_id
	_spawn_queue.append(orb)
	produced += value
	return true


## Uncapped, so pumps stack: an orb crossing three of them is worth three times
## the restore more than one that crossed none. Without a ceiling the whole
## amount always lands, so `restored` takes it directly.
func restore_orb(orb: Orb, amount: int) -> void:
	if amount <= 0:
		return
	orb.value += amount
	restored += amount


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

	# An orb belongs to the route that launched it, so moving either end
	# invalidates anything already in flight from these cells.
	#
	# Dormant while the generator is both the only block that emits an orb and
	# the only one that is anchored: no orb's source_id can name a cell a swap is
	# allowed to touch. Kept because a movable emitter — a distributor, an
	# upgrader — reactivates it the day it lands, and because getting this wrong
	# leaks value past the ledger rather than failing loudly.
	_cancel_orbs_from(a_id)
	_cancel_orbs_from(b_id)

	var moved := a.block
	a.block = b.block
	b.block = moved

	# Either end may have been a sphere, and the block that arrives may now be
	# standing in a field the one that left was not. Dirtied unconditionally
	# rather than only when a sphere is involved: the check is two lookups and
	# getting it wrong leaves a stale bonus that nothing else would catch.
	mark_stats_dirty()

	# A block can land on the very cell it was aiming at. set_target refuses a
	# self-target on the way in; the same invariant has to hold on the way out.
	# Dormant for the same reason, and kept for the same one.
	_drop_invalid_target(a)
	_drop_invalid_target(b)
	return true


func _drop_invalid_target(cell: GraphCell) -> void:
	if cell.block == null or not cell.block.has_target():
		return
	var target_id := cell.block.target_id
	if target_id == cell.id or graph.find_path(cell.id, target_id).size() < 2:
		cell.block.target_id = -1


## Whether this block may legally be aimed at this cell. The single verdict
## `set_target` enforces and the view previews, so the board can never offer a
## route the simulation is about to refuse.
##
## Three ways to fail, and the last two are the tier rules:
##
## - **Unroutable.** Undiscovered ground needs no special case: `find_path`
##   refuses to route through fog, so aiming into the dark falls out of this and
##   stays a simulation rule rather than a UI one.
## - **Wrong colour.** A locked cell states what it takes, and pouring red into
##   an orange cell would be pure waste. Refused up front rather than allowed and
##   wasted, so the board teaches the rule instead of quietly eating the output.
## - **A mined cell with no intake.** Mined cells consume nothing on their own,
##   so aiming at one used to be refused outright. That is now the *default*
##   rather than the rule: a mined cell holding a converter that takes this tier
##   is a legal target, and it is the only way a generator ever feeds an
##   upgrader.
func can_aim_at(cell_id: int, target_id: int) -> bool:
	var cell := graph.get_cell(cell_id)
	if cell == null or cell.block == null:
		return false
	var target := graph.get_cell(target_id)
	if target == null or target_id == cell_id:
		return false
	if graph.find_path(cell_id, target_id).size() < 2:
		return false
	var tier := cell.block.def.output_tier
	if target.is_unlocked:
		return target.block != null and target.block.def.accepts_delivery(tier)
	return target.accepts_tier(tier)


## Aim a block. Pass -1 to unaim, which idles it.
func set_target(cell_id: int, target_id: int) -> bool:
	var cell := graph.get_cell(cell_id)
	if cell == null or cell.block == null or not cell.block.def.needs_target:
		return false
	if target_id == cell_id:
		return false
	if target_id != -1 and not can_aim_at(cell_id, target_id):
		return false
	if cell.block.target_id == target_id:
		return true

	cell.block.target_id = target_id
	# In-flight orbs are bound to the route that launched them.
	_cancel_orbs_from(cell_id)
	return true


func _cancel_orbs_from(cell_id: int) -> void:
	for orb in orbs:
		if orb.dead or orb.source_id != cell_id:
			continue
		cancelled += orb.value
		orb.dead = true
		_has_dead = true
	# A player command lands between ticks, when this is empty. Mining does not:
	# _unaim_everything_targeting runs mid-tick, after the produce phase has
	# already queued this generator's next orb, so the queue is routinely
	# populated here and must be swept too or that value leaks.
	var kept: Array[Orb] = []
	for orb in _spawn_queue:
		if orb.source_id == cell_id:
			cancelled += orb.value
		else:
			kept.append(orb)
	_spawn_queue = kept


# --- Effective stats ----------------------------------------------------
#
# The only sanctioned way to read a stat that a sphere can change. Reading
# `block.def.produce_interval` or `block.def.restore_amount` directly gets the
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
func base_interval(cell: GraphCell) -> int:
	if cell == null or cell.block == null:
		return 0
	var base := cell.block.def.produce_interval
	if base <= 0:
		return 0
	return base


## Value this path modifier adds before any sphere, but after any Current.
func base_restore(cell: GraphCell) -> int:
	if cell == null or cell.block == null:
		return 0
	var base := cell.block.def.restore_amount
	if base <= 0:
		return 0
	_ensure_stats()
	return StatBonus.combine(base, _global.restore_delta)


## Ticks between emissions for the producer on this cell, after any spheres.
## Floored at MIN_PRODUCE_INTERVAL. 0 for a cell with no producer, which callers
## already treat as "does not produce".
func effective_interval(cell: GraphCell) -> int:
	var base := base_interval(cell)
	if base <= 0:
		return 0
	_ensure_stats()
	var bonus: StatBonus = _field.get(cell.id)
	if bonus == null:
		return base
	return StatBonus.combine(base, bonus.interval_delta, MIN_PRODUCE_INTERVAL)


## Value this cell's path modifier adds to an orb passing through, after any
## spheres and any Current. Floored at 0 — a negative field must not turn a pump
## into a drain, which would put value into no bucket at all.
##
## The global is folded in through `base_restore()` rather than added here, so a
## pump standing outside every field still gets it. An early return for "no field
## at this cell" would silently drop it for exactly the pumps nothing reaches.
func effective_restore(cell: GraphCell) -> int:
	var base := base_restore(cell)
	if base <= 0:
		return 0
	var bonus: StatBonus = _field.get(cell.id)
	if bonus == null:
		return base
	return StatBonus.combine(base, bonus.restore_delta)


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
## cell, or another sphere — because the point of the query is to mark blocks that
## are actually running on different numbers.
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
		or effective_restore(cell) != base_restore(cell)


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
		== delivered + wasted + decayed + cancelled + converted + in_flight_value()


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
		if cell.block.def.needs_target and not cell.block.has_target():
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
	var value := effective_orb_value()
	for i in range(1, path.size() - 1):
		value -= DECAY_PER_HOP
		if value <= 0:
			return 0
		var cell := graph.get_cell(path[i])
		if cell != null and cell.is_unlocked and cell.block != null:
			# Effective, not base: a pump standing in a sphere's field restores
			# more, and a preview quoting the base would under-promise every
			# route through one.
			value += effective_restore(cell)
	return value
