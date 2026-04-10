#!/usr/bin/env python3
"""Report SUPPORTED/UNSUPPORTED ability stats from cards_effects.json files."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


@dataclass
class SeriesStats:
    series: str
    cards: int
    abilities: int
    supported: int
    unsupported: int

    @property
    def support_rate(self) -> float:
        if self.abilities == 0:
            return 0.0
        return self.supported / self.abilities


def _load_effect_cards(path: Path) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))


def collect_stats(cards_root: Path) -> list[SeriesStats]:
    stats: list[SeriesStats] = []
    for effects_path in sorted(cards_root.glob("*/cards_effects.json")):
        cards = _load_effect_cards(effects_path)
        counter = Counter()
        ability_count = 0
        for card in cards:
            for ability in card.get("abilities", []):
                ability_count += 1
                counter[ability.get("status", "UNSUPPORTED")] += 1
        stats.append(
            SeriesStats(
                series=effects_path.parent.name,
                cards=len(cards),
                abilities=ability_count,
                supported=counter["SUPPORTED"],
                unsupported=counter["UNSUPPORTED"],
            )
        )
    return stats


def to_markdown(stats: list[SeriesStats]) -> str:
    total_cards = sum(x.cards for x in stats)
    total_abilities = sum(x.abilities for x in stats)
    total_supported = sum(x.supported for x in stats)
    total_unsupported = sum(x.unsupported for x in stats)
    total_rate = (total_supported / total_abilities) if total_abilities else 0.0

    lines = [
        "# 支持率统计报表",
        "",
        "| 系列 | 卡牌数 | 能力总数 | SUPPORTED | UNSUPPORTED | 支持率 |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in stats:
        lines.append(
            f"| {row.series} | {row.cards} | {row.abilities} | {row.supported} | "
            f"{row.unsupported} | {row.support_rate:.2%} |"
        )
    lines.extend(
        [
            "| **总计** | "
            f"**{total_cards}** | **{total_abilities}** | **{total_supported}** | "
            f"**{total_unsupported}** | **{total_rate:.2%}** |",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cards-root", default="data/cards", type=Path)
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()

    stats = collect_stats(args.cards_root)
    report = to_markdown(stats)
    print(report)
    if args.out:
        args.out.write_text(report + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
