class_name World
extends RefCounted

## The whole simulation. Pure data and integer arithmetic — no Godot nodes, no
## floats in the economy, no RNG. Runs headless.
##
## A tick has three phases, and each phase completes across all entities before
## the next begins. That is what makes iteration order irrelevant: generators
## read only their own timer, delivery writes only unlock progress, and nothing
## in the produce phase reads it. No double-buffering needed; test
## `tick_order_independent` holds this honest.

const TICK_HZ := 10
const TICK_SECONDS := 1.0 / float(TICK_HZ)

## Ticks to cross one edge. At 10 Hz this is one second per hop.
const TICKS_PER_HOP := 10

## Value of a freshly emitted orb, and the ceiling a pump can restore to.
const ORB_MAX_VALUE := 10

## Value an orb loses on entering each new cell.
const DECAY_PER_HOP := 1

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

# Diagnostic, not part of the value ledger: an evaporating orb is already at
# zero value, so its loss is fully accounted for under `decayed`.
var evaporated_orbs: int = 0

var _spawn_queue: Array[Orb] = []
var _has_dead: bool = false


func _init(p_graph: Graph) -> void:
	graph = p_graph


# --- Simulation ---------------------------------------------------------


func tick() -> void:
	tick_count += 1
	_phase_produce()
	_phase_transport()
	_phase_deliver()

	# Appended after transport, so an orb never moves on the tick it is born.
	if not _spawn_queue.is_empty():
		orbs.append_array(_spawn_queue)
		_spawn_queue.clear()

	if _has_dead:
		_compact_orbs()


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

		# Blocks never act on an orb's final cell, so nothing can inflate what
		# a delivery is worth.
		if orb.is_at_end():
			continue

		var cell := graph.get_cell(orb.path[orb.hop_index])
		if cell != null and cell.is_unlocked and cell.block != null:
			cell.block.def.behavior.on_orb_pass(self, cell, orb)


func _phase_deliver() -> void:
	for orb in orbs:
		if orb.dead or not orb.is_at_end():
			continue
		_deliver(orb)
		orb.dead = true
		_has_dead = true


func _deliver(orb: Orb) -> void:
	var cell := graph.get_cell(orb.destination_id())
	if cell == null:
		wasted += orb.value
		return

	if cell.is_unlocked:
		# Nothing consumes resource yet. Distributors and upgraders will hook in
		# here via an on_orb_deliver behaviour.
		wasted += orb.value
		return

	var used := mini(cell.unlock_remaining(), orb.value)
	cell.unlock_progress += used
	delivered += used
	wasted += orb.value - used
	if cell.unlock_progress >= cell.unlock_cost:
		cell.unlock()


func _compact_orbs() -> void:
	var alive: Array[Orb] = []
	for orb in orbs:
		if not orb.dead:
			alive.append(orb)
	orbs = alive
	_has_dead = false


# --- Called by behaviours -----------------------------------------------


## Queue an orb from `from_id` to `to_id`. Silently does nothing if there is no
## route, so an unreachable target simply idles rather than leaking value.
func emit_orb(from_id: int, to_id: int, tier: int) -> void:
	var path := graph.find_path(from_id, to_id)
	if path.size() < 2:
		return

	var orb := Orb.new()
	orb.value = ORB_MAX_VALUE
	orb.tier = tier
	orb.path = path
	orb.source_id = from_id
	_spawn_queue.append(orb)
	produced += ORB_MAX_VALUE


func restore_orb(orb: Orb, amount: int) -> void:
	if amount <= 0:
		return
	var before := orb.value
	orb.value = mini(orb.value + amount, ORB_MAX_VALUE)
	restored += orb.value - before


# --- Player commands ----------------------------------------------------


## Blocks cannot be created or destroyed — only moved. Two mined cells may
## exchange contents at any distance; swapping against an empty cell is a move.
func can_swap(a_id: int, b_id: int) -> bool:
	if a_id == b_id:
		return false
	var a := graph.get_cell(a_id)
	var b := graph.get_cell(b_id)
	if a == null or b == null:
		return false
	if not a.is_unlocked or not b.is_unlocked:
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
	_cancel_orbs_from(a_id)
	_cancel_orbs_from(b_id)

	var moved := a.block
	a.block = b.block
	b.block = moved

	# A block can land on the very cell it was aiming at. set_target refuses a
	# self-target on the way in; the same invariant has to hold on the way out.
	_drop_invalid_target(a)
	_drop_invalid_target(b)
	return true


func _drop_invalid_target(cell: GraphCell) -> void:
	if cell.block == null or not cell.block.has_target():
		return
	var target_id := cell.block.target_id
	if target_id == cell.id or graph.find_path(cell.id, target_id).size() < 2:
		cell.block.target_id = -1


## Aim a block. Pass -1 to unaim, which idles it.
func set_target(cell_id: int, target_id: int) -> bool:
	var cell := graph.get_cell(cell_id)
	if cell == null or cell.block == null or not cell.block.def.needs_target:
		return false
	if target_id == cell_id:
		return false
	if target_id != -1 and graph.find_path(cell_id, target_id).size() < 2:
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
	# Commands normally land between ticks, when this is empty; handled anyway
	# so a behaviour that ever issues one cannot leak value.
	var kept: Array[Orb] = []
	for orb in _spawn_queue:
		if orb.source_id == cell_id:
			cancelled += orb.value
		else:
			kept.append(orb)
	_spawn_queue = kept


# --- Queries ------------------------------------------------------------


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


func ledger_balanced() -> bool:
	return produced + restored \
		== delivered + wasted + decayed + cancelled + in_flight_value()


func unlocked_count() -> int:
	var count := 0
	for id in graph.cell_ids:
		if graph.cells[id].is_unlocked:
			count += 1
	return count


func is_complete() -> bool:
	return unlocked_count() == graph.size()


## Value an orb launched now from `from_id` would arrive with, accounting for
## pumps along the route. 0 means it cannot get there. Drives the UI's route
## preview so the player can judge a route before committing to it.
func projected_arrival(from_id: int, to_id: int) -> int:
	var path := graph.find_path(from_id, to_id)
	if path.size() < 2:
		return 0

	var value := ORB_MAX_VALUE
	for i in range(1, path.size()):
		value -= DECAY_PER_HOP
		if value <= 0:
			return 0
		if i == path.size() - 1:
			break
		var cell := graph.get_cell(path[i])
		if cell != null and cell.is_unlocked and cell.block != null:
			value = mini(value + cell.block.def.restore_amount, ORB_MAX_VALUE)
	return value
