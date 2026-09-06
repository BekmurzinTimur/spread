class_name DeliveryEvent
extends RefCounted

## One orb's value landing in a locked cell, recorded for the view to animate.
##
## Presentation only. Nothing in the simulation ever reads this back and no
## ledger bucket depends on it — the value it names is already fully accounted
## for under `delivered`. What it adds is *where* and *what colour*, which the
## ledger totals cannot say.
##
## `amount` is what actually counted toward the unlock, not what the orb was
## carrying: an orb worth 11 landing on a cell needing 3 records 3, and the other
## 8 is overshoot the ledger already books as waste. So the number on screen is
## always the number the bar moved by.

var cell_id: int = -1
var amount: int = 0
var tier: int = Tiers.RED

## The tick this landed on. A frame that catches several ticks up at once drains
## them together, and this is the only thing left afterwards that says how far
## apart they happened — enough for the view to stagger them rather than stack
## them all at one instant.
var tick: int = 0


func _init(p_cell_id: int, p_amount: int, p_tier: int, p_tick: int) -> void:
	cell_id = p_cell_id
	amount = p_amount
	tier = p_tier
	tick = p_tick
