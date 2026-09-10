class_name Bands

## The seven depth rings, red at the core to purple at the rim.
##
## A band is a *distance*, not a currency. Hue says how far out a cell sits and
## nothing else; node rarity is carried by glow instead, so the two read at once
## without fighting.
##
## Band positions are fixed — the board is the same place every run, and only
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

## Last hop of each band. Red is 0-8, orange 9-11, and so on to purple at 23-24.
## Red is nine hops deep because it is the whole of run 1 and has to be long
## enough to teach the game.
const BAND_LAST_HOP: PackedInt32Array = [8, 11, 14, 17, 19, 22, 24]

## Radius of the board, and the last hop of the outermost band.
const MAX_HOPS := 24


static func band_of(hops: int) -> int:
	for band in COUNT:
		if hops <= BAND_LAST_HOP[band]:
			return band
	return PURPLE


static func name_of(band: int) -> String:
	if band < 0 or band >= COUNT:
		return "?"
	return NAMES[band]


static func color_of(band: int) -> Color:
	if band < 0 or band >= COUNT:
		return Color.WHITE
	return Color(COLORS[band])
