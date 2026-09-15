class_name Achievements

## Every achievement. Static, built once. Held achievements live in `MetaState`.
##
## ⚠️ Keys are save keys and must never be renamed.

## Per beaten boss, multiplicative: fewer orbs, each worth more.
const BOSS_RATE_LESS := 33
const BOSS_VALUE_MORE := 75

const BOSS_PREFIX := "boss_"

static var _all: Dictionary = {}
static var _order: Array[String] = []


static func _build() -> void:
	if not _all.is_empty():
		return
	# Every region but the last has a boss guarding the next one.
	for region in range(Regions.RED, Regions.COUNT - 1):
		var name := Regions.name_of(region)
		_add(Achievement.make(boss_key(region), "%s boss" % name,
			"Beat the %s boss and bank the run." % name.to_lower(), region,
			-BOSS_RATE_LESS, BOSS_VALUE_MORE))


static func _add(a: Achievement) -> void:
	_all[a.key] = a
	_order.append(a.key)


static func boss_key(region: int) -> String:
	return BOSS_PREFIX + Regions.name_of(region).to_lower()


static func all() -> Array[String]:
	_build()
	return _order


static func get_achievement(key: String) -> Achievement:
	_build()
	return _all.get(key)


static func has(key: String) -> bool:
	_build()
	return _all.has(key)


## Progress toward `target`. Held achievements read as complete.
static func progress(meta: MetaState, key: String) -> int:
	var a := get_achievement(key)
	if a == null or meta == null:
		return 0
	if meta.has_achievement(key):
		return a.target
	if key.begins_with(BOSS_PREFIX):
		return 1 if meta.region_open(a.region + 1) else 0
	return 0


## Grants everything earned and not yet held. Returns the new keys.
static func evaluate(meta: MetaState) -> Array[String]:
	var granted: Array[String] = []
	for key in all():
		if not meta.has_achievement(key) \
				and progress(meta, key) >= get_achievement(key).target:
			meta.grant_achievement(key)
			granted.append(key)
	return granted


static func held_count(meta: MetaState) -> int:
	var count := 0
	for key in all():
		if meta != null and meta.has_achievement(key):
			count += 1
	return count


static func rate_multiplier(meta: MetaState) -> float:
	var total := 1.0
	if meta == null:
		return total
	for key in meta.achievements:
		var a := get_achievement(key)
		if a != null:
			total *= (100 + a.rate_more_percent) / 100.0
	return total


static func value_multiplier(meta: MetaState) -> float:
	var total := 1.0
	if meta == null:
		return total
	for key in meta.achievements:
		var a := get_achievement(key)
		if a != null:
			total *= (100 + a.value_more_percent) / 100.0
	return total
