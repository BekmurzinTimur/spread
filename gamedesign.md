# Spread

## The pitch

A board of dark hexes. One cell is lit. It starts eating outward on its own — a ring of light crawling
into the dark, orbs hopping from your edge into the cells beyond it, each one landing with a flash.

You don't route anything. You don't place anything. The spread runs itself and it gets faster every
time it swallows a cell, because **the cells you own are what powers the edge**. Ten cells is a slow
creep. Three hundred cells is a roaring perimeter.

Buried out in the dark are **buffs**. You can see them coming before you can read them — a glow at
range, a name up close — and they are what make the spread accelerate rather than merely continue:
orbs worth more, orbs firing faster, orbs that crit for five times value, orbs that fork in two.

And you have one weapon. The **ram** banks the cost of every cell you take, and when you throw it, it
lands anywhere on the board — no range, no walls — and hits that cell for everything you saved. Enough
damage and it cracks open out in expensive ground, next to that legendary glow you've been staring at
for two minutes, and a **colony** starts spreading there on its own. Eventually the two of them meet.

Then you stop, bank what you took, and buy the things that make the next run better.

**No routing. No placement. No decisions per second. One decision every couple of minutes, and it
matters.**

---

## The three things

### 1. The frontier — automatic, you never touch it

- **A mined cell rolls for a generator.** One that comes up a generator drives the rate; a dud is
  inert ground worth nothing. Raising the odds to 100% is the first thing the shop sells, so the
  frontier is something you earn rather than something you are handed.
- **Only generators on the frontier emit** — mined, a generator, *and* adjacent to ground they can
  still take. Interior cells go quiet.
- **If the frontier is ever nothing but duds, the run is over.** Nothing emits, nothing else can be
  mined, and the way forward is to ascend and spend what you banked. That is not a failure state — it
  is how a run *ends*, and early on it is how every run ends.
- Each frontier cell fires an orb on its own timer, and **how many generators you own sets how fast that timer
  runs**.
- An orb hops to an adjacent locked cell and delivers its value. When a locked cell has absorbed its
  full cost, it is mined.

That's it. No targeting, no allocation, no budget being moved around. One number feeds every emitter's
clock.

**Why this shape:**

- **The snowball is literal and on screen.** More cells → the whole rim visibly speeds up. No HUD
  number needed to understand you're getting richer.
- **It stays legible at scale.** Orb count tracks the **perimeter**, not the area. A growing disc's
  perimeter goes as √area, so you go from 6 emitters to ~90 at full board, not 2,000.
- **Travel is one hop.** Fast, punchy, constantly landing — which is why there is no decay.
- **The visual is a ring of light on the growing edge**, which reads instantly and correctly as *this is
  where you are.*

A frontier cell fires at whichever neighbour is **closest to done**. Concentrating fire rather than
spreading it evenly is what makes cells land one after another instead of six bars creeping at once.

**Income is one global pool**, not per-blob. A distant colony is throttled automatically by having a
tiny perimeter and by sitting on expensive ground. The geometry does the balancing.

### 2. The ram — the only thing you aim

- The pool banks **20% of the cost of every cell you mine**, so it scales with the board rather than
  falling behind it.
- You may throw it at **any unmined cell, at any distance, in any band**. No range check, no wall.
- It deals its pool as **damage** to that cell's progress.
- Damage that doesn't finish the cell **stays as progress**. A partial ram is a down payment you can
  read on the board, not a miss.
- **Only what actually lands is spent.** Throw a huge pool at a nearly-finished cell and the surplus
  stays banked. Firing early is never punished, so the decision is *where*, never *whether you saved
  too much*.

**Why the pool comes from mining:** it couples the ambient loop to the punctual one. Spreading wide
literally loads the gun that lets you go deep. The decision becomes *how long do I save* — farm
broadly, watch the number climb, spend it on the glow you've been eyeing.

**Why a colony and not just a hole:** a uniformly expanding disc is the least interesting shape a board
can have. Colonies make your territory *shaped*, and shape is what makes a run memorable. It also makes
the ram decision a real one — crack open a cell next to that far legendary and let a colony grow toward
you, or put the damage into the ring in front of you?

**The ram ignores the band wall.** It can crack a cell in ground you haven't unlocked. The colony
spreads through its own band but can't climb into the next one — so you get to *see* what's out there,
which sells the next ascension purchase far better than any shop description.

### 3. Ascension — a phase, not a button

The game is always in one of two phases, and each has exactly one button.

| Phase | What is happening | The way on |
|---|---|---|
| **Running** | The board ticks. The shop cannot be opened. | **End run** — one click, no confirmation |
| **Shopping** | Everything is banked, the next board is dealt and frozen behind the shop. | **Start run** |

