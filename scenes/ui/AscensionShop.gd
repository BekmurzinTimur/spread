extends Control

## The ascension shop: seven wallets across the top, upgrade cards below, and the
## button that ends a run.
##
## Built in code like `HUD.gd`, and for the same stated reason — the layout lives
## next to the logic that fills it, and there is no theme resource in the project
## to hang it off. Reads the sim and the meta state through `Main`; every purchase
## and the ascension itself go back through Main's command methods.
##
## ⚠️ **This is the project's first modal**, so it sets a precedent rather than
## following one. Two consequences it has to get right:
##
## - The HUD root is `MOUSE_FILTER_IGNORE` on purpose, so the board stays
##   clickable through it. A modal is the exact opposite: this root takes
##   `MOUSE_FILTER_STOP` while open, or clicks fall through onto the board behind
##   it and aim a generator the player cannot see.
## - `get_tree().paused` is deliberately **not** used. Nothing in the project sets
##   `process_mode`, so pausing the tree would freeze the splash and floating-text
##   layers mid-animation. `Main.paused` gates only the accumulator, which is the
##   thing that should stop.

const COLOR_PANEL_BG := Color("0f1218", 0.98)
const COLOR_PANEL_EDGE := Color("272b33")
const COLOR_SCRIM := Color("05060a", 0.82)

const COLOR_TEXT := Color("c3cad6")
const COLOR_TEXT_DIM := Color("7b8290")
const COLOR_ACCENT := Color("9d8cf5")
const COLOR_GOOD := Color("7fd18a")

const CARD_WIDTH := 300
const PANEL_MARGIN := 48

var _main: Node

var _scrim: ColorRect
var _panel: PanelContainer
var _wallets: RichTextLabel
var _ascend_button: Button
var _close_button: Button

## Upgrade key -> the widgets whose text and enabled state change every frame.
## Built once; nothing here is rebuilt per refresh, on the HUD's precedent.
var _cards: Dictionary = {}

## Tier -> the section holding that colour's cards. Hidden until the player has
## some of that currency, so run 1 shows red alone rather than seven columns of
## prices in colours they have never seen.
var _tier_sections: Dictionary = {}

var _open: bool = false


func setup(main: Node) -> void:
	_main = main


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_apply_open_state()


# --- Open / close -------------------------------------------------------


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	_apply_open_state()
	refresh()


func close() -> void:
	_open = false
	_apply_open_state()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## Visibility and mouse filter move together, and the filter is the half that
## matters: a hidden Control still answers `MOUSE_FILTER_STOP`, so leaving it set
## would swallow every board click for the rest of the session.
func _apply_open_state() -> void:
	visible = _open
	mouse_filter = Control.MOUSE_FILTER_STOP if _open \
		else Control.MOUSE_FILTER_IGNORE


## `_input`, not `_unhandled_input`, so Escape and [u] are consumed **before**
## `Main` sees them. Main's Escape clears the selection and its [u] toggles this
## panel; either reaching it while the shop is open would mean one key doing two
## things at once, which is the one rule the whole input scheme is built on.
func _input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_U:
		close()
		get_viewport().set_input_as_handled()


# --- Building -----------------------------------------------------------


func _build() -> void:
	# Dims the board rather than hiding it, so the player keeps the context of the
	# run they are about to end.
	_scrim = ColorRect.new()
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.color = COLOR_SCRIM
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_panel = _make_panel()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = PANEL_MARGIN
	_panel.offset_top = PANEL_MARGIN
	_panel.offset_right = -PANEL_MARGIN
	_panel.offset_bottom = -PANEL_MARGIN
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)

	var title := Label.new()
	title.text = "Ascension"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(title)

	_wallets = RichTextLabel.new()
	_wallets.bbcode_enabled = true
	_wallets.fit_content = true
	_wallets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wallets.custom_minimum_size.y = 44
	column.add_child(_wallets)

	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	_build_sections(body)

	column.add_child(HSeparator.new())
	_build_footer(column)


