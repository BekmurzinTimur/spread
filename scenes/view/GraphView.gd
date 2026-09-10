extends Node2D

## Draws the board.
##
## Two independent colour channels, and keeping them apart is the whole readout:
## **hue is depth** (which band a cell sits in) and **glow is rarity** (how big a
## node it holds). One look answers both without them fighting.
##
## The eye goes to the edge because that is where the game is: frontier cells
## breathe, interior cells hold a dim still light.

const CELL_RADIUS := 44.0
const HEX_POINTS := 6

## How far the breathing swings, and how fast.
const BREATHE_SPEED := 2.2
const BREATHE_DEPTH := 0.28

## Scale overshoot and shockwave when a cell pops.
const POP_TIME := 0.45
const POP_SCALE := 0.55
const POP_RING := 3.2

const COLOR_GROUND := Color("0d0f14")
const COLOR_LOCKED_FILL := Color("11141a")
const COLOR_TEXT := Color("c3cad6")
const COLOR_EDGE := Color("272b33")
const EDGE_WIDTH := 3.0

## Below this zoom the per-cell numbers are skipped — at radius 24 a zoomed-out
## board is otherwise a wall of unreadable digits.
const TEXT_MIN_ZOOM := 0.28
const NUMBER_SIZE := 24

## Interior cells sit this far down from their band's hue; frontier cells ride
## the breath above it.
const INTERIOR_DIM := 0.30
const LOCKED_RING_DIM := 0.42

## Node glow radius per tier: none, common, rare, keystone.
const GLOW_RADIUS: PackedFloat32Array = [0.0, 28.0, 48.0, 76.0]

## The lance shot: board dims, beam streaks out, impact blooms.
const BEAM_TIME := 0.7
const BEAM_WIDTH := 10.0
const DIM_ALPHA := 0.45

var world: World
var camera: Camera2D

## Seconds, for the breathing cycle. Advanced by Main so a paused board holds
## still instead of breathing at nothing.
var clock: float = 0.0

## Cell under the cursor, for the lance preview. -1 for none.
var hovered_id: int = -1

## cell id -> seconds since it popped.
var _pops: Dictionary = {}

var _beam_from: Vector2 = Vector2.ZERO
var _beam_to: Vector2 = Vector2.ZERO
var _beam_age: float = -1.0

var _font: Font
var _font_size: int


func _ready() -> void:
	var label := Label.new()
	_font = label.get_theme_font("font")
	_font_size = label.get_theme_font_size("font_size") * 2
	label.queue_free()


func pop(cell_id: int) -> void:
	_pops[cell_id] = 0.0


func fire_beam(from: Vector2, to: Vector2) -> void:
	_beam_from = from
	_beam_to = to
	_beam_age = 0.0


func advance(delta: float) -> void:
	clock += delta
	if _beam_age >= 0.0:
		_beam_age += delta
		if _beam_age >= BEAM_TIME:
			_beam_age = -1.0
	if _pops.is_empty():
		return
	var done: Array = []
	for id in _pops:
		var age: float = _pops[id] + delta
		if age >= POP_TIME:
			done.append(id)
		else:
			_pops[id] = age
	for id in done:
		_pops.erase(id)


func _draw() -> void:
	if world == null:
		return

	# 1,801 cells is far more than fits on screen at play zoom, so cull. Without
	# this the whole board is re-tessellated every frame for the sake of a few
	# hundred visible hexes.
	var view := Rect2()
	if camera != null:
		view = camera.visible_world_rect().grow(CELL_RADIUS * 4.0)

	var breath := 1.0 + sin(clock * BREATHE_SPEED) * BREATHE_DEPTH
	var show_numbers := camera == null or camera.zoom.x >= TEXT_MIN_ZOOM

	_draw_edges(view)

	for id in world.graph.cell_ids:
		var cell: GraphCell = world.graph.cells[id]
		if camera != null and not view.has_point(cell.position):
			continue
		_draw_cell(cell, breath, show_numbers)

	_draw_ram(view, breath)


## One line per adjacent pair, drawn once by only emitting the low-id side.
## Beneath the cells, so a hex always sits on top of its own edges.
func _draw_edges(view: Rect2) -> void:
	for id in world.graph.cell_ids:
		var cell: GraphCell = world.graph.cells[id]
		if camera != null and not view.has_point(cell.position):
			continue
		if world.visibility_of(id) == 0 and not cell.is_mined:
			continue
		for n in cell.neighbor_ids:
			if n < id:
				continue
			var other: GraphCell = world.graph.cells[n]
			if world.visibility_of(n) == 0 and not other.is_mined:
				continue
			draw_line(cell.position, other.position, COLOR_EDGE, EDGE_WIDTH, true)


