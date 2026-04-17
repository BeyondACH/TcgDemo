#!/usr/bin/env python3
"""Validate compiler template telemetry against migration gate thresholds."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def _build_conflict_key(entry: dict) -> str:
    return f"{entry.get('registry', '')}|{entry.get('event', '')}|{entry.get('text', '')}"


def _collect_conflict_keys(telemetry: dict) -> set[str]:
    conflicts = telemetry.get("conflicts", [])
    if not isinstance(conflicts, list):
        return set()
    return {_build_conflict_key(entry) for entry in conflicts if isinstance(entry, dict)}


def _collect_family_conflict_hits(telemetry: dict) -> dict[str, int]:
    hits: dict[str, int] = {}
    conflicts = telemetry.get("conflicts", [])
    if not isinstance(conflicts, list):
        return hits
    for entry in conflicts:
        if not isinstance(entry, dict):
            continue
        families = entry.get("candidate_families", [])
        if not isinstance(families, list):
            continue
        hit_count = int(entry.get("hit_count", 0))
        for family in families:
            if not family:
                continue
            family_name = str(family)
            hits[family_name] = hits.get(family_name, 0) + hit_count
    return hits


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", type=Path, default=Path("docs/plan/compiler_metrics_snapshot.json"))
    parser.add_argument(
        "--baseline-snapshot",
        type=Path,
        default=Path("docs/plan/compiler_metrics_snapshot.json"),
        help="Baseline metrics snapshot for delta checks.",
    )
    parser.add_argument("--gate", type=Path, default=Path("docs/plan/compiler_metrics_gate.json"))
    args = parser.parse_args()

    snapshot = json.loads(args.snapshot.read_text(encoding="utf-8"))
    gate = json.loads(args.gate.read_text(encoding="utf-8"))
    baseline_snapshot = {}
    if args.baseline_snapshot.exists():
        baseline_snapshot = json.loads(args.baseline_snapshot.read_text(encoding="utf-8"))
    telemetry = snapshot.get("template_telemetry", {})
    baseline_telemetry = baseline_snapshot.get("template_telemetry", {}) if isinstance(baseline_snapshot, dict) else {}
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

    baseline_conflict_count = int(baseline_telemetry.get("conflict_count", conflict_count))
    max_conflict_delta = gate.get("max_conflict_delta")
    if max_conflict_delta is not None:
        allowed_delta = int(max_conflict_delta)
        conflict_delta = conflict_count - baseline_conflict_count
        if conflict_delta > allowed_delta:
            violations.append(
                f"conflict_delta {conflict_delta} exceeds max_conflict_delta {allowed_delta} "
                f"(baseline={baseline_conflict_count}, current={conflict_count})"
            )

    if bool(gate.get("forbid_new_conflict_keys", False)):
        baseline_keys = _collect_conflict_keys(baseline_telemetry)
        current_keys = _collect_conflict_keys(telemetry)
        new_keys = sorted(current_keys - baseline_keys)
        if new_keys:
            violations.append(f"new_conflict_keys detected: {len(new_keys)}")

    if bool(gate.get("block_on_rule_order_diff", False)):
        allowed_registries = {str(name) for name in gate.get("allowed_rule_order_diff_registries", [])}
        rule_order_diff = telemetry.get("rule_order_diff", {})
        if isinstance(rule_order_diff, dict):
            blocked = sorted(registry for registry in rule_order_diff.keys() if registry not in allowed_registries)
            if blocked:
                violations.append(f"rule_order_diff blocked registries: {blocked}")

    baseline_family_conflict_hits = _collect_family_conflict_hits(baseline_telemetry)
    current_family_conflict_hits = _collect_family_conflict_hits(telemetry)
    for family in gate.get("protected_families_no_new_conflicts", []):
        family_name = str(family)
        current_hits = int(current_family_conflict_hits.get(family_name, 0))
        baseline_hits = int(baseline_family_conflict_hits.get(family_name, 0))
        if current_hits > baseline_hits:
            violations.append(
                f"family_conflict_hits[{family_name}] increased from {baseline_hits} to {current_hits}"
            )

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
        f"baseline_conflict_count={baseline_conflict_count}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
