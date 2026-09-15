class_name World
extends RefCounted

## The simulation. Money is float, everything else integer. No Godot node, no `delta`.
##
## The frontier runs itself: a mined cell either rolls a generator or is inert
## ground, only generators touching mineable ground emit, and the generator count
## sets how fast every emitter's clock runs. The player aims one thing — the ram.

const TICK_HZ := 10
const TICK_SECONDS := 1.0 / float(TICK_HZ)

## Ticks to cross one hop. Orbs are short-range now, so they are quick.
const HOP_TICKS := 3

const BASE_ORB_VALUE := 1

## Charge one emission costs. At base rate (10000 per tick) that is 20 ticks.
const EMIT_CHARGE := 20 * 100 * 100

## What one generator adds to the emission rate, so 50 of them is +100%.
## Percentage points, summed with Speed — see `effective_rate()`.
const RATE_PER_GENERATOR := 2

const CRIT_MULTIPLIER := 2

## Share of a splash orb's value each neighbour of its target takes.
const SPLASH_PERCENT := 50
const SPLASH_STRENGTH_PER_LEVEL := 25

## Share of its value a bounce keeps each hop. The Bounce skill keeps it all.
const BOUNCE_KEEP_PERCENT := 50
const BOUNCE_STRENGTH_PER_LEVEL := 5
## Extra bounces while the Bounce skill is active, before Glaive skill levels.
const BOUNCE_SKILL_BASE := 1

## Percent orb value per generator, per Overcharge level.
const OVERCHARGE_PER_LEVEL := 1
## Orb value multiplier per Orb value ×2 level.
const ORB_MULTIPLIER := 2.0
const RAM_CHARGE_PER_LEVEL := 5
const BOUNTY_PER_LEVEL := 10

## Chance a mined cell becomes a generator, in `Rng.SCALE` units. Zero before any
## purchase. A cliff, not a curve: a dud neither emits nor feeds the rate.
const GENERATOR_CHANCE := 0
const GENERATOR_CHANCE_PER_LEVEL := 2000

## Roll key, kept apart from the node-placement keys in `HexMap`.
const KEY_GENERATOR := 3
## Third roll key on a bounce; the target pick uses 0.
const KEY_BOUNCE_SPLASH := 1
## Splash roll key for a ram shot.
const KEY_RAM_SPLASH := -1

## How much of a mined cell's cost is banked as ram damage. Also the most of the
## board the ram can ever account for.
const RAM_SHARE_PERCENT := 8
const RAM_POWER_PER_LEVEL := 10

## Percent more emission rate while the Speed skill is active.
const SPEED_SKILL_MORE := 100

const VISION_IDENTITY := 1
const VISION_RARITY := 4

var graph: Graph
var tick_count: int = 0
var orbs: Array[Orb] = []

## The run's found buffs. Levels last the run and reset at ascension.
var buffs: BuffState = BuffState.new()

## Hex skills: readiness from mining, cooldowns, active buffs.
var skills: SkillState = SkillState.new()

# --- Value ledger -------------------------------------------------------
#
#   produced == delivered + wasted + in_flight
#
# Three terms, because there are three things that can happen to an orb. Crit
# and Bounce need no bucket: `emit_orb` books what it actually emitted.

var produced: float = 0.0
var delivered: float = 0.0
var wasted: float = 0.0

## Currency banked this run. **Outside the ledger** — it never becomes an orb,
## and the orb value that paid for the cell was booked under `delivered` on the
## way in.
var earned: float = 0.0

## Damage banked since the ram last fired, a share of every cell's cost. It
## scales with the board rather than falling behind it, so the decision is how
## long to save rather than whether the pool can still dent anything.
var ram_power: float = 0.0

const LEDGER_TOLERANCE := 1e-9

const MAX_DELIVERY_EVENTS := 256
var _delivery_events: Array[DeliveryEvent] = []

## Cells mined since the view last drained. The second pull channel, same shape
## as the first: the simulation appends, the view drains, nothing in `sim/` ever
## reads it back. It carries the cell pop, the fog lifting off its neighbours and
## the node reveal — all presentation, no ledger.
var _mine_events: PackedInt32Array = PackedInt32Array()

