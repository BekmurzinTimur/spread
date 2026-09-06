extends Node2D

## Short-lived text that rises and fades — a delivered "+8" over the cell that
## absorbed it, and anything else worth saying for a moment.
##
## One `_draw()` for every live text, like the graph and the orbs: these are
## transient marks, not board entities, so there is no node per text to spawn and
## free sixty times a second.
##
## Knows nothing about the simulation — no orbs, no cells, no ticks. It takes a
## string, a colour, a world position and an age, which is what makes it reusable
## for the next thing worth announcing; `Main` does the translation from delivery
## events into calls on `spawn()`.

## Seconds a text lives for.
const LIFETIME := 0.9

## How far it travels upward over that lifetime, in world units.
const RISE := 34.0

## Fraction of the lifetime spent at full opacity. Fading from birth reads as a
## glitch; the text has to be legible before it starts to leave.
const HOLD := 0.45

## Sideways nudges applied to successive texts at one spot, so two orbs landing
## on the same cell on the same tick do not print on top of each other. The first
## is centred — a lone text is the common case and belongs over its cell — and
## the rest step out either side. Cycles, so a burst fans rather than marching
## off the screen.
const STAGGER_OFFSETS: PackedFloat32Array = [0.0, -24.0, 24.0]

## Hard ceiling. Nothing should ever approach this — it exists so a runaway
## caller degrades into dropped text rather than an unbounded array.
const MAX_LIVE := 128

var _texts: Array[Dictionary] = []
var _font: Font
var _font_size: int

## Origin key -> next index into STAGGER_OFFSETS, so repeat spawns at one cell
## spread out instead of stacking. Dropped once nothing is in the air.
var _stagger: Dictionary = {}


func _ready() -> void:
	# Same source as GraphView's labels, so the board speaks in one typeface.
	_font = ThemeDB.fallback_font
	_font_size = ThemeDB.fallback_font_size


## Show `text` at `at` (world space) in `color`. Any string, any colour.
##
## `age` back-dates the text: pass how long ago the thing it describes actually
## happened. A frame that catches many ticks up at once hands over a whole batch
## in one call, and without this they would all start together and print on top
## of each other — the stagger only separates a few. Back-dated, each one enters
## at the point of its arc it should already have reached, and anything older
## than a lifetime is dropped rather than shown late.
func spawn(text: String, color: Color, at: Vector2, age: float = 0.0) -> void:
	if text.is_empty() or age >= LIFETIME or _texts.size() >= MAX_LIVE:
		return

	var key := "%d:%d" % [roundi(at.x), roundi(at.y)]
	var step: int = _stagger.get(key, 0)
	_stagger[key] = (step + 1) % STAGGER_OFFSETS.size()

	_texts.append({
		"text": text,
		"color": color,
		"origin": at + Vector2(STAGGER_OFFSETS[step], 0.0),
		"age": maxf(age, 0.0),
	})


## Age every live text and drop the expired ones. Driven by `Main`, like every
## other view node; deliberately independent of the simulation clock, so texts
## finish their arc while the game is paused instead of freezing mid-air.
func advance(delta: float) -> void:
	if _texts.is_empty():
		if not _stagger.is_empty():
			_stagger.clear()
		return

	var alive: Array[Dictionary] = []
	for entry in _texts:
		entry["age"] = float(entry["age"]) + delta
		if float(entry["age"]) < LIFETIME:
			alive.append(entry)
	_texts = alive


func _draw() -> void:
	for entry in _texts:
		var k: float = clampf(float(entry["age"]) / LIFETIME, 0.0, 1.0)
		var text: String = entry["text"]

		# Ease out: most of the travel happens early, so the number is moving
		# when it appears and nearly still by the time it goes.
		var pos: Vector2 = entry["origin"] + Vector2(0.0, -RISE * (1.0 - pow(1.0 - k, 2.0)))

		var color: Color = entry["color"]
		color.a = 1.0 - smoothstep(HOLD, 1.0, k)

		var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
		draw_string(_font, pos - Vector2(size.x * 0.5, 0.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, color)
