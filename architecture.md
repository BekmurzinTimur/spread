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
| `sim/regions.gd` | Seven depth regions of eight rings each: names, colours, `region_of(hops)`, the deepest depth | — |
| `sim/rng.gd` | Stateless hash rolls. The only source of variance | — |
| `sim/hex_map.gd` | Builds the gapped lattice and its tunnels into a `Graph`, the per-hop cost table; scatters nodes from a run seed | Graph, GraphCell, Regions, Rng, NodeCatalog |
| `sim/graph.gd` | Cells, `cell_ids`, `mined_ids`, `mine_cell()`, the distance-from-mined field | GraphCell |
| `sim/graph_cell.gd` | One position: region, cost, progress, mined state, buried node, emit timer | NodeCatalog |
| `sim/node_type.gd` | Static data for one buff type | — |
| `sim/node_catalog.gd` | Every buff type and what a level of it is worth | NodeType, MetaState |
| `sim/buff_state.gd` | The run's buff tally, found and bought kept apart | NodeCatalog, MetaState |
| `sim/orb.gd` | A packet in flight: value, endpoints, crit flag | — |
| `sim/world.gd` | The tick, the frontier, the ledger, the region wall, the ram | everything in `sim/` |
| `sim/delivery_event.gd` | One recorded delivery, for the view | Regions |
| `sim/meta_state.gd` | What the player carries between runs: one wallet, purchase levels, which regions are open, what is buyable | MetaUpgrades, Regions |
| `sim/meta_upgrade.gd` | Static per-upgrade data: price curve, level cap, colour block | Regions |
| `sim/meta_upgrades.gd` | Every upgrade, grouped into colour blocks; region prices from `HexMap.region_value` | MetaUpgrade, NodeCatalog, Regions, HexMap |
| `sim/meta_store.gd` | `MetaState` ⇄ JSON on disk | MetaState |
| `scenes/Main.gd` | Owns World, drives the fixed tick, routes input, ascension | sim, view, HUD |
| `scenes/camera_2d.gd` | Pan/zoom, the click-vs-drag verdict, the visible world rect | — |
| `scenes/view/GraphView.gd` | Cached board chunks (edges, cells, prices, glows, icons) and a per-frame overlay (frontier, progress, pops, ram) | sim (read-only), Icons |
| `scenes/view/OrbLayer.gd` | Orbs and trails as instance batches, interpolated between ticks | sim (read-only), InstanceBatch |
| `scenes/view/SplashLayer.gd` | Expanding shards (an instance batch) and a ring; knows a position, a colour and an age | InstanceBatch |
| `scenes/view/instance_batch.gd` | A MultiMesh of quads refilled each frame; one draw call per batch | — |
| `scenes/view/FloatingTextLayer.gd` | Rising, fading text; knows only strings and colours | — |
| `scenes/icons.gd` | Every icon texture, buff and upgrade lookups, and the icon + text label drawing | NodeCatalog, MetaUpgrades |
| `scenes/ui/HUD.gd` | Four readouts, the end-run button, and the tooltips | Main, sim (read-only), Icons |
| `scenes/ui/AscensionShop.gd` | The project's one modal: wallet, one card block per colour, Start run | Main, sim (read-only), Icons |
| `scenes/ui/format.gd` | Presentation helpers shared by the HUD and the shop | — |
| `tests/run_tests.gd` | Headless suite, exits non-zero on failure | everything |

**The board is arithmetic, not data.** `HexMap.build()` generates a hex disc with six-way adjacency.
A cell's `hops` is its **depth** (0..`Regions.MAX_HOPS`), which sets region and cost (`HexMap.hop_costs()`:
`COST_BASE` growing by `COST_GROWTH_PERCENT` per hop, in integer steps). Its geometric ring is
`HexMap.ring_of(depth)`: one empty gap ring sits before every region past red. Each gap holds one
**tunnel** cell at `(±ring, 0)`, owned by the outer region, on the left for odd regions and the right for
even ones. Missing cells simply have no edges. `HexMap.region_value` counts the tunnel. There is no map file.
Only node placement is randomised, and it is a pure function of the run seed.

