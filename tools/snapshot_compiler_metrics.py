#!/usr/bin/env python3
"""Create/compare compiler metrics snapshots for regression checks."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def build_snapshot(cards_root: Path) -> dict:
    per_series = {}
    totals = {"cards": 0, "abilities": 0, "supported": 0, "unsupported": 0}
    for effects_path in sorted(cards_root.glob("*/cards_effects.json")):
        cards = json.loads(effects_path.read_text(encoding="utf-8"))
        series_stats = {"cards": len(cards), "abilities": 0, "supported": 0, "unsupported": 0}
        for card in cards:
            for ability in card.get("abilities", []):
                series_stats["abilities"] += 1
                status = ability.get("status", "UNSUPPORTED")
                if status == "SUPPORTED":
                    series_stats["supported"] += 1
                elif status == "UNSUPPORTED":
                    series_stats["unsupported"] += 1
        per_series[effects_path.parent.name] = series_stats
        for key in totals:
            totals[key] += series_stats[key]
    return {"totals": totals, "per_series": per_series}


def compare_snapshot(old: dict, new: dict) -> list[str]:
    lines: list[str] = []
    for scope in ("totals",):
        for key in ("cards", "abilities", "supported", "unsupported"):
            delta = new[scope][key] - old[scope][key]
            if delta != 0:
                lines.append(f"{scope}.{key}: {old[scope][key]} -> {new[scope][key]} ({delta:+d})")
    for series, stats in new["per_series"].items():
        if series not in old["per_series"]:
            lines.append(f"per_series.{series}: added")
            continue
        old_stats = old["per_series"][series]
        for key in ("cards", "abilities", "supported", "unsupported"):
            delta = stats[key] - old_stats[key]
            if delta != 0:
                lines.append(
                    f"per_series.{series}.{key}: {old_stats[key]} -> {stats[key]} ({delta:+d})"
                )
    return lines


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cards-root", default="data/cards", type=Path)
    parser.add_argument("--snapshot", default=Path("docs/plan/compiler_metrics_snapshot.json"), type=Path)
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()

    current = build_snapshot(args.cards_root)
    if not args.snapshot.exists() or args.update:
        args.snapshot.write_text(
            json.dumps(current, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"snapshot written: {args.snapshot}")
        return 0

    baseline = json.loads(args.snapshot.read_text(encoding="utf-8"))
    diff_lines = compare_snapshot(baseline, current)
    if not diff_lines:
        print("snapshot matches baseline")
        return 0
    print("snapshot differs:")
    for line in diff_lines:
        print(f"- {line}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
