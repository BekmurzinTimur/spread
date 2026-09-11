extends Control

## The project's one modal, and the whole of the between-runs phase: the wallet,
## the upgrade blocks, and Start run.
##
## One horizontal block per colour. Open blocks sell; the next closed one is shown
## dimmed as a teaser; the rest stay hidden.

const MARGIN := 60.0
const TOP := MARGIN + 156.0
const CARD_WIDTH := 450.0
const CARD_HEIGHT := 104.0
const CARD_PAD := 20.0
const CARD_GAP := 12.0
const HEADER_GAP := 40.0
const BLOCK_GAP := 28.0
const SCROLL_STEP := 60.0

## Room kept clear under the cards for the reset button.
const BOTTOM_CLEAR := 76.0

const TEASER_ALPHA := 0.35

const COLOR_SCRIM := Color(0.02, 0.03, 0.04, 0.86)
const COLOR_CARD := Color(0.10, 0.12, 0.15, 0.95)
const COLOR_CARD_HOVER := Color(0.16, 0.19, 0.24, 0.95)
const COLOR_CARD_OWNED := Color(0.08, 0.14, 0.10, 0.95)
const COLOR_TEXT := Color("dfe5ee")
const COLOR_DIM := Color("7b8290")
const COLOR_GOOD := Color("6fcf7f")
const COLOR_BAD := Color("c05a55")

const ICON_SIZE := 48.0
const ICON_GAP := 18.0

var main: Node

var _font: Font
var _hovered: String = ""
var _start_rect: Rect2 = Rect2()
var _start_hovered: bool = false
var _reset_rect: Rect2 = Rect2()
var _reset_hovered: bool = false

## Reset wipes everything, so it takes two clicks.
var _reset_armed: bool = false

## Upgrade key -> the rect it was last drawn at. Only buyable cards are here.
var _rects: Dictionary = {}

var _scroll: float = 0.0
var _content_bottom: float = 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var label := Label.new()
	_font = label.get_theme_font("font")
	label.queue_free()


func _meta() -> MetaState:
	return main.meta if main != null else null


