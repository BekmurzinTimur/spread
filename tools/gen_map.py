#!/usr/bin/env python3
"""Generate data/map_01.json — a hex lattice with barrier voids.

Run from the project root:  python3 tools/gen_map.py

Shape matters more than size. The board is an odd-r offset hex lattice, so most
cells have six neighbours and there are many equally short routes between any
two — the graph reads as a web without needing hand-placed bridges.

Hex is compact, though: a plain 7x6 patch has a diameter of only 9 hops, which
is exactly unaided reach, and decay would never bite. Scattered holes do not fix
that (with six neighbours you just go around). Barrier voids do — a few cells
removed in staggered walls force real detours and push the diameter to 13.

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

COLS, ROWS = 7, 6

# Two staggered walls. Verified to give 36 cells, diameter 13, min degree 2 and
# an average degree of 4.11 — today's diameter and cell count, on a far more
# interconnected board. Changing these will move every number below.
VOIDS = {(3, 5), (4, 3), (4, 4), (5, 1), (5, 2), (6, 3)}

GENERATOR_COUNT = 5
PUMP_COUNT = 5

# How many cells a placement must strand when its pumps are taken away before the
# search stops looking. Five matches the old clustered map's five out-of-unaided-
# range cells. Without an early exit the search runs every candidate and takes
# half a minute for no better result.
STRANDED_TARGET = 5
SEARCH_TRIES = 20000

# On-screen spacing. 0.866 is sin(60°): the row step of a regular hex lattice.
SPACING = 190
ROW_STEP = 0.866

# Cost rises with distance from the start while arrivals shrink, so the far side
# is deliberately impractical until pumps are in place.
COST_BASE = 25
COST_PER_HOP = 7


# --- The lattice --------------------------------------------------------


def neighbors(col, row):
    """Odd-r offset hex: six neighbours, clipped to the board and its voids."""
    if row % 2 == 0:
        deltas = [(-1, 0), (1, 0), (-1, -1), (0, -1), (-1, 1), (0, 1)]
    else:
        deltas = [(-1, 0), (1, 0), (0, -1), (1, -1), (0, 1), (1, 1)]
    for dc, dr in deltas:
        c, r = col + dc, row + dr
        if 0 <= c < COLS and 0 <= r < ROWS and (c, r) not in VOIDS:
            yield (c, r)


def build_lattice():
    # Row-major ids. This fixes the BFS tie-break: neighbour lists are sorted
    # ascending and the lowest id wins, so among the many equally short routes a
    # hex lattice offers, orbs consistently prefer the row above. Deterministic
    # and intended — but visible, which is why the ordering is stated here.
    coords = [
        (c, r)
        for r in range(ROWS)
        for c in range(COLS)
        if (c, r) not in VOIDS
    ]
    ids = {xy: i for i, xy in enumerate(coords)}
    adjacency = {
        ids[xy]: sorted(ids[n] for n in neighbors(*xy)) for xy in coords
    }
    positions = {
        ids[(c, r)]: (
            round(c * SPACING + (r % 2) * SPACING / 2),
            round(r * SPACING * ROW_STEP),
        )
        for c, r in coords
    }
    return coords, ids, adjacency, positions


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


def search_contents(adjacency, rng):
    """Find a generator/pump placement that needs its pumps to be finishable.

    Two conditions, and the second is the interesting one: with pumps the whole
    board must fall, and *without* them it must not. That is what makes pumps
    load-bearing rather than decorative, and it replaces the old static proxies
    (diameter, "some cells out of unaided range") which cannot see it — with
    generators spread evenly, nothing is ever more than five hops from one and
    the map finishes with no pumps at all.
    """
    cells = sorted(adjacency)
    start = 0
    best = None
    for _ in range(SEARCH_TRIES):
        generators = {start} | set(
            rng.sample([c for c in cells if c != start], GENERATOR_COUNT - 1)
        )
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


# --- Emit ---------------------------------------------------------------


def main():
    coords, ids, adjacency, positions = build_lattice()
    cell_count = len(coords)
    start = 0

    diameter = diameter_of(adjacency)
    assert diameter is not None, "lattice is not connected — check VOIDS"

    rng = random.Random(SEED)
    found = search_contents(adjacency, rng)
    assert found, (
        f"no placement of {GENERATOR_COUNT} generators and {PUMP_COUNT} pumps "
        "both finishes the map and needs its pumps to do it"
    )
    stranded, generators, pumps = found

    distances, _ = bfs(adjacency, start)
    contents = {}
    for cell in generators:
        contents[cell] = "generator"
    for cell in pumps:
        contents[cell] = "pump"

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
    print(f"{cell_count} cells on a {COLS}x{ROWS} hex lattice "
          f"({len(VOIDS)} voids), {sum(degrees) // 2} edges")
    print(f"degree min {min(degrees)} avg {sum(degrees) / len(degrees):.2f} "
          f"max {max(degrees)}")
    print(f"diameter {diameter} hops, max distance from start "
          f"{max(distances.values())}")
    print(f"generators {generators}")
    print(f"pumps      {pumps}")
    print(f"without pumps, {stranded} cells are unmineable")
    print()

    by_id = {c["id"]: c for c in cells}
    for row in range(ROWS):
        line = []
        for col in range(COLS):
            if (col, row) in VOIDS:
                line.append("  ....  ")
                continue
            cell_id = ids[(col, row)]
            mark = {"generator": "G", "pump": "P"}.get(
                contents.get(cell_id), "."
            )
            line.append(f" {cell_id:2d}{mark}{by_id[cell_id]['unlock_cost']:3d} ")
        indent = "    " if row % 2 else ""
        print(indent + "".join(line))
    print("\n  id + G/P/. + unlock cost")

    # --- Assertions ---
    assert diameter >= 12, f"diameter {diameter} too short — decay would not matter"
    assert min(degrees) >= 2, "a degree-1 cell is a dead end, not a web"

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