var _spawn_queue: Array[Orb] = []
var _splash_queue: Array[Orb] = []
var _bounce_queue: Array[Orb] = []
var _has_dead: bool = false

## Rebuilt wholesale whenever the board changes, never edited incrementally.
var _frontier: PackedInt32Array = PackedInt32Array()
var _generators: int = 0
var _frontier_version: int = -1
var _frontier_meta_version: int = -1

var _meta: MetaState = null

## Seed for this run's rolls. Node placement and every crit/splash hang off it.
var run_seed: int = 0


func _init(p_graph: Graph, p_meta: MetaState = null, p_seed: int = 0) -> void:
	graph = p_graph
	_meta = p_meta
	run_seed = p_seed
	buffs.apply_meta(_meta)


func meta() -> MetaState:
	return _meta


## A purchase changes what buffs are worth and which regions are open. The tally's
## *bought* half is re-read; the levels this run dug up are left alone.
func on_meta_changed() -> void:
	buffs.apply_meta(_meta)
	_frontier_version = -1


# --- The region wall ------------------------------------------------------


## Red is always open; any other colour once its boss has fallen, in any run.
func region_open(region: int) -> bool:
	if region <= Regions.RED or boss_beaten(region):
		return true
	return _meta != null and _meta.region_open(region)


## The boss guarding this colour is mined on this board. Main banks it into meta.
func boss_beaten(region: int) -> bool:
	if region <= Regions.RED or region >= graph.boss_ids.size():
		return false
	var id := graph.boss_ids[region]
	return id >= 0 and graph.cells[id].is_mined


## One rule for the frontier and the ram alike: unmined, in an open region.
func is_mineable(cell: GraphCell) -> bool:
	return not cell.is_mined and region_open(cell.region)


## A mined cell touching ground it can still take. Interior cells go quiet.
func is_frontier(cell: GraphCell) -> bool:
	if not cell.is_mined:
		return false
	for n in cell.neighbor_ids:
		if is_mineable(graph.cells[n]):
			return true
	return false


## Chance a cell becomes a generator when mined, in `Rng.SCALE` units.
func generator_chance() -> int:
	var bought := 0
	if _meta != null:
		bought = _meta.level_of(MetaUpgrades.GENERATOR_CHANCE)
	return clampi(GENERATOR_CHANCE + bought * GENERATOR_CHANCE_PER_LEVEL,
		0, Rng.SCALE)


## Rolled once, when the cell is mined. Deterministic from the seed and the cell,
## so it does not care where iteration had reached, and it picks up a purchase
## made a moment earlier.
func _rolls_generator(cell_id: int) -> bool:
	return Rng.roll(run_seed, cell_id, KEY_GENERATOR) < generator_chance()


# --- Simulation ---------------------------------------------------------


func tick() -> void:
	tick_count += 1
	skills.advance()
	_phase_resolve_frontier()
	_phase_produce()
	_phase_transport()
	_phase_deliver()
	_phase_splash()
	_phase_bounce()

	# Appended after transport, so an orb never moves on the tick it is born.
	if not _spawn_queue.is_empty():
		orbs.append_array(_spawn_queue)
		_spawn_queue.clear()

	if _has_dead:
		_compact_orbs()


## Phase 0. Who emits, and how many generators feed the rate.
##
## A wholesale rebuild over the mined cells, never an incremental edit, so it is
## safe to run after a mine in the deliver phase. A frontier of nothing but duds
## resolves empty, and that is how a run ends.
func _phase_resolve_frontier() -> void:
	var meta_version := _meta.version if _meta != null else 0
	if _frontier_version == graph.unlock_version \
			and _frontier_meta_version == meta_version:
		return

	var emitters: Array[int] = []
	var count := 0
	for id in graph.mined_ids:
		var cell: GraphCell = graph.cells[id]
		if not cell.is_generator:
			continue
		count += 1
		if is_frontier(cell):
			emitters.append(id)
	emitters.sort()

	_frontier = PackedInt32Array(emitters)
	_generators = count
	_frontier_version = graph.unlock_version
	_frontier_meta_version = meta_version


