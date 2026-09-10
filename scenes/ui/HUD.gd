extends Control

## Four things, and nothing else on screen by default.
##
## Currency, the ram pool, band progress, buff levels. Each buff names what it
## does rather than hiding behind a glyph, tooltips carry the rest, and nothing
## here updates faster than the eye can read.

const MARGIN := 36.0

## The ram is what the player is saving for, so it gets the most room.
const RAM_RADIUS := 92.0
const RAM_WIDTH := 18.0

const BAND_BAR_WIDTH := 440.0
const BAND_BAR_HEIGHT := 16.0

const ROW_HEIGHT := 44.0
const ROW_WIDTH := 500.0

const COLOR_TEXT := Color("dfe5ee")
const COLOR_DIM := Color("7b8290")
const COLOR_PANEL := Color(0.04, 0.05, 0.07, 0.72)
const COLOR_GOOD := Color("6fcf7f")

## One glyph per buff type. A hue on screen is always a band, so these stay
## neutral and are told apart by shape.
const GLYPHS := {
	NodeCatalog.YIELD: "+",
	NodeCatalog.PULSE: "~",
	NodeCatalog.CRIT: "*",
	NodeCatalog.SPLIT: "Y",
}

var main: Node

## Where the end-run button was last drawn, so Main can hit-test it and the two
## can never disagree about where it is.
var end_run_rect: Rect2 = Rect2()

## Cell under the cursor, fed by Main. -1 for none.
var hovered_cell: int = -1

var _font: Font
var _font_size: int
var _tooltip: String = ""
var _tooltip_at: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	_font = label.get_theme_font("font")
	_font_size = label.get_theme_font_size("font_size")
	label.queue_free()


func _process(_delta: float) -> void:
	_update_tooltip(get_viewport().get_mouse_position())
	queue_redraw()


func _world() -> World:
	return main.world if main != null else null


func _draw() -> void:
	var world := _world()
	if world == null:
		return

	_draw_currency(world)
	_draw_ram(world)
	_draw_band(world)
	_draw_buffs(world)

	if not _tooltip.is_empty():
		_draw_tooltip()


func _draw_currency(world: World) -> void:
	_text("◆ %s" % Format.thousands(world.earned),
		Vector2(MARGIN, MARGIN + 32.0), COLOR_TEXT, 40)
	_text("%s banked" % Format.thousands(main.meta.banked),
		Vector2(MARGIN, MARGIN + 66.0), COLOR_DIM, 26)

	# The one way out of a run, and the only door to the shop. It always states
	# what ending the run pays, so the choice is never made blind.
	var stalled := world.frontier().is_empty() and world.live_orb_count() == 0
	end_run_rect = Rect2(MARGIN, MARGIN + 90.0, 360.0, 60.0)
	var hot := end_run_rect.has_point(get_viewport().get_mouse_position())
	draw_rect(end_run_rect,
		Color(0.16, 0.19, 0.24) if hot else Color(0.11, 0.13, 0.16))
	var label := "END RUN  ◆ %s" % Format.thousands(world.earned)
	if stalled:
		# Nothing emits and nothing else can be mined: the run is over whether or
		# not the player has noticed, so the button says so.
		label = "RUN OVER — CLAIM ◆ %s" % Format.thousands(world.earned)
	_text(label, end_run_rect.position + Vector2(24.0, 40.0),
		COLOR_GOOD if stalled else COLOR_TEXT, 28)