## One section per family, and within the two per-tier families one sub-section
## per colour. The order is `MetaUpgrades.keys()`'s registration order, so the
## grouping is decided in the catalog rather than by a sort here.
func _build_sections(body: VBoxContainer) -> void:
	var families := [
		MetaUpgrade.FAMILY_BLOCK,
		MetaUpgrade.FAMILY_TIER_SOURCE,
		MetaUpgrade.FAMILY_SOURCE_VALUE,
		MetaUpgrade.FAMILY_SOURCE_RATE,
		MetaUpgrade.FAMILY_REACH,
	]
	for family in families:
		var upgrades: Array[MetaUpgrade] = []
		for key in MetaUpgrades.keys():
			var upgrade := MetaUpgrades.get_upgrade(key)
			if upgrade.family == family:
				upgrades.append(upgrade)
		if upgrades.is_empty():
			continue

		var heading := Label.new()
		heading.text = MetaUpgrade.FAMILY_NAMES[family]
		heading.add_theme_font_size_override("font_size", 16)
		heading.add_theme_color_override("font_color", COLOR_ACCENT)
		body.add_child(heading)

		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(grid)

		for upgrade in upgrades:
			grid.add_child(_make_card(upgrade))


## One card per upgrade: what it is, what it does, what it costs, and a button.
##
## Everything that changes — the level readout, the price, whether the button is
## enabled — is stored in `_cards` and rewritten by `refresh()`. Nothing is
## rebuilt per frame, and the button's disabled state is **pushed from the meta
## state** rather than trusted to the widget, on the auto-aim toggle's precedent.
func _make_card(upgrade: MetaUpgrade) -> Control:
	var card := _make_panel()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var name_label := Label.new()
	name_label.text = upgrade.display_name
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(name_label)

	var description := Label.new()
	description.text = upgrade.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(CARD_WIDTH - 24, 0)
	description.add_theme_font_size_override("font_size", 12)
	description.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	box.add_child(description)

	var status := RichTextLabel.new()
	status.bbcode_enabled = true
	status.fit_content = true
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(status)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 30)
	_style_button(button)
	button.pressed.connect(func(): _on_buy(upgrade.key))
	box.add_child(button)

	_cards[upgrade.key] = {"status": status, "button": button, "card": card}
	return card


func _build_footer(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)

	var note := Label.new()
	note.name = "Note"
	note.text = "Ascending resets the board. Everything you have bought, and every " \
		+ "coin you have banked, carries over."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	row.add_child(note)

	_ascend_button = Button.new()
	_ascend_button.text = "Ascend — end this run"
	_ascend_button.custom_minimum_size = Vector2(200, 36)
	_style_button(_ascend_button, COLOR_ACCENT)
	_ascend_button.pressed.connect(_on_ascend)
	row.add_child(_ascend_button)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size = Vector2(100, 36)
	_style_button(_close_button)
	_close_button.pressed.connect(close)
	row.add_child(_close_button)


## The HUD's panel recipe. Duplicated rather than shared: `HUD._make_panel` is
## private to a sibling, and a util module for fourteen lines of StyleBoxFlat
## would be more indirection than the project keeps anywhere else.
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


