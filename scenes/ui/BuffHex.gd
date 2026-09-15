class_name BuffHex
extends VBoxContainer

## One buff: its final stat, a hex in the colour of the region that unlocks it, and
## its level. A locked buff is a grey question mark. The hex is also the buff's
## skill: its background fills with readiness, and a click activates it.

signal pressed(buff_id: String)

const LOCKED_COLOR := Color(0.34, 0.37, 0.43)
const COOLDOWN_ICON := Color(1.0, 1.0, 1.0, 0.35)

@export_enum("yield", "pulse", "crit", "bounce", "splash") var buff_id: String = "yield"

## How much darker the fill is than the outline, so the white icon stays readable.
@export_range(0.0, 1.0) var fill_darken := 0.55

## Darkening of the part of the hex readiness has not filled yet.
@export_range(0.0, 1.0) var empty_darken := 0.85

@onready var _stat: Label = $Stat
@onready var _hex: HexPanel = $Hex
@onready var _icon: TextureRect = $Hex/Icon
@onready var _level: Label = $Level

var _locked := true
var _tooltip := ""


func _ready() -> void:
	_hex.gui_input.connect(_on_hex_input)


func _on_hex_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(buff_id)


## `armed` is true while this hex's skill waits for a target.
func refresh(world: World, armed: bool = false) -> void:
	var type := NodeCatalog.get_type(buff_id)
	var meta := world.meta()
	_locked = meta != null and not meta.is_unlocked(type.unlock_key)
	if _locked:
		_set_look(LOCKED_COLOR, LOCKED_COLOR.darkened(fill_darken), 0.0, Icons.QUESTION)
		_icon.modulate = Color.WHITE
		_stat.text = ""
		_level.text = ""
		_tooltip = ""
		return

	var hue := Regions.color_of(unlock_region(type))
	var skills := world.skills
	var skill_on := world.skill_unlocked(buff_id)
	var outline := hue
	if armed or skills.is_active(buff_id):
		outline = Color.WHITE
	elif skill_on and skills.is_ready(buff_id):
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006)
		outline = hue.lerp(Color.WHITE, 0.2 + 0.5 * pulse)
	var fill := float(skills.readiness_of(buff_id)) / float(SkillState.FULL) \
		if skill_on else 0.0
	_set_look(outline, hue, fill, Icons.buff(buff_id))
	_icon.modulate = COOLDOWN_ICON if skills.cooldown_of(buff_id) > 0 else Color.WHITE

	var level := world.buffs.level_of(buff_id)
	_stat.text = _stat_text(world)
	_level.text = "lvl %s" % Format.number(level)
	_tooltip = "%s — level %d\n%s\nFound in the ground, and stacks all run.\n%s" \
		% [type.display_name, level, _effect(world, maxi(level, 1)), _skill_line(world)]


## Empty while locked.
func tooltip() -> String:
	return _tooltip


## Top centre of the stat, where level gains rise from.
func gain_anchor() -> Vector2:
	return _stat.global_position + Vector2(_stat.size.x * 0.5, 0.0)


func gain_color() -> Color:
	return Regions.color_of(unlock_region(NodeCatalog.get_type(buff_id))).lerp(Color.WHITE, 0.3)


## The region whose shop block sells the unlock. Always-unlocked types are red.
static func unlock_region(type: NodeType) -> int:
	if type.unlock_key.is_empty():
		return Regions.RED
	return MetaUpgrades.get_upgrade(type.unlock_key).region


func _set_look(outline: Color, hue: Color, readiness: float, texture: Texture2D) -> void:
	_hex.outline_color = outline
	_hex.fill_color = hue.darkened(empty_darken)
	_hex.readiness_color = hue.darkened(fill_darken)
	_hex.readiness = readiness
	_icon.texture = texture


func _skill_line(world: World) -> String:
	var seconds := SkillState.ACTIVE_TICKS / World.TICK_HZ
	var effect := "no effect yet"
	match buff_id:
		NodeCatalog.YIELD:
			effect = "throw the ram"
		NodeCatalog.PULSE:
			effect = "x2 emission rate for %ds" % seconds
		NodeCatalog.CRIT:
			effect = "100%% crit for %ds" % seconds
		NodeCatalog.BOUNCE:
			effect = "+%d bounces, no loss for %ds" % [World.BOUNCE_SKILL_BASE
				+ world.meta().level_of(MetaUpgrades.BOUNCE_SKILL), seconds]
	if not world.skill_unlocked(buff_id):
		return "Skill: %s — buy Ram in red" % effect
	var skills := world.skills
	var status := "%d%% ready" % skills.readiness_of(buff_id)
	if skills.cooldown_of(buff_id) > 0:
		status = "cooldown %ds" % ceili(float(skills.cooldown_of(buff_id)) / World.TICK_HZ)
	elif skills.is_ready(buff_id):
		status = "ready — click"
	return "Skill: %s (%s)" % [effect, status]


func _stat_text(world: World) -> String:
	match buff_id:
		NodeCatalog.YIELD:
			return Format.number(world.effective_orb_value())
		NodeCatalog.PULSE:
			return "%.1f/s" % (float(World.TICK_HZ * world.effective_rate()) / World.EMIT_CHARGE)
		NodeCatalog.CRIT:
			return "%s x%s" % [Format.chance(world.effective_crit_chance()),
				String.num(world.effective_crit_multiplier(), 2)]
		NodeCatalog.BOUNCE:
			return "%d · %d%%" % [world.effective_bounces(),
				world.effective_bounce_keep_percent()]
		NodeCatalog.SPLASH:
			return "%s · %d%%" % [Format.chance(world.effective_splash_chance()),
				world.effective_splash_percent()]
	return ""


func _effect(world: World, level: int) -> String:
	match buff_id:
		NodeCatalog.YIELD:
			return "+%s orb value (now %s)" % [
				Format.number(level * NodeCatalog.YIELD_PER_LEVEL),
				Format.number(world.effective_orb_value())]
		NodeCatalog.PULSE:
			return "+%d%% emission rate" % (level * NodeCatalog.PULSE_PER_LEVEL)
		NodeCatalog.CRIT:
			return "%s chance of x%s" % [
				Format.chance(NodeCatalog.crit_chance(level)),
				String.num(world.effective_crit_multiplier(), 2)]
		NodeCatalog.BOUNCE:
			return "+%d bounces, each keeps %d%%" % [level,
				world.effective_bounce_keep_percent()]
		NodeCatalog.SPLASH:
			return "%s chance to splash %d%%" % [
				Format.chance(level * NodeCatalog.SPLASH_PER_LEVEL),
				world.effective_splash_percent()]
	return ""