---

## The tick

`World.tick()` runs at a fixed **10 Hz**, driven by an accumulator in `Main._process`. Five phases,
each completing across all cells before the next begins:

| Phase | What happens |
|---|---|
| **0. Resolve frontier** | Rebuild the frontier set and the generator count from the mined cells if the board or the purchases changed. |
| **1. Produce** | Every frontier cell advances its own timer; at zero it rolls crit and split and emits at its chosen neighbour. |
| **2. Transport** | Every live orb advances one tick toward its target. |
| **3. Deliver** | Orbs that have crossed deposit their value or waste it. Crossing the cost threshold mines the cell. Splash orbs are queued. |
| **4. Splash** | Each queued splash hits its target's mineable neighbours for a share of its value. |

Then the spawn queue is appended (so **an orb never moves on the tick it is born**) and dead orbs are
compacted out.

Phase 0 is separate from produce because the generator count is a condition the tick runs under, not
something that happens on a tick. Folded into the produce loop, a cell's interval would depend on
iteration order.

### Why order does not matter

- A frontier cell reads and writes only its own `emit_timer`.
- Every roll is a hash of its keys, so it cannot depend on how far iteration has reached.
- Two orbs delivering into the same cell produce the same aggregate whichever lands first.
- The frontier and the generator count are **recomputed wholesale** (then sorted), never edited
  incrementally, so it is safe to rebuild them after a mine inside the deliver phase.

**The one deliver-phase write another delivery in the same phase can see is mining.** A later orb bound
for the same cell finds it mined rather than locked. It holds because what counts is capped by
`remaining()` and everything the cap turns away wastes: a cell needing 8 fed by orbs worth 5 and 10
books `delivered 8, wasted 7` in either order.

**Splash runs in two passes.** First every hit's targets are chosen, and booked to `produced`, off the
board the deliver phase left; only then do hits land, capped by `remaining()` like a delivery. Choosing
targets while landing would let one splash's mine change another's target list.

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
| `produced` | Value emitted by frontier cells, splash hits, plus ram damage that landed |
| `delivered` | Value that counted toward mining a cell |
| `wasted` | Overshoot, or an arrival at a cell that is no longer mineable |
| `in_flight` | Sum of live orb values |

`ledger_balanced()` checks it; `test_ledger_balances` asserts it every tick for 2,000 ticks while cells
mine, crits fire, splits fork and rams land.

**Any new mechanic that creates or removes value must add a bucket.** A mechanic that only changes *how
much flows through an existing path* is exempt — crit, the crit multiplier, split and overcharge need
none, because `emit_orb` books the value it actually emitted. A splash hit behaves like an orb that lands
the moment it is made: its full amount enters `produced`, and it splits into `delivered` and `wasted`.

**Ascension currency is outside the ledger**, and so is the ram pool until it fires, so Bounty and Ram
charge need no bucket. `World.earned` never becomes an orb: it is minted when a
cell is mined and spent in a shop the simulation cannot see. The test to carry forward is: **does the
quantity ever become an orb?**

`earned` is granted in `World._mine`, never in `Graph.mine_cell()` — that function is idempotent and also
runs for the board's starting cell.

**The ram is the one source of value that was never an orb.** It enters and lands in the same step:
`produced += used` and `delivered += used`, where `used` is capped by `remaining()`. It writes nothing to
`wasted`, because the pool is charged only for what it lands. Damage that does not finish a cell stays
as progress.

