# Compiler Template Generalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the card-effects compiler into a normalized template-recognition pipeline that emits stable English semantic IR and reuses the same template families across `MMM` and `TLR`.

**Architecture:** Keep `tools/compile_cards_effects.py` as the CLI entrypoint, but split normalization, template recognition, semantic assembly, and effects compilation into focused helper modules under `tools/card_effects_compiler/`. Migrate existing reusable registry cases first, preserve `registry -> legacy fallback` during transition, and remove migrated legacy branches only after test and compile baselines are stable.

**Tech Stack:** Python 3, `unittest`, JSON card data under `data/cards/*`, existing compiler entrypoint `tools/compile_cards_effects.py`

---

## File Structure

- Create: `tools/card_effects_compiler/__init__.py`
  - Package marker for extracted compiler helpers.
- Create: `tools/card_effects_compiler/normalization.py`
  - Owns Japanese text normalization helpers and normalized matching adapters.
- Create: `tools/card_effects_compiler/template_registry.py`
  - Owns reusable template rules, rule registration, and dispatch on normalized text.
- Create: `tools/card_effects_compiler/semantic_ir.py`
  - Owns semantic entry assembly, English failure enums, and semantic contract helpers.
- Create: `tests/test_compile_cards_effects.py`
  - Owns compiler-focused unit tests for normalization, template recognition, semantic output, and compile output.
- Modify: `tools/compile_cards_effects.py`
  - Keep CLI and existing compile helpers, but delegate normalization, template dispatch, and semantic assembly to extracted modules.
- Modify: `docs/plan/development_plan.md`
  - Update compiler-refactor progress once the migration starts landing.
- Modify: `docs/logs/log_2026-04-09.md`
  - Append implementation progress and verification results in Chinese.

### Task 1: Add Characterization Tests And Extraction Seams

**Files:**
- Create: `D:\CodexWork\TcgDemo\tests\test_compile_cards_effects.py`
- Modify: `D:\CodexWork\TcgDemo\tools\compile_cards_effects.py`

- [ ] **Step 1: Write the failing normalization and semantic contract tests**

```python
import unittest

from tools.compile_cards_effects import (
    _build_semantic_entry,
    _normalize_japanese_text_for_matching,
)


class NormalizeJapaneseTextTests(unittest.TestCase):
    def test_normalize_japanese_text_collapses_whitespace_and_width(self):
        raw = "自分の山札の上から  3枚見る。\nこの中から  黄のイベントカードを1枚まで公開し手札に加える。"
        normalized = _normalize_japanese_text_for_matching(raw)
        self.assertEqual(
            normalized,
            "自分の山札の上から3枚見る。この中から黄のイベントカードを1枚まで公開し手札に加える。",
        )


class SemanticContractTests(unittest.TestCase):
    def test_build_semantic_entry_uses_english_unresolved_capabilities(self):
        card_effects = {
            "id": "UA_TEST_001",
            "card_meta": {"text": {"effect": "dummy", "trigger": "-", "rule": "-"}, "keywords": []},
            "analysis": {"source": "test"},
            "abilities": [
                {
                    "id": "ua_test_001_a1",
                    "status": "UNSUPPORTED",
                    "unsupported_reason": "NO_TEMPLATE_MATCH",
                    "timing": {"event": "ON_ENTER"},
                    "ui": {"text": "dummy"},
                }
            ],
        }

        semantic = _build_semantic_entry(card_effects)

        self.assertEqual(semantic["card_id"], "UA_TEST_001")
        self.assertEqual(semantic["unresolved_capabilities"], ["NO_TEMPLATE_MATCH"])
        self.assertNotIn("missing_capabilities", semantic)
```

- [ ] **Step 2: Run the new test file and confirm it fails on missing extraction seams**

Run: `python -m unittest tests.test_compile_cards_effects -v`
Expected: FAIL with `ImportError` or `KeyError` because `_normalize_japanese_text_for_matching` and the new semantic contract do not exist yet.

- [ ] **Step 3: Add minimal extraction seam functions in the compiler entrypoint**

```python
def _normalize_japanese_text_for_matching(text: str) -> str:
    text = unicodedata.normalize("NFKC", text)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"\s+", "", text)
    return text.strip()


def _english_failure_list(reasons: list[str]) -> list[str]:
    return [reason for reason in reasons if reason]
```

- [ ] **Step 4: Update `_build_semantic_entry()` to emit the new field names**

