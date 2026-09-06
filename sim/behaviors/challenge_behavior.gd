class_name ChallengeBehavior
extends BlockBehavior

## Grants a permanent, board-wide bonus from the moment its cell is mined.
##
## **This behaviour overrides no hook**, for the same reason `SphereBehavior`
## does not: a challenge block does nothing in any tick phase. It neither
## produces nor touches a passing orb. What it does is *exist*, and the
## stat-resolve pass at the top of the tick sums it out of the graph. The code
## that makes a challenge matter lives in `World._resolve_stats()`.
##
## Where it differs from a sphere is reach, not shape. A sphere's bonus is keyed
## by position and only the blocks it can walk to see it; a challenge's is read
## by every consumer on the board. That is why a challenge is anchored: there is
## no placement decision to make, so leaving it movable would be a chore rather
## than a choice.
##
## It never pulses either. `mark_active()` is for a block that *did* something on
## a given tick, and a challenge's contribution is continuous — there is no
## instant to flash. The board draws it as a triangle instead, permanently, which
## is the honest picture of a landmark that is simply always on.
##
## One behaviour serves all three challenge types. They differ only in which
## `global_*` numbers their def carries, and none of that is behaviour.
