# Architecture

How Spread is put together: the modules, the calculations they own, and the contracts between them.
Read this before changing anything structural. See `gamedesign.md` for what the game *is*; this
document is how it works.

---

## The one rule

**The simulation is not the scene tree.**

```
   scenes/  ──────────────►  sim/
   (Godot nodes, drawing,     (plain RefCounted, integer math,
    input, HUD)                no Node, no _process, no rendering)
```

The arrow points one way and never back. `sim/` must never reference a Godot node, a scene, a signal,
or `delta`. This is what makes the economy testable headlessly, deterministic across runs, and
serialisable later without walking a node tree.

The view reads simulation state and issues commands through `World`'s public methods. It never mutates
simulation state directly.

---

## Module map

| Module | Owns | Depends on |
|---|---|---|
| `sim/world.gd` | The tick, the value ledger, all player commands | Graph, Orb, Block, BlockCatalog |
| `sim/graph.gd` | Adjacency, discovery, restricted BFS, path cache, `unlock_cell()` | GraphCell |
| `sim/graph_cell.gd` | One position: lock state, cost, contents, `apply_unlock()` | Block, BlockCatalog |
| `sim/block.gd` | An installed block: def + target + timer + last-active tick | BlockDef |
| `sim/block_def.gd` | Static per-type data (Resource) | BlockBehavior, Tiers |
| `sim/block_catalog.gd` | Every block type, in one place | BlockDef, behaviours |
| `sim/behaviors/*.gd` | Per-type logic, at most one hook each — except the upgrader, which has two, and two types override none | GraphCell, Block, Orb |
| `sim/stat_bonus.gd` | One cell's summed field bonuses, and how a base combines with them | — |
| `sim/global_bonus.gd` | The board's summed challenge bonuses, and the one percentage scale | — |
| `sim/orb.gd` | A packet in flight: value, route, progress | Tiers |
| `sim/delivery_event.gd` | One recorded delivery: cell, amount, tier, tick | Tiers |
| `sim/map_loader.gd` | JSON → Graph; `line_graph()` for tests | Graph, GraphCell, BlockCatalog |
| `sim/tiers.gd` | Six tiers, red → purple, names and colours | — |
| `scenes/Main.gd` | Owns World, drives the fixed tick, routes input | sim, view, HUD |
| `scenes/camera_2d.gd` | Pan/zoom, and the click-vs-drag verdict | — |
| `scenes/view/GraphView.gd` | Draws edges, cells, routes, previews | sim (read-only) |
| `scenes/view/OrbLayer.gd` | Draws orbs, interpolated between ticks | sim (read-only) |
| `scenes/view/FloatingTextLayer.gd` | Rising, fading text; knows only strings and colours | — |
| `scenes/ui/HUD.gd` | Selection panel, commands, ledger readout | Main, sim (read-only) |
| `tools/gen_map.py` | Generates `data/map_01.json`, asserts its properties | — |
| `tests/run_tests.gd` | Headless suite, exits non-zero on failure | everything |

Behaviours take `world` as an **untyped** parameter on purpose. `World` reaches behaviours through the
catalog, so annotating it would close a hard `class_name` cycle back to the top-level type. The
remaining references among `sim/` types (cell → block → def → behaviour) resolve lazily and are fine.

---

## Data model

**Cell vs Block is the central distinction.** The cell is the real estate; the block is the tenant.

- `GraphCell` — a fixed position with neighbours, a lock state, an unlock cost, and `initial_block_id`
  (what the map buried here, `""` for empty). Cells never move and are never created at runtime.
- `Block` — a `BlockDef` plus mutable state: `target_id`, a produce `timer`, and a `charge` bank.
  Created only by `GraphCell.apply_unlock()`, then moved between cells by swapping — if its type
  allows it.

**A cell also states the colour that opens it.** `GraphCell.required_tier` is static map data, and
`accepts_tier()` is the whole of the tier gate: an orb of any other tier is wasted. This is how a
second currency is expressed, and it is worth saying why it is not a stockpile. Value in Spread is
never banked — it is emitted, routed, and spent on arrival — so there is nowhere for a "balance" to
live. A currency is therefore a fact about *what a cell will take*, and the board is the ledger.

Unlike `initial_block_id`, `required_tier` is **not concealed**: the view tints a locked cell by it.
That leaks nothing the fog is there to protect, because it describes the *price* and not the prize —
the glyph stays the same question mark every unmined cell gets.

`initial_block_id` and `block` are separate fields because they diverge the moment the player swaps.
`initial_block_id` is **concealed until the cell is mined** — a locked cell draws a question mark — so
nothing outside `apply_unlock()` reads it. Presentation asks `block`; the view must never reach for
`initial_block_id`, or it will draw the answer to something the player is meant to discover.

**Blocks are never created or destroyed at runtime.** `apply_unlock()` is the only constructor, and
swapping is the only way to relocate one. The map therefore fixes the supply of generators and pumps,
which is what makes placement a real decision.

**And generators are never relocated at all.** `BlockDef.movable` is false for the generator, and
`can_swap` refuses from either side — a generator can be neither picked up nor displaced by something
arriving. This is a balance rule with an architectural consequence, so it is worth stating why: swapping
is free, instant and unlimited in range, so a movable generator could always be parked one hop from the
frontier, every delivery would land at 9 of 10, and decay would never gate anything. Anchoring them is
what makes a pump chain the way to extend reach. It is a flag on the def rather than a check against the
generator's id, so a future block type declares its own answer without touching `World`.

