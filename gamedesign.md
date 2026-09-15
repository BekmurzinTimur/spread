# Spread

## The pitch

A board of dark hexes. One cell is lit. It starts eating outward on its own — a ring of light crawling
into the dark, orbs hopping from your edge into the cells beyond it, each one landing with a flash.

You don't route anything. You don't place anything. The spread runs itself and it gets faster every
time it swallows a cell, because **the cells you own are what powers the edge**. Ten cells is a slow
creep. Three hundred cells is a roaring perimeter.

Buried out in the dark are **buffs**. You can see them coming before you can read them — a glow at
range, a name up close — and they are what make the spread accelerate rather than merely continue:
orbs worth more, orbs firing faster, orbs that crit for five times value, orbs that bounce on to the next cell.

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
- **Plateau.** Cost compounds cell by cell along a belt, so its far end outruns your income. Runs
  stop gaining ground and become about getting strong enough to break the **boss** in the tunnel.
- **Switch.** Beating the boss opens the next colour and its upgrades, and growth starts again.

---

## The five things

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

- **The ram is bought in the red block.** Until then the pool banks nothing and the meter is dim.
- The pool banks **20% of the cost of every cell you mine**, so it scales with the board. A cell the
  ram itself finishes banks nothing.
- It is thrown through the **Power skill**: click the Power hex when it is ready, then click a cell.
- You may throw it at **any unmined cell in an unlocked colour, at any distance**.
- It deals its pool as **damage** to that cell's progress. Damage that doesn't finish the cell **stays
  as progress**.
- **Only what actually lands is spent.** The surplus stays banked, so the decision is *where*, never
  *whether you saved too much*.
- **Ram splash, Ram bounce and Ram splashing bounces** let the shot splash and bounce like an orb, from
  the damage that landed and rolling the same chances. Nothing they mine banks ram. Every hop strikes
  with the ram's sound.

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

**The shop has two tabs: Upgrades and Achievements.** It opens on Achievements when the run just
earned one.

**Upgrades are hex badges grouped by type** — Power, Speed, Crit, Bounce, Splash, Ram, Economy — each in
the colour of the block that sells it. Red is open from the start; a colour opens once you have beaten
the boss guarding it and banked the run. Upgrades of a closed colour are shown grey, so you can see what
the boss is guarding; an upgrade can instead be flagged hidden, a question mark until its colour opens.

- **Hover** an upgrade: the middle panel shows its colour, what it does, its level → the level you would
  reach, and the price.
- **The stat table** on the right lists every stat the shop moves as a run starts, and shows the new
  value next to each stat the hovered purchase would change.
- **Click** buys one level, **shift+click** five, **ctrl/cmd+click** twenty — or as many as the wallet
  and the cap allow.

**Upgrades have no level cap** unless the effect is bounded: generator chance and chance levels stop at
100%, unlocks are one-offs, and Ram power and Ram charge stop before the ram could pay for itself. Crit
levels are uncapped because crit chance flattens toward 50%.

> **A buff type does not appear on the board until you have bought it.**

The shop also holds **Reset progress** — wallet and purchases back to first boot, on two clicks.

### 4. Skills — the buff hexes

Every buff hex is a skill.

- **Mining charges them.** Each mined cell gives every unlocked skill +10% readiness, up to 100%. The
  hex background fills from the top down.
- **At 100%, click the hex.** The skill fires and goes on a **30 s cooldown**, during which it charges
  nothing.

| Hex | Skill |
|---|---|
| **Power** | Arms the ram; click a cell to throw it. Needs Ram bought |
| **Speed** | ×2 emission rate for 10 s — *more*, multiplying everything else |
| **Crit** | 100% crit chance for 10 s |
| **Bounce** | +1 bounce (+1 per Glaive skill level), and bounces lose nothing, for 10 s |
| **Splash** | Charges and fires, but has no effect yet |

### 5. Achievements — permanent buffs

- **Every achievement grants a permanent buff**, earned when a run is banked and kept until reset.
  Rewards multiply with each other.