## Chrome, not a tier colour. The shop is a menu rather than a thing on the
## board, so it takes the neutral ramp — the one place it names a colour is a
## wallet, where the colour *is* the information.
func _style_button(button: Button, accent: Color = COLOR_TEXT_DIM) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)

	var hover := style.duplicate()
	hover.border_color = accent

	var disabled := style.duplicate()
	disabled.bg_color = Color("0b0d12", 0.9)
	disabled.border_color = Color("1c2027")

	for state in ["normal", "focus"]:
		button.add_theme_stylebox_override(state, style)
	for state in ["hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("4a505c"))


# --- Commands -----------------------------------------------------------


func _on_buy(key: String) -> void:
	if _main == null:
		return
	_main.buy_upgrade(key)
	refresh()


func _on_ascend() -> void:
	if _main == null:
		return
	# `ascend()` re-opens this panel on its way out, which is deliberate: the
	# shop is the reward for stopping, so ending a run should land the player in
	# it rather than on an empty board.
	_main.ascend()
	refresh()


# --- Refresh ------------------------------------------------------------


## Rewrites every changing figure from the model. Called on open, after every
## purchase, and from `Main._process` while the panel is up — so the wallets
## track a run that is still delivering behind the scrim.
func refresh() -> void:
	if not _open or _main == null or _main.meta == null:
		return
	var meta: MetaState = _main.meta
	_refresh_wallets(meta)
	_refresh_cards(meta)


## Banked and, separately, what this run has earned but not yet banked. The two
## are kept apart because only the first can be spent: ascending is what moves
## the second across, and showing them summed would make the shop look like it
## was refusing a purchase the player could afford.
func _refresh_wallets(meta: MetaState) -> void:
	var parts := PackedStringArray()
	for tier in Tiers.COUNT:
		var banked := meta.wallet(tier)
		var pending: int = 0
		if _main.world != null and tier < _main.world.earned.size():
			pending = _main.world.earned[tier]
		# A colour the player has never held is not shown at all. Run 1 is red and
		# nothing else, and seven columns of prices in colours they cannot earn
		# would bury the two purchases that actually matter.
		if banked == 0 and pending == 0:
			continue
		var hex := Tiers.color_of(tier).to_html(false)
		var text := "[color=#%s]%s %s[/color]" % [hex, Tiers.name_of(tier), _amount(banked)]
		if pending > 0:
			text += "[color=#%s] +%s[/color]" % [COLOR_GOOD.to_html(false), _amount(pending)]
		parts.append(text)

	if parts.is_empty():
		_wallets.text = "[color=#%s]Mine a cell to earn its colour. A cell costing 50 red pays 50 red.[/color]" \
			% COLOR_TEXT_DIM.to_html(false)
		return
	_wallets.text = "    ".join(parts)


func _refresh_cards(meta: MetaState) -> void:
	for key in _cards:
		var upgrade := MetaUpgrades.get_upgrade(key)
		var widgets: Dictionary = _cards[key]
		var status: RichTextLabel = widgets["status"]
		var button: Button = widgets["button"]
		var card: PanelContainer = widgets["card"]

		var level := meta.level_of(key)
		var cost := meta.next_cost(key)
		var hex := Tiers.color_of(upgrade.currency_tier).to_html(false)

		# A colour the player has never held hides every card priced in it, for
		# the reason the wallet row does: an orange price means nothing until
		# orange exists. Cards already bought stay visible, so a ladder the player
		# has climbed does not vanish behind them.
		card.visible = level > 0 or meta.wallet(upgrade.currency_tier) > 0 \
			or upgrade.currency_tier == Tiers.RED

		if cost < 0:
			status.text = "[color=#%s]%s[/color]" % [
				COLOR_GOOD.to_html(false),
				"Unlocked" if upgrade.is_unlock() else "Maxed — level %d" % level,
			]
			button.text = "Bought"
			button.disabled = true
			continue

		if upgrade.is_unlock():
			status.text = "[color=#%s]%s %s[/color]" % [hex,
				Tiers.name_of(upgrade.currency_tier), _amount(cost)]
		else:
			status.text = "level %d / %d      [color=#%s]%s %s[/color]" % [
				level, upgrade.max_level, hex,
				Tiers.name_of(upgrade.currency_tier), _amount(cost)]

		var affordable := meta.can_afford(key)
		button.text = "Buy" if affordable else "Not enough %s" \
			% Tiers.name_of(upgrade.currency_tier)
		button.disabled = not affordable


## Thousands separators, because these run to ten digits by the deep bands and an
## unbroken string of them is unreadable at a glance. Integer-only, like
## everything else the economy prints.
static func _amount(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