---

## The tick

`World.tick()` runs at a fixed **10 Hz**, driven by an accumulator in `Main._process`. Four phases,
each completing across all entities before the next begins:

| Phase | What happens |
|---|---|
| **1. Resolve stats** | Rebuild the board-wide bonuses, then the effective-stats field, if anything moved. Nothing else in the tick may read a stat until this has run. |
| **2. Produce** | Every block on a mined cell gets `on_produce()`. Generators emit into `_spawn_queue`; upgraders spend banked charge into it. |
| **3. Transport** | Every live orb advances; on entering a new cell: decay → death check → `on_orb_pass()`. |
| **4. Deliver** | Orbs at the end of their route deposit their value or are absorbed by `on_orb_deliver()`, then die. |

Stats resolve **ahead of** produce rather than inside it, because a sphere's contribution is not
something that *happens* on a tick — it is a condition the rest of the tick runs under. Folded into the
produce loop, a generator's interval would depend on whether its sphere was iterated first, which is
precisely the order-dependence phase separation exists to prevent.

**Phase 1 has two sub-passes, and their order is forced.** Globals are summed first, then fields are
radiated. A Lens widens every sphere's radius, so the field cannot be built until the globals are known;
built the other way round, whether a sphere reached three hops would depend on whether the Lens happened
to be iterated first — the same order-dependence one level down. Within each sub-pass order is still
free, because both are sums of integers.

Then the spawn queue is appended (so **an orb never moves on the tick it is born**) and dead orbs are
compacted out.

### Why order does not matter

Phase separation alone gives order-independence, so there is **no double-buffering**:

- Generators read only their own timer.
- Delivery writes `unlock_progress` and block targets, and nothing in the produce phase reads either —
  produce has already run by then.
- Two orbs delivering into the same cell produce the same aggregate regardless of which lands first.
- The stats table is a **sum of integers per cell**, and `_resolve_stats()` rebuilds it wholesale rather
  than editing it, so it converges to the same table however `cell_ids` is iterated. This is the
  "recompute, never mutate incrementally" rule from *Extension points* paying for itself:
  `test_tick_order_independent` covers the phase for free, and there is no accumulated drift to chase.

`test_tick_order_independent` runs the same world with `cell_ids` reversed and asserts every observable
matches. **If you add a phase or a hook that reads state another block writes in the same phase, this
property breaks and that test is your warning.** The fix is a new phase, not a special case.

### The one deliver-phase write that another deliver step sees

Unaiming on mining is exactly the case above — a delivery mutates state a later delivery in the same
phase can observe — so it needs its own argument rather than the blanket one. It holds because the
unlock fires exactly once whichever orb crosses the threshold, and every orb bound for that cell then
ends up either delivered or cancelled with identical totals. For a cost-3 cell fed by two 5-value orbs
it is `delivered 3, wasted 2, cancelled 5` in either order, and that stays true whether the two orbs
share a generator or come from different ones, since one unlock releases both.

**The delivering orb must be marked dead *before* `_deliver` runs**, not after. It was launched by a
generator that is about to be unaimed, so left alive it is swept up by the cancel and counted again on
top of the delivery just recorded. This is not theoretical: restoring the old ordering breaks
`test_value_conservation` at tick 190 and fails three other tests with it.

---

## The value ledger

The correctness contract for the whole economy:

```
produced + restored  ==  delivered + wasted + decayed + cancelled + converted + in_flight
```

| Bucket | Meaning |
|---|---|
| `produced` | Value emitted by generators |
| `restored` | Value added by pumps. Uncapped, so this can exceed `produced` on a well-pumped route |
| `delivered` | Value that counted toward mining a cell |
| `wasted` | Arrived but had nowhere useful to go (overshoot, or a mined destination) |
| `decayed` | Lost to travel |
| `cancelled` | Destroyed because a route was retargeted, or its target got mined |
| `converted` | Consumed by an upgrader to mint a higher tier |
| `in_flight` | Sum of live orb values |

`evaporated_orbs` is a **count, not a value** — an evaporating orb is already at zero, so its loss is
fully accounted for under `decayed`.

`ledger_balanced()` checks this; `test_value_conservation` asserts it every tick for 2000 ticks while
pumps fire, cells unlock, orbs evaporate and routes change. It is also live in the HUD.

**Any new mechanic that creates or removes value must add a ledger bucket.** Pumps needed `restored`;
retargeting needed `cancelled`; the upgrader needed `converted`. If you skip this, the invariant
breaks and the suite fails loudly — which is the point.

**One scalar ledger still spans two tiers, and that is deliberate.** A conversion looks like it
should need per-tier accounting, and it does not: red absorbed into a charge bank has left
circulation for good, so it is an ordinary sink (`converted`), and the orange that comes back out
enters through `emit_orb` like any other emission, so it is an ordinary source (`produced`). The sum
is over *abstract value*, which is exactly what makes a leak between the two halves impossible to
hide — a behaviour that returns a non-zero amount from `on_orb_deliver` without calling
`absorb_value` fails `test_value_conservation` immediately. A per-tier readout is a HUD feature, not
a correctness one, and is deliberately not built.

