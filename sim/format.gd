class_name Format

## Number formatting for anything shown to the player. Pure string math.

const SUFFIXES := ["", "k", "m", "b", "t", "qa", "qi", "sx", "sp", "oc", "no", "dc"]

## Guards truncation against a float landing a hair under a round number.
const NUDGE := 1.0 + 1e-12


## 950 -> "950", 1234 -> "1.23k", 1.378e67 -> "1.37e67". Truncates, never rounds up.
static func number(value: float) -> String:
	var n := absf(value)
	var sign := "-" if value < 0.0 else ""
	if n < 1000.0:
		return sign + str(int(n))
	var exponent := int(floor(log(n * NUDGE) / log(10.0)))
	var tier := exponent / 3
	if tier < SUFFIXES.size():
		return sign + _hundredths(n / pow(1000.0, tier)) + SUFFIXES[tier]
	return sign + _hundredths(n / pow(10.0, exponent)) + "e%d" % exponent


## A chance in `Rng.SCALE` units as a percent: "5%", "2.5%".
static func chance(scaled: int) -> String:
	scaled = mini(scaled, Rng.SCALE)
	if scaled % 100 == 0:
		return "%d%%" % (scaled / 100)
	return "%.1f%%" % (float(scaled) / 100.0)


## "31.45", "31.4" or "31": trailing zeros dropped.
static func _hundredths(scaled: float) -> String:
	var hundredths := int(floor(scaled * 100.0 * NUDGE))
	var text := str(hundredths / 100)
	var fraction := hundredths % 100
	if fraction != 0:
		text += (".%02d" % fraction).rstrip("0")
	return text
