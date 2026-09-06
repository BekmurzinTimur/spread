class_name MapLoader

## Builds a Graph from map JSON.
##
## Cell fields: id, x, y, neighbors, unlock_cost, tier, block, starts_unlocked.
##
## `tier` names the colour of orb that unlocks the cell and is omitted for red,
## so the overwhelming majority of cells carry no such key and the file stays
## close to what it was before a second tier existed.
##
## `block` is what the map buries in the cell — a BlockCatalog id, or absent for
## an empty cell. It is revealed to the player but only becomes usable once the
## cell is mined. Blocks exist in no other way, so the map fixes the supply.
##
## Ids are stable and authored, never derived from position in the file, so
## saves and hand-edits stay compatible.


static func load_from_file(path: String) -> Graph:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MapLoader: cannot open %s" % path)
		return null
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MapLoader: %s is not a JSON object" % path)
		return null
	return from_dict(parsed)


static func from_dict(data: Dictionary) -> Graph:
	var graph := Graph.new()

	for entry in data.get("cells", []):
		var cell := GraphCell.new()
		cell.id = int(entry["id"])
		cell.position = Vector2(float(entry["x"]), float(entry["y"]))
		cell.neighbor_ids = PackedInt32Array(entry.get("neighbors", []))
		cell.unlock_cost = int(entry.get("unlock_cost", 0))
		cell.required_tier = Tiers.from_name(String(entry.get("tier", "red")))
		cell.initial_block_id = String(entry.get("block", ""))
		if not cell.initial_block_id.is_empty() \
				and not BlockCatalog.has_def(cell.initial_block_id):
			push_error("MapLoader: cell %d buries unknown block '%s'"
				% [cell.id, cell.initial_block_id])
			cell.initial_block_id = ""
		graph.add_cell(cell)

	graph.finalize()

	# Cells the map hands over already mined go through exactly the same path a
	# mined cell takes, so a starting block cannot differ from a earned one.
	for entry in data.get("cells", []):
		if bool(entry.get("starts_unlocked", false)):
			graph.unlock_cell(int(entry["id"]))

	return graph


## A straight chain of `count` cells, 0..count-1. Used by tests to pin exact
## decay arithmetic without depending on the shipped map.
static func line_graph(count: int, spacing: float = 100.0) -> Graph:
	var graph := Graph.new()
	for i in count:
		var cell := GraphCell.new()
		cell.id = i
		cell.position = Vector2(i * spacing, 0.0)
		var neighbors: Array[int] = []
		if i > 0:
			neighbors.append(i - 1)
		if i < count - 1:
			neighbors.append(i + 1)
		cell.neighbor_ids = PackedInt32Array(neighbors)
		graph.add_cell(cell)
	graph.finalize()
	return graph