func frontier() -> PackedInt32Array:
	_phase_resolve_frontier()
	return _frontier


func generators() -> int:
	_phase_resolve_frontier()
	return _generators


## Phase 1. Every frontier cell spends its own countdown and fires once per
## `EMIT_CHARGE` crossed. A cell touches only its own countdown, every roll is a hash of its keys,
## so nothing here depends on iteration order.
func _phase_produce() -> void:
	# Hoisted: one rate for the whole phase, so the number cannot move
	# part-way through it.
	var rate := effective_rate()
	var value := effective_orb_value()
	var crit_chance := effective_crit_chance()
	var crit_multiplier := effective_crit_multiplier()
	var splash_chance := effective_splash_chance()
	var bounces := effective_bounces()

	for id in _frontier:
		var cell: GraphCell = graph.cells[id]
		cell.emit_countdown -= rate
		if cell.emit_countdown > 0:
			continue
		var deficit := -cell.emit_countdown
		var emissions := deficit / EMIT_CHARGE + 1
		cell.emit_countdown += emissions * EMIT_CHARGE

		var target := _next_target(cell)
		if target < 0:
			continue
		for e in emissions:
			# Emission index folded into the roll key; e = 0 keeps the old keys.
			var key := e * 1000
			var lead := (deficit - e * EMIT_CHARGE) * 1000 / rate
			var is_crit := crit_chance > 0 \
				and Rng.roll(run_seed, id, tick_count, key) < crit_chance
			var is_splash := splash_chance > 0 \
				and Rng.roll(run_seed, id, tick_count, key + 200) < splash_chance
			emit_orb(id, target, value * crit_multiplier if is_crit else value,
				is_crit, is_splash, lead, bounces, (tick_count * 16384 + id) * 1024 + e)


## The mineable neighbour closest to done, ties to the lowest id.
##
## Concentrating fire rather than spreading it: split six ways the opening cell
## takes a minute to finish anything, concentrated it takes ten seconds and then
## pops one steadily.
func _next_target(cell: GraphCell) -> int:
	var best := -1
	var best_progress := -1.0
	for neighbor_id in cell.neighbor_ids:
		var neighbor: GraphCell = graph.cells[neighbor_id]
		if not is_mineable(neighbor):
			continue
		if neighbor.progress > best_progress:
			best = neighbor_id
			best_progress = neighbor.progress
	return best


func _phase_transport() -> void:
	for orb in orbs:
		if orb.dead:
			continue
		orb.ticks_in_hop += 1


func _phase_deliver() -> void:
	for orb in orbs:
		if orb.dead or orb.ticks_in_hop < HOP_TICKS:
			continue
		orb.dead = true
		_has_dead = true
		_deliver(orb)


## The one deliver-phase write another delivery in the same phase can see: a
## later orb bound for the same cell finds it mined rather than locked.
##
## Order-independent anyway, because `used` is capped by `remaining()` and
## everything the cap turns away wastes. A cell needing 8 fed by orbs worth 5 and
## 10 books `delivered 8, wasted 7` whichever lands first.
func _deliver(orb: Orb) -> void:
	# Queued whether or not the orb counts: that depends on delivery order.
	if orb.is_splash:
		_splash_queue.append(orb)
	if orb.bounces_left > 0:
		_bounce_queue.append(orb)

	var cell := graph.get_cell(orb.to_id)
	if cell == null or not is_mineable(cell):
		wasted += orb.value
		return

	var used := cell.absorb(orb.value)
	delivered += used
	wasted += orb.value - used
	if used > 0:
		_record_delivery(cell.id, used, cell.region, orb.is_crit)

	if cell.progress >= cell.cost:
		_mine(cell, orb.from_ram)


