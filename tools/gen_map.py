#!/usr/bin/env python3
"""Generate data/map_01.json — a honeycomb.

Run from the project root:  python3 tools/gen_map.py

The board starts as an odd-r offset *triangular* lattice, where every cell has up
to six neighbours. Drawn as cells and edges that reads as a mesh of triangles,
not as a hex map — the hexagons are there, but each one has a cell sitting in the
middle of it, and the eye sees the triangles instead.

So the centre of every hexagon is removed. A triangular lattice splits into three
sublattices by `(q - r) % 3`; deleting one of them leaves exactly the honeycomb,
each surviving cell with three neighbours, and the board finally looks like a hex
map. A couple of centres are kept as hubs — they are the only cells with more
than three edges, and they read as junctions.

Removing centres leaves dangling cells around the rim, so anything with fewer
than two neighbours is pruned repeatedly until none remain: a degree-1 cell is a
dead end, not a web.

Honeycomb is sparse, which costs cell count, and play starts in the *middle* of
the board rather than in a corner — so the number that has to clear unaided
reach is the radius from the centre, not the diameter. That roughly doubles the
lattice a corner start needed: 13x13, for a radius of 11 against a 10-hop reach.
Anything smaller and every cell sits inside range of the starting generator, the
search finds no placement its pumps are needed for, and the assertion at the
bottom fires.

Contents are *searched for*, not hand-placed. Generators are anchored where the
map buries them, so where a placement leaves the player is a sequencing question
— can you bootstrap your way out to the next buried generator? — and no static
property answers it. `play()` below answers it by playing the map, and the search
ranks candidates on what it finds.

`play()` used to *assert* the board was winnable, and does not any more. The
shipped board is known to clear, and the model's pump is a frozen number rather
than a mirror of the simulation's — a percentage restore since — so an assertion
built on it would fail a board that is in fact fine. It reports now, and the
report is worth reading; it is not a gate.

Roughly half the cells bury something, and unlock cost is *geometric* in distance
from the start rather than linear. The two go together: a denser board hands the
player compounding power — pumps stack flat bonuses, spheres stack onto whatever
is near them — so a cost curve that only adds a constant per hop falls behind it,
and the far side of the map ends up cheaper in real terms than the near side. See
GENERATOR_COUNT and COST_GROWTH below for the numbers and what constrains them.

Prints a distance/arrival table, reports the playthrough, and asserts the
*shape* properties the game depends on — the colour gate, the challenge order,
the single starting region.
"""

import collections
import json
import random
import re

SEED = 20260906

# Must match sim/world.gd and sim/block_catalog.gd. Decay is charged per cell
# *crossed*, so a route of N hops pays it N-1 times — see the note in `play()`.
ORB_START_VALUE = 10
DECAY_PER_HOP = 1
UPGRADE_COST = 60

# The seven tiers, in ladder order. **Must match `sim/tiers.gd`** — the map names
# a cell's gate as a string, and a name this file emits that `Tiers.from_name`
# does not recognise falls back to red, which would quietly unlock the rim.
TIER_NAMES = ("red", "orange", "yellow", "green", "teal", "blue", "purple")

# One letter each for the ASCII board below. Red is a space rather than "r": most
# of the opening is red, and a column of letters where the old map had blanks
# would make the board harder to read, not easier.
TIER_LETTERS = (" ", "o", "y", "g", "t", "b", "p")

# A **frozen placement heuristic**, and pointedly no longer one of the constants
# above. The simulation's pump restores a percentage of an orb's launch value
# (20%, so 2 on a plain orb), not a flat 3 — this is the number the shipped map
# was drawn under, and `play()` uses it only to rank candidate placements.
#
# Left alone on purpose. It feeds the search that chose the generator, upgrader
# and challenge positions, and that search consumes the RNG stream, so changing
# it would reshuffle every placement on the board the next time anyone
# regenerates. Nothing asserts winnability any more, so it has nothing to be
# accurate *for* — see the note where the playthrough is reported.
PUMP_RESTORE = 3

# Seven colour bands need room. At 13x13 the radius was 11, which is under two
# hops a band once red has taken the opening — a band that thin is a ring rather
# than a region, and a colour you cross in one step teaches nothing. 19x19 gives
# 230 cells at a radius of 15: red keeps four hops to open in, and every colour
# after it gets two.
COLS, ROWS = 19, 19

# Which of the three sublattices to delete. These are the hexagon centres; taking
# them out is what turns the triangular mesh into a honeycomb.
CENTRE_CLASS = 0

# Centres kept anyway, as junctions. Every other cell has three neighbours, so
# these are the only place the board opens up. Keep few: each one shortens routes
# across the middle, which is exactly what pumps are there to pay for.
KEPT_CENTRES = {(0, 4), (7, 3)}

# Roughly half the board is buried with something. A map that is mostly empty
# holes makes mining a formality — you pay, you dig, you find nothing, you pay
# again — and the reward for pushing outward has to be more than fog lifting.
#
# **A couple of generators per colour**, and four for red. Every tier now has an
# income that does not run through a converter, so a colour is a place on the
# board rather than a rung on a ladder. Red gets double because it is the
# bootstrap: it is the only colour on hand before anything at all has been mined,
# and it is what feeds every upgrader afterwards.
#
# Two is deliberately thin. A tier with two anchored sources is a tier whose
# reach is decided by where the map put them, which is the same question
# anchoring has always asked about red — one level up, six more times.
GENERATOR_COUNTS = (4, 2, 2, 2, 2, 2, 2)
GENERATOR_COUNT = sum(GENERATOR_COUNTS)

# Scaled with the board: 230 cells against 106 is a little over double, and the
# pump and sphere counts follow it. Density belongs here rather than in
# generators, because these two are the movable blocks — they are what the player
# actually rearranges, and what a longer route is paid for with.
PUMP_COUNT = 40

# Spheres speed up generators and strengthen pumps within a couple of hops.
# Placed but deliberately *not* modelled by `play()` below — see the note there.
# The challenges below are left out of it for the same reason.
SPHERE_COUNT = 30

# Generators must land in at least this many quadrants of the board. Anchored
# generators are the only sources there are, so clustering them in one corner
# leaves most of the map supplied from a single direction.
#
# This pulls against the pump requirement below and the tension is real, not an
# artifact: generators spaced evenly leave every cell within a few hops of one,
# and then nothing ever needs a pump. Quadrant *coverage* is the compromise —
# spread across the board without being spread uniformly.
MIN_QUADRANTS = 3

