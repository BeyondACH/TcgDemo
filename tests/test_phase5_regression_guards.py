import json
import unittest
from pathlib import Path

from tools.run_phase5_guardrails import _commands


class Phase5RegressionGuardsTests(unittest.TestCase):
    def setUp(self):
        repo_root = Path(__file__).resolve().parents[1]
        self.mcr_effects = json.loads((repo_root / "data" / "cards" / "MCR" / "cards_effects.json").read_text(encoding="utf-8"))
        self.tlr_effects = json.loads((repo_root / "data" / "cards" / "TLR" / "cards_effects.json").read_text(encoding="utf-8"))
        self.mmm_effects = json.loads((repo_root / "data" / "cards" / "MMM" / "cards_effects.json").read_text(encoding="utf-8"))

    @staticmethod
    def _ability_for_event(card_entry: dict, event_name: str) -> dict:
        for ability in card_entry.get("abilities", []):
            timing = ability.get("timing", {})
            if timing.get("event") == event_name:
                return ability
        raise AssertionError(f"Missing ability event={event_name} for card={card_entry.get('id')}")

    @staticmethod
    def _card_by_id(cards: list[dict], card_id: str) -> dict:
        for card in cards:
            if card.get("id") == card_id:
                return card
        raise AssertionError(f"Missing card {card_id}")

    @staticmethod
    def _unsupported_count(cards: list[dict]) -> int:
        total = 0
        for card in cards:
            for ability in card.get("abilities", []):
                if ability.get("status") != "SUPPORTED":
                    total += 1
        return total

    def test_phase5_budget_guard_keeps_zero_unsupported(self):
        self.assertEqual(self._unsupported_count(self.mcr_effects), 0)
        self.assertEqual(self._unsupported_count(self.tlr_effects), 0)
        self.assertEqual(self._unsupported_count(self.mmm_effects), 0)

    def test_phase4_tail_cards_keep_expected_template_variants(self):
        cases = [
            ("MCR", "UA36BT_MCR_1_029", "ON_PLAY", "mcr_sheryl_raid_chain_phase4"),
            ("TLR", "UA45BT_TLR_1_013", "ON_ENTER", "other_energy_lte_unblockable_bp_gate"),
            ("TLR", "UA45BT_TLR_1_015", "MAIN_ACTIVATE", "other_energy_lte_unblockable_bp_gate"),
            ("TLR", "UA45BT_TLR_1_037", "ON_PLAY", "bp_remove_dynamic_name_gate_energy_lte_count"),
            ("TLR", "UA45BT_TLR_1_043", "ON_ENTER", "hand_summon_named_or_energy_lte_then_conditional_keyword_placeholder"),
            ("TLR", "UA45BT_TLR_1_047", "ON_ENTER", "conditional_bp_gate_grant_cannot_block"),
            ("TLR", "UA45BT_TLR_1_048", "ON_ENTER", "self_gain_source_bp_compare_remove"),
        ]
        pools = {"MCR": self.mcr_effects, "TLR": self.tlr_effects}
        for series, card_id, event_name, expected_variant in cases:
            card = self._card_by_id(pools[series], card_id)
            ability = self._ability_for_event(card, event_name)
            self.assertEqual(ability.get("status"), "SUPPORTED", msg=f"{card_id} {event_name} should stay SUPPORTED")
            self.assertEqual(
                ability.get("template_metadata", {}).get("variant"),
                expected_variant,
                msg=f"{card_id} {event_name} template regression",
            )

    def test_phase5_guardrail_command_set_contains_zero_budget_gate(self):
        commands = _commands(include_compile=True, include_utf8=True)
        flattened = [" ".join(cmd) for cmd in commands]
        self.assertTrue(any("tools/check_unsupported_budget.py --max-total 0" in cmd for cmd in flattened))
        self.assertTrue(any("tests.test_phase5_regression_guards" in cmd for cmd in flattened))

    def test_phase5_guardrail_commands_can_skip_optional_steps(self):
        commands = _commands(include_compile=False, include_utf8=False)
        flattened = [" ".join(cmd) for cmd in commands]
        self.assertFalse(any("tools/compile_cards_effects.py" in cmd for cmd in flattened))
        self.assertFalse(any("tools/check_utf8_docs.py" in cmd for cmd in flattened))
