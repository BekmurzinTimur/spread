class_name MetaStore

## Reads and writes a `MetaState` as JSON. The only place in the project that
## writes a file.
##
## ⚠️ **The path is a required argument with no default.** This writes a mutable
## file, and a default of `user://ascension.json` would let the headless suite
## clobber a real player's progress the first time somebody wrote a test that
## forgot to pass a path. Naming the file is the caller's job — `Main` does it
## once, in one constant.
##
## `World` never references this class. It takes a `MetaState`, which is plain
## data, so the simulation still has no opinion about where that state came from
## and the determinism contract is unaffected: same state in, same economy out,
## whether it was loaded, built by a test, or null.

## Missing file is the ordinary first-boot case, not an error: a player who has
## never ascended has nothing saved, and a fresh state is the right answer.
static func load_from(path: String) -> MetaState:
	if not FileAccess.file_exists(path):
		return MetaState.new()

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MetaStore: cannot open %s" % path)
		return MetaState.new()
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		# A corrupt save starts the player over rather than refusing to boot. The
		# alternative is a game that will not open, which is a worse outcome than
		# a lost ladder — and `from_dict` already drops anything it cannot read.
		push_error("MetaStore: %s is not a JSON object" % path)
		return MetaState.new()

	return MetaState.from_dict(parsed)


## Returns whether the write landed, so the caller can tell the player their
## progress did not save rather than discovering it at the next launch.
static func save_to(state: MetaState, path: String) -> bool:
	if state == null:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("MetaStore: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(state.to_dict(), "\t"))
	file.close()
	return true
