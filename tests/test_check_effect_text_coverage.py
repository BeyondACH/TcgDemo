import json
import subprocess
import tempfile
import unittest
from pathlib import Path


class CheckEffectTextCoverageTests(unittest.TestCase):
    def test_detects_high_confidence_drop(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "cards" / "XAA"
            root.mkdir(parents=True)
            semantic = [
                {
                    "card_id": "XAA_001",
                    "template_types": ["READY_AND_TEMP_BP"],
                    "abilities": [
                        {
                            "text": "自分の場のキャラを1枚選び、アクティブにし、このターン中、BP+3000。",
                            "status": "SUPPORTED",
                        }
                    ],
                    "source_text_jp": {
                        "effect": "自分の場の他の［特徴：飛信隊］を1枚まで選び、このターン中、BP+1000。",
                        "trigger": "自分の場のキャラを1枚選び、アクティブにし、このターン中、BP+3000。",
                        "rule": "",
                    },
                }
            ]
            (root / "cards_semantic.json").write_text(
                json.dumps(semantic, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            out_json = Path(tmp) / "out.json"
            proc = subprocess.run(
                [
                    "python",
                    "tools/check_effect_text_coverage.py",
                    "--cards-root",
                    str(Path(tmp) / "cards"),
                    "--write-json",
                    str(out_json),
                    "--max-total",
                    "0",
                ],
                cwd=Path(__file__).resolve().parents[1],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(proc.returncode, 0)
            payload = json.loads(out_json.read_text(encoding="utf-8"))
            self.assertEqual(payload["total"], 1)
            self.assertEqual(payload["by_series"]["XAA"], 1)


if __name__ == "__main__":
    unittest.main()
