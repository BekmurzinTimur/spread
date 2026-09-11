class_name Regions

## The seven depth rings, red at the core to purple at the rim.
##
## A region is a *distance*, not a currency. Hue says how far out a cell sits and
## nothing else; node rarity is carried by glow instead, so the two read at once
## without fighting.
##
## Region positions are fixed — the board is the same place every run, and only
## node placement is randomised.

const RED := 0
const ORANGE := 1
const YELLOW := 2
const GREEN := 3
const TEAL := 4
const BLUE := 5
const PURPLE := 6

const COUNT := 7

const NAMES: PackedStringArray = [
	"Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple"
]

const COLORS: PackedStringArray = [
	"e05252", "e08a3c", "d8c040", "5cb85c", "3cb0a8", "4a86d8", "9a5cd0"
]

## Last hop of each region. Every region is eight rings; red also holds the centre.
const REGION_LAST_HOP: PackedInt32Array = [8, 16, 24, 32, 40, 48, 56]

## Deepest depth on the board. The geometric radius adds the gap rings (`HexMap.ring_of`).
const MAX_HOPS := 56


static func region_of(hops: int) -> int:
	for region in COUNT:
		if hops <= REGION_LAST_HOP[region]:
			return region
	return PURPLE


static func name_of(region: int) -> String:
	if region < 0 or region >= COUNT:
		return "?"
	return NAMES[region]


static func color_of(region: int) -> Color:
	if region < 0 or region >= COUNT:
		return Color.WHITE
	return Color(COLORS[region])
