class_name Format

## Number formatting for anything shown to the player. Pure string math.

const SUFFIXES := ["", "k", "m", "b", "t", "qa", "qi"]


## 950 -> "950", 1234 -> "1.2k", 31_400_000 -> "31.4m". Truncates, never rounds up.
static func number(value: int) -> String:
	var n := absi(value)
	var tier := 0
	var scale := 1
	while tier < SUFFIXES.size() - 1 and n >= scale * 1000:
		scale *= 1000
		tier += 1
	var text := str(n)
	if tier > 0:
		var tenths := n / (scale / 10)
		text = str(tenths / 10)
		if tenths % 10 != 0:
			text += ".%d" % (tenths % 10)
		text += SUFFIXES[tier]
	return ("-" if value < 0 else "") + text