## Phase 4. Splash orbs that landed this tick hit their target and its neighbours.
##
## Two passes: targets and `produced` are read off the board phase 3 left, then
## hits land capped by `remaining()` like a delivery, so order cannot matter.
func _phase_splash() -> void:
	if _splash_queue.is_empty():
		return
	var percent := effective_splash_percent()
	var hits: Array = []  # cell id, amount, from ram, triples
	for orb in _splash_queue:
		var amount := orb.value * percent / 100.0
		var target := graph.get_cell(orb.to_id)
		if amount <= 0 or target == null:
			continue
		_record_delivery(target.id, 0.0, target.region, false, false, true)
		if is_mineable(target):
			produced += amount
			hits.append_array([target.id, amount, orb.from_ram])
		for n in target.neighbor_ids:
			if is_mineable(graph.cells[n]):
				produced += amount
				hits.append_array([n, amount, orb.from_ram])
	_splash_queue.clear()

	for i in range(0, hits.size(), 3):
		_land_hit(graph.cells[hits[i]], hits[i + 1], true, hits[i + 2])


## A hit already booked to `produced` lands, capped by `remaining()` like a delivery.
func _land_hit(cell: GraphCell, amount: float, is_splash: bool, by_ram: bool) -> void:
	var used := cell.absorb(amount) if is_mineable(cell) else 0.0
	delivered += used
	wasted += amount - used
	if used > 0:
		_record_delivery(cell.id, used, cell.region, false, is_splash)
	if cell.progress >= cell.cost:
		_mine(cell, by_ram)


## Phase 5. Orbs that landed this tick bounce on from their target.
##
## The target is a random mineable neighbour, the cell it came from included. With
## nowhere to go, every bounce left lands on the cell it hit at once.
##
## Two passes like splash: choose off the board phase 4 left, then land.
func _phase_bounce() -> void:
	if _bounce_queue.is_empty():
		return
	var keep := effective_bounce_keep_percent()
	var orb_splash_chance := effective_splash_chance() if bounces_splash() else 0
	var ram_splash_chance := effective_splash_chance() if ram_bounces_splash() else 0
	var options: Array[int] = []
	var stuck: Array = []  # cell id, amount, from ram, triples
	for orb in _bounce_queue:
		var from := graph.get_cell(orb.to_id)
		if from == null:
			continue
		options.clear()
		for n in from.neighbor_ids:
			if is_mineable(graph.cells[n]):
				options.append(n)
		if options.is_empty():
			if is_mineable(from):
				var amount := _bounce_remainder(orb.value, orb.bounces_left, keep)
				produced += amount
				stuck.append_array([from.id, amount, orb.from_ram])
			continue
		var pick := Rng.roll(run_seed, orb.chain_key, orb.bounces_left) % options.size()
		var splash_chance := ram_splash_chance if orb.from_ram else orb_splash_chance
		var is_splash := splash_chance > 0 and Rng.roll(run_seed, orb.chain_key,
			orb.bounces_left, KEY_BOUNCE_SPLASH) < splash_chance
		emit_orb(from.id, options[pick], orb.value * keep / 100.0, false, is_splash, 0,
			orb.bounces_left - 1, orb.chain_key, orb.from_ram)
	_bounce_queue.clear()

	for i in range(0, stuck.size(), 3):
		_land_hit(graph.cells[stuck[i]], stuck[i + 1], false, stuck[i + 2])


## What `bounces` more hops would deal: v·q + v·q² + … + v·qⁿ, in O(1).
static func _bounce_remainder(value: float, bounces: int, keep_percent: int) -> float:
	if keep_percent >= 100:
		return value * bounces
	var q := keep_percent / 100.0
	return value * q * (1.0 - pow(q, bounces)) / (1.0 - q)


## Mine a cell: roll its generator, pay out, reveal its node.
##
## The grant lives here rather than in `Graph.mine_cell()`, which is idempotent
## and also runs for the board's starting cell.
## A cell the ram finishes banks no ram damage, or the ram would feed itself.
func _mine(cell: GraphCell, by_ram: bool = false) -> void:
	if cell.is_mined:
		return
	cell.is_generator = _rolls_generator(cell.id)
	graph.mine_cell(cell.id)
	earned += cell.cost * (100 + bounty_percent()) / 100.0
	if ram_unlocked() and not by_ram:
		ram_power += cell.cost * ram_share() / 100.0
	for id in NodeCatalog.ids():
		if skill_unlocked(String(id)):
			skills.charge(String(id))
	if cell.has_node():
		buffs.add(cell.node_id, cell.node_grant())
	if _mine_events.size() < MAX_DELIVERY_EVENTS:
		_mine_events.append(cell.id)


