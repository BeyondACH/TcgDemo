import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tools.check_compiler_metrics_gate import _collect_family_conflict_hits


class CheckCompilerMetricsGateTests(unittest.TestCase):
    def test_collect_family_conflict_hits_sums_hit_count_per_family(self):
        telemetry = {
            "conflicts": [
                {"hit_count": 2, "candidate_families": ["DRAW_SEQUENCE", "AP_ACTIVATE"]},
                {"hit_count": 3, "candidate_families": ["DRAW_SEQUENCE"]},
            ]
        }

        hits = _collect_family_conflict_hits(telemetry)

        self.assertEqual(hits["DRAW_SEQUENCE"], 5)
        self.assertEqual(hits["AP_ACTIVATE"], 2)

    def test_script_blocks_new_conflict_key_and_rule_order_diff(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            baseline_path = temp_path / "baseline.json"
            snapshot_path = temp_path / "current.json"
            gate_path = temp_path / "gate.json"

            baseline_payload = {
                "template_telemetry": {
                    "fallback_ratio": 0.5,
                    "conflict_count": 1,
                    "conflicts": [
                        {
                            "registry": "event",
                            "event": "ON_PLAY",
                            "text": "A",
                            "hit_count": 1,
                            "candidate_families": ["DRAW_SEQUENCE"],
                        }
                    ],
                    "rule_order_diff": {},
                    "family_hits": {"DRAW_SEQUENCE": 2},
                }
            }
            current_payload = {
                "template_telemetry": {
                    "fallback_ratio": 0.5,
                    "conflict_count": 2,
                    "conflicts": [
                        {
                            "registry": "event",
                            "event": "ON_PLAY",
                            "text": "A",
                            "hit_count": 1,
                            "candidate_families": ["DRAW_SEQUENCE"],
                        },
                        {
                            "registry": "event",
                            "event": "ON_PLAY",
                            "text": "B",
                            "hit_count": 1,
                            "candidate_families": ["AP_ACTIVATE"],
                        },
                    ],
                    "rule_order_diff": {"event": [{"index": 0, "old": "a", "new": "b"}]},
                    "family_hits": {"DRAW_SEQUENCE": 2, "AP_ACTIVATE": 1},
                }
            }
            gate_payload = {
                "max_fallback_ratio": 0.9,
                "max_conflict_count": 3,
                "max_conflict_delta": 0,
                "forbid_new_conflict_keys": True,
                "block_on_rule_order_diff": True,
                "allowed_rule_order_diff_registries": [],
                "protected_families_no_new_conflicts": ["AP_ACTIVATE"],
                "required_family_hits": {"DRAW_SEQUENCE": 1, "AP_ACTIVATE": 1},
            }

            baseline_path.write_text(json.dumps(baseline_payload, ensure_ascii=False), encoding="utf-8")
            snapshot_path.write_text(json.dumps(current_payload, ensure_ascii=False), encoding="utf-8")
            gate_path.write_text(json.dumps(gate_payload, ensure_ascii=False), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    "tools/check_compiler_metrics_gate.py",
                    "--snapshot",
                    str(snapshot_path),
                    "--baseline-snapshot",
                    str(baseline_path),
                    "--gate",
                    str(gate_path),
                ],
                cwd=Path(__file__).resolve().parents[1],
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("COMPILER_METRICS_GATE_FAILED", result.stdout)
            self.assertIn("new_conflict_keys detected", result.stdout)
            self.assertIn("rule_order_diff blocked registries", result.stdout)
            self.assertIn("family_conflict_hits[AP_ACTIVATE] increased", result.stdout)

    def test_script_passes_when_within_baseline_constraints(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            baseline_path = temp_path / "baseline.json"
            snapshot_path = temp_path / "current.json"
            gate_path = temp_path / "gate.json"

            payload = {
                "template_telemetry": {
                    "fallback_ratio": 0.4,
                    "conflict_count": 1,
                    "conflicts": [
                        {
                            "registry": "event",
                            "event": "ON_PLAY",
                            "text": "A",
                            "hit_count": 2,
                            "candidate_families": ["DRAW_SEQUENCE"],
                        }
                    ],
                    "rule_order_diff": {},
                    "family_hits": {"DRAW_SEQUENCE": 3},
                }
            }
            gate_payload = {
                "max_fallback_ratio": 0.9,
                "max_conflict_count": 2,
                "max_conflict_delta": 0,
                "forbid_new_conflict_keys": True,
                "block_on_rule_order_diff": True,
                "allowed_rule_order_diff_registries": [],
                "protected_families_no_new_conflicts": ["DRAW_SEQUENCE"],
                "required_family_hits": {"DRAW_SEQUENCE": 1},
            }

            baseline_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            snapshot_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            gate_path.write_text(json.dumps(gate_payload, ensure_ascii=False), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    "tools/check_compiler_metrics_gate.py",
                    "--snapshot",
                    str(snapshot_path),
                    "--baseline-snapshot",
                    str(baseline_path),
                    "--gate",
                    str(gate_path),
                ],
                cwd=Path(__file__).resolve().parents[1],
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertIn("COMPILER_METRICS_GATE_OK", result.stdout)


if __name__ == "__main__":
    unittest.main()
