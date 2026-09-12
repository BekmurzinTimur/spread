class_name HexMap

## Builds the board.
##
## A hex disc of colour rings split by one-ring air gaps. Each gap holds a single
## boss cell, owned by the inner region, at the left tip for odd regions and the
## right tip for even ones. Arithmetic, not data.
##
## Red costs by ring. Every belt past red compounds cell by cell along it, from its
## entry tip to its exit tip. Only node placement is randomised, and it is a
## pure function of the run seed.

const CELL_SPACING := 92.0

# --- Cost balance: every knob -----------------------------------------------

## Red ring 1.
const COST_FIRST := 4.0
## Per region. Red multiplies per ring; a belt per cell along its middle ring.
const CELL_GROWTH: PackedFloat64Array = [2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0]
## A belt's first cell costs this many times the previous colour's exit tip.
const BELT_ENTRY_STEP := 2.0
## A tunnel boss costs this many times the exit tip of the colour it sits in.
const BOSS_COST_MULTIPLIER := 20.0
## A keystone cell costs this many times its ground.
const KEYSTONE_COST_MULTIPLIER := 10.0

# ---------------------------------------------------------------------------

## Resolution of how far along its belt a cell sits.
const BELT_STEPS := 1024
## Levels a belt reports in `hops`, entry to exit.
const BELT_LEVELS := 7

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## Rarity thresholds, cumulative, in `Rng.SCALE` units. 93% nothing, 4% common,
## 1% rare Power, 1.5% rare, 0.5% keystone.
const ROLL_COMMON := 9300
const ROLL_RARE_POWER := 9700
const ROLL_RARE := 9800
const ROLL_KEYSTONE := 9950

## Keys, so two rolls about the same cell can never collide.
const KEY_RARITY := 1
const KEY_TYPE := 2


static func hex_distance(q: int, r: int) -> int:
	return (absi(q) + absi(r) + absi(q + r)) / 2


## Pointy-top axial to pixel.
static func to_pixel(q: int, r: int) -> Vector2:
	return Vector2(
		CELL_SPACING * sqrt(3.0) * (float(q) + float(r) * 0.5),
		CELL_SPACING * 1.5 * float(r)
	)


## Geometric ring of a depth: one gap ring sits before every region past red.
static func ring_of(depth: int) -> int:
	return depth + Regions.region_of(depth)


## Depth of the cell at (q, r), or -1 for air.
static func _depth_at(q: int, r: int) -> int:
	var ring := hex_distance(q, r)
	for region in range(1, Regions.COUNT):
		var gap := Regions.REGION_LAST_HOP[region - 1] + region
		if ring < gap:
			return ring - (region - 1)
		if ring == gap:
			var side := -1 if region % 2 == 1 else 1
			if r == 0 and q == side * ring:
				return Regions.REGION_LAST_HOP[region - 1] + 1
			return -1
	return ring - (Regions.COUNT - 1)


## How far along its belt a cell sits, 0..BELT_STEPS. Arc around the ring from the
## left tip, 0..3g, mirrored for even regions.
static func _belt_step(q: int, r: int, region: int) -> int:
	var g := hex_distance(q, r)
	var arc: int
	if r <= 0:
		arc = 3 * g + r if q == g else q + g
	else:
		arc = r if q == -g else 2 * g + q
	if region % 2 == 0:
		arc = 3 * g - arc
	return arc * BELT_STEPS / (3 * g)


## Cells along a belt's middle ring, entry tip to exit tip.
static func _belt_length(region: int) -> float:
	var inner := Regions.REGION_LAST_HOP[region - 1] + 1 + region
	var outer := Regions.REGION_LAST_HOP[region] + region
	return 1.5 * float(inner + outer)


## What a belt's first cell costs.
static func belt_entry(region: int) -> float:
	return belt_exit(maxi(region - 1, Regions.RED)) * BELT_ENTRY_STEP


## What a colour's dearest cell costs. Red's is its last ring.
static func belt_exit(region: int) -> float:
	if region <= Regions.RED:
		return _red_cost(Regions.REGION_LAST_HOP[Regions.RED])
	return belt_entry(region) * pow(CELL_GROWTH[region], _belt_length(region))


## The boss in the tunnel into `region`. It sits in the colour before.
static func boss_cost(region: int) -> float:
	return belt_exit(region - 1) * BOSS_COST_MULTIPLIER


static func _red_cost(ring: int) -> float:
	return COST_FIRST * pow(CELL_GROWTH[Regions.RED], ring - 1)


## `[cost, hops]` of the real cell at (q, r). `costs` is red's ring table.
static func _price_at(q: int, r: int, depth: int, costs: PackedFloat64Array) -> Array:
	var region := Regions.region_of(depth)
	if region == Regions.RED:
		return [costs[depth], depth]
	var step := _belt_step(q, r, region)
	var cells := _belt_length(region) * float(step) / float(BELT_STEPS)
	var cost := belt_entry(region) * pow(CELL_GROWTH[region], cells)
	return [cost, Regions.REGION_LAST_HOP[region - 1] + 1 + step * BELT_LEVELS / BELT_STEPS]


