import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.check_compile_incremental_consistency import _diff_snapshots, _invalidate_series_outputs


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

    def test_invalidate_series_outputs_removes_only_compiled_artifacts(self):
        with TemporaryDirectory() as tmpdir:
            cards_root = Path(tmpdir)
            series_dir = cards_root / "MMM"
            series_dir.mkdir()
            (series_dir / "cards_raw.json").write_text("[]", encoding="utf-8")
            (series_dir / "cards_effects.json").write_text("{}", encoding="utf-8")
            (series_dir / "cards_semantic.json").write_text("{}", encoding="utf-8")
            (series_dir / "extra.json").write_text("{}", encoding="utf-8")

            removed_count = _invalidate_series_outputs(cards_root)

            self.assertEqual(removed_count, 2)
            self.assertFalse((series_dir / "cards_effects.json").exists())
            self.assertFalse((series_dir / "cards_semantic.json").exists())
            self.assertTrue((series_dir / "cards_raw.json").exists())
            self.assertTrue((series_dir / "extra.json").exists())


if __name__ == "__main__":
    unittest.main()
