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

One resource tier (red) and two block types (generator, pump) are built and playable; the map is a hex
lattice uncovered by playing it rather than handed over whole; generators are anchored where you find
them and pumps are what you rearrange. Everything else in the pitch above — the other four tiers,
upgraders, distributors, spheres, teleports, upkeep — is design intent, not code. See *Not built yet* at
the bottom.

---

## The loop

1. **Aim** a generator at a cell you can see but have not mined. Unaimed generators idle; they never
   bank progress.
2. Orbs travel the shortest path **through ground you have uncovered**, losing value every hop. What
   arrives is what counts.
3. When a cell has absorbed its full cost it is **mined**. Only then do you find out what was in it.
4. Mining also **uncovers that cell's neighbours**, so the visible edge of the map moves outward.
5. The generator that was feeding it **goes idle**, because a mined cell consumes nothing. It waits for
   you to point it somewhere new rather than quietly emptying itself into a finished cell.
6. **Move a pump** into the gap that is costing you the most. Generators stay where you found them —
   what you rearrange is the support between them and the frontier.
7. Repeat until every cell is mined.

The tension is spatial. Value is not scarce — generators make it from nothing — but *reach* is, and so
is knowledge. You cannot plan around a cell you have not uncovered, you cannot route through the dark to
get to one, and you cannot carry your generator over to it either.

---

## Mechanics

### The graph

Cells at fixed positions, joined by undirected edges. **Distance is hop count only** — a long edge costs
exactly as much as a short one. Locked cells are freely traversable, as long as you have uncovered them;
they simply offer no support to orbs crossing them.

### Discovery

You start seeing one mined generator and the cells touching it. Everything else is not there: not
dimmed, not greyed, simply absent, along with the edges leading to it.

**Mining a cell uncovers its neighbours.** That is the only way the map opens up, so the visible region
is always the mined region plus one ring around it.

An uncovered cell you have not yet mined shows its **price but not its contents** — a question mark.
What is buried is fixed from the start and never rerolled; you just do not get to see it until you have
paid for it. Mining is what tells you whether you bought a generator, a pump, or nothing at all.

**The dark is an obstacle, not a curtain.** Orbs cannot cross cells you have not uncovered, and you
cannot aim at them. If the short way round runs through the dark, your orbs take the long way — and
uncovering that shortcut later genuinely improves your network. Every cell you can legally aim at is,
by definition, one hop from something you have already mined.

### Mining

Every uncovered cell shows its unlock cost. Delivered value accumulates until the cost is met; overshoot
is discarded. A mined cell installs its buried block, or stays empty if there was nothing in it.

### Orbs and decay

An orb carries an integer value, spends a fixed time crossing each edge, and loses value on entering
each new cell. At zero it evaporates and delivers nothing. Two rules matter more than they look:

- **Decay resolves before a pump fires.** An orb arriving at a pump on its last point of value dies — it
  didn't make it to the pump.
- **A block never acts on an orb's final cell.** Otherwise a pump parked on a target would hand every
  delivery into it a free +3, and the best place for every pump you own would be obvious and boring.

### Blocks

| Block | Does |
|---|---|
| **Generator** | Emits a full-value orb at its aimed target on a fixed interval. Idles with no target. **Anchored** — it never moves from where you found it. |
| **Pump** | Adds a flat **+3** to orbs *passing through*, and pumps stack. Does nothing to orbs that stop there. Movable. |

### Idle blocks

A mined cell absorbs nothing, so aiming at one is throwing output away. The game will not let you: you
cannot aim at a mined cell, and **the moment a cell is mined, everything aimed at it is released** and
its orbs in flight are called back. Finishing a cell always hands you a generator wanting work.

Because that happens on every single cell, and because the generator in question may be far off-screen
behind ground you have already cleared, the bottom-right corner keeps a **count of idle blocks by type**
— the block's own glyph with a number beside it. Clicking one flies you to the next idle block of that
type and selects it, so `A` aims it straight away. Click again for the one after that; it wraps.

**Blocks are never built or destroyed** — only mined, and moved if they can be. The map fixes how many
exist.

### Anchoring

**A generator stays where the map buried it. Forever.** You cannot pick it up, and you cannot displace
it by swapping something onto its cell. Everything you can do with a generator, you do from where it is:
aim it, or reach it.

This is the rule the whole game leans on, so it is worth saying why it exists. Swapping is free, instant
and unlimited in range. If generators moved, you would simply walk one to the edge of the frontier every
time, deliver at 9 of 10 on every single cell, and never build anything — which is exactly what the game
did before, and it made decay a formality. Anchored, a generator's reach is fixed by where it sits, and
**extending that reach is what pumps are for**.

So the map hands you a fixed set of anchored sources scattered across the board, and the real question
becomes: can you push far enough out from the ones you have to uncover the next one? Each generator you
find is a new place the network can grow from.

### Swapping

