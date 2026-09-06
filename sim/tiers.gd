class_name Tiers

## Six resource tiers, cheapest to rarest: red -> purple.
## RED and ORANGE are in play; the rest have names and colours but nothing that
## emits them yet.

const RED := 0
const ORANGE := 1
const YELLOW := 2
const GREEN := 3
const BLUE := 4
const PURPLE := 5

const COUNT := 6

const NAMES: PackedStringArray = ["red", "orange", "yellow", "green", "blue", "purple"]

const COLORS: PackedColorArray = [
	Color("e0453a"),  # red
	Color("e8842c"),  # orange
	Color("e5c235"),  # yellow
	Color("4fb050"),  # green
	Color("3b7fd4"),  # blue
	Color("9a4fd0"),  # purple
]


static func color_of(tier: int) -> Color:
	if tier < 0 or tier >= COUNT:
		return Color.WHITE
	return COLORS[tier]


static func name_of(tier: int) -> String:
	if tier < 0 or tier >= COUNT:
		return "unknown"
	return NAMES[tier]


## Inverse of `name_of`, for the map file. Cells name their required tier as a
## string so the JSON stays readable, and an unknown name falls back to RED
## rather than failing: a cell that demands nothing recognisable is a cell the
## starting tier can still open, which keeps a typo from bricking the board.
static func from_name(tier_name: String) -> int:
	var index := NAMES.find(tier_name)
	return index if index >= 0 else RED
