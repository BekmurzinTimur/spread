class_name NodeType
extends RefCounted

## Static data for one buff type. The mutable half — how many levels the run has
## found — lives in `BuffState`.

const COMMON := 0
const RARE := 1

var id: String = ""
var display_name: String = ""
var rarity: int = COMMON

## Ascension purchase that puts this type into the board's table. Empty means it
## is in the pool from the first run — which is Yield and only Yield.
var unlock_key: String = ""


static func make(p_id: String, p_name: String, p_rarity: int,
		p_unlock_key: String) -> NodeType:
	var type := NodeType.new()
	type.id = p_id
	type.display_name = p_name
	type.rarity = p_rarity
	type.unlock_key = p_unlock_key
	return type
