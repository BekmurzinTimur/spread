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
| `sim/graph.gd` | Adjacency, BFS shortest paths, path cache | GraphCell |
| `sim/graph_cell.gd` | One position: lock state, cost, contents, `unlock()` | Block, BlockCatalog |
| `sim/block.gd` | An installed block: def + target + timer | BlockDef |
| `sim/block_def.gd` | Static per-type data (Resource) | BlockBehavior, Tiers |
| `sim/block_catalog.gd` | Every block type, in one place | BlockDef, behaviours |
| `sim/behaviors/*.gd` | Per-type logic, one hook each | GraphCell, Block, Orb |
| `sim/orb.gd` | A packet in flight: value, route, progress | Tiers |
| `sim/map_loader.gd` | JSON → Graph; `line_graph()` for tests | Graph, GraphCell, BlockCatalog |
| `sim/tiers.gd` | Six tiers, red → purple, names and colours | — |
| `scenes/Main.gd` | Owns World, drives the fixed tick, routes input | sim, view, HUD |
| `scenes/camera_2d.gd` | Pan/zoom, and the click-vs-drag verdict | — |
| `scenes/view/GraphView.gd` | Draws edges, cells, routes, previews | sim (read-only) |
| `scenes/view/OrbLayer.gd` | Draws orbs, interpolated between ticks | sim (read-only) |
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
- `Block` — a `BlockDef` plus mutable state: `target_id` and a produce `timer`. Created only by
  `GraphCell.unlock()`, then freely moved between cells by swapping.

`initial_block_id` and `block` are separate fields because they diverge the moment the player swaps:
the first stays the source of truth for *drawing a locked cell*, the second for everything else.

**Blocks are never created or destroyed at runtime.** `unlock()` is the only constructor, and swapping
is the only way to relocate one. The map therefore fixes the supply of generators and pumps, which is
what makes placement a real decision.

---

## The tick

`World.tick()` runs at a fixed **10 Hz**, driven by an accumulator in `Main._process`. Three phases,
each completing across all entities before the next begins:

| Phase | What happens |
|---|---|
| **1. Produce** | Every block on a mined cell gets `on_produce()`. Generators emit into `_spawn_queue`. |
| **2. Transport** | Every live orb advances; on entering a new cell: decay → death check → `on_orb_pass()`. |
| **3. Deliver** | Orbs at the end of their route deposit their value, then die. |

Then the spawn queue is appended (so **an orb never moves on the tick it is born**) and dead orbs are
compacted out.

### Why order does not matter

Phase separation alone gives order-independence, so there is **no double-buffering**:

- Generators read only their own timer.
- Delivery writes only `unlock_progress`, and nothing in the produce phase reads it.
- Two orbs delivering into the same cell produce the same aggregate regardless of which lands first.

`test_tick_order_independent` runs the same world with `cell_ids` reversed and asserts every observable
matches. **If you add a phase or a hook that reads state another block writes in the same phase, this
property breaks and that test is your warning.** The fix is a new phase, not a special case.

---

## The value ledger

The correctness contract for the whole economy:

```
produced + restored  ==  delivered + wasted + decayed + cancelled + in_flight
```

| Bucket | Meaning |
|---|---|
| `produced` | Value emitted by generators |
| `restored` | Value added back by pumps |
| `delivered` | Value that counted toward mining a cell |
| `wasted` | Arrived but had nowhere useful to go (overshoot, or a mined destination) |
| `decayed` | Lost to travel |
| `cancelled` | Destroyed because a route was retargeted, or its cell swapped |
| `in_flight` | Sum of live orb values |

`evaporated_orbs` is a **count, not a value** — an evaporating orb is already at zero, so its loss is
fully accounted for under `decayed`.

`ledger_balanced()` checks this; `test_value_conservation` asserts it every tick for 2000 ticks while
pumps fire, cells unlock, orbs evaporate and routes change. It is also live in the HUD.

**Any new mechanic that creates or removes value must add a ledger bucket.** Pumps needed `restored`;
swapping needed `cancelled`. If you skip this, the invariant breaks and the suite fails loudly — which
is the point.

---

## Calculations

All economy arithmetic is **integer**. No floats, no RNG, no seeded random anywhere in `sim/`.
Floats appear only in view interpolation and camera math.

### Constants (`sim/world.gd`)

| Constant | Value | Meaning |
|---|---|---|
| `TICK_HZ` | 10 | Simulation ticks per second |
| `TICKS_PER_HOP` | 10 | One second to cross one edge |
| `ORB_MAX_VALUE` | 10 | Value of a fresh orb, and the pump ceiling |
| `DECAY_PER_HOP` | 1 | Value lost entering each new cell |

Per-type numbers live in `sim/block_catalog.gd`: generator `produce_interval` 20 ticks, pump
`restore_amount` 10.

### Travel

On entering a new cell, in this exact order:

