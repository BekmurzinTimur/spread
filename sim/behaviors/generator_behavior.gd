class_name GeneratorBehavior
extends BlockBehavior

## Emits a full-value orb at its aimed target on a fixed interval.
## No target means idle: the timer does not even advance, so aiming a
## generator never grants it banked progress.


func on_produce(world, cell: GraphCell, block: Block) -> void:
	if block.target_id == -1:
		return
	block.timer += 1
	if block.timer < block.def.produce_interval:
		return
	block.timer = 0
	world.emit_orb(cell.id, block.target_id, block.def.output_tier)