func _compact_orbs() -> void:
	var live: Array[Orb] = []
	for orb in orbs:
		if not orb.dead:
			live.append(orb)
	orbs = live
	_has_dead = false


# --- Emission -----------------------------------------------------------


## Books what it actually emitted, so a crit enters `produced` at its full value
## and needs no bucket of its own.
func emit_orb(from_id: int, to_id: int, value: float, is_crit: bool = false,
		is_splash: bool = false, lead_permille: int = 0, bounces: int = 0,
		chain_key: int = 0, from_ram: bool = false) -> void:
	var orb := Orb.new()
	orb.chain_key = chain_key
	orb.from_ram = from_ram
	orb.value = value
	orb.from_id = from_id
	orb.to_id = to_id
	orb.is_crit = is_crit
	orb.is_splash = is_splash
	orb.bounces_left = bounces
	orb.lead_permille = lead_permille
	_spawn_queue.append(orb)
	produced += value


# --- The ram ------------------------------------------------------------


## The shop's multiplier on the pool, in percentage points. Its own function so
## `ram_damage()` and `fire_ram()`'s refund cannot drift apart — they are inverses
## of each other and a second copy is how one of them quietly stops matching.
func _ram_bonus() -> int:
	if _meta == null:
		return 0
	return _meta.level_of(MetaUpgrades.RAM_POWER) * RAM_POWER_PER_LEVEL


## The shop's ram damage bonus, in percent.
func ram_damage_bonus() -> int:
	return _ram_bonus()


## What the pool would actually land, after the shop's multiplier.
func ram_damage() -> float:
	return ram_power * (100 + _ram_bonus()) / 100.0


func ram_unlocked() -> bool:
	return _meta != null and _meta.is_unlocked(MetaUpgrades.RAM_UNLOCK)


## Any mineable cell, at any distance, once the Power skill is ready. The region
## wall holds for the ram too.
func can_ram_at(cell_id: int) -> bool:
	if not can_activate(NodeCatalog.YIELD) or ram_damage() <= 0:
		return false
	var cell := graph.get_cell(cell_id)
	return cell != null and is_mineable(cell)


## Damage enters as `produced` and lands as `delivered` in the same step, so the
## ledger needs no bucket and nothing is wasted. Damage short of the cost stays
## as progress.
##
## ⚠️ The pool is charged only for what it lands. The refund divides back through
## `_ram_bonus()`; the `used >= damage` branch empties a full shot exactly.
func fire_ram(cell_id: int) -> bool:
	if not can_ram_at(cell_id):
		return false
	skills.activate(NodeCatalog.YIELD)
	var cell: GraphCell = graph.cells[cell_id]
	var damage := ram_damage()
	var used := cell.absorb(damage)
	if used >= damage:
		ram_power = 0.0
	else:
		ram_power = maxf(0.0, ram_power - used * 100.0 / (100 + _ram_bonus()))

	produced += used
	delivered += used
	if used > 0:
		_record_delivery(cell.id, used, cell.region, false)
		_queue_ram_shot(cell.id, used)
	if cell.progress >= cell.cost:
		_mine(cell, true)
	return true


## With Ram splash or Ram bounce, what landed is queued as an orb that already
## landed; the next tick's splash and bounce phases take it from there.
func _queue_ram_shot(cell_id: int, used: float) -> void:
	var shot := Orb.new()
	shot.value = used
	shot.from_id = cell_id
	shot.to_id = cell_id
	shot.from_ram = true
	# Negative, so it never matches an emission's key.
	shot.chain_key = -(tick_count * 16384 + cell_id) - 1
	var splash_chance := effective_splash_chance()
	if ram_splashes() and splash_chance > 0 \
			and Rng.roll(run_seed, shot.chain_key, KEY_RAM_SPLASH) < splash_chance:
		_splash_queue.append(shot)
	if ram_bounces():
		shot.bounces_left = effective_bounces()
		if shot.bounces_left > 0:
			_bounce_queue.append(shot)


