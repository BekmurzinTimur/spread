class_name Graph
extends RefCounted

## Cells and their adjacency.
##
## Orbs travel exactly one hop, so there is no routing here and no path cache.
## What is left is the lattice itself plus one derived distance field: how far
## each cell sits from the nearest mined one, which answers both vision range
## and lance range.

var cells: Dictionary = {}  # int -> GraphCell

## Ascending cell ids. The canonical iteration order for the simulation.
var cell_ids: PackedInt32Array = PackedInt32Array()

## Bumped every time a cell is actually mined. Anything derived from which cells
## are mined — the frontier, total power, the distance field — compares against
## this to notice it has gone stale.
var unlock_version: int = 0

var _distance_cache: PackedInt32Array = PackedInt32Array()
var _distance_version: int = -1


func add_cell(cell: GraphCell) -> void:
	cells[cell.id] = cell


func get_cell(id: int) -> GraphCell:
	if cells.has(id):
		return cells[id]
	return null


func size() -> int:
	return cells.size()


## Call once after all cells are added. Symmetrises edges, drops dangling ones,
## sorts adjacency for determinism, and fixes iteration order.
func finalize() -> void:
	var ids: Array[int] = []
	for id in cells:
		ids.append(id)
	ids.sort()

	var adjacency: Dictionary = {}
	for id in ids:
		adjacency[id] = {}
	for id in ids:
		for n in cells[id].neighbor_ids:
			if n == id or not cells.has(n):
				continue
			adjacency[id][n] = true
			adjacency[n][id] = true

	for id in ids:
		var sorted: Array[int] = []
		for n in adjacency[id]:
			sorted.append(n)
		sorted.sort()
		cells[id].neighbor_ids = PackedInt32Array(sorted)

	cell_ids = PackedInt32Array(ids)
	_distance_version = -1


## Mine a cell. The only way to do so. Idempotent, and also the path the board's
## starting cell takes — which is why nothing that should happen once, like
## paying currency, belongs in here.
func mine_cell(id: int) -> void:
	var cell: GraphCell = cells.get(id)
	if cell == null or cell.is_mined:
		return
	cell.apply_mine()
	unlock_version += 1


# --- The distance field -------------------------------------------------


## Hops from the nearest mined cell, per cell id. Zero for a mined cell, -1 if
## nothing is mined at all.
##
## Serves both vision and lance range: the nearest mined cell to an unmined one
## is always a frontier cell, so the two distances are the same number.
## Rebuilt wholesale when `unlock_version` moves, never edited in place.
func distance_from_mined() -> PackedInt32Array:
	if _distance_version == unlock_version:
		return _distance_cache

	var max_id := 0
	for id in cell_ids:
		max_id = maxi(max_id, id)
	var dist := PackedInt32Array()
	dist.resize(max_id + 1)
	dist.fill(-1)

	var queue := PackedInt32Array()
	for id in cell_ids:
		if cells[id].is_mined:
			dist[id] = 0
			queue.append(id)

	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for n in cells[current].neighbor_ids:
			if dist[n] != -1:
				continue
			dist[n] = dist[current] + 1
			queue.append(n)

	_distance_cache = dist
	_distance_version = unlock_version
	return dist


func distance_of(id: int) -> int:
	var dist := distance_from_mined()
	if id < 0 or id >= dist.size():
		return -1
	return dist[id]


## A straight chain of `count` cells, 0..count-1. For tests that want exact
## arithmetic without the hex board.
static func line(count: int, cost: int = 100) -> Graph:
	var graph := Graph.new()
	for i in count:
		var cell := GraphCell.new()
		cell.id = i
		cell.position = Vector2(i * 100.0, 0.0)
		cell.hops = i
		cell.band = Bands.RED
		cell.cost = cost
		var neighbors: Array[int] = []
		if i > 0:
			neighbors.append(i - 1)
		if i < count - 1:
			neighbors.append(i + 1)
		cell.neighbor_ids = PackedInt32Array(neighbors)
		graph.add_cell(cell)
	graph.finalize()
	return graph