```python
return {
    "card_id": card_effects.get("id", ""),
    "origin": card_effects.get("analysis", {}).get("source", ""),
    "template_types": template_types,
    "abilities": abilities,
    "can_be_expressed_by_dsl": can_be_expressed,
    "unresolved_capabilities": _english_failure_list(unresolved_capabilities),
    "source_text_jp": card_effects.get("card_meta", {}).get("text", {}),
}
```

- [ ] **Step 5: Re-run the focused test file and confirm it passes**

Run: `python -m unittest tests.test_compile_cards_effects -v`
Expected: PASS for the new normalization and semantic contract tests.

- [ ] **Step 6: Commit**

```bash
git add tests/test_compile_cards_effects.py tools/compile_cards_effects.py
git commit -m "test: add compiler characterization seams"
```

### Task 2: Extract Normalization And Template Dispatch Modules

**Files:**
- Create: `D:\CodexWork\TcgDemo\tools\card_effects_compiler\__init__.py`
- Create: `D:\CodexWork\TcgDemo\tools\card_effects_compiler\normalization.py`
- Create: `D:\CodexWork\TcgDemo\tools\card_effects_compiler\template_registry.py`
- Modify: `D:\CodexWork\TcgDemo\tools\compile_cards_effects.py`
- Test: `D:\CodexWork\TcgDemo\tests\test_compile_cards_effects.py`

- [ ] **Step 1: Write the failing dispatch test against normalized template matching**

```python
from tools.card_effects_compiler.template_registry import dispatch_trigger_template


class TemplateDispatchTests(unittest.TestCase):
    def test_dispatch_trigger_template_matches_normalized_preview_text(self):
        card = {"id": "UA31BT_MMM_1_007"}
        trigger_entry = {
            "trigger": "ON_ENTER",
            "text": "自分の山札の上から 3枚見る。 この中から黄のイベントカードを1枚まで公開し手札に加える。 残りを好きな順で自分の山札の下に置く。",
        }

        ability = dispatch_trigger_template(card, trigger_entry, semantic_map={})

        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(ability["analysis"]["template_id"], "PREVIEW_ADD_TO_HAND_THEN_REORDER")
```

- [ ] **Step 2: Run the targeted dispatch test and confirm it fails because the module does not exist**

Run: `python -m unittest tests.test_compile_cards_effects.TemplateDispatchTests.test_dispatch_trigger_template_matches_normalized_preview_text -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'tools.card_effects_compiler'`.

- [ ] **Step 3: Create the normalization module**

```python
import re
import unicodedata


def normalize_japanese_text(text: str) -> str:
    text = unicodedata.normalize("NFKC", text)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("「", '"').replace("」", '"')
    text = re.sub(r"\s+", "", text)
    return text.strip()
```

- [ ] **Step 4: Create the template registry module with normalized matchers**

```python
from dataclasses import dataclass
import re

from .normalization import normalize_japanese_text


@dataclass(frozen=True)
class TemplateRule:
    name: str
    event_filter: str | tuple[str, ...]
    matcher: object
    builder: object
    priority: int = 0


def normalized_exact_match(expected_text: str):
    expected = normalize_japanese_text(expected_text)

    def _matcher(_card, _entry, text, _card_id):
        if normalize_japanese_text(text) == expected:
            return {}
        return None

    return _matcher
```

- [ ] **Step 5: Switch compiler dispatch to use the extracted module**

```python
from tools.card_effects_compiler.normalization import normalize_japanese_text
from tools.card_effects_compiler.template_registry import dispatch_trigger_template


def _normalize_japanese_text_for_matching(text: str) -> str:
    return normalize_japanese_text(text)


def _compile_trigger(card: dict, trigger_entry: dict, semantic_map: dict[str, dict]) -> dict:
    return dispatch_trigger_template(card, trigger_entry, semantic_map, _compile_trigger_legacy)
```

- [ ] **Step 6: Re-run the focused dispatch test and then the whole compiler test file**

Run: `python -m unittest tests.test_compile_cards_effects.TemplateDispatchTests.test_dispatch_trigger_template_matches_normalized_preview_text -v`
Expected: PASS

Run: `python -m unittest tests.test_compile_cards_effects -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add tools/card_effects_compiler/__init__.py tools/card_effects_compiler/normalization.py tools/card_effects_compiler/template_registry.py tools/compile_cards_effects.py tests/test_compile_cards_effects.py
git commit -m "refactor: extract compiler normalization and template dispatch"
```

### Task 3: Freeze English Semantic IR And Effects Metadata