# --- Skills -------------------------------------------------------------


## Power's skill is the ram; every other skill follows its buff's unlock.
func skill_unlocked(id: String) -> bool:
	if id == NodeCatalog.YIELD:
		return ram_unlocked()
	var type := NodeCatalog.get_type(id)
	return type != null and (_meta == null or _meta.is_unlocked(type.unlock_key))


func can_activate(id: String) -> bool:
	return skill_unlocked(id) and skills.is_ready(id)


## Called between ticks. Power is spent only through `fire_ram`.
func activate_skill(id: String) -> bool:
	if id == NodeCatalog.YIELD or not can_activate(id):
		return false
	skills.activate(id)
	return true


# --- Vision -------------------------------------------------------------


func vision_identity() -> int:
	return VISION_IDENTITY + _vision_bonus()


func vision_rarity() -> int:
	return VISION_RARITY + _vision_bonus()


## +1 hop per open colour past red, plus the shop's Vision levels.
func _vision_bonus() -> int:
	var bonus := _meta.level_of(MetaUpgrades.VISION) if _meta != null else 0
	for region in range(Regions.RED + 1, Regions.COUNT):
		if region_open(region):
			bonus += 1
	return bonus


## 2 you can read its name, 1 you can see a glow sized by rarity, 0 nothing.
## A lottery ticket: rarity is honest so you never feel cheated, identity is
## hidden so the board is never solved at the start of a run.
func visibility_of(cell_id: int) -> int:
	var distance := graph.distance_of(cell_id)
	if distance < 0:
		return 0
	if distance <= vision_identity():
		return 2
	if distance <= vision_rarity():
		return 1
	return 0


# --- Effective stats ----------------------------------------------------


func effective_orb_value() -> float:
	var flat := BASE_ORB_VALUE \
		+ buffs.level_of(NodeCatalog.YIELD) * NodeCatalog.YIELD_PER_LEVEL
	return float(flat) * (100 + overcharge_percent()) / 100.0 \
		* pow(ORB_MULTIPLIER, _meta_level(MetaUpgrades.ORB_MULTIPLIER)) \
		* Achievements.value_multiplier(_meta)


## Increased orb value from Overcharge, in percent.
func overcharge_percent() -> int:
	return _meta_level(MetaUpgrades.OVERCHARGE) * OVERCHARGE_PER_LEVEL * generators()


func effective_splash_chance() -> int:
	return buffs.level_of(NodeCatalog.SPLASH) * NodeCatalog.SPLASH_PER_LEVEL


## Whether bounce hops roll for splash like emissions do.
func bounces_splash() -> bool:
	return _meta_level(MetaUpgrades.SPLASH_BOUNCE) > 0


func ram_splashes() -> bool:
	return _meta_level(MetaUpgrades.RAM_SPLASH) > 0


func ram_bounces() -> bool:
	return _meta_level(MetaUpgrades.RAM_BOUNCE) > 0


func ram_bounces_splash() -> bool:
	return _meta_level(MetaUpgrades.RAM_SPLASH_BOUNCE) > 0


func effective_splash_percent() -> int:
	return SPLASH_PERCENT \
		+ _meta_level(MetaUpgrades.SPLASH_STRENGTH) * SPLASH_STRENGTH_PER_LEVEL


## Percent of a mined cell's cost the ram banks.
func ram_share() -> int:
	return RAM_SHARE_PERCENT \
		+ _meta_level(MetaUpgrades.RAM_CHARGE) * RAM_CHARGE_PER_LEVEL


func bounty_percent() -> int:
	return _meta_level(MetaUpgrades.BOUNTY) * BOUNTY_PER_LEVEL


func _meta_level(key: String) -> int:
	return _meta.level_of(key) if _meta != null else 0