func open() -> void:
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	_reset_armed = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hovered = _key_at(event.position)
		_start_hovered = _start_rect.has_point(event.position)
		_reset_hovered = _reset_rect.has_point(event.position)
		if not _reset_hovered:
			_reset_armed = false
		queue_redraw()
		return

	if event is InputEventPanGesture:
		_scroll_by(event.delta.y * SCROLL_STEP * 0.5)
		return

	if not (event is InputEventMouseButton) or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_scroll_by(-SCROLL_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_by(SCROLL_STEP)
		MOUSE_BUTTON_LEFT:
			_click(event.position)


func _click(at: Vector2) -> void:
	if _reset_rect.has_point(at):
		if _reset_armed:
			main.reset_progress()
			_reset_armed = false
		else:
			_reset_armed = true
		queue_redraw()
		return
	if _start_rect.has_point(at):
		main.start_run()
		return
	var key := _key_at(at)
	if not key.is_empty():
		main.buy_upgrade(key)
		queue_redraw()


func _scroll_by(amount: float) -> void:
	var limit := maxf(0.0, _content_bottom - _cards_bottom())
	_scroll = clampf(_scroll + amount, 0.0, limit)
	queue_redraw()


func _cards_bottom() -> float:
	return size.y - MARGIN - BOTTOM_CLEAR


func _key_at(at: Vector2) -> String:
	for key in _rects:
		if _rects[key].has_point(at):
			return String(key)
	return ""


func _draw() -> void:
	var meta := _meta()
	if meta == null:
		return

	draw_rect(Rect2(Vector2.ZERO, size), COLOR_SCRIM)
	_rects.clear()

	_text("ASCENSION", Vector2(MARGIN, MARGIN + 12.0), COLOR_TEXT, 52)
	Icons.draw_label(self, _font, Icons.CURRENCY, "%s banked" % Format.number(meta.banked),
		Vector2(MARGIN, MARGIN + 52.0), COLOR_DIM, 30)

	_start_rect = Rect2(MARGIN, MARGIN + 70.0, 380.0, 62.0)
	draw_rect(_start_rect, COLOR_CARD_HOVER if _start_hovered else COLOR_CARD)
	_icon_centred(Icons.START_RUN, "START RUN  [ENTER]",
		_start_rect.position + Vector2(_start_rect.size.x * 0.5, 41.0),
		COLOR_GOOD, 30)

	_right("+%s from that run" % Format.number(main.last_run_banked),
		Vector2(size.x - MARGIN, MARGIN + 48.0), COLOR_DIM, 30)

	var y := TOP - _scroll
	for region in Regions.COUNT:
		var keys := MetaUpgrades.in_region(region)
		if keys.is_empty():
			continue
		var is_open := meta.region_open(region)
		y = _draw_block(region, keys, is_open, y)
		if not is_open:
			break
	_content_bottom = y + _scroll

	_draw_reset()


## Header, then cards left to right, wrapping. Returns the y below the block.
func _draw_block(region: int, keys: Array[String], is_open: bool, y: float) -> float:
	var hue := Regions.color_of(region)
	var header := Regions.name_of(region).to_upper()
	if not is_open:
		header = "%s  —  buy Mine %s to open" % [header, Regions.name_of(region)]
		hue.a = TEASER_ALPHA
	if _in_view(y, HEADER_GAP):
		Icons.draw_label(self, _font, Icons.REGION, header, Vector2(MARGIN, y + 26.0),
			hue, 26)
	y += HEADER_GAP

	var x := MARGIN
	for key in keys:
		if x > MARGIN and x + CARD_WIDTH > size.x - MARGIN:
			x = MARGIN
			y += CARD_HEIGHT + CARD_GAP
		if _in_view(y, CARD_HEIGHT):
			_draw_card(MetaUpgrades.get_upgrade(key),
				Rect2(x, y, CARD_WIDTH, CARD_HEIGHT), is_open)
		x += CARD_WIDTH + CARD_GAP
	return y + CARD_HEIGHT + BLOCK_GAP


func _in_view(y: float, height: float) -> bool:
	return y >= TOP - 1.0 and y + height <= _cards_bottom()


func _draw_reset() -> void:
	_reset_rect = Rect2(size.x - MARGIN - 450.0, size.y - MARGIN - 56.0,
		450.0, 56.0)
	draw_rect(_reset_rect,
		COLOR_CARD_HOVER if _reset_hovered else COLOR_CARD)
	var label := "RESET EVERYTHING?  click again" if _reset_armed \
		else "RESET PROGRESS"
	_icon_centred(Icons.RESET, label,
		_reset_rect.position + Vector2(_reset_rect.size.x * 0.5, 37.0),
		COLOR_BAD if _reset_armed else COLOR_DIM, 24)


func _draw_card(upgrade: MetaUpgrade, rect: Rect2, is_open: bool) -> void:
	var meta := _meta()
	var level := meta.level_of(upgrade.key)
	var maxed := upgrade.is_maxed(level)
	var fade := 1.0 if is_open else TEASER_ALPHA

	var background := COLOR_CARD
	if maxed:
		background = COLOR_CARD_OWNED
	elif is_open and _hovered == upgrade.key:
		background = COLOR_CARD_HOVER
	background.a *= fade
	draw_rect(rect, background)

	# Icon column on the left; its level badge sits under it so the description
	# gets the card's full width.
	var icon_centre := Vector2(CARD_PAD + ICON_SIZE * 0.5, rect.size.y * 0.5)
	if not upgrade.is_unlock():
		icon_centre.y = CARD_PAD + ICON_SIZE * 0.5 - 4.0
		var levels := "%d / %d" % [level, upgrade.max_level] \
			if upgrade.is_capped() else "lv %d" % level
		_centred(levels, rect.position + Vector2(icon_centre.x, rect.size.y - 14.0),
			Color(COLOR_DIM, fade), 17)
	Icons.draw(self, Icons.upgrade(upgrade.key), rect.position + icon_centre, ICON_SIZE,
		Color(COLOR_GOOD if maxed else COLOR_TEXT, fade))

	var text_x := CARD_PAD + ICON_SIZE + ICON_GAP
	_text(upgrade.display_name, rect.position + Vector2(text_x, 42.0),
		Color(COLOR_TEXT, fade), 26)
	_text(upgrade.description, rect.position + Vector2(text_x, 76.0),
		Color(COLOR_DIM, fade), 19)

	if not is_open:
		return
	_rects[upgrade.key] = rect

	var right := rect.position + Vector2(rect.size.x - CARD_PAD, 42.0)
	if maxed:
		_right("owned" if upgrade.is_unlock() else "max", right, COLOR_GOOD, 22)
	else:
		var price := Format.number(meta.next_cost(upgrade.key))
		Icons.draw_label(self, _font, Icons.CURRENCY, price,
			right - Vector2(Icons.label_width(_font, price, 22), 0.0),
			COLOR_GOOD if meta.can_afford(upgrade.key) else COLOR_BAD, 22)


func _text(value: String, at: Vector2, color: Color, font_size: int) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _right(value: String, at: Vector2, color: Color, font_size: int) -> void:
	var width := _font.get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, at - Vector2(width, 0.0), color, font_size)


func _icon_centred(texture: Texture2D, value: String, at: Vector2, color: Color,
		font_size: int) -> void:
	var width := Icons.label_width(_font, value, font_size)
	Icons.draw_label(self, _font, texture, value, at - Vector2(width * 0.5, 0.0), color,
		font_size)


func _centred(value: String, at: Vector2, color: Color, font_size: int) -> void:
	var width := _font.get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, at - Vector2(width * 0.5, 0.0), color, font_size)
