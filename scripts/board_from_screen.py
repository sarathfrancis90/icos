#!/usr/bin/env python3
"""Read the puzzle currently on screen out of the Maestro view hierarchy.

The grid exposes one accessibility label per cell ("Row 3, Column 4, wall"),
which is enough to rebuild the board and hand it to the solver.

Usage:
    python3 scripts/board_from_screen.py <device-udid>
Prints the board as JSON on stdout.
"""
import json
import re
import subprocess
import sys

CELL = re.compile(r"^Row (\d+), Column (\d+), (.+)$")


def hierarchy(device: str) -> dict:
    raw = subprocess.run(
        ["maestro", "--device", device, "hierarchy"],
        capture_output=True, text=True, timeout=180,
    ).stdout
    return json.loads(raw[raw.index("{"):])


def cells(node, out):
    label = node.get("attributes", {}).get("accessibilityText", "")
    m = CELL.match(label)
    if m:
        out[(int(m.group(1)) - 1, int(m.group(2)) - 1)] = m.group(3)
    for child in node.get("children") or []:
        cells(child, out)


def main() -> int:
    found = {}
    cells(hierarchy(sys.argv[1]), found)
    if not found:
        raise SystemExit("no grid cells on screen")

    size = max(max(r, c) for r, c in found) + 1
    walls, waypoints = [], []
    for (row, col), state in sorted(found.items()):
        if state == "wall":
            walls.append([row, col])
        elif state.startswith("waypoint "):
            waypoints.append([row, col, int(state.split()[1])])

    print(json.dumps({"size": size, "walls": walls, "waypoints": waypoints}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