## A radial meter. It never "fills" — the pool has no cap — so the arc shows the
## pool against the dearest cell you could currently see paying for, and the
## number underneath is the truth.
func _draw_ram(world: World) -> void:
	var centre := Vector2(size.x - MARGIN - RAM_RADIUS, MARGIN + RAM_RADIUS)
	var damage := world.ram_damage()

	draw_arc(centre, RAM_RADIUS, 0.0, TAU, 48, Color(0.18, 0.2, 0.24),
		RAM_WIDTH, true)

	var color := Color(1.0, 0.97, 0.85)
	if damage <= 0:
		color = Color(0.42, 0.46, 0.54)
	else:
		var pulse := 0.72 + 0.28 * sin(float(Time.get_ticks_msec()) * 0.004)
		draw_circle(centre, RAM_RADIUS + 12.0, Color(color, 0.10 * pulse))

	# A full turn per order of magnitude, so the arc keeps moving all game
	# instead of pinning the moment the pool outgrows one cell.
	var turns := 0.0
	if damage > 0:
		turns = fmod(log(float(damage)) / log(10.0), 1.0)
	draw_arc(centre, RAM_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * turns, 48,
		color, RAM_WIDTH, true)

	_centred("RAM", centre + Vector2(0.0, -8.0), COLOR_DIM, 24)
	_centred(Format.thousands(damage), centre + Vector2(0.0, 28.0), color, 32)


## The run's progress bar and its end condition.
func _draw_band(world: World) -> void:
	var band := world.current_band()
	var progress := world.band_progress(band)
	var mined: int = progress[0]
	var total: int = progress[1]
	var hue := Bands.color_of(band)

	var at := Vector2(MARGIN, size.y - MARGIN - BAND_BAR_HEIGHT)
	draw_rect(Rect2(at, Vector2(BAND_BAR_WIDTH, BAND_BAR_HEIGHT)),
		Color(0.16, 0.18, 0.22))
	var fraction := clampf(float(mined) / float(maxi(1, total)), 0.0, 1.0)
	draw_rect(Rect2(at, Vector2(BAND_BAR_WIDTH * fraction, BAND_BAR_HEIGHT)), hue)
	_text("%s  %d/%d" % [Bands.name_of(band), mined, total],
		at - Vector2(0.0, 16.0), COLOR_DIM, 26)


## Named, levelled and with the effect spelled out. "Icons over words" loses
## here: a row that leaves the player unable to say what Power does is not
## telling them anything.
func _draw_buffs(world: World) -> void:
	var rows := NodeCatalog.ids().size()
	var top := size.y - MARGIN - BAND_BAR_HEIGHT - 52.0 - ROW_HEIGHT * float(rows)

	# The single line that makes every +N on the board mean something.
	var base := World.BASE_ORB_VALUE
	var from_power := world.effective_orb_value() - base
	var orb := "orb %d" % world.effective_orb_value()
	if from_power > 0:
		orb = "%s  =  %d base + %d power" % [orb, base, from_power]
	_text(orb, Vector2(MARGIN, top - 20.0), COLOR_TEXT, 30)

	var y := top + ROW_HEIGHT
	for id in NodeCatalog.ids():
		var key := String(id)
		var type := NodeCatalog.get_type(key)
		var level := world.buffs.level_of(key)
		var color := COLOR_TEXT if level > 0 else Color(0.34, 0.37, 0.43)
		_text("%s %s %d" % [GLYPHS.get(key, "?"), type.display_name, level],
			Vector2(MARGIN, y), color, 28)
		if level > 0:
			_text(_effect(key, level), Vector2(MARGIN + 220.0, y), COLOR_DIM, 26)
		else:
			_text("locked", Vector2(MARGIN + 220.0, y), Color(0.30, 0.33, 0.38), 26)
		y += ROW_HEIGHT


# --- Tooltips -----------------------------------------------------------


