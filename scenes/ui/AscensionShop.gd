extends Control

## The project's one modal, and the whole of the between-runs phase: the wallet,
## the upgrade cards, and Start run.
##
## It is open exactly when the simulation is frozen and a fresh board is waiting
## behind it, so every purchase lands on the run you are about to start. There is
## no way out of it but starting that run.
##
## Where buff types get bought — and a type does not appear on the board until
## it has been. That is the progression spine: ascension makes the board
## *richer*, not only the numbers bigger.

const MARGIN := 60.0
const CARD_WIDTH := 470.0
const CARD_HEIGHT := 106.0
const CARD_GAP := 12.0
const COLUMN_GAP := 30.0

## Air above a family heading, and between that heading and its first card. The
## families are the only grouping the shop has, so they carry the whole of its
## structure — run them together and the wall of cards reads as one list.
const GROUP_GAP := 34.0
const HEADER_GAP := 44.0

const COLOR_SCRIM := Color(0.02, 0.03, 0.04, 0.86)
const COLOR_CARD := Color(0.10, 0.12, 0.15, 0.95)
const COLOR_CARD_HOVER := Color(0.16, 0.19, 0.24, 0.95)
const COLOR_CARD_OWNED := Color(0.08, 0.14, 0.10, 0.95)
const COLOR_TEXT := Color("dfe5ee")
const COLOR_DIM := Color("7b8290")
const COLOR_GOOD := Color("6fcf7f")
const COLOR_BAD := Color("c05a55")

var main: Node

var _font: Font
var _hovered: String = ""
var _start_rect: Rect2 = Rect2()
var _start_hovered: bool = false
var _reset_rect: Rect2 = Rect2()
var _reset_hovered: bool = false

## Reset wipes everything, so it takes two clicks. Cleared whenever the modal
## closes or the pointer leaves the button.
var _reset_armed: bool = false

## Upgrade key -> the rect it was last drawn at, so hit-testing and drawing can
## never disagree about where a card is.
var _rects: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
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

	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _reset_rect.has_point(event.position):
			if _reset_armed:
				# Still between runs afterwards — just with an empty wallet and a
				# freshly dealt board behind the shop.
				main.reset_progress()
				_reset_armed = false
			else:
				_reset_armed = true
			queue_redraw()
			return
		if _start_rect.has_point(event.position):
			main.start_run()
			return
		var key := _key_at(event.position)
		if not key.is_empty():
			main.buy_upgrade(key)
			queue_redraw()


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
	_text("◆ %s banked" % Format.thousands(meta.banked),
		Vector2(MARGIN, MARGIN + 52.0), COLOR_DIM, 30)

	# The only way out, top-left: the corner that is on screen whatever the
	# window is doing. The run behind the scrim is already dealt and waiting.
	_start_rect = Rect2(MARGIN, MARGIN + 70.0, 380.0, 62.0)
	draw_rect(_start_rect, COLOR_CARD_HOVER if _start_hovered else COLOR_CARD)
	_centred("START RUN  [ENTER]",
		_start_rect.position + Vector2(_start_rect.size.x * 0.5, 40.0),
		COLOR_GOOD, 30)

	# What the run that just ended paid, stated once. It is no longer a button —
	# ending a run happens on the board now.
	_right("+%s from that run" % Format.thousands(main.last_run_banked),
		Vector2(size.x - MARGIN, MARGIN + 48.0), COLOR_DIM, 30)

	var x := MARGIN
	var top := MARGIN + 156.0
	var y := top
	var last_family := -1
	for key in MetaUpgrades.all():
		var upgrade := MetaUpgrades.get_upgrade(key)
		if upgrade.family != last_family:
			# Air before the heading, but never at the top of a column — the
			# first heading of every column has to sit on the same line, or the
			# columns read as unaligned rather than as separate groups. Added
			# before the break test so a wrapped family discards it with `y`.
			if y > top:
				y += GROUP_GAP
			# Never strand a heading with fewer than two cards under it.
			if last_family != -1 \
					and y + HEADER_GAP + CARD_HEIGHT * 2.0 > size.y - MARGIN:
				x += CARD_WIDTH + COLUMN_GAP
				y = top
			last_family = upgrade.family
			_text(MetaUpgrade.FAMILY_NAMES[upgrade.family].to_upper(),
				Vector2(x, y), COLOR_DIM, 24)
			y += HEADER_GAP
		_draw_card(upgrade, Rect2(x, y, CARD_WIDTH, CARD_HEIGHT))
		y += CARD_HEIGHT + CARD_GAP

	_draw_reset()


## Bottom-right, drawn last so no column of cards can end up over it.
func _draw_reset() -> void:
	_reset_rect = Rect2(size.x - MARGIN - 380.0, size.y - MARGIN - 56.0,
		380.0, 56.0)
	draw_rect(_reset_rect,
		COLOR_CARD_HOVER if _reset_hovered else COLOR_CARD)
	var label := "RESET EVERYTHING?  click again" if _reset_armed \
		else "RESET PROGRESS"
	_centred(label,
		_reset_rect.position + Vector2(_reset_rect.size.x * 0.5, 36.0),
		COLOR_BAD if _reset_armed else COLOR_DIM, 24)


func _draw_card(upgrade: MetaUpgrade, rect: Rect2) -> void:
	var meta := _meta()
	var level := meta.level_of(upgrade.key)
	var maxed := level >= upgrade.max_level
	var cost := meta.next_cost(upgrade.key)
	var affordable := meta.can_afford(upgrade.key)

	_rects[upgrade.key] = rect
	var background := COLOR_CARD
	if maxed:
		background = COLOR_CARD_OWNED
	elif _hovered == upgrade.key:
		background = COLOR_CARD_HOVER
	draw_rect(rect, background)

	_text(upgrade.display_name, rect.position + Vector2(18.0, 36.0),
		COLOR_TEXT, 30)
	_text(upgrade.description, rect.position + Vector2(18.0, 68.0),
		COLOR_DIM, 22)

	# An unlock reads as a toggle, a levelled stat as "3 / 10". Derived from
	# max_level so the two can never disagree.
	var right := rect.position + Vector2(rect.size.x - 18.0, 36.0)
	if maxed:
		_right("owned" if upgrade.is_unlock() else "max", right, COLOR_GOOD, 26)
	else:
		_right("◆ %s" % Format.thousands(cost), right,
			COLOR_GOOD if affordable else COLOR_BAD, 26)
	if not upgrade.is_unlock():
		_right("%d / %d" % [level, upgrade.max_level],
			right + Vector2(0.0, 34.0), COLOR_DIM, 24)


func _text(value: String, at: Vector2, color: Color, font_size: int) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _right(value: String, at: Vector2, color: Color, font_size: int) -> void:
	var width := _font.get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, at - Vector2(width, 0.0), color, font_size)


func _centred(value: String, at: Vector2, color: Color, font_size: int) -> void:
	var width := _font.get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, at - Vector2(width * 0.5, 0.0), color, font_size)
