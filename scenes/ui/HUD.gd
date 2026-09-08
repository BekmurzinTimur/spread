extends Control

## Selection panel, build controls, and the value-ledger readout.
##
## Built in code rather than as a scene tree so the layout lives next to the
## logic that fills it. Reads the sim through Main; issues commands back
## through Main's command methods.

const PANEL_WIDTH := 300
const COLOR_PANEL_BG := Color("0f1218", 0.94)
const COLOR_PANEL_EDGE := Color("272b33")

## Size of one idle-block indicator in the bottom-right corner.
const IDLE_BUTTON_SIZE := Vector2(64, 44)

## The auto-aim toggle, top-right. Chrome rather than a tier colour: a mode
## switch is not a resource, and seven hues on one board is where a stray
## decorative colour starts lying.
const AUTO_AIM_BUTTON_SIZE := Vector2(104, 32)
const COLOR_AUTO_AIM_ON := Color("9d8cf5")

var _main: Node

var _title: Label
var _detail: RichTextLabel
var _hint: Label
var _status: Label
var _ledger: RichTextLabel

## The board-wide buffs panel and its container, bottom-left. Hidden outright
## until the first challenge is mined, so an early board carries no empty frame.
var _buffs_panel: PanelContainer
var _buffs: RichTextLabel

## Block type id -> its idle-count button. Built once; only visibility and the
## count change per frame.
var _idle_buttons: Dictionary = {}

## The auto-aim toggle, top-right. Its pressed state is pushed from the world
## every frame rather than trusted to the button, so it stays right whether the
## mode was flipped by this button or by the [a] key.
var _auto_aim_button: Button


func setup(main: Node) -> void:
	_main = main


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_status_bar()
	_build_side_panel()
	_build_buffs_panel()
	_build_idle_bar()
	_build_auto_aim_toggle()


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


## What the mined challenges are doing for the whole board, bottom-left.
##
## Deliberately not part of the side panel, which is selection-scoped and blanks
## whenever nothing is selected. A board-wide buff belongs to the board, not to
## whatever cell the player happens to have clicked, and it has to stay legible
## while they are inspecting something else.
func _build_buffs_panel() -> void:
	_buffs_panel = _make_panel()
	_buffs_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_buffs_panel.offset_left = 12
	_buffs_panel.offset_right = 12 + PANEL_WIDTH
	_buffs_panel.offset_bottom = -12
	_buffs_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_buffs_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buffs_panel.visible = false
	add_child(_buffs_panel)

	_buffs = RichTextLabel.new()
	_buffs.bbcode_enabled = true
	_buffs.fit_content = true
	_buffs.scroll_active = false
	_buffs.custom_minimum_size = Vector2(0, 0)
	_buffs_panel.add_child(_buffs)


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

	# No buttons at all. Aiming and swapping are both a right-click on the
	# destination, so there is no mode to enter and nothing for a button to do —
	# the Swap button followed the Aim button out for the same reason. The hint
	# below carries both gestures.
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color("9aa3b2"))
	column.add_child(_hint)

	column.add_child(HSeparator.new())

	_ledger = RichTextLabel.new()
	_ledger.bbcode_enabled = true
	_ledger.fit_content = true
	_ledger.custom_minimum_size.y = 170
	_ledger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_ledger)


## How many block types could ever show an idle button — the same filter the row
## below is built with, so the width and the contents can never disagree.
func _idle_capable_count() -> int:
	var count := 0
	for id in BlockCatalog.ids():
		var def := BlockCatalog.get_def(id)
		if def.needs_target or def.has_ports():
			count += 1
	return count


## One indicator per block type, bottom-right, shown only while that type has
## something idle. Each is drawn to look like the cell it will take you to, so
## the thing you click and the thing you land on read as the same object.
func _build_idle_bar() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# Wide enough for every type that can idle at once, counted from the catalog
	# rather than written down. It was a literal 400 when there were two such
	# types and a literal 13 when there were thirteen, and it went stale both
	# times — every family added is another column, and the failure is a row that
	# silently runs off the left edge of the screen. Derived, it cannot drift.
	row.offset_left = -(IDLE_BUTTON_SIZE.x + 8) * _idle_capable_count() - 16
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
		# Either mechanism for placing an output: a target, or ports. A block with
		# neither — a pump, a sphere — can never be idle.
		if not def.needs_target and not def.has_ports():
			continue
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


