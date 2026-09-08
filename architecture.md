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
| `sim/graph.gd` | Adjacency, discovery, restricted BFS, the simple-path rule, path cache, `unlock_cell()`, teleport links, `nearest_discovered()` | GraphCell |
| `sim/graph_cell.gd` | One position: lock state, cost, contents, `apply_unlock()` | Block, BlockCatalog |
| `sim/block.gd` | An installed block: def + target (or ports) + timer + last-active tick + the auto-aim pin | BlockDef, BlockPort |
| `sim/block_port.gd` | One output of a multi-output block: a target and its waypoints | — |
| `sim/block_def.gd` | Static per-type data (Resource) | BlockBehavior, Tiers |
| `sim/block_catalog.gd` | Every block type, in one place | BlockDef, behaviours |
| `sim/behaviors/*.gd` | Per-type logic, at most one hook each — except the upgrader, which has two, and three types (sphere, challenge, upkeep) which override none. The amplifier is the one whose hook does no arithmetic | GraphCell, Block, Orb |
| `sim/stat_bonus.gd` | One cell's summed field bonuses, how a base combines with them, the one increased-rate division and the one percentage-of rounding | — |
| `sim/global_bonus.gd` | The board's summed challenge bonuses, and the one percentage scale | — |
| `sim/orb.gd` | A packet in flight: value, launch value, route, progress | Tiers |
| `sim/delivery_event.gd` | One recorded delivery: cell, amount, tier, tick | Tiers |
| `sim/map_loader.gd` | JSON → Graph; `line_graph()` for tests | Graph, GraphCell, BlockCatalog |
| `sim/tiers.gd` | Seven tiers, red → purple, names and colours | — |
| `scenes/Main.gd` | Owns World, drives the fixed tick, routes input | sim, view, HUD |
| `scenes/camera_2d.gd` | Pan/zoom, the click-vs-drag verdict, and the visible world rect | — |
| `scenes/view/GraphView.gd` | Draws edges, cells, routes, previews | sim (read-only) |
| `scenes/view/OrbLayer.gd` | Draws orbs, interpolated between ticks | sim (read-only) |
| `scenes/view/SplashLayer.gd` | Expanding shards and a ring at a delivery; knows only a position, a colour and an age | — |
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
currency is expressed, and it is worth saying why it is not a stockpile. Value in Spread is
never banked — it is emitted, routed, and spent on arrival — so there is nowhere for a "balance" to
live. A currency is therefore a fact about *what a cell will take*, and the board is the ledger.

Unlike `initial_block_id`, `required_tier` is **not concealed**: the view tints a locked cell by it.
That leaks nothing the fog is there to protect, because it describes the *price* and not the prize —
the glyph stays the same question mark every unmined cell gets.

`initial_block_id` and `block` are separate fields because they diverge the moment the player swaps.
`initial_block_id` is **concealed until the cell is mined** — a locked cell draws a question mark — so
nothing outside `apply_unlock()` reads it. Presentation asks `block`; the view must never reach for
`initial_block_id`, or it will draw the answer to something the player is meant to discover.

### Block families

**There is no single generator type. There are seven, one per tier, six upgraders, one per step of
the ladder, and seven compressors, one per colour.** `BlockCatalog` builds both families in a loop rather than declaring them one at a
time, so a tier added to `Tiers` cannot arrive without the generator that emits it. Ids are
`generator_<tier name>`, `upgrader_<output tier name>` and `compressor_<tier name>`;
`BlockCatalog.generator_id(tier)`, `upgrader_id(tier)` and `compressor_id(tier)` are the only
sanctioned way to name one. The compressor family has seven rather than six because it does not climb
the ladder — it takes a colour and hands the same colour back — so unlike the upgraders it has a red
member.

`BlockCatalog.GENERATOR` and `UPGRADER` survive as **aliases** for the red generator and the
red → orange upgrader, because "a generator" unqualified still means the one the game opens with.

⚠️ **Nothing may identify a generator by id any more.** A scan matching `BlockCatalog.GENERATOR`
counts a seventh of the board's sources and passes quietly on a map with one red generator on it —
which is exactly what two shipped-map tests used to do. `BlockDef.produces()` is the id-free
predicate to use, beside the `converts()` / `radiates()` / `has_intake()` family it was added to.

**A generator's colour reaches the orb through its def and nowhere else.** `emit_orb` takes a tier
from its caller, and every caller passes `def.output_tier` — so a family member wired to the wrong
tier emits the wrong colour, and the only symptom is a cell that mysteriously refuses to open.
`test_a_generator_of_every_colour_emits_its_own_tier` is what catches that.

**Blocks are never created or destroyed at runtime.** `apply_unlock()` is the only constructor, and
swapping is the only way to relocate one. The map therefore fixes the supply of generators and pumps,
which is what makes placement a real decision.

**And generators are never relocated at all.** `BlockDef.movable` is false for every generator, and
`can_swap` refuses from either side — a generator can be neither picked up nor displaced by something
arriving. This is a balance rule with an architectural consequence, so it is worth stating why: swapping
is free, instant and unlimited in range, so a movable generator could always be parked one hop from the
frontier, every delivery would land at the full launch value, and decay would never gate anything. Anchoring them is
what makes a pump chain the way to extend reach. It is a flag on the def rather than a check against the
generator's id, so a future block type declares its own answer without touching `World`.

---

## The tick

`World.tick()` runs at a fixed **10 Hz**, driven by an accumulator in `Main._process`. Five phases,
each completing across all entities before the next begins:

| Phase | What happens |
|---|---|
| **0. Upkeep** | Every upkeep block burns its drain from its bank and updates its on/off latch. Nothing else in the tick may read a stat until this *and* phase 1 have run. |
| **1. Resolve stats** | Rebuild the board-wide bonuses, then the effective-stats field, if anything moved. Nothing else in the tick may read a stat until this has run. |
| **2. Produce** | Every block on a mined cell gets `on_produce()`. Generators emit into `_spawn_queue`; upgraders spend banked charge into it. |
| **3. Transport** | Every live orb advances; on entering a new cell: destination check → decay → death check → `on_orb_pass()`. |
| **4. Deliver** | Orbs at the end of their route deposit their value or are absorbed by `on_orb_deliver()`, then die. |

Stats resolve **ahead of** produce rather than inside it, because a sphere's contribution is not
something that *happens* on a tick — it is a condition the rest of the tick runs under. Folded into the
produce loop, a generator's interval would depend on whether its sphere was iterated first, which is
precisely the order-dependence phase separation exists to prevent. The upgrader reads a stat in the same
phase now — a sphere discounts its `upgrade_cost` — and it is covered by the same ordering for the same
reason.

**Phase 0 exists because the drain is neither a stat nor a hook**, and the two things it cannot be are
worth naming separately:

- It **cannot** live inside `_resolve_stats()`. That has to stay a pure read of board state, because it
  is rebuilt lazily from *every* effective-stat read — including the HUD's and the aim preview's,
  between ticks, several times a frame. A resolve that also drained would charge the player once per
  redraw.
- It **cannot** live in `on_produce()` either. A generator asked to produce before the upkeep block
  drained would read a different interval than one asked after, so the tick's result would depend on
  `cell_ids` order. This is the "the fix is a new phase, not a special case" rule below, taken.

**Phase 0 must not read an effective stat.** It reads only each block's own `charge` and flat constants
off its def, so order within the phase is free. A drain that consulted `effective_*` would resolve
`_global` from a `fuelled` set that later blocks in the same phase are still flipping — the Lens/sphere
ordering bug one level down. *"Make the drain cheaper near a sphere"* is the obvious future edit that
would break this silently, which is why the constraint is written at the function.

The bank phase 0 reads was last written by the **previous** tick's deliver phase, which is how upkeep
satisfaction ends up computed from the previous tick — the same latency shape as the upgrader's
deliver-then-produce split.

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
- The upkeep drain reads and writes only its own block's `charge` and `fuelled`, and its latch is an
  integer comparison, so the set of fuelled blocks converges the same way however `cell_ids` runs.
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

Mining is exactly the case above — a delivery mutates state a later delivery in the same phase can
observe — so it needs its own argument rather than the blanket one. A later orb bound for the same cell
now finds it **mined** rather than locked, and delivers into the mined branch instead of the unlock one.

It holds because `delivered` is capped by `unlock_remaining()` and everything the cap turns away wastes.
For a cell with 8 remaining fed by orbs worth 5 and 10: taking the 5 first gives `delivered 5`, then
`delivered 3, wasted 7`; taking the 10 first gives `delivered 8, wasted 2`, then the 5 lands on a mined
cell and wastes entirely. Both come to `delivered 8, wasted 7`. The unlock fires exactly once whichever
orb crosses the threshold, and it releases every block feeding the cell regardless of which generator
each orb came from.

The delivering orb is still marked dead *before* `_deliver` runs. That used to be load-bearing — the
unaim cascade would otherwise sweep the still-live orb into a cancel and count it twice — and with
nothing cancelling any more the order is free either way.

---

## The value ledger

The correctness contract for the whole economy:

```
produced + restored
  ==  delivered + wasted + decayed + converted + burned + in_flight
```

| Bucket | Meaning |
|---|---|
| `produced` | Value emitted by generators |
| `restored` | Value added in transport by pumps and amplifiers. Uncapped, so this can exceed `produced` on a well-supported route |
| `delivered` | Value that counted toward mining a cell |
| `wasted` | Arrived but had nowhere useful to go (overshoot, or a mined destination) |
| `decayed` | Lost to travel |
| `converted` | Consumed by an upgrader or a compressor to mint a new orb — a higher tier, or the same tier at a larger size |
| `burned` | Consumed by an upkeep block to hold a board-wide bonus up |
| `in_flight` | Sum of live orb values |

`evaporated_orbs` is a **count, not a value** — an evaporating orb is already at zero, so its loss is
fully accounted for under `decayed`.

`ledger_balanced()` checks this; `test_value_conservation` asserts it every tick for 2000 ticks while
pumps fire, cells unlock, orbs evaporate, routes change and an upkeep block runs itself dry. It is also
live in the HUD.

**Any new mechanic that creates or removes value must add a ledger bucket.** Pumps needed `restored`;
the upgrader needed `converted`; upkeep needed `burned`. If you skip this, the invariant breaks and the
suite fails loudly — which is the point.

**And a bucket goes when its sink does.** `cancelled` existed for exactly one mechanic — destroying
in-flight orbs when their route changed — and left with it. Nothing else ever wrote to it, so the term
simply came out of the sum. A permanently-zero bucket is worse than no bucket: it reads as a sink that
happens to be quiet rather than one that no longer exists.

**The compressor needs no bucket either, and it is the clearest case of the rule.** It banks
`compress_cost` (booked `converted` through `absorb_value`) and emits one orb worth all of it (booked
`produced` through `emit_orb`). Same in as out. The ledger is over *abstract value* and is tier-blind,
so "same colour in, same colour out" is not a special case — it is the upgrader's accounting with the
colour change taken out, which is exactly why it needed no ledger work at all.

