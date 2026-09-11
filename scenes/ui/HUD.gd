extends Control

## Four things, and nothing else on screen by default.
##
## Currency, the ram pool, region progress, buff levels. Each buff is an icon and
## a name that says what it does, tooltips carry the rest, and nothing here
## updates faster than the eye can read.

const MARGIN := 36.0

## The ram is what the player is saving for, so it gets the most room.
const RAM_RADIUS := 92.0
const RAM_WIDTH := 18.0

const REGION_BAR_WIDTH := 440.0
const REGION_BAR_HEIGHT := 16.0

const ROW_HEIGHT := 44.0
const ROW_WIDTH := 580.0
const ROW_FONT := 28

## Where a buff row's effect text starts, past the icon and name.
const EFFECT_X := 262.0

const COLOR_TEXT := Color("dfe5ee")
const COLOR_DIM := Color("7b8290")
const COLOR_PANEL := Color(0.04, 0.05, 0.07, 0.72)
const COLOR_GOOD := Color("6fcf7f")

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
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	_draw_region(world)
	_draw_buffs(world)

	if not _tooltip.is_empty():
		_draw_tooltip()


func _draw_currency(world: World) -> void:
	_icon_text(Icons.CURRENCY, Format.number(world.earned),
		Vector2(MARGIN, MARGIN + 32.0), COLOR_TEXT, 40)
	_icon_text(Icons.CURRENCY, "%s banked" % Format.number(main.meta.banked),
		Vector2(MARGIN, MARGIN + 70.0), COLOR_DIM, 26)

	# The one way out of a run, and the only door to the shop. It always states
	# what ending the run pays, so the choice is never made blind.
	var stalled := world.frontier().is_empty() and world.live_orb_count() == 0
	# Nothing emits and nothing else can be mined: the run is over whether or
	# not the player has noticed, so the button says so.
	var label := "RUN OVER — CLAIM" if stalled else "END RUN"
	var amount := Format.number(world.earned)
	var pad := 24.0
	var gap := 20.0
	var width := pad * 2.0 + gap + Icons.label_width(_font, label, 28) \
		+ Icons.label_width(_font, amount, 28)
	end_run_rect = Rect2(MARGIN, MARGIN + 96.0, maxf(360.0, width), 60.0)
	var hot := end_run_rect.has_point(get_viewport().get_mouse_position())
	draw_rect(end_run_rect,
		Color(0.16, 0.19, 0.24) if hot else Color(0.11, 0.13, 0.16))
	var color := COLOR_GOOD if stalled else COLOR_TEXT
	var x := _icon_text(Icons.END_RUN, label,
		end_run_rect.position + Vector2(pad, 40.0), color, 28)
	_icon_text(Icons.CURRENCY, amount,
		Vector2(x + gap, end_run_rect.position.y + 40.0), color, 28)


## A radial meter. It never "fills" — the pool has no cap — so the arc shows the
## pool against the dearest cell you could currently see paying for, and the
## number underneath is the truth.
func _draw_ram(world: World) -> void:
	var centre := Vector2(size.x - MARGIN - RAM_RADIUS, MARGIN + RAM_RADIUS)
	var damage := world.ram_damage()

	draw_arc(centre, RAM_RADIUS, 0.0, TAU, 48, Color(0.18, 0.2, 0.24),
		RAM_WIDTH)

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
		color, RAM_WIDTH)

	Icons.draw(self, Icons.RAM, centre + Vector2(0.0, -20.0), 44.0, color)
	_centred(Format.number(damage), centre + Vector2(0.0, 38.0), color, 32)


## The run's progress bar and its end condition.
func _draw_region(world: World) -> void:
	var region := world.current_region()
	var progress := world.region_progress(region)
	var mined: int = progress[0]
	var total: int = progress[1]
	var hue := Regions.color_of(region)

	var at := Vector2(MARGIN, size.y - MARGIN - REGION_BAR_HEIGHT)
	draw_rect(Rect2(at, Vector2(REGION_BAR_WIDTH, REGION_BAR_HEIGHT)),
		Color(0.16, 0.18, 0.22))
	var fraction := clampf(float(mined) / float(maxi(1, total)), 0.0, 1.0)
	draw_rect(Rect2(at, Vector2(REGION_BAR_WIDTH * fraction, REGION_BAR_HEIGHT)), hue)
	_icon_text(Icons.REGION, "%s  %d/%d" % [Regions.name_of(region), mined, total],
		at - Vector2(0.0, 16.0), COLOR_DIM, 26, hue)


