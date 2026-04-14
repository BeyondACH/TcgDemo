#!/usr/bin/env python3
"""Phase 5 固定门禁执行器。

用途：
- 在本地或 CI 中一键执行 Phase 5 最小回归门禁；
- 避免漏跑关键命令导致 `UNSUPPORTED` 基线回退。
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def _commands(include_compile: bool, include_utf8: bool) -> list[list[str]]:
    commands: list[list[str]] = [
        [
            sys.executable,
            "-m",
            "unittest",
            "tests.test_compile_cards_effects",
            "tests.test_check_unsupported_budget",
            "tests.test_phase5_regression_guards",
        ],
    ]
    if include_compile:
        commands.extend(
            [
                [sys.executable, "tools/compile_cards_effects.py"],
                [sys.executable, "tools/report_support_stats.py"],
            ]
        )
    commands.append(
        [
            sys.executable,
            "tools/check_unsupported_budget.py",
            "--max-total",
            "0",
            "--max-series",
            "MCR=0",
            "--max-series",
            "TLR=0",
            "--max-series",
            "MMM=0",
            "--write-json",
            "docs/plan/unsupported_budget_baseline.json",
        ]
    )
    if include_utf8:
        commands.append([sys.executable, "tools/check_utf8_docs.py"])
    return commands


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Phase 5 guardrail checks.")
    parser.add_argument("--skip-compile", action="store_true", help="Skip compile/report commands.")
    parser.add_argument("--skip-utf8", action="store_true", help="Skip UTF-8 docs check.")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without executing.")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    commands = _commands(include_compile=not args.skip_compile, include_utf8=not args.skip_utf8)

    for cmd in commands:
        pretty = " ".join(cmd)
        print(f"[PHASE5] {pretty}")
        if args.dry_run:
            continue
        result = subprocess.run(cmd, cwd=repo_root)
        if result.returncode != 0:
            print(f"[PHASE5] FAILED: {pretty}")
            return result.returncode
    print("[PHASE5] ALL_CHECKS_PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