## The lattice, with costs and regions. No nodes — call `place_nodes()` for those.
## `radius` is a depth. The centre cell is mined; everything else is dark.
static func build(radius: int = Regions.MAX_HOPS) -> Graph:
	var graph := Graph.new()
	var index: Dictionary = {}  # "q:r" -> id
	var next_id := 0
	var costs := hop_costs(Regions.REGION_LAST_HOP[Regions.RED])
	var rings := ring_of(radius)

	for q in range(-rings, rings + 1):
		var r_lo := maxi(-rings, -q - rings)
		var r_hi := mini(rings, -q + rings)
		for r in range(r_lo, r_hi + 1):
			var depth := _depth_at(q, r)
			if depth < 0 or depth > radius:
				continue
			var cell := GraphCell.new()
			cell.id = next_id
			cell.position = to_pixel(q, r)
			var price := _price_at(q, r, depth, costs)
			cell.region = Regions.region_of(depth)
			cell.cost = price[0]
			cell.hops = price[1]
			# The gap-ring tunnel is a boss owned by the inner colour.
			if cell.region > Regions.RED and hex_distance(q, r) == ring_of(depth) - 1:
				graph.boss_ids[cell.region] = next_id
				cell.is_boss = true
				cell.cost = boss_cost(cell.region)
				cell.region -= 1
			cell.base_cost = cell.cost
			graph.add_cell(cell)
			index["%d:%d" % [q, r]] = next_id
			next_id += 1

	# Second pass: adjacency, now that every id exists. Air has no key, so gaps cut edges.
	for q in range(-rings, rings + 1):
		var r_lo := maxi(-rings, -q - rings)
		var r_hi := mini(rings, -q + rings)
		for r in range(r_lo, r_hi + 1):
			var key_here := "%d:%d" % [q, r]
			if not index.has(key_here):
				continue
			var id: int = index[key_here]
			var neighbors: Array[int] = []
			for dir in DIRECTIONS:
				var key := "%d:%d" % [q + dir.x, r + dir.y]
				if index.has(key):
					neighbors.append(index[key])
			neighbors.sort()
			graph.cells[id].neighbor_ids = PackedInt32Array(neighbors)

	graph.finalize()
	# The one cell that never rolls: without a generator here nothing would ever
	# emit and the run could not begin.
	var start := start_cell(graph)
	graph.cells[start].is_generator = true
	graph.mine_cell(start)
	return graph


## Red's cost per ring, 0..radius. Ring 1 is `COST_FIRST`.
static func hop_costs(radius: int) -> PackedFloat64Array:
	var costs := PackedFloat64Array()
	for ring in radius + 1:
		costs.append(_red_cost(ring))
	return costs


## The centre cell — the one the player starts on. Found rather than remembered,
## so it cannot drift from whatever radius the board was built at.
static func start_cell(graph: Graph) -> int:
	for id in graph.cell_ids:
		if graph.cells[id].hops == 0:
			return id
	return graph.cell_ids[0] if graph.cell_ids.size() > 0 else -1


## Scatter buff nodes across the board from a run seed.
##
## ⚠️ The rarity roll never looks at what is unlocked — that is the whole
## dilution guarantee. A slot with no unlocked type stays empty rather than
## falling back to a commoner one, so a purchase can only ever add.
static func place_nodes(graph: Graph, seed_value: int, meta: MetaState) -> void:
	var commons := NodeCatalog.unlocked_of_rarity(NodeType.COMMON, meta)
	var rares := NodeCatalog.unlocked_of_rarity(NodeType.RARE, meta)
	var any: Array = commons + rares
	# Power needs no unlock, so its rare slot is always filled.
	var power: Array = [NodeCatalog.get_type(NodeCatalog.YIELD)]

	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		cell.node_id = ""
		cell.tier = 0
		cell.cost = cell.base_cost
		if cell.is_mined or cell.is_boss:
			continue

		var rarity_roll := Rng.roll(seed_value, id, KEY_RARITY)
		if rarity_roll < ROLL_COMMON:
			continue
		# A keystone's slot never depends on unlocks, so neither does its price.
		if rarity_roll >= ROLL_KEYSTONE:
			cell.cost = cell.base_cost * KEYSTONE_COST_MULTIPLIER

		var pool: Array = commons
		var tier := NodeCatalog.TIER_COMMON
		if rarity_roll >= ROLL_KEYSTONE:
			pool = any
			tier = NodeCatalog.TIER_KEYSTONE
		elif rarity_roll >= ROLL_RARE:
			pool = rares
			tier = NodeCatalog.TIER_RARE
		elif rarity_roll >= ROLL_RARE_POWER:
			pool = power
			tier = NodeCatalog.TIER_RARE
		if pool.is_empty():
			continue

		var pick := Rng.roll(seed_value, id, KEY_TYPE) % pool.size()
		cell.node_id = pool[pick].id
		cell.tier = tier
