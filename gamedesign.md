# Spread — an incremental resource-routing game

## The pitch

You wake up inside a vast, dormant network. Cells are scattered across the space, connected by paths you
can't yet see the value of — until you start feeding them.

Every cell needs to be paid to open. Point a working generator at a locked cell, and its output starts
flowing toward it, cell by cell, along the shortest path the network can find. Feed it enough and it
wakes up, handing you whatever was buried inside it — sometimes a generator, sometimes a pump, often
nothing at all. What you dig up is yours to move: any two cells you've mined can trade contents, so the
network you end up with is the one you arrange, not the one you were given.

Resources come in seven tiers — red, orange, yellow, green, teal, blue, purple — cheap to rare. Every
colour has generators of its own, buried out in the ring of the map that demands it. Upgraders consume several units of one tier to output a single unit of the next — the deeper
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

All seven resource tiers and five block types (generator, pump, sphere, upgrader, upkeep) are built and
playable, plus **challenge cells** that grant permanent board-wide buffs, three in every colour band.
The map is a honeycomb uncovered by playing it rather than handed over whole; generators and upgraders
are anchored where you find them, and pumps, spheres and upkeep blocks are what you rearrange. Half the
cells bury something.

**Routes are yours to draw.** An orb takes the shortest path by default, but you can bend one through
cells you pick — the extra hops cost decay, and what they buy is passing pumps the short way round would
have missed.

**The colour ladder is the shape of the whole game.** Cells state the colour that opens them, and which
colour that is follows how far out the cell sits: red for the first ten hops, then orange, yellow,
green, teal, blue, and purple at the rim. Pushing the frontier outward and climbing the ladder are the
same act.

**Every colour has a generator of its own** — exactly one, buried in the ring that demands it, and four
for red. So income never *has* to run through a converter, and a colour is a *place on the board* as much
as a rung on a ladder. But one anchored source on a board 30 hops across is a very specific place, so in
practice a colour reaches the frontier up the ladder: what an upgrader gives you is that colour
**somewhere else**. See *Colours, and the upgrader* below.

Everything else in the pitch above — distributors, teleports — is design intent, not code. See *Not
built yet* at the bottom.

---

## The loop

1. **Aim** a source at a cell you can see but have not mined, and that takes the colour it makes —
   select it, then right-click the cell. Unaimed generators idle; they never bank progress. An upgrader
   is the exception — it banks whatever is routed into it whether or not it is aimed.
2. Orbs travel **through ground you have uncovered**, losing value every cell they cross — by the
   shortest path, or bent through **waypoints** you choose. What arrives is what counts.
3. When a cell has absorbed its full cost it is **mined**. Only then do you find out what was in it.
4. Mining also **uncovers that cell's neighbours**, so the visible edge of the map moves outward.
5. The generator that was feeding it **goes idle**, because a mined cell consumes nothing. It waits for
   you to point it somewhere new rather than quietly emptying itself into a finished cell. Whatever was
   already on its way keeps going and simply lands for nothing — orbs are never called back.
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
each new cell it *crosses*. At zero it evaporates and delivers nothing. Three rules matter more than
they look:

- **Decay resolves before a pump fires.** An orb arriving at a pump on its last point of value dies — it
  didn't make it to the pump.
- **Nothing happens on an orb's destination.** It is delivered *into* that cell rather than crossing it,
  so the destination charges no decay and grants no pump. Otherwise a pump parked on a target would hand
  every delivery into it a free top-up, and the best place for every pump you own would be obvious and
  boring. A neighbour one hop away therefore receives the full launch value.
- **An orb is committed once launched.** Re-aiming a generator, rebending its route, or moving a pump
  under it changes what the *next* orb does and nothing about the ones already crossing the board. They
  fly the path they were given and land where it ends. Nothing on the map can take an orb back from you,
  so redrawing a route is free — and an orb heading for a cell that someone else finishes first simply
  arrives and does nothing.

### Blocks

