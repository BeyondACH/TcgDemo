#!/usr/bin/env python3
"""Check UNSUPPORTED ability budget and fail on regression."""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
import sys

if __package__ is None or __package__ == "":
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.report_support_stats import collect_stats


@dataclass
class BudgetSummary:
    total_unsupported: int
    per_series_unsupported: dict[str, int]


def build_summary(cards_root: Path) -> BudgetSummary:
    stats = collect_stats(cards_root)
    return BudgetSummary(
        total_unsupported=sum(item.unsupported for item in stats),
        per_series_unsupported={item.series: item.unsupported for item in stats},
    )


def parse_series_limits(raw_values: list[str]) -> dict[str, int]:
    limits: dict[str, int] = {}
    for raw in raw_values:
        if "=" not in raw:
            raise ValueError(f"Invalid --max-series format: {raw!r}. Expected SERIES=COUNT.")
        series, value = raw.split("=", 1)
        series = series.strip()
        if not series:
            raise ValueError(f"Invalid --max-series format: {raw!r}. Empty series name.")
        limits[series] = int(value.strip())
    return limits


def validate_budget(
    summary: BudgetSummary,
    max_total: int | None,
    max_series: dict[str, int],
) -> list[str]:
    errors: list[str] = []
    if max_total is not None and summary.total_unsupported > max_total:
        errors.append(
            f"Total unsupported {summary.total_unsupported} exceeded max_total {max_total}."
        )
    for series, limit in max_series.items():
        actual = summary.per_series_unsupported.get(series, 0)
        if actual > limit:
            errors.append(
                f"Series {series} unsupported {actual} exceeded series limit {limit}."
            )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cards-root", default="data/cards", type=Path)
    parser.add_argument("--max-total", type=int, default=None)
    parser.add_argument(
        "--max-series",
        action="append",
        default=[],
        help="Per-series unsupported ceiling, format SERIES=COUNT. Repeatable.",
    )
    parser.add_argument(
        "--write-json",
        type=Path,
        default=None,
        help="Optional path to write current unsupported summary.",
    )
    args = parser.parse_args()

    max_series = parse_series_limits(args.max_series)
    summary = build_summary(args.cards_root)
    errors = validate_budget(summary, args.max_total, max_series)

    print(f"TOTAL_UNSUPPORTED={summary.total_unsupported}")
    for series, count in sorted(summary.per_series_unsupported.items()):
        print(f"SERIES_UNSUPPORTED[{series}]={count}")

    if args.write_json:
        args.write_json.write_text(
            json.dumps(asdict(summary), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"WROTE_SUMMARY={args.write_json}")

    if errors:
        for error in errors:
            print(f"BUDGET_CHECK_FAILED: {error}")
        return 1

    print("BUDGET_CHECK_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
