extends Node2D

## Draws orbs in flight.
##
## One hop each: a slide from the cell that fired to the cell it lands on, with a
## short trail. A crit is larger and brighter for the whole flight.
##
## Each orb is written once, on the tick it is born, into a ring buffer;
## `orb.gdshader` moves it from its birth tick. Per-frame cost does not grow with
## orbs alive. Orbs and trails are two MultiMeshes with the same slots.

const RADIUS := 8.0
const CRIT_RADIUS := 15.0

## Halo reach as a multiple of the core radius. The orb texture's core edge sits
## at 1 / HALO of its radius.
const HALO := 1.8

const TRAIL_LENGTH := 0.22
const TRAIL_WIDTH := 4.0
const TRAIL_ALPHA := 0.35
const CRIT_COLOR := Color(1.0, 0.98, 0.9)

## Orbs alive at once. A tick born with more than a hop's share is sampled.
const CAPACITY := 8192

## Floats per slot: transform (8), colour (4), custom (4).
const STRIDE := 16
const CUSTOM := 12

## Birth ticks are stored relative to a base, rebased past this so float32 stays exact.
const REBASE_AFTER := 4096

var world: World

## Ram orbs are drawn there as beams, not here. Set by Main.
var beams: Node2D

## How far into the current tick the frame is, 0..1. Set by Main.
var render_alpha: float = 0.0

var _orbs: MultiMeshInstance2D
var _trails: MultiMeshInstance2D
var _orb_data := PackedFloat32Array()
var _trail_data := PackedFloat32Array()
var _head := 0
var _used := 0
var _dirty := false

## The world the buffer was written from, and the last tick written.
var _written_world: World
var _last_tick := 0
var _base_tick := 0

var _colors: Array[Color] = []


func _ready() -> void:
	for region in Regions.COUNT:
		_colors.append(Regions.color_of(region).lerp(Color.WHITE, 0.45))
	_orb_data.resize(CAPACITY * STRIDE)
	_trail_data.resize(CAPACITY * STRIDE)
	_trails = _make_batch(null, true)
	_orbs = _make_batch(InstanceBatch.disc(
		PackedFloat32Array([0.0, 0.52, 0.58, 0.85, 1.0]),
		PackedFloat32Array([1.0, 1.0, 0.2, 0.12, 0.0])), false)


func _make_batch(texture: Texture2D, is_trail: bool) -> MultiMeshInstance2D:
	var material := ShaderMaterial.new()
	material.shader = preload("res://scenes/view/orb.gdshader")
	material.set_shader_parameter("hop_ticks", float(World.HOP_TICKS))
	material.set_shader_parameter("trail", is_trail)
	material.set_shader_parameter("trail_length", TRAIL_LENGTH)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = QuadMesh.new()
	multimesh.custom_aabb = InstanceBatch.BOUNDS
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0

	var batch := MultiMeshInstance2D.new()
	batch.multimesh = multimesh
	batch.material = material
	batch.texture = texture
	add_child(batch)
	return batch


## Write the ticks born since last frame and advance the clock. Called by Main every frame.
func refresh() -> void:
	if world != _written_world:
		_reset()
	if world == null:
		return

	var now := world.tick_count
	if now > _last_tick:
		for tick in range(maxi(_last_tick + 1, now - World.HOP_TICKS + 1), now + 1):
			_write_tick(world.orbs_born_on(tick))
		_last_tick = now
	if now - _base_tick > REBASE_AFTER:
		_rebase(now)
	if _dirty:
		_orbs.multimesh.buffer = _orb_data
		_trails.multimesh.buffer = _trail_data
		_orbs.multimesh.visible_instance_count = _used
		_trails.multimesh.visible_instance_count = _used
		_dirty = false

	var time := float(now - _base_tick) + render_alpha
	(_orbs.material as ShaderMaterial).set_shader_parameter("sim_time", time)
	(_trails.material as ShaderMaterial).set_shader_parameter("sim_time", time)


func _reset() -> void:
	_written_world = world
	_head = 0
	_used = 0
	_last_tick = world.tick_count if world != null else 0
	_base_tick = _last_tick
	_orbs.multimesh.visible_instance_count = 0
	_trails.multimesh.visible_instance_count = 0


func _write_tick(born: Array[Orb]) -> void:
	var step := maxi(1, ceili(float(born.size()) * World.HOP_TICKS / CAPACITY))
	# Sampling could skip a ram orb, so with ram bounces every orb is looked at.
	var stride := 1 if world.ram_bounces() else step
	for i in range(0, born.size(), stride):
		var orb := born[i]
		if orb.from_ram:
			if beams != null:
				beams.add_hop(world.graph.cells[orb.from_id].position,
					world.graph.cells[orb.to_id].position, orb.born_tick)
			continue
		if i % step != 0:
			continue
		var from: Vector2 = world.graph.cells[orb.from_id].position
		var to: GraphCell = world.graph.cells[orb.to_id]
		var delta := to.position - from
		var color := CRIT_COLOR if orb.is_crit else _colors[to.region]
		var size := (CRIT_RADIUS if orb.is_crit else RADIUS) * HALO * 2.0
		var birth := float(orb.born_tick - _base_tick)
		var lead := orb.lead_permille * 0.001
		var o := _head * STRIDE

		# Orb: a size-wide quad at `from`, slid along `delta` by the shader.
		_orb_data[o] = size
		_orb_data[o + 1] = 0.0
		_orb_data[o + 2] = 0.0
		_orb_data[o + 3] = from.x
		_orb_data[o + 4] = 0.0
		_orb_data[o + 5] = size
		_orb_data[o + 6] = 0.0
		_orb_data[o + 7] = from.y
		_orb_data[o + 8] = color.r
		_orb_data[o + 9] = color.g
		_orb_data[o + 10] = color.b
		_orb_data[o + 11] = color.a
		_orb_data[o + 12] = birth
		_orb_data[o + 13] = delta.x / size
		_orb_data[o + 14] = delta.y / size
		_orb_data[o + 15] = lead

		# Trail: local x along `delta`, y across; the shader picks the stretch.
		var across := delta.orthogonal().normalized() * TRAIL_WIDTH
		_trail_data[o] = delta.x
		_trail_data[o + 1] = across.x
		_trail_data[o + 2] = 0.0
		_trail_data[o + 3] = from.x
		_trail_data[o + 4] = delta.y
		_trail_data[o + 5] = across.y
		_trail_data[o + 6] = 0.0
		_trail_data[o + 7] = from.y
		_trail_data[o + 8] = color.r
		_trail_data[o + 9] = color.g
		_trail_data[o + 10] = color.b
		_trail_data[o + 11] = TRAIL_ALPHA
		_trail_data[o + 12] = birth
		_trail_data[o + 13] = 0.0
		_trail_data[o + 14] = 0.0
		_trail_data[o + 15] = lead

		_used = maxi(_used, _head + 1)
		_head = (_head + 1) % CAPACITY
		_dirty = true


func _rebase(now: int) -> void:
	var shift := float(now - _base_tick)
	_base_tick = now
	for i in _used:
		_orb_data[i * STRIDE + CUSTOM] -= shift
		_trail_data[i * STRIDE + CUSTOM] -= shift
	_dirty = true