Ending a run banks it and deals the next board in the same instant, so the currency is in the wallet
before the shop has finished drawing. Nothing ticks while you shop, and **every purchase lands on the
board waiting behind the modal** — buy a node type and it is dealt into that ground; buy a band and
that board's wall has already moved. There is no such thing as a purchase that half-applies, because
there is no run in progress to apply it to.

When the frontier stalls, the end-run button says so — *run over, claim* — since that is the moment
the phase is meant to turn over.

The shop is where **buff types get unlocked** — and this is the important rule:

> **A buff type does not appear on the board until you have bought it.**

The shop also holds **Reset progress** — wallet and purchases back to first boot, on two clicks.

Run 1 has one buff type in the pool. By run 5 there are four, at higher levels, and the board is a much
richer place. That's the progression spine: **ascension makes the board richer, not just your numbers
bigger.**

---

## The board

**A plain hex lattice.** Every cell has six neighbours. No holes, no hubs, no quirks — the board's job
is to be a clean, readable field for the spread to grow across.

- **Radius 24** from the centre → 1,801 cells.
- **You start on the centre cell**, mined. Everything else dark.
- **Fixed topology, fixed band positions.** The board is the same place every run. Only buff placement
  is randomised.

### Colour: two independent channels

| Channel | Means |
|---|---|
| **Hue** | Depth band. Red at the core, purple at the rim. Reads as a map at a glance. |
| **Glow / size** | Node rarity. A big pale bloom is a keystone, wherever it sits. |

Two facts, readable in one look, without fighting each other. Rarity gets brightness because it's the
thing you most need to see instantly.

### Bands

Bands are pure distance rings — same shape, same positions, every run.

| Band | Hops | Cells | Clear pays |
|---|---|---|---|
| Red | 0–8 | 217 | 2,631,600 |
| Orange | 9–11 | 180 | 9,360,600 |
| Yellow | 12–14 | 234 | 26,313,900 |
| Green | 15–17 | 288 | 59,904,600 |
| Teal | 18–19 | 222 | 70,589,100 |
| Blue | 20–22 | 378 | 176,621,100 |
| Purple | 23–24 | 282 | 183,485,100 |

**A band is a wall.** Your frontier cannot mine into a band you haven't unlocked. Unlocking is an
ascension purchase.

Hard walls give a run a **clean end condition** — *you cleared red, here's your haul* — which makes each
run a complete object rather than a fade-out. They're also the run-length knob: the single number to
turn when pacing is wrong.

Red gets nine hops because it's the whole of run 1 and needs to be long enough to teach the game.

---

## Costs

**`cost(hops) = 50 × hops³`**

Polynomial, not exponential, and that much is structural rather than a preference. Income scales with
**area** (`~r²` cells), so an exponential curve isn't hard, it's an impassable wall at a fixed radius.
Cubic against area-scaling income means the frontier stays something you **earn** — the ring in front
of you always costs more than the ring behind you paid — while multiplicative buffs are what let you
accelerate past it. That's where the dopamine is: feeling yourself outrun the curve.

| Hops | Cost | Ring cells | Ring total |
|---|---|---|---|
| 1 | 50 | 6 | 300 |
| 2 | 400 | 12 | 4,800 |
| 3 | 1,350 | 18 | 24,300 |
| 4 | 3,200 | 24 | 76,800 |
| 5 | 6,250 | 30 | 187,500 |
| 6 | 10,800 | 36 | 388,800 |
| 7 | 17,150 | 42 | 720,300 |
| 8 | 25,600 | 48 | 1,228,800 |

**A full red clear pays 2,631,600.** That's the one hard number the shop is priced against.

**Every cell pays currency equal to its cost when mined.** So there are no dry digs — mining anything
always pays, always counts toward the rate, and sometimes also holds a node.

---

## Buffs

### The four types

| Node | Rarity | Effect per level |
|---|---|---|
| **Power** | Common | +1 orb value |
| **Speed** | Common | +10% increased emission rate |
| **Crit** | Rare | +5% chance an orb lands for ×5 value |
| **Split** | Rare | +5% chance a frontier cell emits two orbs instead of one |

Power and Speed are **additive** and keep the baseline moving. Crit and Split are **multiplicative** and
are what let you outrun the cost curve. They are deliberately in different rarity bands — see the
dilution rule.

**Every node found grants +1 level of its type**, and levels stack for the whole run.

### Distribution

| Roll | Holds |
|---|---|
| 93% | Nothing extra |
| 5% | A common node (Power or Speed), +1 level |
| 1.5% | A rare node (Crit or Split), +1 level |
| 0.5% | A keystone — +3 levels of one type at once |

About fifteen nodes across the red band, so a find lands roughly once a minute and each one is an event
rather than noise. Randomised per run, so every run's tree is a different tree on the same familiar
board.

### The dilution rule

> **A purchase must never lower your expected run.**