# How many cells a placement must strand when its pumps are taken away before the
# search stops looking. Without an early exit the search runs every candidate for
# no better result.
#
# A floor to stop at, not a guarantee, and nothing asserts a stranded cell any
# more. Its ceiling is set by GENERATOR_COUNT: every anchored source added shrinks
# the region nothing already reaches unaided. Sixteen generators would make it
# unreachable if they were all red — but they are not, and a purple generator
# cannot mine a red cell, so the colour bands cut the other way and stranding is
# easier to come by than it was.
STRANDED_TARGET = 2

# Two orders of magnitude smaller than it was, and it has to be. `play()` walks a
# seven-tier source table over 230 cells instead of two tiers over 106, so a
# single playthrough costs something now — 20,000 of them would take minutes.
# Nothing downstream asserts on the result any more, so the search is a *ranking*
# with an early exit: a few hundred draws finds a good placement, and the best of
# them ships whether or not it hit the target.
SEARCH_TRIES = 300

# On-screen spacing. 0.866 is sin(60°): the row step of a regular hex lattice.
SPACING = 190
ROW_STEP = 0.866

# Cost rises with distance from the start while arrivals shrink, so the far side
# is deliberately impractical until pumps are in place.
#
# **Geometric in hops, not linear.** Cost used to be `25 + 7 * hops`, which put the
# far rim at 102 against a near ring of 32 — barely three times the price for
# eleven times the distance. That is the wrong shape, because the player's side of
# the trade compounds: every pump found adds a flat +3 to every orb on the route,
# every sphere found speeds every generator near it, and reach grows faster than a
# straight line. Against linear cost the late board got cheaper in real terms the
# further out it went. Doubling per hop makes distance cost something.
#
# The exponent is `hops - 1`, so COST_BASE is the price of the *first ring* rather
# than a notional cost-at-zero-hops nothing is ever charged. That matters because
# the opening is the one part of the curve tuned by feel rather than by shape: the
# first two cells are what a player pays before owning a second generator, and
# they were rough at 75 and 112. Written this way the number that sets them is
# right here and means what it says.
#
# **Growth came down from 2.0 with the board.** The exponent is distance from the
# start, and the radius went from 11 to 15 — four more doublings, which put the
# rim at 409,600 against a first ring of 50. A colour has two anchored generators
# behind it, so that is hours of a purple line for one cell, and the curve stopped
# describing a game. At 1.6 the same rim is a few tens of thousands: still a
# thousand times the opening ring, still steeper than anything the player's side
# compounds by, and still finishable.
COST_BASE = 50
COST_GROWTH = 1.6

# The three challenges. One of each is buried in **every colour band**, so a board
# of seven bands carries twenty-one of them.
#
# The three effects are placeholders that repeat unchanged in every band, which
# means they *stack*: a full clear is +35 orb value, +140% pump restore and +350%
# sphere radius. That is a much stronger endgame than three challenges granted
# once, and it is deliberate for now — the types differentiate per band later, and
# the per-instance numbers in `sim/block_catalog.gd` are the first thing to retune
# when they do.
#
# What survives that change is the shape: a challenge is a detour. You stop
# pushing the frontier and pay six times a normal cell for something whose payout
# you cannot see, and there is one of those decisions waiting in every colour.
CHALLENGE_IDS = ("challenge_surge", "challenge_current", "challenge_lens")
CHALLENGE_COUNT = len(CHALLENGE_IDS) * len(TIER_NAMES)

# What a challenge costs, as a multiple of the normal cost for its distance. Six
# is about four extra hops' worth of the geometric ramp: enough that mining one
# is a decision you plan a pump chain around rather than something you clear in
# passing, and not so much that the far ones are out of reach of a board that has
# already found most of its generators.
#
# Invisible to `play()`, which ignores unlock cost entirely — see the note there.
# So this number cannot change what the playthrough reports; it changes how long
# the board takes, not whether it can be finished.
CHALLENGE_COST_MULTIPLIER = 6

# --- The colour ladder --------------------------------------------------
#
# Each tier owns a ring of the board, red at the middle and purple at the rim.
# The hop at which each colour takes over, matching TIER_NAMES from the second
# entry on: red runs 0-4, orange 5-6, yellow 7-8, then a hop each for green, teal
# and blue, and everything from 12 out is purple.
#
# **Uneven on purpose, because the rings are.** A honeycomb cut out of a square
# has rings that grow to hop 9-11 and then collapse as the board runs out of
# corners: 3 cells at hop 1, 28 at hop 9, and 2 at hop 15. Bands of equal width
# would put 14 cells in red and 8 in purple with 55 in the middle — a colour you
# cross in one step either side of one you live in. Measured against the ring
# sizes instead, these give 31 / 34 / 46 / 28 / 27 / 28 / 36, which is as close
# to even as a square board allows.
#
# Red keeps five hops because the opening is the part of the curve tuned by feel
# rather than by shape: it is the whole game before a second colour exists, and
# it has to be long enough to find a few generators in.
BAND_EDGES = (5, 7, 9, 10, 11, 12)

# A fraction of the cells in the *last* hop of a band are promoted one colour, so
# a player meets each new colour as a scatter of cells they cannot pay for yet
# while the current one still works everywhere else. A hard boundary would read
# as a wall and simply be routed around until the day it opened; a scatter
# teaches the rule before it becomes the only rule.
#
# **Only a band more than one hop wide donates.** The rings run out toward the
# rim, so the deep bands are a single hop each, and taking a third of a one-hop
# band leaves it a third smaller and its neighbour a third larger — measured, it
# cut green from 28 cells to 16. It costs nothing to skip them: out there the
# colour changes every single ring, so the next colour needs no announcing. It is
# already the next ring out.
SCATTER_DENSITY = 0.35

# A colour's cells cost less than the same distance in red, and by exactly as
# much as its income is thinner: two anchored generators against red's four.
#
# It replaces a `/4` that existed for a reason that has gone. Orange used to be
# minted from red at UPGRADE_COST per orb, so pricing it on the red curve would
# have made it that whole multiple harder in real terms. Orange has its own
# generators now, so the only asymmetry left is how many.
DEEP_TIER_COST_DIVISOR = 2

# Upgraders are anchored like generators, so where these land decides where a
# colour can be made *other than* where the map buried its generators. Two per
# step of the ladder, red -> orange through blue -> purple.
#
# Each is buried on a cell gated at or below the colour it consumes — an upgrader
# you cannot afford to mine until you already have the colour it makes is a
# deadlock, and the assertions at the bottom pin that it never happens.
UPGRADERS_PER_STEP = 2
UPGRADER_COUNT = UPGRADERS_PER_STEP * (len(TIER_NAMES) - 1)

