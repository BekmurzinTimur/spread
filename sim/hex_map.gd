class_name HexMap

## Builds the board.
##
## A plain hex disc: every cell has six neighbours, bands are pure distance
## rings, and the whole thing is arithmetic rather than data — the board is the
## same place every run, so there is nothing to author and nothing to load.
##
## Only node placement is randomised, and it is a pure function of the run seed.

const CELL_SPACING := 92.0

## `50 x hops^3`. Still polynomial — an exponential curve is not hard, it is an
## impassable wall at a fixed radius — but cubic against income that scales with
## *area* means the frontier has to be earned rather than walked.
const COST_BASE := 50
const COST_EXPONENT := 3

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## Rarity thresholds, cumulative, in `Rng.SCALE` units. 93% nothing, 5% common,
## 1.5% rare, 0.5% keystone — about fifteen nodes across the red band, so a find
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


## The lattice, with costs and bands. No nodes — call `place_nodes()` for those.
## The centre cell is mined; everything else is dark.
static func build(radius: int = Bands.MAX_HOPS) -> Graph:
	var graph := Graph.new()
	var index: Dictionary = {}  # "q:r" -> id
	var next_id := 0

	for q in range(-radius, radius + 1):
		var r_lo := maxi(-radius, -q - radius)
		var r_hi := mini(radius, -q + radius)
		for r in range(r_lo, r_hi + 1):
			var cell := GraphCell.new()
			cell.id = next_id
			cell.position = to_pixel(q, r)
			cell.hops = hex_distance(q, r)
			cell.band = Bands.band_of(cell.hops)
			cell.cost = COST_BASE * cell.hops * cell.hops * cell.hops
			graph.add_cell(cell)
			index["%d:%d" % [q, r]] = next_id
			next_id += 1

	# Second pass: adjacency, now that every id exists.
	for q in range(-radius, radius + 1):
		var r_lo := maxi(-radius, -q - radius)
		var r_hi := mini(radius, -q + radius)
		for r in range(r_lo, r_hi + 1):
			var id: int = index["%d:%d" % [q, r]]
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
