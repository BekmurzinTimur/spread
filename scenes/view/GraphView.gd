extends Node2D

## Draws the whole network in one pass: edges, cells, unlock progress, the
## selected block's route, and the aiming preview.
##
## Immediate mode rather than a node per cell — at this scale it is faster,
## and it keeps all the visual rules in one readable place. State is pushed in
## by Main each frame; this layer never touches the simulation.

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

## How much a buried block's glyph is dimmed while its cell is still locked.
const BURIED_DIM := 0.42

var world: World

# Pushed in by Main every frame.
var selected_id: int = -1
var hovered_id: int = -1
var aiming: bool = false
var swapping: bool = false

var _font: Font
var _font_size: int


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_font_size = ThemeDB.fallback_font_size


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
		var cell := world.graph.get_cell(id)
		for n in cell.neighbor_ids:
			if n <= id:
				continue  # draw each undirected edge once
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
		_draw_cell(world.graph.get_cell(id))


func _draw_cell(cell: GraphCell) -> void:
	var pos := cell.position

	if not cell.is_unlocked:
		draw_circle(pos, CELL_RADIUS, COLOR_LOCKED_FILL)
		draw_arc(pos, CELL_RADIUS, 0.0, TAU, 32, COLOR_LOCKED_RING, 2.0)
		_draw_unlock_progress(cell)
		# Contents are always visible, so mining order is a planning decision
		# rather than a gamble — dimmed, because you cannot use it yet.
		if not cell.initial_block_id.is_empty():
			var buried := BlockCatalog.get_def(cell.initial_block_id)
			if buried != null:
				_draw_glyph(buried.id, pos, buried.color.darkened(BURIED_DIM))
		_label(str(cell.unlock_cost), pos + Vector2(0, CELL_RADIUS + 16),
			COLOR_TEXT_DIM, true)
	elif cell.block == null:
		draw_circle(pos, CELL_RADIUS, COLOR_EMPTY_FILL)
		draw_arc(pos, CELL_RADIUS, 0.0, TAU, 32, COLOR_EMPTY_RING, 2.0)
	else:
		var color := cell.block.def.color
		draw_circle(pos, CELL_RADIUS, color.darkened(0.55))
		draw_arc(pos, CELL_RADIUS, 0.0, TAU, 32, color, 3.0)
		_draw_glyph(cell.block.def.id, pos, color)
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


## Drawn for both an installed block and a buried one, so a locked cell reads
## as the same thing it will become.
func _draw_glyph(def_id: String, pos: Vector2, color: Color) -> void:
	match def_id:
		BlockCatalog.GENERATOR:
			# A filled core: this cell makes something from nothing.
			draw_circle(pos, 9.0, color)
		BlockCatalog.PUMP:
			# Two chevrons: things pass through and come out stronger.
			for offset in [-5.0, 3.0]:
				draw_polyline(PackedVector2Array([
					pos + Vector2(-7, -6 + offset),
					pos + Vector2(0, 1 + offset),
					pos + Vector2(7, -6 + offset),
				]), color, 2.5)
		_:
			draw_rect(Rect2(pos - Vector2(7, 7), Vector2(14, 14)), color)


func _label(text: String, pos: Vector2, color: Color, centered: bool = false) -> void:
	var draw_pos := pos
	if centered:
		var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
		draw_pos.x -= size.x * 0.5
	draw_string(_font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, color)