- **Achievements are hex badges** in the shop's Achievements tab. Hovering one fills the panel on the
  right: name, status, what earns it, its reward, progress and the total of every reward held.

| State | Badge |
|---|---|
| **Unlocked** | Filled in its colour, white icon |
| **Locked** | Grey, dim icon; the fill shows progress if it has one (also a bar in the panel) |
| **Hidden** | Grey question mark and "???" until unlocked |

| Achievement | Earned by | Reward |
|---|---|---|
| **<Colour> boss** (one per boss, red to blue) | Beating that boss and banking the run | −33% emission rate, +75% orb value |

The boss rewards trade orbs for value: fewer orbs on screen, each worth more, ×1.17 damage per boss.
No achievement is hidden yet.

---

## The board

**Concentric colour rings on a hex lattice, split by air gaps.**

- **One empty ring separates every two colours.** The only way across is a **tunnel** holding one
  **boss** cell. It is the inner colour (the red→orange boss is red), so you can always mine it.
- **The boss is the gate.** It costs 20× its colour's dearest cell, far more than the first cell beyond
  it, and every ability works on it. Beating it opens the next colour on the board at once, for good,
  and opens that colour's shop block once the run is banked. The boss is back in the tunnel every run.
- **Bosses stand out** once in vision: a large hex with a crowned skull and a pulsing glow in their colour.
- **Tunnels alternate sides.** Red → Orange is at the left tip, Orange → Yellow at the right tip, and so
  on out. Reaching the next colour means going halfway around the current one.
- **Radius 62** from the centre (56 rings of depth + 6 gaps) → 10,591 cells.
- **You start on the centre cell**, mined. Everything else dark.
- **Fixed topology, fixed region positions.** Only buff placement is randomised.

### Colour: two independent channels

| Channel | Means |
|---|---|
| **Hue** | Depth region. Red at the core, purple at the rim. |
| **Glow / size** | Node rarity. A big pale bloom is a keystone, wherever it sits; unmined keystones are also larger and pulse. |

### Regions

Every region is **eight rings** deep. Cells include the outgoing boss.

| Region | Cells | Entry cell | Exit tip | Boss |
|---|---|---|---|---|
| Red | 218 | 4 | 512 | 10,240 |
| Orange | 649 | 1,024 | 1.4e10 | 2.8e11 |
| Yellow | 1,081 | 2.8e10 | 2.1e22 | 4.3e23 |
| Green | 1,513 | 4.3e22 | 1.9e39 | 3.7e40 |
| Teal | 1,945 | 3.7e39 | 9.3e60 | 1.9e62 |
| Blue | 2,377 | 1.9e61 | 2.6e87 | 5.2e88 |
| Purple | 2,808 | 5.2e87 | 4.2e118 | — |

**A region is a wall for everything.** Neither the frontier nor the ram can mine a colour whose boss you
have never beaten. Colonies exist only inside open colours.

---

## Costs

- **Red costs by ring**: `4 × 2^(ring−1)`, so the first cell takes 4 base orbs.
- **Every belt doubles cell by cell** from its entry tip to its exit tip, counted along its middle ring.
  Cells across the belt's width cost the same.
