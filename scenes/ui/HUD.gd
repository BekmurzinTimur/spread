extends Control

## Four readouts: currency, the ram pool, region progress, the buff hexes.
## Tooltips carry the rest. Layout lives in HUD.tscn.

const COLOR_TEXT := Color("dfe5ee")
const COLOR_GOOD := Color("6fcf7f")

const TOOLTIP_OFFSET := Vector2(28.0, -28.0)

var main: Node

## Cell under the cursor, fed by Main. -1 for none.
var hovered_cell: int = -1

var _bar_fill: StyleBoxFlat

@onready var _earned: Label = %Earned
@onready var _banked: Label = %Banked
@onready var _end_run: Button = %EndRun
@onready var _ram: RamMeter = %RamMeter
@onready var _ram_icon: TextureRect = %RamIcon
@onready var _ram_damage: Label = %RamDamage
@onready var _buffs: Container = %Buffs
@onready var _region_icon: TextureRect = %RegionIcon
@onready var _region_label: Label = %RegionLabel
@onready var _region_bar: ProgressBar = %RegionBar
@onready var _tooltip: PanelContainer = %Tooltip
@onready var _tooltip_label: Label = %TooltipLabel


func _ready() -> void:
	_end_run.pressed.connect(func() -> void: main.end_run())
	# Own copy, so tinting it doesn't tint the theme.
	_bar_fill = _region_bar.get_theme_stylebox("fill").duplicate()
	_region_bar.add_theme_stylebox_override("fill", _bar_fill)
	for hex in _buffs.get_children():
		if hex is BuffHex:
			hex.pressed.connect(func(id: String) -> void: main.activate_skill(id))


func _process(_delta: float) -> void:
	var world: World = main.world if main != null else null
	if world == null:
		return
	_update_currency(world)
	_update_ram(world)
	_update_region(world)
	for hex in _buffs.get_children():
		if hex is BuffHex:
			hex.refresh(world, main.ram_armed and hex.buff_id == NodeCatalog.YIELD)
	_update_tooltip(world)


func _update_currency(world: World) -> void:
	_earned.text = Format.number(world.earned)
	_banked.text = "%s banked" % Format.number(main.meta.banked)

	# Nothing emits and nothing else can be mined: the run is over, so the button says so.
	var stalled := world.frontier().is_empty() and world.live_orb_count() == 0
	_end_run.text = "%s   ◆ %s" % ["RUN OVER — CLAIM" if stalled else "END RUN",
		Format.number(world.earned)]
	var color := COLOR_GOOD if stalled else COLOR_TEXT
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_end_run.add_theme_color_override(state, color)


func _update_ram(world: World) -> void:
	_ram.damage = world.ram_damage()
	_ram.modulate = Color.WHITE if world.ram_unlocked() else Color(1.0, 1.0, 1.0, 0.35)
	var color := _ram.current_color()
	_ram_icon.modulate = color
	_ram_damage.text = Format.number(_ram.damage)
	_ram_damage.add_theme_color_override("font_color", color)


func _update_region(world: World) -> void:
	var region := world.current_region()
	var progress := world.region_progress(region)
	var hue := Regions.color_of(region)
	_region_bar.max_value = maxi(1, progress[1])
	_region_bar.value = progress[0]
	_bar_fill.bg_color = hue
	_region_icon.modulate = hue
	_region_label.text = "%s  %d/%d" % [Regions.name_of(region), progress[0], progress[1]]


# --- Tooltips -----------------------------------------------------------


func _update_tooltip(world: World) -> void:
	var text := ""
	var control := get_viewport().gui_get_hovered_control()
	if control == null:
		if hovered_cell >= 0:
			text = _cell_tooltip(world, hovered_cell)
	elif control == _ram:
		if not world.ram_unlocked():
			text = "Ram — locked\nBuy Ram in the red block."
		else:
			text = "Ram — %s damage\nBanks %d%% of every cell you mine.\nClick the Power hex when ready, then click any cell in an open region.\nUnspent damage is kept." \
				% [Format.number(world.ram_damage()), world.ram_share()]
	elif control is HexPanel and control.get_parent() is BuffHex:
		text = control.get_parent().tooltip()

	_tooltip.visible = not text.is_empty()
	if text.is_empty():
		return
	_tooltip_label.text = text
	_tooltip.size = _tooltip.get_combined_minimum_size()
	var at := get_viewport().get_mouse_position() + TOOLTIP_OFFSET \
		- Vector2(0.0, _tooltip.size.y)
	_tooltip.position = at.clamp(Vector2.ZERO, size - _tooltip.size)


## What a cell is worth, what it has taken, and what is buried in it if you are
## close enough to read the name.
func _cell_tooltip(world: World, cell_id: int) -> String:
	var cell: GraphCell = world.graph.cells[cell_id]
	var visibility := world.visibility_of(cell_id)
	if visibility == 0 and not cell.is_mined:
		return ""

	var lines := "%s region — %d hops out" % [Regions.name_of(cell.region), cell.hops]
	if cell.is_boss:
		lines = "%s boss — beat it to open %s" % [Regions.name_of(cell.region),
			Regions.name_of(cell.region + 1)]
	if cell.is_mined:
		lines += "\nMined for %s" % Format.number(cell.cost)
		lines += "\nGenerator — emits on the frontier" if cell.is_generator \
			else "\nDud — inert ground, never emits"
	else:
		lines += "\n%s / %s" % [Format.number(cell.progress),
			Format.number(cell.cost)]
		if not world.is_mineable(cell):
			lines += "\nRegion locked — beat the %s boss" % Regions.name_of(cell.region - 1)

	if cell.has_node():
		if visibility >= 2 or cell.is_mined:
			var type := NodeCatalog.get_type(cell.node_id)
			lines += "\n%s +%s" % [type.display_name,
				Format.number(cell.node_grant())]
		else:
			lines += "\nSomething buried here"
	return lines
