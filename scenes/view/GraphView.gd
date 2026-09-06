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

## Unlock progress, just inside the cell's rim.
const UNLOCK_ARC_RADIUS := CELL_RADIUS - 4.0
const UNLOCK_ARC_WIDTH := 4.0

## A block standing in a sphere's field gets a thin outer ring, so a board says
## at a glance which blocks are running on better numbers than their type's. Sits
## outside the cell but inside the selection ring at +11, and clear of the
## anchored ring at -5.
const BOOST_RING_RADIUS := CELL_RADIUS + 4.0

## A producer's charge, one band further in. It cannot share the unlock radius:
## every generator is anchored, and an anchored block already draws a ring at
## CELL_RADIUS - 5 — the two would smear into each other. This sits inside that
## ring and outside the glyph, so a generator reads outward as charge, anchored,
## type.
const COOLDOWN_ARC_RADIUS := CELL_RADIUS - 9.0
const COOLDOWN_ARC_WIDTH := 3.0

## How long a block's activity pulse takes to fade, in ticks — so it is measured
## in simulated time like everything else on the board. At 10 Hz this is 0.5s at
## normal speed, and correctly compresses when the player speeds the game up: a
## generator firing eight times a second should look like it.
const PULSE_TICKS := 5.0

## How much bigger the glyph gets at the peak of a pulse. Small on purpose — this
## fires constantly on a busy route, and a big jump would turn a working network
## into a twitching one.
const PULSE_SCALE := 0.35

## And how much brighter. Carries most of the signal at low zoom, where a few
## pixels of scale are invisible but a flash still reads.
const PULSE_LIFT := 0.5

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

## A challenge cell is a triangle rather than a circle, mined or not, so it reads
## as a landmark from across the board and at any zoom — shape survives being
## small in a way that colour and glyph do not.
##
## Circumradius, so the triangle is drawn slightly larger than a cell: an
## inscribed triangle covers well under half a circle's area and would read as a
## *smaller* cell rather than a special one. Still inside `Main._cell_at`'s
## `CELL_RADIUS * 1.35` hit test, so clicking one needs no change there.
const CHALLENGE_RADIUS := CELL_RADIUS * 1.2

## Unlock progress on a challenge cell, drawn *outside* the silhouette. The
## regular arc at `CELL_RADIUS - 4` would saw straight through a triangle's
## edges, because a triangle's edge midpoints sit far inside its circumradius.
const CHALLENGE_ARC_RADIUS := CELL_RADIUS + 8.0

## The rim of an unmined challenge. Warm, and deliberately not any block's colour
## — it says "something hard is buried here", not which of the three.
const COLOR_CHALLENGE_RING := Color("e0b050")

const ICON_UNKNOWN := "res://assets/question.svg"

## Side of the square a glyph is drawn into, centred on the cell.
const ICON_SIZE := 22.0

var world: World

# Pushed in by Main every frame.
var selected_id: int = -1
var hovered_id: int = -1
var aiming: bool = false
var swapping: bool = false

## Fraction of the current tick already elapsed. Smooths generator cooldowns,
## which advance every tick — never unlock progress, which moves on deliveries
## and has no in-between state to reconstruct.
var render_alpha: float = 0.0

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
	_draw_field()
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


## Every sphere's reach, all the time: a circle enclosing the field it radiates.
##
## Always drawn, not only for the selected sphere, because where the fields lie is
## the standing question a player is answering — which pump is covered, which
## generator is not, where a gap is worth moving one into. Hiding that until you
## click makes you click every sphere in turn to see the board you are already
## looking at. The one in focus is simply brighter, the same way an aimed route is
## drawn at full strength and the rest at a fraction.
##
## Radius is derived from the field itself — the distance to the farthest cell
## actually in range — rather than from a constant, so it encloses exactly what
## the simulation buffs and cannot drift from it as a sphere moves to a sparser or
## denser part of the board.
##
## Cell-by-cell highlights come out only for the sphere in focus. Radius is
## measured in *hops* and the board is a graph, so a cell drawn inside the circle
## may be several hops away around a wall and get nothing; the highlights are what
## resolve that ambiguity, and they are worth the clutter only for the sphere
## being considered.
##
## Drawn under the cells so it reads as ground a sphere covers, not as a mark on
## each block.
func _draw_field() -> void:
	for id in world.graph.cell_ids:
		if world.graph.is_discovered(id):
			_draw_field_of(id)


