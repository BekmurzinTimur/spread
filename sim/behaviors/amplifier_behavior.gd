class_name AmplifierBehavior
extends BlockBehavior

## Multiplies an orb passing through, where a pump adds to it.
##
## **This hook does no arithmetic, and that is the entire design.** It increments
## a counter on the orb; `World._deliver` resolves the whole exponent once, when
## the orb lands. Multiplication does not commute with the additive pump restore
## the way another addition would, so an amplifier that scaled the orb *where it
## was met* would make arrival depend on the order the route met its blocks —
## which is precisely the order-dependence `architecture.md` cites when it rules
## out a compounding pump restore.
##
## Counting here and resolving there makes arrival a function of the orb's value
## and the number of amplifiers it passed, and of nothing else. It is the same
## shape as `StatBonus.apply_rate()`: sum the terms, divide once.
##
## Like the pump, this only fires on pass-through — the engine does not call it
## for an orb's final cell — so an amplifier parked on a target does nothing to
## the deliveries landing on it.


func on_orb_pass(world, cell: GraphCell, orb: Orb) -> void:
	orb.amplifiers += 1
	cell.block.mark_active(world.tick_count)
