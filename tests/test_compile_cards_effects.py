import unittest
from pathlib import Path
import subprocess
import sys

from tools.card_effects_compiler.normalization import normalize_japanese_text
from tools.card_effects_compiler.template_registry import dispatch_template_rules
from tools.card_effects_compiler.template_registry import dispatch_trigger_template
from tools.compile_cards_effects import _build_semantic_entry
from tools.compile_cards_effects import _compile_event_effect
from tools.compile_cards_effects import _compile_event_effect_legacy
from tools.compile_cards_effects import _compile_trigger
from tools.compile_cards_effects import _compile_trigger_legacy
from tools.compile_cards_effects import _compile_series_cards
from tools.compile_cards_effects import _TRIGGER_TEMPLATE_RULES


class CompileCardsEffectsTests(unittest.TestCase):
    PREVIEW_ADD_TO_HAND_TEXT = (
        "\u81ea\u5206\u306e\u5c71\u672d\u306e\u4e0a\u304b\u30893\u679a\u898b\u308b\u3002"
        "\u305d\u306e\u4e2d\u304b\u3089\u3008\u767e\u6c5f \u306a\u304e\u3055\u3009\u304b"
        "\uff3b\u7279\u5fb4\uff1a\u30d4\u30e5\u30a8\u30e9\u30fb\u30de\u30ae\u30fb\u30db\u30fc\u30ea\u30fc"
        "\u30fb\u30af\u30a4\u30f3\u30c6\u30c3\u30c8\uff3d\u30921\u679a\u307e\u3067\u516c\u958b\u3057"
        "\u624b\u672d\u306b\u52a0\u3048\u308b\u3002\u6b8b\u308a\u3092\u671b\u3080\u9806\u3067\u81ea\u5206"
        "\u306e\u5c71\u672d\u306e\u4e0b\u306b\u7f6e\u304f\u3002\u624b\u672d\u306b\u52a0\u3048\u305f\u5834\u5408\u3001"
        "\u81ea\u5206\u306e\u624b\u672d\u30921\u679a\u5834\u5916\u306b\u7f6e\u304f\u3002"
    )
    BP_THRESHOLD_TEXT = (
        "\u300eBP3000\u4ee5\u4e0b\u300f\u306e\u76f8\u624b\u306e\u30d5\u30ed\u30f3\u30c8L\u306e\u30ad\u30e3\u30e9"
        "\u30921\u679a\u9078\u3073\u3001\u9000\u5834\u3055\u305b\u308b\u3002\u81ea\u5206\u306e\u5834\u306b"
        "\u3008\u9e7f\u76ee \u307e\u3069\u304b\u3009\u304c\u3042\u308b\u5834\u5408\u3001\u300eBP5000\u4ee5\u4e0b\u300f"
        "\u306b\u4ee3\u308f\u308b\u3002"
    )
    HOMURA_BP_THRESHOLD_TEXT = (
        "\u300eBP3000\u4ee5\u4e0b\u300f\u306e\u76f8\u624b\u306e\u30d5\u30ed\u30f3\u30c8L\u306e\u30ad\u30e3\u30e9"
        "\u30921\u679a\u9078\u3073\u3001\u9000\u5834\u3055\u305b\u308b\u3002\u81ea\u5206\u306e\u5834\u306b"
        "\u3008\u6681\u7f8e \u307b\u3080\u3089\u3009\u304c\u3042\u308b\u5834\u5408\u3001\u300eBP5000\u4ee5\u4e0b\u300f"
        "\u306b\u4ee3\u308f\u308b\u3002"
    )


    TLR_PREVIEW_ADD_TO_HAND_TEXT = (
        "自分の山札の上から3枚見て、必要エナジーが3以下のキャラカードを1枚まで公開し手札に加える。"
        "残りを望む順で山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"
    )
    TLR_BP_THRESHOLD_TEXT = (
        "『BP3000以下』の相手のフロントLのキャラを1枚選び、退場させる。"
        "自分の場に〈モモ・ベリア・デビルーク〉がある場合、『BP5000以下』に代わる。"
    )
    TLR_COMPLEX_OVERRIDE_TEXT = "BP5000以下の相手のフロントLのキャラを1枚選び、相手の山札の下に置く。"
    TLR_PREVIEW_TOP_CHOOSE_TEXT = "自分の山札の上から1枚見て、山札の上か下に置く。"
    TLR_CONDITIONAL_DRAW_TEXT = "自分の場に他のカードが5枚以上ある場合、カードを1枚引く。"
    TLR_OPTIONAL_AP_DAMAGE_TEXT = "相手のライフが4以上の場合、APを1支払ってもよい。そうした場合、相手に1ダメージ。"
    TLR_HAND_SUMMON_TEXT = "自分の手札から必要エナジーが3以下で消費APが1の黄の〈金色の闇〉を1枚まで自分の場にレストで登場させる。"
    TLR_BP_PLUS_TEXT = "自分の場の他のキャラを1枚選び、このターン中、BP+1000。"
    TLR_BRANCH_SELECT_ONE_TEXT = "以下から1つ選ぶ。"
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

    def test_compile_cards_effects_script_runs_from_workspace_root(self):
        result = subprocess.run(
            [sys.executable, "tools/compile_cards_effects.py"],
            cwd=Path(__file__).resolve().parents[1],
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("Compiled", result.stdout)

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
 
    def test_compile_trigger_assigns_preview_add_to_hand_family_metadata(self):
        ability = _compile_trigger(
            {"id": "UA31BT_MMM_1_043"},
            {
                "trigger": "ON_ENTER",
                "source_label": "登場時",
                "effect_box": "OUTER",
                "text": self.PREVIEW_ADD_TO_HAND_TEXT,
            },
            {},
        )

        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(
            ability["template_metadata"],
            {
                "family": "PREVIEW_ADD_TO_HAND",
                "variant": "preview_add_to_hand_discard_on_add",
            },
        )

        semantic_entry = _build_semantic_entry(
            {
                "id": "UA31BT_MMM_1_043",
                "analysis": {"source": "test-source"},
                "card_meta": {
                    "keywords": [],
                    "text": {"effect": "", "trigger": self.PREVIEW_ADD_TO_HAND_TEXT, "rule": ""},
                },
                "abilities": [ability],
            }
        )

        self.assertEqual(semantic_entry["template_types"], ["SELECT_AND_MOVE", "PREVIEW_ADD_TO_HAND"])
        self.assertEqual(semantic_entry["abilities"][0]["template_type"], "PREVIEW_ADD_TO_HAND")

    def test_compile_event_effect_assigns_bp_threshold_family_metadata(self):
        ability = _compile_event_effect(
            {"id": "UA31BT_MMM_1_094", "card_type": "EVENT"},
            {
                "source_label": "",
                "effect_box": "OUTER",
                "text": self.BP_THRESHOLD_TEXT,
            },
            {},
        )

        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(
            ability["template_metadata"],
            {
                "family": "BP_THRESHOLD_REMOVE",
                "variant": "bp_threshold_remove_dynamic_madoka",
            },
        )

        semantic_entry = _build_semantic_entry(
            {
                "id": "UA31BT_MMM_1_094",
                "analysis": {"source": "test-source"},
                "card_meta": {
                    "keywords": [],
                    "text": {"effect": self.BP_THRESHOLD_TEXT, "trigger": "", "rule": ""},
                },
                "abilities": [ability],
            }
        )

        self.assertEqual(semantic_entry["template_types"], ["SELECT_AND_MOVE", "BP_THRESHOLD_REMOVE"])
        self.assertEqual(semantic_entry["abilities"][0]["template_type"], "BP_THRESHOLD_REMOVE")

    def test_build_semantic_entry_extends_mixed_template_types_with_stable_family(self):
        semantic_entry = _build_semantic_entry(
            {
                "id": "UA31BT_MMM_1_007",
                "analysis": {"source": "test-source"},
                "card_meta": {
                    "keywords": [],
                    "text": {"effect": self.PREVIEW_ADD_TO_HAND_TEXT, "trigger": "dummy", "rule": ""},
                },
                "abilities": [
                    {
                        "id": "preview",
                        "timing": {"event": "ON_ENTER"},
                        "status": "SUPPORTED",
                        "requirements": [],
                        "target_specs": [],
                        "steps": [{"type": "PREVIEW_TOP_DECK"}, {"type": "SELECT_TARGETS"}, {"type": "MOVE_SELECTED_CARDS"}],
                        "limits": {},
                        "ui": {"text": self.PREVIEW_ADD_TO_HAND_TEXT},
                        "template_metadata": {
                            "family": "PREVIEW_ADD_TO_HAND",
                            "variant": "preview_add_to_hand_discard_on_add",
                        },
                    },
                    {
                        "id": "ready-bp",
                        "timing": {"event": "ON_LIFE_TRIGGER"},
                        "status": "SUPPORTED",
                        "requirements": [],
                        "target_specs": [],
                        "steps": [{"type": "ACTIVATE_CARD"}, {"type": "ADD_TEMP_BP_MODIFIER"}],
                        "limits": {},
                        "ui": {"text": "ready bp"},
                    },
                ],
            }
        )

        self.assertEqual(
            semantic_entry["template_types"],
            ["SELECT_AND_MOVE", "READY_AND_TEMP_BP", "PREVIEW_ADD_TO_HAND"],
        )
        self.assertEqual(semantic_entry["abilities"][0]["template_type"], "PREVIEW_ADD_TO_HAND")
        self.assertEqual(semantic_entry["abilities"][1]["template_type"], "READY_AND_TEMP_BP")

    def test_compile_trigger_reuses_preview_add_to_hand_family_for_tlr_energy_threshold_text(self):
        ability = _compile_trigger(
            {"id": "UA45BT_TLR_1_012"},
            {
                "trigger": "ON_ENTER",
                "source_label": "test",
                "effect_box": "OUTER",
                "text": self.TLR_PREVIEW_ADD_TO_HAND_TEXT,
            },
            {},
        )

        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(
            ability["template_metadata"],
            {
                "family": "PREVIEW_ADD_TO_HAND",
                "variant": "preview_add_to_hand_discard_on_add",
            },
        )

        semantic_entry = _build_semantic_entry(
            {
                "id": "UA45BT_TLR_1_012",
                "analysis": {"source": "TLR/cards_raw.json"},
                "card_meta": {
                    "keywords": [],
                    "text": {"effect": self.TLR_PREVIEW_ADD_TO_HAND_TEXT, "trigger": "", "rule": ""},
                },
                "abilities": [ability],
            }
        )

        self.assertEqual(semantic_entry["template_types"], ["SELECT_AND_MOVE", "PREVIEW_ADD_TO_HAND"])
        self.assertEqual(semantic_entry["abilities"][0]["template_type"], "PREVIEW_ADD_TO_HAND")

    def test_compile_event_effect_reuses_bp_threshold_family_for_tlr_name_gate_text(self):
        ability = _compile_event_effect(
            {"id": "UA45BT_TLR_1_078", "card_type": "EVENT"},
            {
                "source_label": "",
                "effect_box": "OUTER",
                "text": self.TLR_BP_THRESHOLD_TEXT,
            },
            {},
        )

        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(
            ability["template_metadata"],
            {
                "family": "BP_THRESHOLD_REMOVE",
                "variant": "bp_threshold_remove_dynamic_name_gate",
            },
        )

        semantic_entry = _build_semantic_entry(
            {
                "id": "UA45BT_TLR_1_078",
                "analysis": {"source": "TLR/cards_raw.json"},
                "card_meta": {
                    "keywords": [],
                    "text": {"effect": self.TLR_BP_THRESHOLD_TEXT, "trigger": "", "rule": ""},
                },
                "abilities": [ability],
            }
        )

        self.assertEqual(semantic_entry["template_types"], ["SELECT_AND_MOVE", "BP_THRESHOLD_REMOVE"])
        self.assertEqual(semantic_entry["abilities"][0]["template_type"], "BP_THRESHOLD_REMOVE")

    def test_compile_trigger_supports_preview_top_choose_top_or_bottom_template(self):
        ability = _compile_trigger(
            {"id": "UA45BT_TLR_1_010"},
            {
                "trigger": "ON_ENTER",
                "source_label": "登場時",
                "effect_box": "OUTER",
                "text": self.TLR_PREVIEW_TOP_CHOOSE_TEXT,
            },
            {},
        )
        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(ability["steps"][0]["type"], "PREVIEW_TOP_DECK")
        self.assertEqual(ability["steps"][1]["type"], "SELECT_TARGETS")
        self.assertEqual(ability["steps"][2]["type"], "MOVE_SELECTED_CARDS")

    def test_compile_trigger_supports_conditional_draw_template(self):
        ability = _compile_trigger(
            {"id": "UA45BT_TLR_1_050"},
            {
                "trigger": "ON_ENTER",
                "source_label": "登場時",
                "effect_box": "OUTER",
                "text": self.TLR_CONDITIONAL_DRAW_TEXT,
            },
            {},
        )
        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(ability["requirements"][0]["type"], "CONTROLLER_OTHER_CARDS_COUNT_GTE")
        self.assertEqual(ability["steps"][0]["type"], "DRAW")

    def test_compile_trigger_supports_optional_ap_damage_template(self):
        ability = _compile_trigger(
            {"id": "UA45BT_TLR_1_007"},
            {
                "trigger": "ON_ENTER",
                "source_label": "登場時",
                "effect_box": "OUTER",
                "text": self.TLR_OPTIONAL_AP_DAMAGE_TEXT,
            },
            {},
        )
        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual([step["type"] for step in ability["steps"]], ["SELECT_TARGETS", "PAY_AP_COST", "DEAL_DAMAGE"])

    def test_compile_trigger_supports_hand_summon_template(self):
        ability = _compile_trigger(
            {"id": "UA45BT_TLR_1_005"},
            {
                "trigger": "ON_ENTER",
                "source_label": "登場時",
                "effect_box": "OUTER",
                "text": self.TLR_HAND_SUMMON_TEXT,
            },
            {},
        )
        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(ability["steps"][-1]["type"], "PLAY_SELECTED_CARDS")
        self.assertEqual(ability["steps"][-1]["state"], "RESTED")

    def test_compile_trigger_supports_temp_bp_modifier_template(self):
        ability = _compile_trigger(
            {"id": "UA45BT_TLR_1_014"},
            {
                "trigger": "MAIN_ACTIVATE",
                "source_label": "起動メイン",
                "effect_box": "OUTER",
                "text": self.TLR_BP_PLUS_TEXT,
            },
            {},
        )
        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(ability["steps"][-1]["type"], "ADD_TEMP_BP_MODIFIER")
        self.assertEqual(ability["steps"][-1]["value"], 1000)

    def test_compile_event_effect_supports_branch_choice_template(self):
        ability = _compile_event_effect(
            {"id": "UA45BT_TLR_1_081", "card_type": "EVENT", "effects": [{"text": "・A。"}, {"text": "・B。"}]},
            {
                "source_label": "",
                "effect_box": "OUTER",
                "text": self.TLR_BRANCH_SELECT_ONE_TEXT,
            },
            {},
        )
        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual([step["type"] for step in ability["steps"]], ["SELECT_TARGETS", "EXECUTE_BRANCH"])
        self.assertEqual(len(ability["steps"][1]["branches"]), 2)

    def test_build_semantic_entry_uses_override_enum_for_complex_tlr_boundary_cases(self):
        semantic_entry = _build_semantic_entry(
            {
                "id": "UA45BT_TLR_1_095",
                "analysis": {"source": "TLR/cards_raw.json"},
                "card_meta": {
                    "keywords": [],
                    "text": {"effect": self.TLR_COMPLEX_OVERRIDE_TEXT, "trigger": "", "rule": ""},
                },
                "abilities": [
                    {
                        "id": "override-needed",
                        "timing": {"event": "ON_PLAY"},
                        "status": "UNSUPPORTED",
                        "requirements": [],
                        "target_specs": [],
                        "steps": [],
                        "limits": {},
                        "ui": {"text": self.TLR_COMPLEX_OVERRIDE_TEXT},
                        "unsupported_reason": "out-of-template",
                    }
                ],
            }
        )

        self.assertFalse(semantic_entry["can_be_expressed_by_dsl"])
        self.assertEqual(semantic_entry["unresolved_capabilities"], ["SEMANTIC_OVERRIDE_REQUIRED"])

    def test_migrated_template_families_no_longer_compile_through_legacy_helpers(self):
        legacy_preview = _compile_trigger_legacy(
            {"id": "UA31BT_MMM_1_043"},
            {
                "trigger": "ON_ENTER",
                "source_label": "test",
                "effect_box": "OUTER",
                "text": self.PREVIEW_ADD_TO_HAND_TEXT,
            },
            {},
        )
        self.assertEqual(legacy_preview["status"], "UNSUPPORTED")

        legacy_bp_cases = [
            ("UA31BT_MMM_1_094", self.BP_THRESHOLD_TEXT),
            ("UA31BT_MMM_1_066", self.HOMURA_BP_THRESHOLD_TEXT),
            ("UA45BT_TLR_1_078", self.TLR_BP_THRESHOLD_TEXT),
        ]
        for card_id, effect_text in legacy_bp_cases:
            legacy_bp = _compile_event_effect_legacy(
                {"id": card_id, "card_type": "EVENT"},
                {
                    "source_label": "",
                    "effect_box": "OUTER",
                    "text": effect_text,
                },
                {},
            )
            self.assertEqual(legacy_bp["status"], "UNSUPPORTED", msg=card_id)

        workspace_root = Path(__file__).resolve().parents[1]
        cases = [
            (workspace_root / "data" / "cards" / "MMM" / "cards_raw.json", "UA31BT_MMM_1_043", "PREVIEW_ADD_TO_HAND"),
            (workspace_root / "data" / "cards" / "MMM" / "cards_raw.json", "UA31BT_MMM_1_094", "BP_THRESHOLD_REMOVE"),
            (workspace_root / "data" / "cards" / "MMM" / "cards_raw.json", "UA31BT_MMM_1_066", "BP_THRESHOLD_REMOVE"),
            (workspace_root / "data" / "cards" / "TLR" / "cards_raw.json", "UA45BT_TLR_1_012", "PREVIEW_ADD_TO_HAND"),
            (workspace_root / "data" / "cards" / "TLR" / "cards_raw.json", "UA45BT_TLR_1_078", "BP_THRESHOLD_REMOVE"),
        ]

        compiled_by_series: dict[Path, tuple[list[dict], list[dict]]] = {}
        for raw_path, card_id, expected_family in cases:
            if raw_path not in compiled_by_series:
                compiled_by_series[raw_path] = _compile_series_cards(raw_path)
            _compiled, semantic_entries = compiled_by_series[raw_path]
            semantic_map = {entry["card_id"]: entry for entry in semantic_entries}
            semantic_entry = semantic_map[card_id]

            self.assertIn(expected_family, semantic_entry["template_types"])
            self.assertNotIn("LEGACY_PASSTHROUGH", semantic_entry["template_types"])
            self.assertTrue(
                all(
                    ability.get("template_type") != "LEGACY_PASSTHROUGH"
                    for ability in semantic_entry.get("abilities", [])
                )
            )


if __name__ == "__main__":
    unittest.main()
