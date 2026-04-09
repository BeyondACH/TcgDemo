import io
import subprocess
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

import download_images as script


class DownloadImagesTests(unittest.TestCase):
    def test_build_source_url_prefers_works_filter_when_provided(self) -> None:
        url = script.build_source_url(works="作品A", limit=50)

        self.assertIn("works=%E4%BD%9C%E5%93%81A", url)
        self.assertIn("limit=50", url)
        self.assertNotIn("good=", url)

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
        self.assertIn("--list-works", result.stdout)
        self.assertIn("Defaults to pic/<title_code>.", help_output)

    def test_parse_args_rejects_missing_title_code_value(self) -> None:
        stderr = io.StringIO()

        with self.assertRaises(SystemExit) as exc, redirect_stderr(stderr):
            script.parse_args(["--title-code"])

        self.assertEqual(exc.exception.code, 2)
        self.assertIn("expected one argument", stderr.getvalue())

    def test_main_list_works_prompts_for_index_and_downloads_selected_work(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()

        with (
            patch.object(
                script,
                "get_attr_works",
                return_value=["作品A", "作品B"],
            ) as get_works,
            patch("builtins.input", return_value="2"),
            patch.object(script.Path, "mkdir") as mkdir,
            patch.object(script, "iter_image_urls", return_value=iter(())),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            exit_code = script.main(["--list-works"])

        self.assertEqual(exit_code, 1)
        self.assertEqual(
            stdout.getvalue().splitlines(),
            [
                "Official works:",
                "1. 作品A",
                "2. 作品B",
            ],
        )
        get_works.assert_called_once_with()
        mkdir.assert_called_once()
        self.assertIn("No images found in the response.", stderr.getvalue())
        self.assertEqual(
            script.SOURCE_URL,
            script.build_source_url(works="作品B"),
        )


if __name__ == "__main__":
    unittest.main()
