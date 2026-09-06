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

Two resource tiers (red and orange) and four block types (generator, pump, sphere, upgrader) are built
and playable, plus three one-off **challenge cells** that grant permanent board-wide buffs. The map is a
honeycomb uncovered by playing it rather than handed over whole; generators and upgraders are anchored
where you find them, and pumps and spheres are what you rearrange. Half the cells bury something.

**Orange is the first real gate.** Cells state the colour that opens them: the middle of the board takes
red, orange starts appearing around 5–7 hops out, and everything past 8 hops takes orange and nothing
else. Only an upgrader makes orange, and only red feeds an upgrader, so the outer third of the map stays
shut until you have found one and built a line to it. There are no orange *generators* — orange is never
produced, only converted.

Everything else in the pitch above — the other four tiers, distributors, teleports, upkeep — is design
intent, not code. See *Not built yet* at the bottom.

---

## The loop

1. **Aim** a source at a cell you can see but have not mined, and that takes the colour it makes.
   Unaimed generators idle; they never bank progress. An upgrader is the exception — it banks whatever
   is routed into it whether or not it is aimed.
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
| **Sphere** | Radiates to every block within **2 hops**: generators there produce **4 ticks faster**, pumps there restore **+1 more**. Spheres stack, so a block reached by two gets both. Movable. |
| **Upgrader** | Banks **60** delivered red, then launches one **orange** orb at its target. Idles with no target, but banks anyway. **Anchored.** |
| **Surge** | A challenge. Every generator on the board launches its orbs with **+5** value. Anchored. |
| **Current** | A challenge. Every pump on the board restores **+2** more. Anchored. |
| **Lens** | A challenge. Every sphere on the board reaches **50% further** — 2 hops becomes 3. Anchored. |

A sphere is the odd one out: it never *does* anything on a tick, it just **is somewhere**. Aim it at
nothing, and it has no cooldown to watch. What it changes is the numbers every other block nearby runs
on, which is why the board draws its field rather than pulsing it. Two consequences worth knowing:

- **It only radiates once its own cell is mined.** A sphere still buried is a sphere doing nothing.
- **Generators floor at 5 ticks.** Stacking spheres on one generator pays off up to four of them and
  not past it, so blanketing a single source is worse than spreading the field over several.

### Colours, and the upgrader

Every cell states the colour that opens it. Red cells take red orbs; orange cells take orange and
nothing else — a red orb arriving at an orange cell counts for **nothing**, not for a little. The board
says which is which: a locked cell is tinted by the colour it demands, in its fill, its ring, its price
and the arc that fills as it is fed. The panel names it too.

You will not do it by accident. **Aiming a red source at an orange cell is refused**, the same way
aiming at a mined cell or into the dark is refused — the preview turns red and says *needs orange*.
The rule is worth teaching by refusal rather than by waste: there is no way to quietly pour a
generator's whole output into a cell that was never going to take it.

**Where orange comes from.** Nothing produces it. An **upgrader** is a generator with the clock taken
out of it: its progress bar is filled by orbs *you* routed into it, and at 60 banked red it launches one
orange orb at its target. So an upgrader has to be the target of a generator before it is a source of
anything, and a working orange line is really two lines — red into the converter, orange out of it —
both of which have to survive decay.

Four consequences, and all of them follow from that:

- **An upgrader is anchored**, like a generator and for the same reason. Swapping is free and unlimited
  in range, so a movable converter could be parked beside the frontier and the orange half of every
  route would collapse to one hop.
- **It banks while idle.** Mining a cell unaims everything pointed at it, so a converter that refused
  orbs whenever it had no target would throw away everything in flight during that window.
- **It only takes the orb that stops there.** An orb merely routed *across* an upgrader is untouched,
  so a converter cannot be used as a toll gate on somebody else's line.
- **A sphere does nothing for it.** There is no interval to shorten and no restore to raise. Parking one
  next door is wasted; what makes a converter faster is feeding it faster.

**The shape this gives the game.** Red opens the middle of the board on its own. Somewhere around 5–7
hops you start meeting cells you cannot pay for while red still works everywhere else, which is where
the colour gets taught. Past 8 hops there is no red left at all, and the rim is shut until you have
mined an upgrader, found a generator to feed it, and pushed an orange line out of it. Since an upgrader
never moves, *where the map buried yours* decides where orange can reach — exactly the question
anchoring already asks about red, one tier up.

The map guarantees you can always get started: **every buried upgrader sits on a red cell.** An
orange-gated upgrader could only be paid for in orange, which only an upgrader can make, and the
generator refuses to emit a map with that deadlock on it.

### Challenge cells

Three cells on the map are **triangles**. They cost **six times** what an ordinary cell at the same
distance costs, and mining one grants a permanent bonus that applies to the **whole board** rather than
to anything nearby.

The point is that you can see one coming. Every other unmined cell is a question mark and a price; a
challenge is a *triangle* and a price, so you know from the moment it comes out of the fog that there is
something worth saving for out there. What you do not know is which of the three you are buying — the
glyph is the same question mark, and the shape only tells you the category. Knowing a hard thing is
coming is what makes it a goal; knowing exactly what it pays would turn the decision into arithmetic.

