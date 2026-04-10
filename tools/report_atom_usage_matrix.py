#!/usr/bin/env python3
"""Report requirement/step atom usage from cards_effects.json files."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


def collect_usage(cards_root: Path) -> tuple[Counter, Counter]:
    requirement_usage: Counter = Counter()
    step_usage: Counter = Counter()
    for effects_path in sorted(cards_root.glob("*/cards_effects.json")):
        cards = json.loads(effects_path.read_text(encoding="utf-8"))
        for card in cards:
            for ability in card.get("abilities", []):
                for requirement in ability.get("requirements", []):
                    requirement_usage[requirement.get("type", "UNKNOWN")] += 1
                for step in ability.get("steps", []):
                    step_usage[step.get("type", "UNKNOWN")] += 1
    return requirement_usage, step_usage


def _counter_to_table(title: str, counter: Counter) -> list[str]:
    lines = [f"## {title}", "", "| 原子类型 | 使用次数 |", "| --- | ---: |"]
    for atom, count in sorted(counter.items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"| {atom} | {count} |")
    lines.append("")
    return lines


def to_markdown(requirement_usage: Counter, step_usage: Counter) -> str:
    lines = ["# 原子复用矩阵", ""]
    lines.extend(_counter_to_table("Requirement 复用", requirement_usage))
    lines.extend(_counter_to_table("Step 复用", step_usage))
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cards-root", default="data/cards", type=Path)
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()

    requirement_usage, step_usage = collect_usage(args.cards_root)
    report = to_markdown(requirement_usage, step_usage)
    print(report)
    if args.out:
        args.out.write_text(report + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