## The one thing the player aims. Any unmined cell is a target — the pool is the
## only limit — so this highlights what is under the cursor rather than painting
## a range.
func _draw_ram(view: Rect2, breath: float) -> void:
	if _beam_age >= 0.0:
		var t := _beam_age / BEAM_TIME
		# Board dims for a beat, then the beam and the bloom.
		draw_rect(view, Color(0.0, 0.0, 0.0, DIM_ALPHA * (1.0 - t)))
		var head := _beam_from.lerp(_beam_to, minf(1.0, t * 2.5))
		draw_line(_beam_from, head, Color(1.0, 0.97, 0.85, 1.0 - t * 0.6),
			BEAM_WIDTH, true)
		if t > 0.4:
			var bloom := (t - 0.4) / 0.6
			draw_circle(_beam_to, 20.0 + 90.0 * bloom,
				Color(1.0, 0.97, 0.85, 0.5 * (1.0 - bloom)))
		return

	if hovered_id < 0 or not world.can_ram_at(hovered_id):
		return

	var target: GraphCell = world.graph.cells[hovered_id]
	var damage := world.ram_damage()
	var kills := damage >= target.remaining()
	var color := Color(1.0, 0.97, 0.85) if kills else Color(0.95, 0.72, 0.45)

	_draw_hex_outline(target.position, CELL_RADIUS + 4.0,
		Color(color, 0.55 + 0.35 * breath), 2.5)
	draw_circle(target.position, CELL_RADIUS * 1.8, Color(color, 0.10))

	# What the shot would actually do, so a partial ram reads as a down payment
	# rather than a miss.
	var label := "RAM %s" % Format.thousands(damage)
	if not kills:
		label = "%s  (%s left)" % [label,
			Format.thousands(target.remaining() - damage)]
	_label(label, target.position + Vector2(0.0, CELL_RADIUS + 30.0), color)


func _draw_cell(cell: GraphCell, breath: float, show_numbers: bool) -> void:
	var hue := Bands.color_of(cell.band)
	var visibility := world.visibility_of(cell.id)
	var scale := 1.0

	if _pops.has(cell.id):
		# Overshoot then settle. The cell is the reward, so it gets the motion.
		var t: float = _pops[cell.id] / POP_TIME
		scale += POP_SCALE * (1.0 - t) * (1.0 - t)
		var ring := CELL_RADIUS * (1.0 + POP_RING * t)
		draw_arc(cell.position, ring, 0.0, TAU, 24,
			Color(hue, (1.0 - t) * 0.7), 2.5, true)

	if cell.is_mined:
		# A dud is inert ground and reads as such: no breath, no rim, no core.
		var emitting := cell.is_generator and world.is_frontier(cell)
		var fill := hue * (INTERIOR_DIM * (breath if emitting else 1.0))
		if not cell.is_generator:
			fill = hue * (INTERIOR_DIM * 0.4)
		fill.a = 1.0
		_draw_hex(cell.position, CELL_RADIUS * scale, fill)
		if emitting:
			# The live edge, unmistakable against the dead interior.
			_draw_hex_outline(cell.position, CELL_RADIUS * scale,
				Color(hue, 0.55 * breath), 2.0)
		if cell.is_generator:
			# The core says this cell is a generator, frontier or interior.
			draw_circle(cell.position, CELL_RADIUS * 0.22 * scale,
				Color(hue.lerp(Color.WHITE, 0.5), 0.85))
		_draw_node(cell, 2)
		return

	if visibility == 0:
		return

	_draw_hex(cell.position, CELL_RADIUS, COLOR_LOCKED_FILL)
	var ring := hue * LOCKED_RING_DIM
	ring.a = 1.0
	_draw_hex_outline(cell.position, CELL_RADIUS, ring, 1.5)
	_draw_node(cell, visibility)

	if cell.progress > 0:
		_draw_progress(cell, hue)
	if show_numbers:
		_draw_price(cell, hue)


## `850 / 3,200`, or just the price on an untouched cell. This is what makes an
## extra point of orb value mean something.
func _draw_price(cell: GraphCell, hue: Color) -> void:
	var text := Format.thousands(cell.cost)
	if cell.progress > 0:
		text = "%s / %s" % [Format.thousands(cell.progress), text]
	_label(text, cell.position + Vector2(0.0, CELL_RADIUS + 14.0),
		hue.lerp(COLOR_TEXT, 0.55), NUMBER_SIZE)


## Rarity is honest at range, identity is not. A big pale bloom eight hops out
## says *there is something huge over there* without saying what, which is what
## makes committing the lance toward it a gamble rather than arithmetic.
func _draw_node(cell: GraphCell, visibility: int) -> void:
	var tier := cell.node_tier()
	if tier == 0:
		return

	var glow := GLOW_RADIUS[tier]
	var tint := Color(0.95, 0.93, 0.85)
	# Three soft rings rather than one hard disc — a bloom, not a dot.
	for step in 3:
		var r := glow * (0.4 + 0.3 * float(step))
		draw_circle(cell.position, r, Color(tint, 0.05 + 0.03 * float(3 - step)))

	if visibility < 2:
		return

	var type := NodeCatalog.get_type(cell.node_id)
	if type == null:
		return
	var label := type.display_name
	if cell.is_keystone():
		label = label.to_upper()
	_label(label, cell.position + Vector2(0.0, -CELL_RADIUS - 6.0), tint)


func _draw_progress(cell: GraphCell, hue: Color) -> void:
	var fraction := clampf(float(cell.progress) / float(maxi(1, cell.cost)), 0.0, 1.0)
	draw_arc(cell.position, CELL_RADIUS - 3.0, -PI * 0.5,
		-PI * 0.5 + TAU * fraction, 20, Color(hue, 0.9), 3.0, true)


func _hex(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in HEX_POINTS:
		var angle := TAU * (float(i) / float(HEX_POINTS)) - PI * 0.5
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _draw_hex(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(_hex(center, radius), color)


func _draw_hex_outline(center: Vector2, radius: float, color: Color,
		width: float) -> void:
	var points := _hex(center, radius)
	points.append(points[0])
	draw_polyline(points, color, width, true)


func _label(text: String, pos: Vector2, color: Color, font_size: int = -1) -> void:
	var at_size := _font_size if font_size < 0 else font_size
	var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, at_size)
	draw_string(_font, pos - Vector2(size.x * 0.5, 0.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, at_size, color)