What a compressor changes is not how much value exists but **how many orbs it is spread across**, and
that is worth stating because it is the whole mechanic: decay is charged per orb entering a cell, not
per unit of value, so ten orbs worth 10 each all die over twenty hops while one orb worth 100 arrives
with 82. That asymmetry was in the economy from the day `DECAY_PER_HOP` was written; the compressor is
only the thing that lets a player act on it. `test_compression_beats_decay_over_a_long_haul` measures
both halves.

**Both banks are booked at intake, and both are therefore outside the ledger.** An upgrader's `charge`
and an upkeep block's fuel are recorded the moment an orb lands — to `converted` and `burned`
respectively — so the drain that spends them tick by tick touches no bucket at all. That is what keeps
the invariant a flat scalar sum rather than needing a `banked` term summed across every block.

**A capped bank splits its overshoot, and the split costs the ledger nothing.** This used to be written
here as an argument that both banks were *forced* to be uncapped — that a cap would have to divide an
arrival between two buckets on a path where the behaviour returns a single number. That was wrong, and
the upgrader's cap is what showed it: the hook returns the amount it *took*, `_deliver` books
`orb.value - taken` to `wasted`, and one orb lands in two buckets with no new machinery at all. The
number the behaviour returns was always the split.

So the two banks now differ, **by choice rather than by force**:

- The **upgrader** holds room for exactly one output orb, against `effective_upgrade_cost`. Overflow
  wastes. Uncapped, a converter nothing was aimed away from stockpiled hundreds of value that bought
  nothing, since only one orb leaves per tick regardless; capped, that same red is visibly wasted, which
  is the honest reading of a line pointed at a full bank.
- The **upkeep block** stays uncapped, because over-feeding one is the mechanic. Its bank is run time,
  and a battery with a lid is just a smaller battery.

**Waypoints add no bucket, and they are the cleanest example of the exemption rule.** Bending a route
changes how many cells an orb crosses and how many pumps it meets, so it moves value between `decayed`
and `restored` and changes what lands — but every point of it goes through paths that already exist.
Nothing is created outside `emit_orb` and nothing is destroyed outside the existing sinks. That is also
why the one abuse they did open — lapping a pump corridor — had to be closed in the *router* rather than
with a bucket: every point of it was already booked correctly.

**One scalar ledger spans all seven tiers, and that is deliberate.** A conversion looks like it
should need per-tier accounting, and it does not: a colour absorbed into a charge bank has left
circulation for good, so it is an ordinary sink (`converted`), and the colour that comes back out
enters through `emit_orb` like any other emission, so it is an ordinary source (`produced`). A chain
of converters is just that pair repeated, which is why the ladder needed no ledger work at all. The sum
is over *abstract value*, which is exactly what makes a leak between the two halves impossible to
hide — a behaviour that returns a non-zero amount from `on_orb_deliver` without calling
`absorb_value` fails `test_value_conservation` immediately. A per-tier readout is a HUD feature, not
a correctness one, and is deliberately not built.

**Spheres, challenges and the upkeep bonus are the exception, and it is worth being precise about why.**
None adds a bucket, because none is a new source of value — they move the dial on an existing one. A
faster generator emits more often and books every orb under `produced`; a stronger pump books the larger
amount under `restored`. Upkeep is the interesting case, because it does both: its *bonus* is exempt for
exactly this reason, while its *fuel* is a genuine new sink and gets `burned`. Two halves of one block,
on opposite sides of the rule. The Surge looks like the case that should break this, since it raises what an orb is
*worth at birth*, but `emit_orb` books the value it actually emitted rather than `ORB_START_VALUE`, so
`produced` still records exactly what entered the economy. It now has a **second** effect for the same
reason it needs no bucket: a pump restores a percentage of the launch value, so a richer orb is pumped
harder, and every point of that lands in `restored` on the existing path. The rule to carry forward: a mechanic that
changes *how much flows through an existing path* is exempt; one that creates value outside `emit_orb`
or destroys it outside the existing sinks is not.

**An orb is committed once launched, and this is the rule the ledger got simpler for.** Its path is
resolved at `emit_orb` and never revisited: retargeting, rebending, swapping and mining all change what
the *next* orb does and nothing about the ones already crossing the board. So there is no way to destroy
an orb between launch and arrival, and every one of them ends in an existing sink — delivered, wasted,
converted, burned, or decayed to nothing. That is what removed `cancelled` rather than merely emptying
it.

The `_drop_invalid_target` pair in `swap_blocks` survives on its own account and is still **dormant
rather than dead**: a block can land on the very cell it was aiming at, which `set_target` refuses on the
way in and this catches on the way out. It revalidates a whole waypoint chain rather than just the
endpoints and drops target and via together, but it is unreachable while the generator is the only block
that both emits and is anchored.

**The destination guard in transport is the third of these.** Nothing acts on an orb's destination
whenever it is reached, not merely when the walk ends there. The case that forced it — a bent route
crossing its own destination on the way out to a waypoint — is now unreachable, because such a route is
not a simple path and is refused. The guard stays for the same reason the wrong-colour branch does: a
pump on a crossed destination would inflate `restored`, and the ledger's correctness must not rest on a
guarantee made two calls away in the router.

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
| `DECAY_PER_HOP` | 1 | Value lost entering each new cell the orb *crosses*. Its destination is not one of them |
| `MAX_WAYPOINTS` | 4 | How many cells one route may be forced through. A balance cap, not a UI one — see Travel |
| `MAX_ORB_VALUE` | 1e9 | Ceiling on one orb's value, applied wherever amplifiers compound. A legibility guard, not a balance cap — see the amplifier note under Travel |

Per-type numbers live in `sim/block_catalog.gd`: every generator `produce_interval` 20 ticks, pump
`restore_percent` 20, amplifier `amplify_percent` 50 (which is also `AMPLIFY_PERCENT`, the
economy-wide number `World` resolves the exponent from), every compressor `compress_cost` 100,
sphere `field_radius` 2 with `field_rate_percent` +25,
`field_charge_percent` +25 and `field_restore_percent` +10,
the upgrader family with `upgrade_cost` 60 at every step, upkeep `input_tier` red with
`upkeep_drain` 1, `upkeep_reserve` 200 and `global_rate_percent` +25, and the three challenge types with
their `global_*` values.

`upkeep_reserve` is a **threshold, not a cap**, and the ratio `reserve / drain` is the dwell time — 200
ticks, so a marginal block cannot flicker its bonus faster than once every 20 seconds. `+25%`
deliberately matches the sphere's `field_rate_percent`: an upkeep block is a sphere for the whole board,
as long as it is paid for, and because both are rates they share one divisor rather than compounding.

`upgrade_cost` is a cooldown denominated in delivered value rather than ticks, which is the whole idea
of the type — a generator whose timer the player has to fill. A sphere therefore speeds a converter up
by making it *cost less*: `field_charge_percent` is an increased charge rate resolved through the same
`apply_rate()` the interval uses. It is its own field rather than a second reader of
`field_rate_percent`, so generator speed and converter cost can be tuned apart. This replaces a
deliberate gap — a sphere used to do nothing at all for an upgrader — and
`test_sphere_discounts_an_upgrader` pins the new answer.

**Both speed buffs are *increased rates*, not flat deltas, and that is the load-bearing shape.** A stat
resolves as `base ÷ (1 + Σincreased/100)`, which is asymptotic: bonuses stack forever and never reach
zero. Flat tick subtraction needed a floor to stop it hitting zero, and that floor made every buff past
the fourth worth exactly nothing. So `MIN_PRODUCE_INTERVAL` (now 1, was 5) and `MIN_UPGRADE_COST` are
**divide-by-zero guards, not balance caps** — on a base of 20 the first is +1900% away.

Every one of those is a **base**, not what the tick actually uses. There are four sanctioned readers and
nothing else: `effective_interval()`, `effective_restore_percent()`, `effective_upgrade_cost()` and
`effective_field_radius()`. Reading a
number off the def gets the un-upgraded board, which is a bug that shows up as the HUD disagreeing with
the simulation rather than as a crash. `World.charge_meter_max()` is the fifth for the view's arc —
`BlockDef.charge_meter_max()` is its un-buffed baseline.

`base_interval()` / `base_restore_percent()` / `base_upgrade_cost()` sit between the two: base plus any
global, but before any field.
They exist so `is_boosted()` and the HUD's "(was N)" keep meaning *a sphere is doing this*. Measured
against the raw base instead, mining a Current would light the sphere ring on every pump on the board at
once.

⚠️ `base_interval()` is **not** an input to `effective_interval()` any more, and the reason is the
formula. Rates sum before they divide, so the global and the field are added and applied once —
`20 × 100 / 150 = 13` for a sphere on a board with an upkeep block lit, where dividing twice would
truncate twice and give 12. The two functions read the same raw base independently.
`test_sphere_still_pays_off_under_upkeep` pins it. (`base_upgrade_cost()` has no global to fold in at
all, so it stays a plain read of the def.)

**Unlock costs are not a simulation constant.** They are baked into `data/map_01.json` by
`tools/gen_map.py` as `COST_BASE × COST_GROWTH ^ (hops − 1)` — geometric in distance from the start, because
the player's reach compounds as pumps and spheres are found and a linear curve falls behind it. `sim/`
never sees the curve, only `cell.unlock_cost`, so retuning it is a generator edit and a regenerate.

**Every colour above red is priced on a divided curve.** `gen_map.py` charges those cells
`COST_BASE × COST_GROWTH ^ (hops − 1) ÷ DEEP_TIER_COST_DIVISOR`. The divisor used to be a generator
headcount — two anchored sources per deep colour against red's four — and with `GENERATOR_COUNTS` cut
to one apiece that reading would argue for a `÷ 4`. It stays at 2 on a different argument: a deep
colour's income is meant to arrive **up the ladder** through a converter, and the ring feeding that
converter is already priced on this same curve. Halving twice would discount the same thinness twice.
The challenge multiplier is applied *before* the divisor, so a challenge stays six ordinary cells in
whatever colour it is charged in.

⚠️ **`COST_GROWTH` is back at 2.0, on a board whose radius went 15 → 31.** Growth and radius are not
independent — the exponent is distance from the start — so restoring the rate *and* quadrupling the
board compounds. Measured on the shipped lattice:

| | before (1.6, r15) | now (2.0, r30) |
|---|---|---|
| hop 14 cell | 25,600 | 409,600 — what the *rim* used to cost |
| dearest cell | 42,222 | 13,421,772,800 |
| full clear | 619,707 | 226,901,320,400 |

This is an intended result, not an accident, and it is written down so nobody rediscovers it late: the
deep bands are very long, and `COST_GROWTH` is the one line to move first if they drag. Every value
stays well inside int64. `play()` ignores unlock cost entirely, so none of it can change what the
generator's playthrough reports — an expensive cell is slow, never unreachable.

