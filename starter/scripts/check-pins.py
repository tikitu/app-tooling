#!/usr/bin/env python3
"""Check that two Package.resolved files pin the same versions.

The shared package and the Mac package resolve their dependencies separately
but link the same libraries, so a disagreement means the app is built against
one version and tested against another. Only dependencies both files pin are
compared: the Mac package may pin more. Standard library only; run by
`make check-pins`, which every build runs.

Usage: check-pins.py <Package.resolved> <Package.resolved>
"""

import json
import sys


def pins(path):
    with open(path) as f:
        return {pin["identity"]: pin["state"] for pin in json.load(f)["pins"]}


def describe(state):
    return state.get("version") or state.get("branch") or state["revision"][:12]


def main():
    first_path, second_path = sys.argv[1:3]
    first, second = pins(first_path), pins(second_path)
    disagreements = sorted(k for k in first.keys() & second.keys() if first[k] != second[k])
    for identity in disagreements:
        print(
            f"  ✗ {identity}: {describe(first[identity])} in {first_path}, "
            f"{describe(second[identity])} in {second_path}"
        )
    return 1 if disagreements else 0


if __name__ == "__main__":
    sys.exit(main())