## Icon, name, level, and the effect spelled out. The icon never replaces the
## words: a row that leaves the player unable to say what Power does is not
## telling them anything.
func _draw_buffs(world: World) -> void:
	var rows := NodeCatalog.ids().size()
	var top := size.y - MARGIN - REGION_BAR_HEIGHT - 52.0 - ROW_HEIGHT * float(rows)

	# The single line that makes every +N on the board mean something.
	var base := World.BASE_ORB_VALUE
	var from_power := world.buffs.level_of(NodeCatalog.YIELD) \
		* NodeCatalog.YIELD_PER_LEVEL
	var orb := "orb %s" % Format.number(world.effective_orb_value())
	if from_power > 0:
		orb = "%s  =  %d base + %s power" % [orb, base,
			Format.number(from_power)]
	if world.overcharge_percent() > 0:
		orb = "%s  +%d%%" % [orb, world.overcharge_percent()]
	_icon_text(Icons.ORB, orb, Vector2(MARGIN, top - 20.0), COLOR_TEXT, 30)

	var y := top + ROW_HEIGHT
	for id in NodeCatalog.ids():
		var key := String(id)
		var type := NodeCatalog.get_type(key)
		var level := world.buffs.level_of(key)
		var color := COLOR_TEXT if level > 0 else Color(0.34, 0.37, 0.43)
		_icon_text(Icons.buff(key), "%s %d" % [type.display_name, level],
			Vector2(MARGIN, y), color, ROW_FONT)
		if level > 0:
			_text(_effect(key, level), Vector2(MARGIN + EFFECT_X, y), COLOR_DIM, 26)
		else:
			_text("locked", Vector2(MARGIN + EFFECT_X, y), Color(0.30, 0.33, 0.38), 26)
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
	var top := size.y - MARGIN - REGION_BAR_HEIGHT - 52.0 - ROW_HEIGHT * float(rows)

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
		_tooltip = "Ram — %s damage\nBanks %d%% of every cell you mine.\nRight-click any cell in an open region, at any distance.\nUnspent damage is kept." \
			% [Format.number(world.ram_damage()), world.ram_share()]
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

	var lines := "%s region — %d hops out" % [Regions.name_of(cell.region), cell.hops]
	if cell.is_mined:
		lines += "\nMined for %s" % Format.number(cell.cost)
		lines += "\nGenerator — emits on the frontier" if cell.is_generator \
			else "\nDud — inert ground, never emits"
	else:
		lines += "\n%s / %s" % [Format.number(cell.progress),
			Format.number(cell.cost)]
		if not world.is_mineable(cell):
			lines += "\nRegion locked — buy Mine %s" % Regions.name_of(cell.region)

	if cell.has_node():
		if visibility >= 2 or cell.is_mined:
			var type := NodeCatalog.get_type(cell.node_id)
			lines += "\n%s +%s" % [type.display_name,
				Format.number(cell.node_grant())]
		else:
			lines += "\nSomething buried here"
	return lines


func _effect(key: String, level: int) -> String:
	match key:
		NodeCatalog.YIELD:
			return "+%s orb value (now %s)" % [
				Format.number(level * NodeCatalog.YIELD_PER_LEVEL),
				Format.number(_world().effective_orb_value())]
		NodeCatalog.PULSE:
			return "+%d%% emission rate" % (level * NodeCatalog.PULSE_PER_LEVEL)
		NodeCatalog.CRIT:
			return "%.1f%% chance of x%d" % [
				float(level * NodeCatalog.CRIT_PER_LEVEL) / 100.0,
				_world().effective_crit_multiplier()]
		NodeCatalog.SPLIT:
			return "%.1f%% chance of two orbs" % (
				float(level * NodeCatalog.SPLIT_PER_LEVEL) / 100.0)
		NodeCatalog.SPLASH:
			return "%.1f%% chance to splash %d%%" % [
				float(level * NodeCatalog.SPLASH_PER_LEVEL) / 100.0,
				_world().effective_splash_percent()]
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


func _icon_text(texture: Texture2D, value: String, at: Vector2, color: Color,
		font_size: int, icon_color: Color = Color.TRANSPARENT) -> float:
	return Icons.draw_label(self, _font, texture, value, at, color, font_size, icon_color)


func _centred(value: String, at: Vector2, color: Color, font_size: int) -> void:
	var width := _font.get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, at - Vector2(width * 0.5, 0.0), color, font_size)

