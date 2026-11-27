#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

"""Fails (exit 1) when the dev check's check.json reports a problem, so headless-check.sh doesn't pass on exit code alone.
A problem is: the file is missing or not a JSON object, it has an "error" (e.g. "no screen", which skips every check),
or the check still had a window on screen when it finished. Usage: check-json.py <check.json>"""
import json
import sys


def problems(path):
    try:
        with open(path) as f:
            r = json.load(f)
    except (OSError, ValueError) as e:
        return [f"check.json unreadable: {e}"]
    if not isinstance(r, dict):
        return ["check.json is not a JSON object"]
    out = []
    if "error" in r:
        out.append(f"check.json has an error: {r['error']}")
    if r.get("windows_on_screen_at_end", 0) != 0:
        out.append(f"the check had {r['windows_on_screen_at_end']} window(s) on screen at the end")
    if len(r) < 5:
        out.append(f"check.json has only {len(r)} field(s); the check stopped early")
    return out


if __name__ == "__main__":
    found = problems(sys.argv[1])
    for p in found:
        print(f"FAIL  {p}")
    sys.exit(1 if found else 0)
