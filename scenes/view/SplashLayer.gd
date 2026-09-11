extends Node2D

## The mark a delivery leaves: a ring of shards thrown outward from the cell that
## absorbed an orb, with a thin expanding ring behind them.
##
## A splash is five numbers and some trigonometry, not a node. Rings draw in
## `_draw()`; every shard of every splash is one instance batch, one draw call.
##
## Knows nothing about the simulation — no orbs, no cells, no ticks. It takes a
## position, a colour, a size and an age, the same shape `FloatingTextLayer` takes;
## `Main` does the translation from delivery events into calls on `spawn()`, and
## feeds both layers from the one drain.
##
## ⚠️ **The `randf()` below is view-only, and must stay that way.** `sim/` has no
## RNG by design — it is what makes the economy reproducible — and this is on the
## far side of that line: the angle it picks feeds nothing but this frame's
## drawing, and no simulation state is ever derived from it. A splash that
## *decided* something would put randomness back into the game.

## Seconds a splash lives for. Shorter than the floating text's 0.9 on purpose:
## the burst is the impact and the number is the information, so the burst should
## be gone while the number is still readable.
const LIFETIME := 0.55

## How many shards fly out. Odd, so the fan never reads as a symmetrical cross.
const SHARDS := 7

## How far a shard travels over its life, before `strength` scales it. About one
## cell radius, so a burst stays legibly attached to the cell that made it rather
## than spilling onto its neighbours.
const SHARD_DISTANCE := 52.0

## A shard's radius at birth. It shrinks to nothing over the lifetime.
const SHARD_RADIUS := 6.0

## The ring starts just outside the glyph and ends just outside the cell, so it
## reads as something leaving the cell rather than something landing on it.
const RING_START := 12.0
const RING_END := 68.0
const RING_WIDTH := 5.0

## The ring is quieter than the shards — it is the part that carries at low zoom,
## where individual shards are sub-pixel, and at full strength it would fight the
## selection and route chrome.
const RING_ALPHA := 0.55

## Fraction of the lifetime spent at full opacity, as in `FloatingTextLayer`.
## Fading from birth reads as a glitch rather than as an impact.
const HOLD := 0.35

## Hard ceiling. This one is closer to being reached than the text layer's: at 16x
## speed a single frame can drain dozens of deliveries, and a splash costs
## `SHARDS + 1` draw calls against a text's one. Reaching it degrades into dropped
## bursts, which on a board that busy is invisible.
const MAX_LIVE := 96

## Bounds on the size multiplier a caller may ask for. The floor keeps a 1-value
## trickle visible; the ceiling stops a heavily pumped orb throwing shards over
## the neighbouring cells.
const MIN_STRENGTH := 0.5
const MAX_STRENGTH := 1.6

var _splashes: Array[Dictionary] = []
var _shards: InstanceBatch


func _ready() -> void:
	# A child draws after its parent, so shards sit in front of the rings.
	_shards = InstanceBatch.new(InstanceBatch.disc(
		PackedFloat32Array([0.0, 0.85, 1.0]), PackedFloat32Array([1.0, 1.0, 0.0])))
	add_child(_shards)


## Burst at `at` (world space) in `color`.
##
## `strength` scales the whole figure — pass how big the delivery was relative to
## an ordinary orb, and a trickle pops smaller than a full arrival. Clamped here
## rather than at the call site, so the bound lives with the drawing it protects.
##
## `age` back-dates the splash: pass how long ago the thing it describes actually
## happened. A frame that catches many ticks up at once hands over a whole batch
## in one call, and without this they would all start together and fire as a
## single flash. Back-dated, each enters at the point of its arc it should already
## have reached, and anything older than a lifetime is dropped rather than shown
## late. Same contract as `FloatingTextLayer.spawn`, deliberately.
func spawn(at: Vector2, color: Color, strength: float = 1.0, age: float = 0.0) -> void:
	if age >= LIFETIME or _splashes.size() >= MAX_LIVE:
		return

	_splashes.append({
		"origin": at,
		"color": color,
		"scale": clampf(strength, MIN_STRENGTH, MAX_STRENGTH),
		# One angle per splash rather than one per shard: it is all the variation
		# needed to stop repeat deliveries at one cell looking stamped, and it
		# keeps an entry a fixed size however many shards are drawn from it.
		"angle": randf() * TAU,
		"age": maxf(age, 0.0),
	})


## Age every live splash and drop the expired ones. Driven by `Main`, like every
## other view node; deliberately independent of the simulation clock, so a burst
## finishes rather than freezing mid-air when the game is paused.
func advance(delta: float) -> void:
	if _splashes.is_empty():
		return

	var alive: Array[Dictionary] = []
	for entry in _splashes:
		entry["age"] = float(entry["age"]) + delta
		if float(entry["age"]) < LIFETIME:
			alive.append(entry)
	_splashes = alive


## How many are in the air. For tests and for anything that wants to know whether
## the cap is being reached.
func live_count() -> int:
	return _splashes.size()


func _draw() -> void:
	_shards.begin(_splashes.size() * SHARDS)
	for entry in _splashes:
		var k: float = clampf(float(entry["age"]) / LIFETIME, 0.0, 1.0)
		var origin: Vector2 = entry["origin"]
		var scale: float = entry["scale"]
		var alpha := fade(k)

		var color: Color = entry["color"]

		draw_arc(origin, ring_radius(k, scale), 0.0, TAU, 24,
			Color(color, alpha * RING_ALPHA), RING_WIDTH * (1.0 - k))

		var size := SHARD_RADIUS * scale * (1.0 - k) * 2.0
		if size <= 0.0:
			continue
		var shard_color := Color(color, alpha)
		for i in SHARDS:
			_shards.add(Transform2D(Vector2(size, 0.0), Vector2(0.0, size),
				origin + shard_offset(i, entry["angle"], k, scale)), shard_color)
	_shards.commit()


## Where shard `index` sits at life fraction `k`.
##
## Static and pure so the geometry is checked headlessly, the same way
## `GraphView.triangle_points()` and the gate blends are — the drawing above is
## then a thin enough wrapper to read.
##
## Shards fan on evenly spaced angles from `base_angle`, and each carries a fixed
## speed multiplier derived from its index rather than from a random draw: the
## golden-ratio step gives a spread that never repeats across the seven and costs
## no per-shard state to store.
static func shard_offset(index: int, base_angle: float, k: float, scale: float) -> Vector2:
	var angle := base_angle + TAU * float(index) / float(SHARDS)
	var speed := 0.75 + 0.35 * fmod(float(index) * 0.618, 1.0)
	# Ease out: the shards are fastest at the instant of impact and drift to a
	# stop, which is what makes it read as a splash rather than an expansion.
	var travel := SHARD_DISTANCE * scale * speed * (1.0 - pow(1.0 - k, 2.0))
	return Vector2(cos(angle), sin(angle)) * travel


## The ring's radius at life fraction `k`, on the same ease-out curve as the
## shards so the two halves of the figure move together.
static func ring_radius(k: float, scale: float) -> float:
	return lerpf(RING_START, RING_END * scale, 1.0 - pow(1.0 - k, 2.0))


## Opacity at life fraction `k`: full until `HOLD`, then out. Matches the floating
## text's curve, so a burst and the number over it fade as one thing.
static func fade(k: float) -> float:
	return 1.0 - smoothstep(HOLD, 1.0, k)
