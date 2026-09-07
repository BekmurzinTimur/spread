class_name PumpBehavior
extends BlockBehavior

## Adds a percentage of an orb's launch value to it as it travels through this
## cell. Not a top-up to full value — that was the old capped design, and it made
## a second pump on a route worthless. Uncapped, so pumps stack and an orb can
## arrive worth more than it launched with.
##
## Only fires on pass-through (the engine does not call this for an orb's final
## cell), so a pump next to a target cannot inflate deliveries.


func on_orb_pass(world, cell: GraphCell, orb: Orb) -> void:
	# Through `restore_for`, which is the one place a percentage becomes value —
	# a sphere in range makes this pump restore more, and `World.arrival_along`
	# promises the aim preview the same number by asking the same function.
	#
	# The orb's launch value, not its current one: pumps are summed along a route
	# rather than compounded, so what one adds cannot depend on which pumps the
	# orb met first.
	world.restore_orb(orb, world.restore_for(cell, orb.launch_value))
	cell.block.mark_active(world.tick_count)
