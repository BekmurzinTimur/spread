class_name GeneratorBehavior
extends BlockBehavior

## Emits a full-value orb at its aimed target on a fixed interval.
## No target means idle: the timer does not even advance, so aiming a
## generator never grants it banked progress.


func on_produce(world, cell: GraphCell, block: Block) -> void:
	if block.target_id == -1:
		return
	block.timer += 1
	# Effective, not base: a sphere in range shortens the interval. Read every
	# tick rather than cached on the block, so moving a sphere takes effect on the
	# next tick instead of on the next emission.
	if block.timer < world.effective_interval(cell):
		return
	block.timer = 0
	# Only a real emission counts as activity. An unroutable target still resets
	# the timer — the cycle ran — but nothing left the cell, so nothing pulses.
	if world.emit_orb(cell.id, block.target_id, block.def.output_tier, block.route_via):
		block.mark_active(world.tick_count)