| Block | Does |
|---|---|
| **Generator** | Emits a full-value orb at its aimed target on a fixed interval. **One per colour**, all on the same interval — a purple generator is exactly as fast as a red one. Idles with no target. **Anchored** — it never moves from where you found it. |
| **Pump** | Adds **+20% of an orb's launch value** to orbs *passing through* — +2 on an ordinary orb — and pumps stack, additively. Does nothing to orbs that stop there. Movable. |
| **Sphere** | Radiates to every block within **2 hops**: generators there work **25% faster**, upgraders there charge **25% faster** (so they cost 25% less), pumps there restore **+10 percentage points more** — 20% becomes 30%. Spheres stack, so a block reached by two gets both. Movable. |
| **Upgrader** | Banks **60** delivered value of one colour, then launches one orb of the **next colour up** at its target. Holds **one orb's worth and no more** — anything past that is wasted on arrival. One per step of the ladder, red → orange through blue → purple, all at the same cost. Spheres discount it. Idles with no target, but banks anyway. **Anchored.** |
| **Upkeep** | Burns **1 red per tick** from a bank you fill. While the bank holds out, **every generator on the board runs 25% faster**. Takes no target. Movable. |
| **Surge** | A challenge. Every generator on the board launches its orbs with **+5** value. Anchored. |
| **Current** | A challenge. Every pump on the board restores **+20 percentage points** more — it doubles what a pump is worth. Anchored. |
| **Lens** | A challenge. Every sphere on the board reaches **50% further** — 2 hops becomes 3. Anchored. |

**Only a source carries a colour.** A generator and an upgrader are painted the colour they emit, which
is how the board says at a glance what a cell makes. A pump, a sphere and an upkeep block act on orbs of
*every* colour, so none of them claims one — they are neutral greys, told apart by their glyph. That is
the whole of the board's palette rule: a hue on screen is always a resource.

A sphere is the odd one out: it never *does* anything on a tick, it just **is somewhere**. Aim it at
nothing, and it has no cooldown to watch. What it changes is the numbers every other block nearby runs
on, which is why the board draws its field rather than pulsing it. Two consequences worth knowing:

- **It only radiates once its own cell is mined.** A sphere still buried is a sphere doing nothing.
- **Spheres stack forever, with diminishing returns.** A sphere grants **+25% increased rate**, and
  every rate reaching a block is summed and applied once — `interval = 20 ÷ (1 + total/100)`. So the
  curve approaches zero without ever arriving, and there is no number of spheres at which the next one
  is worth nothing:

  | spheres | 1 | 2 | 3 | 4 | 5 | 8 |
  |---|---|---|---|---|---|---|
  | generator interval | 16 | 13 | 11 | 10 | 8 | 6 |
  | upgrade cost | 48 | 40 | 34 | 30 | 26 | 20 |

  Spreading the field over several blocks is still usually better than blanketing one — the first
  sphere on a block is worth four ticks and the fifth is worth two — but it is now a judgement about
  where the throughput matters rather than a hard wall. A lit upkeep block adds its +25% into the same
  sum, so it makes each sphere on a generator buy slightly less rather than eating a floor.

### Colours, and the upgrader

Every cell states the colour that opens it, and there are seven: red, orange, yellow, green, teal, blue,
purple. A cell takes its own colour and **nothing else** — a red orb arriving at a green cell counts for
nothing, not for a little. The board says which is which: a locked cell is tinted by the colour it
demands, in its fill, its ring, its price and the arc that fills as it is fed. The panel names it too.

You will not do it by accident. **Aiming a red source at a green cell is refused**, the same way aiming
at a mined cell or into the dark is refused — the preview turns red and says *needs green*. The rule is
worth teaching by refusal rather than by waste: there is no way to quietly pour a generator's whole
output into a cell that was never going to take it.

**Where a colour comes from.** Two places, and the difference between them is the interesting part.

**Generators.** Every colour above red has **exactly one** of its own, buried in the ring of the map that
demands it. Red gets four, because it is the only colour you have before anything is mined. They all run
at the same interval — a purple generator emits exactly as often as a red one — so no colour is *rarer*
than another in the sense of being slower to make. What differs is where the map put yours, and with one
apiece that is a very sharp difference: a single cell decides where teal is cheap.

**Upgraders.** A converter is a generator with the clock taken out of it: its progress bar is filled by
orbs *you* routed into it, and at 60 banked it launches one orb of the next colour up at its target.
There are three for each step of the ladder. So an upgrader has to be the target of something before it
is a source of anything, and a working line through one is really two lines — the colour below going in,
the colour above coming out — both of which have to survive decay.

**What an upgrader is actually for.** Not the mint — every colour has a generator. It is **position**.
Your one teal generator sits where the map buried it, and teal is cheap *there*; an upgrader is how you
make teal somewhere else, out of the green income you already have. On a board 30 hops across,
"somewhere else" is most of the map, which is exactly why the deep colours have one generator rather than
two. With a pair you could usually reach what you needed from one or the other and a converter was a
convenience. With one, the ladder is how a colour travels.

