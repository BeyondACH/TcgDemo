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
