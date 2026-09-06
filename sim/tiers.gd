class_name Tiers

## Six resource tiers, cheapest to rarest: red -> purple.
## Iteration 1 only uses RED.

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
