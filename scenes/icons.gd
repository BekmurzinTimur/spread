class_name Icons

## Every glyph the view draws, and the one way to draw it. White art, tinted on draw.

const CURRENCY := preload("res://assets/cut-diamond.svg")
const RAM := preload("res://assets/meteor-impact.svg")
const DUD := preload("res://assets/disabled.svg")
const REGION := preload("res://assets/mining.svg")
const ORB := preload("res://assets/ball-glow.svg")
const LOCK := preload("res://assets/padlock.svg")
const END_RUN := preload("res://assets/exit-door.svg")
const START_RUN := preload("res://assets/fast-arrow.svg")
const RESET := preload("res://assets/anticlockwise-rotation.svg")
const QUESTION := preload("res://assets/question.svg")
const BOSS := preload("res://assets/boss.svg")
const ENEMY := preload("res://assets/enemy.svg")
const SOLDIER := preload("res://assets/soldier.svg")
const UPGRADES_TAB := preload("res://assets/upgrade.svg")
const ACHIEVEMENTS_TAB := preload("res://assets/glowing-artifact.svg")

const BUFFS := {
	NodeCatalog.YIELD: preload("res://assets/power-lightning.svg"),
	NodeCatalog.PULSE: preload("res://assets/speedometer.svg"),
	NodeCatalog.CRIT: preload("res://assets/targeting.svg"),
	NodeCatalog.BOUNCE: preload("res://assets/teleport.svg"),
	NodeCatalog.SPLASH: preload("res://assets/water-splash.svg"),
}

const UPGRADES := {
	MetaUpgrades.GENERATOR_CHANCE: DUD,
	MetaUpgrades.RAM_UNLOCK: RAM,
	MetaUpgrades.RAM_POWER: RAM,
	MetaUpgrades.VISION: preload("res://assets/eye-target.svg"),
	MetaUpgrades.CRIT_MULTIPLIER: preload("res://assets/striking-diamonds.svg"),
	MetaUpgrades.SPLASH_STRENGTH: preload("res://assets/burst-blob.svg"),
	MetaUpgrades.SPLASH_BOUNCE: preload("res://assets/distribute.svg"),
	MetaUpgrades.BOUNCE_STRENGTH: preload("res://assets/amplify.svg"),
	MetaUpgrades.BOUNCE_SKILL: preload("res://assets/teleport.svg"),
	MetaUpgrades.OVERCHARGE: preload("res://assets/overdrive.svg"),
	MetaUpgrades.ORB_MULTIPLIER: preload("res://assets/upgrade.svg"),
	MetaUpgrades.RAM_CHARGE: preload("res://assets/energy-tank.svg"),
	MetaUpgrades.RAM_SPLASH: preload("res://assets/water-splash.svg"),
	MetaUpgrades.RAM_BOUNCE: preload("res://assets/teleport.svg"),
	MetaUpgrades.RAM_SPLASH_BOUNCE: preload("res://assets/distribute.svg"),
	MetaUpgrades.BOUNTY: preload("res://assets/two-coins.svg"),
}


const GROUPS := {
	MetaUpgrades.GROUP_POWER: preload("res://assets/power-lightning.svg"),
	MetaUpgrades.GROUP_SPEED: preload("res://assets/speedometer.svg"),
	MetaUpgrades.GROUP_CRIT: preload("res://assets/targeting.svg"),
	MetaUpgrades.GROUP_BOUNCE: preload("res://assets/teleport.svg"),
	MetaUpgrades.GROUP_SPLASH: preload("res://assets/water-splash.svg"),
	MetaUpgrades.GROUP_RAM: RAM,
	MetaUpgrades.GROUP_ECONOMY: CURRENCY,
}


static func group(g: int) -> Texture2D:
	return GROUPS.get(g)


static func buff(id: String) -> Texture2D:
	return BUFFS.get(id)


## Unlock and level cards borrow their buff's icon.
static func upgrade(key: String) -> Texture2D:
	if UPGRADES.has(key):
		return UPGRADES[key]
	if key.begins_with("region_"):
		return REGION
	for id in BUFFS:
		if key == "unlock_%s" % id or key == "level_%s" % id \
				or key.begins_with("level_%s_" % id):
			return BUFFS[id]
	return null


static func achievement(key: String) -> Texture2D:
	if key.begins_with(Achievements.BOSS_PREFIX):
		return BOSS
	return QUESTION


## Icon size and the gap after it, per point of font size.
const LABEL_SCALE := 1.15
const LABEL_GAP := 0.4


## Icon then text, as one label. `at` is the icon's left edge on the text baseline.
static func draw_label(canvas: CanvasItem, font: Font, texture: Texture2D, text: String,
		at: Vector2, color: Color, font_size: int,
		icon_color: Color = Color.TRANSPARENT) -> float:
	var icon := font_size * LABEL_SCALE
	draw(canvas, texture, Vector2(at.x + icon * 0.5, at.y - font_size * 0.36), icon,
		color if icon_color.a == 0.0 else icon_color)
	canvas.draw_string(font, Vector2(at.x + font_size * (LABEL_SCALE + LABEL_GAP), at.y),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	return at.x + label_width(font, text, font_size)


static func label_width(font: Font, text: String, font_size: int) -> float:
	return font_size * (LABEL_SCALE + LABEL_GAP) \
		+ font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Square icon centred on `centre`.
static func draw(canvas: CanvasItem, texture: Texture2D, centre: Vector2, size: float,
		color: Color) -> void:
	if texture == null:
		return
	var half := Vector2(size, size) * 0.5
	canvas.draw_texture_rect(texture, Rect2(centre - half, half * 2.0), false, color)