**And an upgrader now surfaces when its colour does.** Each is buried in the last couple of rings of the
colour it *eats*, so the red → orange converter comes out of the ground at about the distance the first
orange cells appear, and the same holds all the way up. It used to be allowed anywhere in the input band,
which meant digging up an orange upgrader at hop 1 — ten rings before a single orange cell existed, with
nothing to point it at and no way to work out what it was for.

Five consequences, and all of them follow from that:

- **An upgrader is anchored**, like a generator and for the same reason. Swapping is free and unlimited
  in range, so a movable converter could be parked beside the frontier and the upper half of every route
  would collapse to one hop — which would make position free, and position is the whole point of it.
- **It banks while idle, but only one orb's worth.** Mining a cell unaims everything pointed at it, so a
  converter that refused orbs whenever it had no target would throw away everything already in flight
  during that window — hence the banking. What it will not do is *stockpile*: the bar holds enough for
  exactly one output orb, and an orb arriving at a full bank is wasted. Only one orb leaves per tick
  however much is banked, so a converter left fed and unaimed used to swallow hundreds of value that
  bought nothing at all. Now that waste is on screen, where it belongs — a full bar means the line
  feeding it should be pointed somewhere else.
- **A sphere tightens the bank as it speeds the converter up.** The cap is whatever the conversion
  currently costs, so a sphere taking the cost from 60 to 48 takes the bank to 48 with it. You get more
  orbs out and less slack in the buffer, which is the honest version of the same buff.
- **It only takes the orb that stops there.** An orb merely routed *across* an upgrader is untouched,
  so a converter cannot be used as a toll gate on somebody else's line.
- **A sphere makes it cheaper.** A converter's clock is denominated in delivered value rather than
  ticks, so "charges 25% faster" and "costs 25% less" are the same sentence: one sphere in range takes
  the cost from 60 to 48, two to 40, three to 34, and it never reaches zero. That is the same increased
  rate a generator gets, on the only stat a converter has. Feeding it faster still matters more — a
  discount does nothing for an upgrader nothing is routed into.

**The shape this gives the game.** Red opens the first ten hops on its own — exactly unaided reach, so
the opening is the whole game before a pump is strictly necessary. Then each ring outward asks for the
next colour, and getting it means one of two things: dig out to the single cell where that colour's
generator is buried, or build a converter line from the ring behind you. Usually both — the generator is
the income and the converter is the reach.

**A colour arrives as a scatter before it arrives as a wall.** A handful of cells in the last hop of
each band demand the *next* colour, so you meet a few you cannot pay for while the current one still
works everywhere else. A hard boundary would just be routed around until the day it opened; a scatter is
met, understood, and planned for.

The map guarantees you can always get started. **No source is ever buried behind a gate deeper than what
it makes**: an upgrader sits at or below the colour it *eats*, and a generator at or below the colour it
*emits*. A converter that could only be paid for in the colour it exists to produce is a deadlock, and
the map generator refuses to emit a board with one on it.

### Waypoints

By default an orb takes the shortest route it can find. **Shift+right-click a cell** and the route has
to pass through it on the way.

Drawing a route is not a mode you enter — you pick up a block and shift+right-click your way across the
board, and **the route goes live as you draw it**. Every cell you add that could legally take an orb
becomes the destination there and then, so the block is already firing while you keep extending; add
another and the old destination quietly becomes a waypoint on the way to the new one. A cell that
cannot take an orb — the wrong colour, or already mined — just stays a corner the route turns at.

Up to four waypoints, Backspace undoes the last one, Esc clears the chain, and the preview shows the
bent route and what would arrive before you commit to anything.

**A waypoint is a cell to go through, not a path.** The game re-works out the route every time an orb
launches, so a line you drew early keeps improving as the fog lifts and a shortcut opens on one of its
legs. You never have to redraw a route because the map got better.

The trade is always the same, and it is worth doing the arithmetic once. Extra hops cost 1 each. A pump
you pass is worth +2 on an ordinary orb, and **arrival counts pumps, not distance between them** — so
bending a route to pick up one more pump pays for itself at two extra hops and profits after that. Mine
a Surge and a pump is worth 3, so the detour buys a hop more. That is the whole
reason the shortest path is not automatically the right one, and the reason the map's detours exist.

Two rules that follow:

- **A waypoint has no colour.** The tier gate is about where an orb *stops*, not where it passes, so a
  red route may legally be bent through an orange cell. What you cannot do is route through the dark —
  a waypoint you have not uncovered is refused the same way an unaimed dark cell is.
