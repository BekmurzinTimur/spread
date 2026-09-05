extends Node

var nodes: Dictionary = {}   # id -> GraphNodeData
var astar := AStar2D.new()

func load_level(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	nodes.clear()
	for entry in json["nodes"]:
		var n = GraphNodeData.new()
		n.id = entry["id"]
		n.position = Vector2(entry["x"], entry["y"])
		n.neighbor_ids = entry["neighbors"]
		n.unlock_cost_tier = entry["unlock_tier"]
		n.unlock_cost_amount = entry["unlock_amount"]
		n.node_type = entry.get("predetermined_type", 0)
		nodes[n.id] = n
	rebuild_astar()

func rebuild_astar() -> void:
	astar.clear()
	for id in nodes:
		astar.add_point(id, nodes[id].position)
	for id in nodes:
		for n_id in nodes[id].neighbor_ids:
			if nodes[id].is_unlocked and nodes.has(n_id) and nodes[n_id].is_unlocked:
				if not astar.are_points_connected(id, n_id):
					astar.connect_points(id, n_id)

func _get_path(from_id: int, to_id: int) -> Array[int]:
	var result: Array[int] = []
	for p in astar.get_id_path(from_id, to_id):
		result.append(p)
	return result
