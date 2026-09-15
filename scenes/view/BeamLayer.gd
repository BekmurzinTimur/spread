extends Node2D

## The ram's light, above the orbs: the shot's beam and, with Ram bounce, every hop
## after it. Few alive at once, so plain draw calls.

## The shot: board dims, beam streaks out, impact blooms.
const BEAM_TIME := 0.7
const BEAM_WIDTH := 10.0
const DIM_ALPHA := 0.45
const COLOR := Color(1.0, 0.97, 0.85)

## A hop streaks over its flight, then fades over this many ticks.
const HOP_FADE_TICKS := 3.0
const HOP_WIDTH := 7.0
const HEAD_RADIUS := 9.0

## A wide, faint line under each ray.
const GLOW_SCALE := 3.0
const GLOW_ALPHA := 0.25

var world: World
var camera: Camera2D

## How far into the current tick the frame is, 0..1. Set by Main.
var render_alpha: float = 0.0

var _beam_from := Vector2.ZERO
var _beam_to := Vector2.ZERO
var _beam_age := -1.0

var _hop_from := PackedVector2Array()
var _hop_to := PackedVector2Array()
var _hop_birth := PackedInt32Array()
var _bound_world: World

## Where hops started since Main last asked, for their sound.
var _launches := PackedVector2Array()


func fire_beam(from: Vector2, to: Vector2) -> void:
	_beam_from = from
	_beam_to = to
	_beam_age = 0.0


## A ram orb born on `birth_tick`. Called by OrbLayer, which skips drawing it.
func add_hop(from: Vector2, to: Vector2, birth_tick: int) -> void:
	_hop_from.append(from)
	_hop_to.append(to)
	_hop_birth.append(birth_tick)
	_launches.append(from)


func take_launches() -> PackedVector2Array:
	var launches := _launches
	_launches = PackedVector2Array()
	return launches


func advance(delta: float) -> void:
	if _beam_age >= 0.0:
		_beam_age += delta
		if _beam_age >= BEAM_TIME:
			_beam_age = -1.0
	if world != _bound_world:
		_bound_world = world
		_hop_from.clear()
		_hop_to.clear()
		_hop_birth.clear()
		return
	var now := _now()
	var i := 0
	while i < _hop_birth.size():
		if now - _hop_birth[i] >= World.HOP_TICKS + HOP_FADE_TICKS:
			_hop_from.remove_at(i)
			_hop_to.remove_at(i)
			_hop_birth.remove_at(i)
		else:
			i += 1


func _now() -> float:
	return float(world.tick_count) + render_alpha if world != null else 0.0


func _draw() -> void:
	if _beam_age >= 0.0:
		var t := _beam_age / BEAM_TIME
		if camera != null:
			draw_rect(camera.visible_world_rect(), Color(0.0, 0.0, 0.0, DIM_ALPHA * (1.0 - t)))
		var head := _beam_from.lerp(_beam_to, minf(1.0, t * 8.0))
		_draw_ray(_beam_from, head, BEAM_WIDTH, 1.0 - t * 0.6)
		if t > 0.4:
			var bloom := (t - 0.4) / 0.6
			draw_circle(_beam_to, 20.0 + 90.0 * bloom, Color(COLOR, 0.5 * (1.0 - bloom)))

	if world == null:
		return
	var now := _now()
	for i in _hop_birth.size():
		var flown := (now - float(_hop_birth[i])) / World.HOP_TICKS
		if flown < 0.0:
			continue
		var head := _hop_from[i].lerp(_hop_to[i], minf(flown, 1.0))
		var fade := 1.0 - clampf((flown - 1.0) * World.HOP_TICKS / HOP_FADE_TICKS, 0.0, 1.0)
		_draw_ray(_hop_from[i], head, HOP_WIDTH, fade)
		if flown < 1.0:
			draw_circle(head, HEAD_RADIUS, COLOR)


func _draw_ray(from: Vector2, to: Vector2, width: float, alpha: float) -> void:
	draw_line(from, to, Color(COLOR, alpha * GLOW_ALPHA), width * GLOW_SCALE)
	draw_line(from, to, Color(COLOR, alpha), width)