**Spheres and challenges are the exception, and it is worth being precise about why.** Neither adds a
bucket, because neither is a new source of value — they move the dial on an existing one. A faster
generator emits more often and books every orb under `produced`; a stronger pump books the larger amount
under `restored`. The Surge looks like the case that should break this, since it raises what an orb is
*worth at birth*, but `emit_orb` books the value it actually emitted rather than `ORB_START_VALUE`, so
`produced` still records exactly what entered the economy. The rule to carry forward: a mechanic that
changes *how much flows through an existing path* is exempt; one that creates value outside `emit_orb`
or destroys it outside the existing sinks is not.

`cancelled` is fed by retargeting and by mining (which releases everything aimed at the cell). It is
*not* fed by swapping any more, even though `swap_blocks` still calls `_cancel_orbs_from` on both ends:
the generator is the only block that emits an orb and the only one that is anchored, so no orb's
`source_id` can name a cell a swap is allowed to touch. Those calls, and the `_drop_invalid_target`
pair beside them, are **dormant rather than dead** — a movable emitter (a distributor, an upgrader)
reactivates both the day it lands, and getting them wrong leaks value past the ledger instead of
failing loudly. They are commented as such at the call site.

---

## Calculations

All economy arithmetic is **integer**. No floats, no RNG, no seeded random anywhere in `sim/`.
Floats appear only in view interpolation and camera math.

### Constants (`sim/world.gd`)

| Constant | Value | Meaning |
|---|---|---|
| `TICK_HZ` | 10 | Simulation ticks per second |
| `TICKS_PER_HOP` | 10 | One second to cross one edge |
| `ORB_START_VALUE` | 10 | Base value of a fresh orb. **Not** a ceiling — see Travel. Also no longer the answer: a Surge raises it, so read `effective_orb_value()` |
| `DECAY_PER_HOP` | 1 | Value lost entering each new cell |

Per-type numbers live in `sim/block_catalog.gd`: generator `produce_interval` 20 ticks, pump
`restore_amount` 3, sphere `field_radius` 2 with `field_interval_bonus` −4 and `field_restore_bonus` +1,
upgrader `input_tier` red / `output_tier` orange with `upgrade_cost` 60, and the three challenges with
their `global_*` values.

`upgrade_cost` is a cooldown denominated in delivered value rather than ticks, which is the whole idea
of the type — a generator whose timer the player has to fill. It has no effective-stat reader because
nothing modifies it: a sphere has no interval or restore to change here, so it does nothing for a
converter. That is a deliberate gap, not an oversight — discounting `upgrade_cost` would be a third
field-bonus axis — and `test_sphere_does_nothing_for_an_upgrader` pins today's answer.

Every one of those is a **base**, not what the tick actually uses. There are three sanctioned readers and
nothing else: `effective_interval()`, `effective_restore()` and `effective_field_radius()`. Reading a
number off the def gets the un-upgraded board, which is a bug that shows up as the HUD disagreeing with
the simulation rather than as a crash.

`base_interval()` / `base_restore()` sit between the two: base plus any global, but before any field.
They exist so `is_boosted()` and the HUD's "(was N)" keep meaning *a sphere is doing this*. Measured
against the raw base instead, mining a Current would light the sphere ring on every pump on the board at
once.

**Unlock costs are not a simulation constant.** They are baked into `data/map_01.json` by
`tools/gen_map.py` as `COST_BASE × COST_GROWTH ^ (hops − 1)` — geometric in distance from the start, because
the player's reach compounds as pumps and spheres are found and a linear curve falls behind it. `sim/`
never sees the curve, only `cell.unlock_cost`, so retuning it is a generator edit and a regenerate.

**Orange cells are priced on a divided curve.** `gen_map.py` charges them
`COST_BASE × COST_GROWTH ^ (hops − 1) ÷ ORANGE_COST_DIVISOR`, because orange is minted from red at
`UPGRADE_COST` per orb: on the same curve it would be that whole multiple harder in real terms. The
divisor leaves the rim a step up rather than a different game. The challenge multiplier is applied
*before* the divisor, so a challenge stays six ordinary cells in whatever colour it is charged in.

⚠️ `gen_map.py` **duplicates** `ORB_START_VALUE`, `DECAY_PER_HOP`, `PUMP_RESTORE` and `UPGRADE_COST`
from the GDScript, with nothing but a comment holding them in sync. Change one of those four here and
the winnability proof silently starts describing a different game.

### Travel

On entering a new cell, in this exact order:

1. `value -= min(DECAY_PER_HOP, value)`, added to `decayed`
2. if `value <= 0` → evaporate, stop
3. if **not** the final cell → `on_orb_pass()`; a pump does `value += restore`, uncapped

Three rules encoded here, all load-bearing:

- **Decay resolves before the pump.** An orb entering a pump cell on its last point of value dies; it
  did not make it to the pump.
- **Blocks never act on an orb's final cell.** Without this, a pump parked on a target would hand every
  delivery into it a free +3, and the best place for every pump would be obvious.
- **There is no ceiling.** Pumps add a flat amount and stack, so an orb can arrive worth more than it
  launched with. `ORB_START_VALUE` is a starting value, not a maximum; the name says so because the
  clamp it used to describe is gone, and a constant called `MAX` that is not one is a trap.

Net effect, and worth being precise because it is easy to get backwards:

- Arrival is **`effective_orb_value() − hops + restore × pumps_passed`**, and **spacing does not appear
  in it**. Two pumps three hops apart and the same two pumps four hops apart deliver the same value, as
  long as the orb lives.
