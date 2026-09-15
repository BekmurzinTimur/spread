class_name SoundBank
extends Resource

## Every game sound, one slot per event. An empty slot is silent.

@export_group("Board")
@export var orb_launch: SoundCue
@export var orb_land: SoundCue
@export var splash: SoundCue
@export var crit: SoundCue
@export var cell_mined: SoundCue
@export var node_found: SoundCue
@export var boss_mined: SoundCue
@export var ram_fire: SoundCue

@export_group("UI")
@export var skill_activate: SoundCue
@export var ram_arm: SoundCue
@export var buy: SoundCue
@export var buy_denied: SoundCue
@export var run_end: SoundCue
@export var run_start: SoundCue
