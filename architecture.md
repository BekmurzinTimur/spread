# Architecture

How Spread is put together: the modules, the calculations they own, and the contracts between them.
See `gamedesign.md` for what the game *is*; this is how it works.

---

## The one rule

**The simulation is not the scene tree.**

```
   scenes/  ──────────────►  sim/
   (Godot nodes, drawing,     (plain RefCounted, integer math,
    input, HUD)                no Node, no _process, no rendering)
```

The arrow points one way and never back. `sim/` must never reference a Godot node, a scene, a signal,
or `delta`. This is what makes the economy testable headlessly and deterministic across runs.

`MetaStore` uses `FileAccess`, which is none of those four. It is the only file the project writes.

The view reads simulation state and issues commands through `World`'s public methods. It never mutates
simulation state directly.

---

## Module map

| Module | Owns | Depends on |
|---|---|---|
| `sim/bands.gd` | Seven depth bands: names, colours, `band_of(hops)`, the board radius | — |
| `sim/rng.gd` | Stateless hash rolls. The only source of variance | — |
| `sim/hex_map.gd` | Builds the lattice into a `Graph`; scatters nodes from a run seed | Graph, GraphCell, Bands, Rng, NodeCatalog |
| `sim/graph.gd` | Cells, `cell_ids`, `mine_cell()`, the distance-from-mined field | GraphCell |
| `sim/graph_cell.gd` | One position: band, cost, progress, mined state, buried node, emit timer | NodeCatalog |
| `sim/node_type.gd` | Static data for one buff type | — |
| `sim/node_catalog.gd` | Every buff type and what a level of it is worth | NodeType, MetaState |
| `sim/buff_state.gd` | The run's buff tally, found and bought kept apart | NodeCatalog, MetaState |
| `sim/orb.gd` | A packet in flight: value, endpoints, crit flag | — |
| `sim/world.gd` | The tick, the frontier, the ledger, the band wall, the ram | everything in `sim/` |
| `sim/delivery_event.gd` | One recorded delivery, for the view | Bands |
| `sim/meta_state.gd` | What the player carries between runs: one wallet, purchase levels | MetaUpgrades |
| `sim/meta_upgrade.gd` | Static per-upgrade data — `NodeType` one level up | — |
| `sim/meta_upgrades.gd` | Every upgrade, in one place — `NodeCatalog` one level up | MetaUpgrade, NodeCatalog, Bands |
| `sim/meta_store.gd` | `MetaState` ⇄ JSON on disk | MetaState |
| `scenes/Main.gd` | Owns World, drives the fixed tick, routes input, ascension | sim, view, HUD |
| `scenes/camera_2d.gd` | Pan/zoom, the click-vs-drag verdict, the visible world rect | — |
| `scenes/view/GraphView.gd` | Draws edges, cells, prices, node glows, the ram preview and beam | sim (read-only) |
| `scenes/view/OrbLayer.gd` | Draws orbs, interpolated between ticks | sim (read-only) |
| `scenes/view/SplashLayer.gd` | Expanding shards and a ring; knows a position, a colour and an age | — |
| `scenes/view/FloatingTextLayer.gd` | Rising, fading text; knows only strings and colours | — |
| `scenes/ui/HUD.gd` | Four readouts, the shop button, and the tooltips | Main, sim (read-only) |
| `scenes/ui/AscensionShop.gd` | The project's one modal: wallet, cards, Ascend | Main, sim (read-only) |
| `scenes/ui/format.gd` | Presentation helpers shared by the HUD and the shop | — |
| `tests/run_tests.gd` | Headless suite, exits non-zero on failure | everything |

**The board is arithmetic, not data.** `HexMap.build()` generates a hex disc of radius `Bands.MAX_HOPS`
with six-way adjacency, band by hex distance, and cost `50 × hops³`. There is no map file and no
generator script. Only node placement is randomised, and it is a pure function of the run seed.

---

## The tick

`World.tick()` runs at a fixed **10 Hz**, driven by an accumulator in `Main._process`. Four phases,
each completing across all cells before the next begins:

| Phase | What happens |
|---|---|
| **0. Resolve frontier** | Rebuild the frontier set and the generator count if the board or the purchases changed. |
| **1. Produce** | Every frontier cell advances its own timer; at zero it rolls crit and split and emits at its chosen neighbour. |
| **2. Transport** | Every live orb advances one tick toward its target. |
| **3. Deliver** | Orbs that have crossed deposit their value or waste it. Crossing the cost threshold mines the cell. |

