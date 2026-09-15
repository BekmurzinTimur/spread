class_name IconHex
extends HexPanel

## A hex with an icon in it: achievement and upgrade badges. Pages decide the look.

const LOCKED_COLOR := Color(0.34, 0.37, 0.43)
const LOCKED_FILL := Color(0.051, 0.056, 0.065)
const LOCKED_ICON := Color(1.0, 1.0, 1.0, 0.35)

## Darkening of the empty hex, and of the filled part.
const EMPTY_DARKEN := 0.85
const FILL_DARKEN := 0.55

@onready var _icon: TextureRect = $Icon


func set_look(outline: Color, fill: Color, readiness_fill: Color, amount: float,
		texture: Texture2D, icon_color: Color = Color.WHITE) -> void:
	outline_color = outline
	fill_color = fill
	readiness_color = readiness_fill
	readiness = amount
	_icon.texture = texture
	_icon.modulate = icon_color


## 0..1, for outlines that pulse.
static func pulse() -> float:
	return 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006)
