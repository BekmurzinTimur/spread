class_name PumpBehavior
extends BlockBehavior

## Re-pressurises orbs travelling through this cell, back up to full value.
##
## Only fires on pass-through (the engine does not call this for an orb's final
## cell), so a pump next to a target cannot inflate deliveries.


func on_orb_pass(world, cell: GraphCell, orb: Orb) -> void:
	world.restore_orb(orb, cell.block.def.restore_amount)
	cell.block.mark_active(world.tick_count)
