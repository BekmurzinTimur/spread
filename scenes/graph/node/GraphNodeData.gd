class_name GraphNodeData
extends Resource

@export var id: int
@export var position: Vector2
@export var neighbor_ids: Array[int]

@export var is_unlocked: bool = false
@export var unlock_cost_tier: int
@export var unlock_cost_amount: int
@export var unlock_progress: float = 0.0

@export var node_type: int = 0   # NodeType enum
@export var tier: int
@export var block_data: Dictionary = {}

@export var target_id: int = -1
@export var resolved_path: Array[int] = []