| Challenge | Grants |
|---|---|
| **Surge** | +5 to the value every generator launches with. This is the only thing in the game that extends *unaided* reach — 9 hops becomes 14 |
| **Current** | +2 to every pump's restore, everywhere, with no sphere needed |
| **Lens** | +50% sphere radius: 2 hops becomes 3, which roughly doubles the blocks each sphere covers |

Four rules, all of which follow from the buff being board-wide:

- **Anchored, like generators, but for the opposite reason.** A generator is pinned because moving it
  would trivialise decay. A challenge is pinned because its bonus reaches everywhere from anywhere, so
  there is no placement to get right — leaving it movable would be a chore, not a choice.
- **A sphere does nothing to one.** A challenge has no interval to shorten and no restore to raise, so
  parking a sphere next to it is wasted. It is not a block to support; it is a thing you bought.
- **It grants nothing while buried.** Mining is the whole transaction, so the board does not pay out
  first.
- **They arrive in a fixed order, nearest first.** The Surge sits about 4 hops out, the Current around
  8, the Lens around 9 — so they land as milestones across a playthrough rather than all at once. The
  first is cheap enough to teach you what a triangle means while the board is still affordable; by the
  time the Lens is in range, the +50% is worth the several thousand it costs.

The trade is always the same: a challenge is a **detour**. You stop pushing the frontier and pay six
times over for something whose payout you cannot see. What makes it worth it is that the bonus is
retroactive across your entire network — every pump you have already placed gets stronger the moment the
Current lands.

### Idle blocks

A mined cell absorbs nothing, so aiming at one is throwing output away. The game will not let you: you
cannot aim at a mined cell, and **the moment a cell is mined, everything aimed at it is released** and
its orbs in flight are called back. Finishing a cell always hands you a generator wanting work.

**The one exception is a cell holding an upgrader**, which is mined and still takes deliveries — that is
the whole point of it. So "you cannot aim at a mined cell" is really "you cannot aim at a mined cell
with nothing to feed", and a converter is the first thing on the board with an appetite.

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
| Sphere field | 2 hops | Every block within reach reads the bonus |
| Sphere interval bonus | −4 ticks | Per sphere in range, stacking |
| Sphere restore bonus | +1 | Per sphere in range, stacking |
| Interval floor | 5 ticks | No stack of spheres takes a generator below this |
| Upgrade cost | 60 red | Banked delivered value per orange orb launched. A sphere does not reduce it |
| Orange orb value | 10 | Same as red — an orange orb decays and is pumped exactly like one |
| Orange band | 5–7 hops | Where orange cells start appearing, mixed in among red |
| Orange from | 8 hops | Past here every cell is orange |
| Orange cost | red curve ÷ 4 | So an orange cell is ~1.5× a red one in real terms, not 6× |
| Unlock cost | `50 × 2 ^ (hops − 1)` | 50 on the ring around the start, doubling per hop after. The start itself costs 0 |
| Challenge cost | ×6 | Six times the normal cost for that distance — about three extra hops' worth of the ramp |
| Surge | +5 orb value | Board-wide, once mined |
| Current | +2 pump restore | Board-wide, stacks on top of any sphere |
| Lens | +50% sphere radius | Board-wide; 2 hops becomes 3, rounding down |

### What those numbers mean in play

- **Unaided reach is 9 hops.** An orb dies on the tenth. A cell at 9 hops receives 1 value per orb.
- A route's arrival value is **`10 − hops + 3 × pumps passed`**. The HUD shows it before you commit.
- **Pumps stack and there is no ceiling.** Two pumps early on a short route deliver *more* than a fresh
  orb is worth. Three pumps buy nine extra hops of range, wherever you put them.
- **Where you put them decides whether the orb lives, not what it carries.** Arrival depends only on how
  many pumps the orb passes, not their spacing. But a pump cell nets +2 and a plain cell −1, so a supply
  line holds indefinitely only while its pumps sit **3 hops apart or closer**. At 4 apart it bleeds a
  point per stretch and eventually dies mid-route — carrying nothing, having cost you the same orbs.
- **Cost is geometric, and that is the shape of the whole game.** Each hop out doubles: 50 at one hop,
  800 at five, 51,200 at eleven — before the orange divisor, which quarters everything past the band.
  Clearing the board takes **75,150 red and 113,600 orange**, and at 60 red per orange orb that orange
  half is worth around 680,000 red of generator output. The second tier is most of the game.
- **Your side compounds too, which is why cost has to.** Every pump you find adds +3 to every orb on
  every route through it, forever; every sphere speeds every generator near it. Reach and throughput
  both grow multiplicatively as you dig, so a cost curve that only added a constant per hop would leave
  the far rim *cheaper* in real terms than the near ring — which is exactly what it used to do.
