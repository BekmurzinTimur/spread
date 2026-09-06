class_name PumpBehavior
extends BlockBehavior

## Adds a flat amount to orbs travelling through this cell. Not a top-up to full
## value — that was the old capped design, and it made a second pump on a route
## worthless. Flat and uncapped, so pumps stack and an orb can arrive worth more
## than it launched with.
##
## Only fires on pass-through (the engine does not call this for an orb's final
## cell), so a pump next to a target cannot inflate deliveries.


func on_orb_pass(world, cell: GraphCell, orb: Orb) -> void:
	# Effective, not base — a sphere in range makes this pump restore more, and
	# `World.arrival_along` promises the same number to the aim preview.
	world.restore_orb(orb, world.effective_restore(cell))
	cell.block.mark_active(world.tick_count)
