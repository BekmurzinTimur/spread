extends Control

## The project's one modal, and the whole between-runs phase: the wallet, one
## upgrade block per colour, and Start run.
##
## Open blocks sell; the next closed one is shown dimmed as a teaser; the rest stay hidden.

const BLOCK := preload("res://scenes/ui/ShopBlock.tscn")

const COLOR_DIM := Color("7b8290")
const COLOR_BAD := Color("c05a55")

var main: Node

## Reset wipes everything, so it takes two clicks.
var _reset_armed := false

@onready var _banked: Label = %Banked
@onready var _last_run: Label = %LastRun
@onready var _start: Button = %StartRun
@onready var _scroll: ScrollContainer = %Scroll
@onready var _blocks: VBoxContainer = %Blocks
@onready var _reset: Button = %Reset


func _ready() -> void:
	visible = false
	_start.pressed.connect(func() -> void: main.start_run())
	_reset.pressed.connect(_on_reset_pressed)
	_reset.mouse_exited.connect(_set_reset_armed.bind(false))


func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	visible = false
	_set_reset_armed(false)


## Blocks in order, stopping after the first closed one.
func _rebuild() -> void:
	var meta: MetaState = main.meta
	var scroll := _scroll.scroll_vertical
	for block in _blocks.get_children():
		_blocks.remove_child(block)
		block.queue_free()

	for region in Regions.COUNT:
		if MetaUpgrades.in_region(region).is_empty():
			continue
		var is_open := meta.region_open(region)
		var block: ShopBlock = BLOCK.instantiate()
		_blocks.add_child(block)
		block.setup(region, is_open)
		block.buy_requested.connect(_buy)
		if not is_open:
			break
	_refresh()

	# The new content has to lay out before the old scroll fits it.
	await get_tree().process_frame
	_scroll.scroll_vertical = scroll


func _refresh() -> void:
	var meta: MetaState = main.meta
	_banked.text = "%s banked" % Format.number(meta.banked)
	_last_run.text = "+%s from that run" % Format.number(main.last_run_banked)
	for block in _blocks.get_children():
		block.refresh(meta)


func _buy(key: String) -> void:
	if main.buy_upgrade(key):
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
