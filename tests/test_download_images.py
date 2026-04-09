import io
import subprocess
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path

import download_images as script


class DownloadImagesTests(unittest.TestCase):
    def test_default_output_dir_uses_title_code_subdirectory(self) -> None:
        output_dir = script.default_output_dir("MMM")

        expected_dir = Path(script.__file__).resolve().parent / "pic" / "MMM"
        self.assertEqual(output_dir, expected_dir)

    def test_help_output_mentions_title_code_directory(self) -> None:
        result = subprocess.run(
            [sys.executable, "download_images.py", "--help"],
            cwd="D:\\CodexWork\\TcgDemo",
            capture_output=True,
            text=True,
            encoding="utf-8",
        )

        self.assertEqual(result.returncode, 0)
        help_output = " ".join(result.stdout.split())
        self.assertIn("--title-code", result.stdout)
        self.assertIn("Defaults to pic/<title_code>.", help_output)

    def test_parse_args_rejects_missing_title_code_value(self) -> None:
        stderr = io.StringIO()

        with self.assertRaises(SystemExit) as exc, redirect_stderr(stderr):
            script.parse_args(["--title-code"])

        self.assertEqual(exc.exception.code, 2)
        self.assertIn("expected one argument", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
