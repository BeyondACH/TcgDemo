import unittest

from tools.compile_cards_effects import _build_semantic_entry
from tools.compile_cards_effects import normalize_compiler_text


class CompileCardsEffectsTests(unittest.TestCase):
    def test_normalize_compiler_text_collapses_whitespace_without_losing_japanese_punctuation(self):
        raw_text = "  召喚\n\t条件。\r\nさらに続く　、\n  終了。  "

        self.assertEqual(
            normalize_compiler_text(raw_text),
            "召喚 条件。 さらに続く 、 終了。",
        )

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
        self.assertIn("unresolved_capabilities", entry)
        self.assertNotIn("missing_capabilities", entry)
        self.assertEqual(entry["unresolved_capabilities"], ["一行目 二行目。"])


if __name__ == "__main__":
    unittest.main()
