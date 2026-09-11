extends Node2D

## Draws the board.
##
## Two independent colour channels, and keeping them apart is the whole readout:
## **hue is depth** (which region a cell sits in) and **glow is rarity** (how big a
## node it holds). One look answers both without them fighting.
##
## Two layers. Still ground is cached in chunks that redraw only when a cell's
## look changes. The live edge, progress, pops and the ram are an overlay drawn
## every frame in `_draw()`.

const CELL_RADIUS := 44.0
const HEX_POINTS := 6

## World units per cached chunk, about 25 cells.
const CHUNK_SIZE := 640.0

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

## Below this zoom per-cell numbers and icons are skipped — a zoomed-out board is
## otherwise a wall of unreadable marks.
const TEXT_MIN_ZOOM := 0.28
const NUMBER_SIZE := 24

## Interior cells sit this far down from their region's hue; frontier cells ride
## the breath above it.
const INTERIOR_DIM := 0.30
const LOCKED_RING_DIM := 0.42

## Icon sizes, as a share of the cell radius.
const NODE_ICON := 1.0
const KEYSTONE_ICON := 1.25
const GENERATOR_ICON := 0.8
const LOCK_ICON := 0.6

## Node glow radius per tier: none, common, rare, keystone.
const GLOW_RADIUS: PackedFloat32Array = [0.0, 28.0, 48.0, 76.0]

## The lance shot: board dims, beam streaks out, impact blooms.
const BEAM_TIME := 0.7
const BEAM_WIDTH := 10.0
const DIM_ALPHA := 0.45

## One byte per cell: everything the cached layer depends on.
const LOOK_VISIBILITY := 3
const LOOK_MINED := 4
const LOOK_GENERATOR := 8
const LOOK_FRONTIER := 16

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
var _region_colors: Array[Color] = []

var _edge_root: Node2D
var _cell_root: Node2D
var _edge_chunks: Array[Node2D] = []
var _cell_chunks: Array[Node2D] = []
var _chunk_cells: Array[PackedInt32Array] = []
var _chunk_of: PackedInt32Array = PackedInt32Array()

## The looks the cached chunks were last drawn from.
var _look: PackedByteArray = PackedByteArray()

## Locked cells with progress, whose label the overlay owns. id -> true.
var _progressing: Dictionary = {}

var _bound_world: World
var _meta_version: int = -1
var _unlock_version: int = -1
var _show_detail: bool = true


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var label := Label.new()
	_font = label.get_theme_font("font")
	_font_size = label.get_theme_font_size("font_size") * 2
	label.queue_free()
	for region in Regions.COUNT:
		_region_colors.append(Regions.color_of(region))
	# Behind the overlay; edges under every hex.
	_edge_root = _make_root()
	_cell_root = _make_root()


func pop(cell_id: int) -> void:
	_pops[cell_id] = 0.0


func fire_beam(from: Vector2, to: Vector2) -> void:
	_beam_from = from
	_beam_to = to
	_beam_age = 0.0


## A delivery landed. The first one on a cell moves its label to the overlay.
func touch(cell_id: int) -> void:
	if world == null or world != _bound_world or _progressing.has(cell_id):
		return
	var cell := world.graph.get_cell(cell_id)
	if cell == null or cell.is_mined or cell.progress <= 0:
		return
	_progressing[cell_id] = true
	_cell_chunks[_chunk_of[cell_id]].queue_redraw()


func advance(delta: float) -> void:
	_sync()
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


# --- Cached layer -------------------------------------------------------


func _make_root() -> Node2D:
	var root := Node2D.new()
	root.show_behind_parent = true
	add_child(root)
	return root


## Redraw whatever chunks went stale. Everything on a new world, a purchase or a
## zoom across the text threshold; only changed cells after a mine.
func _sync() -> void:
	if world == null:
		return
	var meta_version := world.meta().version if world.meta() != null else 0
	var show_detail := camera == null or camera.zoom.x >= TEXT_MIN_ZOOM
	if world != _bound_world:
		_bind_chunks()
	elif meta_version == _meta_version and show_detail == _show_detail:
		if world.graph.unlock_version != _unlock_version:
			_redraw_changed()
		return

	_meta_version = meta_version
	_show_detail = show_detail
	_unlock_version = world.graph.unlock_version
	_look = _compute_looks()
	_progressing.clear()
	for chunk in _edge_chunks:
		chunk.queue_redraw()
	for chunk in _cell_chunks:
		chunk.queue_redraw()


