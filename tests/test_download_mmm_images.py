import io
import subprocess
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

import download_images as script


class DownloadMmmImagesTests(unittest.TestCase):
    def test_build_source_url_uses_product_filter_link_shape(self) -> None:
        url = script.build_source_url(
            product="魔法少女小圆 补充包【UA31BT】",
            limit=50,
        )

        self.assertIn(
            "good=%E9%AD%94%E6%B3%95%E5%B0%91%E5%A5%B3%E5%B0%8F%E5%9C%86+%E8%A1%A5%E5%85%85%E5%8C%85%E3%80%90UA31BT%E3%80%91",
            url,
        )
        self.assertIn("limit=50", url)
        self.assertNotIn("works=", url)
        self.assertNotIn("color=", url)

    def test_extract_products_from_attr_data_keeps_order_and_skips_invalid_items(self) -> None:
        data = {
            "goods": [
                {"id": 11, "name": "魔法少女小圆 补充包【UA31BT】"},
                {"id": 22, "name": "魔法少女小圆 基本卡组【UA31ST】"},
                {"id": "", "name": "ignore empty id"},
                {"id": 33, "name": ""},
                {"name": "ignore missing id"},
            ]
        }

        self.assertEqual(
            script.extract_products_from_attr_data(data),
            [
                {"id": "11", "name": "魔法少女小圆 补充包【UA31BT】"},
                {"id": "22", "name": "魔法少女小圆 基本卡组【UA31ST】"},
            ],
        )

    def test_extract_products_from_attr_data_deduplicates_by_first_id(self) -> None:
        data = {
            "goods": [
                {"id": 11, "name": "first product"},
                {"id": 11, "name": "second product"},
                {"id": 22, "name": "third product"},
            ]
        }

        self.assertEqual(
            script.extract_products_from_attr_data(data),
            [
                {"id": "11", "name": "first product"},
                {"id": "22", "name": "third product"},
            ],
        )

    def test_extract_titles_from_attr_data_keeps_order_and_skips_invalid_items(self) -> None:
        data = {
            "works": [
                {"id": 4, "name": "CODE GEASS 反叛的鲁路修"},
                {"id": 5, "name": "咒术回战"},
                {"id": "", "name": "ignore empty id"},
                {"id": 6, "name": ""},
                {"name": "ignore missing id"},
            ]
        }

        self.assertEqual(
            script.extract_titles_from_attr_data(data),
            ["CODE GEASS 反叛的鲁路修", "咒术回战"],
        )

    def test_extract_titles_from_attr_data_raises_when_works_missing(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Failed to parse works"):
            script.extract_titles_from_attr_data({})

    def test_extract_products_from_attr_data_raises_when_goods_missing(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Failed to parse goods"):
            script.extract_products_from_attr_data({})

    def test_infer_work_from_product_prefers_longest_matching_title(self) -> None:
        works = ["東京喰種", "東京喰種トーキョーグール", "魔法少女まどか☆マギカ"]

        self.assertEqual(
            script.infer_work_from_product_name(
                "「東京喰種トーキョーグール」シリーズ〖UA47BT〗",
                works,
            ),
            "東京喰種トーキョーグール",
        )

    def test_main_list_products_prompts_for_index_and_downloads_selected_product(
        self,
    ) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()

        with (
            patch.object(
                script,
                "get_attr_goods",
                return_value=[
                    {"id": "11", "name": "商品A"},
                    {"id": "22", "name": "東京喰種トーキョーグール〖UA47BT〗"},
                ],
            ) as get_products,
            patch.object(
                script,
                "get_attr_works",
                return_value=["魔法少女小圆", "東京喰種トーキョーグール"],
            ) as get_titles,
            patch("builtins.input", return_value="2"),
            patch.object(script.Path, "mkdir") as mkdir,
            patch.object(script, "iter_image_urls", return_value=iter(())),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            exit_code = script.main(["--list-products", "--work", "作品X"])

        self.assertEqual(exit_code, 1)
        self.assertEqual(
            stdout.getvalue().splitlines(),
            [
                "Official products:",
                "1. 商品A [11]",
                "2. 東京喰種トーキョーグール〖UA47BT〗 [22]",
            ],
        )
        get_products.assert_called_once_with()
        get_titles.assert_called_once_with()
        mkdir.assert_called_once()
        self.assertIn("No images found in the response.", stderr.getvalue())
        self.assertEqual(
            script.SOURCE_URL,
            script.build_source_url(
                product="東京喰種トーキョーグール〖UA47BT〗",
            ),
        )

    def test_main_list_products_rejects_invalid_index(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()

        with (
            patch.object(
                script,
                "get_attr_goods",
                return_value=[
                    {"id": "11", "name": "商品A"},
                    {"id": "22", "name": "商品B"},
                ],
            ),
            patch.object(script, "get_attr_works", return_value=["作品A", "作品B"]),
            patch("builtins.input", return_value="9"),
            patch.object(
                script,
                "default_output_dir",
                side_effect=AssertionError("download flow should not run"),
            ),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            exit_code = script.main(["--list-products"])

        self.assertEqual(exit_code, 1)
        self.assertEqual(
            stdout.getvalue().splitlines(),
            [
                "Official products:",
                "1. 商品A [11]",
                "2. 商品B [22]",
            ],
        )
        self.assertIn("Invalid product number: 9", stderr.getvalue())

    def test_parse_args_rejects_list_title(self) -> None:
        stderr = io.StringIO()

        with self.assertRaises(SystemExit) as exc, redirect_stderr(stderr):
            script.parse_args(["--list-title"])

        self.assertEqual(exc.exception.code, 2)
        self.assertIn("unrecognized arguments: --list-title", stderr.getvalue())

    def test_help_output_does_not_list_title(self) -> None:
        result = subprocess.run(
            [sys.executable, "download_images.py", "--help"],
            cwd="D:\\CodexWork\\TcgDemo",
            capture_output=True,
            text=True,
            encoding="utf-8",
        )

        self.assertEqual(result.returncode, 0)
        self.assertIn("--list-products", result.stdout)
        self.assertNotIn("--list-title", result.stdout)

    def test_prompt_for_product_selection_handles_non_utf8_stdout(self) -> None:
        stdout_buffer = io.BytesIO()
        stdout = io.TextIOWrapper(stdout_buffer, encoding="gbk", errors="strict")

        with (
            patch.object(sys, "stdout", stdout),
            patch("builtins.input", return_value="1"),
        ):
            selected = script.prompt_for_product_selection(
                [{"id": "11", "name": "魔法少女まどか・マギカ 【UA31BT】"}]
            )

        stdout.flush()
        output = stdout_buffer.getvalue().decode("gbk")
        self.assertEqual(selected, {"id": "11", "name": "魔法少女まどか・マギカ 【UA31BT】"})
        self.assertIn("Official products:", output)
        self.assertIn(r"\u30fb", output)

    def test_main_list_products_fails_when_selected_product_has_no_matching_work(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()

        with (
            patch.object(
                script,
                "get_attr_goods",
                return_value=[{"id": "11", "name": "未知商品〖UA99BT〗"}],
            ),
            patch.object(script, "get_attr_works", return_value=["魔法少女小圆"]),
            patch("builtins.input", return_value="1"),
            patch.object(
                script,
                "default_output_dir",
                side_effect=AssertionError("download flow should not run"),
            ),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            exit_code = script.main(["--list-products"])

        self.assertEqual(exit_code, 1)
        self.assertEqual(
            stdout.getvalue().splitlines(),
            [
                "Official products:",
                "1. 未知商品〖UA99BT〗 [11]",
            ],
        )
        self.assertIn("Could not infer work for selected product", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
