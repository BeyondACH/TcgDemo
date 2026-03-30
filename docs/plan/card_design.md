# cards_effects 当前真实缺口与优先级

## 当前状态

- 统计基线以 `data/cards/cards_effects.json` 与 `data/cards/cards_semantic.json` 为准，而不是旧版计划文档。
- 截至 2026-03-30 当前共编译 `99` 张卡，运行时能力统计为：
  - `SUPPORTED`：`128`
  - `UNSUPPORTED`：`0`
- 当前已不存在未支持能力卡牌，Phase 1“补齐剩余未支持模板”的目标已完成。
- 当前正式验证基线为：
  - `docs/cards_raw_minimal_duel_smoke_test.gd`：`66 / 0`
  - `docs/milestone_smoke_test.gd`：`32 / 0`
- 本文件的职责不再是复述一整批已经过期的“历史待办”，而是记录当前真实缺口、优先级和验证入口。

## 复核结论

### `UA31BT_MMM_1_056` 已转为 `SUPPORTED`

- 已补齐“己方场上其他指定特征卡数量 >= 4”的精确 requirement。
- 已把后半段统一表达为：条件满足时，为 `SOURCE_CARD` 追加本回合临时 `IMPACT`。
- `056` 现已不再属于当前未支持能力集合；对应 raw 回归已补到 `docs/cards_raw_minimal_duel_smoke_test.gd`。

## 当前状态结论

### Phase 1 已完成

- 已补齐最后一批高耦合模板，包括：
  - 指定名称存在于指定区域
  - 来源 `ACTIVE / entered_this_turn / BP` requirement
  - 条件化 BP provider 与动态 BP 阈值
  - 选择己方其他角色、批量己方目标、`OPTION_SET`
  - 位置交换、raid 元卡回手、按本次目标减 AP
  - `DRAW -> DISCARD`、临时 BP / 关键词、命中检索后继续结算
- `cards_effects.json` 已不存在 `abilities[*].status == UNSUPPORTED`。
- 当前计划主线应从“补模板”切换为“稳固共性回归 + 收尾 P2”。

## 真实优先级

### P0：复杂 raw 组合回归与剩余高耦合模板

- 该阶段已完成。
- 目前 `docs/cards_raw_minimal_duel_smoke_test.gd` 已覆盖复杂组合链，包括：
  - 跨完整回合生命周期
  - 离场触发链与 raid 元卡回手
  - 临时能力授予与过期
  - 预览链 + 命中/未命中分支
  - 事件按目标减费与位置交换
- 后续若新增卡池或 DSL/IR 能力，仍应沿用同一原则：先补通用 requirement / target / step，再补正式 raw 样例。

### P1：规则共性稳定性回归

- 当前进入主阶段，围绕 `docs/milestone_smoke_test.gd` 继续增补共性规则断言，重点观察：
  - `delayed_effects` 是否按回合正确过期
  - `pending_decisions` 是否在复杂链后清空
  - `effect_queue` 是否在显式决策后恢复并耗尽
  - `battle_context` 是否在 ON_LEAVE / 延迟效果 / 叠放离场后不残留脏状态
- 当前已补的共性断言至少包括：
  - 本回合临时关键词结束时清理
  - `entered_this_turn` 在下个自己回合开始时清理
  - 多个结束主阶段延迟效果不残留脏状态
- 若后续新增高风险规则修复，仍先补主冒烟，再扩正式 raw 样例。

### P2：非高风险收尾项

- 现在可以开始处理低风险收尾，而不是继续围绕 `UNSUPPORTED` 展开：
  - 更完整的日志输出
  - 完善 `ui/card_preview_panel.gd`
  - 复核“开始游戏前弹窗选择双方卡组”
  - 复核“开始时的卡组打乱逻辑”
- 若改动触及预览流、日志面板或布局消费，额外执行 `--layout-probe`，并记录“手牌区域不遮挡战场区域”的结果。

## 接口冻结项

- 若继续实现当前未支持能力，优先冻结 `tools/compile_cards_effects.py` 的 IR 输出，再改 `core/effect_resolver.gd` 的 requirement / target / step 解释器。
- `GameManager.get_snapshot()` 与 UI 待决策流继续保持只读消费关系，UI 不反向承载规则判断。
- `RAID` 元卡引用、位置交换、事件减费仍归规则层 / 出牌规则层处理，不回退到效果步骤按卡特判。

## 验收要求

- 每次计划口径调整后，都要重新以 `cards_effects.json` 的 `abilities[*].status` 统计结果作为文档基线。
- 每次补新的 raw 模板、原子能力，或完成阶段性收口，都要同步更新：
  - `tools/compile_cards_effects.py`
  - `data/cards/cards_effects.json`
  - 对应回归脚本
- 当前推荐验证入口固定为：
  - 规则主冒烟：`docs/milestone_smoke_test.gd`
  - 正式 raw 样例：`docs/cards_raw_minimal_duel_smoke_test.gd`
- 若改动触及预览流或布局消费，额外执行 `--layout-probe`，并记录“手牌区域不遮挡战场区域”的验收结果。
