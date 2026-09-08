class_name BlockPort
extends RefCounted

## One output of a block that has several: a destination, and the waypoints the
## route to it is bent through.
##
## Exactly the pair `Block.target_id` and `Block.route_via` already are for a
## single-output block, lifted into an object so a block can hold a list of them.
##
## **The two are deliberately not unified.** Aliasing a single-target block's
## fields onto `ports[0]` was the obvious tidy-up and it is the wrong trade: every
## function that walks ports has to walk *all* of them anyway, so the alias buys
## nothing but a second source of truth to keep in sync forever. The twelve
## single-output types keep the fields they always had; a ported block keeps this.
##
## Plain data, so it costs a serialiser nothing — `route_via` is a
## `PackedInt32Array` of cell ids, the same shape `Block.route_via` already is.

var target_id: int = -1
var route_via: PackedInt32Array = PackedInt32Array()


func _init(p_target_id: int, p_route_via := PackedInt32Array()) -> void:
	target_id = p_target_id
	route_via = p_route_via
