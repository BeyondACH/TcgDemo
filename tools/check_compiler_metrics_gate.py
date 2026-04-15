#!/usr/bin/env python3
"""Validate compiler template telemetry against migration gate thresholds."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", type=Path, default=Path("docs/plan/compiler_metrics_snapshot.json"))
    parser.add_argument("--gate", type=Path, default=Path("docs/plan/compiler_metrics_gate.json"))
    args = parser.parse_args()

    snapshot = json.loads(args.snapshot.read_text(encoding="utf-8"))
    gate = json.loads(args.gate.read_text(encoding="utf-8"))
    telemetry = snapshot.get("template_telemetry", {})
    family_hits = telemetry.get("family_hits", {})

    violations: list[str] = []
    fallback_ratio = float(telemetry.get("fallback_ratio", 1.0))
    max_fallback_ratio = float(gate.get("max_fallback_ratio", 1.0))
    if fallback_ratio > max_fallback_ratio:
        violations.append(
            f"fallback_ratio {fallback_ratio:.6f} exceeds max_fallback_ratio {max_fallback_ratio:.6f}"
        )

    conflict_count = int(telemetry.get("conflict_count", 0))
    max_conflict_count = int(gate.get("max_conflict_count", 0))
    if conflict_count > max_conflict_count:
        violations.append(f"conflict_count {conflict_count} exceeds max_conflict_count {max_conflict_count}")

    for family, min_hits in gate.get("required_family_hits", {}).items():
        hits = int(family_hits.get(family, 0))
        if hits < int(min_hits):
            violations.append(f"family_hits[{family}]={hits} is below required minimum {int(min_hits)}")

    if violations:
        print("COMPILER_METRICS_GATE_FAILED")
        for line in violations:
            print(f"- {line}")
        return 1

    print("COMPILER_METRICS_GATE_OK")
    print(
        "summary:",
        f"fallback_ratio={fallback_ratio:.6f}",
        f"conflict_count={conflict_count}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
