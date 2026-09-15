class_name SoundCue
extends Resource

## One kind of sound, and how it behaves when requested hundreds of times a second.

## An AudioStreamRandomizer gives variations and random pitch.
@export var stream: AudioStream
@export_range(-60.0, 12.0, 0.5, "suffix:dB") var volume_db: float = 0.0
@export var bus: StringName = &"Board"

## Copies that may overlap. One more stops the oldest.
@export_range(1, 32) var max_voices: int = 4
## Requests sooner than this after the last play are dropped.
@export_range(0.0, 1.0, 0.005, "suffix:s") var min_interval: float = 0.05
## With every voice taken, a cue may replace only voices of equal or lower priority.
@export_range(0, 10) var priority: int = 1

## Extra loudness per doubling of the requests one play stands for.
@export_range(0.0, 6.0, 0.1, "suffix:dB") var stack_gain_db: float = 1.5
@export_range(0.0, 24.0, 0.5, "suffix:dB") var max_stack_db: float = 6.0
