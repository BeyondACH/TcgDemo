# Effect 未落能力项修复计划（2026-04-17）

## 1. 问题定义（高置信口径）

- 以 `source_text_jp.effect` 为源，筛选“单句动作文本”（排除换行/项目符号/纯括号说明）；
- 若该文本未在 `abilities[].text` 中逐字出现，则记为高置信疑似“effect 未落能力项”；
- 当前基线：总计 **82** 条，分系列为 `CGD=2`、`KGD=45`、`MCR=28`、`MMM=3`、`TLR=4`。

## 2. 修复优先级

### P0（本周）

- 优先修复同族高频漏项：
  - `other + trait + BP+1000`
  - `发生产能+ + 回合末退场`
  - `N 看牌 + 选牌 + 余牌回顶/回底`
- 对每个文本族补“至少 1 张编译样例 + 1 张运行时样例 + 1 条失败边界”。

### P1（次周）

- 扩展 `_compile_passive_effect` 与相关模板规则，覆盖“effect 段动作文本”到能力项的标准落盘路径；
- 对 `can_be_expressed_by_dsl=true` 但疑似漏项卡优先回填。

### P2（稳定期）

- 收敛剩余中低频漏项；
- 固化快照与门禁阈值，避免回归。

## 3. 防回归策略（必须执行）

1. 每轮编译后执行：
   - `python tools/check_effect_text_coverage.py --cards-root data/cards --write-json docs/plan/effect_coverage_baseline.json`
2. 合入前门禁执行：
   - `python tools/check_effect_text_coverage.py --cards-root data/cards --max-total 82 --max-series CGD=2 --max-series KGD=45 --max-series MCR=28 --max-series MMM=3 --max-series TLR=4`
3. 若门禁失败：
   - 不允许合入；
   - 必须在日志中写明新增漏项卡号与对应文本族。

## 4. 完成定义（DoD）

- 高置信漏项总数不高于基线，且目标系列漏项不回升；
- 至少完成 1 个高频文本族的模板化闭环（编译 + 运行时 + 边界）；
- `docs/plan/high_confidence_effect_drop_list.md` 与日志已同步更新；
- 禁止按卡硬编码修补。

## 5. P0 完成记录（2026-04-17）

- 已完成三个高频文本族的 P0 闭环：
  - `other + trait + BP+1000`
  - `发生产能+ + 回合末退场`
  - `N 看牌 + 选牌 + 余牌回顶/回底`
- 实现方式：
  - 在 `tools/compile_cards_effects.py` 中新增“effect 段标签提升”逻辑：`登場時 -> ON_ENTER`、`起動メイン -> MAIN_ACTIVATE`；
  - 起动主效果支持从标签恢复 `ターン1`（`once_per_turn=true`）与 `レストにする`（`REST_SOURCE` 成本）；
  - 新增两组模板：
    - `self_other_trait_bp_plus`（覆盖 `other + trait + BP+1000`）
    - `preview_add_to_hand_variable_clause_discard_on_add`（覆盖“看牌 + 选牌 + 余牌回底 + 加手后弃牌”可变子句）
- P0 结果（对比 2026-04-17 初始基线）：
  - 高置信漏项由 **82** 降至 **25**；
  - 分系列由 `CGD=2, KGD=45, MCR=28, MMM=3, TLR=4` 降至 `CGD=2, KGD=11, MCR=5, MMM=3, TLR=4`。
- 验证闭环：
  - 编译验证：`python tools/compile_cards_effects.py`
  - 覆盖度快照：`python tools/check_effect_text_coverage.py --cards-root data/cards --out-md docs/plan/high_confidence_effect_drop_list.md --write-json docs/plan/effect_coverage_baseline.json`
  - 门禁验证：`python tools/check_effect_text_coverage.py --cards-root data/cards --max-total 82 --max-series CGD=2 --max-series KGD=45 --max-series MCR=28 --max-series MMM=3 --max-series TLR=4`
  - 单测验证：`python -m pytest tests/test_compile_cards_effects.py tests/test_check_effect_text_coverage.py`

## 6. P1 完成记录（2026-04-17）

- 已完成 `_compile_passive_effect` 的标准落盘扩展，新增 `passive` registry 模板规则并接入模板遥测：
  - `passive.source_bp_bonus.conditional_name_in_field`
  - `passive.source_bp_bonus.always_on`
- 新增 builder：`_passive_source_bp_bonus_builder`，将以下 effect 段文本标准落盘为 `STATIC` 能力项（保留原文 `ui.text`）：
  - `自分の場に〈X〉がある場合、このキャラはBP+N。`
  - `このキャラはBP+N。`
- 结果（对比 P0 后基线 `25`）：
  - 高置信漏项由 **25** 降至 **21**；
  - 分系列由 `CGD=2, KGD=11, MCR=5, MMM=3, TLR=4` 降至 `CGD=2, KGD=9, MCR=5, MMM=2, TLR=3`。
- 验证闭环：
  - 单测验证：`python -m pytest tests/test_compile_cards_effects.py tests/test_check_effect_text_coverage.py`
  - 编译验证：`python tools/compile_cards_effects.py`
  - 覆盖度快照：`python tools/check_effect_text_coverage.py --cards-root data/cards --out-md docs/plan/high_confidence_effect_drop_list.md --write-json docs/plan/effect_coverage_baseline.json`
  - 门禁验证：`python tools/check_effect_text_coverage.py --cards-root data/cards --max-total 82 --max-series CGD=2 --max-series KGD=45 --max-series MCR=28 --max-series MMM=3 --max-series TLR=4`
