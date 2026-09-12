class_name ShopBlock
extends VBoxContainer

## One colour's upgrades: a header, then cards that wrap. A closed block is a dimmed teaser.

signal buy_requested(key: String)

const CARD := preload("res://scenes/ui/UpgradeCard.tscn")
const TEASER_ALPHA := 0.35

var is_open := false

@onready var _icon: TextureRect = $Header/Icon
@onready var _header: Label = $Header/Label
@onready var _cards: HFlowContainer = $Cards


func setup(region: int, open: bool) -> void:
	is_open = open
	var hue := Regions.color_of(region)
	var region_name := Regions.name_of(region)
	_header.text = region_name.to_upper() if open \
		else "%s  —  beat the %s boss to open" % [region_name.to_upper(),
			Regions.name_of(region - 1)]
	_header.add_theme_color_override("font_color", hue)
	_icon.modulate = hue
	modulate.a = 1.0 if open else TEASER_ALPHA

	for key in MetaUpgrades.in_region(region):
		var card: UpgradeCard = CARD.instantiate()
		card.key = key
		_cards.add_child(card)
		card.pressed.connect(buy_requested.emit.bind(key))


func refresh(meta: MetaState) -> void:
	for card in _cards.get_children():
		card.refresh(meta, is_open)