func _bind_chunks() -> void:
	_bound_world = world
	for chunk in _edge_chunks + _cell_chunks:
		chunk.free()
	_edge_chunks.clear()
	_cell_chunks.clear()
	_chunk_cells.clear()

	var graph := world.graph
	_chunk_of = PackedInt32Array()
	_chunk_of.resize(graph.cell_ids[graph.cell_ids.size() - 1] + 1)

	var index_of: Dictionary = {}  # Vector2i -> chunk index
	var buckets: Array[PackedInt32Array] = []
	for id in graph.cell_ids:
		var key := Vector2i((graph.cells[id].position / CHUNK_SIZE).floor())
		if not index_of.has(key):
			index_of[key] = buckets.size()
			buckets.append(PackedInt32Array())
		var index: int = index_of[key]
		buckets[index].append(id)
		_chunk_of[id] = index

	for index in buckets.size():
		_chunk_cells.append(buckets[index])
		_edge_chunks.append(_make_chunk(_edge_root, _draw_edge_chunk.bind(index)))
		_cell_chunks.append(_make_chunk(_cell_root, _draw_cell_chunk.bind(index)))


func _make_chunk(root: Node2D, painter: Callable) -> Node2D:
	var chunk := Node2D.new()
	chunk.draw.connect(painter)
	root.add_child(chunk)
	return chunk


func _compute_looks() -> PackedByteArray:
	var graph := world.graph
	var distance := graph.distance_from_mined()
	var identity := world.vision_identity()
	var rarity := world.vision_rarity()

	var looks := PackedByteArray()
	looks.resize(_chunk_of.size())
	looks.fill(0)
	for id in world.frontier():
		looks[id] = LOOK_FRONTIER

	for id in graph.cell_ids:
		var cell: GraphCell = graph.cells[id]
		var look := looks[id]
		if cell.is_mined:
			look |= LOOK_MINED
			if cell.is_generator:
				look |= LOOK_GENERATOR
		var d := distance[id]
		if d >= 0 and d <= identity:
			look |= 2
		elif d >= 0 and d <= rarity:
			look |= 1
		looks[id] = look
	return looks


## An edge lives in its low-id end's chunk, so a changed cell dirties the edge
## chunks of its neighbours too.
func _redraw_changed() -> void:
	_unlock_version = world.graph.unlock_version
	var looks := _compute_looks()
	var cell_dirty: Dictionary = {}
	var edge_dirty: Dictionary = {}
	for id in world.graph.cell_ids:
		if looks[id] == _look[id]:
			continue
		cell_dirty[_chunk_of[id]] = true
		edge_dirty[_chunk_of[id]] = true
		for n in world.graph.cells[id].neighbor_ids:
			edge_dirty[_chunk_of[n]] = true
	_look = looks
	for index in cell_dirty:
		_cell_chunks[index].queue_redraw()
	for index in edge_dirty:
		_edge_chunks[index].queue_redraw()


func _draw_edge_chunk(index: int) -> void:
	var canvas := _edge_chunks[index]
	for id in _chunk_cells[index]:
		if (_look[id] & LOOK_VISIBILITY) == 0:
			continue
		var cell: GraphCell = world.graph.cells[id]
		for n in cell.neighbor_ids:
			if n < id or (_look[n] & LOOK_VISIBILITY) == 0:
				continue
			canvas.draw_line(cell.position, world.graph.cells[n].position,
				COLOR_EDGE, EDGE_WIDTH)


