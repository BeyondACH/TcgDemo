# cards 未支持能力实施计划（全量）

> 更新日期：2026-04-14（Week 1 执行后）  
> 数据范围：`data/cards/*/cards_effects.json`（当前仓库）  
> 目标：将当前 `UNSUPPORTED` 能力从 **60** 收敛到 **0**，并建立防回归机制。

---

## 1. 当前基线

- 总未支持能力：`60`
- 涉及卡牌：`49`
- 系列分布：
  - `MCR`: 39
  - `TLR`: 21
  - `MMM`: 0
- 原因分布：
  - `当前原子要求/步骤模板尚未覆盖该文本模式。`: 59
  - `SEMANTIC_OVERRIDE_REQUIRED`: 1
- 时机分布：
  - `ON_PLAY`: 26
  - `ON_LIFE_TRIGGER`: 17
  - `ON_ENTER`: 11
  - `MAIN_ACTIVATE`: 4
  - `ON_ATTACK`: 2

---

## 2. 总体策略

1. **先高频模板族**（同句/同结构）  
   优先 `LIFE_TRIGGER_RAID_CHOICE`、`BP过滤+目标处理`、`分支二选一`，快速削减存量。
2. **再处理中复杂组合链**  
   `预览牌库 + 加手 + 余牌去向`、`条件替代阈值`、`可选成本后续结算`。
3. **最后清零长尾与单点 override**  
   专项收口 `SEMANTIC_OVERRIDE_REQUIRED`，并补齐规则回归。

---

## 3. 分阶段计划

## Phase 0：冻结与分组（0.5 天）

### 目标
- 固化能力分组、模板边界、运行时原子契约（requirement/step）。
- 明确高风险区涉及点（生命触发、攻击/阻挡、AP/能量、回合恢复）。

### 交付
- 未支持能力分组表（本文件第 5 节）
- 模板族优先级与 DoD（第 6 节）

### 验收
- 分组与 `rule.md` 口径一致。
- 不允许按卡硬编码路线。

---

## Phase 1：高收益模板收口（2~3 天）

### 目标（里程碑）
- `UNSUPPORTED: 60 -> 40`

### 范围
1. `LIFE_TRIGGER_RAID_CHOICE` 同族（MCR 高频）  
2. `BP_FILTER + BOUNCE/REMOVE` 同族  
3. 基础 `PLAY_CONDITION` 门槛模板

### 关键实现点
- 编译层：`tools/compile_cards_effects.py` 增参数化模板匹配。
- 运行时：仅增可复用 requirement/step，不加按卡分支。

### 验收
- 高频同句迁移率 >= 70%
- 无新增 `SEMANTIC_OVERRIDE_REQUIRED`

---

## Phase 2：分支与组合能力（3~4 天）

### 目标（里程碑）
- `UNSUPPORTED: 40 -> 20`

### 范围
1. `CHOOSE_ONE_BRANCH`（含“以下から1つ選ぶ”）  
2. `THRESHOLD_REPLACE`（阈值替代）  
3. `PREVIEW_TOP_DECK + ADD_TO_HAND + REORDER` 组合链  
4. `OPTIONAL_COST_THEN_EFFECT`（可选支付后继续）

### 验收
- `ON_PLAY` 未支持条目至少下降 50%
- 每个新增模板族至少一条编译回归 + 一条最小对局回归

---

## Phase 3：复杂 enter/activate/attack 与长尾（3 天）

### 目标（里程碑）
- `UNSUPPORTED: 20 -> 8`

### 范围
1. `ON_ENTER` 临时授权/阻挡限制/条件 ready  
2. `MAIN_ACTIVATE` 费用与授予联动  
3. `ON_ATTACK` “本回合已选不可重复”的 once-per-turn 分支锁

### 验收
- 覆盖 `ON_ENTER / MAIN_ACTIVATE / ON_ATTACK` 低频长尾
- 生命周期清理正确（临时关键词、临时 BP、回合标记）

---

## Phase 4：清零与稳定化（2 天）

### 目标（里程碑）
- `UNSUPPORTED: 8 -> 0`

### 范围
- 收口剩余长尾
- 专项解决 `SEMANTIC_OVERRIDE_REQUIRED`（`UA36BT_MCR_1_048`）

### 验收
- `compile_cards_effects` 输出 `Unsupported abilities: 0`
- `cards_semantic.json` 中目标条目不再 unresolved（或仅保留明确白名单并文档化）

---

## Phase 5：防回归与持续维护（并行长期）

### 目标
- 后续新增系列/新卡不回归

### 动作
1. PR 门禁加入：
   - 支持率快照对比
   - 高频模板族回归
   - 关键时机冒烟
   - `python tools/check_unsupported_budget.py --max-total 33 --max-series MCR=15 --max-series TLR=18 --max-series MMM=0`
