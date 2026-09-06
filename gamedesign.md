# Spread — an incremental resource-routing game

## The pitch

You wake up inside a vast, dormant network. Cells are scattered across the space, connected by paths you
can't yet see the value of — until you start feeding them.

Every cell needs to be paid to open. Point a working generator at a locked cell, and its output starts
flowing toward it, cell by cell, along the shortest path the network can find. Feed it enough and it
wakes up, handing you whatever was buried inside it — sometimes a generator, sometimes a pump, often
nothing at all. What you dig up is yours to move: any two cells you've mined can trade contents, so the
network you end up with is the one you arrange, not the one you were given.

Resources come in six tiers, red to purple, cheap to rare. Basic generators produce red at the edges of
the map. Upgraders consume several units of one tier to output a single unit of the next — the deeper
you push, the more valuable (and expensive) everything gets. Distributors split one colour across as
many outputs as you like. Spheres radiate an efficiency bonus to everything weaker than them nearby.
Teleports fold distant corners of the map together, turning a costly detour into a free hop. Upkeep
cells quietly burn a steady trickle of resource to keep a global buff alive — faster generators, wider
spheres, safer travel — as long as you keep them fed.

And travel isn't free: every orb that sets out on a long, unsupported route risks never arriving. Decay
eats at anything crossing unclaimed distance, and it's on you to decide when a route is worth the risk
and when it's time to move a pump into the gap — or a teleport — to make it safe.

There's no clock, no rival, no combat. Just you, an idle engine that gets smarter every time you
rearrange it, and a graph that gets a little more yours every time a new cell lights up. Push outward,
chain your tiers, tune your placements, and watch the whole thing hum — until every last cell on the map
is finally, quietly, yours.

---

## Current state

One resource tier (red) and two block types (generator, pump) are built and playable. Everything else in
the pitch above — the other four tiers, upgraders, distributors, spheres, teleports, upkeep — is design
intent, not code. See *Not built yet* at the bottom.

---

## The loop

1. **Aim** a generator at a locked cell. Unaimed generators idle; they never bank progress.
2. Orbs travel the shortest path, **losing value every hop**. What arrives is what counts.
3. When a cell has absorbed its full cost it is **mined**, and yields whatever the map buried in it.
4. **Swap** what you found to where it earns more — a pump into a gap, a generator closer to the
   frontier.
5. The frontier moves. Repeat until every cell is mined.

The tension is entirely spatial. Value is not scarce — generators make it from nothing — but *reach* is.
A cell ten hops out is unreachable no matter how long you wait, and the only fix is rearranging the
network.

---

## Mechanics

### The graph

Cells at fixed positions, joined by undirected edges. **Distance is hop count only** — a long edge costs
exactly as much as a short one. Locked cells are freely traversable; they simply offer no support to
orbs crossing them, so there are no reachability puzzles, only decay ones.

### Mining

Every cell has an unlock cost and predetermined contents, both **visible from the start** — mining order
is a planning problem, not a gamble. Delivered value accumulates until the cost is met; overshoot is
discarded. A mined cell installs its buried block, or stays empty if there was nothing in it.

### Orbs and decay

An orb carries an integer value, spends a fixed time crossing each edge, and loses value on entering
each new cell. At zero it evaporates and delivers nothing. Two rules matter more than they look:

- **Decay resolves before a pump fires.** An orb arriving at a pump on its last point of value dies — it
  didn't make it to the pump.
- **A block never acts on an orb's final cell.** Otherwise parking a pump next to a target would make
  every delivery land at full value.

### Blocks

| Block | Does |
|---|---|
| **Generator** | Emits a full-value orb at its aimed target on a fixed interval. Idles with no target. |
| **Pump** | Restores orbs *passing through* back to full value. Does nothing to orbs that stop there. |

**Blocks are never built or destroyed** — only mined and moved. The map fixes how many exist. That is
what makes placement a real decision: a generator moved to the frontier is one no longer serving home.

### Swapping

Any two mined cells can exchange contents, free, instantly, at any distance. Swapping against an empty
cell is a move. Two consequences:

- Orbs already in flight from either cell are **cancelled** — an orb belongs to the route that launched
  it.
- A block that lands on the cell it was aiming at is **unaimed** rather than left aiming at itself.

### Win condition

Every cell on the map mined. No timer, no failure state.

---

## Balance

These match the constants in `sim/world.gd` and `sim/block_catalog.gd`. **Keep this table in sync when
tuning.**

| Value | Setting | Effect |
|---|---|---|
| Tick rate | 10 Hz | Simulation step |
| Hop time | 10 ticks | 1 second to cross one edge |
| Orb value | 10 | Also the ceiling a pump restores to |
| Decay | 1 per hop | Charged on entering each new cell |
| Generator interval | 20 ticks | One orb every 2 seconds |
| Pump restore | 10 | Back to full |

### What those numbers mean in play

- **Unaided reach is 9 hops.** An orb dies on the tenth. A cell at 9 hops receives 1 value per orb.
- **Pumps must sit no more than 9 hops apart** along a route, or the chain breaks.
- A route's arrival value is `10 − (hops since the last pump)`. The HUD shows this before you commit.
- Cost per orb rises sharply with distance: a cell at 8 hops takes ~40 orbs, one at 2 hops takes 5.

### The map — *First Light*

35 cells in five ring-shaped clusters joined by bridges. Diameter 13 hops. 5 generators, 8 pumps, the
rest empty. Unlock costs scale as `25 + 7 × hops from start`.

Two distinct routes run from home to the middle of the map; beyond that it is a chain. Five cells sit
outside unaided range, so the far side is unreachable until a pump chain exists.

Generated by `tools/gen_map.py`, which asserts the properties the game depends on: connected, diameter
≥ 12, no dead-end cells, some cells out of unaided range, and at least one pump reachable *without*
already having one — otherwise the map is unwinnable from the opening move.

---

## Not built yet

Design intent from the pitch, with what each would cost. The tick is phased so all of these are
additive; see `architecture.md` for the hooks.

| Block | Idea | Needs |
|---|---|---|
| **Upgrader** | Several units of tier N → one of N+1 | A second tier; an `on_orb_deliver` hook |
| **Distributor** | Splits one colour across many outputs | `on_orb_deliver`; multiple output ports per block |
| **Sphere** | Radiates a bonus to lower tiers nearby | An effective-stats pass ahead of production |
| **Teleport** | Folds two distant cells into one hop | Mutable adjacency, which breaks the permanent path cache |
| **Upkeep** | Burns a trickle to hold a global buff | A stats pass, plus hysteresis so marginal upkeep doesn't strobe |

**Tiers 2–6** (orange, yellow, green, blue, purple) are defined in `sim/tiers.gd` with names and colours
but are otherwise unused. They only become meaningful alongside the upgrader.