## Hovering explains. Effects are read off the same constants the simulation
## uses, so a tuned number can never make this lie.
func _update_tooltip(at: Vector2) -> void:
	_tooltip = ""
	var world := _world()
	if world == null:
		return
	_tooltip_at = at

	var ids := NodeCatalog.ids()
	var rows := ids.size()
	var top := size.y - MARGIN - BAND_BAR_HEIGHT - 52.0 - ROW_HEIGHT * float(rows)

	if at.x >= MARGIN and at.x <= MARGIN + ROW_WIDTH \
			and at.y >= top + ROW_HEIGHT - 28.0 \
			and at.y <= top + ROW_HEIGHT * float(rows + 1):
		var index := int((at.y - (top + ROW_HEIGHT - 28.0)) / ROW_HEIGHT)
		if index >= 0 and index < rows:
			var key := String(ids[index])
			var type := NodeCatalog.get_type(key)
			var level := world.buffs.level_of(key)
			_tooltip = "%s — level %d\n%s\nFound in the ground, and stacks all run." \
				% [type.display_name, level, _effect(key, maxi(level, 1))]
			return

	# The ram meter, top-right.
	var ram_centre := Vector2(size.x - MARGIN - RAM_RADIUS, MARGIN + RAM_RADIUS)
	if at.distance_to(ram_centre) <= RAM_RADIUS + 16.0:
		_tooltip = "Ram — %s damage\nBanks %d%% of every cell you mine.\nRight-click any cell, at any distance.\nUnspent damage is kept." \
			% [Format.thousands(world.ram_damage()), World.RAM_SHARE_PERCENT]
		return

	if hovered_cell >= 0:
		_tooltip = _cell_tooltip(world, hovered_cell)


## What a cell is worth, what it has taken, and what is buried in it if you are
## close enough to read the name.
func _cell_tooltip(world: World, cell_id: int) -> String:
	var cell: GraphCell = world.graph.cells[cell_id]
	var visibility := world.visibility_of(cell_id)
	if visibility == 0 and not cell.is_mined:
		return ""

	var lines := "%s band — %d hops out" % [Bands.name_of(cell.band), cell.hops]
	if cell.is_mined:
		lines += "\nMined for %s" % Format.thousands(cell.cost)
		lines += "\nGenerator — emits on the frontier" if cell.is_generator \
			else "\nDud — inert ground, never emits"
	else:
		lines += "\n%s / %s" % [Format.thousands(cell.progress),
			Format.thousands(cell.cost)]
		if not world.is_mineable(cell):
			lines += "\nBand locked — buy it, or ram in"

	if cell.has_node():
		if visibility >= 2 or cell.is_mined:
			var type := NodeCatalog.get_type(cell.node_id)
			lines += "\n%s +%d" % [type.display_name, cell.node_levels]
		else:
			lines += "\nSomething buried here"
	return lines


func _effect(key: String, level: int) -> String:
	match key:
		NodeCatalog.YIELD:
			return "+%d orb value (now %d)" % [
				level * NodeCatalog.YIELD_PER_LEVEL, _world().effective_orb_value()]
		NodeCatalog.PULSE:
			return "+%d%% emission rate" % (level * NodeCatalog.PULSE_PER_LEVEL)
		NodeCatalog.CRIT:
			return "%.1f%% chance of x%d" % [
				float(level * NodeCatalog.CRIT_PER_LEVEL) / 100.0,
				World.CRIT_MULTIPLIER]
		NodeCatalog.SPLIT:
			return "%.1f%% chance of two orbs" % (
				float(level * NodeCatalog.SPLIT_PER_LEVEL) / 100.0)
	return ""


func _draw_tooltip() -> void:
	var lines := _tooltip.split("\n")
	var width := 0.0
	for line in lines:
		width = maxf(width,
			_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x)
	var box := Rect2(_tooltip_at + Vector2(28.0, -28.0 - 36.0 * lines.size()),
		Vector2(width + 36.0, 36.0 * lines.size() + 24.0))
	draw_rect(box, COLOR_PANEL)
	var y := box.position.y + 36.0
	for line in lines:
		_text(line, Vector2(box.position.x + 18.0, y), COLOR_TEXT, 28)
		y += 36.0


# --- Text ---------------------------------------------------------------


func _text(value: String, at: Vector2, color: Color, font_size: int) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _centred(value: String, at: Vector2, color: Color, font_size: int) -> void:
	var width := _font.get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, at - Vector2(width * 0.5, 0.0), color, font_size)

