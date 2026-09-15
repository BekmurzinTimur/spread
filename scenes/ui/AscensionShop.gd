extends Control

## The project's one modal, and the whole between-runs phase: the wallet, Start run,
## and two tabs — upgrades grouped by type, and achievements.

const COLOR_TEXT := Color("dfe5ee")
const COLOR_DIM := Color("7b8290")
const COLOR_BAD := Color("c05a55")

enum Tab { UPGRADES, ACHIEVEMENTS }

var main: Node

## Reset wipes everything, so it takes two clicks.
var _reset_armed := false
var _tab := Tab.UPGRADES

@onready var _banked: Label = %Banked
@onready var _last_run: Label = %LastRun
@onready var _start: Button = %StartRun
@onready var _upgrades_tab: Button = %UpgradesTab
@onready var _achievements_tab: Button = %AchievementsTab
@onready var _upgrades: UpgradesPage = %Upgrades
@onready var _achievements: AchievementsPage = %Achievements
@onready var _reset: Button = %Reset


func _ready() -> void:
	visible = false
	_start.pressed.connect(func() -> void: main.start_run())
	_reset.pressed.connect(_on_reset_pressed)
	_reset.mouse_exited.connect(_set_reset_armed.bind(false))
	_upgrades.buy_requested.connect(_buy)
	var group := ButtonGroup.new()
	_upgrades_tab.button_group = group
	_achievements_tab.button_group = group
	_upgrades_tab.icon = Icons.UPGRADES_TAB
	_achievements_tab.icon = Icons.ACHIEVEMENTS_TAB
	_upgrades_tab.pressed.connect(_show_tab.bind(Tab.UPGRADES))
	_achievements_tab.pressed.connect(_show_tab.bind(Tab.ACHIEVEMENTS))


## Opens on achievements when the last run earned one.
func open() -> void:
	visible = true
	_rebuild()
	_show_tab(Tab.ACHIEVEMENTS if not main.new_achievements.is_empty() else _tab)


func close() -> void:
	visible = false
	_set_reset_armed(false)


func _show_tab(tab: Tab) -> void:
	_tab = tab
	_upgrades.visible = tab == Tab.UPGRADES
	_achievements.visible = tab == Tab.ACHIEVEMENTS
	for pair in [[_upgrades_tab, Tab.UPGRADES], [_achievements_tab, Tab.ACHIEVEMENTS]]:
		var button: Button = pair[0]
		button.set_pressed_no_signal(pair[1] == tab)
		var color := COLOR_TEXT if pair[1] == tab else COLOR_DIM
		for state in ["font_color", "font_hover_color", "font_pressed_color",
				"icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
			button.add_theme_color_override(state, color)


func _rebuild() -> void:
	_upgrades.build(main)
	_achievements.build(main.meta, main.new_achievements)
	_refresh()


func _refresh() -> void:
	var meta: MetaState = main.meta
	_banked.text = "%s banked" % Format.number(meta.banked)
	_last_run.text = "+%s from that run" % Format.number(main.last_run_banked)
	_achievements_tab.text = "ACHIEVEMENTS  %d/%d" % [Achievements.held_count(meta),
		Achievements.all().size()]


func _buy(key: String, count: int) -> void:
	if main.buy_upgrade(key, count):
		_refresh()


func _on_reset_pressed() -> void:
	if not _reset_armed:
		_set_reset_armed(true)
		return
	_set_reset_armed(false)
	main.reset_progress()
	_rebuild()


func _set_reset_armed(armed: bool) -> void:
	_reset_armed = armed
	_reset.text = "RESET EVERYTHING?  click again" if armed else "RESET PROGRESS"
	var color := COLOR_BAD if armed else COLOR_DIM
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_reset.add_theme_color_override(state, color)