func _draw_field_of(origin_id: int) -> void:
	var cells: PackedInt32Array = world.field_cells(origin_id)
	if cells.is_empty():
		return

	var origin := world.graph.get_cell(origin_id)
	var color: Color = origin.block.def.color
	var focused := origin_id == selected_id or origin_id == hovered_id
	var emphasis := 1.0 if focused else 0.4

	# Encloses the farthest cell in range whether or not it is discovered yet: the
	# field is a fact about the board, and a circle that grew as the fog lifted
	# would suggest the sphere's reach had changed when nothing had.
	var reach := 0.0
	for id in cells:
		reach = maxf(reach, origin.position.distance_to(world.graph.get_cell(id).position))
	reach += CELL_RADIUS + 8.0

	draw_circle(origin.position, reach, Color(color, 0.09 * emphasis))
	draw_arc(origin.position, reach, 0.0, TAU, 64, Color(color, 0.5 * emphasis), 2.0)

	if not focused:
		return
	for id in cells:
		if id == origin_id or not world.graph.is_discovered(id):
			continue
		var pos := world.graph.get_cell(id).position
		draw_circle(pos, CELL_RADIUS + 6.0, Color(color, 0.12))
		draw_arc(pos, CELL_RADIUS + 6.0, 0.0, TAU, 32, Color(color, 0.35), 1.5)


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
	# Asked once and reused: the silhouette is the same before and after mining,
	# because a challenge is a permanent landmark rather than a pre-dig hint.
	var challenge := cell.is_challenge()

	if not cell.is_unlocked:
		if challenge:
			# A triangle and a warm rim say a challenge is buried here. The glyph
			# stays the same question mark every other unmined cell gets, because
			# *which* challenge it is stays hidden — knowing something hard is
			# coming is the point, knowing what it pays out would remove the
			# reason to dig it.
			_draw_triangle(pos, COLOR_LOCKED_FILL, COLOR_CHALLENGE_RING, 2.5)
		else:
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
		# Every block that acts beats once, whatever it does — an orb emitted, an
		# orb restored. So a live route reads as a chain of things firing in
		# sequence, and a pump nothing is routed through visibly sits out.
		# A challenge never acts, so its pulse is always zero — the expressions
		# below collapse to their resting values rather than needing a branch.
		var pulse := _pulse_strength(cell.block)
		if challenge:
			_draw_triangle(pos, color.darkened(0.55), color.lightened(0.15), 3.0)
		else:
			draw_circle(pos, CELL_RADIUS, color.darkened(0.55 - 0.25 * pulse))
			draw_arc(pos, CELL_RADIUS, 0.0, TAU, 32,
				color.lightened(PULSE_LIFT * pulse), 3.0 + 1.5 * pulse)
		# An anchored block gets a second, tighter ring. Which cells can be
		# rearranged is the central placement decision, so it should be readable
		# off the board rather than discovered by a swap that refuses.
		#
		# Skipped for a challenge: a circular ring inside a triangle reads as a
		# stray mark, and the triangle already says this one is not going
		# anywhere.
		if not cell.block.def.movable and not challenge:
			draw_arc(pos, CELL_RADIUS - 5.0, 0.0, TAU, 32, color.darkened(0.25), 1.5)
		# Standing in a sphere's field. Drawn in the sphere's colour rather than
		# the block's, so the ring points at what is causing it.
		if world.is_boosted(cell.id):
			draw_arc(pos, BOOST_RING_RADIUS, 0.0, TAU, 32,
				Color(BlockCatalog.get_def(BlockCatalog.SPHERE).color, 0.8), 1.5)
		# Charge toward the next orb. Fills, then empties as it fires — so a board
		# at a glance says which producers are about to do something. A challenge
		# produces nothing, so `_cooldown_fraction` returns 0 and this draws
		# nothing; it is left unbranched because that is already the right answer.
		_draw_progress_arc(pos, COOLDOWN_ARC_RADIUS, _cooldown_fraction(cell),
			color, COOLDOWN_ARC_WIDTH)
		_draw_icon(cell.block.def.icon_path, pos, color.lightened(PULSE_LIFT * pulse),
			1.0 + PULSE_SCALE * pulse)
		if cell.block.def.needs_target and not cell.block.has_target():
			_label("idle", pos + Vector2(0, CELL_RADIUS + 16), COLOR_ROUTE_BAD, true)

	if cell.id == selected_id:
		var ring := COLOR_SWAP if swapping else COLOR_SELECT
		draw_arc(pos, CELL_RADIUS + 11.0, 0.0, TAU, 32, ring, 2.5)
	elif cell.id == hovered_id:
		draw_arc(pos, CELL_RADIUS + 11.0, 0.0, TAU, 32, COLOR_HOVER, 1.5)


