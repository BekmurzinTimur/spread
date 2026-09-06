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
map buries them, so whether the map can be finished at all is a sequencing
question — can you bootstrap your way out to the next buried generator? — and no
static property answers it. `play()` below answers it by playing the map.

Roughly half the cells bury something, and unlock cost is *geometric* in distance
from the start rather than linear. The two go together: a denser board hands the
player compounding power — pumps stack flat bonuses, spheres stack onto whatever
is near them — so a cost curve that only adds a constant per hop falls behind it,
and the far side of the map ends up cheaper in real terms than the near side. See
GENERATOR_COUNT and COST_GROWTH below for the numbers and what constrains them.

Prints a distance/arrival table and asserts the properties the game depends on.
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
PUMP_RESTORE = 3
UPGRADE_COST = 60

COLS, ROWS = 13, 13

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
# The split is deliberately lopsided, and the reason is the pump assertion at the
# bottom. Generators are the anchored sources, so every one added shrinks the
# region no generator can already reach unaided, and the map gets closer to being
# finishable with no pumps at all. Measured over 500 random placements: at 5
# generators 14.6% of them strand at least one cell without pumps and the best
# strands 4; at 10 it is 1.2% and the best strands 2. Past that the search runs
# out of board. **So density comes from pumps and spheres**, which are movable and
# therefore what the player actually rearranges — raising GENERATOR_COUNT again
# means spending what little slack this assertion has left.
GENERATOR_COUNT = 10
PUMP_COUNT = 20

# Spheres speed up generators and strengthen pumps within a couple of hops.
# Placed but deliberately *not* modelled by `play()` below — see the note there.
# The challenges below are left out of it for the same reason.
SPHERE_COUNT = 15

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
# A floor to stop at, not a guarantee — the assertion at the bottom only demands
# one stranded cell. Its ceiling is set by GENERATOR_COUNT, and it was 4 back when
# there were five generators. Ten generators cannot reach it: the best over 500
# random placements strands 2. Left at 4 the early exit never fires, the search
# grinds all SEARCH_TRIES candidates, and generating the map takes minutes instead
# of a fraction of a second. Raise it only alongside a cut to GENERATOR_COUNT.
STRANDED_TARGET = 2
SEARCH_TRIES = 20000

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
COST_BASE = 50
COST_GROWTH = 2.0

# The three challenges, nearest the start first. Each is buried exactly once, and
# the assertions at the bottom pin both facts: one of each, at strictly
# increasing distance from the start.
#
# The order is the whole design. A challenge is a detour — you stop pushing the
# frontier and pay six times a normal cell for something whose payout you cannot
# see — so the first one has to be affordable early enough that a player learns
# what a triangle means while the board is still cheap. By the time the Lens is
# reachable, the +50% radius it grants is worth the several thousand it costs.
CHALLENGE_IDS = ("challenge_surge", "challenge_current", "challenge_lens")

# The hop bands each challenge is drawn from, matching CHALLENGE_IDS. The board's
# radius is 11, so these span it from just outside the opening ring to the rim.
# Bands rather than exact distances because the lattice does not offer a cell at
# every hop count in every direction, and a search that insists on one would fail
# on a map that is otherwise fine.
CHALLENGE_BANDS = ((3, 5), (6, 8), (9, 11))

# What a challenge costs, as a multiple of the normal cost for its distance. Six
# is about three extra hops' worth of the geometric ramp: enough that mining one
# is a decision you plan a pump chain around rather than something you clear in
# passing, and not so much that the far one is out of reach of a board that has
# already found most of its generators.
#
# Invisible to `play()`, which ignores unlock cost entirely — see the note there.
# So this number cannot make the winnability assertion a lie; it changes how long
# the board takes, not whether it can be finished.
CHALLENGE_COST_MULTIPLIER = 6

