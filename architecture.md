# Architecture

How Spread is put together: the modules, the calculations they own, and the contracts between them.
See `gamedesign.md` for what the game *is*; this is how it works.

---

## The one rule

**The simulation is not the scene tree.**

```
   scenes/  ──────────────►  sim/
   (Godot nodes, drawing,     (plain RefCounted, fixed-order math,
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
| `sim/hex_map.gd` | Builds the gapped lattice and its tunnel bosses into a `Graph`, the cost curve, mandatory keystone slots; scatters nodes and prices keystones from a run seed | Graph, GraphCell, Regions, Rng, NodeCatalog |
| `sim/graph.gd` | Cells, `cell_ids`, `mined_ids`, `boss_ids`, `mine_cell()`, the distance-from-mined field | GraphCell |
| `sim/graph_cell.gd` | One position: region, cost, progress, mined state, boss flag, buried node, emit timer | NodeCatalog |
| `sim/node_type.gd` | Static data for one buff type | — |
| `sim/node_catalog.gd` | Every buff type and what a level of it is worth | NodeType, MetaState |
| `sim/buff_state.gd` | The run's buff tally, found and bought kept apart | NodeCatalog, MetaState |
| `sim/skill_state.gd` | The run's skill clocks per buff id: readiness, cooldown, active window | — |
| `sim/orb.gd` | A packet in flight: value, endpoints, flags, birth tick | — |
| `sim/world.gd` | The tick, the frontier, the ledger, the region wall, the ram, skills | everything in `sim/` |
| `sim/delivery_event.gd` | One recorded delivery, for the view | Regions |
| `sim/meta_state.gd` | What the player carries between runs: one wallet, purchase levels, which regions are open (banked bosses), which achievements are held, what is buyable, bulk buys and price quotes, copies for previews | MetaUpgrades, Achievements, Regions |
| `sim/achievement.gd` | Static data for one achievement: colour, hidden flag, progress target, rate and value *more* percents | Regions |
| `sim/achievements.gd` | Every achievement, progress per achievement, `evaluate` (grants what is earned), the rate and value multipliers | Achievement, MetaState, Regions |
| `sim/meta_upgrade.gd` | Static per-upgrade data: price curve, level cap, colour block, type group, hidden flag | Regions |
| `sim/meta_upgrades.gd` | Every upgrade, each in a colour block (what gates it) and a type group (how the shop draws it); block prices in a per-colour unit | MetaUpgrade, NodeCatalog, Regions |
| `sim/meta_store.gd` | `MetaState` ⇄ JSON on disk | MetaState |
| `scenes/Main.gd` | Owns World, drives the fixed tick, routes input, arms the ram, ascension, banks beaten bosses into meta | sim, view, HUD |
| `scenes/camera_2d.gd` | Pan/zoom, the click-vs-drag verdict, the visible world rect | — |
| `scenes/view/GraphView.gd` | Cached board chunks (edges, cells, prices, glows, icons) and a per-frame overlay (frontier, bosses and keystones, progress, pops, ram aim preview) | sim (read-only), Icons |
| `scenes/view/OrbLayer.gd` | Orbs and trails in a fixed ring buffer, each written once on its birth tick and moved by `orb.gdshader`; hands ram orbs to BeamLayer | sim (read-only), InstanceBatch, BeamLayer |
| `scenes/view/BeamLayer.gd` | Above the orbs: the ram shot's dim, beam and bloom, and each ram orb drawn as a beam hop | sim (read-only) |
| `scenes/view/SplashLayer.gd` | Bursts and splash-reach rings in a fixed ring buffer, one MultiMesh animated by `splash.gdshader`; a full buffer replaces its oldest | InstanceBatch (bounds) |
| `scenes/view/instance_batch.gd` | Never-culled MultiMesh bounds and the radial disc texture | — |
| `scenes/view/FloatingTextLayer.gd` | Rising, fading text; knows only strings and colours | — |
| `scenes/audio/SoundManager.gd` | Merges sound requests per frame and plays them on one polyphonic player within per-cue and global voice caps | SoundBank, SoundCue |
| `scenes/audio/sound_cue.gd` | Resource: one sound's stream and its load policy (bus, voices, interval, priority, stack gain) | — |
| `scenes/audio/sound_bank.gd` | Resource: one cue slot per game event; `assets/sounds/sound_bank.tres` fills it | SoundCue |
| `scenes/icons.gd` | Every icon texture, buff, upgrade and achievement lookups, and the icon + text label drawing | NodeCatalog, MetaUpgrades, Achievements |
| `scenes/ui/HUD.tscn` + `.gd` | Currency, end-run button, orb value readout, ram meter, buff hexes and their level gain texts, region bar, tooltips | Main, sim (read-only), BuffHex, RamMeter, FloatingTextLayer |
| `scenes/ui/BuffHex.tscn` + `.gd` | One buff and its skill: final stat, hex in its unlock region's colour filled by readiness, level; a click asks Main to activate; locked is a question mark | sim (read-only), HexPanel, Icons |
| `scenes/ui/HexPanel.gd` | `@tool` hexagon Control with a top-down fill clipped to the hex; hover and clicks follow its outline | — |
| `scenes/ui/RamMeter.gd` | `@tool` radial meter for the ram pool | — |
| `scenes/ui/AscensionShop.tscn` + `.gd` | The project's one modal: wallet, Start run, the Upgrades and Achievements tabs, reset | Main, sim (read-only), UpgradesPage, AchievementsPage |
| `scenes/ui/UpgradesPage.tscn` + `.gd` | Upgrade badges by type group; the last hovered one explained (level, next level, bulk price); the stat table previewing that purchase on a probe `World` | Main, sim (read-only), UpgradeBadge, IconHex, StatTable |
| `scenes/ui/UpgradeBadge.tscn` + `.gd` | One upgrade as a hex in its colour and its level; click buys 1, shift 5, ctrl/cmd 20 | sim (read-only), IconHex, Icons |
| `scenes/ui/StatTable.tscn` + `.gd` | Every stat the shop moves at run start, with the next value where a preview differs | sim (read-only), Icons |
| `scenes/ui/AchievementsPage.tscn` + `.gd` | Achievement badges, the last hovered one explained: status, rewards, progress, totals | sim (read-only), IconHex, Icons |
| `scenes/ui/IconHex.tscn` + `.gd` | A HexPanel with an icon, and the shared locked look | HexPanel |
| `scenes/ui/theme.tres` | Shared font sizes, colours, button, panel and bar styles | — |
| `sim/format.gd` | Number and chance formatting for anything shown to the player | Rng |
| `tests/run_tests.gd` | Headless suite, exits non-zero on failure | everything |

**The board is arithmetic, not data.** `HexMap.build()` generates a hex disc with six-way adjacency.
A cell's **depth** (0..`Regions.MAX_HOPS`) sets its region; its geometric ring is `HexMap.ring_of(depth)`:
one empty gap ring sits before every region past red. Each gap holds one **boss** cell at `(±ring, 0)`,
owned by the *inner* region, on the left for odd regions and the right for even ones.
`graph.boss_ids[region]` names the boss guarding each region. Missing cells simply have no edges.

**Cost only climbs outward, except at bosses and keystones.** Every cost knob sits in one block at the top
of `sim/hex_map.gd`. `CELL_GROWTH[region]` is the per-step multiplier: red multiplies it per ring from
`COST_FIRST`; a belt multiplies it per cell along its middle ring. A belt cell costs `belt_entry × growth^(f × L)`,
where `f` is its arc from the entry tip (0) to the exit tip (1) and `L` is the middle ring's length in cells,
so cells across the belt's width share a cost. `belt_entry` is the previous colour's `belt_exit` ×
`BELT_ENTRY_STEP`. A boss costs `BOSS_COST_MULTIPLIER` × its own colour's exit. `place_nodes` resets every
cell to `base_cost` and marks keystone slots up by `KEYSTONE_COST_MULTIPLIER`; keystone slots never depend
on unlocks, so a purchase never moves a price. There is no map file. Only node placement is randomised,
and it is a pure function of the run seed.

---

## The tick

`World.tick()` runs at a fixed **10 Hz**, driven by an accumulator in `Main._process`. Skill clocks
advance first, then five phases, each completing across all cells before the next begins:

| Phase | What happens |
|---|---|
| **Clocks** | Skill cooldowns and active windows count down one tick, so a skill buff switches only at a tick boundary. |
| **0. Resolve frontier** | Rebuild the frontier set and the generator count from the mined cells if the board or the purchases changed. |
| **1. Produce** | Every frontier cell spends its own emission countdown; each `EMIT_CHARGE` crossed is one emission (several per tick at high rates), rolling crit and splash and carrying the bounce count to its chosen neighbour. |
| **2. Deliver** | Orbs born `HOP_TICKS` ago deposit their value or waste it. Crossing the cost threshold mines the cell. Splash and bouncing orbs are queued; a splash whose orb bounces on waits `HOP_TICKS` (`Orb.splash_tick`), so the bounce picks its target before the splash can mine every neighbour. |
| **3. Splash** | Each queued splash whose wait is over (an orb, or a ram shot queued as an already-landed orb) hits its target and its target's mineable neighbours for a share of its value. |
| **4. Bounce** | Each queued bouncing orb emits a new orb from its target to a random mineable neighbour of that cell (the cell it came from included), for a share of its value and one bounce fewer; with Splashing bounces (or Ram splashing bounces, for a ram shot's chain) bought, that orb rolls for splash. With no neighbour to take, every bounce left lands on its target at once (a closed-form geometric sum). |

Orbs in flight sit in `HOP_TICKS` buckets by birth tick, each in spawn order. Deliver empties the
current bucket and the tick's spawns refill it, so **an orb never lands on the tick it is born** and no
orb is scanned before it lands.

The hot loops read `is_mineable` off a per-region open flag, refreshed at the start of every tick and
when a boss is mined. **Anything else that opens a region mid-tick must refresh it too.**

Phase 0 is separate from produce because the generator count is a condition the tick runs under, not
something that happens on a tick. Folded into the produce loop, a cell's interval would depend on
iteration order.

### Why order does not matter

- A frontier cell reads and writes only its own `emit_countdown`.
- Every roll is a hash of its keys, so it cannot depend on how far iteration has reached.
- Two orbs delivering into the same cell produce the same aggregate whichever lands first.
- Mining charges skill readiness with a clamped add, and nothing inside the tick reads readiness.
- The frontier and the generator count are **recomputed wholesale** (then sorted), never edited
  incrementally, so it is safe to rebuild them after a mine inside the deliver phase.

**The one deliver-phase write another delivery in the same phase can see is mining.** A later orb bound
for the same cell finds it mined rather than locked. It holds because what counts is capped by
`remaining()` and everything the cap turns away wastes: a cell needing 8 fed by orbs worth 5 and 10
books `delivered 8, wasted 7` in either order. Mining a boss also opens a region, but that only adds
mineable cells, and no orb in flight can be aimed at a cell that was closed when it fired.

**Every landing goes through `GraphCell.absorb()`.** A hit that covers `remaining()` snaps progress to
`cost` exactly; otherwise float rounding at huge costs could leave a cell a hair short forever.

**Splash runs in two passes.** First every hit's targets are chosen, and booked to `produced`, off the
board the deliver phase left; only then do hits land, capped by `remaining()` like a delivery. Choosing
targets while landing would let one splash's mine change another's target list.

**Bounce runs in two passes too.** It picks targets off the board splash left (its own splash is still waiting), spawning orbs that land on a
later tick and booking dead-end remainders to `produced`; only then do the remainders land, capped by
`remaining()`.

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

`ledger_balanced()` checks it within a relative tolerance (`LEDGER_TOLERANCE`), since float sums round;
`test_ledger_balances` asserts it every tick for 2,000 ticks while cells mine, crits fire, bounces chain and
rams land.

**Any new mechanic that creates or removes value must add a bucket.** A mechanic that only changes *how
much flows through an existing path* is exempt — crit, the crit multiplier, the orb multiplier, bounce, overcharge and achievement multipliers need
none, because `emit_orb` books the value it actually emitted; every bounce is a fresh emission. A splash hit behaves like an orb that lands
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
as progress. With Ram splash or Ram bounce bought, `used` is also queued as an already-landed orb
(`Orb.from_ram`) for the next tick's splash and bounce phases, which book it like any orb's.

⚠️ **That refund divides back through `_ram_bonus()`, and the two must stay inverses.** A full-strength
shot takes the `used >= damage` branch and zeroes the pool exactly. `test_ram_pool_empties_on_a_full_shot`
is the guard.

---

## Calculations

**Money is float (double); everything else is integer.** Costs, progress, orb values, the ledger, the
ram pool, the wallet and prices are doubles, reaching ~1e308. Counts, levels, percents, chances
(`Rng.SCALE` units), emission charge, timers and rolls stay integer.

### Constants (`sim/world.gd`)

| Constant | Value | Meaning |
|---|---|---|
| `TICK_HZ` | 10 | Simulation ticks per second |
| `HOP_TICKS` | 3 | Ticks to cross one hop |
| `BASE_ORB_VALUE` | 1 | What an orb launches with before the Power buff |
| `EMIT_CHARGE` | 200000 | Charge per emission; 20 ticks at the base rate of 10000 per tick |
| `RATE_PER_GENERATOR` | 2 | Percentage points of increased rate per generator |
| `CRIT_MULTIPLIER` | 5 | What a crit is worth before the shop's Crit multiplier |
| `SPLASH_PERCENT` | 50 | Share of a splash orb's value each neighbour takes, +25 per Splash strength |
| `BOUNCE_KEEP_PERCENT` | 50 | Share of its value each bounce keeps, +5 per Bounce strength; 100 while the Bounce skill is active |
| `OVERCHARGE_PER_LEVEL` | 1 | Percent orb value per generator, per Overcharge level |
| `ORB_MULTIPLIER` | 2.0 | Orb value multiplier per Orb value ×2 level |
| `RAM_CHARGE_PER_LEVEL` / `BOUNTY_PER_LEVEL` | 5 / 10 | Ram share and currency percent per level |
| `GENERATOR_CHANCE` | 0 | Odds a mined cell becomes a generator before purchases |
| `RAM_SHARE_PERCENT` | 20 | How much of a mined cell's cost the ram banks |
| `SPEED_SKILL_MORE` | 100 | Percent more emission rate while the Speed skill is active |
| `VISION_IDENTITY` / `VISION_RARITY` | 1 / 4 | Hops at which a node's name, and its glow, are visible; +1 per open colour past red |

Cost constants live in `sim/hex_map.gd`, node effects in `sim/node_catalog.gd`, shop prices in
`sim/meta_upgrades.gd`, skill timings in `sim/skill_state.gd`.

### Skills and the ram

- Every buff hex is a skill keyed by its buff id. Mining a cell adds 10 readiness to every unlocked
  skill not on cooldown, capped at 100.
- Activating a full skill zeroes readiness and starts a 300-tick cooldown and a 100-tick active window.
  Activation is a command issued between ticks.
- **Power's skill is the ram.** `can_ram_at` requires Ram bought (`unlock_ram`) and Power ready;
  `fire_ram` spends it. Main arms the ram on a hex click; the arming itself is view state.
- The pool banks nothing before Ram is bought, and never from a cell the ram itself, or its shot's
  splash and bounces (`Orb.from_ram`), finished — or the ram would feed itself. `test_ram_spends_only_what_it_lands` pins the second.
- Speed's active window is a *more* multiplier inside the one divisor; Crit's sets crit chance to 100%.
  Bounce's adds `1 + Glaive skill` bounces to orbs emitted while active, and bounces keep 100%. Splash
  charges and activates with no effect.

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

### Emission rate

⚠️ **The generator count and Speed are both *increased rates*, so they sum before they multiply:**

```
rate = (100 + generators×2 + speed_levels×10) × (100 + speed_skill) × achievement_rate
                                                    charge per tick, floored, at least 1
