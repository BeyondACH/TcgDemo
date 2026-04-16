import unittest

from tools.check_compile_incremental_consistency import _diff_snapshots


class CheckCompileIncrementalConsistencyTests(unittest.TestCase):
    def test_diff_snapshots_empty_when_identical(self):
        baseline = {
            "MMM": {"cards_effects": "a", "cards_semantic": "b"},
        }
        current = {
            "MMM": {"cards_effects": "a", "cards_semantic": "b"},
        }
        self.assertEqual(_diff_snapshots(baseline, current), {})

    def test_diff_snapshots_reports_changed_files(self):
        baseline = {
            "MMM": {"cards_effects": "a", "cards_semantic": "b"},
            "TLR": {"cards_effects": "x", "cards_semantic": "y"},
        }
        current = {
            "MMM": {"cards_effects": "a2", "cards_semantic": "b"},
            "TLR": {"cards_effects": "x", "cards_semantic": "y2"},
        }
        self.assertEqual(
            _diff_snapshots(baseline, current),
            {
                "MMM": ["cards_effects"],
                "TLR": ["cards_semantic"],
            },
        )

    def test_diff_snapshots_reports_missing_series(self):
        baseline = {"MMM": {"cards_effects": "a", "cards_semantic": "b"}}
        current = {}
        self.assertEqual(_diff_snapshots(baseline, current), {"MMM": ["cards_effects", "cards_semantic"]})


if __name__ == "__main__":
    unittest.main()