## The auto-aim toggle, top-right under the status bar.
##
## Its own container rather than a seat in the idle row: that row's width is
## derived from how many types can currently idle, and a permanent button in it
## would have to be counted in — a second thing to keep in step with the catalog,
## for no gain.
##
## The one widget the side panel's "a command that is one right-click needs no
## button" rule does not cover, because auto-aim is not a command on the selected
## cell. It is a standing mode with no gesture of its own, so it needs something
## to be visible on — and the button is where the player learns the mode exists
## at all.
func _build_auto_aim_toggle() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.offset_left = -AUTO_AIM_BUTTON_SIZE.x - 16
	row.offset_right = -16
	# Clear of the status bar, which spans the top edge.
	row.offset_top = 48
	row.offset_bottom = 48 + AUTO_AIM_BUTTON_SIZE.y
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# The HUD root ignores the mouse; this row has to take it back, or the button
	# never receives a press. Same handshake as the idle bar.
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(row)

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)

	var on_style := style.duplicate()
	on_style.bg_color = COLOR_AUTO_AIM_ON.darkened(0.6)
	on_style.border_color = COLOR_AUTO_AIM_ON

	_auto_aim_button = Button.new()
	_auto_aim_button.custom_minimum_size = AUTO_AIM_BUTTON_SIZE
	_auto_aim_button.toggle_mode = true
	_auto_aim_button.text = "Auto-aim"
	# Struck from the chrome ramp rather than a tier colour. Colour on this board
	# means a resource tier, and a mode switch is not one — it is chrome, like a
	# route line or the selection ring.
	for state in ["normal", "hover", "focus", "disabled"]:
		_auto_aim_button.add_theme_stylebox_override(state, style)
	for state in ["pressed", "hover_pressed"]:
		_auto_aim_button.add_theme_stylebox_override(state, on_style)
	_auto_aim_button.add_theme_color_override("font_color", Color("8b93a7"))
	_auto_aim_button.add_theme_color_override("font_pressed_color", COLOR_AUTO_AIM_ON)
	_auto_aim_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_auto_aim_button.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	_auto_aim_button.pressed.connect(func(): _main.toggle_auto_aim())
	row.add_child(_auto_aim_button)


func refresh() -> void:
	if _main == null or _main.world == null:
		return
	_refresh_status()
	_refresh_selection()
	_refresh_buffs()
	_refresh_idle()
	_refresh_auto_aim()
	_refresh_ledger()


## The mined challenges and what each is doing, or nothing at all.
##
## The panel disappears rather than showing "no buffs yet", because for most of a
## playthrough that is the answer and a permanently empty frame is just clutter.
## The first challenge mined is a milestone, and having the panel appear with it
## is the announcement.
func _refresh_buffs() -> void:
	var world: World = _main.world
	var challenges := world.mined_challenges()
	var upkeeps := world.mined_upkeeps()
	_buffs_panel.visible = not (challenges.is_empty() and upkeeps.is_empty())
	if not _buffs_panel.visible:
		return

	var lines: Array[String] = ["[color=#6d7590]board-wide[/color]"]
	for def in challenges:
		lines.append("[color=#%s]%s[/color]  %s" % [
			def.color.to_html(false), def.display_name, def.description,
		])
	# An upkeep block's bonus can go out while the player is looking at something
	# else entirely, so its live state belongs here rather than only on its own
	# cell — this panel is the one place a board-wide effect is always legible.
	for cell in upkeeps:
		var def := cell.block.def
		var lit: bool = cell.block.fuelled
		lines.append("[color=#%s]%s[/color]  cell %d — [color=%s]%s[/color]  %d fuel" % [
			def.color.to_html(false), def.display_name, cell.id,
			"#7fd18a" if lit else "#d95c5c",
			"generators +%d%%" % def.global_rate_percent if lit else "dark",
			cell.block.charge,
		])
	_buffs.text = "\n".join(lines)


