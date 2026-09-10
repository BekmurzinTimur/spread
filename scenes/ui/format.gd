class_name Format

## Presentation helpers shared by the HUD and the shop. Nothing here is read by
## `sim/`.


## 1234567 -> "1,234,567". Currency reaches the millions, and a bare digit run
## that long is unreadable.
static func thousands(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