Then the spawn queue is appended (so **an orb never moves on the tick it is born**) and dead orbs are
compacted out.

Phase 0 is separate from produce because the generator count is a *condition the tick runs under*, not something that
happens on a tick. Folded into the produce loop, a cell's interval would depend on whether it was
iterated before or after the cell that changed the total — precisely the order-dependence phase
separation exists to prevent.

### Why order does not matter

- A frontier cell reads and writes only its own `emit_timer`.
- Every roll is a hash of its keys, so it cannot depend on how far iteration has reached.
- Two orbs delivering into the same cell produce the same aggregate whichever lands first.
- The frontier and the generator count are **recomputed wholesale**, never edited incrementally, so they converge to
  the same answer however `cell_ids` runs — which is what makes it safe to rebuild them after a mine
  inside the deliver phase.

**The one deliver-phase write another delivery in the same phase can see is mining.** A later orb bound
for the same cell finds it mined rather than locked. It holds because what counts is capped by
`remaining()` and everything the cap turns away wastes: a cell needing 8 fed by orbs worth 5 and 10
books `delivered 8, wasted 7` in either order.

`test_tick_order_independent` runs a busy board with `cell_ids` reversed and compares every observable.
**If you add a phase or a hook that reads state another cell writes in the same phase, this property
breaks and that test is your warning.** The fix is a new phase, not a special case.

---

## The value ledger

The correctness contract for the whole economy:

```
produced == delivered + wasted + in_flight
```

| Bucket | Meaning |
|---|---|
| `produced` | Value emitted by frontier cells |
| `delivered` | Value that counted toward mining a cell |
| `wasted` | Overshoot, or an arrival at a cell something else finished first |
| `in_flight` | Sum of live orb values |

`ledger_balanced()` checks it; `test_ledger_balances` asserts it every tick for 2,000 ticks while cells
mine, crits fire and splits fork.

**Any new mechanic that creates or removes value must add a bucket.** A mechanic that only changes *how
much flows through an existing path* is exempt — crit and split need none, because `emit_orb` books the
value it actually emitted, so a ×5 orb enters `produced` at ×5.

**Ascension currency is outside the ledger entirely**, and it is a third category rather than an
exemption. `World.earned` never becomes an orb: it is minted when a cell is mined and spent in a shop
the simulation cannot see. The orb value that paid for that cell was booked under `delivered` one line
above the grant. The test to carry forward is: **does the quantity ever become an orb?**

`earned` is granted in `_deliver`, never in `Graph.mine_cell()` — that function is idempotent and also
runs for the board's starting cell, so a grant placed there would pay for ground the player was given.
**The ram is the one source of value that was never an orb.** It enters and lands in the same step:
`produced += used` and `delivered += used`, where `used` is capped by `remaining()`. Same in as out, so
it needs no bucket — and the ram writes **nothing to `wasted`**, because the pool is charged only for
what it lands. Damage that does not finish a cell stays as progress.

⚠️ **That refund divides back through `_ram_bonus()`, and the two must stay inverses.** A full-strength
shot takes the `used >= damage` branch and zeroes the pool exactly; without it a rounding crumb would
survive every shot and accumulate forever. `test_ram_pool_empties_on_a_full_shot` is the guard, at both
zero and max upgrade levels.

---

## Calculations

All economy arithmetic is **integer**. Floats appear only in view interpolation and camera math.

### Constants (`sim/world.gd`)

| Constant | Value | Meaning |
|---|---|---|
| `TICK_HZ` | 10 | Simulation ticks per second |
| `HOP_TICKS` | 3 | Ticks to cross one hop |
| `BASE_ORB_VALUE` | 10 | What an orb launches with before the Power buff |
| `BASE_INTERVAL` | 20 | Ticks between emissions with one generator |
| `MIN_INTERVAL` | 2 | Floor on the above. A legibility guard, not a balance cap |
| `POWER_RATE_PER_CELL` | 2 | Percentage points of increased rate per mined cell |
| `CRIT_MULTIPLIER` | 5 | What a crit is worth |
| `GENERATOR_CHANCE` | 0 | Odds a mined cell becomes a generator before purchases. Ten shop levels take it to 100% |
| `RAM_SHARE_PERCENT` | 20 | How much of a mined cell's cost the ram banks |
| `VISION_IDENTITY` / `VISION_RARITY` | 3 / 8 | Hops at which a node's name, and its glow, are visible |

