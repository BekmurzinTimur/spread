class_name UpgradeCard
extends Button

## One shop purchase. The shop decides what pressing it means.

const COLOR_TEXT := Color("dfe5ee")
const COLOR_GOOD := Color("6fcf7f")
const COLOR_BAD := Color("c05a55")

## Background once the upgrade can't go higher.
@export var owned_style: StyleBox

var key := ""

@onready var _icon: TextureRect = %Icon
@onready var _level: Label = %Level
@onready var _name: Label = %Name
@onready var _description: Label = %Description
@onready var _price_icon: TextureRect = %PriceIcon
@onready var _price: Label = %PriceLabel


func refresh(meta: MetaState, is_open: bool) -> void:
	var upgrade := MetaUpgrades.get_upgrade(key)
	var level := meta.level_of(key)
	var maxed := upgrade.is_maxed(level)

	_icon.texture = Icons.upgrade(key)
	_icon.modulate = COLOR_GOOD if maxed else COLOR_TEXT
	_name.text = upgrade.display_name
	_description.text = upgrade.description
	_level.visible = not upgrade.is_unlock()
	_level.text = "%d / %d" % [level, upgrade.max_level] if upgrade.is_capped() \
		else "lv %d" % level

	disabled = not is_open or maxed
	for state in ["normal", "hover", "pressed", "disabled"]:
		if maxed:
			add_theme_stylebox_override(state, owned_style)
		else:
			remove_theme_stylebox_override(state)

	_price.visible = is_open
	_price_icon.visible = is_open and not maxed
	if maxed:
		_price.text = "owned" if upgrade.is_unlock() else "max"
		_price.add_theme_color_override("font_color", COLOR_GOOD)
	else:
		_price.text = Format.number(meta.next_cost(key))
		_price.add_theme_color_override("font_color",
			COLOR_GOOD if meta.can_afford(key) else COLOR_BAD)