⚠️ **That refund divides back through `_ram_bonus()`, and the two must stay inverses.** A full-strength
shot takes the `used >= damage` branch and zeroes the pool exactly. `test_ram_pool_empties_on_a_full_shot`
is the guard.

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
| `MIN_INTERVAL` | 2 | Floor on the above. A legibility guard |
| `RATE_PER_GENERATOR` | 2 | Percentage points of increased rate per generator |
| `CRIT_MULTIPLIER` | 5 | What a crit is worth before the shop's Crit multiplier |
| `SPLASH_PERCENT` | 50 | Share of a splash orb's value each neighbour takes, +25 per Splash strength |
| `OVERCHARGE_PER_LEVEL` | 1 | Percent orb value per 100 generators, per Overcharge level |
| `RAM_CHARGE_PER_LEVEL` / `BOUNTY_PER_LEVEL` | 5 / 10 | Ram share and currency percent per level |
| `GENERATOR_CHANCE` | 0 | Odds a mined cell becomes a generator before purchases |
| `RAM_SHARE_PERCENT` | 20 | How much of a mined cell's cost the ram banks |
| `VISION_IDENTITY` / `VISION_RARITY` | 3 / 8 | Hops at which a node's name, and its glow, are visible |

Cost constants live in `sim/hex_map.gd`, node effects in `sim/node_catalog.gd`, shop prices in
`sim/meta_upgrades.gd`.

### The frontier

- **A mined cell rolls once for a generator**, on `Rng.roll(seed, cell_id, KEY_GENERATOR)` against the
  current chance.
- **A generator drives the emission rate; a dud does nothing.** `generators()` counts them,
  `mined_count()` counts mined cells.
- **Only generators on the frontier emit** — a generator, mined, *and* touching a mineable cell.
  Interior cells go quiet, so orb count tracks the **perimeter** rather than the area.
- A frontier cell fires at the mineable neighbour **closest to done**, ties to the lowest id.

⚠️ **A frontier of nothing but duds resolves empty, and that ends the run.** There is no fallback
emitter. `test_a_dud_frontier_ends_the_run` is the guard.

**A stalled run must bank enough to buy the way out of itself.** At 0% chance a run mines exactly the
centre's six hop-1 neighbours, which must pay for the first generator level.
`test_run_one_funds_the_first_purchase` fails the day the cost curve or that price closes the gap.

### One divisor

⚠️ **The generator count and Speed are both *increased rates*, so they sum before they divide:**

```
interval = 20 × 100 / (100 + generators×2 + speed_levels×10)   floored at 2
```

Dividing twice truncates twice. `test_rate_is_one_divisor` pins it.

### The region wall

**One rule, three places:**

> A cell is mineable if it is unmined **and** its region is open. Red is always open; any other region
> opens when its "Mine <colour>" upgrade is bought.

- The **frontier** only targets mineable cells, and a delivery into an unmineable cell wastes.
- The **ram** only fires at mineable cells (`can_ram_at`), at any distance.
- The **shop** only sells an upgrade whose colour block is open: `MetaState.next_cost` returns -1
  otherwise. The gate lives in `sim/`, not only in the UI.

`MetaState.region_open` is the single source; `World.region_open` defers to it. There is no colony entity in
`sim/`: a rammed cell far away is just a mined cell with a tiny perimeter inside an open region.
`test_region_wall` pins all three.

### Upgrades

- Every `MetaUpgrade` belongs to a colour block (`region`). "Mine <colour>" sits in the block before the
  colour it opens.
- Upgrades are **uncapped** (`MetaUpgrade.UNCAPPED`) unless the effect is bounded: generator chance
  (10 levels), type unlocks and region unlocks (1).
- Price is `cost_base × (cost_growth / 100)^level` in integer steps, saturating at `COST_CEILING`.
- Red is hand-priced. Every block past red prices its cards as a percentage of what clearing the
  previous region pays, so prices follow the cost curve when it is retuned. "Mine <colour>" costs
  `REGION_PRICE_PERCENT` of what clearing the region before it pays.
- Every block sells a **Power tier**, keyed `level_yield` for red and `level_yield_<colour>` beyond.
  `MetaUpgrades.bought_levels` sums tiers × `NodeCatalog.levels_in_region` into the run's bought levels.
- **One table sets Power per region**, `NodeCatalog.POWER_BY_REGION`. A shop tier and a found node
  (`GraphCell.node_grant()`) both read it, so the two never disagree.- Upgrade keys are save keys and are never renamed.

### Randomness

**Every roll is a hash of its keys, never a stream.** `Rng.roll(seed, a, b, c)` returns 0..9999 from a
splitmix64 avalanche. Emission rolls key off `(cell_id, tick, orb_index)`; node placement keys off
`(run_seed, cell_id)` at board build. `test_rolls_are_pure` is the guard.