**Files:**
- Create: `D:\CodexWork\TcgDemo\tools\card_effects_compiler\semantic_ir.py`
- Modify: `D:\CodexWork\TcgDemo\tools\compile_cards_effects.py`
- Test: `D:\CodexWork\TcgDemo\tests\test_compile_cards_effects.py`

- [ ] **Step 1: Write failing tests for semantic field names and English failure enums**

```python
class SemanticFieldTests(unittest.TestCase):
    def test_compile_series_cards_produces_english_semantic_fields(self):
        compiled, semantic_entries = _compile_series_cards(Path("data/cards/MMM/cards_raw.json"))
        entry = next(item for item in semantic_entries if item["card_id"] == "UA31BT_MMM_1_007")

        self.assertIn("origin", entry)
        self.assertIn("source_text_jp", entry)
        self.assertIn("unresolved_capabilities", entry)
        self.assertNotIn("source", entry)
        self.assertNotIn("missing_capabilities", entry)
```

- [ ] **Step 2: Run the semantic field tests and confirm they fail on old field names**

Run: `python -m unittest tests.test_compile_cards_effects.SemanticFieldTests -v`
Expected: FAIL because the compiler still emits `source` and `missing_capabilities`.

- [ ] **Step 3: Add the semantic helper module**

```python
def build_semantic_entry(card_effects: dict, *, infer_template_type) -> dict:
    unresolved_capabilities: list[str] = []
    template_types: list[str] = []
    abilities: list[dict] = []
    for ability in card_effects.get("abilities", []):
        template_type = infer_template_type(ability)
        reason = str(ability.get("unsupported_reason", "")).strip()
        abilities.append(
            {
                "ability_id": ability.get("id", ""),
                "timing": ability.get("timing", {}).get("event", ""),
                "status": ability.get("status", "UNSUPPORTED"),
                "reason": reason,
                "template_type": template_type,
            }
        )
        if template_type and template_type not in template_types:
            template_types.append(template_type)
        if reason:
            unresolved_capabilities.append(reason)

    return {
        "card_id": card_effects.get("id", ""),
        "origin": card_effects.get("analysis", {}).get("source", ""),
        "template_types": template_types,
        "abilities": abilities,
        "can_be_expressed_by_dsl": all(item["status"] == "SUPPORTED" for item in abilities) if abilities else False,
        "unresolved_capabilities": unresolved_capabilities,
        "source_text_jp": card_effects.get("card_meta", {}).get("text", {}),
    }
```

- [ ] **Step 4: Route `_build_semantic_entry()` through the new module**

```python
from tools.card_effects_compiler.semantic_ir import build_semantic_entry


def _build_semantic_entry(card_effects: dict) -> dict:
    return build_semantic_entry(card_effects, infer_template_type=_infer_template_type)
```

- [ ] **Step 5: Re-run semantic field tests and the whole file**

Run: `python -m unittest tests.test_compile_cards_effects.SemanticFieldTests -v`
Expected: PASS

Run: `python -m unittest tests.test_compile_cards_effects -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add tools/card_effects_compiler/semantic_ir.py tools/compile_cards_effects.py tests/test_compile_cards_effects.py
git commit -m "refactor: freeze english semantic ir contract"
```

### Task 4: Migrate MMM Preview And BP Templates To Reusable Families

**Files:**
- Modify: `D:\CodexWork\TcgDemo\tools\card_effects_compiler\template_registry.py`
- Modify: `D:\CodexWork\TcgDemo\tools\compile_cards_effects.py`
- Test: `D:\CodexWork\TcgDemo\tests\test_compile_cards_effects.py`
- Test data: `D:\CodexWork\TcgDemo\data\cards\MMM\cards_raw.json`

- [ ] **Step 1: Add failing tests for MMM preview and BP families**

```python
class MmmTemplateFamilyTests(unittest.TestCase):
    def test_mmm_preview_template_family_compiles_as_supported(self):
        compiled, _semantic_entries = _compile_series_cards(Path("data/cards/MMM/cards_raw.json"))
        card = next(item for item in compiled if item["id"] == "UA31BT_MMM_1_007")
        ability = next(a for a in card["abilities"] if a["timing"]["event"] == "ON_ENTER")
        self.assertEqual(ability["status"], "SUPPORTED")
        self.assertEqual(ability["analysis"]["template_id"], "PREVIEW_ADD_TO_HAND_THEN_REORDER")
```

- [ ] **Step 2: Run the MMM family tests and capture the current failure**

