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
lattice a corner start needed: 13x13, for a radius of 11 against a 9-hop reach.
Anything smaller and every cell sits inside range of the starting generator, the
search finds no placement its pumps are needed for, and the assertion at the
bottom fires.

Contents are *searched for*, not hand-placed. Generators are anchored where the
map buries them, so whether the map can be finished at all is a sequencing
question — can you bootstrap your way out to the next buried generator? — and no
static property answers it. `play()` below answers it by playing the map.

Prints a distance/arrival table and asserts the properties the game depends on.
"""

import collections
import json
import random
import re

SEED = 20260906

# Must match sim/world.gd and sim/block_catalog.gd.
ORB_START_VALUE = 10
DECAY_PER_HOP = 1
PUMP_RESTORE = 3

COLS, ROWS = 13, 13

# Which of the three sublattices to delete. These are the hexagon centres; taking
# them out is what turns the triangular mesh into a honeycomb.
CENTRE_CLASS = 0

# Centres kept anyway, as junctions. Every other cell has three neighbours, so
# these are the only place the board opens up. Keep few: each one shortens routes
# across the middle, which is exactly what pumps are there to pay for.
KEPT_CENTRES = {(0, 4), (7, 3)}

GENERATOR_COUNT = 5
PUMP_COUNT = 5

# Spheres speed up generators and strengthen pumps within a couple of hops.
# Placed but deliberately *not* modelled by `play()` below — see the note there.
SPHERE_COUNT = 3

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
STRANDED_TARGET = 4
SEARCH_TRIES = 20000

# On-screen spacing. 0.866 is sin(60°): the row step of a regular hex lattice.
SPACING = 190
ROW_STEP = 0.866

# Cost rises with distance from the start while arrivals shrink, so the far side
# is deliberately impractical until pumps are in place.
COST_BASE = 25
COST_PER_HOP = 7


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


def play(adjacency, generators, pumps, start, with_pumps=True):
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
    """
    mined = {start}
    owned = {start}          # generators acquired, and therefore usable
    in_hand = 0              # pumps acquired, freely repositionable

    while True:
        discovered = set(mined)
        for cell in mined:
            discovered.update(adjacency[cell])

        progressed = False
        for target in sorted(discovered - mined):
            best = 0
            for source in sorted(owned):
                seen, parent = bfs(adjacency, source, allowed=discovered)
                if target not in seen:
                    continue
                path = route(parent, target)
                # A pump only helps on a mined cell it can actually sit on: not
                # the source (hop 0 is never entered), not the final cell
                # (blocks never act there), and not a cell holding an anchored
                # generator. This mirrors World.arrival_along.
                interior = [
                    c for c in path[1:-1] if c in mined and c not in generators
                ]
                usable = min(in_hand if with_pumps else 0, len(interior))
                hops = len(path) - 1
                best = max(
                    best,
                    ORB_START_VALUE - DECAY_PER_HOP * hops + PUMP_RESTORE * usable,
                )
            if best > 0:
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

    rng = random.Random(SEED)
    found = search_contents(adjacency, coords, start, rng)
    assert found, (
        f"no placement of {GENERATOR_COUNT} generators and {PUMP_COUNT} pumps "
        f"spans {MIN_QUADRANTS} quadrants, finishes the map, and needs its pumps "
        "to do it — try keeping fewer centres, which shorten routes"
    )
    stranded, generators, pumps = found
    spheres = place_spheres(adjacency, set(generators) | set(pumps), start, rng)

    distances, _ = bfs(adjacency, start)
    contents = {}
    for cell in generators:
        contents[cell] = "generator"
    for cell in pumps:
        contents[cell] = "pump"
    for cell in spheres:
        contents[cell] = "sphere"

    cells = []
    for cell_id in sorted(adjacency):
        hops = distances[cell_id]
        cells.append({
            "id": cell_id,
            "x": positions[cell_id][0],
            "y": positions[cell_id][1],
            "neighbors": adjacency[cell_id],
            "unlock_cost": 0 if cell_id == start else COST_BASE + COST_PER_HOP * hops,
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
        i: ORB_START_VALUE - DECAY_PER_HOP * d for i, d in distances.items()
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
    print(f"without pumps, {stranded} cells are unmineable")
    print()

    by_id = {c["id"]: c for c in cells}
    for row in range(ROWS):
        line = []
        for col in range(COLS):
            if (col, row) not in ids:
                line.append("        ")
                continue
            cell_id = ids[(col, row)]
            mark = {"generator": "G", "pump": "P", "sphere": "O"}.get(
                contents.get(cell_id), "."
            )
            if cell_id == start:
                mark = "S"
            line.append(f" {cell_id:2d}{mark}{by_id[cell_id]['unlock_cost']:3d} ")
        indent = "    " if row % 2 else ""
        print(indent + "".join(line).rstrip())
    print("\n  id + S/G/P/O/. + unlock cost   (S is the start, a generator; "
          "O a sphere)")

    # --- Assertions ---
    assert diameter >= 12, f"diameter {diameter} too short — decay would not matter"
    assert min(degrees) >= 2, "a degree-1 cell is a dead end, not a web"

    # Play opens in the middle, so the far corner is a radius away, not a
    # diameter. An orb has to arrive with something left, so unaided reach is
    # the last hop before it hits zero; if the whole board sits inside that, the
    # starting generator alone supplies everything and the two assertions at the
    # bottom become unsatisfiable.
    radius = max(distances.values())
    reach = (ORB_START_VALUE - 1) // DECAY_PER_HOP
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
    with_pumps = play(adjacency, generator_set, pump_set, start, True)
    assert len(with_pumps) == cell_count, (
        f"unwinnable: only {len(with_pumps)} of {cell_count} cells can be mined"
    )
    without_pumps = play(adjacency, generator_set, pump_set, start, False)
    assert len(without_pumps) < cell_count, (
        "the whole map falls without ever placing a pump — pumps are decorative"
    )

    print("\nok")


if __name__ == "__main__":
    main()
