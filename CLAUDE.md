# Spread

A Godot 4.4 incremental resource-routing game. Feed locked cells to mine them, rearrange what you find,
route orbs across a graph before decay eats them.

## Read these first

At the **start of every conversation**, before proposing or making any change, read:

1. **`architecture.md`** — modules, calculations, and the contracts between them. Always. Even for a
   change that looks small: the tick's phase ordering, the value-ledger invariant, and the determinism
   rules are easy to violate by accident and the file is where they are written down.
2. **`gamedesign.md`** — what the game is, its mechanics, and the current balance numbers. Read it
   whenever the task touches gameplay, balance, or content.

## Keep them up to date

These two files are the project's memory. A change that makes them wrong is not finished.

### `architecture.md`

Update it in the **same change** that introduces:

- a new module, or a file moving between layers
- a new dependency between modules, or a change in dependency direction
- a new tick phase, a new `BlockBehavior` hook, or a change to phase ordering
- a new value-ledger bucket, or any change to the ledger invariant
- promoting something out of *Deliberately not built*, or adding a new deferral

Do **not** update it for ordinary work inside an existing module — a bug fix, a new test, a tuned
constant, a renamed local, a view tweak. It is a map, not a changelog.

### `gamedesign.md`

Update it in the **same change** that introduces:

- a new mechanic, block type, or resource tier
- a change to how the player interacts with the game (mining, aiming, swapping)
- a change to the win condition or the shape of the map

Keep the pitch at the top intact — it is the vision. Add and correct the concrete sections below it, and
keep the balance table matching the constants actually in the code.

Very important. Both of these files should contain high level only. And it should not be a history ledger. You shoudn't keep the history or old notes or the reason for why something changes, only the current basic high level info

## Working notes

- **Run the tests**: `./run_tests.sh` (headless, zero dependencies, exits non-zero on failure). Do not test on screenshots. Do not spend unnecessary tokens on testing, especially if the task is trivial.
- **Keep the suite very small.** If you can see it by playing, don't test it. A test earns its place
  only when it pins an invariant that is invisible on screen and silent when broken — ledger
  conservation, tick order-independence, RNG determinism. Never test view behaviour or juice.
- **Godot lives at** `/Users/timurbekmurzin/Downloads/Godot.app/Contents/MacOS/Godot` — not on `PATH`.
- **Play it**: `Godot --path .`
- **After adding or renaming a script**, run `Godot --headless --path . --import` to rebuild the global
  class cache, or `class_name` lookups fail with confusing parse errors.
- `sim/` must never reference a Godot node, scene, signal, or `delta`.


## On commentaries in code
- Keep them short and sweet. Don't write paragrpah. Only the very basic needed info