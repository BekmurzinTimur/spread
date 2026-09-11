extends Node2D

## Draws orbs in flight, interpolated between ticks.
##
## One hop each, so there is no route to follow — just a lerp from the frontier
## cell that fired to the locked cell it is opening, with a short trail behind
## it. A crit is visibly larger and brighter for the whole flight, because it was
## rolled at emission rather than at landing.
##
## Orbs and trails are two instance batches: one draw call each at any orb count.

const RADIUS := 8.0
const CRIT_RADIUS := 15.0

## Halo reach as a multiple of the core radius. The orb texture's core edge sits
## at 1 / HALO of its radius.
const HALO := 1.8

const TRAIL_LENGTH := 0.22
const TRAIL_WIDTH := 4.0

var world: World

## How far into the current tick the frame is, 0..1. Set by Main so orbs move
## smoothly at 10 Hz.
var render_alpha: float = 0.0

var _trails: InstanceBatch
var _orbs: InstanceBatch
var _region_colors: Array[Color] = []


func _ready() -> void:
	for region in Regions.COUNT:
		_region_colors.append(Regions.color_of(region))
	_trails = InstanceBatch.new()
	add_child(_trails)
	_orbs = InstanceBatch.new(InstanceBatch.disc(
		PackedFloat32Array([0.0, 0.52, 0.58, 0.85, 1.0]),
		PackedFloat32Array([1.0, 1.0, 0.2, 0.12, 0.0])))
	add_child(_orbs)


## Refill both batches. Called by Main every frame.
func refresh() -> void:
	var count := world.orbs.size() if world != null else 0
	_trails.begin(count)
	_orbs.begin(count)

	for i in count:
		var orb: Orb = world.orbs[i]
		if orb.dead:
			continue
		var from := world.graph.get_cell(orb.from_id)
		var to := world.graph.get_cell(orb.to_id)
		if from == null or to == null:
			continue

		var t := clampf(
			(float(orb.ticks_in_hop) + render_alpha) / float(World.HOP_TICKS),
			0.0, 1.0)
		var at := from.position.lerp(to.position, t)
		var tail := from.position.lerp(to.position, maxf(0.0, t - TRAIL_LENGTH))

		var hue := _region_colors[to.region]
		var color := Color(1.0, 0.98, 0.9) if orb.is_crit else hue.lerp(Color.WHITE, 0.45)
		var size := (CRIT_RADIUS if orb.is_crit else RADIUS) * HALO * 2.0

		# A quad stretched along the segment.
		var along := at - tail
		_trails.add(Transform2D(along, along.orthogonal().normalized() * TRAIL_WIDTH,
			(tail + at) * 0.5), Color(color, 0.35))
		_orbs.add(Transform2D(Vector2(size, 0.0), Vector2(0.0, size), at), color)

	_trails.commit()
	_orbs.commit()