### Node distribution, and the dilution rule

> **A purchase must never lower your expected run.**

1. **Fixed slots.** The rarity roll never looks at what is unlocked. A slot whose rarity has no unlocked
   type stays **empty**, so buying a type fills empty slots and takes nothing away.
2. **Additives and multipliers never share a table.** Power and Speed are commons; Crit, Split and
   Splash are rares.

`test_slots_are_fixed` pins both halves.

### Vision

One multi-source BFS from every mined cell, cached against `unlock_version`. Rarity is visible at range,
identity only up close.

---

## The two pull channels

`take_delivery_events()` and `take_mine_events()` are **the only data paths out of `sim/`**. The
simulation appends, the view drains. No signals, no callbacks.

Draining rather than clearing per tick matters: a frame can advance the simulation by many ticks before
it draws, and every event in that window must survive to be shown. Both lists are capped and evict
oldest-first.

They stay **write-only from the simulation's side**. If any `sim/` code branches on them, iteration
order leaks into the economy. Neither touches the ledger.

---

## Determinism

| Property | Guaranteed by |
|---|---|
| Same inputs → same economy | Integer-only arithmetic; every roll a pure hash |
| Iteration order irrelevant | Phase separation, and wholesale recompute over incremental edit |
| No value appears or vanishes | The ledger invariant |
| Same seed → same board | Integer cost table; node placement keyed on `(run_seed, cell_id)` alone |
| Same board → same frontier | Rebuilt wholesale from mined cells and sorted; an all-dud frontier resolves empty |
| Same seed → same generators | The generator roll is a pure hash of `(seed, cell_id)` |
| Same board → same visibility | One multi-source BFS, cached against `unlock_version` |
| Same meta → same economy | `MetaState` is plain integers; `from_dict` forces every loaded value through `int()` |
| Same board → same earnings | `earned` is a sum of per-cell constants over cells that mine exactly once |

Floats in value arithmetic or a stateful RNG stream would break these. Neither is forbidden, but both
are architectural decisions.

---

## View and input

`Main` owns the `World`, accumulates real time, and steps the sim at a fixed rate; the view interpolates
between ticks with `render_alpha`. There is no node per cell, orb or mark: a `+8` or a splash is an entry
in a list.

**The board draws in two layers.** Still ground lives in spatial chunks, each its own canvas item,
redrawn only when a cell's *look* (visibility, mined, generator, frontier) changes. The overlay is drawn
every frame and holds only what moves: breathing frontier cells, progress on cells being fed, pops, and
the ram.

**Orbs and splash shards are instance batches** — one MultiMesh each, one draw call at any count.
Antialiasing is MSAA alone.

**`Main` owns a run phase — running or shopping — and it gates the tick.** The shop is open exactly when
the simulation is frozen and the next board has been built, so a purchase always lands on a board with
nothing mined on it. Buying re-places nodes on that board's own seed.

**The shop draws one block per colour**, top to bottom: open blocks sell, the next closed block is drawn
dimmed as a teaser, the rest are hidden.

**There is one board gesture: throw the ram.** Everything else on screen runs itself.

---

## Testing

**The suite is deliberately small.** A test earns its place only when it pins an invariant that is
invisible on screen and silent when broken.

Eleven tests: ledger conservation, tick order-independence, the region wall (frontier, ram and shop), the
one-divisor rate, RNG purity, the dilution rule, the dud-frontier stall, run 1 funding the first
purchase, and three ram guards (spend only what lands, a full shot empties the pool, the early ram is
affordable).

---

## Deliberately not built

- **Sound.** Every event has a light and a shape; none has a sound yet.
- **A failure state.** No clock, no threat. The region wall and the shop blocks supply the run's shape.
- **Level-up cards.** Cards would be the layer that grants *verbs* while nodes grant *numbers*.
- **Node synergies.** With five types there is little to combine.
- **Per-blob income.** Perimeter and the cost gradient already throttle distant colonies.
