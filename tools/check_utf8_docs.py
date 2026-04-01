from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable


DEFAULT_GLOBS = [
    "README.md",
    "docs/plan/*.md",
    "docs/logs/*.md",
]

HIGH_RISK_PATTERNS = [
    ("question_run", "Suspicious repeated question marks", "????"),
    ("replacement_char", "包含 Unicode 替代字符", "\ufffd"),
    ("old_english_baseline", "包含旧英文口径，建议人工复核", "passed, 0 failed"),
    ("old_english_focus", "包含旧英文计划口径，建议人工复核", "Focus next on"),
    ("old_english_runtime", "包含旧英文统计口径，建议人工复核", "Formal `cards_raw` baseline is now"),
    ("old_english_prioritize", "包含旧英文优先级描述，建议人工复核", "Prioritize the remaining"),
]


def _iter_default_paths(repo_root: Path) -> Iterable[Path]:
    seen: set[Path] = set()
    for pattern in DEFAULT_GLOBS:
        for candidate in repo_root.glob(pattern):
            if candidate.is_file() and candidate not in seen:
                seen.add(candidate)
                yield candidate


def _iter_input_paths(repo_root: Path, raw_paths: list[str]) -> Iterable[Path]:
    seen: set[Path] = set()
    for raw in raw_paths:
        candidate = (repo_root / raw).resolve() if not Path(raw).is_absolute() else Path(raw)
        if candidate.is_file():
            if candidate not in seen:
                seen.add(candidate)
                yield candidate
            continue
        for matched in repo_root.glob(raw):
            if matched.is_file() and matched not in seen:
                seen.add(matched)
                yield matched


def _scan_file(path: Path) -> list[str]:
    issues: list[str] = []
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        issues.append(f"{path}:1: 检测到 UTF-8 BOM，建议统一改为 UTF-8 无 BOM。")
    text = raw.decode("utf-8")
    for lineno, line in enumerate(text.splitlines(), start=1):
        for _code, message, token in HIGH_RISK_PATTERNS:
            if token in line:
                issues.append(f"{path}:{lineno}: {message}: {line.strip()}")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(
        description="扫描中文文档中的高风险编码污染模式，只做告警，不自动改写文件。"
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="可选的文件或 glob；为空时默认扫描 README.md、docs/plan/*.md、docs/logs/*.md",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    targets = list(_iter_input_paths(repo_root, args.paths)) if args.paths else list(_iter_default_paths(repo_root))

    if not targets:
        print("未找到可扫描的文档。")
        return 0

    issues: list[str] = []
    for path in targets:
        issues.extend(_scan_file(path))

    if not issues:
        print(f"UTF8_DOC_CHECK_OK {len(targets)} files")
        return 0

    print("UTF8_DOC_CHECK_WARN")
    for issue in issues:
        print(issue)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