- **A route may not cross itself.** You cannot send an orb back over ground it has already covered, so
  every pump on a route pays exactly once. Without that rule you could lap a pump line and hand any cell
  on the map arbitrary value, which would make reach — the thing the whole game is about — stop
  mattering. A bend is a detour to somewhere new, never a loop. If a chain you are drawing would double
  back, the preview says so and refuses the corner rather than letting you find out at the end.

### Upkeep

An **upkeep block** is the first thing in the game that costs something to run.

Everything else you find is bought once and kept: a challenge is mined and pays out for the rest of the
game, a pump sits where you put it. An upkeep block has a **bank** you fill by aiming a generator at it,
exactly like an upgrader, and it **burns 1 red per tick** out of that bank. While the bank holds out,
every generator on the board runs **25% faster** — 20 ticks down to 16, the same bonus a sphere gives,
except it reaches the whole map instead of two hops.

It lights up at **200 banked** and goes dark only when the bank is **empty**. That gap is deliberate: a
block sitting near the line would otherwise flicker its buff on and off across the entire board every
few seconds. Once lit, 200 in the bank is 20 seconds of running time, and anything you feed past the
threshold is stored — over-feeding is a battery, not waste.

The economics are the point. A generator one hop from its target delivers 10 every 20 ticks, or 0.5 per
tick; the drain is 1.0. **So one upkeep block costs the full output of two dedicated generators.** What
it gives back is +25% throughput on every generator you own, so it pays for itself at four of them and
profits after that. Early on it is a millstone; once your network is wide it is the best thing on the
board.

Three consequences:

- **It is movable**, unlike every other board-wide bonus. A challenge is anchored because its buff
  reaches everywhere from anywhere, so there is no placement to get right. This one has to be *fed*, so
  where it sits — beside a generator with output to spare, and close enough that decay does not eat the
  supply — is a real decision, and the only one of its kind.
- **It banks while nothing is aimed at it**, like the upgrader, and for the same reason: mining a cell
  releases everything pointed at it, and a block that refused orbs during that window would throw away
  whatever was already in flight.
- **It only takes the orb that stops there.** An orb routed *across* an upkeep block is untouched — so
  it cannot be used as a toll gate on somebody else's line, which matters more now that waypoints make
  crossing a particular cell a deliberate act.

Two upkeep blocks are buried on the map. Both running is +50%, which takes generators from 20 ticks to
13, and a sphere adds its +25% into the same sum for 11 — so the two buffs stack without either making
the other pointless, and without either running into a wall.

### Challenge cells

Some cells on the map are **triangles**. They cost **six times** what an ordinary cell at the same
distance costs, and mining one grants a permanent bonus that applies to the **whole board** rather than
to anything nearby. There are three in every colour band — twenty-one in all — so every colour you climb
to comes with three of these decisions waiting in it.

The point is that you can see one coming. Every other unmined cell is a question mark and a price; a
challenge is a *triangle* and a price, drawn in the colour it demands like every other locked cell, so
you know from the moment it comes out of the fog that there is something worth saving for out there and
what it will be paid in. What you do not know is which of the three you are buying — the glyph is the
same question mark, and the shape only tells you the category. Knowing a hard thing is coming is what
makes it a goal; knowing exactly what it pays would turn the decision into arithmetic.

| Challenge | Grants |
|---|---|
| **Surge** | +5 to the value every generator launches with. This is the only thing in the game that extends *unaided* reach — 10 hops becomes 15 |
| **Current** | +20 percentage points to every pump's restore, everywhere, with no sphere needed — it doubles what a pump gives back |
| **Lens** | +50% sphere radius: 2 hops becomes 3, which roughly doubles the blocks each sphere covers |

Four rules, all of which follow from the buff being board-wide:

- **Anchored, like generators, but for the opposite reason.** A generator is pinned because moving it
  would trivialise decay. A challenge is pinned because its bonus reaches everywhere from anywhere, so
  there is no placement to get right — leaving it movable would be a chore, not a choice.
- **A sphere does nothing to one.** A challenge has no interval to shorten and no restore to raise, so
  parking a sphere next to it is wasted. It is not a block to support; it is a thing you bought.
- **It grants nothing while buried.** Mining is the whole transaction, so the board does not pay out
  first.
- **One of each per band, never two the same in one ring.** So a colour always offers three different
  decisions rather than the same one twice, and the trio arrives again a ring further out at six times
  the price of that ring.

The trade is always the same: a challenge is a **detour**. You stop pushing the frontier and pay six
times over for something whose payout you cannot see. What makes it worth it is that the bonus is
retroactive across your entire network — every pump you have already placed gets stronger the moment a
Current lands.