## The three corners of a challenge cell, point-up, at `radius` from centre.
##
## Static and pure so the geometry can be checked headlessly — the same trick
## `OrbLayer`'s weave maths is tested with. Point-up because the board's only
## other strong direction is the row offset of the honeycomb, and a triangle
## sharing that tilt would read as part of the lattice rather than against it.
static func triangle_points(pos: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 3:
		var angle := -PI / 2.0 + float(i) * TAU / 3.0
		points.append(pos + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Fill plus rim, the polygon counterpart of the `draw_circle` + `draw_arc` pair
## every other cell uses. Godot has no polygon equivalent of `draw_arc`, so the
## rim is a closed polyline — hence the first point repeated at the end.
func _draw_triangle(pos: Vector2, fill: Color, rim: Color, width: float) -> void:
	var points := triangle_points(pos, CHALLENGE_RADIUS)
	draw_colored_polygon(points, fill)
	var outline := points
	outline.append(points[0])
	draw_polyline(outline, rim, width)


func _draw_unlock_progress(cell: GraphCell) -> void:
	if cell.unlock_cost <= 0 or cell.unlock_progress <= 0:
		return
	var fraction := float(cell.unlock_progress) / float(cell.unlock_cost)
	# Outside the silhouette on a challenge cell. A triangle's edge midpoints sit
	# at half its circumradius, so the usual arc just inside the rim would cross
	# the shape rather than trace it.
	if cell.is_challenge():
		_draw_progress_arc(cell.position, CHALLENGE_ARC_RADIUS, fraction,
			Tiers.color_of(Tiers.RED), UNLOCK_ARC_WIDTH)
		return
	_draw_progress_arc(cell.position, UNLOCK_ARC_RADIUS, fraction,
		Tiers.color_of(Tiers.RED), UNLOCK_ARC_WIDTH)


## How charged a producer is, smoothed within the tick.
##
## `timer` counts whole ticks and resets to 0 on the tick that emits, so the raw
## ratio only ever reads 0/20 .. 19/20: it never shows full and it snaps back
## from 95%. Adding `render_alpha` both smooths the 10 Hz stepping and closes
## that gap — the last tick before an emission runs (19 + alpha) / 20 up to
## exactly 1.0, and the firing tick puts the timer back to 0 with alpha back to
## 0. So the wrap is seamless by construction, and no frame runs backwards.
##
## An idle generator does not advance its timer at all — the behaviour returns
## before touching it — so it gets no arc. Given alpha, a frozen timer would
## shimmer between two values forever on a cell whose whole message is that it is
## doing nothing.
##
## Takes the cell rather than the block because the interval is no longer a
## property of the block alone: a sphere in range shortens it, and the arc has to
## fill at the rate the generator actually fires or it will visibly overshoot and
## snap. `effective_interval` is floored above zero, so the divide is safe.
func _cooldown_fraction(cell: GraphCell) -> float:
	var block := cell.block
	var interval: int = world.effective_interval(cell)
	if interval <= 0:
		return 0.0
	if block.def.needs_target and not block.has_target():
		return 0.0
	return clampf((float(block.timer) + render_alpha) / float(interval), 0.0, 1.0)


## How far through its activity pulse a block is: 1.0 the instant it acts,
## falling to 0.0 over PULSE_TICKS. 0.0 for a block that has never acted.
##
## Any block that does its thing gets one — an orb emitted, an orb restored — so
## a working network beats visibly and a stranded pump sits still. The behaviour
## decides what counts as acting; this only reads the mark it left.
##
## `render_alpha` is added for the same reason the cooldown arc adds it: the tick
## count alone would step the fade at 10 Hz. A block that acted on the current
## tick reads exactly 1.0, because tick_count and last_active_tick are equal and
## alpha is the fraction elapsed since.
func _pulse_strength(block: Block) -> float:
	var age: int = block.ticks_since_active(world.tick_count)
	if age < 0:
		return 0.0
	var t := (float(age) + render_alpha) / PULSE_TICKS
	if t >= 1.0:
		return 0.0
	# Eased so the pulse snaps in and eases out, rather than fading linearly —
	# a linear falloff reads as a slow throb instead of a beat.
	return (1.0 - t) * (1.0 - t)


## A clockwise sweep from twelve o'clock. Shared so the unlock bar and a
## generator's charge read as the same kind of statement about the same kind of
## thing — one is filling toward a cell opening, the other toward an orb.
func _draw_progress_arc(pos: Vector2, radius: float, fraction: float,
		color: Color, width: float) -> void:
	if fraction <= 0.0:
		return
	draw_arc(
		pos, radius,
		-PI / 2.0, -PI / 2.0 + TAU * minf(fraction, 1.0),
		32, color, width
	)


## The icons are white artwork on transparency, so modulating by `color` paints
## them outright — which is how a block ends up in its tier's colour.
func _draw_icon(path: String, pos: Vector2, color: Color, size_scale: float = 1.0) -> void:
	var texture: Texture2D = _icons.get(path)
	if texture == null:
		# A block type whose icon is missing still has to read as something.
		var half := 7.0 * size_scale
		draw_rect(Rect2(pos - Vector2(half, half), Vector2(half, half) * 2.0), color)
		return
	var side := Vector2(ICON_SIZE, ICON_SIZE) * size_scale
	draw_texture_rect(texture, Rect2(pos - side * 0.5, side), false, color)


func _label(text: String, pos: Vector2, color: Color, centered: bool = false) -> void:
	var draw_pos := pos
	if centered:
		var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
		draw_pos.x -= size.x * 0.5
	draw_string(_font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, color)
