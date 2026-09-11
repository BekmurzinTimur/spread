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
lands anywhere you have unlocked — no range — and hits that cell for everything you saved. Enough
damage and it cracks open out in expensive ground, next to that legendary glow you've been staring at
for two minutes, and a **colony** starts spreading there on its own. Eventually the two of them meet.

Then you stop, bank what you took, and buy the things that make the next run better.

**No routing. No placement. No decisions per second. One decision every couple of minutes, and it
matters.**

---

## The shape of the game

Progress comes in **growth and plateau** phases, and the colour switch is where they turn over.

- **Growth.** A new colour opens along with its block of upgrades. The first runs into it push the
  frontier noticeably further each time.
- **Plateau.** Each ring costs ×1.65 the last, so the far edge of a colour outruns your income. Runs
  stop gaining ground and become about banking toward **Mine <next colour>**.
- **Switch.** Buying it opens the next colour and its upgrades, and growth starts again.

---

## The three things

### 1. The frontier — automatic, you never touch it

- **A mined cell rolls for a generator.** A generator drives the rate; a dud is inert ground. Raising
  the odds to 100% is the first thing the shop sells.
- **Only generators on the frontier emit** — mined, a generator, *and* next to a cell they can still
  take. Interior cells go quiet.
- **If the frontier is ever nothing but duds, the run is over.** That is how a run ends, not a failure.
- Each frontier cell fires an orb on its own timer, and **how many generators you own sets how fast that
  timer runs**.
- An orb hops to an adjacent unmined cell and delivers its value. When a cell has absorbed its full
  cost, it is mined.

A frontier cell fires at whichever neighbour is **closest to done**, so cells land one after another
instead of six bars creeping at once.

**Why this shape:**

- **The snowball is literal and on screen.** More cells → the whole rim visibly speeds up.
- **It stays legible at scale.** Orb count tracks the **perimeter**, not the area.
- **Travel is one hop.** Fast, punchy, constantly landing.
- **The visual is a ring of light on the growing edge**, which reads instantly as *this is where you are.*

**Income is one global pool**, not per-blob. A distant colony is throttled by its tiny perimeter and
the expensive ground it sits on.

### 2. The ram — the only thing you aim

- The pool banks **20% of the cost of every cell you mine**, so it scales with the board.
- You may throw it at **any unmined cell in an unlocked colour, at any distance**.
- It deals its pool as **damage** to that cell's progress. Damage that doesn't finish the cell **stays
  as progress**.
- **Only what actually lands is spent.** The surplus stays banked, so the decision is *where*, never
  *whether you saved too much*.

**Why the pool comes from mining:** spreading wide loads the gun that lets you go deep.

**Why a colony and not just a hole:** colonies make your territory *shaped*. Crack open a cell next to
that far legendary and let a colony grow toward you, or put the damage into the ring in front of you?

### 3. Ascension — a phase, not a button

| Phase | What is happening | The way on |
|---|---|---|
| **Running** | The board ticks. The shop cannot be opened. | **End run** — one click, no confirmation |
| **Shopping** | Everything is banked, the next board is dealt and frozen behind the shop. | **Start run** |

Ending a run banks it and deals the next board in the same instant. Nothing ticks while you shop, and
**every purchase lands on the board waiting behind the modal**. When the frontier stalls, the end-run
button says so — *run over, claim*.

**The shop is one horizontal block per colour.** Red is open from the start. Each block holds that
colour's upgrades plus **Mine <next colour>**; buying it opens the next colour on the board *and* the
next block in the shop. The next closed block is shown dimmed, so you can see what you are saving for.

**Upgrades have no level cap** unless the effect is bounded (generator chance stops at 100%, unlocks
are one-offs).

> **A buff type does not appear on the board until you have bought it.**

The shop also holds **Reset progress** — wallet and purchases back to first boot, on two clicks.

---

## The board

**Concentric colour rings on a hex lattice, split by air gaps.**