⚠️ **The three effects repeat unchanged in every band, and they stack.** Clearing the whole board is
therefore +35 orb value, +140 percentage points of pump restore, and +350% sphere radius. That is a
placeholder rather than a balance: the three types are meant to differentiate per band, and the
per-instance numbers are the first thing to retune when they do. Written down here so it is a known
consequence rather than something discovered late in a playthrough.

### Idle blocks

A mined cell absorbs nothing, so aiming at one is throwing output away. The game will not let you: you
cannot aim at a mined cell, and **the moment a cell is mined, everything aimed at it is released**.
Finishing a cell always hands you a generator wanting work. Orbs already on their way are not recalled —
they arrive at the finished cell and do nothing, which is the small price of the rule that an orb is
never taken back from you mid-flight.

**The exceptions are cells holding an upgrader or an upkeep block**, which are mined and still take
deliveries — that is the whole point of both, and it is why an orb that was in the air when you finished
digging one out is still banked rather than wasted. So "you cannot aim at a mined cell" is really "you cannot
aim at a mined cell with nothing to feed", and there are now two things on the board with an appetite:
one that hands the value back as a higher tier, and one that burns it for speed.

Because that happens on every single cell, and because the generator in question may be far off-screen
behind ground you have already cleared, the bottom-right corner keeps a **count of idle blocks by type**
— the block's own glyph with a number beside it. Clicking one flies you to the next idle block of that
type and selects it, so a right-click aims it straight away. Click again for the one after that; it
wraps.

**Blocks are never built or destroyed** — only mined, and moved if they can be. The map fixes how many
exist.

### Anchoring

**A generator stays where the map buried it. Forever.** You cannot pick it up, and you cannot displace
it by swapping something onto its cell. Everything you can do with a generator, you do from where it is:
aim it, or reach it.

This is the rule the whole game leans on, so it is worth saying why it exists. Swapping is free, instant
and unlimited in range. If generators moved, you would simply walk one to the edge of the frontier every
time, deliver the full launch value on every single cell, and never build anything — which is exactly what the game
did before, and it made decay a formality. Anchored, a generator's reach is fixed by where it sits, and
**extending that reach is what pumps are for**.

So the map hands you a fixed set of anchored sources scattered across the board, and the real question
becomes: can you push far enough out from the ones you have to uncover the next one? Each generator you
find is a new place the network can grow from.

### Swapping

Any two mined cells can exchange contents, free, instantly, at any distance — provided neither holds an
anchored block. In practice that means **pumps are what you move**. Swapping against an empty cell is a
move. Two consequences:

- Orbs already in flight from either cell **carry on** — moving a pump under a live route never costs
  you the traffic on it, though the orbs that have already passed the pump's old cell keep whatever it
  gave them.
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
| Orb value | 10 | What an orb launches with, and what every pump on its route takes its percentage of. **Not** a ceiling — pumps can push it higher |
| Decay | 1 per hop | Charged on entering each cell the orb *crosses*. Its destination is not one of them |
| Generator interval | 20 ticks | One orb every 2 seconds |
| Pump restore | +20% | Of the orb's *launch* value, so +2 on an ordinary orb. Uncapped, and summed with every other pump on the route rather than compounded |
| Sphere field | 2 hops | Every block within reach reads the bonus |
| Sphere rate bonus | +25% increased | Per sphere in range. Every rate reaching a block is summed, then applied once: `base ÷ (1 + total/100)`. 20 → 16 → 13 → 11 → 10 → 8 |
| Sphere charge bonus | +25% increased | The same, on a converter's cost: 60 → 48 → 40 → 34 → 30. Its own number, so it can be tuned apart from generator speed |
| Sphere restore bonus | +10pp | Per sphere in range, stacking: 20% → 30% → 40% |
| Interval floor | 1 tick | A divide-by-zero guard, not a cap. The rate formula never reaches it — from 20 it would take +1900% |
| Upgrade cost | 60 | Banked delivered value per orb launched, the same at every step of the ladder, before any sphere discount. Also the **bank's ceiling** — a converter holds one orb's worth and wastes the rest |
| Upkeep drain | 1 red / tick | The running cost of one upkeep block — the output of two dedicated generators |
| Upkeep reserve | 200 red | Bank level that lights the buff. A threshold, not a cap: it goes dark only at empty, so this is also 20 s of run time |
| Upkeep bonus | +25% increased | Board-wide generator rate, while fuelled. The same number a sphere gives, over the whole map, summed into the same divisor |
| Max waypoints | 4 | How far a route may be bent. Looping is prevented by the no-crossing rule, so this is a limit on how fiddly a route may get |
| Tiers | 7 | red, orange, yellow, green, teal, blue, purple. Every colour launches, decays and pumps identically — a purple orb is a red orb with a different gate |
| Generators per colour | 1 | Four for red, the bootstrap. All on the same interval, so a colour's scarcity is *where* it is, not how fast |
| Upgraders per rung | 3 | Eighteen in all. Buried in the outer two rings of the colour each one eats, so a converter appears with its colour rather than long before it |
| Colour bands | 0–9, 10–13, 14–16, 17–19, 20–21, 22–24, 25+ | Hops from the start. Red gets ten — exactly unaided reach, so it is the colour you can work without a single pump. Widths are uneven because the rings are; measured in *cells* the seven bands come out close to even |
| Colour scatter | 35% of a band's last hop | Promoted one colour, so you meet each new one before it becomes the wall. Only bands wider than a hop donate, which on this table is all of them |
| Deep-colour cost | curve ÷ 2 | Every colour above red. Not a generator headcount any more — a deep colour's income comes up the ladder, and the ring feeding that converter is already on this curve |
| Unlock cost | `50 × 2.0 ^ (hops − 1)` | 50 on the ring around the start, doubling every hop after. The start itself costs 0 |
| Challenge cost | ×6 | Six times the normal cost for that distance — about four extra hops' worth of the ramp |
| Challenges | 3 per band | One of each type in every colour. 21 in all, and their bonuses stack |
| Surge | +5 orb value | Board-wide, once mined |
| Current | +20pp pump restore | Board-wide, stacks on top of any sphere: 20% → 40% |
| Lens | +50% sphere radius | Board-wide; 2 hops becomes 3, rounding down |
| Rounding | up | A pump's percentage rounds in your favour — 30% of a 15-value orb is 5, not 4. A radius still rounds down |

