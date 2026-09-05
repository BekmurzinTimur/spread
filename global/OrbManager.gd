extends Node

var orbs: Array[OrbData] = []
var orb_scene := preload("res://scenes/graph/orb/Orb.tscn")
var orbs_layer: Node2D

func spawn_orb(tier: int, path: Array[int]) -> void:
	var data = OrbData.new()
	data.tier = tier
	data.path = path
	data.will_survive = randf() > get_loss_chance(path)
	orbs.append(data)

	var visual = orb_scene.instantiate()
	visual.setup(data)
	orbs_layer.add_child(visual)

func get_loss_chance(path: Array[int]) -> float:
	return 0.0

func _process(delta: float) -> void:
	for orb in orbs:
		advance_orb(orb, delta)

func advance_orb(orb: OrbData, delta: float) -> void:
	pass
