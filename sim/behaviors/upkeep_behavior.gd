class_name UpkeepBehavior
extends BlockBehavior

## Burns a steady trickle of resource to hold a board-wide bonus up.
##
## The first thing in the game that *costs* something to run. Every other buff is
## bought once and kept forever: a challenge is mined and pays out for the rest of
## the game, a sphere sits where it was put. An upkeep block only pays while the
## player keeps feeding it, which is what makes expansion a trade — every orb
## routed here is an orb not spent opening a cell.
##
## Its bank fills exactly like an upgrader's, from orbs the player aimed at it,
## and for the same reason: a block with an appetite has to be somebody's target
## before it is worth anything. What differs is what the bank buys. An upgrader
## spends it on a higher tier and hands the value back; this spends it on time and
## does not.
##
## **Movable**, unlike a challenge, and that is the whole design of the type. A
## challenge is anchored because its bonus reaches everywhere from anywhere, so
## there is no placement to get right. This one has to be *fed*, so it very much
## has a "where": next to a generator that can afford it, and close enough to the
## red you actually have. Being feedable is the placement decision.
##
## No `on_produce` and no `on_orb_pass`. The drain is a phase rather than a hook —
## it has to run before any stat resolves, and a hook cannot; see
## `World._phase_upkeep()`. And an orb merely routed *across* an upkeep block is
## untouched, the same rule the upgrader has. That one is newly load-bearing:
## waypoints make crossing a cell a deliberate act, and a block that skimmed
## passing traffic would turn every corridor into a toll gate.


## Absorb an arriving orb of the input tier into the fuel bank.
##
## The whole value is taken. There is no cap and so no overshoot waste — a big
## arrival simply buys a longer run before the bonus goes dark, which is what
## makes over-feeding a battery rather than a mistake. It is also what keeps the
## ledger simple: the intake is total, so it books to one bucket.
##
## Banks whether or not anything is aimed at it, like the upgrader. Mining a cell
## unaims everything pointed at it, and a block that refused orbs during that
## window would throw away whatever was already in flight.
func on_orb_deliver(world, cell: GraphCell, orb: Orb) -> int:
	var block := cell.block
	if not block.def.accepts_delivery(orb.tier):
		return 0
	block.charge += orb.value
	world.burn_value(orb.value)
	return orb.value
