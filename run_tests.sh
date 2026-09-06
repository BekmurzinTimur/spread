#!/usr/bin/env bash
# Headless simulation tests. Exits non-zero on failure.
set -euo pipefail

GODOT="${GODOT:-/Users/timurbekmurzin/Downloads/Godot.app/Contents/MacOS/Godot}"

if [ ! -x "$GODOT" ]; then
	echo "Godot not found at: $GODOT" >&2
	echo "Set GODOT=/path/to/Godot and re-run." >&2
	exit 127
fi

cd "$(dirname "$0")"
exec "$GODOT" --headless --path . --script res://tests/run_tests.gd
