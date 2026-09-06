extends Control

## Selection panel, build controls, and the value-ledger readout.
##
## Built in code rather than as a scene tree so the layout lives next to the
## logic that fills it. Reads the sim through Main; issues commands back
## through Main's command methods.

const PANEL_WIDTH := 300
const COLOR_PANEL_BG := Color("11141c", 0.94)
const COLOR_PANEL_EDGE := Color("2c3242")

## Size of one idle-block indicator in the bottom-right corner.
const IDLE_BUTTON_SIZE := Vector2(64, 44)

var _main: Node

var _title: Label
var _detail: RichTextLabel
var _aim: Button
var _swap: Button
var _hint: Label
var _status: Label
var _ledger: RichTextLabel

## Block type id -> its idle-count button. Built once; only visibility and the
## count change per frame.
var _idle_buttons: Dictionary = {}


func setup(main: Node) -> void:
	_main = main


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_status_bar()
	_build_side_panel()
	_build_idle_bar()


## An opaque panel. The board is drawn behind the HUD, so without an explicit
## background the cells show through and the text becomes unreadable.
func _make_panel() -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 10

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _build_status_bar() -> void:
	var bar := _make_panel()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	_status = Label.new()
	bar.add_child(_status)


func _build_side_panel() -> void:
	var panel := _make_panel()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -PANEL_WIDTH - 12
	panel.offset_right = -12
	panel.offset_top = 52
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.custom_minimum_size.x = PANEL_WIDTH
	panel.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	column.add_child(_title)

	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.custom_minimum_size.y = 108
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_detail)

	column.add_child(HSeparator.new())

	_aim = _add_button(column, "Aim  (A)", func(): _main.begin_aim())
	_swap = _add_button(column, "Swap with…  (S)", func(): _main.begin_swap())

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color("8fa4c8"))
	column.add_child(_hint)

	column.add_child(HSeparator.new())

	_ledger = RichTextLabel.new()
	_ledger.bbcode_enabled = true
	_ledger.fit_content = true
	_ledger.custom_minimum_size.y = 150
	_ledger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_ledger)


## One indicator per block type, bottom-right, shown only while that type has
## something idle. Each is drawn to look like the cell it will take you to, so
## the thing you click and the thing you land on read as the same object.
func _build_idle_bar() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.offset_left = -400
	row.offset_right = -16
	row.offset_top = -IDLE_BUTTON_SIZE.y - 16
	row.offset_bottom = -16
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# The HUD root ignores the mouse so the board can be clicked through it; this
	# row has to take it back, or the buttons never receive a press.
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(row)

	for id in BlockCatalog.ids():
		var def := BlockCatalog.get_def(id)
		if not def.needs_target:
			continue  # a block with no target can never be idle
		var button := _make_idle_button(def)
		row.add_child(button)
		_idle_buttons[id] = button


func _make_idle_button(def: BlockDef) -> Button:
	var style := StyleBoxFlat.new()
	style.bg_color = def.color.darkened(0.55)
	style.border_color = def.color
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 8
	style.content_margin_right = 10

	var button := Button.new()
	button.custom_minimum_size = IDLE_BUTTON_SIZE
	# The glyphs import at 64px and would otherwise draw at native size.
	button.expand_icon = true
	if not def.icon_path.is_empty():
		var texture := load(def.icon_path)
		if texture is Texture2D:
			button.icon = texture
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_color_override("icon_%s_color" % state, def.color)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", def.color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.pressed.connect(func(): _main.focus_next_idle(def.id))
	return button


func _add_button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func refresh() -> void:
	if _main == null or _main.world == null:
		return
	_refresh_status()
	_refresh_selection()
	_refresh_idle()
	_refresh_ledger()


func _refresh_status() -> void:
	var world: World = _main.world
	var speed_text := "paused" if _main.paused else "x%d" % _main.speed
	_status.text = "Spread    %d / %d mined    orbs %d    tick %d    %s     left-drag pan · wheel zoom · [space] pause · [1/2/3] speed" % [
		world.unlocked_count(), world.graph.size(),
		world.live_orb_count(), world.tick_count, speed_text,
	]