func _draw_cell_chunk(index: int) -> void:
	var canvas := _cell_chunks[index]
	for id in _chunk_cells[index]:
		var look := _look[id]
		var cell: GraphCell = world.graph.cells[id]
		var hue := _region_colors[cell.region]

		if look & LOOK_MINED:
			if look & LOOK_FRONTIER:
				continue  # the overlay breathes it
			_draw_mined(canvas, cell, hue, false, 1.0, 1.0)
			_draw_node(canvas, cell, 2)
			continue

		var visibility := look & LOOK_VISIBILITY
		if visibility == 0:
			continue
		_draw_hex(canvas, cell.position, CELL_RADIUS, COLOR_LOCKED_FILL)
		var ring := hue * LOCKED_RING_DIM
		ring.a = 1.0
		_draw_hex_outline(canvas, cell.position, CELL_RADIUS, ring, 1.5)
		_draw_node(canvas, cell, visibility)
		if _show_detail and not world.is_mineable(cell) \
				and not (visibility >= 2 and cell.node_tier() > 0):
			Icons.draw(canvas, Icons.LOCK, cell.position, CELL_RADIUS * LOCK_ICON, ring)

		if cell.progress > 0:
			_progressing[id] = true
		elif _show_detail:
			_draw_price(canvas, cell, hue)


# --- Overlay ------------------------------------------------------------


func _draw() -> void:
	if world == null or _look.is_empty():
		return

	var view := Rect2()
	if camera != null:
		view = camera.visible_world_rect().grow(CELL_RADIUS * 4.0)
	var breath := 1.0 + sin(clock * BREATHE_SPEED) * BREATHE_DEPTH

	for id in _pops:
		var cell: GraphCell = world.graph.cells[id]
		if not _on_screen(view, cell.position):
			continue
		var hue := _region_colors[cell.region]
		var t: float = _pops[id] / POP_TIME
		draw_arc(cell.position, CELL_RADIUS * (1.0 + POP_RING * t), 0.0, TAU, 24,
			Color(hue, (1.0 - t) * 0.7), 2.5)
		if cell.is_mined and not (_look[id] & LOOK_FRONTIER):
			_draw_mined(self, cell, hue, false, breath, _pop_scale(id))

	for id in world.frontier():
		var cell: GraphCell = world.graph.cells[id]
		if not _on_screen(view, cell.position):
			continue
		var hue := _region_colors[cell.region]
		_draw_mined(self, cell, hue, true, breath, _pop_scale(id))
		_draw_node(self, cell, 2)

	var done: Array = []
	for id in _progressing:
		var cell: GraphCell = world.graph.cells[id]
		if cell.is_mined:
			done.append(id)
			continue
		if (_look[id] & LOOK_VISIBILITY) == 0 or not _on_screen(view, cell.position):
			continue
		var hue := _region_colors[cell.region]
		_draw_progress(cell, hue)
		if _show_detail:
			_draw_price(self, cell, hue)
	for id in done:
		_progressing.erase(id)

	_draw_ram(view, breath)


func _on_screen(view: Rect2, at: Vector2) -> bool:
	return camera == null or view.has_point(at)


func _pop_scale(cell_id: int) -> float:
	if not _pops.has(cell_id):
		return 1.0
	var t: float = _pops[cell_id] / POP_TIME
	return 1.0 + POP_SCALE * (1.0 - t) * (1.0 - t)


## The one thing the player aims. Any unmined cell is a target — the pool is the
## only limit — so this highlights what is under the cursor rather than painting
## a range.
func _draw_ram(view: Rect2, breath: float) -> void:
	if _beam_age >= 0.0:
		var t := _beam_age / BEAM_TIME
		# Board dims for a beat, then the beam and the bloom.
		draw_rect(view, Color(0.0, 0.0, 0.0, DIM_ALPHA * (1.0 - t)))
		var head := _beam_from.lerp(_beam_to, minf(1.0, t * 2.5))
		draw_line(_beam_from, head, Color(1.0, 0.97, 0.85, 1.0 - t * 0.6), BEAM_WIDTH)
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

	_draw_hex_outline(self, target.position, CELL_RADIUS + 4.0,
		Color(color, 0.55 + 0.35 * breath), 2.5)
	draw_circle(target.position, CELL_RADIUS * 1.8, Color(color, 0.10))

	# What the shot would actually do, so a partial ram reads as a down payment
	# rather than a miss.
	var label := Format.number(damage)
	if not kills:
		label = "%s  (%s left)" % [label,
			Format.number(target.remaining() - damage)]
	var at := target.position + Vector2(0.0, CELL_RADIUS + 30.0)
	at.x -= Icons.label_width(_font, label, _font_size) * 0.5
	Icons.draw_label(self, _font, Icons.RAM, label, at, color, _font_size)