# --- The orange tier ----------------------------------------------------
#
# Red opens the middle of the board; orange opens the rim. Orange cells start
# appearing part-way out and take over completely past ORANGE_FROM, so the outer
# third of the map is shut until the player owns a working upgrader — which is
# the point of a second tier. Below the band nothing changes, so the opening is
# exactly the game it was.
#
# The band is a *mix* rather than a line. A hard boundary would read as a wall
# and be routed around until the day it opened; a scatter means the player meets
# a few cells they cannot pay for while red still works everywhere else, and
# learns what the colour means before it is the only colour that matters.
ORANGE_BAND = (5, 7)
ORANGE_BAND_DENSITY = 0.4
ORANGE_FROM = 8

# Orange is minted from red at UPGRADE_COST red per orb, so pricing orange cells
# on the same curve would make them that multiple harder in real terms. Dividing
# by four leaves a ~1.5x wall at a 6:1 conversion: enough that the rim is a step
# up rather than a formality, and not so much that the far corner needs a
# playthrough of its own.
ORANGE_COST_DIVISOR = 4

# Upgraders are anchored like generators, so where these land decides where
# orange can reach. Buried inside red's comfortable range and always on a
# red-gated cell — an upgrader you cannot afford to mine because it demands the
# colour only it can make is a deadlock, and the assertions at the bottom pin
# that it never happens.
UPGRADER_COUNT = 5
UPGRADER_BAND = (2, 5)

# The upgrader search's early-exit floor, and it is 1 rather than
# STRANDED_TARGET's 2 on purpose. Five upgraders are five new places orange sets
# out from, so they push *against* stranding — the generator placement is what
# establishes that pumps are load-bearing, and all the upgraders have to do is
# not undo it. Asking for 2 here would leave the search grinding all
# SEARCH_TRIES for a property the assertion never needed, which is the same trap
# STRANDED_TARGET documents one constant up.
UPGRADER_STRANDED_TARGET = 1


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