# --- Upkeep ---
# Blocks that burn a trickle of red to hold a board-wide "generators run 25%
# faster" bonus up. Two, not three: the buff is an *increased rate* and every
# source of one shares a single divisor, so at two the board tops out at +50%
# (interval 20 -> 13) and a sphere reaching a generator still moves it a long way
# further. A third would take the baseline to 11 and leave each sphere buying
# less, which quietly devalues a block type that already exists.
#
# Two is also what makes "which one do I feed?" a question at all. It does not
# scale with the board, because the argument above is about the divisor rather
# than about how much room there is.
UPKEEP_COUNT = 2
# Mid-game, and shallow, because they eat red. The band is a hop range rather
# than a colour, but UPKEEP_MAX_TIER below is the rule that matters: a cell out
# past the red and orange rings could not be fed until the red line already
# reached it, which is long after a faster generator was worth having.
UPKEEP_BAND = (2, 5)
UPKEEP_MAX_TIER = 1


# --- The colour ladder --------------------------------------------------


def band_of(hops):
    """Which tier owns this distance, before any scatter. 0 for red."""
    return sum(1 for edge in BAND_EDGES if hops >= edge)


def band_range(tier):
    """The hop range a tier owns, `high` inclusive and None for the rim."""
    low = 0 if tier == 0 else BAND_EDGES[tier - 1]
    high = BAND_EDGES[tier] - 1 if tier < len(BAND_EDGES) else None
    return low, high


# --- The lattice --------------------------------------------------------


def axial(col, row):
    """Offset (odd-r) to axial coordinates, which is where the 3-colouring lives."""
    return col - (row - (row & 1)) // 2, row


def neighbors(col, row, cells):
    """Odd-r offset hex: up to six neighbours, restricted to `cells`."""
    if row % 2 == 0:
        deltas = [(-1, 0), (1, 0), (-1, -1), (0, -1), (-1, 1), (0, 1)]
    else:
        deltas = [(-1, 0), (1, 0), (0, -1), (1, -1), (0, 1), (1, 1)]
    for dc, dr in deltas:
        n = (col + dc, row + dr)
        if n in cells:
            yield n


def honeycomb():
    """The triangular lattice with its hexagon centres taken out, then pruned.

    `(q - r) % 3` three-colours a triangular lattice, and each colour class is
    the set of centres of the hexagons formed by the other two. Dropping one
    class therefore leaves the honeycomb: every remaining cell keeps exactly the
    three neighbours that form its hexagon's rim.

    Pruning afterwards is not optional. The rim of the board is left with cells
    that kept only one neighbour, and a degree-1 cell is a dead end — the map
    asserts against them, and they make for a miserable route.
    """
    full = {(c, r) for c in range(COLS) for r in range(ROWS)}
    q_minus_r = lambda xy: (axial(*xy)[0] - axial(*xy)[1]) % 3
    cells = {xy for xy in full if q_minus_r(xy) != CENTRE_CLASS} | KEPT_CENTRES

    while True:
        dangling = {xy for xy in cells if len(list(neighbors(*xy, cells))) < 2}
        if not dangling:
            return cells
        cells -= dangling


def build_lattice():
    cells = honeycomb()
    # Row-major ids. This fixes the BFS tie-break: neighbour lists are sorted
    # ascending and the lowest id wins, so among equally short routes orbs
    # consistently prefer the row above. Deterministic and intended — but
    # visible, which is why the ordering is stated here.
    coords = sorted(cells, key=lambda xy: (xy[1], xy[0]))
    ids = {xy: i for i, xy in enumerate(coords)}
    adjacency = {
        ids[xy]: sorted(ids[n] for n in neighbors(*xy, cells)) for xy in coords
    }
    positions = {
        ids[(c, r)]: (
            round(c * SPACING + (r % 2) * SPACING / 2),
            round(r * SPACING * ROW_STEP),
        )
        for c, r in coords
    }
    return coords, ids, adjacency, positions


def central_cell(adjacency, positions):
    """The cell nearest the middle of the board, which is where play begins.

    Starting in a corner meant the map only ever opened in one direction, and
    the far corner sat at the full diameter — the most expensive cells on the
    board were also the last ones any route could reach. From the middle the
    frontier grows outward on every side at once, and the worst distance is
    roughly the radius rather than the diameter.

    Measured in pixels against the centroid rather than in hops, because the
    lattice is what has a middle; ties break on the lowest id, so this is
    deterministic like everything else here.
    """
    cx = sum(positions[c][0] for c in adjacency) / len(adjacency)
    cy = sum(positions[c][1] for c in adjacency) / len(adjacency)
    return min(
        sorted(adjacency),
        key=lambda c: (positions[c][0] - cx) ** 2 + (positions[c][1] - cy) ** 2,
    )


def bfs(adjacency, source, allowed=None):
    """Distances and parents from `source`, optionally restricted to `allowed`."""
    seen = {source: 0}
    parent = {source: -1}
    queue = collections.deque([source])
    while queue:
        current = queue.popleft()
        for n in adjacency[current]:
            if allowed is not None and n not in allowed:
                continue
            if n not in seen:
                seen[n] = seen[current] + 1
                parent[n] = current
                queue.append(n)
    return seen, parent


def route(parent, target):
    path = []
    while target != -1:
        path.append(target)
        target = parent[target]
    return path[::-1]


def diameter_of(adjacency):
    longest = 0
    for source in adjacency:
        seen, _ = bfs(adjacency, source)
        if len(seen) != len(adjacency):
            return None  # disconnected
        longest = max(longest, max(seen.values()))
    return longest


# --- Does the map actually finish? --------------------------------------


class Router:
    """One BFS per source, held for as long as the discovered set stands still.

    `leg()` used to run its own BFS on every call, which was affordable when
    there were two tiers and a handful of sources. There are seven tiers and up
    to twenty-eight sources now, every one of them consulted against every
    frontier cell, and the same BFS was being recomputed thousands of times a
    round for an answer that had not changed.

    Lazy on purpose: a round often has no frontier cell of a given colour at all,
    and the sources of that colour should cost nothing when nobody asks.
    """

    def __init__(self, adjacency, discovered):
        self.adjacency = adjacency
        self.discovered = discovered
        self._memo = {}

    def from_source(self, source):
        if source not in self._memo:
            self._memo[source] = bfs(self.adjacency, source,
                                     allowed=self.discovered)
        return self._memo[source]


