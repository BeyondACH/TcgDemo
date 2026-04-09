# download_images `--list-works` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `download_images.py` 增加 `--list-works` 交互入口，使用户可按作品直接下载该作品下全部产品的卡图。

**Architecture:** 保持现有 `attrweblist -> 交互选择 -> weblist 下载` 主链路不变，只新增一个“按作品下载”的并行入口。`build_source_url()` 通过新增 `works` 参数承载 URL 契约，普通按产品下载逻辑继续沿用原有 `good` 参数。

**Tech Stack:** Python 3、`argparse`、`unittest`、`unittest.mock`

---

### Task 1: 先锁定 CLI 与 URL 契约

**Files:**
- Modify: `tests/test_download_images.py`
- Test: `tests/test_download_images.py`

- [ ] **Step 1: Write the failing tests**

```python
def test_build_source_url_prefers_works_filter_when_provided(self) -> None:
    url = script.build_source_url(works="作品A", limit=50)
    self.assertIn("works=", url)
    self.assertNotIn("good=", url)

def test_help_output_mentions_list_works(self) -> None:
    ...

def test_main_list_works_prompts_for_index_and_downloads_selected_work(self) -> None:
    ...
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m unittest tests.test_download_images -v`
Expected: FAIL，因为 `download_images.py` 还没有 `--list-works` 入口，也没有 `works` URL 逻辑。

- [ ] **Step 3: Write minimal implementation**

```python
def build_source_url(*, product: str = DEFAULT_PRODUCT, works: str = "", page: int = 1, limit: int = 50) -> str:
    params = {"page": str(page), "limit": str(limit)}
    if normalize_text(works):
        params["works"] = works
    else:
        params["good"] = product
    return f"{API_BASE_URL}?{urlencode(params)}"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python -m unittest tests.test_download_images -v`
Expected: PASS

### Task 2: 接入作品列表交互下载

**Files:**
- Modify: `download_images.py`
- Modify: `tests/test_download_images.py`
- Test: `tests/test_download_images.py`

- [ ] **Step 1: Write the failing interaction test**

```python
with (
    patch.object(script, "get_attr_works", return_value=["作品A", "作品B"]),
    patch("builtins.input", return_value="2"),
    patch.object(script.Path, "mkdir"),
    patch.object(script, "iter_image_urls", return_value=iter(())),
):
    exit_code = script.main(["--list-works"])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m unittest tests.test_download_images.DownloadImagesTests.test_main_list_works_prompts_for_index_and_downloads_selected_work -v`
Expected: FAIL，因为参数还不存在或主流程未切到 `works` 下载。

- [ ] **Step 3: Write minimal implementation**

```python
parser.add_argument("--list-works", action="store_true", ...)

if args.list_works:
    works = get_attr_works()
    selected_work = prompt_for_work_selection(works)
    args.work = selected_work
    args.product = ""

SOURCE_URL = build_source_url(product=args.product, works=args.work if args.list_works else "", limit=args.limit)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python -m unittest tests.test_download_images -v`
Expected: PASS

### Task 3: 同步中文文档口径

**Files:**
- Modify: `docs/plan/development_plan.md`
- Modify: `docs/logs/log_2026-04-09.md`

- [ ] **Step 1: Write the doc updates**

```md
- 图片抓取脚本新增 `--list-works`，会输出作品列表、提示输入编号，并基于 `works=<作品名>` 直接进入下载流程。
```

- [ ] **Step 2: Verify UTF-8 reload and diff**

Run: `python -c "from pathlib import Path; print(Path('docs/logs/log_2026-04-09.md').read_text(encoding='utf-8')[:80])"`
Expected: 能正常以 UTF-8 读取，且 `git diff -- docs/plan/development_plan.md docs/logs/log_2026-04-09.md` 仅包含本轮文案更新。