func _refresh_status() -> void:
	var world: World = _main.world
	var speed_text := "paused" if _main.paused else "x%d" % _main.speed
	_status.text = "Spread    %d / %d mined    orbs %d    tick %d    %s     left-drag pan · wheel zoom · [space] pause · [1/2/3] speed · [a] auto-aim" % [
		world.unlocked_count(), world.graph.size(),
		world.live_orb_count(), world.tick_count, speed_text,
	]


func _refresh_selection() -> void:
	var world: World = _main.world
	var cell: GraphCell = _main.selected_cell()

	if cell == null:
		_title.text = "Nothing selected"
		_detail.text = "[color=#6d7590]Click a cell to inspect it.\n\nYou can only see as far as you have dug. Feed an unmined cell to find out what it was holding, and to uncover whatever lies beyond it.[/color]"
		_hint.text = ""
		return

	# The panel is always about one cell — the group's primary — so the title says
	# how many others are coming along rather than trying to describe all of them.
	# Their stats are the same stats: a group is one block type by construction.
	var group: PackedInt32Array = _main.selected_ids
	_title.text = "Cell %d" % cell.id
	if group.size() > 1:
		_title.text += "   +%d more" % (group.size() - 1)

	var lines: Array[String] = []
	if cell.is_unlocked:
		lines.append("[color=#7fd18a]Mined[/color]")
		if cell.block != null:
			lines.append("Holds: [b]%s[/b]" % cell.block.def.display_name)
			if group.size() > 1:
				lines.append("[color=#9d8cf5]%d selected — commands apply to all[/color]"
					% group.size())
			lines.append_array(_stat_lines(world, cell))
			if cell.block.def.needs_target:
				if cell.block.has_target():
					var target: int = cell.block.target_id
					# Both read off the block's *actual* route. `graph.distance`
					# answers about the shortest path, which is the wrong question
					# the moment a route is bent through waypoints.
					var route := world.block_route(cell.id)
					var arrival: int = world.arrival_along(route)
					var hops: int = maxi(0, route.size() - 1)
					var color := "#4fd1c5" if arrival > 0 else "#d95c5c"
					lines.append("Aimed at cell %d — %d hops" % [target, hops])
					if cell.block.has_waypoints():
						var stops := PackedStringArray()
						for id in cell.block.route_via:
							stops.append(str(id))
						lines.append("[color=#6d7590]via %s[/color]"
							% " → ".join(stops))
					# No "of 10": pumps stack without a ceiling, so an arrival
					# can legitimately beat the value the orb launched with, and
					# a denominator would read as a cap that does not exist.
					var launched := " (launched with %d)" % world.effective_orb_value()
					lines.append("Arrives with [color=%s][b]%d[/b][/color]%s"
						% [color, arrival, launched])
				else:
					lines.append("[color=#d95c5c]Idle — not aimed[/color]")
		else:
			lines.append("[color=#6d7590]Empty — right-click a mined cell to pull its block here.[/color]")
	else:
		lines.append("[color=#d9a05c]Not mined[/color]")
		# The category, never the identity. A challenge announces that it is one
		# so its price makes sense; which of the three it is stays hidden like
		# every other cell's contents.
		if cell.is_challenge():
			lines.append("[color=#e0b050][b]Challenge[/b][/color]")
		# Named as well as tinted. The board already says which colour this cell
		# takes by how it is drawn, but the panel is where a number gets checked
		# before it is committed to, and a cost of 3200 means two quite different
		# things depending on what has to arrive to pay it.
		lines.append("Needs: [color=%s][b]%s[/b][/color]"
			% [Tiers.color_of(cell.required_tier).to_html(false),
				Tiers.name_of(cell.required_tier)])
		lines.append("Contains: [color=#6d7590][b]unknown[/b][/color]")
		lines.append("Mined at: [b]%d[/b] / %d" % [cell.unlock_progress, cell.unlock_cost])
		lines.append("Remaining: %d" % cell.unlock_remaining())

	_detail.text = "\n".join(lines)

	# An anchored block cannot leave, and nothing can be swapped onto it either.
	var anchored: bool = cell.block != null and not cell.block.def.movable

	if _main.can_aim_selection():
		# Shown whenever something aimable is selected, because there is no aim
		# mode to be in — the controls *are* the state.
		var pending: PackedInt32Array = _main.pending_via
		if pending.is_empty() and group.size() > 1:
			_hint.text = "Right-click aims all %d. Shift+right-click bends one shared route through a cell — sources that cannot take it keep the route they had." % group.size()
		elif pending.is_empty():
			_hint.text = "Right-click a cell to aim at it. Shift+right-click routes the orb through a cell on the way — a route may not cross itself. Double-click to pick up every %s on screen." % cell.block.def.display_name.to_lower()
		else:
			_hint.text = "Routing via %d of %d — shift+right-click to extend, right-click to finish, Backspace to undo one, Esc to clear." % [
				pending.size(), World.MAX_WAYPOINTS,
			]
	elif not cell.is_unlocked and cell.is_challenge():
		_hint.text = "A challenge — one of three on the map, and far more expensive than its neighbours. What it grants is unknown until you mine it, but it helps the whole board, not just this corner."
	elif not cell.is_unlocked:
		_hint.text = "Aim a generator here to mine it and see what it holds. Orbs lose %d value per hop and vanish at 0." % World.DECAY_PER_HOP
	elif cell.block != null and cell.block.def.is_challenge:
		_hint.text = "Mined, and working everywhere. A challenge helps every matching block on the board at once, so there is nothing to place and nothing to aim."
	elif anchored:
		_hint.text = "Anchored — a %s stays where the map buried it. Select a pump and right-click here to bring one to it." % cell.block.def.display_name.to_lower()
	elif cell.block != null and cell.block.def.id == BlockCatalog.PUMP:
		# The effective amount, so the hint agrees with the arrival figure above
		# it when a sphere is boosting this pump.
		# The percentage *and* what it is worth on an orb leaving a generator
		# today, because the percentage alone is now one step removed from the
		# arrival figure above it — and the effective one, so both agree with the
		# simulation when a sphere is boosting this pump.
		_hint.text = "Pumps add +%d%% of an orb's launch value — +%d on one leaving a generator now — and stack along a route, but never fire on the last hop. Put one mid-route, not on the target. Right-click another mined cell to move it there." % [
			world.effective_restore_percent(cell),
			world.restore_for(cell, world.effective_orb_value()),
		]
	elif cell.block != null and cell.block.def.amplifies():
		# Sold against the pump, because the choice between them is the whole
		# point of the block: an addend that stacks versus a multiplier that
		# compounds. The pump is worth more on a thin orb and the amplifier runs
		# away with a fat one, so the number that decides it is what is already
		# arriving — which is the figure directly above this hint.
		_hint.text = "Amplifiers multiply an orb by x%.2f on the way through, and compound with each other — where a pump adds a fixed share, this scales whatever arrives. Worth most on a route that is already delivering well. Never fires on the last hop. Right-click another mined cell to move it there." % [
			(100.0 + cell.block.def.amplify_percent) / 100.0,
		]
	elif cell.block != null and cell.block.def.radiates():
		_hint.text = "Spheres help every block within %d hops and stack with each other. They do nothing on their own — park one where generators, upgraders and pumps are already working. Right-click another mined cell to move it there." % world.effective_field_radius(cell.block.def)
	elif cell.block != null and cell.block.def.movable:
		# The upkeep block, and anything movable added later that has no hint of
		# its own — every movable block should at least say how to move it.
		_hint.text = "Right-click another mined cell to move this there — swapping is free, instant and works at any distance."
	elif cell.block == null:
		# Mined and empty: the pull direction, which is the half of swapping that
		# is easy to miss.
		_hint.text = "Empty. Right-click a mined cell holding a pump, sphere or upkeep block to pull it here."
	else:
		_hint.text = ""


