import unittest
from pathlib import Path
import json
import subprocess
import sys
import tempfile

from tools.check_unsupported_budget import (
    BudgetSummary,
    parse_series_limits,
    validate_budget,
)


class CheckUnsupportedBudgetTests(unittest.TestCase):
    def test_parse_series_limits(self):
        parsed = parse_series_limits(["MCR=39", "TLR=21"])
        self.assertEqual(parsed, {"MCR": 39, "TLR": 21})

    def test_validate_budget_detects_total_and_series_regression(self):
        summary = BudgetSummary(
            total_unsupported=10,
            per_series_unsupported={"MCR": 8, "TLR": 2},
        )
        errors = validate_budget(summary, max_total=9, max_series={"MCR": 7, "TLR": 2})
        self.assertEqual(
            errors,
            [
                "Total unsupported 10 exceeded max_total 9.",
                "Series MCR unsupported 8 exceeded series limit 7.",
            ],
        )

    def test_script_writes_summary_and_passes_when_within_budget(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            cards_root = Path(temp_dir) / "cards"
            series_dir = cards_root / "MCR"
            series_dir.mkdir(parents=True)
            (series_dir / "cards_effects.json").write_text(
                json.dumps(
                    [
                        {"id": "C1", "abilities": [{"status": "SUPPORTED"}]},
                        {"id": "C2", "abilities": [{"status": "UNSUPPORTED"}]},
                    ],
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            out_path = Path(temp_dir) / "summary.json"

            result = subprocess.run(
                [
                    sys.executable,
                    "tools/check_unsupported_budget.py",
                    "--cards-root",
                    str(cards_root),
                    "--max-total",
                    "1",
                    "--max-series",
                    "MCR=1",
                    "--write-json",
                    str(out_path),
                ],
                cwd=Path(__file__).resolve().parents[1],
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertIn("BUDGET_CHECK_OK", result.stdout)
            summary = json.loads(out_path.read_text(encoding="utf-8"))
            self.assertEqual(summary["total_unsupported"], 1)
            self.assertEqual(summary["per_series_unsupported"]["MCR"], 1)


if __name__ == "__main__":
    unittest.main()
