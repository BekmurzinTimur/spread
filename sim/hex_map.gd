class_name HexMap

## Builds the board.
##
## A hex disc of colour rings split by one-ring air gaps. Each gap holds a single
## tunnel cell, owned by the outer region, at the left tip for odd regions and the
## right tip for even ones. Arithmetic, not data.
##
## `hops` is depth (drives cost and region); the geometric ring is `ring_of(depth)`.
## Only node placement is randomised, and it is a pure function of the run seed.

const CELL_SPACING := 92.0

## `50 x 1.65^hops`: each ring costs the same ratio more than the last, so the
## climb never flattens out.
const COST_BASE := 50
const COST_GROWTH_PERCENT := 165

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## Rarity thresholds, cumulative, in `Rng.SCALE` units. 93% nothing, 5% common,
## 1.5% rare, 0.5% keystone — about fifteen nodes across the red region, so a find
## lands roughly once a minute and each one is an event rather than noise.
const ROLL_COMMON := 9300
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


## The lattice, with costs and regions. No nodes — call `place_nodes()` for those.
## `radius` is a depth. The centre cell is mined; everything else is dark.
static func build(radius: int = Regions.MAX_HOPS) -> Graph:
	var graph := Graph.new()
	var index: Dictionary = {}  # "q:r" -> id
	var next_id := 0
	var costs := hop_costs(radius)
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
			cell.hops = depth
			cell.region = Regions.region_of(depth)
			cell.cost = costs[depth]
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


## Cost per hop, 0..radius. Integer steps, never a float `pow`.
static func hop_costs(radius: int) -> PackedInt64Array:
	var costs := PackedInt64Array()
	var cost := COST_BASE
	for _hops in radius + 1:
		costs.append(cost)
		cost = cost * COST_GROWTH_PERCENT / 100
	return costs


## What mining every cell of a region pays, tunnel included. The start cell is never paid for.
static func region_value(region: int) -> int:
	var costs := hop_costs(Regions.MAX_HOPS)
	var total := 0
	for hops in range(1, Regions.MAX_HOPS + 1):
		if Regions.region_of(hops) == region:
			total += 6 * ring_of(hops) * costs[hops]
	if region > 0:
		total += costs[Regions.REGION_LAST_HOP[region - 1] + 1]
	return total


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

	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		cell.node_id = ""
		cell.node_levels = 0
		if cell.is_mined:
			continue

		var rarity_roll := Rng.roll(seed_value, id, KEY_RARITY)
		if rarity_roll < ROLL_COMMON:
			continue

		var pool: Array = commons
		var levels := 1
		if rarity_roll >= ROLL_KEYSTONE:
			pool = any
			levels = NodeCatalog.KEYSTONE_LEVELS
		elif rarity_roll >= ROLL_RARE:
			pool = rares
		if pool.is_empty():
			continue

		var pick := Rng.roll(seed_value, id, KEY_TYPE) % pool.size()
		cell.node_id = pool[pick].id
		cell.node_levels = levels
