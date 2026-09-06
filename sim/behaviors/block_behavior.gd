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
## or Upgrader land they need an `on_orb_deliver` hook; when Sphere or Upkeep
## land they need a stat-resolve pass ahead of `on_produce`. Both are additive:
## a new hook and a new phase, with no change to existing behaviours.


## Produce phase. Called once per tick for every block on an unlocked cell.
func on_produce(_world, _cell: GraphCell, _block: Block) -> void:
	pass


## Transport phase. Called when an orb enters this cell and will continue
## onward. Never called for the orb's final cell, so a block cannot alter what
## a delivery is worth.
func on_orb_pass(_world, _cell: GraphCell, _orb: Orb) -> void:
	pass