### What those numbers mean in play

- **Unaided reach is 10 hops.** An orb dies on the eleventh. A cell at 10 hops receives 1 value per orb.
- A route's arrival value is **`11 − hops + 2 × pumps passed`** on ordinary orbs — an orb is delivered
  *into* its destination rather than crossing it, so the last cell charges no decay. The HUD shows it
  before you commit. The `2` is 20% of the launch value, so it moves when the launch value does.
- **Pumps are additive, not compounding.** Every pump gives back a share of what the orb *launched*
  with, so three of them are worth 60% of that, in any order — a long chain is a sum, and it does not
  snowball.
- **Pumps stack and there is no ceiling.** Two pumps early on a short route deliver *more* than a fresh
  orb is worth. Three pumps buy six extra hops of range, wherever you put them.
- **A percentage means the Surge is worth more than it looks.** +5 launch value is +50% on the orb
  *and* on every pump it passes, so a Surged orb crossing three pumps arrives with 9 more than a plain
  one, not 5. It is the only buff that reaches both halves of a route's arithmetic.
- **Where you put them decides whether the orb lives, not what it carries.** Arrival depends only on how
  many pumps the orb passes, not their spacing. But a pump cell nets +1 and a plain cell −1, so a supply
  line holds indefinitely only while its pumps sit **2 hops apart or closer**. At 3 apart it bleeds a
  point per stretch and eventually dies mid-route — carrying nothing, having cost you the same orbs.
- **Cost is geometric, and that is the shape of the whole game.** Each hop out costs **twice** the last:
  50 at one hop, 1,600 at six, 51,200 at eleven, 13,421,772,800 at the rim — before the divisor, which
  halves everything above red. Clearing the board takes **226,901,320,400** in all, and it is weighted
  brutally toward the rim: 514,000 of that is red across 128 cells, and 205,520,896,000 is purple across
  111. Doubling is the number to reach for first if the late game drags, and it is one line in
  `tools/gen_map.py`.
- **Doubling and board size compound, and the pass that set both did it deliberately.** The exponent is
  distance from the start, so restoring 2.0 *and* quadrupling the board did not add two effects, it
  multiplied them: the price the old rim carried, 409,600, is now what you pay at hop 14 — not quite
  halfway out. Everything past that is new ground in every sense.
- **Your side compounds too, which is why cost has to.** Every pump you find adds a fifth of an orb's
  launch value to every orb on every route through it, forever; every sphere speeds every generator near it. Reach and throughput
  both grow multiplicatively as you dig, so a cost curve that only added a constant per hop would leave
  the far rim *cheaper* in real terms than the near ring — which is exactly what it used to do. The board
  buries 240 pumps and 180 spheres against the old 40 and 30, which is what that side of the curve is
  made of.
