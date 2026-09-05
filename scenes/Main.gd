extends Node2D

@onready var nodes_layer := $GraphContainer/NodesLayer
@onready var edges_layer := $GraphContainer/EdgesLayer
@onready var orbs_layer := $GraphContainer/OrbsLayer

var graph_node_scene := preload("res://scenes/graph/node/Node.tscn")

func _ready() -> void:
	OrbManager.orbs_layer = orbs_layer
	GraphData.load_level("res://graph/graph_data.json")
	spawn_node_visuals()
	spawn_edge_visuals()

func spawn_node_visuals() -> void:
	for id in GraphData.nodes:
		var data: GraphNodeData = GraphData.nodes[id]
		var visual = graph_node_scene.instantiate()
		nodes_layer.add_child(visual)
		visual.setup(data)
		visual.position = data.position

func spawn_edge_visuals() -> void:
	for id in GraphData.nodes:
		var data: GraphNodeData = GraphData.nodes[id]
		for n_id in data.neighbor_ids:
			if n_id > id:
				var line := Line2D.new()
				line.points = [data.position, GraphData.nodes[n_id].position]
				edges_layer.add_child(line)