⚠️ `gen_map.py` **duplicates** `ORB_START_VALUE`, `DECAY_PER_HOP` and `UPGRADE_COST` from the GDScript,
with nothing but a comment holding them in sync. Its `PUMP_RESTORE` is **no longer one of them**: the
simulation restores a percentage now, and that constant is frozen at the flat 3 the shipped map was
drawn under. It ranks candidate placements and nothing else — see *Testing*.

### Travel

On entering a new cell, in this exact order:

1. if this is the last cell of the route → **nothing happens**, stop. An orb is delivered *into* its
   destination rather than travelling through it, so the destination neither charges decay nor grants
   a pump
2. `value -= min(DECAY_PER_HOP, value)`, added to `decayed`
3. if `value <= 0` → evaporate, stop
4. `on_orb_pass()`; a pump does `value += restore_for(cell, orb.launch_value)`, uncapped, and an
   amplifier does `orb.amplifiers += 1` and **no arithmetic at all**

Four rules encoded here, all load-bearing:

- **The destination is not crossed.** Skipping the whole step rather than only the pump is what makes a
  neighbour one hop away receive the full launch value, and it means an orb that survived every cell on
  the way always arrives with something. Still stated about the *cell* rather than the position in the
  walk, even though the simple-path rule means a route can no longer reach its destination twice — see
  the dormant-guard note under the ledger.
- **Decay resolves before the pump.** An orb entering a pump cell on its last point of value dies; it
  did not make it to the pump.
- **There is no ceiling.** Pumps stack, so an orb can arrive worth more than it launched with.
  `ORB_START_VALUE` is a starting value, not a maximum; the name says so because the clamp it used to
  describe is gone, and a constant called `MAX` that is not one is a trap.
- **A pump restores a percentage of the orb's *launch* value, never of its current one.** `Orb`
  carries `launch_value`, stamped once in `emit_orb`, and `World.restore_for()` is the only place a
  percentage becomes value — rounding **up**, through `StatBonus.percent_of()`. Of the launch value
  because that is what makes pumps **additive**: three of them add 60% of what the orb was born with,
  in any order. A percentage of the current value would compound, and what each pump was worth would
  depend on which pumps the orb met first — order-dependence inside transport, which is exactly what
  the phase rules exist to prevent. It is also why a Surge mined mid-flight cannot re-price an orb
  already on its way.

#### The amplifier, and the one compounding term

**An amplifier multiplies where a pump adds, and it is resolved once at delivery rather than at the
cell it is met.** `AmplifierBehavior.on_orb_pass` increments `Orb.amplifiers` and does nothing else;
`World._apply_amplifiers` spends the whole exponent as the first statement of `_deliver`, before any
branch reads `orb.value`.

That split is the whole design, and the reason is the rule directly above. **Multiplication does not
commute with the pump's addition.** Met in the order pump-then-amplifier, an orb worth 5 becomes
`(5 + 2) × 1.5 = 10`; the other way round it becomes `5 × 1.5 + 2 = 9`. Applied where they were met,
arrival would therefore depend on which support the route happened to reach first — the exact
order-dependence this document cites when it rules out a compounding *pump* restore, arriving by a
different door. Counted in transport and spent at delivery, arrival is a function of
`(value, amplifiers)` and nothing else, so it is order-independent by construction.
`test_a_pump_and_an_amplifier_commute` is the assertion; it fails at 9 against 10.

This is the same dodge `StatBonus.apply_rate()` already uses one level up: **sum the terms, resolve
once.** The difference is only that a rate sums and an amplifier counts.

Three consequences worth stating, because each is a plausible wrong turn:

- **No new bucket.** An amplifier creates value in transport exactly as a pump does, so the gain goes
  through `restore_orb()` and books under `restored` — the *"a mechanic that changes how much flows
  through an existing path is exempt"* rule. It must go through `restore_orb` and not write
  `orb.value` directly, or the value and its booking drift apart and the invariant breaks.
- **The percentage is economy-wide, not per-def.** The orb carries a count, so by the time the
  exponent is spent there is no def left to read a percentage from. `BlockCatalog.AMPLIFY_PERCENT` is
  the number `World` uses; `BlockDef.amplify_percent` still declares it so `amplifies()` stays an
  id-free predicate and the HUD has something to print, and `test_amplifiers_share_one_percent` stops
  the two drifting. A second amplifier strength would have to compound against the first with nothing
  left to say in what order, so this is a real constraint rather than a shortcut.
- **A block may not both restore and amplify.** `arrival_along()` makes one pass and asks each cell
  both questions, so a def carrying both would be pumped *and* multiplied.
  `test_restore_and_amplify_are_disjoint` refuses that shape.

`MAX_ORB_VALUE` (1e9) clamps the compounding, through `World.clamp_orb_value()` and nowhere else, so
the simulation and the preview cannot clamp differently. It is a **legibility guard, not a balance
cap** — int64 has ample headroom and this sits well under the board's dearest cell — protecting the
HUD's `%d` and the splash's size ratio rather than the arithmetic.

Net effect, and worth being precise because it is easy to get backwards:

- Arrival is **`(effective_orb_value() − (hops − 1) + Σᵢ ceil(launch × pctᵢ ÷ 100)) × 1.5ⁿ`** over the
  pumps and the `n` amplifiers passed, and **spacing does not appear in it**. Two pumps three hops apart and the same two pumps four
  hops apart deliver the same value, as long as the orb lives. The `− 1` is the destination the orb
  never crosses. It is a **sum, not a product** — that is the launch-value rule above, restated as
  arithmetic.
- What spacing decides is **survival**. A bare pump on a plain orb restores 2, so a pump cell nets +1
  and a plain cell −1: a chain holds indefinitely at ≤2 hops apart and bleeds a point per segment at 3
  — over a long enough route, out. `test_pump_spacing_decides_survival_not_value` pins both halves.
  This tightened from 3 hops when the restore became a percentage, and it tightens or loosens again
  with anything that moves the launch value.
- An unaided orb still survives **10 hops**, arriving with 1, and dies on the eleventh. A mined Surge
  moves that to 15, which is still the only thing that changes *unaided* reach — but it is no longer
  the only place it acts, because a richer orb also makes every pump on its route restore more.

**Waypoints trade hops for pumps, and that is the whole mechanic.** A bent route is longer, so it decays
more; what it buys is passing through cells the shortest path missed. Since arrival counts pumps and not
spacing, one extra pump (+2 on a plain orb) pays for two extra hops (−2) and breaks even, and anything
past that is profit. The trade moves with the launch value: on a Surged board a pump is worth 3, and a
detour buys a hop more. This is why the shortest path is not automatically right, and it is the only reason the
honeycomb's detours were ever worth building.

⚠️ **A route may not cross itself, and that rule is what keeps the trade honest.** Folding back through
a corridor of pumps nets a pump's restore minus decay per pump per lap, and every point of it books
legitimately under
`restored` — so the **ledger will never catch it**. It used to be bounded only by `MAX_WAYPOINTS`, which
made that constant an economy number. `Graph.find_chain` now refuses the shape outright, so each pump on
a route pays exactly once and `MAX_WAYPOINTS` is back to being a limit on how complicated a route may
get. The simple-path rule is the load-bearing one; the cap is tuning.

### Delivery

Into a locked cell **that accepts the orb's tier**: `used = min(unlock_remaining, orb.value)` →
`unlock_progress += used`; the remainder is `wasted`. At `unlock_progress >= unlock_cost` the cell is
mined through `Graph.unlock_cell()` and yields its buried block. Into a locked cell of the wrong
colour, the whole value is `wasted`. Into an already-mined cell, `on_orb_deliver` decides: whatever a
block there absorbs is taken, and the rest is `wasted`.

**The wrong-colour branch is dormant, not dead.** `set_target` refuses a tier mismatch up front and a
cell's required tier never changes, so nothing can currently reach it. It stays for the same reason the
`_drop_invalid_target` calls in `swap_blocks` stay: the ledger's correctness must not rest on a
guarantee made two calls away, and a future emitter that picks its tier at run time would reach that
line on its first bug.

**Aiming has three rules, and two of them are the tier gate.** `World.can_aim_at()` is the single
verdict `set_target` enforces and the aim preview draws, so the board can never offer a route the
simulation is about to refuse:

| Target | Rule |
|---|---|
| Unroutable | Refused. Fog needs no special case — `find_path` will not route through it, and that covers a fogged *waypoint* as much as a fogged destination |
| Locked cell | Requires `target.required_tier == block.def.output_tier` |
| Mined cell with a matching intake | **Allowed** — how a generator feeds an upgrader or an upkeep block |
| Mined cell, anything else | Refused, as before |

**The tier rules apply to the destination only.** A waypoint is somewhere the orb passes *through*, and
a cell it merely crosses neither consumes it nor cares what colour it is — locked cells are traversable
and mined ones take nothing on the way past. So a red route may legally be bent through a purple cell.

**"A matching intake" now means four things**, which is why `accepts_delivery()` is built on
`has_intake()` = `converts() or burns_upkeep() or compresses() or distributes()` rather than on
`converts()` alone. A converter, an upkeep block, a compressor and a distributor are the four things on
the board with an appetite;
everything that asks about *delivery* wants the broader predicate. `converts()` itself is untouched,
because "turns one tier into another" is still a different question from "will absorb an arriving orb".

⚠️ **`has_intake()` is what makes a block aimable at all, and the failure is silent.** `can_aim_at`'s
mined-cell row is the only route by which anything may be pointed at mined ground, so a new intake type
missing from that list can never be fed: `set_target` refuses it, `on_orb_deliver` never fires, and the
block sits on the board doing nothing with no error anywhere. It is the first line to check when a new
intake type appears inert.

#### The compressor, and why two predicates had to diverge

`compresses()` is deliberately **not** a kind of `converts()`, and the split is the whole design of the
type. The two predicates are read by different machinery:

| Asks | Predicate | Compressor |
|---|---|---|
| may an orb be delivered here | `has_intake()` | **in** — or the block is unaimable and dead |
| does a sphere discount this bank | `converts()` → `effective_upgrade_cost()` | **out** — deliberately |

A compressor's bank **is** its output orb. Priced in `upgrade_cost` it would fall inside `converts()`
and pick up the sphere's `field_charge_percent`, so a sphere in range would make it bank *less* and
therefore emit a **smaller** orb — backwards for the one block whose entire purpose is a bigger one.
Its own `compress_cost` field, read straight off the def with no `effective_*` reader in front of it,
is what keeps output size a property of the block rather than of whatever happens to be parked beside
it. `test_a_sphere_does_nothing_to_a_compressor` pins it from both sides.

The price of that choice is paid in exactly two places, both of which have to name `compresses()`
explicitly: `has_intake()` above, and `BlockDef.charge_meter_max()`, which returns `compress_cost` so
the view's arc fills toward the right number. `World.charge_meter_max()` needed no change — its
`converts()` branch is skipped and it already falls through to the def.

**`emit_orb` gained a value override for this, and nothing else uses it.** Left at its default, an orb
is worth `effective_orb_value()` exactly as before; passed a number, it is worth that. Two deliberate
consequences:

- `launch_value` is stamped at the same number, so **every pump on the route restores a percentage of
  the bank**. A pump corridor is worth ten times as much under a compressed line as under an ordinary
  one. That is the launch-value rule working as designed, not a leak — and it is the main reason a
  compressor and a pump chain are complements rather than alternatives.
- `effective_orb_value()` is bypassed, so **a Surge does not touch a compressed orb.** A Surge raises
  what a *generator* launches with; a compressor launches with what was routed into it.
  `test_a_surge_does_not_reprice_a_compressed_orb` states it so it reads as a decision rather than an
  oversight.

That third row is the one change to a long-standing rule. "A mined cell is never a target" was right
while nothing consumed resource; it is now the *default* rather than the rule, and the exception is
tested by `test_can_aim_a_generator_at_an_upgrader` on one side and
`test_cannot_aim_at_a_mined_cell_without_an_intake` on the other.

Mining an upgrader's cell still releases whatever was aimed at it, so finishing a cell hands back an
idle generator exactly as it always did.

**Mining releases everything aimed at the cell — and nothing else.** A mined cell consumes nothing, so a
block still pointed at one is emitting pure waste. `_unaim_everything_targeting()` clears those targets,
which stops the *next* orb. Orbs already in the air are left entirely alone: they arrive at a cell that
is now mined, do nothing, and their value books under `wasted` on the ordinary delivery path. That is
the whole of the cascade, and it is why no bucket is needed for it. `set_target` refuses a mined target
for the same reason the unaim exists, or the player could immediately re-create the situation.

The one exception is the intake. An orb landing on a freshly mined **upgrader or upkeep block** is
banked rather than wasted, which matters most in exactly this window — the orbs that finished the dig
are followed by more already on their way, and throwing them out at the moment the converter came online
would be a cruel reading of the rule. `test_an_orb_still_feeds_an_upgrader_mined_under_it` pins it.

#### Auto-aim, and the pin

Aiming is the command the player gives most often and the one that carries a decision least often:
the answer is nearly always *the nearest cell this block's colour can open*, and the unaim cascade
above asks the question again every time the frontier moves. `World.auto_aim` gives that answer for
every aimable block the player has not answered it for themselves.

**It lives in `World`, and that is the one place player-facing mode state does.** Pause, speed and
the half-drawn waypoint chain are all on `Main`, because none of them writes simulation state; this
one writes block targets, so it is a command rather than a view mode, and putting it in the scene
tree would hang a headless-untestable branch in front of `set_target`.

**`Block.pinned` is the override, and it costs nothing to expire.** `World.set_target` records it
(`by_player`, defaulting true — `apply_auto_aim` is the one caller passing false), and
`Block.clear_target()` releases it alongside the target and the via-list, which the three of them
now are: one decision. So *"a manual aim lasts until its cell is mined"* is not a rule anything
implements. `_unaim_everything_targeting` already calls `clear_target()`, so mining a pinned
block's destination hands it straight back to auto-aim on the way past. There is no expiry to
schedule and no flag to remember to reset.

⚠️ **The pin is recorded ahead of `set_target`'s same-target early-out**, not after it.
Right-clicking the cell a block is *already* auto-aimed at is a real command — "hold this one" —
and it is the natural way to ask for it. Recorded after the early-out, that click would silently do
nothing. `test_pinning_survives_re_aiming_at_the_auto_target` is the guard.

**`auto_target_for()` walks `Graph.nearest_discovered()`**, which searches discovered cells
nearest-first using `_bfs`'s expansion rule to the letter — `neighbor_ids` ascending, undiscovered
skipped. That sameness is load-bearing rather than tidy: auto-aim's idea of "nearest" and
`find_path`'s have to be one idea, or the board picks a target the router then reaches the long way
round. `can_aim_at` stays the **single verdict** on each candidate, so auto-aim can never offer a
route the simulation is about to refuse; the two cheap tests in front of it (mined, wrong colour)
are a cost filter and not a second rule.

It **answers on the first hit** rather than enumerating the reachable set and filtering afterwards,
and on this board that is the difference between a feature and a hitch: with 760 of 950 cells mined
and 32 aimable blocks, a full pass costs **1.2 ms** returning early against **23 ms** enumerating.
The discovered set grows to most of the map while the answer stays a few hops out, so the cost has
to scale with the distance to the answer rather than with how much has been dug. The worst case is
unchanged and is worth naming: a source whose colour has nothing left within reach still walks
everything it can see, every time, and returns -1 — which is also the shape to watch if a deep
colour's sources ever start idling in numbers.

**It is a wholesale recompute, and event-driven — never per tick.** Three call sites, all existing
events: the unlock cascade in `_deliver` (after the unaim, or it would leave alone the very blocks
that unaim just freed), `swap_blocks` (a teleporter moving changes what is nearest board-wide), and
`set_auto_aim(true)`. A per-tick pass would run a BFS per aimable block ten times a second for an
answer that had not changed — the same argument `resolve_links()` is built on.

That it recomputes rather than edits is what makes it safe inside the deliver phase, which is the
one place a write can be observed by a later step of the same phase. Two cells mined on one tick
each run the pass, and both orders converge on the targets the final board implies.
`test_auto_aim_is_order_independent` runs a busy board with `cell_ids` reversed and compares every
target and pin.

**No ledger bucket and no new phase.** Auto-aim decides where an orb is sent, not whether one
exists: everything it does goes through `set_target` and then `emit_orb` like any hand-drawn route.
It is the *"a mechanic that changes how much flows through an existing path is exempt"* rule with
even less to argue about than usual — it does not change how much flows either.

Two deliberate asymmetries. Turning the mode **on** picks up only what is idle, because every
existing aim counts as a pin: auto-aim may decline to draw a route, but it must never take one
away. Turning it **off** likewise unaims nothing — the routes it drew are routes the player is
watching work, and confiscating them on the way out would make the toggle something to be afraid of
rather than something to try.

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
amounts **sum to `delivered + converted + burned`**, since they are the same additions. That sum grew a term
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
- **A direct route is never lost.** Discovery only adds cells, so a route that exists keeps existing.
  `_drop_invalid_target` can never unaim an unbent block just because the fog moved.
- **A waypointed route's length is monotonically non-increasing.** Each leg is a shortest path and
  discovery only grows, so uncovering ground can shorten a leg but never lengthen or break one. This is
  what makes "a via-list needs no invalidation" true rather than merely convenient: the route is
  re-resolved from the waypoints at every emission, and the answer can only improve.
  `test_waypoint_route_reresolves_as_fog_lifts` pins it.
- **A waypointed route can, however, be invalidated by the simple-path rule.** A leg that shortens as
  the fog lifts may newly overlap another leg, and the route is then refused. This is the one place
  discovery can take something away, and it is left to happen rather than repaired: `emit_orb` returns
  false, the block idles, and the idle indicator surfaces it. Auto-unaiming or silently re-routing
  would hand the player a route they did not draw, which is the same argument written at
  `_drop_invalid_target`.

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

**`find_chain(from, stops)` bends a route through chosen cells**, and is deliberately the thinnest
thing that could work: it concatenates one ordinary `find_path` per leg and drops each leg's duplicated
first element. `find_path_via(from, via, to)` is just `find_chain(from, via + [to])`. Four consequences
worth writing down.

- **A route is a simple path.** A walk that would re-enter a cell it has already crossed is refused —
  `find_chain` returns empty, exactly as it does for an unroutable leg. This is a **simulation rule**,
  and it lives here and nowhere else: `can_aim_at`, `set_target`, `block_route`, `emit_orb`,
  `_drop_invalid_target`, the HUD readout and the aim preview all reach a route through this function,
  so a crossing route is simply unroutable to every one of them.
- **The existing `_path_cache` serves it with no key change.** Every leg is a plain `(from, to)` pair,
  which is exactly what the `"%d:%d"` key already describes. A bent route costs the same lookups a
  direct one does, just more of them.
- **A waypoint is a constraint, not a stored path.** `Block.route_via` holds the *cells*, never the
  walk, and the route is rebuilt at every emission. Storing the resolved walk instead would freeze a
  route the day it was drawn and quietly keep taking the long way round after the fog lifted.
- **Determinism is untouched.** Each leg is the same deterministic BFS with the same ascending
  tie-break, so the same via-list on the same board always produces the same walk.

`legs_routable(from, stops)` asks the weaker question — do all the legs route, ignoring overlap — and
exists only so the view can tell the two refusals apart and say *"route crosses itself"* rather than
*"cannot reach"*. It is **not** a verdict on legality; `find_chain` remains the only one.

`World.normalize_via` stays syntactic tidy-up rather than a legality check. A via-list naming a cell
twice survives normalising and is then refused by the router. Dropping the repeat there instead would
silently rewrite the player's route into a different one that happens to be legal.

**`World.set_target_batch()` aims a group, and adds no verdict of its own.** It is a loop over
`set_target`, which is a loop over `can_aim_at` — the single verdict the preview draws. A batch that
filtered on a second rule is how the board starts offering a plan the simulation then refuses, one
source at a time. `count_routable_through` is the same shape over `can_route_through`.

**Partial success is the policy, and it lives in that one function.** A source that fails keeps the
target it already had rather than being unaimed: a group command may decline to change a route, but it
must never cost the player one they already had. The count it returns means "how many are aimed here
*now*", not "how many changed" — a source already on the route answers true, and the caller, which
clears its half-drawn chain on any success, wants the former.

Two things worth knowing about what can actually split a group. `can_aim_at` **never consults decay**,
so a route an orb will not survive is a legal aim drawn red, for a group exactly as for one block. And
a group shares a `def.id` and therefore an `output_tier`, so the destination's colour gate answers the
same for every member. What is left is reachability and the simple-path rule — the second being the
interesting one, since a *shared* waypoint chain is walkable from one source and doubles back from
another. The view's bar for drawing such a corner is therefore "somebody can walk it" rather than
"everybody can".

`World.resolve_route()` and `World.block_route()` wrap it, and they exist so `can_aim_at`, the HUD
readout and `GraphView`'s route drawing all ask the same question. Before waypoints each of those
independently recomputed a shortest path from the endpoints; with waypoints that would draw a straight
line underneath a bent one, and `graph.distance` would report the wrong hop count. Nothing outside
these wrappers should rebuild a block's route from its endpoints.

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

#### Teleport links — the one mutable part of the adjacency

**A teleport link is a real entry in `neighbor_ids`, and that is the entire
implementation.** `Graph.link_cells()` inserts each end into the other's neighbour array and re-sorts
ascending; `unlink_cells()` takes it out again. Everything downstream — `_bfs`, `find_chain`'s
no-crossing rule, the waypoint legs, `cells_within`, decay per hop, the path cache's `"from:to"` key —
keeps working with no notion that the edge is special, because to them it is not one. A teleport hop is
therefore **free in distance and not in decay**: it costs the same 1 value and the same 10 ticks as any
other hop, and what it saves is the twenty hops it stood in for.

