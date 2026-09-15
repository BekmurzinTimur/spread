class_name UpgradeBadge
extends VBoxContainer

## One upgrade: a hex in its colour, its level under it. Click buys one;
## shift buys 5, ctrl or cmd buys 20, as many as the wallet allows.

signal hovered(key: String)
signal unhovered(key: String)
signal buy_requested(key: String, count: int)

const BULK_SHIFT := 5
const BULK_CTRL := 20

const COLOR_GOOD := Color("6fcf7f")
const COLOR_DIM := Color("7b8290")

var key := ""

@onready var _hex: IconHex = $Hex
@onready var _level: Label = $Level


func _ready() -> void:
	_hex.mouse_entered.connect(func() -> void: hovered.emit(key))
	_hex.mouse_exited.connect(func() -> void: unhovered.emit(key))
	_hex.gui_input.connect(_on_hex_input)


func _on_hex_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		buy_requested.emit(key, count_for(event.ctrl_pressed or event.meta_pressed,
			event.shift_pressed))


static func count_for(ctrl: bool, shift: bool) -> int:
	return BULK_CTRL if ctrl else BULK_SHIFT if shift else 1


## Levels a click would buy with the modifiers held right now.
static func held_count() -> int:
	return count_for(Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META),
		Input.is_key_pressed(KEY_SHIFT))


func refresh(meta: MetaState, is_hovered: bool) -> void:
	var upgrade := MetaUpgrades.get_upgrade(key)
	var level := meta.level_of(key)
	apply_look(_hex, meta, key)
	if is_hovered:
		_hex.outline_color = _hex.outline_color.lerp(Color.WHITE, 0.5)
	var secret := upgrade.hidden and not meta.region_open(upgrade.region)
	_level.text = "" if secret else level_text(upgrade, level)
	_level.add_theme_color_override("font_color",
		COLOR_GOOD if upgrade.is_maxed(level) else COLOR_DIM)


## Owned is full; open is its colour, capped ones filled by level; a closed block
## is grey; closed and hidden is a question mark.
static func apply_look(hex: IconHex, meta: MetaState, key: String) -> void:
	var upgrade := MetaUpgrades.get_upgrade(key)
	var level := meta.level_of(key)
	var hue := Regions.color_of(upgrade.region)
	if not meta.region_open(upgrade.region):
		if upgrade.hidden:
			hex.set_look(IconHex.LOCKED_COLOR, IconHex.LOCKED_FILL, IconHex.LOCKED_COLOR,
				0.0, Icons.QUESTION)
		else:
			hex.set_look(IconHex.LOCKED_COLOR, IconHex.LOCKED_FILL,
				IconHex.LOCKED_COLOR.darkened(0.5), 0.0, Icons.upgrade(key),
				IconHex.LOCKED_ICON)
	elif upgrade.is_maxed(level):
		hex.set_look(hue, hue.darkened(IconHex.EMPTY_DARKEN),
			hue.darkened(IconHex.FILL_DARKEN), 1.0, Icons.upgrade(key))
	else:
		var affordable := meta.can_afford(key)
		var amount := float(level) / upgrade.max_level if upgrade.is_capped() else 0.0
		hex.set_look(hue.lerp(Color.WHITE, 0.25) if affordable else hue.darkened(0.35),
			hue.darkened(IconHex.EMPTY_DARKEN), hue.darkened(IconHex.FILL_DARKEN), amount,
			Icons.upgrade(key), Color.WHITE if affordable else Color(1.0, 1.0, 1.0, 0.6))


static func level_text(upgrade: MetaUpgrade, level: int) -> String:
	if upgrade.is_unlock():
		return "owned" if level > 0 else "unlock"
	if upgrade.is_capped():
		return "%d/%d" % [level, upgrade.max_level]
	return "lv %d" % level