```

`speed_skill` is 100 while the Speed skill is active, else 0. A cell emits once per `EMIT_CHARGE` of
charge, so the rate is continuous and can exceed the tick rate. `Orb.lead_permille` records how early in
the tick an orb was emitted; only the view reads it, to stagger same-tick orbs.
`test_rates_sum_before_multiplying` pins it.

### The region wall

**One rule, three places:**

> A cell is mineable if it is unmined **and** its region is open. Red is always open; any other region
> opens once the boss guarding it has been mined.

- The **frontier** only targets mineable cells, and a delivery into an unmineable cell wastes.
- The **ram** only fires at mineable cells (`can_ram_at`), at any distance.
- The **shop** only sells an upgrade whose colour block is open: `MetaState.next_cost` returns -1
  otherwise. The gate lives in `sim/`, not only in the UI.

`World.region_open` is the board's rule: open in `MetaState`, **or** its boss is mined on this board, so a
fallen boss opens its colour mid-run. `World` never writes meta; `Main` banks each beaten boss with
`MetaState.open_region` when the run is banked, which opens the shop block and keeps the colour open in
later runs. Region keys are save keys but not upgrades. There is no colony entity in `sim/`: a rammed cell
far away is just a mined cell with a tiny perimeter inside an open region. `test_region_wall` pins all three.

### Upgrades

- Every `MetaUpgrade` belongs to a colour block (`region`), buyable once that region is open, and to a
  type group (`group`), which only decides where the shop draws it.
- `MetaState.buy_many` buys level by level until the count, the cap or the wallet stops it; `quote`
  prices the same levels without buying.
- Upgrades are **uncapped** (`MetaUpgrade.UNCAPPED`) unless the effect is bounded: generator chance
  (5 levels), splash levels (20, i.e. 100%), bounce strength (8, i.e. 90% kept), type and ram unlocks, Splashing bounces and the ram splash/bounce cards (1). Effective chances also
  clamp at 100% in `World`.
- **Crit levels are uncapped** because `NodeCatalog.crit_chance` has diminishing returns:
  `50% × levels / (levels + 9)`, which never reaches 50%.
- ⚠️ **Ram power and Ram charge are capped** so the ram's effective share of a cell stays well under
  100%. Past it, every rammed cell banks more than it cost and the ram feeds itself.
- Price is `cost_base × (cost_growth / 100)^level`, floored each step, saturating at `COST_CEILING`
  (1e300). The wallet saturates there too.
- Red and Bounce are hand-priced. Every other card past red prices its cards as a multiple of a per-colour unit
  (`PRICE_UNIT_FIRST`, ×`PRICE_UNIT_GROWTH` per colour), independent of the cell cost curve.
- **Everything must stay finite.** Belt costs compound across every colour; `test_economy_is_finite` fails
  when the dearest cell (with a keystone markup) or price leaves less than 100× headroom under the ceiling.
- Every block sells a **Power tier**, keyed `level_yield` for red and `level_yield_<colour>` beyond.
  `MetaUpgrades.bought_levels` sums tiers × `NodeCatalog.levels_in_region` into the run's bought levels.
- **One table sets Power per region**, `NodeCatalog.POWER_BY_REGION`. A shop tier and a found node
  (`GraphCell.node_grant()`) both read it, so the two never disagree.
- Upgrade keys are save keys and are never renamed.

### Achievements

- Held achievements are keys in `MetaState.achievements`, saved alongside levels; reset clears them.
- `Achievements.evaluate(meta)` grants every earned, unheld achievement. **Only `Main` calls it**: when a
  run is banked (after its bosses open their regions) and once on load. So a reward never switches mid-run.
- Progress is read from meta (`Achievements.progress`). A boss achievement is earned once the region it
  guards is open.
- Each achievement carries a *more* percent for emission rate and for orb value. `World` reads only their
  products (`rate_multiplier`, `value_multiplier`), which multiply last.
- Achievement keys are save keys and are never renamed.

### Randomness

**Every roll is a hash of its keys, never a stream.** `Rng.roll(seed, a, b, c)` returns 0..9999 from a
splitmix64 avalanche. Emission rolls key off `(cell_id, tick, emission × 1000 + orb_index)`; a bounce target off the
orb's `chain_key` (emission tick, cell, index; negative for a ram shot) and its bounces left; node placement keys off
`(run_seed, cell_id)` at board build. `test_rolls_are_pure` is the guard.

### Node distribution, and the dilution rule

> **A purchase must never lower your expected run.**

1. **Fixed slots.** The rarity roll never looks at what is unlocked. A slot whose rarity has no unlocked
   type stays **empty**, so buying a type fills empty slots and takes nothing away. Mandatory keystone
   slots (`GraphCell.is_keystone_slot`, fixed at build on each belt's middle ring) skip the roll and are
   always keystones.
2. **Additives and multipliers never share a table.** Power and Speed are commons; Crit and Splash are
   rares; Bounce is keystone-only (`NodeType.KEYSTONE`) and joins only the keystone pool. Rare Power
   rolls in its own band, and Power needs no unlock, so that slot is always filled.

The slot fixes the cell's tier (`GraphCell.tier`); `NodeCatalog.grant()` turns tier and region into
levels. Power multiplies region Power by `POWER_BY_TIER`; Bounce grants 1; other keystones grant
`KEYSTONE_LEVELS`. Bosses
hold no node.

`test_slots_are_fixed` pins both halves.

### Vision

One multi-source BFS from every mined cell, cached against `unlock_version`. Rarity is visible at range,
identity only up close.

---

## The two pull channels

`take_delivery_events()` and `take_mine_events()` are **the only data paths out of `sim/`**. The
simulation appends, the view drains. No signals, no callbacks.

Draining rather than clearing per tick matters: a frame can advance the simulation by many ticks before
it draws, and every event in that window must survive to be shown. Both are capped and evict
oldest-first; delivery events are fixed rings, and splash origins have their own ring, so landings never
evict them.

They stay **write-only from the simulation's side**. If any `sim/` code branches on them, iteration
order leaks into the economy. Neither touches the ledger.

---

## Determinism

| Property | Guaranteed by |
|---|---|
| Same inputs → same economy | Fixed iteration order, so float operations run in the same sequence; every roll a pure hash |
| Iteration order irrelevant | Phase separation, and wholesale recompute over incremental edit |
| No value appears or vanishes | The ledger invariant, within float tolerance |
| Same seed → same board | Costs a pure function of position; node placement keyed on `(run_seed, cell_id)` alone |
| Same board → same frontier | Rebuilt wholesale from mined cells and sorted; an all-dud frontier resolves empty |
| Same seed → same generators | The generator roll is a pure hash of `(seed, cell_id)` |
| Same board → same visibility | One multi-source BFS, cached against `unlock_version` |
| Same meta → same economy | `from_dict` forces levels through `int()` and the wallet through `float()` |
| Same board → same earnings | `earned` is a sum of per-cell constants over cells that mine exactly once |

A stateful RNG stream would break these. It is not forbidden, but it is an architectural decision.

---

## View and input

`Main` owns the `World`, accumulates real time, and steps the sim at a fixed rate; the view interpolates
between ticks with `render_alpha`. There is no node per cell, orb or mark: a `+8` or a splash is an entry
in a list.

**The board draws in two layers.** Still ground lives in spatial chunks, each its own canvas item,
redrawn only when a cell's *look* (visibility, mined, generator, frontier, region open) changes. The
overlay is drawn every frame and holds only what moves: breathing frontier cells, pulsing unmined bosses
and keystones (drawn larger than a cell), progress on cells being fed, pops, and the ram.

**Orbs and splash bursts are GPU-animated ring buffers**: the CPU writes a slot once (an orb on its
birth tick, a burst on spawn) and the shader animates it from birth, so cost does not grow with how many
are alive. `Main` merges a drain's landings per cell and caps rings, bursts and texts per frame.
Antialiasing is MSAA, plus `fwidth` edges in the splash shader.

**The UI is Control scenes; the board is drawn in code.** The HUD and the shop are `.tscn` files under
`scenes/ui/` sharing `theme.tres`. Layout containers ignore the mouse, so board input still reaches
`Main._unhandled_input`; only buttons, hexes and the ram meter take it. Buttons never take focus, or
Space and Enter would stop reaching `Main`.

**Transient effects never starve.** Full effect layers replace their oldest entry rather than reject
the new one.

**Sound is a density, not a voice per event.** `Main` maps drained events to cues from the bank;
`SoundManager.request` only counts. Once per frame each requested cue plays at most once, louder by
the log of its request count, respecting `min_interval`, its own `max_voices` (stops its oldest) and a
global polyphony (steals the oldest voice of equal or lower priority). Board sounds are culled to the
camera rect and skipped for stale events; launches are orbs with `ticks_in_hop == 0` after the frame's
ticks, so `sim/` has no audio channel. Buses: `Board` and `UI` into a hard-limited `Master`.

**`Main` owns a run phase — running or shopping — and it gates the tick.** The shop is open exactly when
the simulation is frozen and the next board has been built, so a purchase always lands on a board with
nothing mined on it. Buying re-places nodes on that board's own seed.

**The shop has two tabs, Upgrades and Achievements**; it opens on Achievements when the bank just
granted one. **Upgrades draws every upgrade, by type group**: open ones in their colour, a
closed block's grey, and a `hidden` one as a question mark while closed. The stat table previews the
hovered purchase by building a throwaway `World` over the waiting board with a `MetaState.copy()`.

**There is one board gesture: throw the ram** — click the ready Power hex to arm it, then click a
cell. The other hexes are clicks too; everything else on screen runs itself.

---

## Testing

**The suite is deliberately small.** A test earns its place only when it pins an invariant that is
invisible on screen and silent when broken.

Twelve tests: ledger conservation, tick order-independence, the region wall (frontier, ram and shop), the
rates summing before they multiply, RNG purity, the dilution rule, the dud-frontier stall, run 1 funding the first
purchase, three ram guards (spend only what lands and bank nothing from its own kill, a full shot
empties the pool, the early ram is affordable), and the economy staying finite.

---

## Deliberately not built

- **A failure state.** No clock, no threat. The region wall and the shop blocks supply the run's shape.
- **Level-up cards.** Cards would be the layer that grants *verbs* while nodes grant *numbers*.
- **Node synergies.** With five types there is little to combine.
- **Per-blob income.** Perimeter and the cost gradient already throttle distant colonies.