Re-sorting on insert is load-bearing. Ascending `neighbor_ids` is the *only* tie-break BFS has, so an
edge appended out of order would make routes depend on when the link was formed —
`test_a_link_keeps_neighbours_sorted` pins it, because the failure is silent and surfaces only as a
route nobody can reproduce.

**Four things this needed that are not obvious:**

- **`topology_version`, and not `unlock_version`.** The latter means "which cells hold blocks" and its
  own comment says so. An edge appearing is a different event with different consequences — it can
  shorten a route *and* move a sphere's field — so `World._ensure_stats()` compares both. Reusing one
  counter for two meanings would make each of them lie about half of what it claimed.
- **`_link_edges` is a separate record, not a flag.** Teleporters are movable, so a pair can end up
  standing next door to each other. `link_cells` refuses to claim a pair the map already joins,
  otherwise the matching unlink would tear a real lattice edge out on the way past.
  `test_a_link_between_neighbours_never_eats_a_map_edge` is that case.
- **`World.resolve_links()` is event-driven, never per-tick.** It is called from the three places a
  teleporter can move — `_init` (the map may start with cells mined), the deliver phase's unlock, and
  `swap_blocks` — and it is public for the same reason `mark_stats_dirty()` is, because mining has
  callers outside `World`. A per-tick scan would clear `_path_cache` every tick whether or not anything
  moved, defeating it outright, and would put topology *inside* the tick where
  `test_tick_order_independent` would have something to say. Driven by events, the tick never sees a
  link form. Order-independence holds regardless: a group's pair is sorted before it is recorded.
- **Discovery answers itself.** A block exists only in a mined cell and a mined cell is discovered, and
  a group links only when *both* ends are mined — so the edge can never join anything the player has
  not already uncovered, and `is_discovered()` needed no change at all.

**A sphere's field reaches through a link, and that is intended rather than overlooked.** `cells_within`
walks `neighbor_ids`, so two cells thirty hops apart become one hop apart for the field as much as for
an orb. The alternative would be teaching the field walk which edges are "real", which is a distinction
the rest of the simulation deliberately does not make.

**Pairing is map-baked, not aimed**, and that is a dodge around the right-click gesture rather than a
limitation. `needs_target` and `movable` are disjoint across the catalog and the whole of
`Main._on_aim_click` rests on it, so a teleporter that had to be *pointed* at its partner would make one
click mean two things. Both ends share a `link_group` by sharing a **def** — one def per pair, buried
twice — so there is no per-block pairing state to keep in sync through a swap and nothing extra to
serialise.

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

The one thing it does *not* duplicate is the pump: both call `restore_for()`, because the rounding has
to match exactly or the preview promises a value the simulation will not land. The amplifier is the
case where duplication was unavoidable — the exponent is a loop over a count, and this walk has no orb
to carry one — so the two loops are written to truncate identically and both clamp through
`clamp_orb_value()`, with neither owning a rounding rule of its own. The amplifier axis was added to
`test_projected_arrival_matches_reality`'s grid for exactly that reason, mixed with pumps so a
resolution in the wrong order surfaces. It passes
`effective_orb_value()` as the launch value, which is what an orb emitted now would carry.

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
| `on_produce(world, cell, block)` | Produce | Generator, Upgrader, Compressor, Distributor |
| `on_orb_pass(world, cell, orb)` | Transport | Pump, Amplifier |
| `on_orb_deliver(world, cell, orb) -> int` | Deliver | Upgrader, Upkeep, Compressor, Distributor |

**`on_orb_deliver` is the exact counterpart of `on_orb_pass`**: that hook sees every orb *except* the
one stopping here, this one sees only that orb. It fires only when the destination is already mined,
returns how much of the orb's value it absorbed, and the world wastes the remainder — so the default
of 0 is what every other type already wanted, and delivery into a mined cell keeps wasting exactly as
it did. A block opts into having an intake by overriding it, and nothing else changes.

**The partial return is live rather than theoretical.** Every override used to answer `0` or
`orb.value`, so the `wasted += orb.value - taken` line in `_deliver` had never actually run with a
value strictly between the two. The upgrader's one-orb cap is the first real exerciser: it takes
`min(orb.value, room)` and the world wastes the rest. Nothing had to be built for it, which is the
point — the hook's signature had the split in it all along.

An absorbing behaviour **must** book what it took, through `world.absorb_value()` or
`world.burn_value()` depending on which sink it is. There is no way to return value here without it
having come from somewhere, and skipping the call leaks straight past the ledger.

**The compressor is the second type with two hooks, and it reuses the upgrader's split wholesale** —
absorb in deliver, emit in produce one tick later, for the same order-independence reason. It is worth
noting how little it needed: no new hook, no new bucket, no new phase. What it added was one field on
`BlockDef`, one predicate, one clause in `has_intake()`, one branch in `charge_meter_max()` and an
optional argument on `emit_orb`. That is close to the "two edits and no engine change" claim at the top
of this section, and it is the case that shows what the claim is worth.

**The upgrader is the first type with two hooks, and the split is load-bearing.** It absorbs in
deliver and emits in produce, one tick later, rather than emitting from inside `on_orb_deliver`.
Deliver runs *after* produce, so charge accrued on a tick is spent on the next one and no deliver
step ever reads state another deliver step wrote — which is the order-independence rule from the tick
section, honoured rather than excepted. Charge is a sum of integers, so two orbs landing in the same
tick commute.

**Its bank is capped at one orb's worth**, against `effective_upgrade_cost` rather than the def's
number, so "room for exactly one orb" stays true as spheres come and go. Order-independence survives
the cap: two orbs landing in one tick bank `min(sum, room)` in either order, so the totals commute and
only the split between the two *delivery events* depends on arrival order — which that channel already
declares about itself. The one asymmetry worth knowing is that a sphere arriving mid-fill lowers the
cap under a bank that is already larger; nothing is confiscated, and the block simply emits on the next
produce phase.

**`SphereBehavior` overrides no hook, and that is not an omission.** A sphere does nothing in any phase;
it acts by *being somewhere*, and `_resolve_stats()` reads its position out of the graph. A block type
whose whole contribution is positional needs a catalog entry and a `field_*` set, not a hook — and it
never calls `mark_active()` either, because there is no instant to flash. The view draws its field
instead, which is the honest picture of what it is doing.

**`UpkeepBehavior` overrides one hook and pointedly not the other two.** It takes `on_orb_deliver` to
fill its bank, and that is all. It has no `on_produce`, because its cost is a *phase* — it has to run
before any stat resolves, and a hook cannot. And it has no `on_orb_pass`, so an orb merely routed across
it is untouched — the same rule the upgrader has, now load-bearing rather than incidental: waypoints
make crossing a cell a deliberate act, and a block that skimmed passing traffic would turn every
corridor into a toll gate.

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

This table is currently **empty**. Both entries that stood in it — Distributor and Teleport — have
been built, and what each actually cost is recorded below so the next estimate has something to
calibrate against.

**The Distributor cost the most, and it is the one that changed a rule rather than extending one.**
`Block` had exactly one `target_id` and one `route_via`, and about a dozen functions assumed it. What
it needed:

- `BlockPort` (a target plus its waypoints), `Block.ports`, `Block.port_cursor`, `BlockDef.max_ports`
  and `has_ports()`.
- **A clean cut, not an alias.** Making a single-target block's fields read `ports[0]` was the obvious
  tidy-up and it is the wrong trade: every function that walks ports walks *all* of them anyway, so
  the alias buys nothing but a second source of truth. The twelve single-output types kept the fields
  they always had.
- `World.toggle_port` / `toggle_port_batch` / `block_routes` / `_drop_invalid_ports`, and a ports-aware
  `_unaim_everything_targeting`, which now drops only the port that fed the mined cell rather than the
  whole rotation.
- `Block.is_idle()`, so "no target" and "no ports" answer one question. Three call sites — the idle
  query, the HUD row, the board's label — would otherwise each have grown the branch.

⚠️ **And a third reading of right-click, which is the real architectural change.** `needs_target` and
`movable` used to be a *two-way* disjointness, and the whole of `Main._on_aim_click` rested on it. A
distributor is neither: it is anchored, and its ports are its aim. So the invariant is re-proved for
three states — `needs_target`, `movable`, `has_ports()` pairwise disjoint,
`test_target_movable_and_ports_are_pairwise_disjoint` — and the ports branch sits **ahead of** the swap
fallback in `_on_aim_click`. Placed after it, an anchored distributor would fall through to
`_on_swap_click`, `can_swap` would refuse it, and the block would be inert on the board with no error
anywhere.

**The gesture is a toggle**, which is what keeps it modeless: right-click a cell the block does not
feed and it becomes an output, right-click one it already feeds and that output goes. Removal
deliberately skips `can_aim_at` — a port whose destination has since become unroutable must still be
removable, or the player holds an output they can neither use nor clear.

⚠️ **`has_intake()` caught this type too.** A distributor sets `input_tier` but neither `upgrade_cost`
nor `compress_cost`, so it was outside `has_intake()` on the first pass and `can_aim_at` refused every
aim at it — nothing could feed it, `on_orb_deliver` never fired, and the tests read zeroes with no
error. `distributes()` is its entry, kept separate from `has_ports()` because one is about outputs and
the other about appetite. **That is twice in two stages**, which is why the predicate now carries a
warning at its definition.

**Teleport cost less than the row claimed.** It cost `Graph.link_cells`/`unlink_cells`, a `topology_version`
counter and `World.resolve_links()` — and, notably, *no* change to `_bfs`, `find_chain`, `cells_within`,
transport, decay or the path cache's key, because putting the link into `neighbor_ids` made it an
ordinary edge to all of them. The row predicted "mutable adjacency, extending the cache invalidation
from unlock to placement", which is exactly what it turned out to be.

**The stat-resolve phase exists**, built for the sphere and since extended for the challenges and the
upkeep block. It resolves **two axes**, and which one a new buff belongs on is the first question to
answer:

| Axis | Shape | Read by | Built for |
|---|---|---|---|
| `_field` | cell id → `StatBonus`, sparse | the block standing on that cell | Sphere |
| `_global` | one `GlobalBonus` for the board | every consumer, no cell required | Challenges, upkeep |

The distinction is *where a bonus is read*, not how big it is. A field bonus is a fact about a position,
which is what makes placing a sphere a decision; a global is read by `emit_orb` with no cell in hand at
all, which is why challenges are anchored — there is no placement to get right, so leaving them movable
would add a chore rather than a choice. `radiates()` and `grants_global()` are the id-free predicates the
two sub-passes walk, in the same spirit as every other type test in the codebase.

**Each axis carries the same kinds of term, and there is one deliberate gap.** `StatBonus` has a rate
(increased producer speed), a restore (flat percentage points) and a charge (increased converter speed);
`GlobalBonus` has the rate, the restore, an orb value and a field radius — but **no charge term**. A
sphere discounts a converter; nothing on the board discounts every converter at once, and an unused
field in a sum every consumer reads is clutter. The day something grants one, it lands there.

