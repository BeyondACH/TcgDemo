#!/usr/bin/env python3
"""全量/增量编译一致性检查脚本（P3 门禁）。"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def _iter_series_dirs(cards_root: Path) -> list[Path]:
    series_dirs: list[Path] = []
    if not cards_root.exists():
        return series_dirs
    for child in sorted(cards_root.iterdir()):
        if child.is_dir() and (child / "cards_raw.json").exists():
            series_dirs.append(child)
    return series_dirs


def _load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def _snapshot_compiled_outputs(cards_root: Path) -> dict[str, dict[str, str]]:
    snapshot: dict[str, dict[str, str]] = {}
    for series_dir in _iter_series_dirs(cards_root):
        effects_path = series_dir / "cards_effects.json"
        semantic_path = series_dir / "cards_semantic.json"
        if not effects_path.exists() or not semantic_path.exists():
            continue
        effects_payload = _load_json(effects_path)
        semantic_payload = _load_json(semantic_path)
        snapshot[series_dir.name] = {
            "cards_effects": json.dumps(effects_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
            "cards_semantic": json.dumps(semantic_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
        }
    return snapshot


def _invalidate_series_outputs(cards_root: Path) -> int:
    removed_count = 0
    for series_dir in _iter_series_dirs(cards_root):
        for output_name in ("cards_effects.json", "cards_semantic.json"):
            output_path = series_dir / output_name
            if output_path.exists():
                output_path.unlink()
                removed_count += 1
    return removed_count


def _diff_snapshots(baseline: dict[str, dict[str, str]], current: dict[str, dict[str, str]]) -> dict[str, list[str]]:
    all_series = sorted(set(baseline.keys()) | set(current.keys()))
    changed: dict[str, list[str]] = {}
    for series in all_series:
        baseline_entry = baseline.get(series, {})
        current_entry = current.get(series, {})
        series_changed: list[str] = []
        for key in ("cards_effects", "cards_semantic"):
            if baseline_entry.get(key) != current_entry.get(key):
                series_changed.append(key)
        if series_changed:
            changed[series] = series_changed
    return changed


def _run_compile(repo_root: Path, *, no_incremental: bool, incremental_cache: Path, metrics_snapshot: Path) -> int:
    cmd = [
        sys.executable,
        "tools/compile_cards_effects.py",
        "--incremental-cache",
        str(incremental_cache),
        "--metrics-snapshot",
        str(metrics_snapshot),
    ]
    if no_incremental:
        cmd.append("--no-incremental")
    print("[P3-CHECK]", " ".join(cmd))
    return subprocess.run(cmd, cwd=repo_root).returncode


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify compile_cards_effects output consistency between full and incremental modes.")
    parser.add_argument(
        "--incremental-cache",
        type=Path,
        default=Path(".cache/card_effects_compiler/series_compile_cache.consistency.json"),
        help="cache path used during consistency check",
    )
    parser.add_argument("--keep-cache", action="store_true", help="keep generated cache file after check")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    cards_root = repo_root / "data" / "cards"
    cache_path = repo_root / args.incremental_cache if not args.incremental_cache.is_absolute() else args.incremental_cache

    with tempfile.TemporaryDirectory(prefix="p3_consistency_") as tmpdir:
        tmpdir_path = Path(tmpdir)
        full_metrics = tmpdir_path / "metrics_full.json"
        incremental_metrics = tmpdir_path / "metrics_incremental.json"

        if _run_compile(
            repo_root,
            no_incremental=True,
            incremental_cache=cache_path,
            metrics_snapshot=full_metrics,
        ) != 0:
            return 1
        full_snapshot = _snapshot_compiled_outputs(cards_root)
        removed_outputs = _invalidate_series_outputs(cards_root)
        print(f"[P3-CHECK] Removed {removed_outputs} compiled artifacts before incremental run.")

        if _run_compile(
            repo_root,
            no_incremental=False,
            incremental_cache=cache_path,
            metrics_snapshot=incremental_metrics,
        ) != 0:
            return 1
        incremental_snapshot = _snapshot_compiled_outputs(cards_root)

    changed = _diff_snapshots(full_snapshot, incremental_snapshot)
    if changed:
        print("[P3-CHECK] FAILED: incremental outputs diverge from full compile.")
        for series, files in changed.items():
            print(f"- {series}: {', '.join(files)}")
        return 1

    print("[P3-CHECK] PASSED: incremental outputs match full compile.")
    if cache_path.exists() and not args.keep_cache:
        cache_path.unlink()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
