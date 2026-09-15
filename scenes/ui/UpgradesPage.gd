class_name UpgradesPage
extends HBoxContainer

## Upgrades grouped by type on the left, the last hovered one explained in the
## middle, and the stats on the right with what that purchase would change.

signal buy_requested(key: String, count: int)

const BADGE := preload("res://scenes/ui/UpgradeBadge.tscn")

const COLOR_TEXT := Color("dfe5ee")
const COLOR_GOOD := Color("6fcf7f")
const COLOR_BAD := Color("c05a55")
const COLOR_DIM := Color("7b8290")

var main: Node

var _badges: Array[UpgradeBadge] = []
var _shown := ""
var _hovered := ""
## Hovered key, preview count and meta version the stat table last showed.
var _stats_for := ""

@onready var _scroll: ScrollContainer = %Scroll
@onready var _groups: VBoxContainer = %Groups
@onready var _detail_hex: IconHex = %DetailHex
@onready var _name: Label = %UpgradeName
@onready var _block: Label = %Block
@onready var _description: Label = %UpgradeDescription
@onready var _level: Label = %UpgradeLevel
@onready var _buy: Label = %Buy
@onready var _price_icon: TextureRect = %PriceIcon
@onready var _price: Label = %Price
@onready var _stats: StatTable = %Stats


func build(p_main: Node) -> void:
	main = p_main
	var scroll := _scroll.scroll_vertical
	for child in _groups.get_children():
		_groups.remove_child(child)
		child.queue_free()
	_badges.clear()
	_hovered = ""
	_stats_for = ""

	for group in MetaUpgrades.GROUP_COUNT:
		var keys := MetaUpgrades.in_group(group)
		if not keys.is_empty():
			_groups.add_child(_group_box(group, keys))
	if not MetaUpgrades.has(_shown):
		_shown = _badges[0].key
	_refresh()

	# The new content has to lay out before the old scroll fits it.
	await get_tree().process_frame
	_scroll.scroll_vertical = scroll


func _group_box(group: int, keys: Array[String]) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.texture = Icons.group(group)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = COLOR_DIM
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon)
	var label := Label.new()
	label.text = MetaUpgrades.GROUP_NAMES[group].to_upper()
	label.theme_type_variation = &"DimLabel"
	label.add_theme_font_size_override("font_size", 22)
	header.add_child(label)
	box.add_child(header)

	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 6)
	for key in keys:
		var badge: UpgradeBadge = BADGE.instantiate()
		badge.key = key
		flow.add_child(badge)
		badge.hovered.connect(_on_hover)
		badge.unhovered.connect(_on_unhover)
		badge.buy_requested.connect(buy_requested.emit)
		_badges.append(badge)
	box.add_child(flow)
	return box


func _process(_delta: float) -> void:
	if visible and main != null and not _badges.is_empty():
		_refresh()


func _on_hover(key: String) -> void:
	_hovered = key
	_shown = key


func _on_unhover(key: String) -> void:
	if _hovered == key:
		_hovered = ""


func _refresh() -> void:
	var meta: MetaState = main.meta
	for badge in _badges:
		badge.refresh(meta, badge.key == _hovered)
	var count := _preview_count(meta)
	_refresh_detail(meta, count)
	_refresh_stats(meta, count)


## Levels the hovered purchase would add: what a click buys now, at least one so
## an unaffordable or closed upgrade still hints what it does.
func _preview_count(meta: MetaState) -> int:
	var upgrade := MetaUpgrades.get_upgrade(_shown)
	var level := meta.level_of(_shown)
	if upgrade.is_maxed(level) or (upgrade.hidden and not meta.region_open(upgrade.region)):
		return 0
	var room := UpgradeBadge.held_count()
	if upgrade.is_capped():
		room = mini(room, upgrade.max_level - level)
	return clampi(meta.quote(_shown, room)[0], 1, room)


func _refresh_detail(meta: MetaState, count: int) -> void:
	var upgrade := MetaUpgrades.get_upgrade(_shown)
	var level := meta.level_of(_shown)
	var is_open := meta.region_open(upgrade.region)
	var secret := upgrade.hidden and not is_open
	var hue := Regions.color_of(upgrade.region)

	UpgradeBadge.apply_look(_detail_hex, meta, _shown)
	_name.text = "???" if secret else upgrade.display_name
	_name.add_theme_color_override("font_color", hue if is_open else COLOR_TEXT)
	_block.text = Regions.name_of(upgrade.region).to_upper() if is_open \
		else "Beat the %s boss to open" % Regions.name_of(upgrade.region - 1).to_lower()
	_block.add_theme_color_override("font_color", hue if is_open else COLOR_DIM)
	_description.text = "" if secret else upgrade.description

	if secret:
		_level.text = ""
	elif count > 0 and not upgrade.is_unlock():
		_level.text = "%s  →  %s" % [UpgradeBadge.level_text(upgrade, level),
			UpgradeBadge.level_text(upgrade, level + count)]
	else:
		_level.text = UpgradeBadge.level_text(upgrade, level)

	var maxed := upgrade.is_maxed(level)
	_price_icon.visible = is_open and not maxed
	_price.visible = _price_icon.visible
	if maxed:
		_set_buy("OWNED" if upgrade.is_unlock() else "MAX", COLOR_GOOD)
	elif not is_open:
		_set_buy("LOCKED", COLOR_DIM)
	else:
		var want := UpgradeBadge.held_count()
		if upgrade.is_capped():
			want = mini(want, upgrade.max_level - level)
		var quote := meta.quote(_shown, want)
		var levels: int = quote[0]
		_price.text = Format.number(quote[1])
		_price.add_theme_color_override("font_color", COLOR_GOOD if levels > 0 else COLOR_BAD)
		if levels == 0:
			_set_buy("BUY" if want == 1 else "BUY x%d" % want, COLOR_BAD)
		elif levels < want:
			_set_buy("BUY x%d of %d" % [levels, want], COLOR_TEXT)
		else:
			_set_buy("BUY" if levels == 1 else "BUY x%d" % levels, COLOR_TEXT)


func _set_buy(text: String, color: Color) -> void:
	_buy.text = text
	_buy.add_theme_color_override("font_color", color)


## A probe World over the waiting board, with the preview levels added. Rebuilt
## only when what it shows changes.
func _refresh_stats(meta: MetaState, count: int) -> void:
	var world: World = main.world
	if world == null:
		return
	var key := "%s|%d|%d" % [_shown, count, meta.version]
	if key == _stats_for:
		return
	_stats_for = key
	var preview: World = null
	if count > 0:
		var copy := meta.copy()
		copy.levels[_shown] = meta.level_of(_shown) + count
		preview = World.new(world.graph, copy, world.run_seed)
	_stats.show_stats(world, preview)
