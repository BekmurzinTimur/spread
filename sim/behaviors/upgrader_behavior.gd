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


## Absorb an arriving orb of the input tier, up to **one orb's worth** of charge.
##
## The bank holds room for exactly one output orb and no more. What will not fit
## is refused here and the world wastes it, which is the first real use of
## `on_orb_deliver`'s partial return — every other override takes all or nothing.
## No ledger work is needed for it: `World._deliver` already books
## `orb.value - taken` to `wasted` and records the delivery event at `taken`.
##
## The cap is the *effective* cost rather than the def's, so "room for one orb"
## stays literally true as spheres come and go. Two consequences worth knowing.
## A sphere arriving mid-fill lowers the cap under a bank that is already larger;
## nothing is confiscated, the block simply emits on the next produce phase. And
## a sphere leaving raises it, which reopens room the player can fill again.
##
## Capped rather than uncapped because an unfed converter used to stockpile
## silently: a line left pointed at one for a few minutes banked hundreds of value
## that bought nothing, since only one orb leaves per tick anyway. Overflow is now
## visible as waste, which is the honest reading — that red should have gone
## somewhere else.
##
## Order-independence survives. Two orbs landing in one tick bank
## `min(sum, room)` whichever lands first, so the totals commute; only the split
## between the two *delivery events* depends on order, and that channel is
## declared order-dependent in its contents already.
##
## Absorption happens whether or not the block is aimed. An idle upgrader banks
## charge the player can spend the moment they point it somewhere, which matters
## because mining a cell unaims whatever was pointed at it: without banking, every
## orb already in flight during that window would be thrown away.
##
## `UpkeepBehavior` deliberately does *not* follow this. Its bank is a battery —
## over-feeding one is how the player buys run time — so it stays uncapped by
## choice. The mechanism here is available to it the day that changes.
func on_orb_deliver(world, cell: GraphCell, orb: Orb) -> int:
	var block := cell.block
	if not block.def.accepts_delivery(orb.tier):
		return 0
	var room: int = world.effective_upgrade_cost(cell) - block.charge
	if room <= 0:
		return 0
	var taken: int = mini(orb.value, room)
	block.charge += taken
	world.absorb_value(taken)
	return taken


## Spend banked charge on one output orb.
##
## Emission is deferred to the produce phase rather than fired from
## `on_orb_deliver`, and that is load-bearing. Deliver runs after produce, so
## charge accrued this tick is spent on the next one, and no deliver step ever
## reads state another deliver step wrote. Charge is a sum of integers, so two
## orbs landing in the same tick commute — the tick stays order-independent for
## free, which is what `test_tick_order_independent` checks.
##
## One orb per tick, and now at most one orb *banked*, so the two limits agree.
## The intake cap means `charge` can never reach twice the cost, and this used to
## be the note explaining what happened when it did. What is left is the residual
## a sphere can create: lowering the cap under a full bank leaves charge above it
## until the next emission clears it.
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