- The practical read: your first cell is 50, about six orbs from a bare generator, and the ring after it
  is 100. A cell out at 20 hops costs about 13 million in *teal*, and delivering that means either
  digging as far as the one teal generator or running a green line into a converter and a teal line out
  of it, both heavily pumped.

### Why anchoring was necessary

Worth recording, because for a while the game did not work and it was not obvious why.

Every cell you can legally aim at is one hop from mined ground — that is what being uncovered means. So
when generators were movable, and swapping was free, instant and unlimited in range, the optimal play
was always the same: walk a generator up to the frontier and deliver the **full launch value**, on every cell, for
the whole game. A scripted playthrough confirmed it — the entire map fell with a mean arrival of 9.0 per
orb and no pump chain ever built. Decay and pumps had stopped gating reach and were gating, at most,
convenience.

Anchoring generators fixes it at the source. Reach is now a property of where the map put your sources,
and the only way to extend it is a pump chain. Pumps went additive at the same time and for the same
reason: restoring to a cap made one pump as good as three, so there was never a reason to commit more
than one to a route. Stacking, every pump you spend buys two more hops on an ordinary orb, and the
question becomes how many you can afford to leave on a line rather than whether to bother with a
second.

The board was built against exactly this. `tools/gen_map.py` plays the map twice — once with pumps and
once without — and looks for a placement where the first clears it and the second **fails**. If the
whole thing can be finished without ever placing a pump, it is not a map worth shipping. The
playthrough is a report rather than a gate now: the shipped board is known to clear, and the model's
pump is frozen at the flat +3 it was drawn under rather than tracking the percentage.

### The map — *First Light*

**950 cells in a honeycomb.** 850 of them have exactly three neighbours, 86 around the rim have two,
and fourteen sit at four or six around the two kept hubs — so the board is almost uniformly three-way,
and the junctions stand out. It is 59 hops across, and you open in the *centre*, so the number that
matters is the radius: **30 hops** to the farthest corner, against an unaided reach of 10.

That radius is the point of the whole balance pass. At 15 the deep colours were single rings and teal
arrived about ten hops in; at 30 every colour is a region you live in for a while.

You start on cell 462 with three neighbours uncovered and the other 949 cells dark. The frontier then
grows outward on every side at once, rather than sweeping across from a corner.

**471 of the 950 cells bury something: 10 generators, 240 pumps, 180 spheres, 18 upgraders, 2 upkeep
blocks, 21 challenges.** The other 479 are empty — very close to half, which is the rule the pump and
sphere counts are set to hold.

The **10 generators** are four red and **one of every other colour**, each buried in the band it serves
or the one below it — never behind a gate deeper than the colour it makes, which would be a cell nothing
could pay for any earlier. Red gets four because it is the only colour you have before anything is mined;
everything above it gets one, which is what makes the ladder load-bearing rather than optional.

The **18 upgraders** are three per step of the ladder, at 8 to 24 hops, each on a cell gated at the
colour it *eats* and inside the **outer two rings** of that colour's band. So a converter surfaces within
a hop of the first cells demanding what it makes: orange upgraders at hops 8-9 against the first orange
cell at 9, yellow at 12-13 against 13, and so on out to purple at 23-24 against 24. Being anchored, where
the map buried yours decides where each colour can be made other than at its one generator.

The two upkeep blocks sit at **7 and 9 hops** (cells 611 and 662), both inside red — they burn red, so
one buried out in the deep bands could not be fed until far too late to be worth having. Being movable,
where they end up is yours to decide; where the map puts them only decides when you find them.

Unlock costs run `50 × 2.0 ^ (hops − 1)`, from **50** on the ring around you to **13,421,772,800** at the
dearest cell, with everything above red halved. Clearing the whole board takes **226,901,320,400**, and
it is weighted brutally toward the rim: 514,000 of that is red and 205,520,896,000 is purple.

The **21 challenges** cost six times their ring, so they scale with the band they sit in — from **300**
in red out to **5,033,164,800** in purple. Three in every colour, one of each type.

**The seven bands** hold 128 / 140 / 140 / 152 / 115 / 164 / 111 cells, red through purple. They are
uneven in *width* on purpose, because the rings are: a honeycomb cut out of a square grows to about 56
cells a ring around hops 19-20 and then collapses as the board runs out of corners. Red gets ten hops,
orange four, yellow three, green three, teal two and blue three before purple takes everything past 25.
Measured in cells rather than hops, that comes out close to even.

