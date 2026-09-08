class_name TeleporterBehavior
extends BlockBehavior

## Folds two distant cells into a single hop.
##
## **Overrides no hook, and that is not an omission** — the same shape as
## `SphereBehavior` one level out. A sphere acts by *being somewhere*; a
## teleporter acts by two of them being somewhere, and what they change is the
## board's **adjacency** rather than anything about a tick. `World._resolve_links`
## reads their positions out of the graph and maintains the edge.
##
## The edge is a real entry in `neighbor_ids`, which is what makes this type so
## nearly free: BFS, `find_chain`'s no-crossing rule, the waypoint legs, decay per
## hop and the path cache all keep working with no notion that the edge is special.
## A teleport hop is therefore **free in distance and not in decay** — it costs the
## same 1 value and the same 10 ticks any other hop costs, and what it saves is the
## twenty hops it stood in for.
##
## Movable, and takes no target. The pairing is baked into the def rather than
## aimed, which is what keeps `needs_target` and `movable` disjoint and the
## right-click gesture unambiguous — see `BlockDef.link_group`.