- **Cost only goes up.** Each colour's entry costs ×2 the previous colour's exit tip. The only exceptions
  are bosses (20× their colour's exit) and keystones (10× the ground they sit in).
- **Every cost knob is one block** at the top of `sim/hex_map.gd`: growth per step for each colour, the
  entry step, and the boss and keystone multipliers.

| Red ring | Cost | Ring cells | Ring total |
|---|---|---|---|
| 1 | 4 | 6 | 24 |
| 2 | 8 | 12 | 96 |
| 3 | 16 | 18 | 288 |
| 4 | 32 | 24 | 768 |
| 5 | 64 | 30 | 1,920 |
| 6 | 128 | 36 | 4,608 |
| 7 | 256 | 42 | 10,752 |
| 8 | 512 | 48 | 24,576 |

**Every cell pays currency equal to its cost when mined**, and sometimes also holds a node.

---

## Buffs

### The types

| Node | Rarity | Effect per level | Shop block |
|---|---|---|---|
| **Power** | Common, rare | +1 orb value | Red |
| **Speed** | Common | +10% increased emission rate | Red |
| **Crit** | Rare | Chance an orb lands for ×5 value, diminishing toward 50%: 5% at level 1, 25% at 9 | Orange |
| **Bounce** | Keystone only | +1 bounce. Every orb, after landing, hops on to a random open neighbour of its target (back where it came from included), keeping 50% of its value each hop. With nowhere to go (a boss in its tunnel), every bounce left hits that cell at once | Yellow |
| **Splash** | Rare | +5% chance an orb also hits its target and every open neighbour of it for 50% of its value | Green |

Power and Speed are **additive**; Crit, Splash and Bounce are **multiplicative**. The orange block also
sells **Orb value ×2**, which doubles the whole orb value per level — flat Power gives each new colour its
jump, the multiplier carries you through the belt. It sells **Crit multiplier** (+1× per level on top of ×5), yellow sells **Bounce strength** (+5% kept per
level, up to 90%) and **Glaive skill** (+1 skill bounce), and green sells **Splash strength** (+25% per
level) and **Splashing bounces** (every bounce hop rolls for splash too).

**Every node found grants +1 level of its type**, and levels stack for the whole run. **A Power node
is worth its region's Power × its rarity**: region Power is +1 in red, +10 in orange, +100 in yellow …
+1,000,000 in purple (the same as that region's shop tier); rarity multiplies it ×1 common, ×3 rare, ×30
keystone. Rarity works the same in every region.

**Keystones are mini bosses.** They cost 10× their ground and grant a run-changing amount: ×30 region
Power, +10 levels of Speed, Crit or Splash, or +1 bounce.

**Every belt from orange out holds mandatory keystones**: 3 in orange, +1 per colour (8 in purple). They sit
on the belt's middle ring, spaced evenly from entry tip to exit tip, alternating the top and bottom arcs.
They are there every run, on top of the random ones.

### Distribution

| Roll | Holds |
|---|---|
| 93% | Nothing extra |
| 4% | A common node (Power or Speed), +1 level |
| 1% | A rare Power node, ×3 region Power |
| 1.5% | A rare node (Crit or Splash), +1 level |
| 0.5% | A keystone — +10 levels of one type, +1 bounce, or ×30 region Power; costs ×10 |

Bosses never hold a node. Mandatory keystone cells skip the roll and always hold a keystone.

### The dilution rule

> **A purchase must never lower your expected run.**

1. **Fixed slots.** The board decides how many commons, rares and keystones exist. A slot whose rarity
   has no unlocked type stays empty, so buying a type fills empty slots.
2. **Additives and multipliers never share a table.** Power and Speed are commons; Crit and Splash
   are rares; Bounce only ever sits on a keystone. Rare Power has its own slot, and Power is always unlocked, so it is never diluted.

### Vision

| Distance from mined | You see |
|---|---|
| 1 hop | **Full identity** — the name |
| 2–4 hops | **That a node exists, and its rarity** — a glow, sized by tier |
| Beyond | Nothing |

**Every boss beaten widens both ranges by 1 hop**, from the moment it falls and in every later run.

---

## Juice

**This is a first-class section, not a polish pass.** 95% of playtime is watching an automatic process.

The rule: **every event gets a light and a shape.**

### Ambient

- Frontier cells **breathe** — a slow glow cycle.
- Bosses and unmined keystones are **larger hexes with a pulsing halo**.
- Interior cells hold a dim, still light.
- Unmined cells show an **enemy skull**, generators a **soldier's helmet**, duds a slashed ring. A
  visible node's icon takes the centre instead.
- Orbs leave a short **motion trail** and land with a splash.
- **The tempo is the readout.** As generators accumulate, emission speeds up visibly.

### Per event

| Event | Juice |
|---|---|
| **Orb lands** | Splash in the region's hue. |
| **Cell mined** | The cell **pops** — scale overshoot, ring shockwave outward, shards. |
| **Crit** | Orb is visibly larger and brighter in flight. On landing: white flash and the multiplier in large text. |
| **Bounce** | The orb hops on from the cell it hit to the next one. |
| **Splash** | A ring expands from the landing cell out to its neighbours, which flash softly in their region's hue. On an orb that bounces on, the splash goes off one hop later, behind it, so it never leaves the bounce nowhere to go. |
| **Node revealed** | Its name floats up off the cell as it is mined. |
| **Boss beaten** | A big white burst and "<COLOUR> OPEN" floats up. |
| **Skill ready** | The hex is full and its outline pulses; active or armed, it turns white. |
| **Ram loaded** | The meter climbs and pulses. While armed, hovering a cell shows what the shot would do to it. |
| **Ram thrown** | Board dims for a beat → beam streaks out → impact bloom → the cell cracks and, if it broke, a colony ignites. With Ram bounce the beam hops on from cell to cell, drawn above the orbs. |
| **Blobs merge** | Cells stop being frontier and go quiet. |

**Not built yet: sound.**

---

## The HUD

**Less Excel, more game.** Five things:

1. **Currency** — one number, top-left, with the end-run button under it.
2. **Orb value** — a big number, top-centre, in the deepest open colour; it pops when it grows.
3. **Ram pool** — a radial meter, top-right.
4. **Buff hexes** — bottom-left, one hex per type in the colour of the region that unlocks it. Above it
   the final stat (orb value, emits per second, crit chance and multiplier, bounces and value kept, splash chance
   and strength); below it the level. A mined node's "+levels" rises above its hex. A locked type is a
   grey question mark. The hex fills with its skill's readiness and is clicked to fire it.
5. **Region progress** — a large bar along the bottom: cells mined / cells in the deepest open region,
   in the region's colour.

Rules: every readout, shop card and identified cell carries an icon; a buff hex names itself in its
tooltip; no debug info; tooltips carry the rest; nothing updates faster than the eye can read.

---

## Controls

| Input | Does |
|---|---|
| Click a ready hex | Fire its skill; Power arms the ram |
| Left-click (ram armed) | Ram that cell for the whole pool. Any unlocked cell, any distance |
| Right-click / `[esc]` | Disarm the ram |
| Left-drag | Pan |
| Wheel / pinch | Zoom (scroll in the shop) |
| Click **End run** | End the run and enter the shop |
| Click an upgrade | Buy one level |
| Shift / ctrl (cmd) + click an upgrade | Buy 5 / 20 levels, or as many as you can |
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
| Base orb value | 1 |
| Orb value | `(1 + Power) × (100 + Overcharge)% × 2^(Orb value ×2 levels) × 1.75^(boss achievements)` |
| Base emission interval | 20 ticks (2 s) |
| Emission rate | `0.5/s × (100 + generators×2 + speed×10)% × 0.67^(boss achievements)`, doubled while the Speed skill is active, uncapped |
| Rate per generator | +2 percentage points each — a dud contributes nothing |
| Generator chance | 0% before any purchase, +20% per level, 100% at five levels |
| Cost | Red `4 × 2^(ring−1)`; belts ×2 per cell along the middle ring; each entry ×2 the previous exit |
| Boss | 20× its colour's exit tip; opens the next colour |
| Keystone | Costs ×10; grants ×30 region Power or +10 levels |
| Mandatory keystones | 3 on orange's middle ring, +1 per colour |
| Crit | `50% × levels / (levels + 9)` chance; ×5, +1 per Crit multiplier level |
| Skills | +10% readiness per mined cell, max 100%; 30 s cooldown; Speed and Crit last 10 s |
| Splash | 50% of the orb's value to its target and each open neighbour, +25% per Splash strength level |
| Bounce | +1 bounce per level; each keeps 50%, +5% per Bounce strength (max 90%); the skill adds 1 + Glaive skill bounces and keeps 100% |
| Overcharge | +1% orb value per generator, per level |
| Ram pool | 20% of the cost of every cell mined, +5% per Ram charge level (max 2). Only what lands is spent. Nothing before Ram is bought, nothing from a cell the ram or its splash and bounces finish |
| Bounty | +10% currency from mined cells, per level |
| Ram reach | Any distance, open colours only |
| Vision — identity / rarity glow | 1 / 4 hops, +1 each per open colour past red |
| Starting pool | Power unlocked; Speed, Crit, Bounce and Splash must be bought |

### Shop

These match `sim/meta_upgrades.gd`. "×1.5" means each level costs 1.5× the last.

**Every colour sells a Power tier and one unique.** Each Power tier grants ×10 the orb value of the one
before it: +1, +10, +100 … +1,000,000 per purchase. There are no region purchases — bosses open colours.

| Block | Purchase | Cost | Levels |
|---|---|---|---|
| Red | **Generator chance**, +20% | 5, ×5 | 5 |
| Red | Unlock **Speed** | 25 | 1 |
| Red | Power +1 | 15, ×1.6 | ∞ |
| Red | Speed level | 18, ×1.6 | ∞ |
| Red | Unlock **Ram** | 50 | 1 |
| Red | Ram power, +25% damage | 40, ×1.8 | 2 |
| Orange | Power +10 | 20,480, ×1.4 | ∞ |
| Orange | **Orb value ×2** | 204,800, ×2.5 | ∞ |
| Orange | Unlock **Crit** | 102,400 | 1 |
| Orange | Crit level | 40,960, ×2.5 | ∞ |
| Orange | **Crit multiplier**, +1× | 204,800, ×2.5 | ∞ |
| Yellow | Power +100 | 512 K, ×1.4 | ∞ |
| Yellow | Unlock **Bounce** | 1e14 | 1 |
| Yellow | Bounce level, +1 bounce | 1e15, ×10 | ∞ |
| Yellow | **Bounce strength**, +5% kept | 1e14, ×4 | 8 |
| Yellow | **Glaive skill**, +1 skill bounce | 1e15, ×10 | ∞ |
| Yellow | **Ram bounce**, the ram bounces like an orb | 1e15 | 1 |
| Green | Power +1,000 | 12.8 M, ×1.4 | ∞ |
| Green | Unlock **Splash** | 64 M | 1 |
| Green | Splash level | 25.6 M, ×2.5 | 20 |
| Green | **Splash strength**, +25% | 128 M, ×2.5 | ∞ |
| Green | **Splashing bounces**, bounces roll for splash | 64 M | 1 |
| Green | **Ram splash**, the ram rolls for splash like an orb | 640 M | 1 |
| Green | **Ram splashing bounces**, ram bounces roll for splash | 640 M | 1 |
| Teal | Power +10,000 | 320 M, ×1.4 | ∞ |
| Teal | **Overcharge**, +1% orb value per generator | 3.2 B, ×2.5 | ∞ |
| Blue | Power +100,000 | 8 B, ×1.4 | ∞ |
| Blue | **Ram charge**, +5% ram share | 80 B, ×2.5 | 2 |
| Purple | Power +1,000,000 | 200 B, ×1.4 | ∞ |
| Purple | **Bounty**, +10% currency | 2 T, ×2.5 | ∞ |

**Bounce is hand-priced far above its block** — an expensive mechanic. **Other prices past red are counted in a per-colour unit** — 2,048 in orange, ×25 per colour: Power 10, unlock
50, chance level 20, strength cards 100. Chance levels and strength cards multiply, so they climb ×2.5 a
level.

### What those numbers mean in play

Not yet measured on the current cost curve.

---

## Open decisions

- **No tension, no failure state.** Deliberate. If playtesting reads flat, this is the first place to
  add something.
- **Level-up cards are not in.** They would grant *verbs* while nodes grant *numbers*.
- **Node synergies are unexplored.** With five types there's little to combine.
- **Board size.** 10,591 cells at radius 62. Late-colour performance and pacing are unproven.
- **Per-blob income was considered and rejected.** Perimeter and the cost gradient already throttle
  distant colonies.
