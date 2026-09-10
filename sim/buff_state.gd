class_name BuffState
extends RefCounted

## The run's buff levels — a tally and nothing else.
##
## The arithmetic that turns it into a number lives in `World`'s `effective_*`
## readers, so two increased rates can share one divisor.
##
## ⚠️ Found and bought levels are kept apart: a purchase can happen mid-run, and
## one shared table would mean re-reading the shop wiped the run's finds.

## Levels dug up this run. Only ever grow, and reset at ascension.
var found: Dictionary = {}

## Levels the shop grants, re-read whenever a purchase lands.
var bought: Dictionary = {}


func level_of(id: String) -> int:
	return int(found.get(id, 0)) + int(bought.get(id, 0))


func add(id: String, count: int = 1) -> void:
	if count <= 0:
		return
	found[id] = int(found.get(id, 0)) + count


## A pure read of `meta`. Called when a run starts and after a purchase — never
## inside the tick.
func apply_meta(meta: MetaState) -> void:
	bought = {}
	if meta == null:
		return
	for node_id in NodeCatalog.ids():
		var id := String(node_id)
		var level := meta.level_of(MetaUpgrades.node_level_key(id))
		if level > 0:
			bought[id] = level