- **One empty ring separates every two colours.** The only way across is a **tunnel**: a single cell
  in the gap, owned by the outer colour, so it opens with **Mine <colour>**.
- **Tunnels alternate sides.** Red → Orange is at the left tip, Orange → Yellow at the right tip, and so
  on out. Reaching the next colour means going halfway around the current one.
- **Radius 62** from the centre (56 rings of depth + 6 gaps) → 10,591 cells.
- **You start on the centre cell**, mined. Everything else dark.
- **Fixed topology, fixed region positions.** Only buff placement is randomised.

### Colour: two independent channels

| Channel | Means |
|---|---|
| **Hue** | Depth region. Red at the core, purple at the rim. |
| **Glow / size** | Node rarity. A big pale bloom is a keystone, wherever it sits. |

### Regions

Every region is **eight rings** deep. Hops are depth, gaps excluded; cells include the tunnel.

| Region | Hops | Cells | Cell cost | Clear pays |
|---|---|---|---|---|
| Red | 0–8 | 217 | 82 – 2,706 | 267,534 |
| Orange | 9–16 | 649 | 4,464 – 148,607 | 34.7 M |
| Yellow | 17–24 | 1,081 | 245 K – 8.2 M | 3.00 B |
| Green | 25–32 | 1,513 | 13.5 M – 449 M | 225 B |
| Teal | 33–40 | 1,945 | 740 M – 24.6 B | 15.7 T |
| Blue | 41–48 | 2,377 | 40.7 B – 1.35 T | 1.04 Q |
| Purple | 49–56 | 2,809 | 2.2 T – 74 T | 67.4 Q |

**A region is a wall for everything.** Neither the frontier nor the ram can mine a colour you haven't
bought. Colonies exist only inside colours you own.

---

## Costs

**`cost(hops) = 50 × 1.65^hops`**, in integer steps.

Every ring costs the same ratio more than the one before, so the climb **never flattens**: the start is
cheap and the rim is astronomically expensive. Income grows with generators and perimeter, which is
fast early in a colour and falls behind the curve near its edge — that is the plateau.

| Hops | Cost | Ring cells | Ring total |
|---|---|---|---|
| 1 | 82 | 6 | 492 |
| 2 | 135 | 12 | 1,620 |
| 3 | 222 | 18 | 3,996 |
| 4 | 366 | 24 | 8,784 |
| 5 | 603 | 30 | 18,090 |
| 6 | 994 | 36 | 35,784 |
| 7 | 1,640 | 42 | 68,880 |
| 8 | 2,706 | 48 | 129,888 |

**Every cell pays currency equal to its cost when mined**, and sometimes also holds a node.

---

## Buffs

### The types

| Node | Rarity | Effect per level | Shop block |
|---|---|---|---|
| **Power** | Common | +1 orb value | Red |
| **Speed** | Common | +10% increased emission rate | Red |
| **Crit** | Rare | +5% chance an orb lands for ×5 value | Orange |
| **Split** | Rare | +5% chance a frontier cell emits two orbs instead of one | Yellow |
| **Splash** | Rare | +5% chance an orb also hits every other open neighbour of its target for 50% of its value | Green |

Power and Speed are **additive**; Crit, Split and Splash are **multiplicative**. The orange block also
sells **Crit multiplier** (+1× per level on top of ×5), and green sells **Splash strength** (+25% per
level).

**Every node found grants +1 level of its type**, and levels stack for the whole run. **A Power node
is worth its region's Power**: +1 in red, +10 in orange, +100 in yellow … +1 M in purple, the same
amount as that region's shop tier.

### Distribution

| Roll | Holds |
|---|---|
| 93% | Nothing extra |
| 5% | A common node (Power or Speed), +1 level |
| 1.5% | A rare node (Crit, Split or Splash), +1 level |
| 0.5% | A keystone — +3 levels of one type at once |

### The dilution rule

> **A purchase must never lower your expected run.**

