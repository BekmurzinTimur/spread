class_name AchievementsPage
extends HBoxContainer

## Badges on the left; the last hovered one explained on the right.

const BADGE := preload("res://scenes/ui/IconHex.tscn")

const COLOR_TEXT := Color("dfe5ee")
const COLOR_GOOD := Color("6fcf7f")
const COLOR_DIM := Color("7b8290")

var _meta: MetaState
var _new: Array[String] = []
var _shown := ""
var _hovered := ""

@onready var _badges: HFlowContainer = %Badges
@onready var _detail_badge: IconHex = %DetailBadge
@onready var _name: Label = %AchievementName
@onready var _status: Label = %Status
@onready var _description: Label = %AchievementDescription
@onready var _rate_row: Control = %RateRow
@onready var _rate_label: Label = %RateLabel
@onready var _value_row: Control = %ValueRow
@onready var _value_label: Label = %ValueLabel
@onready var _progress_row: Control = %ProgressRow
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _progress_label: Label = %ProgressLabel
@onready var _totals: Label = %Totals


func _ready() -> void:
	%RateIcon.texture = Icons.buff(NodeCatalog.PULSE)
	%ValueIcon.texture = Icons.buff(NodeCatalog.YIELD)


func build(meta: MetaState, new_keys: Array[String]) -> void:
	_meta = meta
	_new = new_keys
	_hovered = ""
	for badge in _badges.get_children():
		_badges.remove_child(badge)
		badge.queue_free()
	for key in Achievements.all():
		var badge: IconHex = BADGE.instantiate()
		_badges.add_child(badge)
		badge.mouse_entered.connect(_on_hover.bind(key))
		badge.mouse_exited.connect(_on_unhover.bind(key))
	if not _new.is_empty():
		_shown = _new[0]
	elif not Achievements.has(_shown):
		_shown = Achievements.all()[0]
	_refresh()


func _process(_delta: float) -> void:
	if visible and _meta != null:
		_refresh()


func _on_hover(key: String) -> void:
	_hovered = key
	_shown = key


func _on_unhover(key: String) -> void:
	if _hovered == key:
		_hovered = ""


func _refresh() -> void:
	var keys := Achievements.all()
	for i in _badges.get_child_count():
		var key := keys[i]
		_badge_look(_badges.get_child(i), _meta, key, _new.has(key), key == _hovered)

	var a := Achievements.get_achievement(_shown)
	if a == null:
		return
	var held := _meta.has_achievement(_shown)
	var secret := a.hidden and not held
	_badge_look(_detail_badge, _meta, _shown, _new.has(_shown), false)

	_name.text = "???" if secret else a.display_name
	_name.add_theme_color_override("font_color",
		Regions.color_of(a.region) if held else COLOR_TEXT)
	_status.text = "UNLOCKED" if held else "LOCKED"
	_status.add_theme_color_override("font_color", COLOR_GOOD if held else COLOR_DIM)
	_description.text = "Keep playing to discover it." if secret else a.description

	_rate_row.visible = not secret and a.rate_more_percent != 0
	_rate_label.text = "%+d%% emission rate" % a.rate_more_percent
	_value_row.visible = not secret and a.value_more_percent != 0
	_value_label.text = "%+d%% orb value" % a.value_more_percent

	_progress_row.visible = not held and not secret and a.target > 1
	_progress_bar.max_value = a.target
	_progress_bar.value = Achievements.progress(_meta, _shown)
	_progress_label.text = "%s / %s" % [Format.number(_progress_bar.value),
		Format.number(a.target)]

	_totals.text = "All achievements, multiplied:\nx%s emission rate · x%s orb value" % [
		String.num(Achievements.rate_multiplier(_meta), 2),
		String.num(Achievements.value_multiplier(_meta), 2)]


## Unlocked is its colour, pulsing while new; locked is grey with progress as the
## fill; hidden and locked is a question mark.
static func _badge_look(hex: IconHex, meta: MetaState, key: String, is_new: bool,
		hovered: bool) -> void:
	var a := Achievements.get_achievement(key)
	var hue := Regions.color_of(a.region)
	var outline := IconHex.LOCKED_COLOR
	if meta.has_achievement(key):
		outline = hue.lerp(Color.WHITE, 0.2 + 0.6 * IconHex.pulse()) if is_new else hue
		hex.set_look(outline, hue.darkened(IconHex.EMPTY_DARKEN),
			hue.darkened(IconHex.FILL_DARKEN), 1.0, Icons.achievement(key))
	elif a.hidden:
		hex.set_look(outline, IconHex.LOCKED_FILL, IconHex.LOCKED_COLOR, 0.0, Icons.QUESTION)
	else:
		var amount := float(Achievements.progress(meta, key)) / float(maxi(1, a.target))
		hex.set_look(outline, IconHex.LOCKED_FILL, hue.darkened(0.7), amount,
			Icons.achievement(key), IconHex.LOCKED_ICON)
	if hovered:
		hex.outline_color = outline.lerp(Color.WHITE, 0.5)
