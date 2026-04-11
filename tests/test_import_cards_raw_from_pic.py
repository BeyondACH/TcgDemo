import subprocess
import unittest
import shutil
from pathlib import Path

from tools.import_cards_raw_from_pic import parse_card_page


class ImportCardsRawFromPicTests(unittest.TestCase):
    def test_script_scans_title_code_subdirectories(self) -> None:
        repo_root = Path("D:\\CodexWork\\TcgDemo\\tests\\artifacts\\import_cards_raw_from_pic_case")
        if repo_root.exists():
            shutil.rmtree(repo_root)
        repo_root.mkdir(parents=True)
        try:
            pic_root = repo_root / "pic"
            cards_root = repo_root / "data" / "cards"
            title_dir = pic_root / "TLR"
            title_dir.mkdir(parents=True)
            cards_root.mkdir(parents=True)
            (title_dir / "UA45BT-TLR-1-001.png").write_bytes(b"not-a-real-image")

            result = subprocess.run(
                [
                    "powershell",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    "tools/import_cards_raw_from_pic.ps1",
                    "-PicRoot",
                    str(pic_root),
                    "-CardsRoot",
                    str(cards_root),
                ],
                cwd="D:\\CodexWork\\TcgDemo",
                capture_output=True,
                text=True,
                encoding="utf-8",
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("scanned=1", result.stdout)
        finally:
            if repo_root.exists():
                shutil.rmtree(repo_root)

    def test_parse_card_page_preserves_color_cost_energy_map(self) -> None:
        html = """
        <h2 class="cardNameCol">テストカード<span class="rubyData">てすと</span></h2>
        <span class="cardNumData">UA01BT/ABC-001</span>
        <span class="rareData">R</span>
        <dd class="cardDataTitleCol"><img alt="TEST" /></dd>
        <dl class="cardDataCol categoryData"><dd class="cardDataContents">キャラクター</dd></dl>
        <dl class="cardDataCol needEnergyData"><dd class="cardDataContents"><img alt="赤1"/><img alt="青2"/></dd></dl>
        <dl class="cardDataCol apData"><dd class="cardDataContents">1</dd></dl>
        <dl class="cardDataCol generatedEnergyData"><dd class="cardDataContents"><img alt="赤1"/></dd></dl>
        <dl class="cardDataCol bpData"><dd class="cardDataContents">2000</dd></dl>
        """
        card = parse_card_page(html, "demo.png")
        self.assertEqual(card["cost_energy"], {"RED": 1, "BLUE": 2})

    def test_parse_card_page_routes_timed_effect_labels_to_triggers(self) -> None:
        html = """
        <h2 class="cardNameCol">テストカード<span class="rubyData">てすと</span></h2>
        <span class="cardNumData">UA01BT/ABC-002</span>
        <span class="rareData">U</span>
        <dd class="cardDataTitleCol"><img alt="TEST" /></dd>
        <dl class="cardDataCol categoryData"><dd class="cardDataContents">キャラクター</dd></dl>
        <dl class="cardDataCol needEnergyData"><dd class="cardDataContents"><img alt="赤1"/></dd></dl>
        <dl class="cardDataCol effectData"><dd class="cardDataContents"><img alt="登場時"/>1枚引く<br/><img alt="起動メイン"/>このターン中+1000</dd></dl>
        <dl class="cardDataCol triggerData"><dd class="cardDataContents">-</dd></dl>
        """
        card = parse_card_page(html, "demo.png")
        self.assertEqual(len(card["effects"]), 0)
        self.assertEqual(
            [entry["trigger"] for entry in card["trigger_effects"]],
            ["ON_ENTER", "MAIN_ACTIVATE"],
        )


if __name__ == "__main__":
    unittest.main()
