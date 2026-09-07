class_name Tiers

## Seven resource tiers, cheapest to rarest: red -> purple. A rainbow, with teal
## between green and blue.
##
## All seven are produced: the map buries generators of every colour, so a tier is
## a place on the board rather than a rung nothing can reach. Upgraders convert
## one step up the ladder, which is what makes a colour available *where you need
## it* rather than only where the map put it.
##
## The colours are the board's only hues. Everything that is not a resource — a
## pump, a sphere, an upkeep block, the edges between cells — is painted from a
## neutral grey ramp, so a colour on screen always answers the same question:
## which tier is this? `test_tier_tables_are_consistent` holds that honest by
## asserting the seven are distinct and none of them is grey.

const RED := 0
const ORANGE := 1
const YELLOW := 2
const GREEN := 3
const TEAL := 4
const BLUE := 5
const PURPLE := 6

const COUNT := 7

const NAMES: PackedStringArray = [
	"red", "orange", "yellow", "green", "teal", "blue", "purple"
]

## Struck for a near-black board: brighter and more saturated than a mid-grey
## ground would need, because a dim hue on onyx reads as dark rather than as
## coloured. Teal has to hold its own against both green and blue, so it sits
## well to the cyan side of green rather than halfway between the two.
const COLORS: PackedColorArray = [
	Color("f0554a"),  # red
	Color("f5902f"),  # orange
	Color("efcb3a"),  # yellow
	Color("5cc255"),  # green
	Color("22c3ac"),  # teal
	Color("4a90e2"),  # blue
	Color("a95ce0"),  # purple
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