Node effects live in `sim/node_catalog.gd`; shop prices in `sim/meta_upgrades.gd`.

### The frontier

- **A mined cell rolls once for a generator**, on `Rng.roll(seed, cell_id, KEY_GENERATOR)` against the
  current chance. Deterministic, order-independent, and it picks up a purchase made a moment earlier.
- **A generator drives the emission rate; a dud does nothing.** `generators()` counts them,
  `mined_count()` counts mined cells, and the two are deliberately different numbers.
- **Only generators on the frontier emit** — a generator, mined, *and* touching ground that can still
  be taken. Interior cells go quiet, so orb count tracks the **perimeter** rather than the area.
- A frontier cell fires at the mineable neighbour **closest to done**, ties to the lowest id.
  Concentrating fire rather than spreading it is what makes cells land constantly.

⚠️ **A frontier of nothing but duds ends the run, and that is the ascension trigger.** There used to be
a fallback here — the lowest-id frontier cell emitted when nothing else would, so the spread crawled
instead of stopping. It made run 1 unreadable: the centre mines its six neighbours, every one a dud at
0% chance, the centre stops being frontier, and then an arbitrary cell on the rim kept firing with
nothing on screen to explain why. Stalling *is* how a run ends, so Phase 0 lets it stall.
`test_a_dud_frontier_ends_the_run` is the guard.

**The rule this creates is an economic one, and it has its own test.** A stalled run must bank enough to
buy the way out of itself. At 0% chance a run mines exactly the centre's six neighbours — six cells at
`50 × 1³`, so **300 every time** — against a first generator level costing 150.
`test_run_one_funds_the_first_purchase` fails the day the cost curve, the band table or that price moves
in a way that closes the gap.

⚠️ **The response to the generator chance is a cliff, not a curve.** A dud neither emits nor counts as
toward the rate, so the two effects multiply: below roughly 65% a run cannot clear its band at all. That is the
intended shape — the game starts at 0%, early runs are short by construction, and ascending out of them
is the loop.

### One divisor

⚠️ **The generator count and Speed are both *increased rates*, so they sum before they divide:**

```
interval = 20 × 100 / (100 + generators×2 + speed_levels×10)   floored at 2
```

Dividing twice truncates twice and quietly loses a tick. Summed, the curve is asymptotic — bonuses
stack forever and never reach zero, so `MIN_INTERVAL` is a guard the buffs never actually reach.
`test_rate_is_one_divisor` pins it.

### The band wall

**One derived predicate carries the wall and the colony both:**

> A locked cell may be mined if its band is bought, **or** it already has a mined neighbour in the same
> band.

So the frontier cannot cross into ground you have not unlocked, but a rammed cell out in that ground
*can* spread through its own band — and still cannot climb into the next one. The ram itself ignores
the wall entirely, which is how you get to see what is out there.

**There is therefore no blob or colony entity anywhere in `sim/`.** A colony is just a mined cell far
away, throttled by having a tiny perimeter and sitting on expensive ground. Income is one global pool
and the geometry does the balancing. `test_band_wall` pins all four cases.

### Randomness

**Every roll is a hash of its keys, never a stream.** `Rng.roll(seed, a, b, c)` returns 0..9999 from a
splitmix64 avalanche. Emission rolls key off `(cell_id, tick, orb_index)`; node placement keys off
`(run_seed, cell_id)` at board build.

A stateful generator would make each roll depend on how many rolls came before it, which is exactly the
order-dependence the phase rules exist to prevent. `test_rolls_are_pure` is the guard.

### Node distribution, and the dilution rule

> **A purchase must never lower your expected run.**

Two structural guarantees, not balance passes:

1. **Fixed slots.** The rarity roll never looks at what is unlocked. The board decides how many commons,
   rares and keystones exist; ascension changes only *which* types may fill a slot. A slot whose rarity
   has no unlocked type stays **empty** rather than falling back to a commoner one, so buying a rare
   fills empty slots and takes nothing away.
