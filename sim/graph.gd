class_name Graph
extends RefCounted

## Cells and their adjacency, plus shortest-path lookup.
##
## Edges are undirected and unit-weight: distance is hop count only.
##
## Routing is restricted to *discovered* cells — a cell is discovered when it has
## been mined or sits next to a mined one. Undiscovered ground is not a curtain
## over the map, it is an obstacle: orbs cannot cross it and the player cannot
## aim through it. Mining therefore grows the routable graph, which is why the
## path cache is dropped in `unlock_cell()` and why that is the only way to mine.
##
## `find_path_unrestricted()` ignores discovery and answers what the *map* is,
## rather than what the player has uncovered. Map validation needs that; the game
## never does.

var cells: Dictionary = {}  # int -> GraphCell

## Ascending cell ids. The canonical iteration order for the simulation.
var cell_ids: PackedInt32Array = PackedInt32Array()

## Restricted paths only. Dropped whenever a cell is mined, because that grows
## the discovered set and can open a shorter route.
var _path_cache: Dictionary = {}  # "from:to" -> PackedInt32Array

## Bumped every time a cell is actually mined. Anything derived from *which cells
## hold blocks* can compare against this to notice it has gone stale.
##
## A counter rather than a callback because mining has more than one caller —
## World's deliver phase, MapLoader's starting cells, and the tests' `_place()`
## helper all funnel through `unlock_cell()`, and a derived cache that only
## noticed one of them would be wrong in exactly the situations nobody tests.
var unlock_version: int = 0


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


# --- Discovery ----------------------------------------------------------


## Whether the player has uncovered this cell: mined, or next to something mined.
##
## Derived rather than stored, so it cannot drift out of step with the board and
## there is nothing extra to serialise. Cheap — degree is at most six. It only
## ever grows, because mining never reverses, which is what guarantees a route
## once valid stays valid.
func is_discovered(id: int) -> bool:
	var cell: GraphCell = cells.get(id)
	if cell == null:
		return false
	if cell.is_unlocked:
		return true
	for n in cell.neighbor_ids:
		if cells[n].is_unlocked:
			return true
	return false


## Mine a cell. The only way to do so — `GraphCell.apply_unlock()` must not be
## called directly, because mining grows the discovered set and every cached
## route was computed against the old one.
##
## Clearing the whole cache rather than stamping a version is deliberate: a cell
## unlocks at most once for the life of a game, so this runs a few dozen times
## in total.
func unlock_cell(id: int) -> void:
	var cell: GraphCell = cells.get(id)
	if cell == null:
		return
	var was_unlocked := cell.is_unlocked
	var had_block := cell.block != null
	cell.apply_unlock()
	# Re-mining an already-mined cell (which is how tests install a block) leaves
	# the discovered set alone, so the cache is still good.
	if not was_unlocked:
		_path_cache.clear()
	# The version tracks block placement, not discovery, so it also has to move
	# when an idempotent re-mine installs a block into a cell that had none —
	# which is precisely how `_place()` drops a sphere onto an already-mined cell.
	if not was_unlocked or (not had_block and cell.block != null):
		unlock_version += 1


# --- Pathing ------------------------------------------------------------


## Shortest path by hops through discovered cells, inclusive of both endpoints.
## Empty if unreachable, which includes "the target is still fogged". A path to
## self is a single element, which callers treat as no route.
func find_path(from_id: int, to_id: int) -> PackedInt32Array:
	var key := "%d:%d" % [from_id, to_id]
	if _path_cache.has(key):
		return _path_cache[key]
	var path := _bfs(from_id, to_id, true)
	_path_cache[key] = path
	return path


## Hops between two cells through discovered ground, or -1 if unreachable.
func distance(from_id: int, to_id: int) -> int:
	var path := find_path(from_id, to_id)
	if path.is_empty():
		return -1
	return path.size() - 1


## Shortest path ignoring discovery — what the map allows, not what the player
## has uncovered. For map validation only; the game itself always routes through
## `find_path()`. Uncached, because it is used a few thousand times in tests and
## never in play.
func find_path_unrestricted(from_id: int, to_id: int) -> PackedInt32Array:
	return _bfs(from_id, to_id, false)


## Hops between two cells ignoring discovery, or -1 if the map does not join
## them at all.
func distance_unrestricted(from_id: int, to_id: int) -> int:
	var path := find_path_unrestricted(from_id, to_id)
	if path.is_empty():
		return -1
	return path.size() - 1


## Every cell within `radius` hops of `from_id`, including `from_id` itself,
## ascending. Empty if the cell does not exist.
##
## Ignores discovery and lock state, unlike `find_path`: this answers a question
## about the board's shape rather than about a route the player may take, and its
## one caller — the sphere field — is a physical effect rather than a journey.
##
## Uncached on purpose. It runs once per sphere per rebuild, and rebuilds happen
## on mining and swapping rather than per tick, so there is nothing here worth
## the invalidation risk a cache would add.
func cells_within(from_id: int, radius: int) -> PackedInt32Array:
	if not cells.has(from_id) or radius < 0:
		return PackedInt32Array()

	var seen: Dictionary = {from_id: true}
	var frontier: PackedInt32Array = PackedInt32Array([from_id])
	for _step in radius:
		var next: PackedInt32Array = PackedInt32Array()
		for current in frontier:
			for n in cells[current].neighbor_ids:
				if seen.has(n):
					continue
				seen[n] = true
				next.append(n)
		if next.is_empty():
			break
		frontier = next

	var out: Array[int] = []
	for id in seen:
		out.append(id)
	out.sort()
	return PackedInt32Array(out)


func _bfs(from_id: int, to_id: int, discovered_only: bool) -> PackedInt32Array:
	if not cells.has(from_id) or not cells.has(to_id):
		return PackedInt32Array()
	if discovered_only and (not is_discovered(from_id) or not is_discovered(to_id)):
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
		# keeps decay outcomes reproducible across runs. Filtering for discovery
		# does not disturb that: it removes candidates, never reorders them.
		for n in cells[current].neighbor_ids:
			if came_from.has(n):
				continue
			if discovered_only and not is_discovered(n):
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
