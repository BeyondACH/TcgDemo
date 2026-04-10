#!/usr/bin/env python3
"""Cluster high-frequency UNSUPPORTED ability text families."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


def normalize_text(text: str) -> str:
    text = text.strip()
    text = re.sub(r"[0-9０-９]+", "#", text)
    text = re.sub(r"\s+", " ", text)
    return text


def collect_unsupported(cards_root: Path) -> dict[str, list[dict]]:
    families: dict[str, list[dict]] = defaultdict(list)
    for semantic_path in sorted(cards_root.glob("*/cards_semantic.json")):
        series = semantic_path.parent.name
        cards = json.loads(semantic_path.read_text(encoding="utf-8"))
        for card in cards:
            card_id = card.get("card_id", "")
            for ability in card.get("abilities", []):
                if ability.get("status") != "UNSUPPORTED":
                    continue
                text = ability.get("text", "")
                key = normalize_text(text)
                families[key].append(
                    {
                        "series": series,
                        "card_id": card_id,
                        "ability_id": ability.get("id", ""),
                        "reason": ability.get("reason", ""),
                        "text": text,
                    }
                )
    return families


def classify_family(family: str, reason: str) -> str:
    if "未覆盖" in reason or "尚未覆盖" in reason:
        if "BP" in family or "枚" in family or "选择" in family:
            return "缺少原子/模板（建议优先补）"
        return "可复用已有原子（建议先模板化）"
    if "运行时" in reason:
        return "缺少运行时原子（需先扩运行时）"
    return "暂不建议做（需人工评估）"


def to_markdown(families: dict[str, list[dict]], top_n: int) -> str:
    counter = Counter({family: len(items) for family, items in families.items()})
    lines = ["# 高频 UNSUPPORTED 文本族（Top N）", ""]
    for rank, (family, count) in enumerate(counter.most_common(top_n), start=1):
        lines.append(f"## {rank}. 频次 {count}")
        lines.append(f"- 归一化文本：`{family}`")
        sample = families[family][0]
        lines.append(f"- 原文示例：`{sample['text']}`")
        reason_counter = Counter(item["reason"] for item in families[family])
        top_reasons = ", ".join(f"{r}({c})" for r, c in reason_counter.most_common(3))
        lines.append(f"- 原因分布：{top_reasons}")
        lines.append(f"- 建议分类：{classify_family(family, sample['reason'])}")
        samples = families[family][:3]
        lines.append("- 卡牌样例：")
        for item in samples:
            lines.append(
                f"  - `{item['series']}/{item['card_id']}#{item['ability_id']}`"
            )
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cards-root", default="data/cards", type=Path)
    parser.add_argument("--top-n", default=10, type=int)
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()

    families = collect_unsupported(args.cards_root)
    report = to_markdown(families, args.top_n)
    print(report)
    if args.out:
        args.out.write_text(report + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
