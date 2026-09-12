class_name SkillState
extends RefCounted

## The run's skill clocks, keyed by buff id. Mining charges readiness; a full
## skill can be activated, which starts its cooldown and, for buffs, its effect.

const READINESS_PER_MINE := 10
const FULL := 100
const COOLDOWN_TICKS := 300  # 30 s
const ACTIVE_TICKS := 100    # 10 s

var readiness: Dictionary = {}
var cooldown: Dictionary = {}
var active: Dictionary = {}


func readiness_of(id: String) -> int:
	return int(readiness.get(id, 0))


func cooldown_of(id: String) -> int:
	return int(cooldown.get(id, 0))


func is_ready(id: String) -> bool:
	return readiness_of(id) >= FULL and cooldown_of(id) == 0


func is_active(id: String) -> bool:
	return int(active.get(id, 0)) > 0


## No readiness while cooling down.
func charge(id: String) -> void:
	if cooldown_of(id) > 0:
		return
	readiness[id] = mini(FULL, readiness_of(id) + READINESS_PER_MINE)


func activate(id: String) -> void:
	readiness[id] = 0
	cooldown[id] = COOLDOWN_TICKS
	active[id] = ACTIVE_TICKS


func advance() -> void:
	for id in cooldown:
		cooldown[id] = maxi(0, int(cooldown[id]) - 1)
	for id in active:
		active[id] = maxi(0, int(active[id]) - 1)