2. **Additives and multipliers never share a table.** Power and Speed are commons; Crit and Split are
   rares. "Additives crowding out multipliers" is structurally impossible rather than balanced around.

`test_slots_are_fixed` pins both halves.

### Vision

One multi-source BFS from every mined cell, cached against `unlock_version`. The ram has no range, so
this now serves vision alone.

Rarity is honest at range and identity is hidden, which is what makes saving the ram for a distant glow
a gamble with a build-up rather than arithmetic.

---

## The two pull channels

`take_delivery_events()` and `take_mine_events()` are **the only data paths out of `sim/`**. The
simulation appends, the view drains. No signals, no callbacks — `sim/` still names nothing in Godot.

Draining rather than clearing per tick is load-bearing: a frame can advance the simulation by many ticks
before it draws, and every event in that window must survive to be shown. Both lists are capped and
evict oldest-first, because the headless suite runs thousands of ticks with nobody draining.

They stay **write-only from the simulation's side**. If any `sim/` code branches on them, iteration
order leaks out of presentation and into the economy. Neither touches the ledger.

---

## Determinism

The properties the tests protect, and what guarantees them:

| Property | Guaranteed by |
|---|---|
| Same inputs → same economy | Integer-only arithmetic; every roll a pure hash |
| Iteration order irrelevant | Phase separation, and wholesale recompute over incremental edit |
| No value appears or vanishes | The ledger invariant |
| Same seed → same board | Node placement keyed on `(run_seed, cell_id)` alone |
| Same board → same frontier | Derived from mined state, rebuilt wholesale rather than edited; an all-dud frontier resolves to empty and the run stalls |
| Same seed → same generators | The generator roll is a pure hash of `(seed, cell_id)` |
| Same board → same visibility | One multi-source BFS, cached against `unlock_version` |
| Same meta → same economy | `MetaState` is plain integers; `from_dict` forces every loaded value through `int()`, so a JSON round trip cannot put a float in the economy |
| Same board → same earnings | `earned` is a sum of per-cell constants over cells that mine exactly once |

Introducing floats into value arithmetic, or a stateful RNG stream, would break both. Neither is
forbidden, but both are architectural decisions rather than implementation details.

---

## View and input

`Main` owns the `World`, accumulates real time, and steps the sim at a fixed rate; the view interpolates
between ticks with `render_alpha` so orbs glide rather than step. Rendering is immediate-mode — one
`_draw()` for the whole board, one for all orbs, one for all floating text — rather than a node per
cell. Transient marks are no exception: a `+8` is an entry in a list, not a node spawned and freed.

`GraphView` culls to `camera.visible_world_rect()`. At 1,801 cells the board is far larger than any
sensible zoom shows, and without culling the whole lattice is re-tessellated every frame.

**`Main` owns a run phase — running or shopping — and it gates the tick.** The shop is the whole of
the between-runs phase: it is open exactly when the simulation is frozen and the next board has been
built, so a purchase can only ever land on a board with nothing mined on it. Buying re-places nodes on
that board's own seed, since node placement happens at build and a newly unlocked type has to be dealt
into the ground. The phase is separate from the player's pause, which is theirs.

**There is one board gesture: throw the ram.** Everything else on screen runs itself.

Locked cells draw `progress / cost` under the hex, gated on a zoom threshold — at radius 24 a zoomed-out
board is otherwise a wall of unreadable digits. Edges are drawn once per pair by only emitting the
low-id side.

---

## Testing

**The suite is deliberately small.** A test earns its place only when it pins an invariant that is
invisible on screen and silent when broken. Everything you can see by playing — the frontier breathing,
the vision ranges, the ram preview, every juice event — is checked by looking at it.

Seven tests: ledger conservation (rams included), tick order-independence, the band wall, the
one-divisor rate, RNG purity, the dilution rule, and the no-stall guarantee.

---

## Deliberately not built

- **Sound.** Every event has a light and a shape; none has a sound yet.
- **A failure state.** No clock, no threat, no way to play badly. The band wall and the ram supply
  the run's shape.
- **Level-up cards.** The frontier, the ram, the node pool and the shop are already four progression
  surfaces. Cards would be the layer that grants *verbs* while nodes grant *numbers*.
- **Node synergies.** With four types there is little to combine.
- **Per-blob income.** Perimeter and the cost gradient already throttle distant colonies.
