extends Node2D

## Draws the discovered part of the network in one pass: edges, cells, unlock
## progress, the selected block's route, and the aiming preview.
##
## Immediate mode rather than a node per cell — at this scale it is faster,
## and it keeps all the visual rules in one readable place. State is pushed in
## by Main each frame; this layer never touches the simulation.
##
## Undiscovered cells are not drawn at all, and neither is an edge with an
## undiscovered end — an edge running off into nothing would give away where the
## map continues. Routes need no such trimming: pathing is restricted to
## discovered cells, so a route can never leave the drawn region.

const CELL_RADIUS := 26.0
const EDGE_WIDTH := 3.0
const ROUTE_WIDTH := 5.0

const COLOR_EDGE := Color("2c3242")
const COLOR_LOCKED_FILL := Color("161a24")
const COLOR_LOCKED_RING := Color("3d4459")
const COLOR_EMPTY_FILL := Color("2a3142")
const COLOR_EMPTY_RING := Color("6f7a94")
const COLOR_SELECT := Color("ffffff")
const COLOR_HOVER := Color("8fa4c8")
const COLOR_ROUTE := Color("4fd1c5")
const COLOR_ROUTE_BAD := Color("d95c5c")
const COLOR_SWAP := Color("e0b050")
const COLOR_TEXT := Color("aeb8cc")
const COLOR_TEXT_DIM := Color("6d7590")

## The question mark on a discovered but unmined cell. Neutral on purpose — a
## tier-coloured one would give away the answer it is there to hide.
const COLOR_UNKNOWN := Color("6d7590")

const ICON_UNKNOWN := "res://assets/question.svg"

## Side of the square a glyph is drawn into, centred on the cell.
const ICON_SIZE := 22.0

var world: World

# Pushed in by Main every frame.
var selected_id: int = -1
var hovered_id: int = -1
var aiming: bool = false
var swapping: bool = false

var _font: Font
var _font_size: int

## Loaded once and keyed by resource path, so _draw does no disk work.
var _icons: Dictionary = {}


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_font_size = ThemeDB.fallback_font_size

	_cache_icon(ICON_UNKNOWN)
	for id in BlockCatalog.ids():
		_cache_icon(BlockCatalog.get_def(id).icon_path)


func _cache_icon(path: String) -> void:
	if path.is_empty() or _icons.has(path):
		return
	var texture := load(path)
	if texture is Texture2D:
		_icons[path] = texture


func _draw() -> void:
	if world == null:
		return
	_draw_edges()
	_draw_all_routes()
	_draw_aim_preview()
	_draw_swap_preview()
	_draw_cells()


func _draw_edges() -> void:
	for id in world.graph.cell_ids:
		if not world.graph.is_discovered(id):
			continue
		var cell := world.graph.get_cell(id)
		for n in cell.neighbor_ids:
			if n <= id:
				continue  # draw each undirected edge once
			if not world.graph.is_discovered(n):
				continue  # a stub into the dark shows where the map goes on
			draw_line(cell.position, world.graph.get_cell(n).position, COLOR_EDGE, EDGE_WIDTH)


func _draw_all_routes() -> void:
	for id in world.graph.cell_ids:
		var cell := world.graph.get_cell(id)
		if cell.block == null or not cell.block.has_target():
			continue
		var emphasis := 1.0 if id == selected_id else 0.35
		var arrival := world.projected_arrival(id, cell.block.target_id)
		var color := COLOR_ROUTE if arrival > 0 else COLOR_ROUTE_BAD
		color.a = emphasis
		_draw_path(world.graph.find_path(id, cell.block.target_id), color, ROUTE_WIDTH)


func _draw_aim_preview() -> void:
	if not aiming or selected_id == -1 or hovered_id == -1 or hovered_id == selected_id:
		return
	var path := world.graph.find_path(selected_id, hovered_id)
	if path.size() < 2:
		return
	var arrival := world.projected_arrival(selected_id, hovered_id)
	var color := COLOR_ROUTE if arrival > 0 else COLOR_ROUTE_BAD
	_draw_path(path, color, ROUTE_WIDTH + 2.0)

	# Show what an orb would actually arrive with, which is the whole decision.
	var target := world.graph.get_cell(hovered_id)
	var text := "arrives with %d" % arrival if arrival > 0 else "cannot reach"
	_label(text, target.position + Vector2(0, -CELL_RADIUS - 34), color, true)
	_label("%d hops" % (path.size() - 1),
		target.position + Vector2(0, -CELL_RADIUS - 18), COLOR_TEXT_DIM, true)


