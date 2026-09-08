class_name CompressorBehavior
extends BlockBehavior

## Banks many orbs and launches one big one of the same tier.
##
## **Decay is charged per orb, not per unit of value, and this block is what that
## rule is worth.** Ten orbs worth 10 each crossing twenty hops all evaporate and
## deliver nothing; one orb worth 100 crossing the same twenty hops arrives with
## 81. Nothing in the economy had to change for that to be true — it is a
## consequence of the decay rule as shipped, and a compressor is simply the thing
## that lets the player act on it.
##
## What it adds to play is a second answer to reach, genuinely different from the
## first. A pump extends a route **linearly** — one more hop of survival apiece,
## for every route through it, forever. A compressor makes distance nearly free
## and charges for it in **latency and granularity**: nothing at all arrives while
## the bank fills, and what does arrive lands in one lump that overshoots a small
## cell.
##
## Structurally this is `UpgraderBehavior` with the tier step taken out and the
## value carried across instead. Same two hooks, same absorb-then-emit split one
## tick apart, same order-independence argument. What differs is `compress_cost`
## standing outside the `converts()` family — see `BlockDef.compress_cost` for why
## a sphere must not shrink this bank.
##
## Anchored, like the upgrader and for the upgrader's reason: swapping is free and
## unlimited in range, so a movable compressor could be parked one hop from the
## frontier and the expensive half of every long haul would vanish.


## Absorb an arriving orb of the input tier, up to one output orb's worth.
##
## Read off the def rather than through an `effective_*` reader, and that is the
## whole of the sphere exemption — there is no `effective_compress_cost()` to call
## and deliberately so. A sphere near a compressor does nothing at all, which is
## the honest reading of a block whose output size is its identity.
##
## Capped for the upgrader's reason: only one orb leaves per tick however much is
## banked, so an uncapped bank on an unaimed compressor would swallow value that
## bought nothing. Overflow wastes visibly instead, which says *point that line
## somewhere else*.
##
## Banks whether or not the block is aimed, also for the upgrader's reason: mining
## a cell unaims everything pointed at it, and a compressor that refused orbs in
## that window would throw away whatever was already in flight.
func on_orb_deliver(world, cell: GraphCell, orb: Orb) -> int:
	var block := cell.block
	if not block.def.accepts_delivery(orb.tier):
		return 0
	var room: int = block.def.compress_cost - block.charge
	if room <= 0:
		return 0
	var taken: int = mini(orb.value, room)
	block.charge += taken
	world.absorb_value(taken)
	return taken


## Spend the full bank on one orb worth all of it.
##
## Deferred to the produce phase rather than fired from `on_orb_deliver`, which is
## load-bearing exactly as it is for the upgrader: deliver runs after produce, so
## charge accrued this tick is spent on the next, and no deliver step reads state
## another deliver step wrote.
##
## **The ledger balances without a new bucket.** What comes in books to `converted`
## through `absorb_value` above; what goes out books to `produced` through
## `emit_orb` below, at the value it was actually emitted with. Same in as out, and
## the ledger is tier-blind, so same-tier-in-same-tier-out is not a special case —
## it is the upgrader's accounting with the colour change removed.
func on_produce(world, cell: GraphCell, block: Block) -> void:
	if block.target_id == -1:
		return
	var cost: int = block.def.compress_cost
	if block.charge < cost:
		return
	# The whole bank becomes the orb's value *and* its launch value, so every pump
	# on the route restores a percentage of the big number rather than of an
	# ordinary orb's. A compressed line is why a pump corridor is worth building.
	#
	# Only a real emission spends the bank, for the upgrader's reason: an
	# unroutable target must not quietly bin a hundred value the player spent a
	# whole line collecting.
	if world.emit_orb(cell.id, block.target_id, block.def.output_tier,
			block.route_via, cost):
		block.charge -= cost
		block.mark_active(world.tick_count)