def leg(adjacency, source, target, discovered, mined, anchored, budget):
    """Fewest pumps that land a live orb from `source` on `target`, or None.

    One leg of a route. Factored out because orange needs two of them — red into
    an upgrader, orange out of it — and they have to share one pump budget. The
    old inline version spent the whole budget on a single leg, which is fine when
    there is only ever one and a lie the moment there are two.

    Returning the *cheapest* spend rather than a yes/no is what makes sharing
    possible: the red leg takes what it needs and the orange leg gets the rest.

    Equivalent to the arrival test it replaces. `need` is the smallest u with
    `ORB_START_VALUE - DECAY_PER_HOP * (hops - 1) + PUMP_RESTORE * u > 0`, so
    "need is affordable" and "best arrival > 0" are the same condition, and a
    board with no orange plays exactly as it did before.
    """
    seen, parent = bfs(adjacency, source, allowed=discovered)
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
         tiers=None, upgraders=frozenset()):
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
    above survives untouched. Both assertions at the bottom survive too: the
    no-pump run has no pumps for a sphere to strengthen, and a shorter generator
    interval changes how *often* an orb sets out, never how far it gets. Modelling
    them would only make the search's job easier and its guarantee weaker.

    **Orange is modelled, because it can make a cell unmineable.** Spheres and
    challenges are safe to ignore precisely because they only ever add power; a
    colour gate takes power away, so a board that clears without counting it is
    no evidence at all. An orange cell needs a *live* upgrader — one that is
    mined and that some owned generator can actually land red on — and then a
    surviving orange route out of it, both paid for from the same pump budget.

    Still conservative, in the same two ways as before: shortest discovered
    routes only, pumps only on already-mined interior. It stays optimistic in one
    place it always was — one target at a time with the whole budget — which is
    fair, because pumps are freely repositionable and a player mines one cell at
    a time too.

    `play()` ignores unlock cost entirely, so ORANGE_COST_DIVISOR and
    CHALLENGE_COST_MULTIPLIER cannot turn this assertion into a lie: an expensive
    cell is slow, not unreachable. That is also the thing to remember before
    adding a mechanic that makes a cell genuinely unmineable, which is exactly
    what the orange gate is — hence the modelling above.
    """
    tiers = tiers or {}
    mined = {start}
    owned = {start}          # generators acquired, and therefore usable
    in_hand = 0              # pumps acquired, freely repositionable
    # Upgraders are anchored, so like generators they are ground a pump may not
    # stand on.
    anchored = set(generators) | set(upgraders)

    while True:
        discovered = set(mined)
        for cell in mined:
            discovered.update(adjacency[cell])
        budget = in_hand if with_pumps else 0

        # Which upgraders are actually producing. Being mined is not enough — an
        # upgrader with nothing feeding it is a decoration, so this asks what it
        # costs to get red onto it and remembers the price, which the orange leg
        # below then has to work around.
        live = {}
        for upgrader in sorted(set(upgraders) & mined):
            costs = [
                spend
                for spend in (
                    leg(adjacency, source, upgrader, discovered, mined,
                        anchored, budget)
                    for source in sorted(owned)
                )
                if spend is not None
            ]
            if costs:
                live[upgrader] = min(costs)

        progressed = False
        for target in sorted(discovered - mined):
            if tiers.get(target) == "orange":
                reachable = any(
                    leg(adjacency, upgrader, target, discovered, mined,
                        anchored, budget - red_spend) is not None
                    for upgrader, red_spend in sorted(live.items())
                )
            else:
                reachable = any(
                    leg(adjacency, source, target, discovered, mined,
                        anchored, budget) is not None
                    for source in sorted(owned)
                )
            if reachable:
                mined.add(target)
                progressed = True
                if target in generators:
                    owned.add(target)
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


def search_contents(adjacency, coords, start, rng):
    """Find a generator/pump placement that is spread out and needs its pumps.

    Three conditions. With pumps the whole board must fall; *without* them it
    must not; and the generators must reach into at least MIN_QUADRANTS corners
    of the board.

    The middle one is what makes pumps load-bearing rather than decorative, and
    it replaces the old static proxies (diameter, "some cells out of unaided
    range") which cannot see it. The third pulls against it: generators spaced
    evenly leave every cell within a few hops of one and the map finishes with no
    pumps at all — measured at 0 viable placements out of 1500 once every pair
    was forced 3+ hops apart. Quadrant coverage is what satisfies both, because
    it spreads the generators over the board without spacing them uniformly.
    """
    cells = sorted(adjacency)
    best = None
    for _ in range(SEARCH_TRIES):
        generators = {start} | set(
            rng.sample([c for c in cells if c != start], GENERATOR_COUNT - 1)
        )
        if quadrants_covered(generators, coords) < MIN_QUADRANTS:
            continue
        pumps = set(
            rng.sample([c for c in cells if c not in generators], PUMP_COUNT)
        )
        if len(play(adjacency, generators, pumps, start, True)) != len(cells):
            continue
        stranded = len(cells) - len(
            play(adjacency, generators, pumps, start, False)
        )
        if stranded == 0:
            continue
        # Prefer the placement that strands the most without pumps: that is the
        # one where the pump chain matters most.
        if best is None or stranded > best[0]:
            best = (stranded, sorted(generators), sorted(pumps))
        if best[0] >= STRANDED_TARGET:
            break
    return best


def place_challenges(adjacency, distances, taken, start, rng):
    """Bury one challenge in each hop band, nearest the start first.

    Drawn *after* the search and deliberately invisible to `play()`, exactly as
    the spheres are and for the same reason: a challenge only ever adds power, so
    a board that clears without counting them is one a player clears with them.
    Folding them into the search would burn draws on something none of its three
    conditions can see.

    Their cost is invisible to `play()` too, which asks only whether an orb can
    arrive with anything at all and never looks at `unlock_cost`. That is what
    makes CHALLENGE_COST_MULTIPLIER safe to raise: an expensive cell is slow, not
    unreachable, and the winnability assertion still means what it says.

    Returns ids in CHALLENGE_IDS order. Raises if a band is empty, which would
    mean the lattice changed shape underneath CHALLENGE_BANDS.
    """
    chosen = []
    used = set(taken)
    for block_id, (low, high) in zip(CHALLENGE_IDS, CHALLENGE_BANDS):
        band = [
            c
            for c in sorted(adjacency)
            if c not in used
            and c != start
            and low <= distances[c] <= high
        ]
        if not band:
            raise AssertionError(
                f"no free cell {low}-{high} hops from the start for {block_id} — "
                "CHALLENGE_BANDS no longer matches the lattice"
            )
        pick = rng.choice(band)
        chosen.append(pick)
        used.add(pick)
    return chosen


def assign_tiers(adjacency, distances, challenge_cells, rng):
    """Decide which cells demand orange. Returns {cell: "orange"}; red is absent.

    Two rules. Everything at ORANGE_FROM hops or further is orange outright —
    that is the rim, and it is what the second tier is for. Inside ORANGE_BAND a
    fraction are drawn at random, so the player meets the colour as a scatter of
    cells they cannot pay for yet rather than as a line across the board.

    **Challenges are exempt from the band draw, but not from the rim rule.** The
    nearest challenge is the one that teaches what a triangle means, and it has
    to be affordable while the board still is; rolling it orange would hide the
    tutorial behind the mechanic it is meant to introduce. A challenge out past
    the rim is a different matter — by then orange is simply what the board runs
    on, and exempting it would be a hole in the wall.

    Drawn from its own RNG stream. The main stream placed the generators, pumps,
    spheres and challenges, and taking draws from it here would shift every one
    of them — the board would silently become a different board.
    """
    tiers = {}
    low, high = ORANGE_BAND
    for cell in sorted(adjacency):
        hops = distances[cell]
        if hops >= ORANGE_FROM:
            tiers[cell] = "orange"
        elif low <= hops <= high and cell not in challenge_cells:
            if rng.random() < ORANGE_BAND_DENSITY:
                tiers[cell] = "orange"
    return tiers


def search_upgraders(adjacency, generators, pumps, start, tiers, taken, distances,
                     rng):
    """Find an upgrader placement that reopens the board.

    Searched separately from `search_contents`, and after it, so the generator,
    pump, sphere and challenge placement it already settled on is left exactly
    where it was. Orange is additive to this map rather than a reason to draw a
    new one.

    Candidates are free cells inside UPGRADER_BAND that are themselves *red*.
    An orange-gated upgrader is a deadlock — the only thing that could pay for it
    is the thing it is needed to build — and it is worth excluding by
    construction here rather than detecting in an assertion later.

    Two conditions, and the second is the one that bites. With these upgraders
    the whole board must fall — otherwise orange has shut cells nothing can
    reach. But the board must *still* fail without pumps, and that is not free:
    an upgrader is a new place orange sets out from, so five of them hand the map
    five new sources and can quietly put the far rim back inside unaided range.
    Measured, that is exactly what the first placement found here did — it
    cleared the board with no pump ever placed, which is the one thing the map is
    not allowed to do.

    So this searches for both, the way `search_contents` does, and prefers the
    placement that strands the most without pumps.
    """
    cells = sorted(adjacency)
    candidates = [
        c for c in cells
        if c not in taken
        and c != start
        and tiers.get(c) != "orange"
        and UPGRADER_BAND[0] <= distances[c] <= UPGRADER_BAND[1]
    ]
    assert len(candidates) >= UPGRADER_COUNT, (
        f"only {len(candidates)} free red cells {UPGRADER_BAND[0]}-"
        f"{UPGRADER_BAND[1]} hops out, need {UPGRADER_COUNT} — widen "
        "UPGRADER_BAND or bury fewer blocks"
    )
    best = None
    for _ in range(SEARCH_TRIES):
        upgraders = set(rng.sample(candidates, UPGRADER_COUNT))
        cleared = play(adjacency, generators, pumps, start, True,
                       tiers=tiers, upgraders=upgraders)
        if len(cleared) != len(cells):
            continue
        stranded = len(cells) - len(
            play(adjacency, generators, pumps, start, False,
                 tiers=tiers, upgraders=upgraders)
        )
        if stranded == 0:
            continue
        if best is None or stranded > best[0]:
            best = (stranded, sorted(upgraders))
        if best[0] >= UPGRADER_STRANDED_TARGET:
            break
    return best


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
              + len(CHALLENGE_IDS))
    assert buried < cell_count, (
        f"{buried} blocks do not fit on {cell_count} cells — an entirely buried "
        "board leaves nothing to mine through"
    )

    rng = random.Random(SEED)
    found = search_contents(adjacency, coords, start, rng)
    assert found, (
        f"no placement of {GENERATOR_COUNT} generators and {PUMP_COUNT} pumps "
        f"spans {MIN_QUADRANTS} quadrants, finishes the map, and needs its pumps "
        "to do it — try keeping fewer centres, which shorten routes"
    )
    _, generators, pumps = found

    # Distances are needed before placement now, because the challenges are drawn
    # from hop bands rather than from the board at large.
    distances, _ = bfs(adjacency, start)
    challenges = place_challenges(
        adjacency, distances, set(generators) | set(pumps), start, rng
    )
    spheres = place_spheres(
        adjacency, set(generators) | set(pumps) | set(challenges), start, rng
    )

    # Everything above draws from `rng` and must keep drawing in exactly that
    # order: the board it produces is the shipped one, and orange is being added
    # to that board rather than used as an excuse to roll a new one. So the tier
    # gate and the upgraders get a stream of their own, opened only once the main
    # stream has finished with every placement it owns.
    orange_rng = random.Random(SEED + 1)
    tiers = assign_tiers(adjacency, distances, set(challenges), orange_rng)
    found_upgraders = search_upgraders(
        adjacency, set(generators), set(pumps), start, tiers,
        set(generators) | set(pumps) | set(challenges) | set(spheres),
        distances, orange_rng,
    )
    assert found_upgraders, (
        f"no placement of {UPGRADER_COUNT} upgraders both reopens the board and "
        "still needs its pumps to do it — the gate is either shutting cells "
        "nothing can reach, or handing out so many new sources that the rim "
        "falls unaided. Adjust ORANGE_FROM, ORANGE_BAND_DENSITY or "
        "UPGRADER_COUNT"
    )
    # Recomputed with the upgraders in play: the count from `search_contents`
    # described a board with no orange on it and is no longer the truth.
    stranded, upgraders = found_upgraders

    contents = {}
    for cell in generators:
        contents[cell] = "generator"
    for cell in pumps:
        contents[cell] = "pump"
    for cell in spheres:
        contents[cell] = "sphere"
    for cell in upgraders:
        contents[cell] = "upgrader"
    for cell, block_id in zip(challenges, CHALLENGE_IDS):
        contents[cell] = block_id

    challenge_cells = set(challenges)

    cells = []
    for cell_id in sorted(adjacency):
        hops = distances[cell_id]
        cost = (
            0 if cell_id == start
            else int(round(COST_BASE * COST_GROWTH ** (hops - 1)))
        )
        if cell_id in challenge_cells:
            cost *= CHALLENGE_COST_MULTIPLIER
        # Divided *after* the challenge multiplier, so an orange challenge is
        # still six times an orange cell at its distance rather than six times a
        # red one. The multiplier means "a challenge costs six ordinary cells",
        # and that has to stay true in whatever colour it is charged in.
        if tiers.get(cell_id) == "orange":
            cost = int(round(cost / ORANGE_COST_DIVISOR))
        cells.append({
            "id": cell_id,
            "x": positions[cell_id][0],
            "y": positions[cell_id][1],
            "neighbors": adjacency[cell_id],
            "unlock_cost": cost,
            # Omitted for red, which is most of the board, so the file stays
            # close to what it was before a second tier existed.
            **({"tier": "orange"} if tiers.get(cell_id) == "orange" else {}),
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
    print(f"generators {generators} "
          f"({quadrants_covered(set(generators), coords)} of 4 quadrants)")
    print(f"pumps      {pumps}")
    print(f"spheres    {spheres} (not modelled by the playthrough)")
    print(f"upgraders  {upgraders} "
          f"(at {sorted(distances[u] for u in upgraders)} hops, all red-gated)")
    print("challenges " + ", ".join(
        f"{block_id.removeprefix('challenge_')} {cell} @{distances[cell]} hops "
        f"for {by_id_cost}"
        for block_id, cell, by_id_cost in (
            (b, c, int(round(COST_BASE * COST_GROWTH ** (distances[c] - 1)))
             * CHALLENGE_COST_MULTIPLIER)
            for b, c in zip(CHALLENGE_IDS, challenges)
        )
    ))
    print(f"active     {len(contents)} of {cell_count} cells "
          f"({len(contents) / cell_count:.0%}), {cell_count - len(contents)} empty")
    print(f"unlock cost {min(c['unlock_cost'] for c in cells if c['id'] != start)}"
          f"..{max(c['unlock_cost'] for c in cells)}, "
          f"{sum(c['unlock_cost'] for c in cells)} to clear the board")
    print(f"without pumps, {stranded} cells are unmineable")
    orange_cells = [c for c in cells if c.get("tier") == "orange"]
    in_band = [c for c in orange_cells if distances[c["id"]] < ORANGE_FROM]
    red_total = sum(c["unlock_cost"] for c in cells if c.get("tier") != "orange")
    orange_total = sum(c["unlock_cost"] for c in orange_cells)
    print(f"orange     {len(orange_cells)} of {cell_count} cells "
          f"({len(orange_cells) / cell_count:.0%}), {len(in_band)} of them "
          f"inside the {ORANGE_BAND[0]}-{ORANGE_FROM - 1} band")
    print(f"           {red_total} red + {orange_total} orange to clear "
          f"(= {red_total + orange_total * UPGRADE_COST // ORB_START_VALUE} red "
          f"equivalent at {UPGRADE_COST}:{ORB_START_VALUE})")
    print()

    by_id = {c["id"]: c for c in cells}
    for row in range(ROWS):
        line = []
        for col in range(COLS):
            if (col, row) not in ids:
                line.append(" " * 11)
                continue
            cell_id = ids[(col, row)]
            mark = {
                "generator": "G", "pump": "P", "sphere": "O", "upgrader": "U"
            }.get(contents.get(cell_id), ".")
            # Challenges are marked 1/2/3 rather than sharing a letter, because
            # which one landed where is the thing worth eyeballing.
            if cell_id in challenge_cells:
                mark = str(challenges.index(cell_id) + 1)
            if cell_id == start:
                mark = "S"
            # Trailing marker rather than a colour: the gate is a property of the
            # cell, not of what is buried in it, so it needs its own column.
            gate = "~" if by_id[cell_id].get("tier") == "orange" else " "
            line.append(
                f" {cell_id:3d}{mark}{by_id[cell_id]['unlock_cost']:5d}{gate}"
            )
        # Half a cell, so odd rows sit in the gaps of even ones the way the
        # lattice does. Eleven characters per cell, so five.
        indent = "     " if row % 2 else ""
        print(indent + "".join(line).rstrip())
    print("\n  id + S/G/P/O/U/1/2/3/. + unlock cost + gate   (S is the start, a "
          "generator; O a sphere; U an upgrader;\n  1-3 the challenges, nearest "
          "first; a trailing ~ means the cell is unlocked by orange, not red)")

    # --- Assertions ---
    assert diameter >= 12, f"diameter {diameter} too short — decay would not matter"
    assert min(degrees) >= 2, "a degree-1 cell is a dead end, not a web"

    # Play opens in the middle, so the far corner is a radius away, not a
    # diameter. An orb has to arrive with something left, so unaided reach is
    # the last hop before it hits zero; if the whole board sits inside that, the
    # starting generator alone supplies everything and the two assertions at the
    # bottom become unsatisfiable.
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

    # The two that matter, re-checked on exactly what was written out. Generators
    # are anchored, so winnability is not something the shape alone can promise.
    generator_set, pump_set = set(generators), set(pumps)
    upgrader_set = set(upgraders)
    with_pumps = play(adjacency, generator_set, pump_set, start, True,
                      tiers=tiers, upgraders=upgrader_set)
    assert len(with_pumps) == cell_count, (
        f"unwinnable: only {len(with_pumps)} of {cell_count} cells can be mined"
    )
    without_pumps = play(adjacency, generator_set, pump_set, start, False,
                         tiers=tiers, upgraders=upgrader_set)
    assert len(without_pumps) < cell_count, (
        "the whole map falls without ever placing a pump — pumps are decorative"
    )

    # And that the upgraders are load-bearing in the same sense the pumps are.
    # Without them every orange cell is unreachable, so this is really a check
    # that the orange gate is doing something: if the board still clears with no
    # converter on it, the tier is decoration.
    without_upgraders = play(adjacency, generator_set, pump_set, start, True,
                             tiers=tiers)
    assert len(without_upgraders) < cell_count, (
        "the whole map falls without a single upgrader — the orange gate is "
        "shutting nothing, so the second tier is decorative"
    )

    # Every upgrader must be mineable by the colour that exists before it does.
    # An orange-gated upgrader can only be paid for with orange, which only an
    # upgrader can make — a deadlock the playthrough above would catch only
    # indirectly, and which is worth naming.
    for cell_id in upgraders:
        assert tiers.get(cell_id) != "orange", (
            f"cell {cell_id} buries an upgrader behind an orange gate — nothing "
            "can pay for it before it exists"
        )

    # The gate itself: total past the rim, a scatter before it. Asserted against
    # what was written rather than the dict it came from, so a hand-edited map
    # fails here too.
    for cell in cells:
        orange = cell.get("tier") == "orange"
        hops = distances[cell["id"]]
        assert not (hops >= ORANGE_FROM and not orange), (
            f"cell {cell['id']} at {hops} hops is red, but everything from "
            f"{ORANGE_FROM} hops out must be orange"
        )
        assert not (orange and hops < ORANGE_BAND[0]), (
            f"cell {cell['id']} at {hops} hops is orange, inside the opening "
            f"where only red exists"
        )
    banded = [
        c["id"] for c in cells
        if c.get("tier") == "orange"
        and ORANGE_BAND[0] <= distances[c["id"]] < ORANGE_FROM
    ]
    assert banded, (
        f"no orange cell between {ORANGE_BAND[0]} and {ORANGE_FROM - 1} hops — "
        "the colour arrives as a wall rather than as a scatter the player meets "
        "while red still works"
    )

    # Each challenge exactly once. Uniqueness is the whole premise — a second
    # Surge would stack a bonus the balance assumes is granted one time only —
    # and it is cheaper to assert here than to enforce at runtime.
    for block_id in CHALLENGE_IDS:
        found_at = [c["id"] for c in cells if c.get("block") == block_id]
        assert len(found_at) == 1, (
            f"{len(found_at)} cells bury {block_id} — challenges are unique"
        )

    # And in ascending order of distance, so they arrive as milestones instead of
    # all at once. Strict, not merely non-decreasing: two challenges at the same
    # distance are two cells the player reaches together, which is the thing the
    # ordering exists to avoid.
    challenge_hops = [distances[c] for c in challenges]
    assert challenge_hops == sorted(set(challenge_hops)), (
        f"challenges sit at {challenge_hops} hops — they must be strictly "
        "increasing, or CHALLENGE_BANDS overlap"
    )

    print("\nok")


if __name__ == "__main__":
    main()
