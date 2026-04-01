# cards_raw Unsupported Ability Status

Updated: 2026-04-01

## Baseline

- Scope: formal `cards_raw` only, excluding `data/cards/base_cards.json`.
- Sources:
  - `data/cards/MMM/cards_raw.json`
  - `data/cards/MMM/cards_semantic.json`
  - `data/cards/MMM/cards_effects.json`
- Formal raw totals:
  - cards: `117`
  - abilities: `180`
  - `SUPPORTED`: `174`
  - `UNSUPPORTED`: `6`
- `python tools/compile_cards_effects.py` terminal output is the runtime-total view including base sample cards, so it is `177 / 6` instead of the formal raw baseline.

## Current Status

- `P0` is complete.
- The following cards were fully closed in this round: `UA31BT/MMM-1-001`, `002`, `003`, `005`, `007`, `008`, `016`, `020`, `022`, `024`, `028`, `032`, `033`.
- Remaining unsupported abilities are now `P1` only.

## Closed P0 Template Areas

- Preview / search / reorder chains.
- Add-to-hand then discard follow-up.
- `OUTSIDE -> REMOVED` and `REMOVED -> play/summon` links.
- Source-entered-from-zone requirements.
- Conditional replacement branches via step-level requirement + `NOT`.
- `skip_next_ready_once` / "skip the next ready" lifecycle.
- Once-per-turn support for triggered abilities and event-card turn limits.

## Remaining Unsupported Abilities

- `UA31BT/MMM-1-018`
  - `ON_ENTER`: if controller OUTSIDE has at least 2 event cards, draw 1.
- `UA31BT/MMM-1-019`
  - `ON_ENTER`: draw 1, discard 1, then bounce an opponent front-line character with dynamic BP threshold based on OUTSIDE event count.
- `UA31BT/MMM-1-027`
  - `MAIN_ACTIVATE`: discard an event card from hand, then reduce required energy for all `Mami` cards in hand this turn.
- `UA31BT/MMM-1-029`
  - event effect: rest one ACTIVE self front-line character, then draw 3.
- `UA31BT/MMM-1-034`
  - per-turn usage limit.
  - draw 2, discard 1, then ready up to 1 AP card if the discarded card was an event card.

## Remaining P1 Themes

- Dynamic BP threshold driven by OUTSIDE event count.
- Result-dependent follow-up after draw / discard / payment.
- Hand-group energy reduction after discarding a specific card type.
- Combined "once per turn" event restriction plus result-dependent reward.

## Verification

- `python tools/compile_cards_effects.py`: runtime-total `177 / 6`, formal raw `174 / 6`.
- `docs/milestone_smoke_test.gd`: `33 / 0`.
- `docs/runtime_residue_smoke_test.gd`: `7 / 0`.
- `docs/cards_raw_minimal_duel_smoke_test.gd`: `75 / 0`.