Run: `python -m unittest tests.test_compile_cards_effects.MmmTemplateFamilyTests -v`
Expected: FAIL because current abilities only expose ad-hoc rule names or legacy metadata instead of stable template IDs.

- [ ] **Step 3: Replace per-card rule names with template-family IDs plus params**

```python
ability.setdefault("analysis", {})
ability["analysis"].update(
    {
        "template_id": "PREVIEW_ADD_TO_HAND_THEN_REORDER",
        "template_family": "PREVIEW",
        "params": params,
    }
)
```

- [ ] **Step 4: Apply the same family metadata to BP threshold templates**

```python
ability.setdefault("analysis", {})
ability["analysis"].update(
    {
        "template_id": "BP_THRESHOLD_ACTION",
        "template_family": "BP_THRESHOLD",
        "params": {"threshold": int(payload["match"].group(1)), "min_count": min_count, "max_count": max_count},
    }
)
```

- [ ] **Step 5: Re-run MMM tests and confirm supported counts stay stable**

Run: `python -m unittest tests.test_compile_cards_effects.MmmTemplateFamilyTests -v`
Expected: PASS

Run: `python tools/compile_cards_effects.py`
Expected: Compiler completes and `data/cards/MMM/cards_effects.json` / `data/cards/MMM/cards_semantic.json` are regenerated without reducing the number of supported MMM abilities.

- [ ] **Step 6: Commit**

```bash
git add tools/card_effects_compiler/template_registry.py tools/compile_cards_effects.py tests/test_compile_cards_effects.py data/cards/MMM/cards_effects.json data/cards/MMM/cards_semantic.json
git commit -m "refactor: migrate mmm templates to reusable families"
```

### Task 5: Prove TLR Reuse And Freeze Override Boundaries

**Files:**
- Modify: `D:\CodexWork\TcgDemo\tools\card_effects_compiler\template_registry.py`
- Modify: `D:\CodexWork\TcgDemo\tools\compile_cards_effects.py`
- Test: `D:\CodexWork\TcgDemo\tests\test_compile_cards_effects.py`
- Test data: `D:\CodexWork\TcgDemo\data\cards\TLR\cards_raw.json`

- [ ] **Step 1: Add failing tests that TLR uses the same template IDs as MMM**

```python
class TlrReuseTests(unittest.TestCase):
    def test_tlr_preview_text_reuses_preview_template_family(self):
        compiled, semantic_entries = _compile_series_cards(Path("data/cards/TLR/cards_raw.json"))
        preview_card = next(card for card in compiled if card["id"] == "UA32BT_TLR_1_034")
        ability = next(a for a in preview_card["abilities"] if a["status"] == "SUPPORTED")
        self.assertEqual(ability["analysis"]["template_id"], "PREVIEW_ADD_TO_HAND_THEN_REORDER")
        entry = next(item for item in semantic_entries if item["card_id"] == "UA32BT_TLR_1_034")
        self.assertNotIn("LEGACY_PASSTHROUGH", entry["template_types"])
```

- [ ] **Step 2: Run the TLR reuse tests and confirm they fail before migration**

Run: `python -m unittest tests.test_compile_cards_effects.TlrReuseTests -v`
Expected: FAIL because TLR cards still fall back through legacy branches or do not expose stable template metadata.

- [ ] **Step 3: Extend registry rules to match normalized TLR variants without card-ID filters**

```python
TemplateRule(
    name="event.preview_add_to_hand.distinct_trait",
    event_filter="ON_PLAY",
    matcher=normalized_exact_match("自分の山札の上から5枚見る。この中から特徴：...を2枚まで公開し手札に加える。残りを好きな順で自分の山札の下に置く。"),
    builder=_preview_add_to_hand_builder_factory(
        count=5,
        filters=[{"type": "HAS_TRAIT", "value": "..."}],
        max_count=2,
        distinct_by="CARD_NAME",
        kind="TRIGGERED",
    ),
    priority=200,
)
```

- [ ] **Step 4: Route non-template complex cases to one override enum**

```python
def _semantic_override_required(card: dict, event_name: str, trigger_entry: dict) -> dict:
    return _unsupported_ability(
        card,
        event_name,
        trigger_entry,
        reason="SEMANTIC_OVERRIDE_REQUIRED",
    )
```

- [ ] **Step 5: Re-run the TLR tests and the compiler**

Run: `python -m unittest tests.test_compile_cards_effects.TlrReuseTests -v`
Expected: PASS

