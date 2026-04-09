import unittest
from pathlib import Path

import download_images as script


class DownloadImagesTests(unittest.TestCase):
    def test_default_output_dir_uses_work_subdirectory_without_color(self) -> None:
        work_name = "作品名称"
        output_dir = script.default_output_dir(work_name, "紫")

        expected_dir = Path(script.__file__).resolve().parent / "pic" / work_name
        self.assertEqual(output_dir, expected_dir)


if __name__ == "__main__":
    unittest.main()