If it can, players correctly become afraid to buy things, and fear is the opposite of what this game is
for. Two structural guarantees, not balance passes:

1. **Fixed slots.** The board decides how many commons, rares and keystones exist. Ascension changes
   only *what can appear inside a slot* — never how many slots there are. A slot whose rarity has no
   unlocked type stays empty, so buying a rare type fills empty slots rather than crowding out commons.
2. **Additives and multipliers never share a table.** Power and Speed live in commons; Crit and Split
   live in rares. So "additives crowding out multipliers" is structurally impossible rather than
   balanced around.

### Vision

You cannot plan toward what you cannot see, and you cannot be surprised by what you can.

| Distance from mined | You see |
|---|---|
| 1–3 hops | **Full identity** — the name |
| 4–8 hops | **That a node exists, and its rarity** — a glow, sized by tier. Not what it is. |
| Beyond | Nothing |

A keystone bloom eight hops out says *there is something huge over there* without saying what, so
saving the ram for it is a gamble with a long build-up and a reveal at the end. Rarity is
honest, so you never feel cheated; identity is hidden, so the board never looks solved at the start of a
run.

**Vision range is an ascension purchase** — an upgrade that buys *agency* rather than raw numbers.

---

## Juice

**This is a first-class section, not a polish pass.** 95% of playtime is watching an automatic process,
so if the frontier isn't thrilling to look at with zero input, there is no game.

The rule: **every event gets a light and a shape.**

### Ambient

- Frontier cells **breathe** — a slow glow cycle, so the live edge is obvious against the dead interior.
- Interior cells hold a dim, still light. The eye goes to the edge because the edge is where the game is.
- Orbs leave a short **motion trail** and land with a splash.
- **The tempo is the readout.** As generators accumulate, emission speeds up visibly. No number required.

### Per event

| Event | Juice |
|---|---|
| **Orb lands** | Splash in the band's hue. |
| **Cell mined** | The cell **pops** — scale overshoot, ring shockwave outward, shards. |
| **Crit** | Orb is visibly larger and brighter in flight, rolled at emission rather than at landing. On landing: white flash and `×5` in large text. |
| **Split** | Two orbs leave the same cell on the same tick. |
| **Node revealed** | Its name floats up off the cell as it is mined. |
| **Ram loaded** | The meter climbs and pulses. Hovering a cell shows what the shot would do to it. |
| **Ram thrown** | Board dims for a beat → beam streaks out → impact bloom at the destination → the cell cracks and, if it broke, a colony ignites. The one cinematic moment in the game. |
| **Blobs merge** | Cells stop being frontier and go quiet. |

**Not built yet: sound.** Every event has a light and a shape; none has a sound.

---

## The HUD

**Less Excel, more game.** Four things, and nothing else on screen by default:

1. **Currency** — one number, top-left.
2. **Ram pool** — a radial meter, top-right. This is the thing the player is saving for, so it gets
   the most real estate of the four.
3. **Band progress** — cells mined / cells in band, a bar in the band's colour. The run's progress bar
   and its end condition.
4. **Buff levels** — one row per type, each naming what it does and what it is currently worth, above a
   line breaking down the orb's value: `orb 13 = 10 base + 3 yield`.

Rules:

- **Say what a buff does, in words.** A row of bare glyphs left the player unable to name what Power
  was for, so the effect is spelled out rather than hidden behind a hover.
- **No debug info.** No ledger readout, no tick counter, no orb counts.
- **Tooltips carry the rest.** Hovering a cell gives its band, price, progress and what is buried in it.
- **Nothing that updates faster than the eye can read.**

---

## Controls

| Input | Does |
|---|---|
| Right-click | Ram that cell for the whole pool. Any cell, any distance |
| Left-drag | Pan |
| Wheel / pinch | Zoom |
| Click **End run** | End the run and enter the shop. Click only — no key throws a board away |
| `[enter]` | Start the run waiting behind the shop |
| `[space]` | Pause |
| `[1]` `[2]` `[3]` | Speed ×1, ×4, ×16 |

---

## Balance

These match the constants in `sim/world.gd` and `sim/node_catalog.gd`. **Keep this table in sync when
tuning.**

| Value | Setting |
|---|---|
| Tick rate | 10 Hz |
| Hop time | 3 ticks (0.3 s) |
| Base orb value | 10 |
| Base emission interval | 20 ticks (2 s) |
| Emission rate | `interval = 20 × 100 / (100 + generators×2 + speed×10)`, floor 2 ticks. Both terms are *increased rates*, summed into one divisor |
| Rate per generator | +2 percentage points each — a dud contributes nothing |
| Generator chance | **0% before any purchase**, 100% at ten levels |
| Cost | `50 × hops³` |
| Crit | ×5 |
| Ram pool | **20%** of the cost of every cell mined since the last ram. Only what actually lands is spent — unspent damage is kept |
| Ram reach | Anywhere. No range, no band wall |
| Vision — identity | 3 hops |
| Vision — rarity glow | 8 hops |
| Starting pool | **Power unlocked**; Speed, Crit and Split must be bought |