**`_global` gained a rate term for the upkeep block**, and with it the first global that is not
permanent. Every other global is a mined challenge and stays granted forever; an upkeep block
contributes only while its latch is on. So the sub-pass asks `Block.grants_global_now()` as well as
`BlockDef.grants_global()` — the def says *what* it would contribute, the block says *whether it is
contributing right now*. Keeping that on the block rather than in the pass is what stops a type test
leaking into `_resolve_stats`.

**Upkeep is also the one movable global, and it is not a contradiction.** The rule above says a
board-wide bonus needs no placement, so anchor it. Upkeep escapes that because it has to be *fed*: where
it sits decides whether a generator can reach it cheaply enough to keep it lit. Its placement decision
is about supply, not about coverage — which is a different question, and a real one.

`base_interval()` had to start applying the global, mirroring `base_restore_percent()`. Measured against
the raw base instead, lighting one upkeep block would put the sphere ring on every generator on the
board. `test_upkeep_buff_does_not_mark_generators_boosted` pins it. The floor it applies while doing so
used to matter for a second reason — a flat global drove the baseline negative while the effective value
clamped — which a rate cannot do, so that half is now belt and braces.

Four rules it is built on, all load-bearing for anything added to it later:

- **Recomputed from scratch, never mutated incrementally.** `_resolve_stats()` throws `_field` away and
  walks every radiating block again. `cell.speed *= 1.2` on place and `/= 1.2` on remove drifts, and the
  wholesale rebuild is also what makes the phase order-independent.
- **Rebuilt lazily, and not only on the tick.** `mark_stats_dirty()` is called by anything that could
  have moved a block; `_ensure_stats()` also re-checks `graph.unlock_version`, so mining a cell that
  installs a sphere invalidates without anyone remembering to say so. The rebuild is driven from every
  *read*, not just the phase, because the HUD and aim preview query stats between ticks — a tick-only
  rebuild would quote stale numbers for up to a tenth of a second and disagree with the board.
- **Rates sum before they divide, always.** Every source of an increased rate — a sphere's field, a
  lit upkeep block's global — is added into one total and applied once, so `effective_interval()` reads
  the *raw* base rather than `base_interval()`'s output. Two divisions truncate twice and give a
  different, order-dependent number: `20 × 100 / 150 = 13`, not `apply_rate(apply_rate(20, 25), 25) = 12`.
  This is the same "sum the points, apply once" rule the pump's restore already follows, and it is what
  keeps the rate axis order-independent. `test_sphere_still_pays_off_under_upkeep` pins it.
- **Combination order is fixed in one place — now four.** `StatBonus.combine(base, delta, floor)` is
  still the only place a base meets a *flat* field, and it is still flat-only.
  `StatBonus.apply_rate(base, increased, floor)` is the one place an increased rate becomes a stat:
  `base ÷ (1 + Σincreased/100)`, PoE's cooldown-recovery curve, chosen because it is asymptotic and so
  stacks without a cap. It truncates, which is the player's favour for both stats it serves — a shorter
  interval and a cheaper conversion are both good. It is deliberately **not** folded into `combine()`,
  for the same reason `scale_percent()` is not: it divides rather than scales, and one function
  answering two questions is how an ordering rule starts drifting.
  `StatBonus.percent_of(base, pct)`
  is the third: the one place a resolved percentage becomes value, used by the pump. It rounds **up**,
  deliberately the opposite of `scale_percent()` below — a radius is a whole number of hops and should
  only grow once the buff genuinely buys one, while a restore is value handed to the player and the
  fraction is better in their hands. Note what it is *not*: the pump's percentage is summed as
  percentage points through `combine()` like any other flat field, and only then applied once. Nothing
  compounds. The Lens is the game's first
  multiplicative buff and it deliberately does **not** live there: it scales a *field radius*, which is
  an input to building the field rather than a stat resolved against one, so folding it into `combine()`
  would put a cycle in the pass. It has its own fixed point instead, `GlobalBonus.scale_percent()`,
  which truncates — a radius is a whole number of hops or nothing. A future buff that scales a *stat*
  belongs in one of these four, not in a fifth: flat in `combine()`, increased-rate in `apply_rate()`.

A field ignores discovery but not lock state: a buried sphere radiates nothing, and beyond that a
sphere's field is a fact about the board rather than about what the player has uncovered. Making it
fog-dependent would add an invalidation edge to mining and let an unrelated dig several hops away blink
a bonus on and off.

**Upkeep is built, and it is the phase's cost side.** It sits in a phase of its own ahead of the resolve
(see *The tick*), reads satisfaction from the previous tick's bank, and latches rather than recomputing.

It does introduce the game's one genuine feedback loop — a buff that speeds up the generator feeding it —
and it is worth being precise about what that loop does and does not need, because the obvious worry is
the wrong one:

- **It converges, and hysteresis is not what makes it converge.** The bonus is a flat `−4` on interval
  and the interval floors, so the extra output an upkeep block's own feeder gains is 0.125 value/tick
  against a drain of 1.0 — a ratio well under one, and a series that dies fast. Nothing runs away even
  with every generator on the board aimed at it.
- **Hysteresis is for the boundary, not for divergence.** The real failure is a block held at
  *marginally* its drain rate flipping its bonus on and off every few ticks — which would change every
  generator's interval board-wide, several times a second, forever. The latch turns on at
  `upkeep_reserve` and off only at an empty bank, so the dwell is `reserve / drain` ticks and the
  boundary cannot chatter. `test_upkeep_hysteresis_does_not_strobe` holds a block at exactly that edge
  for 1000 ticks and asserts the board-wide interval changes at most once.

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
| Same board → same stats | `_field` rebuilt wholesale from integer sums, never edited in place, with each stat's rate summed and divided exactly once |
| Same board → same globals | `_global` rebuilt the same way, in a sub-pass that runs before the field |
| Same deliveries → same conversion | Charge is an integer sum written in deliver and read in produce, one tick later |
| Same board → same upkeep state | The drain and the latch are integer operations on each block's own bank, in a phase of their own that reads no stat |
| Same waypoints → same route | `find_chain` concatenates per-leg BFS, each with the unchanged ascending tie-break |
| Same route → same pumps | A pump restores a percentage of the orb's stamped `launch_value`, summed rather than compounded, rounded in one place |
| Same route → same amplifiers | The orb counts them in transport and `_deliver` spends the exponent once, so arrival is a function of `(value, count)` and never of the order the route met its support |
| A route never revisits a cell | `find_chain` refuses a walk that re-enters one, so every pump on a route pays once |
| Same fed distributor → same rotation | The port cursor is written and read only inside that block's own `on_produce`, so no other block in the phase can observe it — the position `timer` and `charge` are already in |
| Same board → same teleport links | A group's pair is sorted before it is recorded, and link edges are re-sorted into `neighbor_ids`, so BFS's tie-break is unchanged by one appearing |
| Same board → same auto-aim targets | `nearest_discovered` is the same BFS with the same ascending tie-break, and `apply_auto_aim` recomputes every unpinned block wholesale rather than editing, so the pass converges the same way however `cell_ids` runs |

Introducing RNG (a chance-based decay, a random event) would break save reproducibility and require a
seeded, serialised stream. Introducing floats into value arithmetic would break exact assertions.
Neither is forbidden, but both are architectural decisions, not implementation details.

---

## View and input

`Main` owns the `World`, accumulates real time, and steps the sim at a fixed rate; the view interpolates
between ticks with `render_alpha` so orbs glide rather than step. Rendering is immediate-mode — one
`_draw()` for the whole graph, one for all orbs, one for all floating text — rather than a node per
cell. Transient marks are no exception: a `+8` is an entry in a list, not a node spawned and freed.