1. `value -= min(DECAY_PER_HOP, value)`, added to `decayed`
2. if `value <= 0` → evaporate, stop
3. if **not** the final cell → `on_orb_pass()`; a pump sets `value = min(value + restore, ORB_MAX_VALUE)`

Two rules encoded here, both load-bearing:

- **Decay resolves before the pump.** An orb entering a pump cell on its last point of value dies; it
  did not make it to the pump.
- **Blocks never act on an orb's final cell.** Without this, parking a pump on a target would make
  every delivery land at full value.

Net effect: an unaided orb survives **9 hops** (arriving with 1) and dies on the tenth. Pumps spaced
≤9 hops apart carry it indefinitely.

### Delivery

Into a locked cell: `used = min(unlock_remaining, orb.value)` → `unlock_progress += used`; the remainder
is `wasted`. At `unlock_progress >= unlock_cost` the cell calls `unlock()` and yields its buried block.
Into an already-mined cell, the whole value is `wasted` — nothing consumes resource yet.

### Pathing

BFS over unit edges — **distance is hop count only**, there are no edge weights. Neighbours are sorted
ascending at load, so among equally short routes the one through the lowest-id neighbour always wins.
This tie-break is fixed and tested: without it, decay outcomes would differ between runs and nothing
would be reproducible.

Topology is static, so paths are cached permanently in `Graph._path_cache`. **If teleports ever mutate
adjacency, this cache needs a version stamp** — that is the one place a new mechanic would break an
existing assumption silently.

### `projected_arrival()`

Walks the route applying the same decay/pump rules to answer "what would an orb arrive with?" — this
drives the HUD readout and the aim preview. It deliberately duplicates the transport logic, so
`test_projected_arrival_matches_reality` cross-checks it against real deliveries across 21 hop/pump
combinations. **Change transport, change this, or the test fails.**

---

## Extension points

A block type declares its behaviour by overriding hooks on `BlockBehavior`. The tick iterates blocks and
calls hooks; it never switches on a block type. Adding a type that fits an existing hook is **two edits
and no engine change**: a behaviour script in `sim/behaviors/`, and an entry in `BlockCatalog`.

### Hooks that exist

| Hook | Phase | Implemented by |
|---|---|---|
| `on_produce(world, cell, block)` | Produce | Generator |
| `on_orb_pass(world, cell, orb)` | Transport | Pump |

### Hooks that do not exist yet

These are the known extension costs, so a future change is a decision rather than a surprise:

| Planned block | Needs | Notes |
|---|---|---|
| Distributor, Upgrader | `on_orb_deliver` hook | Delivery into a mined cell currently just wastes the value |
| Sphere, Upkeep | A stat-resolve phase ahead of Produce | See below |
| Teleport | Mutable adjacency | Breaks the permanent path cache; needs a `topology_version` |

**The stat-resolve phase** is the significant one. Nothing radiates today, so pump `restore_amount` is
read straight off the def. Spheres and upkeep buffs need an effective-stats table, and it must be
**recomputed from scratch on invalidation, never mutated incrementally** — `cell.speed *= 1.2` on place
and `/= 1.2` on remove will drift. Combination order must be fixed in one function
(`(base + Σflat) × (1 + Σpct) × Πmult`) or the numbers move when the map changes.

Upkeep also introduces the only genuine feedback loop: a buff that speeds up the generator feeding it.
Resolve it by computing upkeep satisfaction from the **previous** tick, and give it hysteresis, or a
marginal upkeep will strobe its buff on and off every tick.

---

## Determinism

The properties the tests protect, and what would break them:

| Property | Guaranteed by |
|---|---|
| Same map → same routes | BFS ascending-neighbour tie-break |
| Same inputs → same economy | Integer-only arithmetic, no RNG |
| Iteration order irrelevant | Phase separation |
| No value appears or vanishes | The ledger invariant |

Introducing RNG (a chance-based decay, a random event) would break save reproducibility and require a
seeded, serialised stream. Introducing floats into value arithmetic would break exact assertions.
Neither is forbidden, but both are architectural decisions, not implementation details.

---

## View and input

`Main` owns the `World`, accumulates real time, and steps the sim at a fixed rate; the view interpolates
between ticks with `render_alpha` so orbs glide rather than step. Rendering is immediate-mode — one
`_draw()` for the whole graph, one for all orbs — rather than a node per cell.

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
fixed seed and asserts diameter, connectivity, and that a first pump is reachable unaided. Editing the
JSON by hand is not the workflow — edit the generator.

---

## Deliberately not built

Named so they are visible decisions rather than oversights:

- **Save/load.** Cheap to add — sim state is plain data by construction.
- **Orb merging and MultiMesh rendering.** A single `_draw()` handles hundreds of orbs. Integer decay is
  linear, so merging same-tier/same-edge/same-destination orbs stays valid whenever it is needed.
- **Effective-stats table.** Nothing radiates yet. See *Extension points*.
- **Path invalidation.** Topology is static. See *Pathing*.
- **Congestion.** Edges are stateless; any number of orbs may occupy one.