- The practical read: your first cell is 50, about six orbs from a bare generator, and the ring after it
  is 100. A cell at 8 hops costs 1,600 in *orange*, and delivering that means a red line into an
  upgrader and an orange line out of it, both pumped — not a generator pointed at it.

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

**106 cells in a honeycomb.** 72 of them have exactly three neighbours, 26 around the rim have two, and
a single hub near the middle has six with seven cells at four around the two hubs — so the board is
almost uniformly three-way, and the junctions stand out. It is 19 hops across, and you open in the
*centre*, so the number that matters is the radius: 11 hops to the farthest corner, against an unaided
reach of 9.

You start on cell 45 with three neighbours uncovered and the other 105 cells dark. The frontier then
grows outward on every side at once, rather than sweeping across from a corner.

**53 of the 106 cells bury something: 10 generators, 20 pumps, 15 spheres, 5 upgraders, 3 challenges.**
The other 53 are empty. At least one cell cannot be mined without a pump chain — few, because ten
anchored generators cover most of a board this size on their own, but the map is not allowed to ship
until at least one cell is out of reach of all of them.

The five upgraders sit at **2, 3, 3, 4 and 5 hops**, ringed around the start and all on red cells. They
are close in because they have to be affordable with red alone; what is far away is everything they
then have to reach.

Unlock costs run `50 × 2 ^ (hops − 1)`, from **50** on the ring around you to **51,200** in the far
corner before the orange divisor quarters it to 12,800. The three challenges cost six times their ring:
the **Surge 4,800** at 5 hops and the **Current 19,200** at 7, both in red, and the **Lens 38,400** at
10 hops in orange. Clearing everything takes **75,150 red and 113,600 orange**.

**59 cells take red and 47 take orange**, split at 8 hops with 25 of the orange ones mixed into the
5–7 band. The furthest red cell is 7 hops out against a board radius of 11, so the outer four rings are
orange-only — the generator refuses to emit a map where red reaches the rim, since that would make the
second tier decorative.

**Why a honeycomb rather than a hex patch.** A hex lattice gives every cell six neighbours, and six
neighbours means you route around any obstacle and there are dozens of equally short paths between any
two points — compact, and decay stops mattering. So the centre of every hexagon is removed, leaving each
surviving cell with the three edges that form its rim. That is a genuine web with genuine detours, and
it is what makes a route long enough to be worth supporting. A couple of centres are kept as hubs, and
they are the only places the board opens up.

The generator asserts the properties the game leans on, and refuses to emit a map that misses any of
them: the board is connected, no cell is a dead end, it is at least 12 hops across, the far corner is
outside unaided reach, exactly one cell starts mined (discovery grows one connected region outward, and
two starting points would leave two regions with no route between them), the map **is** finishable with
generators anchored, it is **not** finishable without pumps, and each challenge appears exactly once at
a strictly greater distance than the one before it.

The colour gate gets its own four, because a gate can make a cell genuinely unmineable in a way no buff
can: every cell past 8 hops takes orange and no red cell reaches the rim, at least one orange cell falls
inside the 5–7 band so the colour is met as a scatter rather than as a wall, every buried upgrader sits
on a red cell, and the board **stops** being finishable if the upgraders are taken away. That last one
is the same test the pumps get — a tier that can be ignored is decoration.

---

## Not built yet

Design intent from the pitch, with what each would cost. The tick is phased so all of these are
additive; see `architecture.md` for the hooks.

| Block | Idea | Needs |
|---|---|---|
| **Distributor** | Splits one colour across many outputs | Multiple output ports per block; `on_orb_deliver` already exists |
| **Teleport** | Folds two distant cells into one hop | Mutable adjacency; the path cache is already dropped on unlock, so this extends that to placement |
| **Upkeep** | Burns a trickle to hold a global buff | A stats pass, plus hysteresis so marginal upkeep doesn't strobe |

**Tiers 3–6** (yellow, green, blue, purple) are defined in `sim/tiers.gd` with names and colours but are
otherwise unused. Each needs an upgrader variant that converts into it and a band of the map that
demands it — both of which are now one catalog entry and one generator constant, since orange built the
machinery.

**No orange generator.** Orange is only ever converted, never produced, which is what makes the red line
feeding a converter part of the network rather than a formality. `BlockCatalog` already paints a
generator from its `output_tier`, so adding one is a single field the day it is wanted.

**A sphere does nothing for an upgrader.** It has no interval to shorten and no restore to raise, and
giving it a charge discount would be a third kind of field bonus — worth deciding on its own rather than
inheriting by accident.

**The ledger is one set of numbers, not one per colour.** It balances across a conversion because red
absorbed and orange minted are an ordinary sink and an ordinary source. A per-colour readout would be a
HUD nicety; the invariant does not need it.

**The sphere's tier gate** is the one piece of a built block still outstanding. The pitch has it buffing
"everything *weaker* than it nearby"; today it buffs everything nearby. With two tiers in play this is
now a condition that *can* fail, so the gate has become a real decision rather than a no-op — it is
deferred rather than blocked.