### Shop

These match `sim/meta_upgrades.gd`. Priced against **what a run actually banks**, which is the thing
that changed: a full red clear pays 2,631,600, but nothing before the late runs comes near it.

| Purchase | Cost | Levels |
|---|---|---|
| Unlock **Speed** | 1,000 | 1 |
| Unlock **Crit** | 6,000 | 1 |
| Unlock **Split** | 10,000 | 1 |
| **Generator chance**, +10% | `100 × 2^level` | 10 |
| Node level, per type | `800 × 2^level` | 10 |
| Ram power, +25% damage | `4,000 × 2^level` | 6 |
| Vision, +1 hop | `2,000 × 2^level` | 5 |
| Unlock Orange / Yellow / Green | 250,000 / 900,000 / 2,600,000 | 1 each |
| Unlock Teal / Blue / Purple | 6,000,000 / 7,000,000 / 17,600,000 | 1 each |

⚠️ **Bands used to be priced off a full clear of the band below, and that was the wrong denominator.**
Orange at a quarter of a red clear meant several near-perfect red runs before the second colour existed
at all. Measured, a 50%-chance run banks ~65,000 and a 70% one ~188,000 — so orange at 250,000 lands
around **run 5**, which is the shape the early game wants: short, frequent ascensions that each buy
something.

### What those numbers mean in play

- **First cell mines in about 8 seconds**, and **run 1 is over in well under a minute.** You start at
  0% generator chance, so the centre cell is the only emitter on the board. It mines its six
  neighbours, every one of them a dud, and then it is no longer touching anything mineable — so it
  goes quiet and the run stalls. **Seven cells, 300 banked, ascend.** That is the intended opening: it
  is short enough to read in one sitting, and the stall is what teaches the loop.
- **The first purchase is always the same one**, and it is priced so it cannot not be: generator
  chance costs 100 against a run that banks 300. Run 2 opens at 10%.
- **Generator chance is the spine**, and it is the first thing the shop sells because **every level
  visibly changes the run**. Measured over 24 seeds, playing each run until the frontier stalls:

  | Chance | Avg cells mined | Avg banked | Runs that stall at 7 |
  |---|---|---|---|
  | 0% | 7 | 300 | 24/24 |
  | 10% | 9 | 2,702 | 13/24 |
  | 20% | 13 | 5,895 | 9/24 |
  | 30% | 17 | 13,710 | 3/24 |
  | 40% | 27 | 32,714 | 1/24 |
  | 50% | 40 | 65,595 | 0/24 |
  | 70% | 71 | 188,150 | 0/24 |
  | 100% | 121+ | 617,700+ | 0/24 |

  Banked value roughly **doubles per level**, against a price that also doubles — so the ladder stays
  climbable the whole way up rather than stalling out halfway.

- ⚠️ **At 10% about half of runs still stall at the opening seven cells.** That is variance rather than
  a bug, and it is why the first level is priced at what a stalled run banks: a wasted run 2 costs
  forty seconds and still pays for the next step.
- **The 100% row is a time limit, not a stall.** With every cell a generator the frontier never runs
  out, so from about 80% the run ends when *you* end it. That is the point at which the game stops
  being about ascending and starts being about how long you want to sit there.
- **The ram is an assist, not a key.** At 20% of every cell's cost it can account for at most a fifth
  of the board however long you save. What changed is that it is now *reachable* — at 4% the early ram
  was not weak but arithmetically impossible, needing more mined cells to fund one shot than the board
  contained inside that radius.

---

## Open decisions

- **No tension, no failure state.** Deliberate. There's no clock, no threat, and no way to play badly.
  The band wall and the ram supply the run's shape. If playtesting reads flat, this is the first
  place to add something — but adding a threat risks reintroducing the chores this design exists to
  avoid.
- **Level-up cards are not in.** The frontier, the ram, the node pool and the shop are already four
  progression surfaces. If the game wants a faster decision cadence, cards slot in as the layer that
  grants *verbs* while nodes grant *numbers*.
- **Node synergies are unexplored.** With only four types there's little to combine. The moment the pool
  grows past ~8 types, whether rares *interact* becomes the biggest factor in whether runs feel
  different from each other.
- **Board size is a guess.** 1,801 cells at radius 24 is sized for a full 7-band game. If the later
  bands drag, shrink the radius before touching anything else.
- **Per-blob income was considered and rejected.** Perimeter and the cost gradient already throttle
  distant colonies. If colonies feel too cheap in play, this is the first knob to reach for — it would
  also make merging a payoff event rather than just a nice visual.