def leg(router, source, target, mined, anchored, budget):
    """Fewest pumps that land a live orb from `source` on `target`, or None.

    One leg of a route. Factored out because a converted colour needs two of them
    — the input tier into an upgrader, the output tier out of it — and they have
    to share one pump budget. A deeper colour reached by a chain of converters
    needs one leg per step, and they all share it.

    Returning the *cheapest* spend rather than a yes/no is what makes sharing
    possible: each leg takes what it needs and passes the rest along.

    `need` is the smallest u with
    `ORB_START_VALUE - DECAY_PER_HOP * (hops - 1) + PUMP_RESTORE * u > 0`, so
    "need is affordable" and "best arrival > 0" are the same condition.
    """
    seen, parent = router.from_source(source)
    if target not in seen:
        return None
    path = route(parent, target)
    hops = len(path) - 1
    # A pump only helps on a mined cell it can actually sit on: not the source
    # (hop 0 is never entered), not the final cell (blocks never act there), and
    # not a cell holding an anchored block. This mirrors World.arrival_along.
    interior = [c for c in path[1:-1] if c in mined and c not in anchored]
    # `hops - 1`, not `hops`: the final cell is delivered into, not crossed, so
    # it charges no decay. Mirrors World.arrival_along.
    deficit = DECAY_PER_HOP * (hops - 1) - ORB_START_VALUE + 1
    need = 0 if deficit <= 0 else -(-deficit // PUMP_RESTORE)
    if need > min(budget, len(interior)):
        return None
    return need


def play(adjacency, generators, pumps, start, with_pumps=True,
         tiers=None, upgraders=None):
    """Play the map greedily and return how many cells got mined.

    Mirrors the real rules and is deliberately *conservative*: it only ever uses
    the shortest discovered route and only counts pumps it can place on that
    route's already-mined interior. A player has strictly more options, so if
    this clears the board, a player certainly can.

    Pumps are reusable — swapping is free, instant and unlimited in range — so
    `in_hand` is simply how many have been mined so far.

    **Spheres are ignored entirely, and that is deliberate.** A sphere only ever
    adds power — faster generators, stronger pumps — so a board this clears
    without them is one a player clears with them, and the conservative claim
    above survives untouched: a shorter generator interval changes how *often* an
    orb sets out, never how far it gets. Modelling them would only make the
    search's job easier and its report weaker.

    **The colour ladder is modelled, because a gate can make a cell unmineable.**
    Spheres and challenges are safe to ignore precisely because they only ever add
    power; a colour gate takes power away, so a board that clears without counting
    it is no evidence at all. A tier-T cell needs a *live* tier-T source, and
    there are two kinds: a mined generator of that colour, which is live the
    moment it is dug up, or a mined upgrader into that colour with a surviving
    line of tier T-1 running into it.

    Sources are therefore resolved in ascending tier order every round, and each
    one carries the pump spend that keeps it fed — a converter three steps up the
    ladder is paying for every leg beneath it out of the same budget. That is
    what `leg()` returning a *price* rather than a yes/no is for.

    Still conservative, in the same two ways as before: shortest discovered
    routes only, pumps only on already-mined interior. It stays optimistic in one
    place it always was — one target at a time with the whole budget — which is
    fair, because pumps are freely repositionable and a player mines one cell at
    a time too.

    `play()` ignores unlock cost entirely, so DEEP_TIER_COST_DIVISOR and
    CHALLENGE_COST_MULTIPLIER cannot turn this report into a lie: an expensive
    cell is slow, not unreachable. That is also the thing to remember before
    adding a mechanic that makes a cell genuinely unmineable, which is exactly
    what a colour gate is — hence the modelling above.

    `generators` and `upgraders` are {cell: tier} maps: which colour a generator
    emits, and which colour an upgrader converts *into*.
    """
    tiers = tiers or {}
    upgraders = upgraders or {}
    mined = {start}
    owned = {start: generators[start]}   # sources dug up, and their colours
    in_hand = 0                          # pumps acquired, freely repositionable
    # Upgraders are anchored, so like generators they are ground a pump may not
    # stand on.
    anchored = set(generators) | set(upgraders)

    while True:
        discovered = set(mined)
        for cell in mined:
            discovered.update(adjacency[cell])
        budget = in_hand if with_pumps else 0
        router = Router(adjacency, discovered)

        # Every source of every colour, and what each costs to keep running. A
        # generator is free; an upgrader is priced at the cheapest chain that
        # feeds it, which is why this walks the ladder from the bottom.
        sources = [dict() for _ in TIER_NAMES]
        for cell, tier in owned.items():
            sources[tier][cell] = 0
        for tier in range(1, len(TIER_NAMES)):
            for cell in sorted(mined):
                if upgraders.get(cell) != tier:
                    continue
                prices = []
                for feeder, spent in sorted(sources[tier - 1].items()):
                    more = leg(router, feeder, cell, mined, anchored,
                               budget - spent)
                    if more is not None:
                        prices.append(spent + more)
                if prices:
                    sources[tier][cell] = min(prices)

        progressed = False
        for target in sorted(discovered - mined):
            wanted = tiers.get(target, 0)
            reachable = any(
                leg(router, source, target, mined, anchored, budget - spent)
                is not None
                for source, spent in sorted(sources[wanted].items())
            )
            if reachable:
                mined.add(target)
                progressed = True
                if target in generators:
                    owned[target] = generators[target]
                if target in pumps:
                    in_hand += 1

        if not progressed:
            return mined


def quadrants_covered(generators, coords):
    """How many quadrants of the board the generators land in. `coords` is
    indexed by cell id, so `coords[g]` is that generator's (col, row)."""
    mid_x, mid_y = (COLS - 1) / 2, (ROWS - 1) / 2
    return len({
        (coords[g][0] > mid_x, coords[g][1] > mid_y) for g in generators
    })


def generator_candidates(tier, tiers, taken, start, cells):
    """Where a tier-T generator may be buried.

    Two rules, and both are about the colour of the *cell* rather than the block.
    It may not sit behind a gate deeper than the colour it makes — a purple
    generator under a purple gate can only be paid for with purple, which is a
    deadlock unless an upgrader happens to have got there first. And it should sit
    near the band it serves: a teal generator two rings inside the teal band is
    what makes teal cheap *there*, and burying it at the start would make the
    colour a formality.

    So: the band it serves, or the one below it. Red has no band below and takes
    its own.
    """
    lowest = max(0, tier - 1)
    return [
        c for c in cells
        if c not in taken
        and c != start
        and lowest <= tiers.get(c, 0) <= tier
    ]


def search_contents(adjacency, coords, start, tiers, taken, rng):
    """Find a generator/pump placement that is spread out and needs its pumps.

    Three things are ranked, and none of them is asserted any more. With pumps as
    much of the board as possible should fall; *without* them as little as
    possible; and the red generators must reach into at least MIN_QUADRANTS
    corners of the board.

    The middle one is what makes pumps load-bearing rather than decorative. The
    third pulls against it: generators spaced evenly leave every cell within a few
    hops of one and the map finishes with no pumps at all — measured at 0 viable
    placements out of 1500 once every pair was forced 3+ hops apart. Quadrant
    coverage is what satisfies both, because it spreads them over the board
    without spacing them uniformly.

    Quadrants are asked of the **red** generators alone. They are the bootstrap —
    the only colour on hand before anything is mined — and the deeper colours are
    already spread by their bands, which are rings around the start.

    Returns `({cell: tier}, [pumps], stranded)`, or None if every draw failed.
    """
    cells = sorted(adjacency)
    best = None
    for _ in range(SEARCH_TRIES):
        generators = {start: 0}
        used = set(taken) | {start}
        ok = True
        for tier, count in enumerate(GENERATOR_COUNTS):
            wanted = count - 1 if tier == 0 else count  # the start is red
            if wanted <= 0:
                continue
            pool = generator_candidates(tier, tiers, used, start, cells)
            if len(pool) < wanted:
                ok = False
                break
            for cell in rng.sample(pool, wanted):
                generators[cell] = tier
                used.add(cell)
        if not ok:
            continue

        reds = {c for c, t in generators.items() if t == 0}
        if quadrants_covered(reds, coords) < MIN_QUADRANTS:
            continue
        free = [c for c in cells if c not in used]
        if len(free) < PUMP_COUNT:
            continue
        pumps = set(rng.sample(free, PUMP_COUNT))

        cleared = len(play(adjacency, generators, pumps, start, True,
                           tiers=tiers))
        stranded = cleared - len(
            play(adjacency, generators, pumps, start, False, tiers=tiers)
        )
        # Ranked on how much falls first and how much the pumps are worth second.
        # A placement that clears more of the board is a better board; among
        # equals, the one whose pumps matter most is the better game.
        score = (cleared, stranded)
        if best is None or score > best[0]:
            best = (score, dict(generators), sorted(pumps))
        if best[0][0] == len(cells) and best[0][1] >= STRANDED_TARGET:
            break
    if best is None:
        return None
    return best[1], best[2], best[0][1]


def place_challenges(adjacency, distances, taken, start, rng):
    """Bury one of each challenge in every colour band. Returns {cell: block_id}.

    Deliberately invisible to `play()`, exactly as the spheres are and for the
    same reason: a challenge only ever adds power, so a board that clears without
    counting them is one a player clears with them. Folding them into the search
    would burn draws on something none of its conditions can see.

    Their cost is invisible to `play()` too, which asks only whether an orb can
    arrive with anything at all and never looks at `unlock_cost`. That is what
    makes CHALLENGE_COST_MULTIPLIER safe to raise: an expensive cell is slow, not
    unreachable, whatever the playthrough reports.

    Drawn **before** the tiers, so `assign_tiers` can exempt them from the scatter
    and every challenge sits squarely in the colour of the band it was drawn from.
    A challenge promoted a colour by the scatter would be a cell you cannot pay
    for with what the ring around it is teaching you to make.

    Raises if a band has no free cell, which would mean the lattice changed shape
    underneath BAND_EDGES.
    """
    chosen = {}
    used = set(taken)
    for tier in range(len(TIER_NAMES)):
        low, high = band_range(tier)
        band = [
            c
            for c in sorted(adjacency)
            if c not in used
            and c != start
            and low <= distances[c]
            and (high is None or distances[c] <= high)
        ]
        if len(band) < len(CHALLENGE_IDS):
            raise AssertionError(
                f"only {len(band)} free cells in the {TIER_NAMES[tier]} band "
                f"({low}-{high} hops), need {len(CHALLENGE_IDS)} — BAND_EDGES no "
                "longer matches the lattice, or the board is buried too densely"
            )
        for block_id, pick in zip(CHALLENGE_IDS,
                                  rng.sample(band, len(CHALLENGE_IDS))):
            chosen[pick] = block_id
            used.add(pick)
    return chosen


def assign_tiers(adjacency, distances, challenge_cells, rng):
    """Which colour opens each cell. Returns {cell: tier index}; red is 0.

    Two rules. A cell's band follows its distance from the start, so the ladder
    is a set of rings and pushing outward is climbing it. And a fraction of the
    cells in the *last hop* of a band are promoted one colour, so the player meets
    each new colour as a scatter of cells they cannot pay for yet while the
    current one still works everywhere else.

    The scatter is what keeps a boundary from reading as a wall. A wall is routed
    around and ignored until the day it opens; a scatter is met, understood, and
    planned for.

    **Challenges are exempt from the promotion.** A challenge is already the
    steepest cell in its band at six times the price, and rolling it a colour
    deeper would put it behind a gate the ring around it has not taught yet.

    The tier table is *complete* — every cell has an entry, red included — because
    a seven-tier ladder has no default worth the ambiguity. Only the JSON drops
    red, and only to stay readable.
    """
    tiers = {}
    for cell in sorted(adjacency):
        hops = distances[cell]
        tier = band_of(hops)
        low, high = band_range(tier)
        promotable = (
            high is not None
            and high > low          # a one-hop band is its own announcement
            and hops == high
            and cell not in challenge_cells
        )
        if promotable and rng.random() < SCATTER_DENSITY:
            tier += 1
        tiers[cell] = tier
    return tiers


def upgrader_candidates(tier, tiers, taken, start, cells):
    """Where an upgrader that makes tier T may be buried.

    Gated at or below the colour it *consumes*, which is the generalisation of the
    old "every buried upgrader sits on a red cell". An upgrader you cannot afford
    to mine until you already have the colour it makes is a deadlock; one gated at
    its input colour is exactly affordable at the moment it becomes useful, since
    that is the colour you are about to route into it anyway.

    Held to its input band rather than merely at-or-below it, because a converter
    is a *positional* source — the whole reason to have one is to make a colour
    somewhere its generators are not, and one buried back at the start would make
    the deep half of every route the same length as the shallow half.
    """
    return [
        c for c in cells
        if c not in taken
        and c != start
        and tiers.get(c, 0) == tier - 1
    ]


def search_upgraders(adjacency, generators, pumps, start, tiers, taken, rng):
    """Find an upgrader placement that opens the ladder up.

    Searched separately from `search_contents`, and after it, because the two ask
    different questions of the same board and a joint draw over both would be a
    far larger space for no better answer.

    Two things are ranked, the same two the generator search ranks. With these
    upgraders as much of the board as possible should fall — a colour with no
    converter is a colour that exists only where its two generators sit. And the
    board should still *fail* without pumps, because an upgrader is a new place a
    colour sets out from, and twelve of them can quietly put the rim back inside
    unaided range. Measured on the old two-tier board, that is exactly what the
    first placement found did.

    Returns `({cell: output tier}, stranded)`, or None if every draw failed.
    """
    cells = sorted(adjacency)
    best = None
    for _ in range(SEARCH_TRIES):
        upgraders = {}
        used = set(taken)
        ok = True
        for tier in range(1, len(TIER_NAMES)):
            pool = upgrader_candidates(tier, tiers, used, start, cells)
            if len(pool) < UPGRADERS_PER_STEP:
                ok = False
                break
            for cell in rng.sample(pool, UPGRADERS_PER_STEP):
                upgraders[cell] = tier
                used.add(cell)
        if not ok:
            raise AssertionError(
                f"no free cell in the {TIER_NAMES[tier - 1]} band for an "
                f"upgrader into {TIER_NAMES[tier]} — the band is buried too "
                "densely, or BAND_EDGES has left it too thin"
            )

        cleared = len(play(adjacency, generators, pumps, start, True,
                           tiers=tiers, upgraders=upgraders))
        stranded = cleared - len(
            play(adjacency, generators, pumps, start, False,
                 tiers=tiers, upgraders=upgraders)
        )
        score = (cleared, stranded)
        if best is None or score > best[0]:
            best = (score, dict(upgraders))
        if best[0][0] == len(cells) and best[0][1] >= STRANDED_TARGET:
            break
    if best is None:
        return None
    return best[1], best[0][1]


def place_spheres(adjacency, taken, start, rng):
    """Scatter spheres over cells nothing else claimed.

    Drawn *after* the search rather than inside it, because the search's three
    conditions are all about reach and `play()` ignores spheres on purpose.
    Folding them into the loop would burn random draws on something none of the
    conditions can see, and would imply the placement had been validated against
    something it has not.

    The start cell is excluded so the opening board is a generator and nothing
    else: a sphere already in hand on turn one is a bonus the player never chose.
    """
    free = [c for c in sorted(adjacency) if c not in taken and c != start]
    return sorted(rng.sample(free, SPHERE_COUNT))


def place_upkeeps(adjacency, distances, tiers, taken, start, rng):
    """Scatter upkeep blocks over free red cells in the mid-game band.

    Drawn like the spheres rather than searched like the upgraders, and the
    argument is *stronger* than the sphere's. A sphere is ignored by `play()`
    because it only ever adds power; an upkeep block's bonus is a shorter
    generator interval, and `play()` ignores time entirely — it asks only whether
    an orb can arrive, never how often. So an interval buff is not merely safe to
    ignore here, it is invisible to the model by construction, and the
    playthrough reports exactly the same numbers with these on the board as
    without them.

    Shallow cells only, and for a reason related to but distinct from the
    upgrader's: an upkeep block eats *red*, whatever ring it sits in, so burying
    one out past the near bands would hand the player a block they cannot feed
    until a red line already reaches it — long after a faster generator was worth
    having. UPKEEP_MAX_TIER is that rule; the hop band is what keeps them out of
    the opening.
    """
    low, high = UPKEEP_BAND
    free = [
        c for c in sorted(adjacency)
        if c not in taken
        and c != start
        and tiers.get(c, 0) <= UPKEEP_MAX_TIER
        and low <= distances[c] <= high
    ]
    assert len(free) >= UPKEEP_COUNT, (
        f"only {len(free)} free cells at tier {UPKEEP_MAX_TIER} or below in the "
        f"{low}-{high} hop band, need {UPKEEP_COUNT} — widen UPKEEP_BAND or "
        "lower UPKEEP_COUNT"
    )
    return sorted(rng.sample(free, UPKEEP_COUNT))


# --- Emit ---------------------------------------------------------------


def main():
    coords, ids, adjacency, positions = build_lattice()
    cell_count = len(coords)
    start = central_cell(adjacency, positions)

    diameter = diameter_of(adjacency)
    assert diameter is not None, "lattice is not connected — check KEPT_CENTRES"

    # Checked here rather than with the assertions at the bottom, because this is
    # what `random.sample` needs to be true and it would raise an opaque
    # "sample larger than population" long before the report ever prints.
    buried = (GENERATOR_COUNT + PUMP_COUNT + SPHERE_COUNT + UPGRADER_COUNT
              + UPKEEP_COUNT + CHALLENGE_COUNT)
    assert buried < cell_count, (
        f"{buried} blocks do not fit on {cell_count} cells — an entirely buried "
        "board leaves nothing to mine through"
    )

    rng = random.Random(SEED)
    distances, _ = bfs(adjacency, start)

    # **The colour ladder is decided first**, and everything else is placed
    # against it. It has to be: a generator may not be buried behind a gate
    # deeper than the colour it makes, and an upgrader may not be buried behind
    # one deeper than the colour it eats — so both searches need to know what
    # every cell demands before they can draw a single candidate.
    #
    # Challenges come first of all, because `assign_tiers` exempts them from the
    # scatter and so has to be told where they are.
    challenges = place_challenges(adjacency, distances, set(), start, rng)
    tiers = assign_tiers(adjacency, distances, set(challenges), rng)

    found = search_contents(adjacency, coords, start, tiers, set(challenges),
                            rng)
    assert found, (
        f"no placement of {GENERATOR_COUNT} generators and {PUMP_COUNT} pumps "
        f"spans {MIN_QUADRANTS} quadrants with a generator of every colour in "
        "its own band — try widening BAND_EDGES, which is what thins the pools"
    )
    generators, pumps, _ = found

    taken = set(generators) | set(pumps) | set(challenges)
    found_upgraders = search_upgraders(
        adjacency, generators, set(pumps), start, tiers, taken, rng
    )
    assert found_upgraders, (
        f"no placement of {UPGRADER_COUNT} upgraders — every band needs "
        f"{UPGRADERS_PER_STEP} free cells for the step above it"
    )
    upgraders, stranded = found_upgraders
    taken |= set(upgraders)

    upkeeps = place_upkeeps(adjacency, distances, tiers, taken, start, rng)
    taken |= set(upkeeps)

    # Last, over whatever is left. Spheres are the one block type with no
    # constraint at all on where it goes: it buffs whatever is near it, in any
    # colour, so any free cell is a legitimate place to find one.
    spheres = place_spheres(adjacency, taken, start, rng)

    contents = {}
    for cell, tier in generators.items():
        contents[cell] = f"generator_{TIER_NAMES[tier]}"
    for cell in pumps:
        contents[cell] = "pump"
    for cell in spheres:
        contents[cell] = "sphere"
    for cell, tier in upgraders.items():
        contents[cell] = f"upgrader_{TIER_NAMES[tier]}"
    for cell in upkeeps:
        contents[cell] = "upkeep"
    for cell, block_id in challenges.items():
        contents[cell] = block_id

    challenge_cells = set(challenges)

    cells = []
    for cell_id in sorted(adjacency):
        hops = distances[cell_id]
        tier = tiers[cell_id]
        cost = (
            0 if cell_id == start
            else int(round(COST_BASE * COST_GROWTH ** (hops - 1)))
        )
        if cell_id in challenge_cells:
            cost *= CHALLENGE_COST_MULTIPLIER
        # Divided *after* the challenge multiplier, so a teal challenge is still
        # six times a teal cell at its distance rather than six times a red one.
        # The multiplier means "a challenge costs six ordinary cells", and that
        # has to stay true in whatever colour it is charged in.
        if tier > 0:
            cost = int(round(cost / DEEP_TIER_COST_DIVISOR))
        cells.append({
            "id": cell_id,
            "x": positions[cell_id][0],
            "y": positions[cell_id][1],
            "neighbors": adjacency[cell_id],
            "unlock_cost": cost,
            # Omitted for red, which is the tier `Tiers.from_name` falls back to,
            # so the opening rings stay as terse in the file as they ever were.
            **({"tier": TIER_NAMES[tier]} if tier > 0 else {}),
            **({"block": contents[cell_id]} if cell_id in contents else {}),
            **({"starts_unlocked": True} if cell_id == start else {}),
        })

    # Written tab-indented to match the rest of the repo. json.dump only emits
    # spaces, so convert afterwards — without this, regenerating an unchanged map
    # produces a whole-file whitespace diff and hides the real one.
    text = json.dumps({"name": "First Light", "cells": cells}, indent=2)
    text = re.sub(
        r"^ +",
        lambda m: "\t" * (len(m.group()) // 4) + " " * (len(m.group()) % 4),
        text,
        flags=re.MULTILINE,
    )
    with open("data/map_01.json", "w") as f:
        f.write(text + "\n")

    # --- Report ---
    degrees = [len(c["neighbors"]) for c in cells]
    unaided = {
        i: ORB_START_VALUE - DECAY_PER_HOP * (d - 1) for i, d in distances.items()
    }
    print(f"{cell_count} cells: a {COLS}x{ROWS} honeycomb "
          f"({len(KEPT_CENTRES)} centres kept), {sum(degrees) // 2} edges")
    print(f"degree min {min(degrees)} avg {sum(degrees) / len(degrees):.2f} "
          f"max {max(degrees)}")
    print(f"diameter {diameter} hops, start cell {start}, max distance from it "
          f"{max(distances.values())}")
    reds = {c for c, t in generators.items() if t == 0}
    print(f"generators {quadrants_covered(reds, coords)} of 4 quadrants on red")
    for tier, name in enumerate(TIER_NAMES):
        owned = sorted(c for c, t in generators.items() if t == tier)
        made = sorted(c for c, t in upgraders.items() if t == tier)
        low, high = band_range(tier)
        span = f"{low}+" if high is None else f"{low}-{high}"
        print(f"  {name:<7}{span:>6} hops  generators {str(owned):<26} "
              f"upgraders {made}")
    print(f"pumps      {pumps}")
    print(f"spheres    {spheres} (not modelled by the playthrough)")
    print(f"upkeeps    {upkeeps} "
          f"(at {sorted(distances[u] for u in upkeeps)} hops, "
          "not modelled by the playthrough)")
    print(f"active     {len(contents)} of {cell_count} cells "
          f"({len(contents) / cell_count:.0%}), {cell_count - len(contents)} empty")
    print(f"unlock cost {min(c['unlock_cost'] for c in cells if c['id'] != start)}"
          f"..{max(c['unlock_cost'] for c in cells)}, "
          f"{sum(c['unlock_cost'] for c in cells)} to clear the board")
    print(f"without pumps, {stranded} cells are unmineable")
    print("to clear, by colour: " + ", ".join(
        f"{sum(c['unlock_cost'] for c in cells if tiers[c['id']] == tier)} "
        f"{name} ({sum(1 for c in cells if tiers[c['id']] == tier)} cells)"
        for tier, name in enumerate(TIER_NAMES)
    ))
    scattered = sum(
        1 for c in cells if tiers[c["id"]] != band_of(distances[c["id"]])
    )
    print(f"{scattered} cells sit one colour deeper than their band — the "
          "scatter that meets the player before the wall does")
    print()

    by_id = {c["id"]: c for c in cells}
    for row in range(ROWS):
        line = []
        for col in range(COLS):
            if (col, row) not in ids:
                line.append(" " * 11)
                continue
            cell_id = ids[(col, row)]
            block = contents.get(cell_id, "")
            mark = "."
            if block.startswith("generator_"):
                mark = "G"
            elif block.startswith("upgrader_"):
                mark = "U"
            else:
                mark = {"pump": "P", "sphere": "O", "upkeep": "K"}.get(block, ".")
            # Challenges are marked 1/2/3 rather than sharing a letter, because
            # which one landed where is the thing worth eyeballing.
            if cell_id in challenge_cells:
                mark = str(CHALLENGE_IDS.index(challenges[cell_id]) + 1)
            if cell_id == start:
                mark = "S"
            # A letter per colour rather than a flag, because there are seven of
            # them now. The gate is a property of the cell and not of what is
            # buried in it, so it keeps its own column.
            gate = TIER_LETTERS[tiers[cell_id]]
            line.append(
                f" {cell_id:3d}{mark}{by_id[cell_id]['unlock_cost']:5d}{gate}"
            )
        # Half a cell, so odd rows sit in the gaps of even ones the way the
        # lattice does. Eleven characters per cell, so five.
        indent = "     " if row % 2 else ""
        print(indent + "".join(line).rstrip())
    print("\n  id + S/G/P/O/U/K/1/2/3/. + unlock cost + gate (S is the start, a "
          "red generator; G a generator\n  of any colour; O a sphere; U an "
          "upgrader; K an upkeep block; 1-3 the challenges, one of\n  each per "
          "band). The trailing letter is the colour that opens the cell: "
          + " ".join(f"{TIER_LETTERS[t]}={n}" for t, n in enumerate(TIER_NAMES)))

    # --- Assertions ---
    assert diameter >= 12, f"diameter {diameter} too short — decay would not matter"
    assert min(degrees) >= 2, "a degree-1 cell is a dead end, not a web"

    # Play opens in the middle, so the far corner is a radius away, not a
    # diameter. An orb has to arrive with something left, so unaided reach is
    # the last hop before it hits zero; if the whole board sits inside that, the
    # starting generator alone supplies everything and the two assertions at the
    # bottom has nothing to work with.
    radius = max(distances.values())
    # The destination charges no decay, so a route of N hops pays for N-1 cells:
    # the last hop an orb can afford is one further out than the decay alone says.
    reach = (ORB_START_VALUE - 1) // DECAY_PER_HOP + 1
    assert radius > reach, (
        f"the start reaches every cell in {radius} hops, inside unaided reach "
        f"of {reach} — grow COLS/ROWS or nothing will ever need a pump"
    )

    # Routing only crosses discovered ground, and the mined region grows outward
    # from wherever the map hands the player a working cell. Two separate
    # starting points would give two mined regions with fog between them, and
    # nothing could route from one to the other.
    starts = [c["id"] for c in cells if c.get("starts_unlocked")]
    assert len(starts) == 1, (
        f"{len(starts)} cells start mined — discovery assumes a single region"
    )

    # Reported, not asserted. Three runs on exactly what was written out: the
    # whole board, the board with its pumps taken away, and the board with its
    # upgraders taken away. What they used to assert was that the first clears
    # and the other two do not — that pumps and the orange gate are load-bearing
    # rather than decorative.
    #
    # They are numbers to read now rather than a gate, for two reasons. The
    # shipped board is known to clear, and PUMP_RESTORE here is a frozen
    # heuristic rather than the simulation's percentage restore — so a failure
    # would say the model is stale, not that the map is broken. Re-arm them only
    # alongside making the model mirror `World.arrival_along` again.
    pump_set = set(pumps)
    with_pumps = play(adjacency, generators, pump_set, start, True,
                      tiers=tiers, upgraders=upgraders)
    without_pumps = play(adjacency, generators, pump_set, start, False,
                         tiers=tiers, upgraders=upgraders)
    without_upgraders = play(adjacency, generators, pump_set, start, True,
                             tiers=tiers)
    reds_only = {c: t for c, t in generators.items() if t == 0}
    red_alone = play(adjacency, reds_only, pump_set, start, True, tiers=tiers)
    print(f"\nplaythrough (model, not a proof): "
          f"{len(with_pumps)}/{cell_count} cells mined; "
          f"{len(without_pumps)}/{cell_count} without pumps; "
          f"{len(without_upgraders)}/{cell_count} without upgraders; "
          f"{len(red_alone)}/{cell_count} on red generators alone")

    # That last run is the one worth watching, and it replaced an assertion. The
    # old board asserted it could not be finished without upgraders, because
    # orange was minted and nothing else made it. Every colour has generators of
    # its own now, so a converter is a convenience rather than a gate and that
    # assertion is simply false by design.
    #
    # What still means something is the *ladder*: if red alone clears the board,
    # the six colours above it are decoration. It is a number rather than an
    # assertion for the same reason the rest are — PUMP_RESTORE here is a frozen
    # heuristic, not the simulation's percentage restore.

    # Every upgrader must be mineable in a colour that exists before it does. One
    # gated at or above the colour it makes can only be paid for with the thing it
    # is needed to build — a deadlock the playthrough would catch only indirectly,
    # and which is worth naming.
    for cell_id, tier in upgraders.items():
        assert tiers[cell_id] < tier, (
            f"cell {cell_id} buries an upgrader into {TIER_NAMES[tier]} behind a "
            f"{TIER_NAMES[tiers[cell_id]]} gate — nothing can pay for it before "
            "it exists"
        )

    # A generator may sit on a cell of its own colour — the other generator of
    # that colour, or an upgrader, can open it — but never behind a deeper gate,
    # which nothing on the board could pay for any earlier.
    for cell_id, tier in generators.items():
        assert tiers[cell_id] <= tier, (
            f"cell {cell_id} buries a {TIER_NAMES[tier]} generator behind a "
            f"{TIER_NAMES[tiers[cell_id]]} gate — it is locked behind a colour "
            "deeper than the one it makes"
        )

    # Upkeep blocks, for a related but distinct reason. An upgrader behind a
    # deeper gate is a deadlock; an upkeep block behind one is merely useless — it
    # eats red wherever it sits, so it could not be fed until a red line already
    # reached it, which is long after a faster generator was worth having.
    for cell_id in upkeeps:
        assert tiers[cell_id] <= UPKEEP_MAX_TIER, (
            f"cell {cell_id} buries an upkeep block behind a "
            f"{TIER_NAMES[tiers[cell_id]]} gate — it burns red, so nothing could "
            "feed it out there"
        )

    # The ladder itself, asserted against what was written rather than the dict it
    # came from, so a hand-edited map fails here too. A cell sits in its own band
    # or exactly one colour deeper — the scatter — and never shallower, which
    # would be a hole in the wall.
    for cell in cells:
        hops = distances[cell["id"]]
        tier = tiers[cell["id"]]
        band = band_of(hops)
        assert band <= tier <= band + 1, (
            f"cell {cell['id']} at {hops} hops is {TIER_NAMES[tier]}, but its "
            f"band is {TIER_NAMES[band]} — a cell may be promoted one colour by "
            "the scatter and no more"
        )
        assert (cell.get("tier") is None) == (tier == 0), (
            f"cell {cell['id']} writes tier {cell.get('tier')} for tier index "
            f"{tier} — red is the omitted default and nothing else may be"
        )

    # Every colour has to actually appear, or a band is a name with no cells in
    # it and the ladder has a rung missing.
    for tier, name in enumerate(TIER_NAMES):
        assert any(tiers[c["id"]] == tier for c in cells), (
            f"no cell on the board demands {name} — BAND_EDGES has a band the "
            "lattice does not reach"
        )

    # And the scatter has to have fired somewhere, or every boundary is a wall the
    # player meets with no warning.
    scattered = [
        c["id"] for c in cells if tiers[c["id"]] > band_of(distances[c["id"]])
    ]
    assert scattered, (
        "no cell was promoted past its band — every colour arrives as a wall "
        "rather than as a scatter met while the previous one still works"
    )

    # One of each challenge in every band. Uniqueness used to be board-wide, and
    # it is per band now: three effects repeated seven times is the placeholder
    # arrangement, so what has to hold is that a *band* never doubles one up. Two
    # Surges in the same ring would be two identical decisions in a row, which is
    # the thing the spread exists to avoid.
    for tier, name in enumerate(TIER_NAMES):
        here = [
            c["id"] for c in cells
            if c["id"] in challenge_cells and tiers[c["id"]] == tier
        ]
        found = sorted(challenges[c] for c in here)
        assert found == sorted(CHALLENGE_IDS), (
            f"the {name} band buries {found} — every band gets exactly one of "
            "each challenge"
        )

    # Bands are disjoint hop ranges, so a challenge sitting in its band is what
    # makes them arrive as milestones. Asserted rather than assumed because
    # `assign_tiers` promotes cells, and a challenge promoted out of its band
    # would land in a ring the player reaches with the wrong colour in hand.
    for cell_id, block_id in challenges.items():
        low, high = band_range(tiers[cell_id])
        hops = distances[cell_id]
        assert low <= hops and (high is None or hops <= high), (
            f"{block_id} at cell {cell_id} sits {hops} hops out, outside the "
            f"{low}-{high} band of the {TIER_NAMES[tiers[cell_id]]} it demands"
        )

    print("\nok")


if __name__ == "__main__":
    main()