Run: `python tools/compile_cards_effects.py`
Expected: Compiler completes and regenerates `data/cards/TLR/cards_effects.json` / `data/cards/TLR/cards_semantic.json` with reused template families instead of new card-ID-only branches.

- [ ] **Step 6: Commit**

```bash
git add tools/card_effects_compiler/template_registry.py tools/compile_cards_effects.py tests/test_compile_cards_effects.py data/cards/TLR/cards_effects.json data/cards/TLR/cards_semantic.json
git commit -m "refactor: prove tlr template reuse and override boundaries"
```

### Task 6: Remove Migrated Legacy Paths And Freeze Baseline

**Files:**
- Modify: `D:\CodexWork\TcgDemo\tools\compile_cards_effects.py`
- Modify: `D:\CodexWork\TcgDemo\tests\test_compile_cards_effects.py`
- Modify: `D:\CodexWork\TcgDemo\docs\plan\development_plan.md`
- Modify: `D:\CodexWork\TcgDemo\docs\logs\log_2026-04-09.md`

- [ ] **Step 1: Add a failing regression test that migrated families do not return legacy passthrough**

```python
class LegacyRemovalTests(unittest.TestCase):
    def test_migrated_templates_no_longer_report_legacy_passthrough(self):
        _compiled, semantic_entries = _compile_series_cards(Path("data/cards/MMM/cards_raw.json"))
        semantic = next(item for item in semantic_entries if item["card_id"] == "UA31BT_MMM_1_007")
        self.assertNotIn("LEGACY_PASSTHROUGH", semantic["template_types"])
```

- [ ] **Step 2: Run the legacy-removal test and confirm it fails before cleanup**

Run: `python -m unittest tests.test_compile_cards_effects.LegacyRemovalTests -v`
Expected: FAIL while migrated templates still leak legacy metadata.

- [ ] **Step 3: Delete only the migrated legacy branches and preserve fallback for untouched families**

```python
def _compile_trigger(card: dict, trigger_entry: dict, semantic_map: dict[str, dict]) -> dict:
    ability = dispatch_trigger_template(card, trigger_entry, semantic_map, _compile_trigger_legacy)
    if ability.get("analysis", {}).get("template_id") in {"PREVIEW_ADD_TO_HAND_THEN_REORDER", "BP_THRESHOLD_ACTION"}:
        ability.pop("legacy_effect", None)
    return ability
```

- [ ] **Step 4: Re-run focused tests, full compiler tests, and the compiler CLI**

Run: `python -m unittest tests.test_compile_cards_effects.LegacyRemovalTests -v`
Expected: PASS

Run: `python -m unittest tests.test_compile_cards_effects -v`
Expected: PASS

Run: `python tools/compile_cards_effects.py`
Expected: Compiler completes and rewrites all `cards_effects.json` / `cards_semantic.json` files without reintroducing migrated legacy metadata.

- [ ] **Step 5: Update plan and log documentation**

```md
## 2026-04-09
- 变更类型：编译链重构
- 变更摘要：完成编译器模板通用化第一轮迁移，冻结英文 semantic IR，迁移 MMM 模板族，并验证 TLR 复用主链。
- 验证方式：`python -m unittest tests.test_compile_cards_effects -v`；`python tools/compile_cards_effects.py`
- 结果：MMM 不回归，TLR 复用统一模板族，已迁移族不再依赖 legacy passthrough。
```

- [ ] **Step 6: Commit**

```bash
git add tools/compile_cards_effects.py tests/test_compile_cards_effects.py docs/plan/development_plan.md docs/logs/log_2026-04-09.md data/cards/MMM/cards_effects.json data/cards/MMM/cards_semantic.json data/cards/TLR/cards_effects.json data/cards/TLR/cards_semantic.json
git commit -m "refactor: freeze compiler template generalization baseline"
```

## Self-Review

### Spec coverage

- The plan covers normalization, template recognition, semantic IR, effects metadata, MMM migration, TLR reuse, and migrated legacy cleanup.
- The plan includes recognition tests, semantic tests, compile tests, and full compiler CLI verification.

### Placeholder scan

- No `TODO`, `TBD`, or “implement later” placeholders remain.
- Each task includes exact file paths, commands, and concrete code snippets.

### Type consistency

- The plan consistently uses `origin`, `template_id`, `source_text_jp`, and `unresolved_capabilities`.
- The extracted helper names stay consistent across tasks: `normalize_japanese_text`, `dispatch_trigger_template`, and `build_semantic_entry`.
