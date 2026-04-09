import unittest
from pathlib import Path
import sys

from tools.card_effects_compiler.normalization import normalize_japanese_text
from tools.card_effects_compiler.template_registry import dispatch_template_rules
from tools.card_effects_compiler.template_registry import dispatch_trigger_template
from tools.compile_cards_effects import _build_semantic_entry
from tools.compile_cards_effects import _TRIGGER_TEMPLATE_RULES


class CompileCardsEffectsTests(unittest.TestCase):
    def test_normalize_japanese_text_collapses_whitespace_without_losing_japanese_punctuation(self):
        raw_text = "  召喚\n\t条件。\r\nさらに続く　、\n  終了。  "

        self.assertEqual(
            normalize_japanese_text(raw_text),
            "召喚 条件。 さらに続く 、 終了。",
        )

    def test_dispatch_trigger_template_normalizes_preview_text_before_matching(self):
        card = {"id": "card-001"}
        trigger_entry = {
            "trigger": "ON_ENTER",
            "source_label": "test",
            "effect_box": "OUTER",
            "text": "  自分の山札の上から5枚見る。\nその中から〈鹿目 まどか〉を1枚まで公開し手札に加える。\r\n残りを望む順で自分の山札の下に置く。  手札に加えた場合、自分の手札を1枚場外に置く。  ",
        }

        ability = dispatch_trigger_template(card, trigger_entry, lambda _card, _entry: None)

        self.assertIsNotNone(ability)
        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(ability["steps"][0]["type"], "PREVIEW_TOP_DECK")

    def test_dispatch_template_rules_normalizes_preview_text_before_matching(self):
        card = {"id": "card-001"}
        trigger_entry = {
            "trigger": "ON_ENTER",
            "source_label": "test",
            "effect_box": "OUTER",
            "text": "  自分の山札の上から5枚見る。\nその中から〈鹿目 まどか〉を1枚まで公開し手札に加える。\r\n残りを望む順で自分の山札の下に置く。  手札に加えた場合、自分の手札を1枚場外に置く。  ",
        }

        ability = dispatch_template_rules(
            "trigger",
            _TRIGGER_TEMPLATE_RULES,
            card,
            trigger_entry,
            lambda _card, _entry: None,
        )

        self.assertIsNotNone(ability)
        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(ability["steps"][0]["type"], "PREVIEW_TOP_DECK")

    def test_script_style_trigger_dispatch_does_not_import_entrypoint_module(self):
        script_path = Path(__file__).resolve().parents[1] / "tools" / "compile_cards_effects.py"
        original_module = sys.modules.pop("tools.compile_cards_effects", None)
        try:
            source = script_path.read_text(encoding="utf-8")
            tail = '\nif __name__ == "__main__":\n    main()'
            tail_index = source.rfind(tail)
            if tail_index != -1:
                source = source[:tail_index]
            namespace = {"__name__": "__main__", "__file__": str(script_path), "__package__": "tools"}
            exec(compile(source, str(script_path), "exec"), namespace)

            ability = namespace["_compile_trigger"](
                {"id": "card-001"},
                {
                    "trigger": "ON_ENTER",
                    "source_label": "test",
                    "effect_box": "OUTER",
                    "text": "  自分の山札の上から5枚見る。\nその中から〈鹿目 まどか〉を1枚まで公開し手札に加える。\r\n残りを望む順で自分の山札の下に置く。  手札に加えた場合、自分の手札を1枚場外に置く。  ",
                },
                {},
            )

            self.assertNotIn("tools.compile_cards_effects", sys.modules)
            self.assertEqual(ability["status"], "SUPPORTED")
        finally:
            if original_module is not None:
                sys.modules["tools.compile_cards_effects"] = original_module
            else:
                sys.modules.pop("tools.compile_cards_effects", None)

    def test_build_semantic_entry_uses_unresolved_capabilities_contract(self):
        card_effects = {
            "id": "card-001",
            "analysis": {"source": "test-source"},
            "card_meta": {
                "keywords": ["STEP"],
                "text": {
                    "effect": "効果",
                    "trigger": "",
                    "rule": "",
                },
            },
            "abilities": [
                {
                    "id": "ability-1",
                    "timing": {"event": "ON_PLAY"},
                    "status": "UNSUPPORTED",
                    "ui": {"text": "効果"},
                    "unsupported_reason": "  一行目\n\t二行目。  ",
                }
            ],
        }

        entry = _build_semantic_entry(card_effects)

        self.assertEqual(entry["card_id"], "card-001")
        self.assertNotIn("source", entry)
        self.assertEqual(entry["origin"], "test-source")
        self.assertEqual(
            entry["source_text_jp"],
            {
                "effect": "効果",
                "trigger": "",
                "rule": "",
            },
        )
        self.assertIn("unresolved_capabilities", entry)
        self.assertNotIn("missing_capabilities", entry)
        self.assertEqual(entry["unresolved_capabilities"], ["一行目 二行目。"])

    def test_build_semantic_entry_emits_fallback_for_raw_text_without_abilities(self):
        card_effects = {
            "id": "card-002",
            "analysis": {"source": "test-source"},
            "card_meta": {
                "keywords": [],
                "text": {
                    "effect": "効果だけがある",
                    "trigger": "",
                    "rule": "",
                },
            },
            "abilities": [],
        }

        entry = _build_semantic_entry(card_effects)

        self.assertFalse(entry["can_be_expressed_by_dsl"])
        self.assertEqual(entry["unresolved_capabilities"], ["当前卡牌文本尚未映射为能力对象。"])


if __name__ == "__main__":
    unittest.main()
