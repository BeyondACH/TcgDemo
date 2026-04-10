# Unsupported Atomic Capabilities Report

## Snapshot
- Date: 2026-04-10
- Scope: `data/cards/*/cards_semantic.json`
- Target capability: `SEMANTIC_OVERRIDE_REQUIRED`

## Summary
- Previous count: 3
- Current count: 1
- Delta: -2

## Remaining card ids
- `UA45BT_TLR_1_082`

## Newly covered template families
- `BP_SUM_LIMIT_REMOVE`
- `PREVIEW_ADD_TO_HAND` (`preview_add_to_hand_name_contains_discard_on_add`)

## Validation command
```bash
python tools/compile_cards_effects.py
python - <<'PY'
import json
from pathlib import Path
count = 0
for p in Path('data/cards').glob('*/cards_semantic.json'):
    for e in json.loads(p.read_text(encoding='utf-8')):
        if 'SEMANTIC_OVERRIDE_REQUIRED' in e.get('unresolved_capabilities', []):
            count += 1
print(count)
PY
```
