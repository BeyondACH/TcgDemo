#!/usr/bin/env python3
"""Detect high-confidence cases where source effect text is not materialized as abilities."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Candidate:
    series: str
    card_id: str
    effect_text: str
    ability_count: int
    template_types: list[str]


def _is_high_confidence_effect(effect: str) -> bool:
    text = effect.strip()
    if not text or text == "-":
        return False
    if "\n" in text or "・" in text:
        return False
    if text.startswith("※"):
        return False
    if text.startswith("（") and text.endswith("）"):
        return False
    if len(text) > 90:
        return False
    action_tokens = (
        "選び",
        "退場",
        "レスト",
        "アクティブ",
        "引く",
        "戻す",
        "登場",
        "置く",
        "移動",
        "BP+",
        "BP-",
        "発生エナジー+",
    )
    return any(token in text for token in action_tokens)


def collect_candidates(cards_root: Path) -> list[Candidate]:
    rows: list[Candidate] = []
    for semantic_path in sorted(cards_root.glob("*/cards_semantic.json")):
        series = semantic_path.parent.name
        cards = json.loads(semantic_path.read_text(encoding="utf-8"))
        for card in cards:
            effect_text = str((card.get("source_text_jp") or {}).get("effect", "")).strip()
            if not _is_high_confidence_effect(effect_text):
                continue
            ability_texts = [str(ability.get("text", "")).strip() for ability in card.get("abilities", [])]
            if effect_text in ability_texts:
                continue
            rows.append(
                Candidate(
                    series=series,
                    card_id=str(card.get("card_id", "")),
                    effect_text=effect_text,
                    ability_count=len(card.get("abilities", [])),
                    template_types=[str(x) for x in card.get("template_types", [])],
                )
            )
    return rows


def _to_markdown(rows: list[Candidate]) -> str:
    counter = Counter(row.series for row in rows)
    lines = [
        "# 高置信 effect 未落能力项清单",
        "",
        "> 口径：`source_text_jp.effect` 为单句动作文本（排除换行/项目符号/纯括号说明）且未在 `abilities[].text` 中逐字出现。",
        "",
        f"- 总计：**{len(rows)}**",
        "- 分系列：" + ", ".join(f"`{series}`={count}" for series, count in sorted(counter.items())),
        "",
        "| 系列 | card_id | abilities 数 | template_types | effect 文本 |",
        "| --- | --- | ---: | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| {row.series} | {row.card_id} | {row.ability_count} | "
            f"{', '.join(row.template_types)} | {row.effect_text} |"
        )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cards-root", type=Path, default=Path("data/cards"))
    parser.add_argument("--out-md", type=Path, default=None)
    parser.add_argument("--write-json", type=Path, default=None)
    parser.add_argument("--max-total", type=int, default=None)
    parser.add_argument(
        "--max-series",
        action="append",
        default=[],
        help="Per-series ceiling, format SERIES=COUNT. Repeatable.",
    )
    args = parser.parse_args()

    rows = collect_candidates(args.cards_root)
    counter = Counter(row.series for row in rows)

    print(f"HIGH_CONFIDENCE_EFFECT_DROPS={len(rows)}")
    for series in sorted(counter):
        print(f"SERIES_EFFECT_DROPS[{series}]={counter[series]}")

    if args.out_md:
        args.out_md.write_text(_to_markdown(rows), encoding="utf-8")
    if args.write_json:
        payload = {
            "total": len(rows),
            "by_series": {series: counter[series] for series in sorted(counter)},
            "items": [
                {
                    "series": row.series,
                    "card_id": row.card_id,
                    "effect_text": row.effect_text,
                    "ability_count": row.ability_count,
                    "template_types": row.template_types,
                }
                for row in rows
            ],
        }
        args.write_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    failed = False
    if args.max_total is not None and len(rows) > args.max_total:
        print(
            f"EFFECT_COVERAGE_CHECK_FAILED: total {len(rows)} exceeded max_total {args.max_total}."
        )
        failed = True

    for item in args.max_series:
        series, raw_limit = item.split("=", 1)
        series = series.strip()
        limit = int(raw_limit.strip())
        current = counter.get(series, 0)
        if current > limit:
            print(
                f"EFFECT_COVERAGE_CHECK_FAILED: series {series} has {current} > {limit}."
            )
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
