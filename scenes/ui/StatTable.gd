class_name StatTable
extends PanelContainer

## Every stat the shop moves, as a run starts. Given a preview, the stats it
## changes show their next value.

const COLOR_TEXT := Color("dfe5ee")
const COLOR_GOOD := Color("6fcf7f")
const COLOR_DIM := Color("7b8290")
const FONT_SIZE := 18
const ICON_SIZE := 22
const LOCKED := "locked"

@onready var _grid: GridContainer = %Grid

## [value Label, next Label] per row.
var _rows: Array = []


func show_stats(current: World, preview: World) -> void:
	var now := rows(current)
	var next := rows(preview) if preview != null else now
	if _rows.size() != now.size():
		_build(now)
	for i in now.size():
		var value: Label = _rows[i][0]
		var arrow: Label = _rows[i][1]
		value.text = now[i][2]
		value.add_theme_color_override("font_color",
			COLOR_DIM if now[i][2] == LOCKED else COLOR_TEXT)
		arrow.text = "→ %s" % next[i][2] if next[i][2] != now[i][2] else ""


## `[icon, name, value]` per stat.
static func rows(world: World) -> Array:
	var meta := world.meta()
	var crit := world.skill_unlocked(NodeCatalog.CRIT)
	var bounce := world.skill_unlocked(NodeCatalog.BOUNCE)
	var splash := world.skill_unlocked(NodeCatalog.SPLASH)
	return [
		[Icons.buff(NodeCatalog.YIELD), "Orb value",
			Format.number(world.effective_orb_value())],
		[Icons.buff(NodeCatalog.PULSE), "Emits/s per generator",
			"%.2f" % (float(World.TICK_HZ * world.effective_rate()) / World.EMIT_CHARGE)],
		[Icons.upgrade(MetaUpgrades.GENERATOR_CHANCE), "Generator chance",
			Format.chance(world.generator_chance())],
		[Icons.buff(NodeCatalog.PULSE), "Speed",
			"+%d%%" % (world.buffs.level_of(NodeCatalog.PULSE) * NodeCatalog.PULSE_PER_LEVEL)
			if world.skill_unlocked(NodeCatalog.PULSE) else LOCKED],
		[Icons.buff(NodeCatalog.CRIT), "Crit chance · mult",
			"%s · x%s" % [Format.chance(world.effective_crit_chance()),
			String.num(world.effective_crit_multiplier(), 2)] if crit else LOCKED],
		[Icons.buff(NodeCatalog.BOUNCE), "Bounces · kept",
			"%d · %d%%" % [world.effective_bounces(),
			world.effective_bounce_keep_percent()] if bounce else LOCKED],
		[Icons.upgrade(MetaUpgrades.BOUNCE_SKILL), "Bounce skill",
			"+%d" % (World.BOUNCE_SKILL_BASE + meta.level_of(MetaUpgrades.BOUNCE_SKILL))
			if bounce else LOCKED],
		[Icons.buff(NodeCatalog.SPLASH), "Splash chance · hit",
			"%s · %d%%" % [Format.chance(world.effective_splash_chance()),
			world.effective_splash_percent()] if splash else LOCKED],
		[Icons.upgrade(MetaUpgrades.SPLASH_BOUNCE), "Bounces splash",
			("Yes" if world.bounces_splash() else "No") if splash and bounce else LOCKED],
		[Icons.upgrade(MetaUpgrades.OVERCHARGE), "Overcharge /gen",
			"+%d%%" % (meta.level_of(MetaUpgrades.OVERCHARGE) * World.OVERCHARGE_PER_LEVEL)],
		[Icons.RAM, "Ram bank · damage",
			"%d%% · +%d%%" % [world.ram_share(), world.ram_damage_bonus()]
			if world.ram_unlocked() else LOCKED],
		[Icons.RAM, "Ram splash · bounce · bounce splash",
			" · ".join([_yes_no(world.ram_splashes()), _yes_no(world.ram_bounces()),
			_yes_no(world.ram_bounces_splash())]) if world.ram_unlocked() else LOCKED],
		[Icons.upgrade(MetaUpgrades.BOUNTY), "Bounty", "+%d%%" % world.bounty_percent()],
	]


static func _yes_no(value: bool) -> String:
	return "Yes" if value else "No"


func _build(now: Array) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_rows.clear()
	for row in now:
		var icon := TextureRect.new()
		icon.texture = row[0]
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate = COLOR_DIM
		_grid.add_child(icon)
		var label := _label(row[1], COLOR_DIM)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(label)
		var value := _label("", COLOR_TEXT)
		var next := _label("", COLOR_GOOD)
		_grid.add_child(value)
		_grid.add_child(next)
		_rows.append([value, next])


static func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label