- What spacing decides is **survival**. A pump cell nets `restore − 1` = +2 and a plain cell −1, so a
  chain holds indefinitely at ≤3 hops apart and bleeds a point per segment at 4 — over a long enough
  route, out. `test_pump_spacing_decides_survival_not_value` pins both halves.
- An unaided orb still survives **9 hops**, arriving with 1, and dies on the tenth. A mined Surge moves
  that to 14, which is the only thing in the game that changes unaided reach — every other buff works on
  what a route carries rather than on where a bare generator can get.

### Delivery

Into a locked cell **that accepts the orb's tier**: `used = min(unlock_remaining, orb.value)` →
`unlock_progress += used`; the remainder is `wasted`. At `unlock_progress >= unlock_cost` the cell is
mined through `Graph.unlock_cell()` and yields its buried block. Into a locked cell of the wrong
colour, the whole value is `wasted`. Into an already-mined cell, `on_orb_deliver` decides: whatever a
block there absorbs is taken, and the rest is `wasted`.

**The wrong-colour branch is dormant, not dead.** `set_target` refuses a tier mismatch up front and a
cell's required tier never changes, so nothing can currently reach it. It stays for the same reason
the `_cancel_orbs_from` calls in `swap_blocks` stay: the ledger's correctness must not rest on a
guarantee made two calls away, and a future emitter that picks its tier at run time would reach that
line on its first bug.

**Aiming has three rules, and two of them are the tier gate.** `World.can_aim_at()` is the single
verdict `set_target` enforces and the aim preview draws, so the board can never offer a route the
simulation is about to refuse:

| Target | Rule |
|---|---|
| Unroutable | Refused. Fog needs no special case — `find_path` will not route through it |
| Locked cell | Requires `target.required_tier == block.def.output_tier` |
| Mined cell with a matching intake | **Allowed** — the only way a generator ever feeds an upgrader |
| Mined cell, anything else | Refused, as before |

That third row is the one change to a long-standing rule. "A mined cell is never a target" was right
while nothing consumed resource; it is now the *default* rather than the rule, and the exception is
tested by `test_can_aim_a_generator_at_an_upgrader` on one side and
`test_cannot_aim_at_a_mined_cell_without_an_intake` on the other.

Mining an upgrader's cell still releases whatever was aimed at it — `_unaim_everything_targeting` is
unchanged — so finishing a cell hands back an idle generator exactly as it always did.

**Mining releases everything aimed at the cell.** A mined cell consumes nothing, so a block still
pointed at one is emitting pure waste. `_unaim_everything_targeting()` clears those targets and cancels
their in-flight orbs through the same `_cancel_orbs_from()` the player's own retarget uses — this is that
route ending, and *an orb belongs to the route that launched it*. Value only moves between existing
buckets, from `wasted` to `cancelled`, so **no new ledger bucket**. `set_target` refuses a mined target
for the same reason, or the player could immediately re-create the situation.

#### The delivery-event channel

Each delivery that counts records a `DeliveryEvent` — cell, amount, tier, tick — for the view to float
a `+N` over the cell. The amount is `used`, not `orb.value`, so the number on screen always matches the
progress arc's jump. **An upgrader's absorption records one too**, in the input tier, so a converter
charging up reads the same way a cell being mined does. Nothing is recorded for waste into a mined
cell with no intake, a missing destination, a wrong-colour arrival, or a zero amount.

This is a **pull channel, and the only data path out of `sim/`**: the simulation appends, and the view
drains through `take_delivery_events()`. No signals, no callbacks — `sim/` still names nothing in Godot.
Draining rather than clearing per tick is load-bearing, because a frame can advance the sim by many
ticks before it draws (three or so at speed 16, up to `MAX_TICKS_PER_FRAME` after a stall) and every
delivery in that window must survive to be shown. The list is capped at `MAX_DELIVERY_EVENTS` and evicts
oldest-first, because the headless suite runs thousands of ticks with nobody draining.

**The list is a presentation trace, not an economic observable, and sits outside the order-independence
contract.** It is order-dependent in its *contents*, not merely its order: two orbs of different tiers
landing on a cell with 3 remaining, each worth 5, record `(3, first)` and `(0, second)`, so which tier
gets the 3 depends on arrival order. No sort recovers that, and sorting would imply a property it only
half has. What does hold — and what `test_delivery_events_report_what_counted` pins — is that the
amounts **sum to `delivered + converted`**, since they are the same additions. That sum grew a term
when the upgrader landed, which is the shape to expect: every new *counted* destination adds one, and
a new wasted one adds none.

It stays **write-only from the simulation's side**. If any `sim/` code ever branches on it, iteration
order leaks out of presentation and into the economy, and `test_tick_order_independent` starts failing
intermittently. The ledger is untouched: this reads `used` on its way past and creates nothing, so
**no new bucket**.

### Discovery

A cell is **discovered** when it has been mined, or sits next to a mined one. `Graph.is_discovered()`
computes that from `neighbor_ids` on demand — it is **derived, never stored**, so there is nothing to
keep in sync, nothing extra to serialise, and no way for it to drift. Degree is at most six, so it is
cheaper than the lookup it would replace.

Discovery is **monotonic**: mining never reverses, so the discovered set only grows. Two guarantees
follow, and both are load-bearing.

- **A discovered target is always reachable.** The mined region grows connected outward from the start
  cell — only discovered cells can be aimed at, and only cells delivered into ever unlock — so
  `mined ∪ neighbours(mined)` is connected through mined cells. There is always a route between two
  discovered cells that stays inside the discovered set.