Any two mined cells can exchange contents, free, instantly, at any distance — provided neither holds an
anchored block. In practice that means **pumps are what you move**. Swapping against an empty cell is a
move. Two consequences:

- Orbs already in flight from either cell are **cancelled** — an orb belongs to the route that launched
  it. In practice nothing is cancelled today, since only generators emit and they never move.
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
| Orb value | 10 | What an orb launches with. **Not** a ceiling — pumps can push it higher |
| Decay | 1 per hop | Charged on entering each new cell |
| Generator interval | 20 ticks | One orb every 2 seconds |
| Pump restore | +3 | Flat, uncapped, and stacks with every other pump on the route |

### What those numbers mean in play

- **Unaided reach is 9 hops.** An orb dies on the tenth. A cell at 9 hops receives 1 value per orb.
- A route's arrival value is **`10 − hops + 3 × pumps passed`**. The HUD shows it before you commit.
- **Pumps stack and there is no ceiling.** Two pumps early on a short route deliver *more* than a fresh
  orb is worth. Three pumps buy nine extra hops of range, wherever you put them.
- **Where you put them decides whether the orb lives, not what it carries.** Arrival depends only on how
  many pumps the orb passes, not their spacing. But a pump cell nets +2 and a plain cell −1, so a supply
  line holds indefinitely only while its pumps sit **3 hops apart or closer**. At 4 apart it bleeds a
  point per stretch and eventually dies mid-route — carrying nothing, having cost you the same orbs.
- Cost per orb rises sharply with distance: a cell at 8 hops takes ~40 orbs, one at 2 hops takes 5.

### Why anchoring was necessary

Worth recording, because for a while the game did not work and it was not obvious why.

Every cell you can legally aim at is one hop from mined ground — that is what being uncovered means. So
when generators were movable, and swapping was free, instant and unlimited in range, the optimal play
was always the same: walk a generator up to the frontier and deliver at **9 of 10**, on every cell, for
the whole game. A scripted playthrough confirmed it — the entire map fell with a mean arrival of 9.0 per
orb and no pump chain ever built. Decay and pumps had stopped gating reach and were gating, at most,
convenience.

Anchoring generators fixes it at the source. Reach is now a property of where the map put your sources,
and the only way to extend it is a pump chain. Pumps went additive at the same time and for the same
reason: restoring to a cap made one pump as good as three, so there was never a reason to commit more
than one to a route. Flat and stacking, every pump you spend buys three more hops, and the question
becomes how many you can afford to leave on a line rather than whether to bother with a second.

The board is now checked against exactly this. `tools/gen_map.py` plays the map twice — once with pumps
and once without — and refuses to emit a map unless the first clears it and the second **fails**. If the
whole thing can be finished without ever placing a pump, it is not a map worth shipping.

### The map — *First Light*

36 cells on a 7×6 hex lattice, six of them carved out as barrier walls. Most cells have six neighbours,
so there are many equally short routes between any two — the board reads as a web rather than a set of
corridors. Diameter 13 hops. 5 generators, 5 pumps, the rest empty. Unlock costs scale as
`25 + 7 × hops from start`, from 32 out to 102.

You open on cell 0 in the top-left corner with just two neighbours; the other 33 cells are dark. One of
those two is a second generator, so the first thing the map does is offer you a choice of where to grow
from. **Five cells cannot be mined at all without a pump chain** — the generator asserts that by playing
the map with its pumps taken away and checking that it gets stuck.

Hex is compact, which is why the walls are there: a plain 7×6 hex patch is only 9 hops across, exactly
unaided reach, and decay would never have mattered. Scattered holes do not help — with six neighbours
you just go around them. Walls do.

Generated by `tools/gen_map.py`, which asserts what the game depends on: connected, diameter ≥ 12, no
dead-end cells, exactly one cell handed over already mined (discovery grows a single connected region
outward from it, and two starting points would leave two regions with no way to route between them), the
map is finishable with generators anchored, and it is *not* finishable without pumps.

---

## Not built yet

Design intent from the pitch, with what each would cost. The tick is phased so all of these are
additive; see `architecture.md` for the hooks.

| Block | Idea | Needs |
|---|---|---|
| **Upgrader** | Several units of tier N → one of N+1 | A second tier; an `on_orb_deliver` hook |
| **Distributor** | Splits one colour across many outputs | `on_orb_deliver`; multiple output ports per block |
| **Sphere** | Radiates a bonus to lower tiers nearby | An effective-stats pass ahead of production |
| **Teleport** | Folds two distant cells into one hop | Mutable adjacency; the path cache is already dropped on unlock, so this extends that to placement |
| **Upkeep** | Burns a trickle to hold a global buff | A stats pass, plus hysteresis so marginal upkeep doesn't strobe |

**Tiers 2–6** (orange, yellow, green, blue, purple) are defined in `sim/tiers.gd` with names and colours
but are otherwise unused. They only become meaningful alongside the upgrader.