**Every band is at least two hops wide now, and that matters more than it looks.** The colour scatter
only fires on a band wider than a single ring, so on the old table the four deepest colours announced
themselves not at all — they simply began. Now each one arrives as a handful of cells you cannot pay for
before it becomes the wall.

The furthest red cell is 9 hops out against a board radius of 30, so the outer twenty-one rings are shut
to the colour you start with — the generator refuses to emit a map where red reaches the rim, since that
would make the six colours above it decorative. Ten hops of red is also exactly unaided reach, which is
deliberate: red is the colour you can work without owning a single pump.

**Why a honeycomb rather than a hex patch.** A hex lattice gives every cell six neighbours, and six
neighbours means you route around any obstacle and there are dozens of equally short paths between any
two points — compact, and decay stops mattering. So the centre of every hexagon is removed, leaving each
surviving cell with the three edges that form its rim. That is a genuine web with genuine detours, and
it is what makes a route long enough to be worth supporting. A couple of centres are kept as hubs, and
they are the only places the board opens up.

The generator asserts the properties the game leans on, and refuses to emit a map that misses any of
them: the board is connected, no cell is a dead end, it is at least 12 hops across, the far corner is
outside unaided reach, exactly one cell starts mined (discovery grows one connected region outward, and
two starting points would leave two regions with no route between them), and each colour band buries
exactly one of each challenge, inside the band whose colour it demands.

Whether the board *finishes* is printed rather than asserted, and the numbers are worth reading: the
shipped board clears completely, **523 of 950 cells are unmineable without pumps**, and only **128 of
950** fall on red generators alone. The second is the one that says the colour ladder is load-bearing —
if red alone ever cleared the board, the six colours above it would be decoration; 128 is exactly the
red band, so it does not reach one cell further than its own colour.

The stranding number is the one that moved most, from 23 of 230 to 523 of 950 — better than half the
board. Cutting the deep colours to a single generator apiece is most of that, and it is the point of the
cut: a colour with one anchored source is a colour whose reach has to be built rather than found.

The winnability proof ignores upkeep blocks entirely, and the reason is sharper than the one for
spheres. A sphere is ignored because it only ever adds power; an upkeep block's bonus is a *shorter
interval*, and the proof never models time at all — it asks only whether an orb can arrive, never how
often. An interval buff is invisible to it by construction, so the proof means exactly what it said
before they were added.

The colour ladder gets its own set, because a gate can make a cell genuinely unmineable in a way no
buff can: every cell sits in its own band or exactly one colour deeper (the scatter, and never
shallower, which would be a hole in the wall), every colour actually appears on the board, red does not
reach the rim, the scatter fired somewhere, and **no source is buried behind a gate deeper than what it
makes** — an upgrader at or below the colour it eats, a generator at or below the colour it emits.

One assertion was *deleted* rather than updated, and it is worth naming. The old board asserted it could
not be finished without upgraders, because orange was minted and nothing else made it. Every colour has
generators of its own now, so a converter is reach rather than a gate, and that assertion is false by
design. What replaced it is the red-alone number above.

The upkeep blocks get a shallow-cell check too, for a related but weaker reason. A source behind a
deeper gate is a *deadlock*. An upkeep block behind one is merely useless: it burns red wherever it
sits, so nothing could feed it out there until long after a faster generator was worth having.

---

## Not built yet

Design intent from the pitch, with what each would cost. The tick is phased so all of these are
additive; see `architecture.md` for the hooks.

| Block | Idea | Needs |
|---|---|---|
| **Distributor** | Splits one colour across many outputs | Multiple output ports per block; `on_orb_deliver` already exists |
| **Teleport** | Folds two distant cells into one hop | Mutable adjacency; the path cache is already dropped on unlock, so this extends that to placement |

**The three challenge effects are placeholders.** Surge, Current and Lens repeat unchanged in all seven
bands, so their bonuses stack sevenfold over a full clear. Differentiating them per band — a distinct
effect for each colour, and per-instance numbers retuned to suit — is the next thing this section will
lose an entry to.

**The ledger is one set of numbers, not one per colour.** It balances across a conversion because the
colour absorbed and the colour minted are an ordinary sink and an ordinary source, and a chain of
converters is just that pair repeated. A per-colour readout would be a HUD nicety; the invariant does
not need it.

**The sphere's tier gate** is the one piece of a built block still outstanding. The pitch has it buffing
"everything *weaker* than it nearby"; today it buffs everything nearby. With seven tiers on the board
this is a condition that fails often rather than rarely, so the gate is now a real balance decision —
it would make a sphere's placement a question of what colour it is standing over. Deferred rather than
blocked.