- **A valid route is never lost.** Discovery only adds cells, so a route that exists keeps existing.
  `_drop_invalid_target` can never unaim a block just because the fog moved.

### Pathing

BFS over unit edges — **distance is hop count only**, there are no edge weights. Neighbours are sorted
ascending at load, so among equally short routes the one through the lowest-id neighbour always wins.
This tie-break is fixed and tested: without it, decay outcomes would differ between runs and nothing
would be reproducible. It matters more on a hex lattice than it did on the old clustered map, because
six-way adjacency offers far more equally short routes — cell ids are assigned row-major, so the
tie-break resolves toward the row above, consistently and visibly.

**Routing is restricted to discovered cells.** Undiscovered ground is not a curtain drawn over the map,
it is an obstacle: orbs cannot cross it and the player cannot aim through it. The filter only removes
candidates from the expansion, never reorders them, so the tie-break and determinism are untouched.

**On the shipped hex map this never changes a route.** A scripted playthrough measures the restricted
and unrestricted routes as identical in **0 of 122** (generator, target) lookups: with six neighbours
the discovered region stays convex enough that the shortest path is already inside it. The old clustered
map detoured in 300 of 300, and that sentence used to live here — the lattice falsified it.

The restriction stays anyway, and is not merely defensive. It is what makes **aiming into the dark
illegal**, which is very much observable, and it is a simulation rule rather than a UI one: `set_target`
rejects a fogged target purely because `find_path` returns nothing. Were routing unrestricted, the fix
would have to be re-implemented in the view *and* in every command path. The measurement says the fog
detour is currently unreachable on this board, not that the rule is inert — a map with narrower
corridors would bring it straight back, which is why the guard test now builds its own graph instead of
relying on the shipped one.

`find_path_unrestricted()` ignores discovery and answers what the *map* is rather than what the player
has uncovered. Map validation needs it; the game never does. If a new caller reaches for it, that is a
strong sign it is about to leak.

**The path cache is no longer permanent.** Mining grows the discovered set and can open a shorter route,
so `Graph.unlock_cell()` clears `_path_cache`. This is the version stamp the teleport note below
anticipated, collapsed to a full clear because a cell unlocks at most once for the life of a game.

`unlock_cell()` is therefore **the only way to mine a cell**. The underlying `GraphCell.apply_unlock()`
is deliberately not called `unlock()`: Graph owns the cache, so Graph has to own the event that
invalidates it, and a call site that bypasses the funnel now fails loudly instead of silently serving
stale routes. `test_path_cache_invalidated_on_unlock` is the guard — without it nothing else in the
suite notices a stale cache.

Invalidation cannot disturb tick ordering. Cells unlock only in the deliver phase, and nothing in
deliver paths; `emit_orb` paths in produce, which runs earlier and unlocks nothing. So a clear can never
change a result *within* a tick — only routes computed on the next one.

### `projected_arrival()`

Walks the route applying the same decay/pump rules to answer "what would an orb arrive with?" — this
drives the HUD readout and the aim preview. It deliberately duplicates the transport logic, so
`test_projected_arrival_matches_reality` cross-checks it against real deliveries across 21 hop/pump
combinations. **Change transport, change this, or the test fails.**

The walk itself lives in `arrival_along(path)`, with `projected_arrival(from, to)` supplying the
discovered route. Map validation asks the same question about an unrestricted route, and splitting it
this way keeps that from becoming a *third* copy of the decay rules.

---

## Extension points

A block type declares its behaviour by overriding hooks on `BlockBehavior`. The tick iterates blocks and
calls hooks; it never switches on a block type. Adding a type that fits an existing hook is **two edits
and no engine change**: a behaviour script in `sim/behaviors/`, and an entry in `BlockCatalog`.

### Hooks that exist

| Hook | Phase | Implemented by |
|---|---|---|
| `on_produce(world, cell, block)` | Produce | Generator, Upgrader |
| `on_orb_pass(world, cell, orb)` | Transport | Pump |
| `on_orb_deliver(world, cell, orb) -> int` | Deliver | Upgrader |

**`on_orb_deliver` is the exact counterpart of `on_orb_pass`**: that hook sees every orb *except* the
one stopping here, this one sees only that orb. It fires only when the destination is already mined,
returns how much of the orb's value it absorbed, and the world wastes the remainder — so the default
of 0 is what every other type already wanted, and delivery into a mined cell keeps wasting exactly as
it did. A block opts into having an intake by overriding it, and nothing else changes.

An absorbing behaviour **must** book what it took through `world.absorb_value()`. There is no way to
return value here without it having come from somewhere, and skipping the call leaks straight past
the ledger.

**The upgrader is the first type with two hooks, and the split is load-bearing.** It absorbs in
deliver and emits in produce, one tick later, rather than emitting from inside `on_orb_deliver`.
Deliver runs *after* produce, so charge accrued on a tick is spent on the next one and no deliver
step ever reads state another deliver step wrote — which is the order-independence rule from the tick
section, honoured rather than excepted. Charge is a sum of integers, so two orbs landing in the same
tick commute.

**`SphereBehavior` overrides no hook, and that is not an omission.** A sphere does nothing in any phase;
it acts by *being somewhere*, and `_resolve_stats()` reads its position out of the graph. A block type
whose whole contribution is positional needs a catalog entry and a `field_*` set, not a hook — and it
never calls `mark_active()` either, because there is no instant to flash. The view draws its field
instead, which is the honest picture of what it is doing.