## Emission charge per tick; one emission costs `EMIT_CHARGE`. Uncapped.
## ⚠️ Generators and Speed are both increased rates, so they sum before the
## Speed skill's *more* multiplies them. Achievements multiply last; at least 1,
## since produce divides by it.
func effective_rate() -> int:
	var increased := generators() * RATE_PER_GENERATOR \
		+ buffs.level_of(NodeCatalog.PULSE) * NodeCatalog.PULSE_PER_LEVEL
	var more := SPEED_SKILL_MORE if skills.is_active(NodeCatalog.PULSE) else 0
	var rate := (100 + increased) * (100 + more)
	return maxi(1, int(float(rate) * Achievements.rate_multiplier(_meta)))


func effective_crit_chance() -> int:
	if skills.is_active(NodeCatalog.CRIT):
		return Rng.SCALE
	return NodeCatalog.crit_chance(buffs.level_of(NodeCatalog.CRIT))


## Bounces per emitted orb. The Bounce skill adds more while active.
func effective_bounces() -> int:
	var bounces := buffs.level_of(NodeCatalog.BOUNCE)
	if skills.is_active(NodeCatalog.BOUNCE):
		bounces += BOUNCE_SKILL_BASE + _meta_level(MetaUpgrades.BOUNCE_SKILL)
	return bounces


## Percent of its value each bounce keeps.
func effective_bounce_keep_percent() -> int:
	if skills.is_active(NodeCatalog.BOUNCE):
		return 100
	return BOUNCE_KEEP_PERCENT \
		+ _meta_level(MetaUpgrades.BOUNCE_STRENGTH) * BOUNCE_STRENGTH_PER_LEVEL


func effective_crit_multiplier() -> float:
	var bought := _meta.level_of(MetaUpgrades.CRIT_MULTIPLIER) if _meta != null else 0
	var node_bonus := buffs.level_of(NodeCatalog.CRIT)
	var skill_multiplier := 1
	if skills.is_active(NodeCatalog.CRIT):
		skill_multiplier = 2
	return (CRIT_MULTIPLIER + bought + node_bonus) * skill_multiplier

# --- Delivery events, for the view --------------------------------------


func _record_delivery(cell_id: int, amount: float, region: int, is_crit: bool,
		is_splash: bool = false, is_splash_origin: bool = false) -> void:
	if _delivery_events.size() >= MAX_DELIVERY_EVENTS:
		_delivery_events.pop_front()
	_delivery_events.append(DeliveryEvent.new(cell_id, amount, region, tick_count,
		is_crit, is_splash, is_splash_origin))


## The only data path out of `sim/`: the simulation appends, the view drains.
## Draining rather than clearing per tick matters because a frame can advance the
## sim by several ticks before it draws.
func take_delivery_events() -> Array[DeliveryEvent]:
	var events := _delivery_events
	_delivery_events = []
	return events


func take_mine_events() -> PackedInt32Array:
	var events := _mine_events
	_mine_events = PackedInt32Array()
	return events


# --- Queries ------------------------------------------------------------


func in_flight_value() -> float:
	var total := 0.0
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


## Within a relative tolerance: float sums round.
func ledger_balanced() -> bool:
	var rest := delivered + wasted + in_flight_value()
	return absf(produced - rest) <= LEDGER_TOLERANCE * maxf(1.0, absf(produced))


## Cells mined. Distinct from `generators()`, which counts only the ones that rolled
## a generator — a dud is mined ground worth nothing.
func mined_count() -> int:
	return graph.mined_ids.size()


## How much of a region is mined, for the run's progress ring.
func region_progress(region: int) -> Array:
	var mined := 0
	var total := 0
	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		if cell.region != region:
			continue
		total += 1
		if cell.is_mined:
			mined += 1
	return [mined, total]


## The deepest region the player has bought into. The run's end condition is
## clearing it.
func current_region() -> int:
	var deepest := Regions.RED
	for region in Regions.COUNT:
		if region_open(region):
			deepest = region
	return deepest


func is_complete() -> bool:
	for id in graph.cell_ids:
		if not graph.cells[id].is_mined:
			return false
	return true