2. 新能力准入必须同时提交：
   - 编译模板
   - 运行时原子能力
   - 测试
   - 日志/计划更新

---

## 4. 文件级施工建议

- 编译层：
  - `tools/compile_cards_effects.py`
  - `tools/card_effects_compiler/template_registry.py`（若存在对应注册入口）
  - `tools/card_effects_compiler/semantic_ir.py`（仅在必要时）
- 运行时：
  - `core/effects/requirement_matcher.gd`
  - `core/effects/step_executor.gd`
- 回归：
  - `tests/test_compile_cards_effects.py`
  - `docs/cards_raw_minimal_duel_smoke_test.gd`
  - （必要时）`docs/milestone_smoke_test.gd`
- 文档：
  - `docs/logs/log_yyyy-MM-dd.md`
  - 若改变主线策略，同步 `docs/plan/development_plan.md`
  - `docs/plan/unsupported_budget_baseline.json`（每次阶段收敛后刷新）

---

## 5. 按卡号排序实施清单（全量）

> 格式：`卡号 - 未支持条数 - 时机 - 建议模板族`

### MCR
1. `UA36BT_MCR_1_011` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
2. `UA36BT_MCR_1_012` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
3. `UA36BT_MCR_1_022` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
4. `UA36BT_MCR_1_023` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
5. `UA36BT_MCR_1_028` - 1 - `ON_PLAY` - `OUTSIDE_TO_HAND + COST_BY_REST_FRONT + READY_AP`
6. `UA36BT_MCR_1_029` - 1 - `ON_PLAY` - `PREVIEW_TOP_DECK + ADD_TO_HAND + RAID_STACK_INTERACT`
7. `UA36BT_MCR_1_030` - 3 - `ON_PLAY` - `PLAY_CONDITION + CHOOSE_ONE_BRANCH`
8. `UA36BT_MCR_1_031` - 1 - `ON_PLAY` - `BP_FILTER + CONDITIONAL_REPLACE_EFFECT`
9. `UA36BT_MCR_1_032` - 1 - `ON_PLAY` - `BUFF+DRAW+CONDITIONAL_EXTRA_DRAW`
10. `UA36BT_MCR_1_033` - 1 - `ON_PLAY` - `DRAW_THEN_DISCARD + OUTSIDE_TO_FRONT`
11. `UA36BT_MCR_1_041` - 1 - `ON_LIFE_TRIGGER` - `BP_FILTER_BOUNCE`
12. `UA36BT_MCR_1_044` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
13. `UA36BT_MCR_1_045` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
14. `UA36BT_MCR_1_048` - 1 - `ON_PLAY` - `SEMANTIC_OVERRIDE_REQUIRED`（专项）
15. `UA36BT_MCR_1_049` - 2 - `ON_PLAY` - `PLAY_CONDITION + BP_FILTER_REMOVE`
16. `UA36BT_MCR_1_057` - 1 - `ON_LIFE_TRIGGER` - `BP_FILTER_BOUNCE`
17. `UA36BT_MCR_1_060` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
18. `UA36BT_MCR_1_062` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
19. `UA36BT_MCR_1_063` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
20. `UA36BT_MCR_1_065` - 4 - `ON_PLAY` - `CHOOSE_ONE_BRANCH + THRESHOLD_REPLACE + PREVIEW_1_TOPBOTTOM`
21. `UA36BT_MCR_1_079` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
22. `UA36BT_MCR_1_091` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
23. `UA36BT_MCR_1_092` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
24. `UA36BT_MCR_1_093` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`
25. `UA36BT_MCR_1_098` - 1 - `ON_PLAY` - `BP_FILTER_REMOVE + CONDITIONAL_UPGRADE`
26. `UA36BT_MCR_1_099` - 1 - `ON_PLAY` - `BP_FILTER_MOVE_TO_OPP_DECK_TOP_OR_BOTTOM`
27. `UA36BT_MCR_1_100` - 1 - `ON_PLAY` - `DRAW_2 + CONDITIONAL_READY_AND_BUFF`
28. `UA36ST_MCR_1_057` - 1 - `ON_LIFE_TRIGGER` - `BP_FILTER_BOUNCE`
29. `UA36ST_MCR_1_065` - 4 - `ON_PLAY` - 同 `UA36BT_MCR_1_065`
30. `UA36ST_MCR_1_107` - 1 - `ON_LIFE_TRIGGER` - `LIFE_TRIGGER_RAID_CHOICE`

### TLR
31. `UA45BT_TLR_1_001` - 1 - `MAIN_ACTIVATE` - `SELECT_ALLIED_PAIR_BUFF`
32. `UA45BT_TLR_1_013` - 1 - `ON_ENTER` - `GRANT_TEMP_BLOCK_RESTRICTION`
33. `UA45BT_TLR_1_015` - 1 - `MAIN_ACTIVATE` - `GRANT_TEMP_BLOCK_RESTRICTION`
34. `UA45BT_TLR_1_021` - 1 - `ON_ENTER` - `CONDITIONAL_DEBUFF`
35. `UA45BT_TLR_1_023` - 2 - `ON_ENTER/MAIN_ACTIVATE` - `REST_AND_LOCK + BP_DEBUFF`
36. `UA45BT_TLR_1_026` - 1 - `MAIN_ACTIVATE` - `REST_ALLY_COST_GRANT_KEYWORD`
37. `UA45BT_TLR_1_027` - 1 - `ON_ENTER` - `OPTIONAL_DISCARD_TO_READY_SELF`
38. `UA45BT_TLR_1_037` - 1 - `ON_PLAY` - `BP_REMOVE + CONDITIONAL_DRAW`
39. `UA45BT_TLR_1_039` - 1 - `ON_PLAY` - `BP_REMOVE_TO_REMOVED + CONDITIONAL_THRESHOLD_SWAP`
40. `UA45BT_TLR_1_043` - 1 - `ON_ENTER` - `HAND_TO_FRONT_FILTER + CONDITIONAL_READY`
41. `UA45BT_TLR_1_047` - 1 - `ON_ENTER` - `GRANT_BLOCK_FORBIDDEN + CONDITIONAL_BP_UPGRADE`
42. `UA45BT_TLR_1_048` - 1 - `ON_ENTER` - `GRANT_TEMP_ON_HIT_REMOVE_EFFECT`
43. `UA45BT_TLR_1_052` - 1 - `ON_ENTER` - `SCALING_BUFF_BY_BOARD_COUNT`
44. `UA45BT_TLR_1_060` - 1 - `ON_ENTER` - `ENERGY_TO_FRONT_IF_SLOT_OPEN`
45. `UA45BT_TLR_1_062` - 1 - `ON_ATTACK` - `ONCE_PER_TURN_CHOOSE_ONE_LOCKOUT`
46. `UA45BT_TLR_1_063` - 1 - `ON_ENTER` - `BUFF_TARGET_IF_NAME_THEN_READY`
47. `UA45BT_TLR_1_069` - 1 - `ON_ATTACK` - `ONCE_PER_TURN_CHOOSE_ONE_LOCKOUT`
48. `UA45BT_TLR_1_072` - 1 - `ON_ENTER` - `PREVIEW_2_REORDER_TOP_BOTTOM`
49. `UA45BT_TLR_1_081` - 2 - `ON_PLAY` - `CHOOSE_ONE_BRANCH(REMOVE or BUFF+DRAW)`

---

## 6. DoD（完成判定）

每个阶段都必须满足：

1. 规则一致性：不偏离 `rule.md`
2. 实现方式：无按卡硬编码；新增能力可复用
3. 回归要求：至少 1 条编译回归 + 1 条最小对局回归
4. 生命周期：临时状态可正确清理
5. 文档同步：同日更新 `docs/logs/log_yyyy-MM-dd.md`
6. 中文编码：UTF-8 复读与 `git diff` 复核通过

---

## 7. 推荐排期（可滚动）

- Week 1：Phase 0 + Phase 1
- Week 2：Phase 2
- Week 3：Phase 3 + Phase 4
- Week 4+：Phase 5 持续防回归

---

## 8. Week 1 执行结果（2026-04-14）

- 本周目标：`Phase 0 + Phase 1`
- 实际结果：`UNSUPPORTED 60 -> 40`（达成 `Phase 1` 里程碑）
- 收敛来源：
  - `LIFE_TRIGGER_RAID_CHOICE` 模板化
  - `BP_FILTER_BOUNCE` 模板化
  - `ON_PLAY` 条件预览与基础出牌条件语句归一
- 当前门禁基线命令：
  - `python tools/check_unsupported_budget.py --max-total 40 --max-series MCR=19 --max-series TLR=21 --max-series MMM=0`

---

## 9. Week 2 执行进度（2026-04-14）

- 本周目标：`Phase 2`（`40 -> 20`）
- 当前进度：`UNSUPPORTED 40 -> 33`（持续收敛中）
- 本轮新增收敛模板：
  - `BP_THRESHOLD_REMOVE`（`card name contains` 条件替代）
  - `BP_DEBUFF`（基础/条件型）
  - `OPTIONAL_COST_THEN_EFFECT`（可选弃牌后自我 ready）
  - `PLAY_CONDITION` / `AP_COST_MODIFIER`（`card name contains` 语句）
- 当前门禁基线命令：
  - `python tools/check_unsupported_budget.py --max-total 33 --max-series MCR=15 --max-series TLR=18 --max-series MMM=0`