**`ChallengeBehavior` is the same shape one step further out**, and one behaviour serves all three
challenge types: they differ only in which `global_*` numbers their def carries, and none of that is
behaviour. A block whose contribution is *existential* rather than positional needs a catalog entry and
a `global_*` set. It never pulses either, and the board draws it as a permanent triangle rather than
flashing it.

**A behaviour that does something calls `block.mark_active(world.tick_count)`.** That is the whole
contract behind the board's activity pulse, and it is the behaviour's job because only the behaviour
knows what counts as acting: a generator is asked to produce every tick but fires on the twentieth, and
one whose target has gone unroutable does nothing at all — which is why `emit_orb` returns whether it
actually emitted. A new block type that skips this simply never pulses; nothing else breaks.

`last_active_tick` is order-independent for free, since every writer in a tick writes the same
`tick_count`. It lives on the block rather than the cell so a pulse follows a block through a swap.

### Hooks that do not exist yet

These are the known extension costs, so a future change is a decision rather than a surprise:

| Planned block | Needs | Notes |
|---|---|---|
| Distributor | Multiple output ports per block | `on_orb_deliver` exists; what is missing is a block aimed at more than one place |
| Upkeep | A cost side to the stat-resolve phase | The table exists; what is missing is a buff that has to be *paid* for. See below |
| Teleport | Mutable adjacency | Path cache is already invalidated on unlock; a teleport would extend that to placement |

**The stat-resolve phase exists**, built for the sphere and since extended for the challenges. It
resolves **two axes**, and which one a new buff belongs on is the first question to answer:

| Axis | Shape | Read by | Built for |
|---|---|---|---|
| `_field` | cell id → `StatBonus`, sparse | the block standing on that cell | Sphere |
| `_global` | one `GlobalBonus` for the board | every consumer, no cell required | Challenges |

The distinction is *where a bonus is read*, not how big it is. A field bonus is a fact about a position,
which is what makes placing a sphere a decision; a global is read by `emit_orb` with no cell in hand at
all, which is why challenges are anchored — there is no placement to get right, so leaving them movable
would add a chore rather than a choice. `radiates()` and `grants_global()` are the id-free predicates the
two sub-passes walk, in the same spirit as every other type test in the codebase.

Three rules it is built on, all load-bearing for anything added to it later:

- **Recomputed from scratch, never mutated incrementally.** `_resolve_stats()` throws `_field` away and
  walks every radiating block again. `cell.speed *= 1.2` on place and `/= 1.2` on remove drifts, and the
  wholesale rebuild is also what makes the phase order-independent.
- **Rebuilt lazily, and not only on the tick.** `mark_stats_dirty()` is called by anything that could
  have moved a block; `_ensure_stats()` also re-checks `graph.unlock_version`, so mining a cell that
  installs a sphere invalidates without anyone remembering to say so. The rebuild is driven from every
  *read*, not just the phase, because the HUD and aim preview query stats between ticks — a tick-only
  rebuild would quote stale numbers for up to a tenth of a second and disagree with the board.
- **Combination order is fixed in one place — now two.** `StatBonus.combine(base, delta, floor)` is
  still the only place a base meets a field, and it is still flat-only. The Lens is the game's first
  multiplicative buff and it deliberately does **not** live there: it scales a *field radius*, which is
  an input to building the field rather than a stat resolved against one, so folding it into `combine()`
  would put a cycle in the pass. It has its own fixed point instead, `GlobalBonus.scale_percent()`,
  which truncates — a radius is a whole number of hops or nothing. A future buff that scales a *stat*
  still belongs in `combine()`, extended to `(base + Σflat) × (1 + Σpct) × Πmult`.

A field ignores discovery but not lock state: a buried sphere radiates nothing, and beyond that a
sphere's field is a fact about the board rather than about what the player has uncovered. Making it
fog-dependent would add an invalidation edge to mining and let an unrelated dig several hops away blink
a bonus on and off.

**Upkeep is what the phase still cannot do**, and it introduces the only genuine feedback loop: a buff
that speeds up the generator feeding it. Resolve it by computing upkeep satisfaction from the
**previous** tick, and give it hysteresis, or a marginal upkeep will strobe its buff every tick.

---

## Determinism

The properties the tests protect, and what would break them:

| Property | Guaranteed by |
|---|---|
| Same map → same routes | BFS ascending-neighbour tie-break |
| Same inputs → same economy | Integer-only arithmetic, no RNG |
| Iteration order irrelevant | Phase separation |
| No value appears or vanishes | The ledger invariant |
| Same board → same visibility | Discovery derived from unlock state, never stored |
| Routes never silently stale | Cache cleared in `Graph.unlock_cell()`, the sole unlock funnel |
| Same board → same stats | `_field` rebuilt wholesale from integer sums, never edited in place |
| Same board → same globals | `_global` rebuilt the same way, in a sub-pass that runs before the field |
| Same deliveries → same conversion | Charge is an integer sum written in deliver and read in produce, one tick later |

Introducing RNG (a chance-based decay, a random event) would break save reproducibility and require a
seeded, serialised stream. Introducing floats into value arithmetic would break exact assertions.
Neither is forbidden, but both are architectural decisions, not implementation details.

---

## View and input

