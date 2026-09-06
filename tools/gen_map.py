#!/usr/bin/env python3
"""Generate data/map_01.json — a clustered web.

Run from the project root:  python3 tools/gen_map.py

Shape matters more than size here. A compact 35-cell blob is only ~8 hops
across, which would make decay irrelevant and pumps pointless. So the cells are
grouped into clusters that are dense inside (several routes between nearby
cells, so the map reads as a web) and joined to each other by one or two
bridges (so the diameter stays long enough that the far side is out of unaided
range and pump chains are the only way forward).

Prints a distance/arrival table and asserts the properties the game depends on.
"""

import collections
import json
import math
import random

SEED = 20260906
ORB_MAX_VALUE = 10
DECAY_PER_HOP = 1

# name, centre, cell count, spread
CLUSTERS = [
    ("home",   (0, 0),        6, 210),
    ("north",  (820, -620),   6, 210),
    ("south",  (880, 540),    6, 220),
    ("mid",    (1700, -80),   6, 220),
    ("far",    (2560, 380),   6, 220),
    ("deep",   (3400, -200),  5, 210),
]

# Cluster pairs joined by a bridge. home reaches mid only the long way round,
# through north or south — that loop is the route choice — and beyond mid the
# map is a chain, which is what keeps the far side genuinely far.
BRIDGES = [
    ("home", "north", 1),
    ("home", "south", 1),
    ("north", "mid", 1),
    ("south", "mid", 1),
    ("mid", "far", 1),
    ("far", "deep", 1),
]

# Contents, addressed as (cluster, index-within-cluster). Everything else is
# empty. The home cluster holds the starting generator plus the first pump, so
# the player can always acquire a relay before needing one.
CONTENTS = {
    ("home", 0): "generator",
    ("home", 3): "pump",
    ("north", 2): "pump",
    ("north", 5): "generator",
    ("south", 1): "pump",
    ("south", 4): "generator",
    ("mid", 0): "pump",
    ("mid", 3): "pump",
    ("mid", 5): "generator",
    ("far", 1): "pump",
    ("far", 4): "generator",
    ("deep", 0): "pump",
    ("deep", 3): "pump",
}

START = ("home", 0)


def build():
    rng = random.Random(SEED)
    positions, members, ids = {}, {}, {}
    next_id = 0

    for name, (cx, cy), count, spread in CLUSTERS:
        members[name] = []
        for k in range(count):
            # Ring layout with jitter: keeps cells apart without overlap checks.
            angle = (k / count) * math.tau + rng.uniform(-0.35, 0.35)
            radius = spread * rng.uniform(0.45, 1.0) if k else 0.0
            positions[next_id] = (
                round(cx + math.cos(angle) * radius),
                round(cy + math.sin(angle) * radius * 0.85),
            )
            members[name].append(next_id)
            ids[(name, k)] = next_id
            next_id += 1

    adjacency = collections.defaultdict(set)

    def connect(a, b):
        adjacency[a].add(b)
        adjacency[b].add(a)

    # Inside a cluster: a ring plus one chord. The ring guarantees two distinct
    # routes between any pair (the web-like part) while still costing a couple
    # of hops to cross; linking every cell to its nearest neighbours instead
    # makes clusters near-instant to traverse and collapses the diameter.
    for cells in members.values():
        for i, cell in enumerate(cells):
            connect(cell, cells[(i + 1) % len(cells)])
        connect(cells[0], cells[len(cells) // 2])

    # Between clusters: the closest cross-pairs, which reads as a bridge.
    for a_name, b_name, count in BRIDGES:
        pairs = sorted(
            ((a, b) for a in members[a_name] for b in members[b_name]),
            key=lambda p: dist(positions, p[0], p[1]),
        )
        for a, b in pairs[:count]:
            connect(a, b)

    start_id = ids[START]
    distances = bfs(adjacency, start_id)

    cells = []
    for name, cluster_cells in members.items():
        for k, cell_id in enumerate(cluster_cells):
            hops = distances[cell_id]
            cells.append({
                "id": cell_id,
                "x": positions[cell_id][0],
                "y": positions[cell_id][1],
                "neighbors": sorted(adjacency[cell_id]),
                # Costs rise with distance while arrivals shrink, so the far
                # side is deliberately impractical until pumps are in place.
                "unlock_cost": 0 if cell_id == start_id else 25 + 7 * hops,
                **({"block": CONTENTS[(name, k)]} if (name, k) in CONTENTS else {}),
                **({"starts_unlocked": True} if cell_id == start_id else {}),
            })

    cells.sort(key=lambda c: c["id"])
    return cells, adjacency, distances, start_id, members


def dist(positions, a, b):
    ax, ay = positions[a]
    bx, by = positions[b]
    return math.hypot(ax - bx, ay - by)


def bfs(adjacency, source):
    seen = {source: 0}
    queue = collections.deque([source])
    while queue:
        current = queue.popleft()
        for n in sorted(adjacency[current]):
            if n not in seen:
                seen[n] = seen[current] + 1
                queue.append(n)
    return seen


def main():
    cells, adjacency, distances, start_id, members = build()
    by_id = {c["id"]: c for c in cells}

    assert len(distances) == len(cells), "graph is not connected"

    diameter = max(
        max(bfs(adjacency, c["id"]).values()) for c in cells
    )
    unaided = {i: ORB_MAX_VALUE - DECAY_PER_HOP * d for i, d in distances.items()}
    out_of_range = [i for i, v in unaided.items() if v <= 0]
    pumps = [c["id"] for c in cells if c.get("block") == "pump"]
    generators = [c["id"] for c in cells if c.get("block") == "generator"]
    early_pumps = [p for p in pumps if unaided[p] > 0]

    with open("data/map_01.json", "w") as f:
        json.dump({"name": "First Light", "cells": cells}, f, indent=2)
        f.write("\n")

    degrees = [len(c["neighbors"]) for c in cells]
    print(f"{len(cells)} cells, {sum(degrees) // 2} edges, "
          f"degree min {min(degrees)} avg {sum(degrees) / len(degrees):.1f} max {max(degrees)}")
    print(f"diameter {diameter} hops, max distance from start {max(distances.values())}")
    print(f"generators {generators}")
    print(f"pumps {pumps}  (reachable unaided: {early_pumps})")
    print(f"out of unaided range from start: {len(out_of_range)} cells")
    print()
    for name, cluster_cells in members.items():
        print(f"  {name}:")
        for cell_id in cluster_cells:
            c = by_id[cell_id]
            print(f"    cell {cell_id:2d}  dist {distances[cell_id]:2d}"
                  f"  arrives {max(0, unaided[cell_id]):2d}"
                  f"  cost {c['unlock_cost']:3d}"
                  f"  deg {len(c['neighbors'])}"
                  f"  {c.get('block', '')}")

    assert diameter >= 12, f"diameter {diameter} too short — decay would not matter"
    assert out_of_range, "every cell is reachable unaided — pumps are pointless"
    assert early_pumps, "no pump inside the unaided frontier — unwinnable from the start"
    assert min(degrees) >= 2, "a degree-1 cell is a dead end, not a web"
    print("\nok")


if __name__ == "__main__":
    main()