# --- Shared drawing -----------------------------------------------------


## Mined ground. A dud is inert and reads as such: no breath, no rim, no core.
func _draw_mined(canvas: CanvasItem, cell: GraphCell, hue: Color, emitting: bool,
		breath: float, scale: float) -> void:
	var fill := hue * (INTERIOR_DIM * (breath if emitting else 1.0))
	if not cell.is_generator:
		fill = hue * (INTERIOR_DIM * 0.4)
	fill.a = 1.0
	_draw_hex(canvas, cell.position, CELL_RADIUS * scale, fill)
	if emitting:
		# The live edge, unmistakable against the dead interior.
		_draw_hex_outline(canvas, cell.position, CELL_RADIUS * scale,
			Color(hue, 0.55 * breath), 2.0)
	if not cell.is_generator:
		return
	var core := Color(hue.lerp(Color.WHITE, 0.5), 0.85)
	if not _show_detail:
		canvas.draw_circle(cell.position, CELL_RADIUS * 0.22 * scale, core)
	elif not cell.has_node():
		# A node's icon takes the centre instead.
		Icons.draw(canvas, Icons.GENERATOR, cell.position,
			CELL_RADIUS * GENERATOR_ICON * scale, core)


## `850 / 3,200`, or just the price on an untouched cell. This is what makes an
## extra point of orb value mean something.
func _draw_price(canvas: CanvasItem, cell: GraphCell, hue: Color) -> void:
	var text := Format.number(cell.cost)
	if cell.progress > 0:
		text = "%s / %s" % [Format.number(cell.progress), text]
	_label(canvas, text, cell.position + Vector2(0.0, CELL_RADIUS + 14.0),
		hue.lerp(COLOR_TEXT, 0.55), NUMBER_SIZE)


## Rarity is honest at range, identity is not. A big pale bloom eight hops out
## says *there is something huge over there* without saying what, which is what
## makes committing the lance toward it a gamble rather than arithmetic.
func _draw_node(canvas: CanvasItem, cell: GraphCell, visibility: int) -> void:
	var tier := cell.node_tier()
	if tier == 0:
		return

	var glow := GLOW_RADIUS[tier]
	var tint := Color(0.95, 0.93, 0.85)
	# Three soft rings rather than one hard disc — a bloom, not a dot.
	for step in 3:
		var r := glow * (0.4 + 0.3 * float(step))
		canvas.draw_circle(cell.position, r, Color(tint, 0.05 + 0.03 * float(3 - step)))

	if visibility < 2:
		return

	var type := NodeCatalog.get_type(cell.node_id)
	if type == null:
		return
	if _show_detail:
		var icon := KEYSTONE_ICON if cell.is_keystone() else NODE_ICON
		Icons.draw(canvas, Icons.buff(cell.node_id), cell.position, CELL_RADIUS * icon, tint)
	var label := type.display_name
	if cell.is_keystone():
		label = label.to_upper()
	_label(canvas, label, cell.position + Vector2(0.0, -CELL_RADIUS - 6.0), tint)


func _draw_progress(cell: GraphCell, hue: Color) -> void:
	var fraction := clampf(float(cell.progress) / float(maxi(1, cell.cost)), 0.0, 1.0)
	draw_arc(cell.position, CELL_RADIUS - 3.0, -PI * 0.5,
		-PI * 0.5 + TAU * fraction, 20, Color(hue, 0.9), 3.0)


func _hex(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in HEX_POINTS:
		var angle := TAU * (float(i) / float(HEX_POINTS)) - PI * 0.5
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _draw_hex(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	canvas.draw_colored_polygon(_hex(center, radius), color)


func _draw_hex_outline(canvas: CanvasItem, center: Vector2, radius: float,
		color: Color, width: float) -> void:
	var points := _hex(center, radius)
	points.append(points[0])
	canvas.draw_polyline(points, color, width)


func _label(canvas: CanvasItem, text: String, pos: Vector2, color: Color,
		font_size: int = -1) -> void:
	var at_size := _font_size if font_size < 0 else font_size
	var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, at_size)
	canvas.draw_string(_font, pos - Vector2(size.x * 0.5, 0.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, at_size, color)