func _refresh_selection() -> void:
	var world: World = _main.world
	var cell: GraphCell = _main.selected_cell()

	if cell == null:
		_title.text = "Nothing selected"
		_detail.text = "[color=#6d7590]Click a cell to inspect it.\n\nYou can only see as far as you have dug. Feed an unmined cell to find out what it was holding, and to uncover whatever lies beyond it.[/color]"
		_set_buttons_enabled(false, false)
		_hint.text = ""
		return

	_title.text = "Cell %d" % cell.id

	var lines: Array[String] = []
	if cell.is_unlocked:
		lines.append("[color=#7fd18a]Mined[/color]")
		if cell.block != null:
			lines.append("Holds: [b]%s[/b]" % cell.block.def.display_name)
			if cell.block.def.needs_target:
				if cell.block.has_target():
					var target: int = cell.block.target_id
					var arrival: int = world.projected_arrival(cell.id, target)
					var hops: int = world.graph.distance(cell.id, target)
					var color := "#4fd1c5" if arrival > 0 else "#d95c5c"
					lines.append("Aimed at cell %d — %d hops" % [target, hops])
					# No "of 10": pumps stack without a ceiling, so an arrival
					# can legitimately beat the value the orb launched with, and
					# a denominator would read as a cap that does not exist.
					var launched := " (launched with %d)" % World.ORB_START_VALUE
					lines.append("Arrives with [color=%s][b]%d[/b][/color]%s"
						% [color, arrival, launched])
				else:
					lines.append("[color=#d95c5c]Idle — not aimed[/color]")
		else:
			lines.append("[color=#6d7590]Empty — swap something into it.[/color]")
	else:
		lines.append("[color=#d9a05c]Not mined[/color]")
		lines.append("Contains: [color=#6d7590][b]unknown[/b][/color]")
		lines.append("Mined at: [b]%d[/b] / %d" % [cell.unlock_progress, cell.unlock_cost])
		lines.append("Remaining: %d" % cell.unlock_remaining())

	_detail.text = "\n".join(lines)

	var can_aim: bool = cell.block != null and cell.block.def.needs_target
	# An anchored block cannot leave, and nothing can be swapped onto it either,
	# so the button is dead on this cell rather than merely likely to fail.
	var anchored: bool = cell.block != null and not cell.block.def.movable
	_set_buttons_enabled(can_aim, cell.is_unlocked and not anchored)

	if _main.aiming:
		_hint.text = "Aiming — click a destination cell. Right-click or Esc to cancel."
	elif _main.swapping:
		_hint.text = "Swapping — click another mined cell to exchange contents. Right-click or Esc to cancel."
	elif not cell.is_unlocked:
		_hint.text = "Aim a generator here to mine it and see what it holds. Orbs lose %d value per hop and vanish at 0." % World.DECAY_PER_HOP
	elif anchored:
		_hint.text = "Anchored — a %s stays where the map buried it. Move pumps to it instead." % cell.block.def.display_name.to_lower()
	elif cell.block != null and cell.block.def.id == BlockCatalog.PUMP:
		_hint.text = "Pumps add +%d to orbs passing through and stack along a route, but never fire on the last hop. Put one mid-route, not on the target." % cell.block.def.restore_amount
	else:
		_hint.text = ""


func _refresh_idle() -> void:
	var world: World = _main.world
	for id in _idle_buttons:
		var button: Button = _idle_buttons[id]
		var count: int = world.idle_cells_of(id).size()
		button.visible = count > 0
		if count == 0:
			continue
		button.text = str(count)
		var label := BlockCatalog.get_def(id).display_name.to_lower()
		button.tooltip_text = "%d idle %s — click to jump to the next one" % [
			count, label if count == 1 else label + "s",
		]


func _set_buttons_enabled(aim: bool, swap: bool) -> void:
	_aim.disabled = not aim
	_swap.disabled = not swap


func _refresh_ledger() -> void:
	var world: World = _main.world
	var balanced: bool = world.ledger_balanced()
	var check := "[color=#7fd18a]balanced[/color]" if balanced else "[color=#d95c5c]BROKEN[/color]"
	_ledger.text = "\n".join([
		"[color=#6d7590]value ledger[/color]",
		"produced   %d" % world.produced,
		"restored   %d" % world.restored,
		"delivered  %d" % world.delivered,
		"decayed    %d" % world.decayed,
		"wasted     %d" % world.wasted,
		"cancelled  %d" % world.cancelled,
		"in flight  %d" % world.in_flight_value(),
		"evaporated %d orbs" % world.evaporated_orbs,
		check,
	])
