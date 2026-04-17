# cards_raw Unsupported Ability Status

Updated: 2026-04-02

## Baseline

- Scope: formal `cards_raw` only, excluding `data/cards/base_cards.json`.
- Sources:
  - `data/cards/MMM/cards_raw.json`
  - `data/cards/MMM/cards_semantic.json`
  - `data/cards/MMM/cards_effects.json`
- Formal raw totals:
  - cards: `117`
  - abilities: `180`
  - `SUPPORTED`: `180`
  - `UNSUPPORTED`: `0`
- `python tools/compile_cards_effects.py` terminal output is the runtime-total view including base sample cards, so the runtime-total ability count is `183 / 0` instead of the formal raw baseline.

## Current Status

- `P0` is complete.
- `P1` is complete.
- This round fully closed the remaining unsupported abilities on:
  - `UA31BT/MMM-1-018`
  - `UA31BT/MMM-1-019`
  - `UA31BT/MMM-1-027`
  - `UA31BT/MMM-1-029`
  - `UA31BT/MMM-1-034`
- Formal `cards_raw` has now reached full support for the current MMM baseline.

## Closed Template Areas

- Preview / search / reorder chains.
- Add-to-hand then discard follow-up.
- `OUTSIDE -> REMOVED` and `REMOVED -> play/summon` links.
- Source-entered-from-zone requirements.
- Conditional replacement branches via step-level requirement + `NOT`.
- `skip_next_ready_once` / "skip the next ready" lifecycle.
- Once-per-turn support for triggered abilities and event-card turn limits.
- Dynamic BP threshold driven by OUTSIDE event count.
- Result-dependent follow-up after draw / discard.
- Hand-group energy reduction after discarding an event card.
- Event reward branches driven by discarded card type.

## Verification

- `python tools/compile_cards_effects.py`: runtime-total `183 / 0`, formal raw `180 / 0`.
- `test/milestone_smoke_test.gd`: `33 / 0`.
- `test/runtime_residue_smoke_test.gd`: `9 / 0`.
- `test/cards_raw_minimal_duel_smoke_test.gd`: `80 / 0`.
