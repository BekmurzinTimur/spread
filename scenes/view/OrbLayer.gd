extends Node2D

## Draws every orb in a single pass.
##
## The simulation moves orbs in whole ticks; `render_alpha` is the fraction of
## the current tick already elapsed, so orbs glide instead of stepping. Nothing
## here feeds back into the simulation — the view is free to be frame-rate
## dependent because the economy is not.

## Radius at full value; shrinks as an orb decays, so a dying orb reads as one.
const MAX_RADIUS := 8.0
const MIN_RADIUS := 2.5

## How far, in world units, the outermost lane swings from the edge line. Edges
## are ~190 long and adjacent hex edges are ~95 apart at their midpoints, so 16
## separates opposing lanes by two orb diameters without an orb ever reading as
## sitting on the wrong edge. This is the only knob worth turning.
const WEAVE_AMPLITUDE := 16.0

## Lateral lanes, as a fraction of WEAVE_AMPLITUDE. Every one is non-zero, so
## every orb on the board visibly travels a sine — a zero lane would read as a
## generator whose output simply does not weave, which is the effect this exists
## to produce. Ordered widest-apart first: with two sources on a corridor they
## take the full swing either side of the line, and the narrower pairs only come
## into play once a corridor is genuinely crowded.
const LANES: Array[float] = [1.0, -1.0, 0.5, -0.5, 0.75, -0.75]

var world: World
var render_alpha: float = 0.0

var _lanes: Dictionary = {}  # source cell id -> lane, a fraction of WEAVE_AMPLITUDE
var _next_lane: int = 0


func _draw() -> void:
	if world == null:
		return
	for orb in world.orbs:
		if orb.dead:
			continue
		var from := world.graph.get_cell(orb.current_cell_id())
		var to := world.graph.get_cell(orb.next_cell_id())
		if from == null or to == null:
			continue

		var t := clampf((float(orb.ticks_in_hop) + render_alpha) / float(World.TICKS_PER_HOP),
			0.0, 1.0)
		var pos := from.position.lerp(to.position, t)
		pos += _weave_offset(orb, from.position, to.position, t)

		# Clamped, because pumps stack with no ceiling: a well-supported orb is
		# worth more than it launched with, and an unclamped ratio would keep
		# growing the circle until it swallowed the cell it is crossing.
		var fullness := float(orb.value) / float(World.ORB_START_VALUE)
		var radius: float = lerpf(MIN_RADIUS, MAX_RADIUS, clampf(fullness, 0.0, 1.0))
		var color := Tiers.color_of(orb.tier)

		draw_circle(pos, radius + 2.0, Color(color, 0.20))
		draw_circle(pos, radius, color)


## Lateral sine offset, perpendicular to the direction of travel, so orbs sharing
## a corridor braid instead of stacking on one line.
##
## Parameterised by hops travelled rather than by progress within the hop, which
## is what makes `sin(PI * s)` land on exactly zero at every cell centre. Three
## things follow, and they are why the wavelength is fixed at two hops rather
## than exposed as a constant:
##
## - The perpendicular flips wherever a route turns — up to 120 degrees on a hex
##   lattice — but the offset it multiplies is zero at exactly those moments, so
##   there is nothing to blend and no visible jump.
## - An orb converges onto the cell it delivers into, so the `+N` FloatingTextLayer
##   floats over that cell lines up with where the orb visibly arrived.
## - The sign alternates each hop, so a route reads as a snake rather than as the
##   same bulge repeated.
func _weave_offset(orb: Orb, from: Vector2, to: Vector2, t: float) -> Vector2:
	var dir := to - from
	# Zero-length when the orb sits at the end of its route: next_cell_id() then
	# returns the current cell. Those orbs are dead before _draw sees them, but
	# the guard keeps that from being load-bearing.
	if dir.length_squared() <= 0.0:
		return Vector2.ZERO

	var normal := Vector2(-dir.y, dir.x) / dir.length()
	var hops_travelled := float(orb.hop_index) + t
	return normal * WEAVE_AMPLITUDE * _lane_of(orb.source_id) * sin(PI * hops_travelled)


## A source's lane, handed out in the order sources are first seen emitting.
##
## First-come assignment rather than arithmetic on the cell id, because any
## modulo of an id collides in clumps: `gen_map.py` numbers cells row-major, so
## the generators most likely to share a corridor are exactly the ones with
## nearby ids. Hashing is no better — five sources into six lanes collide by
## birthday far more often than not. Handing out lanes in order instead gives
## every source its own while any are left, whatever ids the next regenerated
## map happens to use.
##
## Keyed by source rather than by orb so a generator's output travels as one
## strand, and an orb keeps its lane for its whole flight. Orbs from one source
## on one route never coincide anyway: the produce interval is 20 ticks against
## 10 per hop, so they are always two hops apart.
##
## The view may only learn of a source once the player has uncovered it, which is
## the point — this reads `source_id` off an orb already on screen, never
## `initial_block_id`, so it cannot leak what is still buried.
func _lane_of(source_id: int) -> float:
	if not _lanes.has(source_id):
		_lanes[source_id] = LANES[_next_lane % LANES.size()]
		_next_lane += 1
	return _lanes[source_id]