`Main` owns the `World`, accumulates real time, and steps the sim at a fixed rate; the view interpolates
between ticks with `render_alpha` so orbs glide rather than step. Rendering is immediate-mode — one
`_draw()` for the whole graph, one for all orbs, one for all floating text — rather than a node per
cell. Transient marks are no exception: a `+8` is an entry in a list, not a node spawned and freed.

**A locked cell is tinted by the tier it demands.** Fill, ring, cost label and unlock arc are all
struck from `Tiers.color_of(cell.required_tier)`, so a cell states its currency without being asked
and progress reads as that colour accumulating. The three blends are `static` and pure
(`_gate_fill`/`_gate_ring`/`_gate_label`), checked headlessly the way `triangle_points` is, and they
blend *toward* the neutral locked palette rather than using the tier colour raw — unmined ground has
to stay quieter than the blocks working on top of it. The unlock arc used to hardcode `Tiers.RED`;
that was the only place a tier was assumed rather than read.

**`render_alpha` smooths only what advances every tick.** Orb motion, a generator's cooldown arc and
the activity pulse's decay qualify; unlock progress does not, because it moves on deliveries — events
with no in-between state to reconstruct, whose animation is the floating number instead. **An
upgrader's charge arc is the same case**: `_cooldown_fraction` reuses the cooldown ring for it but
leaves alpha out, because charge moves on deliveries too. The cooldown
arc leans on this: `timer` resets to 0 on the tick it emits, so the raw ratio never reads full, and
`(timer + render_alpha) / interval` both smooths the 10 Hz stepping and closes that gap seamlessly.

**The activity pulse is derived, not pushed.** `GraphView` reads `tick_count - last_active_tick` and
fades a beat out over `PULSE_TICKS`, brightening the cell, thickening its ring and swelling its glyph.
Nothing is queued and nothing is drained, which is why this does not use the delivery-event channel:
pump passes are far more frequent than deliveries and would evict them from that buffer. A pulse only
ever needs the *last* time a block acted, so one int beats a queue — no cap, no overflow, and it
degrades correctly when a frame swallows many ticks. Measuring the fade in ticks rather than seconds is
deliberate: at 4× or 16× the board should visibly beat faster, because it is running faster.

**`Main` is the sole drainer of delivery events**, once per frame, and the only place the simulation is
translated into presentation. `FloatingTextLayer` therefore knows nothing about orbs, cells or ticks —
it takes a string, a colour, a position and an age, which is what keeps it reusable for the next thing
worth announcing. Draining in a `_draw()` would be a bug: the engine may run one more than once a frame.

**Fog is enforced in three places, and all three are needed.** `GraphView` skips undiscovered cells, and
skips any edge with an undiscovered end — a stub running off into the dark still says where the map
continues. `Main._cell_at` skips them too, so ground that is not drawn cannot be hovered or clicked;
without that, clicking empty space would be a way to probe for what is out there. The simulation itself
refuses to route through fog, which is what makes the rule real rather than cosmetic. Block glyphs come
from `BlockDef.icon_path` — a plain string, so `sim/` still names no Godot texture — drawn tinted with
`BlockDef.color`, which for a generator is its output tier's colour.

**A challenge cell is the one exception to "every cell is a circle"**, and the one place the fog gives
something away on purpose. `GraphCell.is_challenge()` is derived from the buried block rather than
stored, like `is_discovered()`, and it deliberately answers a **category and not an identity**: the view
learns the cell is worth a triangle and a steep price, and cannot learn which of the three it will get.
That is the whole design of the mechanic — knowing a hard thing is coming is the point, knowing what it
pays out would remove the reason to dig it — so the glyph stays the same question mark every other
unmined cell gets.

The triangle is drawn at `1.2 × CELL_RADIUS` circumradius, because an *inscribed* triangle covers well
under half a circle's area and would read as a smaller cell rather than a special one. It still fits
inside `Main._cell_at`'s `CELL_RADIUS * 1.35` hit test, so clicking one needs no change there. The
concentric arcs all assume a circle: the unlock arc moves outside the silhouette for these cells, and the
anchored ring is skipped because a circular ring inside a triangle reads as a stray mark.
`GraphView.triangle_points()` is static and pure so the geometry is checked headlessly, the same way
`OrbLayer`'s weave maths is.

**The idle indicator** sits bottom-right in the HUD: one button per block type that currently has
something idle, drawn from the same `icon_path` and `color` the board uses so the button and the cell it
sends you to read as the same object. Clicking calls `Main.focus_next_idle()`, which walks the type's
idle cells through `World.next_idle_after()`. The cycling lives in `World` rather than the view because
its awkward cases — wrapping, and a cursor left pointing at a cell that stopped being idle — are worth
testing, and in the view they would need a whole scene tree to reach. `Main` keeps only the cursor.

**The click-vs-drag handshake** is the one non-obvious piece. Left-drag pans and left-click selects, so
`camera_2d.gd` owns the verdict: it sets `panned` once a press moves past a threshold, and `Main`
selects on **release** only when `panned` is false. Motion events always precede the release in time, so
this does not depend on `_unhandled_input` tree order.

`camera_2d.gd` reads positions off the event and derives world coordinates from its own
`global_position`, not from the viewport's canvas transform or `get_screen_center_position()` — both are
refreshed a frame late, which silently breaks zoom-toward-cursor and makes the camera untestable.

---

## Testing

