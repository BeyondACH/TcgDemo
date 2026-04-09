import io
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

import download_mmm_images as script


class DownloadMmmImagesTests(unittest.TestCase):
    def test_build_source_url_uses_selected_work_and_product(self) -> None:
        url = script.build_source_url(
            work="东京喰种",
            product="补充包 东京喰种【UAxxBT】",
            color="紫",
            limit=50,
        )

        self.assertIn("works=%E4%B8%9C%E4%BA%AC%E5%96%B0%E7%A7%8D", url)
        self.assertIn(
            "good=%E8%A1%A5%E5%85%85%E5%8C%85+%E4%B8%9C%E4%BA%AC%E5%96%B0%E7%A7%8D%E3%80%90UAxxBT%E3%80%91",
            url,
        )
        self.assertIn("color=%E7%B4%AB", url)
        self.assertIn("limit=50", url)

    def test_extract_products_from_jp_cardlist_html_keeps_order_and_skips_empty_values(
        self,
    ) -> None:
        html = """
        <html>
          <body>
            <select name="series" id="series">
              <option value="">商品名を選択</option>
              <option value="">指定無し</option>
              <option value="11">ブースターパック 魔法少女まどか☆マギカ【UA31BT】</option>
              <option value="22">スタートデッキ 魔法少女まどか☆マギカ【UA31ST】</option>
            </select>
          </body>
        </html>
        """

        self.assertEqual(
            script.extract_products_from_jp_cardlist_html(html),
            [
                {
                    "id": "11",
                    "name": "ブースターパック 魔法少女まどか☆マギカ【UA31BT】",
                },
                {
                    "id": "22",
                    "name": "スタートデッキ 魔法少女まどか☆マギカ【UA31ST】",
                },
            ],
        )

    def test_extract_products_from_jp_cardlist_html_deduplicates_by_first_value(
        self,
    ) -> None:
        html = """
        <select name="series" id="series">
          <option value="11">first product</option>
          <option value="11">second product</option>
          <option value="22">third product</option>
        </select>
        """

        self.assertEqual(
            script.extract_products_from_jp_cardlist_html(html),
            [
                {"id": "11", "name": "first product"},
                {"id": "22", "name": "third product"},
            ],
        )

    def test_extract_titles_from_html_only_reads_real_title_nodes(self) -> None:
        html = """
        <ul class="annotation">
          <li>ignore me</li>
        </ul>
        <div id="title_list">
          <div class="title">魔法少女小圆</div>
          <div class="title">东京喰种</div>
        </div>
        """

        self.assertEqual(
            script.extract_titles_from_html(html),
            ["魔法少女小圆", "东京喰种"],
        )

    def test_extract_titles_from_cardlist_html_fallback_uses_work_select(self) -> None:
        html = """
        <select name="title" id="title">
          <option value="">作品名を選択</option>
          <option value="madoka">魔法少女小圆</option>
          <option value="tokyo-ghoul">东京喰种</option>
        </select>
        """

        self.assertEqual(
            script.extract_titles_from_cardlist_html(html),
            ["魔法少女小圆", "东京喰种"],
        )

    def test_main_list_products_prompts_for_index_and_downloads_selected_product(
        self,
    ) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()

        with (
            patch.object(
                script,
                "get_official_products",
                return_value=[
                    {"id": "11", "name": "商品A"},
                    {"id": "22", "name": "商品B"},
                ],
            ) as get_products,
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
                "2. 商品B [22]",
            ],
        )
        get_products.assert_called_once_with()
        mkdir.assert_called_once()
        self.assertIn("No images found in the response.", stderr.getvalue())
        self.assertEqual(script.SOURCE_URL, script.build_source_url(work="作品X", product="商品B"))

    def test_main_list_products_rejects_invalid_index(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()

        with (
            patch.object(
                script,
                "get_official_products",
                return_value=[
                    {"id": "11", "name": "商品A"},
                    {"id": "22", "name": "商品B"},
                ],
            ),
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


if __name__ == "__main__":
    unittest.main()
