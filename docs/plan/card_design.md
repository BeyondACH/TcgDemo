# cards_effects 当前真实缺口与优先级

## 当前状态

- 统计基线以 `data/cards/cards_effects.json` 与 `data/cards/cards_semantic.json` 为准，而不是旧版计划文档。
- 截至 2026-03-30 当前共编译 `99` 张卡，运行时能力统计为：
  - `SUPPORTED`：`112`
  - `UNSUPPORTED`：`17`
- 当前存在未支持能力的卡牌共有 `13` 张，而不是旧文档中的 `16` 张。
- 未支持能力按时机分布为：
  - `MAIN_ACTIVATE`：`5`
  - `ON_PLAY`：`5`
  - `ON_ENTER`：`4`
  - `ON_ATTACK`：`2`
  - `ON_LEAVE`：`1`
- 本文件的职责不再是复述一整批已经过期的“历史待办”，而是记录当前真实缺口、优先级和验证入口。

## 复核结论

### `UA31BT_MMM_1_056` 已转为 `SUPPORTED`

- 已补齐“己方场上其他指定特征卡数量 >= 4”的精确 requirement。
- 已把后半段统一表达为：条件满足时，为 `SOURCE_CARD` 追加本回合临时 `IMPACT`。
- `056` 现已不再属于当前未支持能力集合；对应 raw 回归已补到 `docs/cards_raw_minimal_duel_smoke_test.gd`。

## 当前真实缺口

### 当前仍为 `UNSUPPORTED` 的卡牌

- `UA31BT_MMM_1_035`
- `UA31BT_MMM_1_036`
- `UA31BT_MMM_1_038`
- `UA31BT_MMM_1_041`
- `UA31BT_MMM_1_044`
- `UA31BT_MMM_1_049`
- `UA31BT_MMM_1_052`
- `UA31BT_MMM_1_055`
- `UA31BT_MMM_1_060`
- `UA31BT_MMM_1_062`
- `UA31BT_MMM_1_064`
- `UA31BT_MMM_1_066`
- `UA31BT_MMM_1_067`

### 缺口类别归纳

- requirement / 数值提供器
  - 指定名称或特征在指定区域存在
  - 登场回合限定、自身 ACTIVE 限定、自身 BP 阈值限定
  - 条件化阈值替换、动态 BP 阈值
- target / zone / play rule
  - 选择“自己的其他角色”
  - 选择批量己方目标
  - 位置交换
  - RAID 元卡引用
  - 事件以特定对象为目标时的 AP 减费
- step / 组合链
  - `DRAW -> DISCARD`
  - 临时 BP 修正
  - 临时授予 `IMPACT / DOUBLE_ATTACK / IMPACT_PLUS_1`
  - 可选分支后继续结算
  - 命中检索后的额外奖励

## 真实优先级

### P0：复杂 raw 组合回归与剩余高耦合模板

- `UA31BT_MMM_1_056` 已完成收口，当前 P0 重心转为继续压实复杂组合回归，并为下一批未支持模板提供稳定观察入口。
- 在 `docs/cards_raw_minimal_duel_smoke_test.gd` 中优先补以下复杂组合回归：
  - 跨完整回合生命周期
  - 离场触发链与延迟效果叠加
  - 临时能力授予与过期
  - 预览链 + 条件追加授能模板
- 若继续推进剩余未支持能力，优先处理 requirement / step 高耦合项，不从 P2 UI/日志项切入。

### P1：规则共性稳定性回归

- 围绕 `docs/milestone_smoke_test.gd` 增补共性规则断言，重点观察：
  - `delayed_effects` 是否按回合正确过期
  - `pending_decisions` 是否在复杂链后清空
  - `effect_queue` 是否在显式决策后恢复并耗尽
  - `battle_context` 是否在 ON_LEAVE / 延迟效果 / 叠放离场后不残留脏状态
- 若后续新增高风险规则修复，先补主冒烟，再扩正式 raw 样例。

## 接口冻结项

- 若继续实现当前未支持能力，优先冻结 `tools/compile_cards_effects.py` 的 IR 输出，再改 `core/effect_resolver.gd` 的 requirement / target / step 解释器。
- `GameManager.get_snapshot()` 与 UI 待决策流继续保持只读消费关系，UI 不反向承载规则判断。
- `RAID` 元卡引用、位置交换、事件减费仍归规则层 / 出牌规则层处理，不回退到效果步骤按卡特判。

## 验收要求

- 每次计划口径调整后，都要重新以 `cards_effects.json` 的 `abilities[*].status` 统计结果作为文档基线。
- 每次补新的 raw 模板或原子能力，都要同步更新：
  - `tools/compile_cards_effects.py`
  - `data/cards/cards_effects.json`
  - 对应回归脚本
- 当前推荐验证入口固定为：
  - 规则主冒烟：`docs/milestone_smoke_test.gd`
  - 正式 raw 样例：`docs/cards_raw_minimal_duel_smoke_test.gd`
- 若改动触及预览流或布局消费，额外执行 `--layout-probe`，并记录“手牌区域不遮挡战场区域”的验收结果。