1. **Fixed slots.** The board decides how many commons, rares and keystones exist. A slot whose rarity
   has no unlocked type stays empty, so buying a type fills empty slots.
2. **Additives and multipliers never share a table.** Power and Speed are commons; Crit, Split and
   Splash are rares.

### Vision

| Distance from mined | You see |
|---|---|
| 1–3 hops | **Full identity** — the name |
| 4–8 hops | **That a node exists, and its rarity** — a glow, sized by tier |
| Beyond | Nothing |

**Vision range is a shop purchase.**

---

## Juice

**This is a first-class section, not a polish pass.** 95% of playtime is watching an automatic process.

The rule: **every event gets a light and a shape.**

### Ambient

- Frontier cells **breathe** — a slow glow cycle.
- Interior cells hold a dim, still light.
- Orbs leave a short **motion trail** and land with a splash.
- **The tempo is the readout.** As generators accumulate, emission speeds up visibly.

### Per event

| Event | Juice |
|---|---|
| **Orb lands** | Splash in the region's hue. |
| **Cell mined** | The cell **pops** — scale overshoot, ring shockwave outward, shards. |
| **Crit** | Orb is visibly larger and brighter in flight. On landing: white flash and the multiplier in large text. |
| **Split** | Two orbs leave the same cell on the same tick. |
| **Splash** | The neighbours of the landing cell flash softly in their region's hue. |
| **Node revealed** | Its name floats up off the cell as it is mined. |
| **Ram loaded** | The meter climbs and pulses. Hovering a cell shows what the shot would do to it. |
| **Ram thrown** | Board dims for a beat → beam streaks out → impact bloom → the cell cracks and, if it broke, a colony ignites. |
| **Blobs merge** | Cells stop being frontier and go quiet. |

**Not built yet: sound.**

---

## The HUD

**Less Excel, more game.** Four things:

1. **Currency** — one number, top-left, with the end-run button under it.
2. **Ram pool** — a radial meter, top-right.
3. **Region progress** — cells mined / cells in the deepest open region, a bar in the region's colour.
4. **Buff levels** — one row per type, an icon and a name saying what it does, above a line breaking down
   the orb's value.

Rules: every readout, shop card and identified cell carries an icon, but an icon never replaces the
words; no debug info; tooltips carry the rest; nothing updates faster
than the eye can read.

---

## Controls

| Input | Does |
|---|---|
| Right-click | Ram that cell for the whole pool. Any unlocked cell, any distance |
| Left-drag | Pan |
| Wheel / pinch | Zoom (scroll in the shop) |
| Click **End run** | End the run and enter the shop |
| `[enter]` | Start the run waiting behind the shop |
| `[space]` | Pause |
| `[1]` `[2]` `[3]` | Speed ×1, ×4, ×16 |

---

## Balance

These match `sim/world.gd`, `sim/hex_map.gd` and `sim/node_catalog.gd`. **Keep in sync when tuning.**

| Value | Setting |
|---|---|
| Tick rate | 10 Hz |
| Hop time | 3 ticks (0.3 s) |
| Base orb value | 10 |
| Base emission interval | 20 ticks (2 s) |
| Emission rate | `interval = 20 × 100 / (100 + generators×2 + speed×10)`, floor 2 ticks |
| Rate per generator | +2 percentage points each — a dud contributes nothing |
| Generator chance | 0% before any purchase, 100% at ten levels |
| Cost | `50 × 1.65^hops` |
| Crit | ×5, +1 per Crit multiplier level |
| Splash | 50% of the orb's value to each other open neighbour, +25% per Splash strength level |
| Overcharge | +1% orb value per 100 generators, per level |
| Ram pool | 20% of the cost of every cell mined, +5% per Ram charge level. Only what lands is spent |
| Bounty | +10% currency from mined cells, per level |
| Ram reach | Any distance, open colours only |
| Vision — identity / rarity glow | 3 / 8 hops |
| Starting pool | Power unlocked; Speed, Crit, Split and Splash must be bought |

