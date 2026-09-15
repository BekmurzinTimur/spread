extends Node2D

## The mark a delivery leaves: a ring of shards thrown outward from the cell that
## absorbed an orb, with a thin expanding ring behind them.
##
## A fixed ring buffer of bursts in one MultiMesh. The CPU writes a slot on
## `spawn()`; `splash.gdshader` animates every burst from its birth time, so the
## per-frame cost does not grow with the number alive. When full, a new burst
## replaces the oldest.
##
## Knows nothing about the simulation. `Main` translates delivery events into
## `spawn()` calls.
##
## ⚠️ **The `randf()` below is view-only, and must stay that way.** No simulation
## state is ever derived from it.

## Seconds a splash lives for. Shorter than the floating text's 0.9 on purpose:
## the burst is the impact and the number is the information.
const LIFETIME := 0.55

## How many shards fly out. Odd, so the fan never reads as a symmetrical cross.
const SHARDS := 7

## How far a shard travels over its life, before `strength` scales it.
const SHARD_DISTANCE := 52.0

## A shard's radius at birth. It shrinks to nothing over the lifetime.
const SHARD_RADIUS := 6.0

## The ring starts just outside the glyph and ends just outside the cell.
const RING_START := 12.0
const RING_END := 68.0
const RING_WIDTH := 5.0

## The ring is quieter than the shards; it is what carries at low zoom.
const RING_ALPHA := 0.55

## Fraction of the lifetime spent at full opacity.
const HOLD := 0.35

## Bursts alive at once. Past this, a new burst replaces the oldest.
const CAPACITY := 8192

## Bounds on the size multiplier a caller may ask for.
const MIN_STRENGTH := 0.5
const MAX_STRENGTH := 1.6

## Floats per slot: transform (8), colour (4), custom (4).
const STRIDE := 16
const CUSTOM := 12

## `now` is rebased past this, so float32 birth times stay precise.
const REBASE_AFTER := 1000.0

var _data := PackedFloat32Array()
var _batch: MultiMeshInstance2D
var _material: ShaderMaterial
var _head := 0
var _used := 0
var _now := 0.0
var _dirty := false


func _ready() -> void:
	_data.resize(CAPACITY * STRIDE)

	_material = ShaderMaterial.new()
	_material.shader = preload("res://scenes/view/splash.gdshader")
	_material.set_shader_parameter("lifetime", LIFETIME)
	_material.set_shader_parameter("hold", HOLD)
	_material.set_shader_parameter("shards", SHARDS)
	_material.set_shader_parameter("shard_distance", SHARD_DISTANCE)
	_material.set_shader_parameter("shard_radius", SHARD_RADIUS)
	_material.set_shader_parameter("ring_start", RING_START)
	_material.set_shader_parameter("ring_end", RING_END)
	_material.set_shader_parameter("ring_width", RING_WIDTH)
	_material.set_shader_parameter("ring_alpha", RING_ALPHA)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = QuadMesh.new()
	multimesh.custom_aabb = InstanceBatch.BOUNDS
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0

	_batch = MultiMeshInstance2D.new()
	_batch.multimesh = multimesh
	_batch.material = _material
	add_child(_batch)


## Burst at `at` (world space) in `color`.
##
## `strength` scales the whole figure. `age` back-dates it: a frame that catches
## many ticks up spawns a batch, and back-dating keeps them from firing as one
## flash. Anything older than a lifetime is dropped.
func spawn(at: Vector2, color: Color, strength: float = 1.0, age: float = 0.0) -> void:
	if age >= LIFETIME:
		return

	var burst_scale := clampf(strength, MIN_STRENGTH, MAX_STRENGTH)
	# Half-size of the quad: covers the ring and the farthest shard.
	var extent := maxf(maxf(RING_START, RING_END * burst_scale) + RING_WIDTH,
		SHARD_DISTANCE * burst_scale * 1.1 + SHARD_RADIUS * burst_scale) + 2.0
	_write(at, color, age, randf() * TAU, burst_scale, extent)


## A lone ring expanding from `at` out to `radius`, in the same batch as bursts.
func spawn_ring(at: Vector2, color: Color, radius: float, age: float = 0.0) -> void:
	if age >= LIFETIME:
		return
	# A negative angle tells the shader to skip shards; scale carries the radius.
	_write(at, color, age, -1.0, radius, radius + RING_WIDTH + 2.0)


func _write(at: Vector2, color: Color, age: float, angle: float, burst_scale: float,
		extent: float) -> void:
	var size := extent * 2.0
	var o := _head * STRIDE
	_data[o] = size
	_data[o + 1] = 0.0
	_data[o + 2] = 0.0
	_data[o + 3] = at.x
	_data[o + 4] = 0.0
	_data[o + 5] = size
	_data[o + 6] = 0.0
	_data[o + 7] = at.y
	_data[o + 8] = color.r
	_data[o + 9] = color.g
	_data[o + 10] = color.b
	_data[o + 11] = color.a
	_data[o + 12] = _now - maxf(age, 0.0)
	_data[o + 13] = angle
	_data[o + 14] = burst_scale
	_data[o + 15] = extent

	_used = maxi(_used, _head + 1)
	_head = (_head + 1) % CAPACITY
	_dirty = true


## Advance the clock and upload this frame's spawns. Driven by `Main` on real
## time, so bursts finish while the game is paused.
func advance(delta: float) -> void:
	_now += delta
	if _now > REBASE_AFTER:
		_rebase()
	_material.set_shader_parameter("now", _now)
	if _dirty:
		_batch.multimesh.buffer = _data
		_batch.multimesh.visible_instance_count = _used
		_dirty = false


func _rebase() -> void:
	_now -= REBASE_AFTER
	for i in _used:
		_data[i * STRIDE + CUSTOM] -= REBASE_AFTER
	_dirty = true
