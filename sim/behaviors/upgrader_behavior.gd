class_name UpgraderBehavior
extends BlockBehavior

## Turns delivered value of one tier into orbs of the next.
##
## A generator with the clock taken out of it. Where a generator's timer fills
## itself and the player only chooses where the output goes, an upgrader's
## charge fills only from orbs the player routed into it — so it has to be the
## target of a generator before it is a source of anything. That is the whole
## shape of the second tier: orange is not produced, it is *converted*, and the
## red line feeding the converter is as much a part of the network as the orange
## line leaving it.
##
## Anchored, like a generator, and for the same reason. Swapping is free and
## unlimited in range, so a movable upgrader could be parked next to the frontier
## and the orange leg of every route would collapse to one hop.


## Absorb an arriving orb of the input tier. The whole value is taken — there is
## no cap and no overshoot waste, so a big arrival simply banks more.
##
## This happens whether or not the block is aimed. An idle upgrader banks charge
## the player can spend the moment they point it somewhere, which matters because
## mining a cell unaims whatever was pointed at it: without banking, every orb
## already in flight during that window would be thrown away.
func on_orb_deliver(world, cell: GraphCell, orb: Orb) -> int:
	var block := cell.block
	if not block.def.accepts_delivery(orb.tier):
		return 0
	block.charge += orb.value
	world.absorb_value(orb.value)
	return orb.value


## Spend banked charge on one output orb.
##
## Emission is deferred to the produce phase rather than fired from
## `on_orb_deliver`, and that is load-bearing. Deliver runs after produce, so
## charge accrued this tick is spent on the next one, and no deliver step ever
## reads state another deliver step wrote. Charge is a sum of integers, so two
## orbs landing in the same tick commute — the tick stays order-independent for
## free, which is what `test_tick_order_independent` checks.
##
## One orb per tick, at most. Charge carries over rather than being flushed, so
## a burst of deliveries becomes a steady stream out instead of a clump, and
## nothing is lost to rounding.
func on_produce(world, cell: GraphCell, block: Block) -> void:
	if block.target_id == -1:
		return
	# Read once, into a local, and used for both the threshold and the deduction.
	# A sphere discounts this, so the def's number is no longer the answer — and
	# asking twice would let a stats rebuild between the two lines charge a price
	# the block was never tested against.
	var cost: int = world.effective_upgrade_cost(cell)
	if block.charge < cost:
		return
	# Only a real emission spends the charge. An unroutable target leaves the
	# bank untouched, which is why the deduction sits inside the check rather
	# than beside it — the generator's timer can afford to burn a cycle on a dead
	# route because it costs nothing; charge cost the player a whole red line.
	if world.emit_orb(cell.id, block.target_id, block.def.output_tier, block.route_via):
		block.charge -= cost
		block.mark_active(world.tick_count)