### Shop

These match `sim/meta_upgrades.gd`. "×1.5" means each level costs 1.5× the last.

**Every colour sells a Power tier and one unique.** Each Power tier grants ×10 the orb value of the one
before it: +1, +10, +100 … +1 M per purchase.

| Block | Purchase | Cost | Levels |
|---|---|---|---|
| Red | **Generator chance**, +10% | 100, ×1.5 | 10 |
| Red | Unlock **Speed** | 300 | 1 |
| Red | Power +1 | 200, ×1.6 | ∞ |
| Red | Speed level | 250, ×1.6 | ∞ |
| Red | Ram power, +25% damage | 500, ×1.8 | ∞ |
| Red | Vision, +1 hop | 400, ×2 | ∞ |
| Red | **Mine Orange** | 133,767 | 1 |
| Orange | Power +10 | 26,753, ×1.6 | ∞ |
| Orange | Unlock **Crit** | 200,650 | 1 |
| Orange | Crit level | 120,390, ×1.6 | ∞ |
| Orange | **Crit multiplier**, +1× | 321,040, ×2 | ∞ |
| Orange | **Mine Yellow** | 17.3 M | 1 |
| Yellow | Power +100 | 3.47 M, ×1.6 | ∞ |
| Yellow | Unlock **Split** | 26.0 M | 1 |
| Yellow | Split level | 15.6 M, ×1.6 | ∞ |
| Yellow | **Mine Green** | 1.50 B | 1 |
| Green | Power +1,000 | 300 M, ×1.6 | ∞ |
| Green | Unlock **Splash** | 2.25 B | 1 |
| Green | Splash level | 1.35 B, ×1.6 | ∞ |
| Green | **Splash strength**, +25% | 3.61 B, ×2 | ∞ |
| Green | **Mine Teal** | 113 B | 1 |
| Teal | Power +10,000 | 22.5 B, ×1.6 | ∞ |
| Teal | **Overcharge**, +1% orb value per 100 generators | 271 B, ×2 | ∞ |
| Teal | **Mine Blue** | 7.85 T | 1 |
| Blue | Power +100,000 | 1.57 T, ×1.6 | ∞ |
| Blue | **Ram charge**, +5% ram share | 18.8 T, ×2 | ∞ |
| Blue | **Mine Purple** | 522 T | 1 |
| Purple | Power +1,000,000 | 104 T, ×1.6 | ∞ |
| Purple | **Bounty**, +10% currency | 1.25 Q, ×2 | ∞ |

**Prices past red are derived from the cost curve**, as a share of what clearing the previous colour
pays: Power 10%, unlock 75%, level 45%, strength cards 120%. **Mine <colour>** costs 50% of what
clearing the colour before it pays.

### What those numbers mean in play

Measured headlessly with a greedy player (buys the cheapest thing it can, rams when the pool finishes a
cell, ends a run on a stall or after 10 minutes of game time):

- **Runs 1–2 stall at seven cells** and bank 492 — enough for the first generator levels.
- **Red** is nearly cleared by run 4, then cleared in under two minutes a run while saving for Mine
  Orange. Red is the easy, fast opening.
- **Orange** reaches 568/600 on its first run and is cleared from the second, then plateaus for about
  five runs while banking toward Mine Yellow.
- **Yellow** grows 600 → 743 → 793 → ~850 over four runs and holds around 850–880 of 984 for roughly ten
  more before Mine Green.
- **Green onward** has not been measured with its upgrade blocks yet.

---

## Open decisions

- **No tension, no failure state.** Deliberate. If playtesting reads flat, this is the first place to
  add something.
- **Level-up cards are not in.** They would grant *verbs* while nodes grant *numbers*.
- **Node synergies are unexplored.** With five types there's little to combine.
- **Board size.** 10,591 cells at radius 62. Late-colour performance and pacing are unproven.
- **Per-blob income was considered and rejected.** Perimeter and the cost gradient already throttle
  distant colonies.