**Colour on the board means exactly one thing: a resource tier.** The ground is onyx (set as the
project's `default_clear_color`), and everything that is not a tier — the edges between cells, an
empty cell, a locked cell's neutral base, and the pump, sphere and upkeep blocks, which act on orbs of
*every* colour — is struck from a neutral grey ramp. Seven hues on one board is where a stray
decorative colour starts lying, so the rule is enforced rather than merely written down:
`test_tier_tables_are_consistent` holds every tier above a saturation floor and apart in hue, and
`test_tierless_blocks_are_neutral` holds the other three below it. The pump was teal until a tier
took that colour.

The one sanctioned exception is **chrome**: a route line, the selection ring, the swap line and a
refusal. They are drawn over the board while the player is doing something and gone afterwards, and
they are never mistaken for a cell because they are never shaped like one — so they keep the
conventional colours, a warm refusal included.

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

**One drain now feeds two layers, which makes that rule sharper rather than softer.**
`_spawn_delivery_effects` turns each event into a splash *and* a number. A second drainer would not
halve the marks on screen — `take_delivery_events()` empties the buffer, so it would take all of one
kind and none of the other, and the board would show bursts with no numbers on them. `SplashLayer` is
the same shape as the text layer for the same reason: a position, a colour, a size and an age, with no
notion of what a delivery is. Neither layer is told whether the value went into an unlock, an upgrader's
bank or an upkeep block's fuel, because they are the same act — where it went is what the *cell* draws.

The splash is sized by `event.amount / effective_orb_value()`, clamped inside the layer. Measured
against what an orb launches with *now*, so a Surged board does not render every ordinary delivery at
maximum size, and clamped where it is drawn rather than where it is computed so the bound travels with
the geometry it protects.

⚠️ **`SplashLayer` is the one place in the project that calls `randf()`, and it must stay view-only.**
One angle per burst, so repeat deliveries at a cell do not look stamped. It feeds nothing but that
frame's drawing and no simulation state is derived from it, so the determinism table above is untouched
— `sim/` still has no RNG. A splash that *decided* something would put randomness back into the game.
Its geometry lives in three static pure functions (`shard_offset`, `ring_radius`, `fade`) for the same
reason `GraphView.triangle_points()` does: it is then checked headlessly rather than on a screenshot.

**Fog is enforced in three places, and all three are needed.** `GraphView` skips undiscovered cells, and
skips any edge with an undiscovered end — a stub running off into the dark still says where the map
continues. `Main._cell_at` skips them too, so ground that is not drawn cannot be hovered or clicked;
without that, clicking empty space would be a way to probe for what is out there. The simulation itself
refuses to route through fog, which is what makes the rule real rather than cosmetic. Block glyphs come
from `BlockDef.icon_path` — a plain string, so `sim/` still names no Godot texture — drawn tinted with
`BlockDef.color`, which for a generator is its output tier's colour.

⚠️ **That tinting imposes a hard requirement on the artwork, and it fails silently.** `_draw_icon`
recolours by *modulating*, so an icon must be white art on transparency and nothing else. The
game-icons.net download ships an opaque backing rect (`<path d="M0 0h512v512H0z"/>`) unless the
transparent option is taken, and a file that keeps it draws as a filled square with the glyph knocked
out of it — which is what two of the six shipped icons did. `assets/ATTRIBUTION.md` states the
invariant (exactly one `<path fill="#fff">`, on transparency, `0 0 512 512`) and is the thing to check
before wiring a new file into `BlockCatalog`. Nothing enforces it in code: a wrong path falls back to
`draw_rect`, and a wrong *background* is not detectable at all without looking at pixels.

**A challenge cell is the one exception to "every cell is a circle"**, and the one place the fog gives
something away on purpose. `GraphCell.is_challenge()` is derived from the buried block rather than
stored, like `is_discovered()`, and it deliberately answers a **category and not an identity**: the view
learns the cell is worth a triangle and a steep price, and cannot learn which of the three it will get.
That is the whole design of the mechanic — knowing a hard thing is coming is the point, knowing what it
pays out would remove the reason to dig it — so the glyph stays the same question mark every other
unmined cell gets.

**A challenge cell is drawn in the colour it demands, before and after mining.** Unmined, the rim
takes the gate colour *raw* where an ordinary cell gets `_gate_ring`'s muted blend — unmined ground is
deliberately quieter than the working board, and a challenge is the one thing under the fog that is
supposed to shout. Mined, it keeps the tier colour of its cell rather than taking its def's own, so
the monument stays tied to the band it came out of. That is a change: the rim used to be a fixed amber,
which made every challenge on the board look like a yellow-gated one and put a second, contradicting
colour rule on the cells that most need reading at a distance. The three types are told apart by name
in the panel, which is the right amount of information while their effects are still placeholders that
repeat in every band.

The triangle is drawn at `1.2 × CELL_RADIUS` circumradius, because an *inscribed* triangle covers well
under half a circle's area and would read as a smaller cell rather than a special one. It still fits
inside `Main._cell_at`'s `CELL_RADIUS * 1.35` hit test, so clicking one needs no change there. The
concentric arcs all assume a circle: the unlock arc moves outside the silhouette for these cells, and the
anchored ring is skipped because a circular ring inside a triangle reads as a stray mark.
`GraphView.triangle_points()` is static and pure so the geometry is checked headlessly, the same way
`OrbLayer`'s weave maths is.

**The idle indicator** sits bottom-right in the HUD: one button per block type that currently has
something idle, drawn from the same `icon_path` and `color` the board uses so the button and the cell it
sends you to read as the same object. There are up to **thirteen** of those types now — seven
generators and six upgraders — and the row's width is derived from that count rather than pinned, or a
late-game board runs it off the left edge of the screen. Clicking calls `Main.focus_next_idle()`, which walks the type's
idle cells through `World.next_idle_after()`. The cycling lives in `World` rather than the view because
its awkward cases — wrapping, and a cursor left pointing at a cell that stopped being idle — are worth
testing, and in the view they would need a whole scene tree to reach. `Main` keeps only the cursor.

**Right-click has no mode, and neither does anything else.** Left-click selects; **right-click acts on
the cell under the cursor**, and *which* act it is depends entirely on what is selected:

| Selected cell holds | Right-click | Shift+right-click |
|---|---|---|
| a block with `needs_target` | aim it here | extend the route through here |
| a block with ports | add this output, or drop it if already fed | extend the route through here, then add |
| a movable block, or nothing (mined) | swap contents with here | nothing |

Backspace undoes one waypoint and Esc clears the chain. There is no `aiming` flag, no `swapping` flag,
no Aim button, no Swap button and nothing to enter or cancel — the view and the HUD key off "does the
selected cell hold a block with `needs_target`", which is the whole of the state two flags used to
carry. The side panel now has **no buttons at all**, for the same reason the Aim button went: a
command that is one right-click on the board needs no widget to arm it.

**Auto-aim is the one mode, and the first row of that table is what makes it modeless anyway.** A
right-click that aims also **pins** — see *Auto-aim, and the pin* under Delivery — so the gesture
means the same thing whether the mode is on or off, and the override is expressed by doing the
thing rather than by leaving a mode first. It is also the one thing in the HUD that gets a button
despite the rule above, and for a stated reason: it is not a command on the selected cell but a
standing choice with no gesture of its own, so there is nowhere else for the player to learn it
exists. `[a]` is the key; the button (top-right, chrome-coloured, `toggle_mode`) has its pressed
state pushed from `World.auto_aim` every frame rather than trusted to itself, so the key and the
button cannot disagree.

⚠️ **That table is unambiguous only because `needs_target`, `movable` and `has_ports()` are pairwise
disjoint**, and the whole gesture rests on it. Generators, upgraders and compressors are aimable and
anchored; pump, amplifier, sphere, teleporter and upkeep are movable and take no target; a distributor
has ports and is neither; challenges are none of the three. Nothing answers to two, so no selection has
two readings of one click. It is a fact about several separately-written blocks of `BlockCatalog`,
which is exactly why it is pinned: `test_target_movable_and_ports_are_pairwise_disjoint` fails the day
a block type would make right-click mean two things.

The rule was **two-way until the distributor**, and widening it was the price of the type — see the
note under *Hooks that do not exist yet*. The ordering of the branches in `_on_aim_click` is load-bearing
for the same reason: ports before the swap fallback, or an anchored ported block is silently inert.

The view gets the same guarantee for free — `_draw_aim_preview` and `_draw_swap_preview` are mutually
exclusive by that same disjointness, so their order in `_draw()` arbitrates nothing and needs no
thought. Both are drawn live off the selection, because neither has a mode to wait for.

**Swapping is therefore unconfirmed and immediate**, which is a real cost worth stating: a right-click
with a pump selected moves it across the board with nothing to say yes to. What stands in for a
confirmation is that the board draws the line and the refusal *before* the click, `can_swap` refuses
everything anchored on either side, and a swap is undone by right-clicking back. The preview's
mined-cell guard is the one line to revisit if that turns out to be too little.

**Selection follows the block through a swap, which is what makes moves chain.** One right-click per
hop walks a pump across the board with no re-selecting in between; leaving the selection on the source
would have cost a click back for every move and given the gesture back half of what dropping the mode
bought. It follows the *block* and not the clicked cell, and the difference is the pull direction: a
push sends the block from the selection to the click, so the selection travels with it, while a pull
brings a block *to* the selection and leaves the clicked cell empty — chasing that cell would strand
the selection on nothing. `_on_swap_click` decides which it is before the swap, by whether the selected
cell had anything to give. The undo survives either way, since the cell you came from is the cell you
right-click to go back.

**Selection is one cell, or a group.** `Main.selected_id` is the selection, and `selected_ids` is the
group — empty in the ordinary case, and otherwise holding `selected_id` as its **first** entry. That
shape is chosen so nothing that inspects *one* cell had to learn about groups: `selected_cell()`, the
HUD's stat panel, the sphere-field focus and `tests/screenshot.gd` all still read the primary and are
right. A group of one is stored as no group, so "empty in the ordinary case" is literally true.

`Main.aim_targets()` is the one accessor every aim path goes through — the group when there is one,
the primary alone otherwise — so no command branches on group-versus-single. A batch of one resolves to
the call that was already there, which is why the single-selection behaviour is unchanged rather than
merely equivalent.

A group is formed by **double-clicking an aimable block**, and it takes every block sharing that
`def.id` **currently on screen**. Two scoping decisions, both deliberate:

- **`def.id`, not tier or "aimable".** The catalog registers one generator def per tier and one
  upgrader def per rung, so `def.id` *is* "same colour of generator", and the same rule picks up a rung
  of upgraders for free. It is a rule the player can state, which is what makes the resulting selection
  predictable.
- **On screen, not board-wide.** A group is something the player can see and check before committing;
  a board-wide select would rope in sources behind ground cleared twenty hops ago and re-aim them from
  a decision made off-screen. Zooming out is how the group is widened, which keeps "what will this
  affect" answerable by looking.

The split of where this lives follows the testability rule: the **rect query** is `World.cells_with_def_in_rect`,
beside `idle_cells_of`/`next_idle_after` and for the same stated reason, while the **rect itself** comes
from `camera_2d.visible_world_rect()`, because that script already owns the screen↔world bridge and is
the one piece of input the suite can drive. `Main` is left a thin caller with no geometry in it.

`Main.pending_via` is still a half-built command rather than simulation state, but it now behaves
differently in one way worth knowing: **a chain commits as it is drawn.** Every shift+right-click passes
the whole chain to `set_target`, and `normalize_via` drops the trailing entry that names the target — so
the moment a clicked cell is a legal destination the block aims there and orbs start flowing, and the
next shift-click pushes the destination further out while that cell falls back to being a waypoint. A
cell that cannot take an orb is refused by `set_target` and simply stays a pending waypoint. The view
never re-implements that verdict; it asks `can_route_through` for the chain's legality and lets
`set_target` decide the rest.

And it costs nothing already in the air. Each click re-commits the route, but an orb is committed once
launched, so the ones mid-journey finish the trip they started while only later ones take the new line.
Drawing a chain a corner at a time is therefore free — which is what makes committing on every click a
reasonable thing to do at all.

**There are two mouse handshakes, and both are non-obvious.**

**Click vs drag.** Left-drag pans and left-click selects, so `camera_2d.gd` owns the verdict: it sets
`panned` once a press moves past a threshold, and `Main` selects on **release** only when `panned` is
false. Motion events always precede the release in time, so this does not depend on `_unhandled_input`
tree order. Right-click acts on **press**, because it never pans and so has no verdict to wait for.

**Double-click vs click.** `double_click` is set on the **press** of the second click, and `Main`
selects on **release** — so a group has to be formed on that press, and the release trailing behind it
suppressed, or `_on_click` collapses the group straight back to one cell. Forming on the release
instead is not an option: the release carries no marker distinguishing it from any other.
`_suppress_next_click` is that one-shot flag.

⚠️ **It is cleared on *any* left release, before the `panned` test and whether or not it was set.** A
drag begun on the group-forming press never reaches the clear inside the `not panned` branch, so the
flag would stay armed and eat the next, unrelated click — a bug that would surface as "sometimes the
first click after using a group does nothing". The two handshakes stay independent because
`camera._begin_drag` resets `panned` on that same press, so dragging after forming a group pans the
board without dissolving it.

`camera_2d.gd` reads positions off the event and derives world coordinates from its own
`global_position`, not from the viewport's canvas transform or `get_screen_center_position()` — both are
refreshed a frame late, which silently breaks zoom-toward-cursor and makes the camera untestable.

---

## Testing

`./run_tests.sh` — headless, zero external dependencies, exits non-zero on failure. Tests run on the
first frame rather than in `_initialize()`, because nodes added during `_initialize` are not yet inside
the tree and the camera cases need viewport queries.

⚠️ **Nothing may loop over `cell_ids` twice.** The shipped map is 950 cells and
`find_path_unrestricted` is **uncached**, so an all-pairs loop is Θ(V³) in node visits — and it stays
*green* the whole time it is rotting, which is what makes this worth a warning rather than a note. Two
tests were written that way when the board was 230 cells and both had to be rebuilt when it grew:
`test_shipped_map_is_a_web`'s diameter is now a **double sweep** (two BFS, giving the lower bound its
`>=` assertion actually needs) and `test_path_determinism` checks the *mechanism* exhaustively — that
two loads agree on every cell's `neighbor_ids`, which is the only ordering input BFS has — and then
samples routes on a fixed stride. Together they went from eight minutes to under a second. The suite
prints a duration beside any test over `SLOW_TEST_MS` and names the slowest at the end, so the next one
announces itself instead of being found with a stopwatch.