## A swap is not a route — it is a straight exchange between two cells at any
## distance — so it is drawn as a direct line rather than along the graph.
func _draw_swap_preview() -> void:
	if not swapping or selected_id == -1 or hovered_id == -1 or hovered_id == selected_id:
		return
	var from := world.graph.get_cell(selected_id)
	var to := world.graph.get_cell(hovered_id)
	if from == null or to == null:
		return

	var allowed := world.can_swap(selected_id, hovered_id)
	var color := COLOR_SWAP if allowed else COLOR_ROUTE_BAD
	draw_line(from.position, to.position, color, ROUTE_WIDTH)

	var text := "swap" if allowed else _swap_refusal(to)
	_label(text, to.position + Vector2(0, -CELL_RADIUS - 18), color, true)


func _swap_refusal(to: GraphCell) -> String:
	if not to.is_unlocked:
		return "not mined yet"
	return "both empty"


func _draw_path(path: PackedInt32Array, color: Color, width: float) -> void:
	if path.size() < 2:
		return
	var points := PackedVector2Array()
	for id in path:
		points.append(world.graph.get_cell(id).position)
	draw_polyline(points, color, width)


func _draw_cells() -> void:
	for id in world.graph.cell_ids:
		if world.graph.is_discovered(id):
			_draw_cell(world.graph.get_cell(id))


func _draw_cell(cell: GraphCell) -> void:
	var pos := cell.position

	if not cell.is_unlocked:
		draw_circle(pos, CELL_RADIUS, COLOR_LOCKED_FILL)
		draw_arc(pos, CELL_RADIUS, 0.0, TAU, 32, COLOR_LOCKED_RING, 2.0)
		_draw_unlock_progress(cell)
		# What the map buried here stays hidden until it is mined, so every
		# unmined cell reads the same: a question mark and a price. The cost is
		# shown because it is the whole basis for deciding to feed it.
		_draw_icon(ICON_UNKNOWN, pos, COLOR_UNKNOWN)
		_label(str(cell.unlock_cost), pos + Vector2(0, CELL_RADIUS + 16),
			COLOR_TEXT_DIM, true)
	elif cell.block == null:
		draw_circle(pos, CELL_RADIUS, COLOR_EMPTY_FILL)
		draw_arc(pos, CELL_RADIUS, 0.0, TAU, 32, COLOR_EMPTY_RING, 2.0)
	else:
		var color := cell.block.def.color
		draw_circle(pos, CELL_RADIUS, color.darkened(0.55))
		draw_arc(pos, CELL_RADIUS, 0.0, TAU, 32, color, 3.0)
		# An anchored block gets a second, tighter ring. Which cells can be
		# rearranged is the central placement decision, so it should be readable
		# off the board rather than discovered by a swap that refuses.
		if not cell.block.def.movable:
			draw_arc(pos, CELL_RADIUS - 5.0, 0.0, TAU, 32, color.darkened(0.25), 1.5)
		_draw_icon(cell.block.def.icon_path, pos, color)
		if cell.block.def.needs_target and not cell.block.has_target():
			_label("idle", pos + Vector2(0, CELL_RADIUS + 16), COLOR_ROUTE_BAD, true)

	if cell.id == selected_id:
		var ring := COLOR_SWAP if swapping else COLOR_SELECT
		draw_arc(pos, CELL_RADIUS + 11.0, 0.0, TAU, 32, ring, 2.5)
	elif cell.id == hovered_id:
		draw_arc(pos, CELL_RADIUS + 11.0, 0.0, TAU, 32, COLOR_HOVER, 1.5)


func _draw_unlock_progress(cell: GraphCell) -> void:
	if cell.unlock_cost <= 0 or cell.unlock_progress <= 0:
		return
	var fraction := float(cell.unlock_progress) / float(cell.unlock_cost)
	draw_arc(
		cell.position, CELL_RADIUS - 4.0,
		-PI / 2.0, -PI / 2.0 + TAU * fraction,
		32, Tiers.color_of(Tiers.RED), 4.0
	)


## The icons are white artwork on transparency, so modulating by `color` paints
## them outright — which is how a block ends up in its tier's colour.
func _draw_icon(path: String, pos: Vector2, color: Color) -> void:
	var texture: Texture2D = _icons.get(path)
	if texture == null:
		# A block type whose icon is missing still has to read as something.
		draw_rect(Rect2(pos - Vector2(7, 7), Vector2(14, 14)), color)
		return
	var side := Vector2(ICON_SIZE, ICON_SIZE)
	draw_texture_rect(texture, Rect2(pos - side * 0.5, side), false, color)


func _label(text: String, pos: Vector2, color: Color, centered: bool = false) -> void:
	var draw_pos := pos
	if centered:
		var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
		draw_pos.x -= size.x * 0.5
	draw_string(_font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, color)
