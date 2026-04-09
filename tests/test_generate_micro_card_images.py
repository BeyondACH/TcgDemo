import subprocess
import unittest
import shutil
from pathlib import Path


class GenerateMicroCardImagesTests(unittest.TestCase):
    def test_script_generates_micro_images_inside_title_code_directory(self) -> None:
        repo_root = Path("D:\\CodexWork\\TcgDemo\\tests\\artifacts\\generate_micro_card_images_case")
        if repo_root.exists():
            shutil.rmtree(repo_root)
        repo_root.mkdir(parents=True)
        try:
            source_root = repo_root / "pic"
            title_dir = source_root / "MMM"
            title_dir.mkdir(parents=True)
            self._write_sample_png(title_dir / "UA31BT-MMM-1-001.png")

            result = subprocess.run(
                [
                    "powershell",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    "tools/generate_micro_card_images.ps1",
                    "-SourceRoot",
                    str(source_root),
                ],
                cwd="D:\\CodexWork\\TcgDemo",
                capture_output=True,
                text=True,
                encoding="utf-8",
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertTrue((title_dir / "micro" / "UA31BT-MMM-1-001.png").exists())
            self.assertIn("scanned=1", result.stdout)
            self.assertIn("generated=1", result.stdout)
        finally:
            if repo_root.exists():
                shutil.rmtree(repo_root)

    @staticmethod
    def _write_sample_png(path: Path) -> None:
        png_bytes = bytes.fromhex(
            "89504E470D0A1A0A"
            "0000000D49484452000000010000000108060000001F15C489"
            "0000000D49444154789C63F8CFC0F01F00050001FF89993D1D"
            "0000000049454E44AE426082"
        )
        path.write_bytes(png_bytes)