`./run_tests.sh` — headless, zero external dependencies, exits non-zero on failure. Tests run on the
first frame rather than in `_initialize()`, because nodes added during `_initialize` are not yet inside
the tree and the camera cases need viewport queries.

`tests/screenshot.gd` is a dev tool: boots the game, plays scripted moves, saves a PNG. Needs a
rendering context, so it cannot run headless.

The map is generated, not hand-written: `python3 tools/gen_map.py` regenerates `data/map_01.json` from a
fixed seed. Editing the JSON by hand is not the workflow — edit the generator.

**The generator proves the map is winnable by playing it.** Once generators are anchored, whether the
board can be finished stops being a property of its shape and becomes a question of *sequencing*: can
you bootstrap your way out to the next buried generator? No static measure answers that. With
generators spread evenly, nothing is ever more than five hops from one and the map completes with no
pumps at all — the old proxies (diameter, "some cells lie out of unaided range") pass happily while the
pumps do nothing.

So `gen_map.py` runs a greedy playthrough — mine what is reachable, collect what is buried, reposition
pumps freely, repeat — and asserts two things:

- **with pumps, every cell falls** → the map is winnable with generators anchored;
- **without pumps, it does not** → pumps are load-bearing rather than decorative.

The sim is deliberately *conservative*: it only ever takes the shortest discovered route and only counts
pumps it can place on that route's already-mined interior, mirroring `World.arrival_along`. Spheres and
challenges are ignored entirely, for the same reason — they only ever add power, so a board this clears
without them is one a player clears with them. A player has strictly more options, so if it clears the
board, a player can. Contents are **searched for** under those two conditions rather than hand-placed,
because no one can eyeball which cells satisfy them.

**Orange is modelled, and the asymmetry with spheres is the point.** A buff that only ever adds power
is safe to ignore; a *colour gate takes power away*, so a board that clears without counting it is no
evidence at all. `play()` therefore tracks which upgraders are **live** — mined, and with some owned
generator able to land red on them — and an orange cell needs a live upgrader plus a surviving orange
route out of it. Both legs are paid from **one shared pump budget**, which is what `leg()` exists for:
it returns the *cheapest* spend that lands an orb, so the red leg takes what it needs and the orange
leg gets the rest. Spending the whole budget twice would be a lie the moment a route has two halves.

`leg()` is exactly equivalent to the arrival test it replaced, so a board with no orange plays as it
always did — which is what let the shipped map keep its existing placement.

Upgraders get a **second search** rather than joining the first, and it also has two conditions. With
them the board must fall; without pumps it must still fail. That second one is not free and was
measured failing: five upgraders are five new places orange sets out from, and the first placement
found put the rim back inside unaided range, clearing the whole board with no pump ever placed.
`UPGRADER_STRANDED_TARGET` is 1 rather than `STRANDED_TARGET`'s 2 because upgraders push *against*
stranding — the generator placement is what makes pumps load-bearing, and the upgraders only have to
avoid undoing it. Asking for 2 leaves the search grinding all `SEARCH_TRIES` for a property no
assertion needs.

**The new draws take a separate RNG stream** (`SEED + 1`), opened only after the main stream has
finished every placement it owns. Orange was added to the shipped board rather than used as an excuse
to roll a new one, and a single draw taken from the main stream would have shifted every generator,
pump, sphere and challenge on the map.

**`play()` also ignores unlock cost entirely** — it asks only whether an orb can arrive with anything at
all. That is what makes `CHALLENGE_COST_MULTIPLIER` and `ORANGE_COST_DIVISOR` safe to retune: an
expensive cell is slow, not unreachable, and the winnability assertion still means what it says. It is
also the thing to remember before adding a mechanic that could make a cell genuinely *unmineable* —
the orange gate is exactly such a mechanic, which is why it is modelled rather than ignored.

Challenges are drawn after the search, from fixed hop bands, and get two assertions of their own: one of
each on the board, at strictly increasing distance from the start. Both are re-checked against the
shipped JSON by `test_shipped_map_challenges_are_unique_and_ordered`, so a stale or hand-edited map fails
loudly rather than quietly granting a buff twice.

**`GENERATOR_COUNT` is the constant that fights the second assertion, and it is nearly spent.** Every
anchored generator added shrinks the region no generator already reaches unaided, so stranding anything
gets rarer: measured over 500 random placements, 14.6% strand at least one cell at five generators and
1.2% at ten, and the most any placement strands falls from 4 to 2. The board currently ships at ten, so
`STRANDED_TARGET` — the search's early-exit floor, not a guarantee — had to come down to 2 with it.
Leave it above what the generator count can reach and the search never exits early, grinding all 20,000
candidates and taking minutes rather than a fraction of a second. **Raise `GENERATOR_COUNT` again and
the assertion becomes unsatisfiable**; density belongs in pumps and spheres, which are movable anyway.

---

## Deliberately not built

Named so they are visible decisions rather than oversights:

- **Save/load.** Cheap to add — sim state is plain data by construction.
- **Orb merging and MultiMesh rendering.** A single `_draw()` handles hundreds of orbs. Integer decay is
  linear, so merging same-tier/same-edge/same-destination orbs stays valid whenever it is needed.
- **Stored discovery.** Derived from unlock state instead. Only worth revisiting if a mechanic uncovers
  a cell *without* mining next to it — orbs scouting a route, say — since that could not be derived.
- **Congestion.** Edges are stateless; any number of orbs may occupy one.