## What this block's numbers actually are right now, and what they would be on
## its own. A stat a sphere has changed is shown as "effective (was base)", so a
## player can see both the benefit and what they would lose by moving the sphere;
## an unbuffed block just states its number.
##
## A sphere reports its reach instead, counting only the blocks it is genuinely
## changing — cells in range holding nothing, or holding another sphere, are in
## the field but are not being helped, and counting them would overstate it.
func _stat_lines(world: World, cell: GraphCell) -> Array[String]:
	var def := cell.block.def
	var lines: Array[String] = []

	# A challenge has no stats of its own to report — it changes everyone else's.
	# Stated as one line about the board rather than a number about this cell,
	# because a number here would invite the player to look for where it applies.
	if def.is_challenge:
		lines.append("[color=#e0b050]%s[/color]" % def.description)
		return lines

	# A converter's "interval" is its charge bank, so it reports that instead of
	# a tick count. Shown as a fraction rather than a percentage because the
	# numbers are the same ones the player is routing — what has landed, and what
	# it takes — and a percentage would hide both.
	# Before the converter branch: both fill a bank from delivered orbs, but this
	# one spends it on time rather than on a higher tier, so what matters is the
	# latch and how long the bank will hold it.
	if def.burns_upkeep():
		var fuel: int = cell.block.charge
		var lit: bool = cell.block.fuelled
		var color := "#7fd18a" if lit else "#d95c5c"
		var state := "running" if lit else ("dry" if fuel <= 0 else "filling")
		lines.append("Fuel [color=%s][b]%d[/b] / %d[/color]  %s"
			% [color, fuel, def.upkeep_reserve, state])
		lines.append("Burns [b]%d[/b] %s per tick" % [
			def.upkeep_drain, Tiers.name_of(def.input_tier),
		])
		if lit:
			# Ticks of runway, not a percentage: it is the number the player has
			# to plan a feed around.
			lines.append("[color=#7fd18a]Generators +%d%% rate board-wide — %d ticks of fuel left[/color]"
				% [def.global_rate_percent, fuel / maxi(1, def.upkeep_drain)])
		else:
			lines.append("[color=#6d7590]Aim a generator at this cell. Lights up at %d.[/color]"
				% def.upkeep_reserve)
		return lines

	if def.converts():
		var charge: int = cell.block.charge
		# The effective cost, so the meter agrees with what the simulation will
		# actually spend when a sphere is discounting this converter. The "(was N)"
		# line beside it reports the discount the same way a shortened interval is
		# reported, which is the whole point of showing both numbers.
		var cost: int = world.effective_upgrade_cost(cell)
		var charged: bool = charge >= cost
		var color := "#7fd18a" if charged else "#aeb8cc"
		lines.append("Charge [color=%s][b]%d[/b] / %d[/color]%s"
			% [color, charge, cost, "  ready" if charged else ""])
		lines.append(_stat_line("Costs", cost, world.base_upgrade_cost(cell),
			" " + Tiers.name_of(def.input_tier)))
		lines.append("Converts [color=%s]%s[/color] → [color=%s]%s[/color]"
			% [Tiers.color_of(def.input_tier).to_html(false),
				Tiers.name_of(def.input_tier),
				Tiers.color_of(def.output_tier).to_html(false),
				Tiers.name_of(def.output_tier)])
		lines.append("[color=#6d7590]Aim a generator at this cell to fill it.[/color]")
		return lines

	if def.has_ports():
		var charge: int = cell.block.charge
		var cost: int = world.effective_orb_value()
		var charged: bool = charge >= cost
		var color := "#7fd18a" if charged else "#aeb8cc"
		lines.append("Bank [color=%s][b]%d[/b] / %d[/color]%s"
			% [color, charge, cost, "  ready" if charged else ""])
		var used: int = cell.block.ports.size()
		var out_color := "#7fd18a" if used > 0 else "#6d7590"
		lines.append("Outputs [color=%s][b]%d[/b] / %d[/color]"
			% [out_color, used, def.max_ports])
		lines.append("[color=#6d7590]Right-click a cell to add an output, or right-click one it already feeds to drop it.[/color]")
		return lines

	if def.compresses():
		var charge: int = cell.block.charge
		var cost: int = def.compress_cost
		var charged: bool = charge >= cost
		var color := "#7fd18a" if charged else "#aeb8cc"
		lines.append("Bank [color=%s][b]%d[/b] / %d[/color]%s"
			% [color, charge, cost, "  ready" if charged else ""])
		# Not through `_stat_line`, and the absence of a "(was N)" is the point:
		# nothing on the board discounts a compressor, so a cost that could appear
		# to move would be a promise the simulation does not keep.
		lines.append("Launches one [color=%s]%s[/color] orb worth [b]%d[/b]"
			% [Tiers.color_of(def.output_tier).to_html(false),
				Tiers.name_of(def.output_tier), cost])
		lines.append("[color=#6d7590]Ten ordinary orbs in, one big one out — decay is charged per orb, so it travels about ten times as far.[/color]")
		return lines

	if def.radiates():
		var boosted := 0
		for id in world.field_cells(cell.id):
			if id != cell.id and world.is_boosted(id):
				boosted += 1
		# The effective reach, so this agrees with the field the board draws once
		# a Lens has widened it.
		var reach := world.effective_field_radius(def)
		lines.append(_stat_line("Radiates", reach, def.field_radius, " hops")
			+ " — generators +%d%% rate, upgraders +%d%%, pumps %+d"
			% [def.field_rate_percent, def.field_charge_percent,
				def.field_restore_percent])
		var noun := "block" if boosted == 1 else "blocks"
		var color := "#7fd18a" if boosted > 0 else "#6d7590"
		lines.append("Boosting [color=%s][b]%d[/b] %s[/color]" % [color, boosted, noun])
		return lines

	# Compared against the baseline — base plus any board-wide buff — rather than
	# the def's base, so "(was N)" keeps meaning "a sphere is doing this". Against
	# the raw base, mining a Current would make every pump on the map claim to be
	# standing in a field.
	if def.produce_interval > 0:
		lines.append(_stat_line("Every", world.effective_interval(cell),
			world.base_interval(cell), " ticks"))
	if def.restore_percent > 0:
		lines.append(_stat_line("Restores", world.effective_restore_percent(cell),
			world.base_restore_percent(cell), "%"))
	# Not through `_stat_line`, which exists to say "(was N)" when a field is
	# raising a stat. Nothing on the board raises an amplifier — the percentage is
	# economy-wide because the exponent is resolved from a count — so there is no
	# baseline to compare against and a "(was N)" that could never appear would be
	# a promise the board does not keep.
	if def.amplifies():
		lines.append("Multiplies  x%.2f" % [(100.0 + def.amplify_percent) / 100.0])
	return lines


func _stat_line(label: String, effective: int, base: int, suffix: String) -> String:
	if effective == base:
		return "%s [b]%d[/b]%s" % [label, base, suffix]
	return "%s [color=#9d8cf5][b]%d[/b]%s[/color] (was %d)" % [
		label, effective, suffix, base,
	]


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


## Pushed from the world rather than left to the button's own state, so the [a]
## key and the button can never disagree about which way the mode is set.
func _refresh_auto_aim() -> void:
	var world: World = _main.world
	_auto_aim_button.button_pressed = world.auto_aim
	if world.auto_aim:
		_auto_aim_button.tooltip_text = \
			"Auto-aim on [a] — idle sources point themselves at the nearest cell "\
			+ "they can open.\nRight-click a source to aim it yourself; it holds "\
			+ "that line until the cell is mined."
	else:
		_auto_aim_button.tooltip_text = \
			"Auto-aim off [a] — click to have idle sources aim themselves at the "\
			+ "nearest cell they can open."


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
		"converted  %d" % world.converted,
		"burned     %d" % world.burned,
		"in flight  %d" % world.in_flight_value(),
		"evaporated %d orbs" % world.evaporated_orbs,
		check,
	])
