class_name BlockBehavior
extends RefCounted

## Base for every block type. All hooks are empty here, so a block implements
## only the tick phases it actually participates in.
##
## One shared instance per BlockDef — behaviours are stateless. Per-block state
## (timers, targets) lives on Block.
##
## `world` is deliberately untyped: World refers to behaviours through the
## catalog, and annotating it here would close a cyclic class_name dependency.
##
## Adding a block type = a new script here + a catalog entry. When Distributor
## lands it needs multiple output ports; when Upkeep lands it needs a cost side
## to the stat-resolve pass. Both are additive, with no change to existing
## behaviours.


## Produce phase. Called once per tick for every block on an unlocked cell.
func on_produce(_world, _cell: GraphCell, _block: Block) -> void:
	pass


## Transport phase. Called when an orb enters this cell and will continue
## onward. Never called for the orb's final cell, so a block cannot alter what
## a delivery is worth.
func on_orb_pass(_world, _cell: GraphCell, _orb: Orb) -> void:
	pass


## Deliver phase. Called when an orb ends its route on this block's cell, which
## is only reachable once that cell is mined. The exact counterpart to
## `on_orb_pass`: that one sees every orb but the one stopping here, this one
## sees only that orb.
##
## Returns how much of `orb.value` it absorbed; the world wastes the remainder.
## The default of 0 is what every existing type wants — delivery into a mined
## cell is pure waste unless something there consumes it — so a block opts in to
## having an intake by overriding, and nothing else changes.
##
## An absorbing block must book what it took, or the ledger breaks. There is no
## way to return value here without it having come from somewhere.
func on_orb_deliver(_world, _cell: GraphCell, _orb: Orb) -> int:
	return 0
