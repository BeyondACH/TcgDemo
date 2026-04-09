# TLR Import Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing card-import pipeline support `pic/<title_code>/` directories and fully sync the `TLR` series into raw data, thumbnails, and compiled outputs.

**Architecture:** Keep the current import pipeline intact and make the smallest possible change: teach the raw-import script to scan top-level series directories under `pic/`, then reuse the existing thumbnail generator and compiler as-is. Verify behavior with a focused regression test before running the real `TLR` sync.

**Tech Stack:** PowerShell, Python `unittest`, JSON card data, existing repository tools

---

### Task 1: Add a regression test for series subdirectory scanning

**Files:**
- Create: `tests/test_import_cards_raw_from_pic.py`
- Modify: `tools/import_cards_raw_from_pic.ps1`

- [ ] Step 1: Write a failing test that prepares `pic/TLR/UA45BT-TLR-1-001.png`, runs the import script against that temp repo, and expects `scanned=1`.
- [ ] Step 2: Run `python -m unittest tests.test_import_cards_raw_from_pic -v` and confirm it fails because the script currently ignores nested series directories.
- [ ] Step 3: Implement the smallest script change that scans top-level series directories and still ignores `micro/`.
- [ ] Step 4: Re-run `python -m unittest tests.test_import_cards_raw_from_pic -v` and confirm it passes.

### Task 2: Execute the TLR sync pipeline

**Files:**
- Modify: `data/cards/TLR/cards_raw.json`
- Modify: `pic/TLR/micro/*`
- Modify: `data/cards/TLR/cards_effects.json`
- Modify: `data/cards/TLR/cards_semantic.json`

- [ ] Step 1: Run `tools/import_cards_raw_from_pic.ps1` outside the sandbox so network fetches can resolve official card pages.
- [ ] Step 2: Run `tools/generate_micro_card_images.ps1` and confirm `pic/TLR/micro/` is populated.
- [ ] Step 3: Run `tools/compile_cards_effects.py` and confirm compiled outputs for `TLR` are written.
- [ ] Step 4: Spot-check key output files for expected counts and required fields.

### Task 3: Record the change

**Files:**
- Modify: `docs/logs/log_2026-04-09.md`

- [ ] Step 1: Add a Chinese log entry covering the script fix, TLR import, thumbnail generation, and compile step.
- [ ] Step 2: Re-read the log file with explicit UTF-8 and review `git diff` for encoding safety.