**`Main`'s input has no headless coverage, and that shapes where new input logic goes.** The rule is to
push the part that can be tested down to something that can: the double-click group put its rect query
and its batch aim in `World` and its rect geometry on the camera, leaving `Main` a caller thin enough
to read. The same instinct is why the chain-aiming flow is pinned at the `World` level rather than
through the clicks that drive it. What is genuinely uncovered is then small and named — the two
handshakes and the preview drawing — rather than spread through a command path.

`tests/screenshot.gd` is a dev tool: boots the game, plays scripted moves, saves a PNG. Needs a
rendering context, so it cannot run headless.

The map is generated, not hand-written: `python3 tools/gen_map.py` regenerates `data/map_01.json` from a
fixed seed. Editing the JSON by hand is not the workflow — edit the generator.

**The generator places contents by playing the map.** Once generators are anchored, where a placement
leaves the player stops being a property of the board's shape and becomes a question of *sequencing*:
can you bootstrap your way out to the next buried generator? No static measure answers that. With
generators spread evenly, nothing is ever more than five hops from one and the map completes with no
pumps at all — the old proxies (diameter, "some cells lie out of unaided range") pass happily while the
pumps do nothing.

So `gen_map.py` runs a greedy playthrough — mine what is reachable, collect what is buried, reposition
pumps freely, repeat — and searches for a placement where the board clears with pumps and does not
clear without them. `generators` and `upgraders` are `{cell: tier}` maps throughout: which colour a
source emits is as much a part of a placement as where it sits.

⚠️ **It used to *assert* those two, and no longer does; they are printed.** Two reasons, and both
matter before re-arming them. The shipped board is known to clear, and the model's `PUMP_RESTORE` is a
frozen 3 rather than the simulation's percentage restore — so a failing assertion would mean the model
is stale, not that the map is broken. The constant is left frozen deliberately: it feeds the search
that chose the shipped generator, upgrader and challenge positions, and the search consumes the RNG
stream, so correcting it would reshuffle every placement on the board the next time anyone regenerates.
Re-arm the assertions only together with making `play()` mirror `World.arrival_along` again, and expect
a new map when you do.

The sim is deliberately *conservative*: it only ever takes the shortest discovered route and only counts
pumps it can place on that route's already-mined interior, mirroring `World.arrival_along`. Spheres,
challenges, amplifiers, compressors, distributors and teleporters are ignored entirely, for the same reason — they only ever add power, so a
board this clears without them is one a player clears with them. `place_amplifiers` therefore sits with
`place_spheres` outside the search rather than inside it, and its own constraint is a **depth floor**
rather than a reachability one: a multiplier scales what arrives, so it is strictly worse than the pump
it would be found instead of on the short routes of the opening, and `AMPLIFIER_MIN_HOPS` holds it out
past the red band so it surfaces at about the distance it starts winning.

`place_compressors` is drawn rather than searched for the same reason — a compressor carries value
further without creating any — but its constraint is the **deadlock rule**, and a strict one: a
compressor sits on a cell gated at *exactly* its own colour. Deeper is the deadlock proper, since a
compressor emits what it eats and a cell demanding the next colour up could not be paid for any earlier
than the block inside it would have helped. Shallower is merely wrong-headed — a red-carrying block
surfacing ten rings before there is a long red haul to carry. Asserted at the bottom of `main()` beside
the generator and upgrader rules, and re-checked on the shipped JSON by
`test_shipped_map_compressors_sit_in_their_own_band`. A player has strictly more options, so if it clears the
board, a player can. Waypoints are the same argument: the model always takes the shortest route, and a
player who can also bend one has strictly more options.

**Upkeep blocks are ignored too, and the argument for them is stronger than the sphere's.** A sphere is
skipped because it only ever adds power. An upkeep block's bonus is a shorter generator interval, and
`play()` ignores time entirely — it asks only whether an orb can *arrive*, never how often. So an
interval buff is not merely safe to ignore, it is **invisible to the model by construction**, and the
playthrough reports the same numbers with two of them on the board as with none. Contents are
**searched for** under those two conditions rather than hand-placed, because no one can eyeball which
cells satisfy them.

**The colour ladder is modelled, and the asymmetry with spheres is the point.** A buff that only ever
adds power is safe to ignore; a *colour gate takes power away*, so a board that clears without counting
it is no evidence at all. `play()` therefore resolves a **source table per tier**, in ascending order,
every round:

```
sources[T] = {cell: pump spend that keeps it fed}
  mined generators of tier T          -> 0
  mined upgraders with output tier T  -> cheapest chain out of sources[T-1]
```

A tier-T cell falls if some entry of `sources[T]` can land an orb on it with what is left of the pump
budget. Every leg is paid from **one shared budget**, which is what `leg()` exists for: it returns the
*cheapest* spend that lands an orb, so a converter three rungs up the ladder pays for every leg
beneath it. Spending the whole budget once per leg would be a lie the moment a route has two halves.

**`Router` memoises one BFS per source per round.** `leg()` used to run its own, which was affordable
at two tiers and a handful of sources; at seven tiers, twenty-eight sources and 950 cells the same BFS
was being recomputed thousands of times a round for an answer that had not changed. It is lazy, so a
round with no frontier cell of a given colour pays nothing for that colour's sources. This is what keeps
generation at about a second on the current board — without it a 4× map would have been minutes.

⚠️ **A new block type's placement call goes at the *end* of the sequence in `main()`, and this is not
a style preference.** Every placement draws from one seeded RNG stream, so a draw inserted before
`search_contents`, `search_upgraders` or `place_challenges` shifts every placement taken after it and
the next regenerate silently rehouses the whole board. Appended after `place_spheres` — with the
spheres folded into `taken` first — the existing placements keep their cells and the new type takes
what is left. `place_amplifiers` is the worked example: adding it moved **0** of the 471 blocks
already on the shipped map, and the playthrough's numbers (950/950 cleared, 523 stranded without
pumps, 128 on red generators alone) came back identical.

**The band table is decided before anything is placed**, and everything else is drawn against it. A
generator may not be buried behind a gate deeper than the colour it makes, and an upgrader may not be
buried behind one deeper than the colour it *eats* — the generalisation of the old "every buried
upgrader sits on a red cell" deadlock rule. Both searches need every cell's colour before they can
draw a single candidate, so `place_challenges` → `assign_tiers` → `search_contents` →
`search_upgraders` is a forced order rather than a stylistic one. (Challenges come first because
`assign_tiers` exempts them from the scatter and so has to be told where they are.)

**An upgrader has a second placement rule, and it is about legibility rather than deadlock.**
`UPGRADER_BAND_TAIL` holds each converter to the outer two hops of its *input* band. The deadlock rule
alone left an orange upgrader free to sit anywhere in red — hop 1 included, ten rings before the first
orange cell exists — so the player dug one out with nothing to point it at and no way to learn what it
was for. Since `SCATTER_DENSITY` promotes part of a band's last hop to the next colour, bounding the
placement to that tail makes a converter surface within a ring of its own output colour. Measured on
the shipped board: orange upgraders at hops 8-9 against the first orange cell at 9, yellow at 12-13
against 13, and so on to purple at 23-24 against 24. Asserted at the bottom of `main()` alongside the
deadlock rule, because it is exactly as easy to break by retuning `BAND_EDGES`.

**`SEARCH_TRIES` came down from 20,000 to 300, and it had to.** A playthrough costs something now, so
the search is a *ranking* with an early exit rather than a filter: it keeps the best draw on
`(cells cleared, cells stranded without pumps)` and ships it whether or not it hit the target. Nothing
downstream asserts on the result, which is what makes that safe.

**`play()` also ignores unlock cost entirely** — it asks only whether an orb can arrive with anything at
all. That is what makes `CHALLENGE_COST_MULTIPLIER` and `DEEP_TIER_COST_DIVISOR` safe to retune: an
expensive cell is slow, not unreachable, whatever the playthrough reports. It is
also the thing to remember before adding a mechanic that could make a cell genuinely *unmineable* —
a colour gate is exactly such a mechanic, which is why it is modelled rather than ignored.

⚠️ **One assertion was deleted rather than updated, and the reason matters.** The old board asserted
it could *not* be finished without upgraders — orange was minted and nothing else made it, so a
converter was a gate. Every colour has generators of its own now, so that assertion is false by
design. What replaced it is a printed number: how much of the board falls on **red generators alone**.
If that ever approaches the whole board, the six colours above red are decoration. It is a number
rather than an assertion for the same reason the other two are.

Challenges are drawn one of each **per colour band**, and the assertion moved with them: board-wide
uniqueness became per-band uniqueness, plus a check that each sits inside the band whose colour it
demands. `test_shipped_map_challenges_are_unique_per_band` re-checks it on the shipped JSON, so a
stale or hand-edited map fails loudly rather than quietly doubling a bonus inside one ring.

**`GENERATOR_COUNTS` no longer fights the stranding target the way `GENERATOR_COUNT` did.** Every
anchored generator added used to shrink the region nothing already reaches unaided: measured over 500
random placements, 14.6% strand at least one cell at five generators and 1.2% at ten. The board ships
ten now — four red and one of every other colour — and they are ten sources across seven colours, so a
purple generator cannot mine a red cell. The colour bands cut the other way, and on the current board
stranding is the normal case rather than the exception: **523 of 950 cells are unmineable without
pumps**, against 23 of 230 before. Cutting the deep colours to one generator each is most of that, and
it is the point of the cut — a colour with a single anchored source is a colour whose reach has to be
built rather than found.

**`SEARCH_TRIES` is still 300 and still costs almost nothing**, which is worth recording because a 4×
board looked certain to break it. Generation takes about a second. Both searches early-exit on
`(cleared == every cell, stranded ≥ STRANDED_TARGET)`, and on a board this size with pumps this
plentiful the first draw satisfies both — so the constant is a ceiling nothing currently approaches. It
becomes load-bearing again the moment a placement rule gets tight enough to reject draws.

---

## Deliberately not built

Named so they are visible decisions rather than oversights:

- **Save/load.** Cheap to add — sim state is plain data by construction, and every feature since has
  kept it that way: `Block.route_via` is a `PackedInt32Array` of cell ids, `Block.fuelled` is a bool and
  `Orb.launch_value` is an int, so none adds anything a serialiser would have to reconstruct.
- **Orb merging and MultiMesh rendering.** A single `_draw()` handles hundreds of orbs. Integer decay is
  linear, so merging same-tier/same-edge/same-destination orbs stays valid whenever it is needed.
- **Stored discovery.** Derived from unlock state instead. Only worth revisiting if a mechanic uncovers
  a cell *without* mining next to it — orbs scouting a route, say — since that could not be derived.
- **Congestion.** Edges are stateless; any number of orbs may occupy one.
