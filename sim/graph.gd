class_name Graph
extends RefCounted

## Cells and their adjacency, plus shortest-path lookup.
##
## Edges are undirected and unit-weight: distance is hop count only. Topology is
## static in this iteration, so paths are cached permanently — nothing can
## invalidate them. When teleports arrive they mutate adjacency, and this cache
## will need a version stamp.

var cells: Dictionary = {}  # int -> GraphCell

## Ascending cell ids. The canonical iteration order for the simulation.
var cell_ids: PackedInt32Array = PackedInt32Array()

var _path_cache: Dictionary = {}  # "from:to" -> PackedInt32Array


func add_cell(cell: GraphCell) -> void:
	cells[cell.id] = cell


func get_cell(id: int) -> GraphCell:
	if cells.has(id):
		return cells[id]
	return null


func size() -> int:
	return cells.size()


## Call once after all cells are added. Symmetrises edges, drops dangling ones,
## sorts adjacency so BFS tie-breaking is deterministic, and fixes iteration
## order.
func finalize() -> void:
	var ids: Array[int] = []
	for id in cells:
		ids.append(id)
	ids.sort()

	# Collect into sets first so a one-sided edge in the map data becomes a
	# proper undirected edge rather than a silently directional one.
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
	_path_cache.clear()


## Shortest path by hops, inclusive of both endpoints. Empty if unreachable.
## A path to self is a single element, which callers treat as no route.
func find_path(from_id: int, to_id: int) -> PackedInt32Array:
	var key := "%d:%d" % [from_id, to_id]
	if _path_cache.has(key):
		return _path_cache[key]
	var path := _bfs(from_id, to_id)
	_path_cache[key] = path
	return path


## Hops between two cells, or -1 if unreachable.
func distance(from_id: int, to_id: int) -> int:
	var path := find_path(from_id, to_id)
	if path.is_empty():
		return -1
	return path.size() - 1


func _bfs(from_id: int, to_id: int) -> PackedInt32Array:
	if not cells.has(from_id) or not cells.has(to_id):
		return PackedInt32Array()
	if from_id == to_id:
		return PackedInt32Array([from_id])

	var came_from: Dictionary = {from_id: -1}
	var queue: PackedInt32Array = PackedInt32Array([from_id])
	var head := 0

	while head < queue.size():
		var current := queue[head]
		head += 1
		# neighbor_ids is sorted ascending, so among equally short routes the
		# one through the lowest-id neighbour always wins. Fixed tie-breaking
		# keeps decay outcomes reproducible across runs.
		for n in cells[current].neighbor_ids:
			if came_from.has(n):
				continue
			came_from[n] = current
			if n == to_id:
				return _reconstruct(came_from, to_id)
			queue.append(n)

	return PackedInt32Array()


func _reconstruct(came_from: Dictionary, to_id: int) -> PackedInt32Array:
	var reversed: Array[int] = []
	var current: int = to_id
	while current != -1:
		reversed.append(current)
		current = came_from[current]
	reversed.reverse()
	return PackedInt32Array(reversed)
