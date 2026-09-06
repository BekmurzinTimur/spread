class_name SphereBehavior
extends BlockBehavior

## Radiates a bonus to every block within `field_radius` hops: producers in range
## run faster, path modifiers in range restore more.
##
## **This behaviour overrides no hook, and that is not an omission.** A sphere
## does nothing in any tick phase — it neither produces nor touches a passing
## orb. What it does is *be somewhere*, and the stat-resolve pass at the top of
## the tick reads its position out of the graph. So there is no `on_produce` and
## no `on_orb_pass` to find here; the code that makes a sphere matter lives in
## `World._resolve_stats()`.
##
## It follows that a sphere never pulses on the board either. `mark_active()` is
## for a block that *did* something on a given tick, and a sphere's contribution
## is continuous — there is no instant to flash. The view shows its field
## instead, which is the honest picture of what it is doing.
