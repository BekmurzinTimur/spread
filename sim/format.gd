class_name Format

## Number formatting for anything shown to the player. Pure string math.

const SUFFIXES := ["", "k", "m", "b", "t", "qa", "qi", "sx", "sp", "oc", "no", "dc"]

## Guards truncation against a float landing a hair under a round number.
const NUDGE := 1.0 + 1e-12


## 950 -> "950", 1234 -> "1.2k", 3.14e40 -> "3.1e40". Truncates, never rounds up.
static func number(value: float) -> String:
	var n := absf(value)
	var sign := "-" if value < 0.0 else ""
	if n < 1000.0:
		return sign + str(int(n))
	var exponent := int(floor(log(n * NUDGE) / log(10.0)))
	var tier := exponent / 3
	if tier < SUFFIXES.size():
		return sign + _tenths(n / pow(1000.0, tier)) + SUFFIXES[tier]
	return sign + _tenths(n / pow(10.0, exponent)) + "e%d" % exponent


## "31.4", or "31" when the tenth is zero.
static func _tenths(scaled: float) -> String:
	var tenths := int(floor(scaled * 10.0 * NUDGE))
	var text := str(tenths / 10)
	if tenths % 10 != 0:
		text += ".%d" % (tenths % 10)
	return text
