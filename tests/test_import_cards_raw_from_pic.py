import subprocess
import unittest
import shutil
from pathlib import Path


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


if __name__ == "__main__":
    unittest.main()
