# 重构实施计划

> 基于 2026-06-05 架构评估报告制定，2026-06-06 经代码库逐项核验修订。目标：消除代码重复、解除循环依赖、统一编码模式，在 2-3 轮迭代窗口内把代码质量拉回健康线。

---

## 总体策略

### 执行原则

1. **每个 Phase 独立可合入**：每完成一个 Phase，冒烟测试必须全部通过，代码可正常工作
2. **先修 Bug，再调结构，最后清理**：P0 → P1 → P2 → P3 顺序严格
3. **每步必验**：修改 ≥3 个文件后，运行冒烟测试
4. **禁绝回归**：重构不改变任何游戏行为，只改变代码组织

### 冒烟测试基线（重构前）

> **⚠️ 待实测确认**：以下数字来自 2026-06-06 评估，与 `development_plan.md`（2026-04-17 记录：cards_raw 80、residue 10）存在差异。Phase 0 启动前必须用 Godot headless 实际跑一遍五项核心测试，以实测结果覆盖此处基线。

```
milestone_smoke_test.gd                 : 33 通过, 0 失败
cards_raw_minimal_duel_smoke_test.gd    : 69 通过, 0 失败
runtime_residue_smoke_test.gd           : 4 通过, 0 失败
simple_ai_v2_smoke_test.gd              : 6 通过, 0 失败
vs_ai_smoke_test.gd                     : 2 通过, 0 失败
```

以上五项为核心冒烟基线，每次 Phase 完成后必须保持全部通过。test/ 目录下另有 9 个专项冒烟测试（active_energy_bonus、card_image_path、draw_phase、hand_available_actions、legal_actions、life_reveal_modal、long_run_stability、preview_selection_modal、starter_a_txt_raw），在涉及相关模块的 Task 中作为补充验证。

---

## Phase 0 — Bug 级修复（预计 1 小时）

> 修复已确认会导致错误行为的代码。不涉及结构变更，风险最低，最先执行。

### Task 0.1: 统一 `_parse_zone` 到 UATypes

- **问题**：`_parse_zone` 在 4 个文件中各自实现，且实现细节不一致：
  - `effect_resolver.gd` 和 `target_selector.gd`：使用 if-elif 链，同时处理大小写（如 `"DECK"` 和 `"deck"`）
  - `step_executor.gd` 和 `requirement_matcher.gd`：使用 match 语句，仅匹配大写，小写输入会静默返回 null
  - `target_selector.gd` 对无效输入返回 `UATypes.Zone.OUTSIDE`，可能静默将卡牌移到错误区域
  - `effect_resolver.gd` 对无效输入返回 `-1`
- **方案**：在 `UATypes` 添加 `static func key_to_zone(s: String) -> int`：
  - 同时处理大小写输入
  - 无效输入返回 `-1`
  - 所有调用方检查返回值是否为 `-1`
- **⚠️ target_selector 行为变更**：`target_selector.gd` L166-168 原对无效输入返回 `OUTSIDE`（直接用于区域筛选），改为 `-1` 后筛选逻辑会静默匹配空集。**已定案：调用处加 `-1` 校验**，若为 `-1` 则 push_warning 并跳过该 zone 条件。
- **影响文件**：
  - `core/ua_types.gd` — 新增 `key_to_zone` 方法
  - `core/effect_resolver.gd` — 删除 `_parse_zone`，调用处改为 `UATypes.key_to_zone()`
  - `core/effects/step_executor.gd` — 同上
  - `core/effects/target_selector.gd` — 同上（**修复默认返回值 bug**）
  - `core/effects/requirement_matcher.gd` — 同上
- **验证**：运行 `milestone_smoke_test.gd` 和 `cards_raw_minimal_duel_smoke_test.gd`
- **工作量**：45 分钟

### Task 0.2: 修复 `consume_timed_delayed_effects` 修饰符丢弃逻辑

- **问题**：`effect_resolver.gd` L326-335，当 delayed_effect 的 filter 不匹配且过期类型为 `END_OF_TURN` / `UNTIL_NEXT_SELF_TURN_START` 时，修饰符被静默丢弃（未加入 remaining 列表）。这与预期行为相反——这些修饰符应由专门的 cleanup 函数（`cleanup_turn_expirations` / `cleanup_start_turn_expirations`）来清理，而非在消费时丢弃。
- **方案**：不匹配的修饰符无论如何都应保留在 remaining 中；仅当 `once=true` 且已匹配时才丢弃。修改逻辑为：匹配且 once → 丢弃；其他情况 → 保留。
- **影响文件**：
  - `core/effect_resolver.gd` — `consume_timed_delayed_effects` 方法
- **验证**：运行 `runtime_residue_smoke_test.gd`（残留检查）
- **工作量**：30 分钟

### Task 0.3: 删除 play_card 死代码

- **问题**：`game_manager.gd` L207-228 中，L226-228 与 L209-225 的 if 条件**完全相同**（均判断 `raid_target.zone == ENERGY_LINE and not play_options.has("raid_target_zone_choice")`）。由于 L225 的 `return` 在条件命中时必定返回，L226-228 为永远不可达的死代码。
- **⚠️ 已核验**：L226 的条件是 `not play_options.has(...)`，与"回退逻辑"声称的"已有 zone_choice"语义相反——即使删除 L225 的 return、保留 L226-228，当玩家已做出选择后重入时条件同样为 false，该段依然不可达。因此这不是"缺 return"的 bug，而是**复制粘贴残留的死代码块**。
- **方案**：删除 L226-228（3 行死代码块），保留 L225 的 `return`（正确的 pending_gate 返回）。无需修改 L225。
- **影响文件**：
  - `core/game_manager.gd` — 删除 3 行（L226-228）
- **验证**：编译通过即可，运行 `milestone_smoke_test.gd`
- **工作量**：5 分钟

---

## Phase 1 — 消除重复与解除反向依赖（预计 7-9 小时）

> 创建共享工具类、消除循环依赖、统一分发模式。结构变更但不改变行为。

### Task 1.1: 创建 `EffectUtils` 共享工具类

- **问题**：约 9 个工具函数在 2-4 个文件中重复实现，共 ~200 行重复代码
- **方案**：创建 `core/effects/effect_utils.gd`，将这些函数统一到一处，全部声明为 `static func`。所有调用方改为引用 `EffectUtils.xxx()`
- **移入 EffectUtils 的函数清单**（已核验实际重复情况）：

| 函数 | 实际重复文件数 | 文件 |
|---|---|---|
| `parse_zone(value) -> int` | 已由 Task 0.1 移到 UATypes | — |
| `parse_card_state(value) -> int` | 3 | effect_resolver, step_executor, requirement_matcher |
| `ensure_array(value) -> Array` | 4 | effect_resolver, step_executor, target_selector, requirement_matcher |
| `array_without_values(src, remove) -> Array` | 2 | effect_resolver, step_executor |
| `context_value_is_non_empty(value) -> bool` | 2 | effect_resolver, step_executor |
| `format_target_choice_label(card_def) -> String` | 3 | effect_resolver, target_selector, step_executor |
| `format_energy_cost_text(energy_map) -> String` | 3 | effect_resolver, target_selector, step_executor |
| `format_modifier_expiry_text(expires) -> String` | 2 | effect_resolver, step_executor |
| `resolve_step_target_uid(effect, context, fallback) -> String` | 2 | effect_resolver, step_executor |
| `_card_energy_cost_total(card_def) -> int` | 2 | effect_resolver, requirement_matcher |
| `_card_matches_color(card_def, color) -> bool` | 2 | effect_resolver, requirement_matcher |

- **不纳入 EffectUtils 的函数**（仅在 target_selector.gd 中存在，无重复）：
  - `register_preview_ui_meta` / `get_preview_ui_meta` / `build_preview_pick_ui_meta` / `build_preview_reorder_ui_meta`

- **影响文件**：
  - `core/effects/effect_utils.gd` — **新建**
  - `core/effect_resolver.gd` — 删除重复函数，调用改为 EffectUtils
  - `core/effects/step_executor.gd` — 同上
  - `core/effects/target_selector.gd` — 同上
  - `core/effects/requirement_matcher.gd` — 同上（仅 `ensure_array` 和 `parse_card_state`）
- **验证**：全部五项冒烟测试
- **工作量**：1-1.5 小时（缩减自原估计 2-3 小时）
- **技能**：`godot-prompter:gdscript-patterns`
- **⚠️ `ensure_array` 语义分歧**：统一前需确认最终行为。当前 4 个实现在非数组入参时行为不同：
  - `effect_resolver.gd`：缺少 null 分支（可能报错退出）
  - `step_executor.gd`：null/空串 → `[]`，其他值 → `[value]`（包装）
  - `target_selector.gd` / `requirement_matcher.gd`：null/非数组 → `[]`（静默丢弃）
  - 统一后的 `EffectUtils.ensure_array(value)` 应采用哪种语义，必须在移入前确认并记录。**已定案：采用 `step_executor` 的包装语义**（null/空 → `[]`，其他值 → `[value]`），所有调用点需审计确保不依赖旧有的静默丢弃行为。
- **⚠️ `parse_card_state` 返回值分歧**：无效输入时各实现返回值不同：
  - `effect_resolver.gd` / `step_executor.gd`：返回 `UATypes.CardState.RESTED`（兜底为 RESTED）
  - `requirement_matcher.gd`：match 无通配分支，无效 String 会走到隐式 fallback（约等于返回 `0` 或触发 warning）
  - 统一后的 `EffectUtils.parse_card_state(value)` 应统一返回值策略。**已定案：无效输入显式返回 `-1`**，所有调用点需检查返回值。

### Task 1.2: 将 keyword 管理移入 CardInstance

- **问题**：`_add_runtime_keyword` 和 `_remove_runtime_keyword` 在 3 个文件中重复实现（effect_resolver、step_executor、zone_manager），`_card_has_keyword` / `_card_has_runtime_keyword` 在 3 个文件中各自实现（battle_resolver、rules_engine、game_manager），逻辑完全相同
- **方案**：在 `CardInstance` 添加三个方法：
  - `add_temp_keyword(keyword: String) -> void`
  - `remove_temp_keyword(keyword: String) -> void`
  - `has_temp_keyword(keyword: String) -> bool`
  - `has_any_temp_keyword() -> bool`
- **影响文件**：
  - `data/card_instance.gd` — 新增方法
  - `core/effect_resolver.gd` — 删除 `_add_runtime_keyword` / `_remove_runtime_keyword`，调用处改为 `card.add_temp_keyword()` / `card.remove_temp_keyword()`
  - `core/effects/step_executor.gd` — 同上
  - `core/zone_manager.gd` — 同上
  - `core/game_manager.gd` — `_card_has_runtime_keyword` 改为 `card_def.keywords.has(kw) or card.has_temp_keyword(kw)`
  - `core/rules_engine.gd` — `_card_has_keyword` 同上
  - `core/battle_resolver.gd` — `_card_has_keyword` 同上
- **验证**：全部五项冒烟测试
- **工作量**：1 小时
- **技能**：`godot-prompter:gdscript-patterns`

### Task 1.3: 解除 StepExecutor/TargetSelector → EffectResolver 反向依赖

- **问题**：4 个 effect 子模块持有 `_effect_resolver` 引用，形成紧密耦合。其中最严重的是 `step_executor.gd`，有 **17 处** 反向调用（`_requirements_met`、`_execute_operation`、`_matches_filter_list`、`_resolve_target_set`、`_resolve_numeric_value`、`preview_play_modifiers`、`commit_play_modifiers`、`move_pending_life_card_to_hand` 等）
- **方案**：
  - StepExecutor 改为注入 `ZoneManager` + `VictoryChecker` + `RulesEngine` + `RequirementMatcher`（而不是 EffectResolver）
  - 将 `_execute_operation` 也从 EffectResolver 移到 StepExecutor（或独立的 OperationExecutor）
  - `_resolve_numeric_value` 移到 EffectUtils（作为静态方法，所依赖的 `_requirements_met` 通过 RequirementMatcher 调用）
  - `_enqueue_life_trigger_raid_choice` 中的 `_effect_resolver.move_pending_life_card_to_hand` 改为直接调用 EffectUtils（该函数是纯状态操作，不依赖队列）
- **影响文件**：
  - `core/effect_resolver.gd` — 构造函数传参调整，删除间接委托方法
  - `core/effects/step_executor.gd` — 构造函数改为接收具体依赖
  - `core/effects/target_selector.gd` — 同上
  - `core/effects/requirement_matcher.gd` — 同上
  - `core/effects/life_damage_handler.gd` — 同上
- **验证**：全部五项冒烟测试 + `life_reveal_modal_smoke_test.gd`
- **工作量**：3-4 小时
- **技能**：`godot-prompter:component-system`, `godot-prompter:gdscript-advanced`

### Task 1.4: `_execute_operation` 改为字典分发

- **问题**：`EffectResolver._execute_operation` 使用 10 分支 if-elif 链，与 StepExecutor 的字典分发模式不一致。此外 `ACTIVATE` 和 `ACTIVATE_CARD` 两分支完全相同（L471-484），可合并
- **方案**：在 EffectResolver 内部创建 `_operation_handlers` 字典，将每个操作类型映射到 handler 方法。合并 `ACTIVATE` / `ACTIVATE_CARD` 为一个 handler
- **影响文件**：
  - `core/effect_resolver.gd` — 新增 `_operation_handlers` 字典和 `_init_operation_handlers()` 方法，重写 `_execute_operation` 为字典查找
- **验证**：全部五项冒烟测试（覆盖所有操作类型）
- **工作量**：1-2 小时
- **技能**：`godot-prompter:gdscript-patterns`

---

## Phase 2 — 核心模块瘦身与 UI 拆分（预计 13-18 小时）

> 削减大文件行数、消除 GameManager 中的业务逻辑、拆分 BattleScene。

### Task 2.1: GameManager 瘦身 — 移除重复的业务逻辑

- **问题**：GameManager（982 行）中 ~50% 代码是业务逻辑而非协调逻辑
- **方案**（分步执行）：

**Step A — 移除 `_available_actions_for_card`（~45 行）**
  - GameManager 中的实现与 RulesEngine `get_card_available_actions` / `_project_action_name` 功能重复
  - **⚠️ 兼容性验证**：两套机制不同——GameManager 直接检查区域/卡牌类型/关键词，RulesEngine 走 Action 系统（`ActionTypes`）。`SNIPER_ATTACK` 等 action 字符串在两套机制中可能不一致
  - **前置步骤**：先编写对比测试脚本，在全卡片范围验证两套机制返回相同 action 集合，确认无误后再替换
  - 删除 GameManager 版本，UI 层改为调用 `rules_engine.get_card_available_actions(state, player_id, card_uid)` 返回的字符串数组

**Step B — 移除 `_can_play_to_front_line/energy_line`（~25 行）**
  - 这些是纯校验逻辑，应属于 RulesEngine
  - `rules_engine.can_play_card` 已包含区域容量、AP、能量校验
  - **前置步骤**：对比 `_can_play_to_front_line`/`_can_play_to_energy_line` 与 `can_play_card` 的校验覆盖度，确保等价后替换
  - 删除 GameManager 版本，改用 `rules_engine.can_play_card()`

**Step C — 提取 MulliganManager（~60 行）**
  - 新建 `core/mulligan_manager.gd`
  - 从 GameManager 移入：`_enqueue_mulligan_decision`, `_resolve_mulligan_decision`, `_apply_mulligan_choice`
  - GameManager 保留薄包装调用 MulliganManager

- **影响文件**：
  - `core/game_manager.gd` — 缩减约 130 行
  - `core/rules_engine.gd` — 确认 `get_card_available_actions` 可用
  - `core/mulligan_manager.gd` — **新建**
  - `ui/battle_scene.gd` — 可能需更新 action 判断逻辑
- **验证**：全部五项冒烟测试 + 兼容性对比测试脚本
- **工作量**：4-6 小时
- **技能**：`godot-prompter:component-system`, `godot-prompter:scene-organization`

### Task 2.2: 消除 LifeTriggerManager → GameManager 反向依赖

- **问题**：LifeTriggerManager 通过 `_game_manager` + `_play_card_callback` + `_enqueue_decision_callback` 反向调用 GameManager
- **方案**：将 `_play_card_callback` 和 `_enqueue_decision_callback` 改为显式接口：
  - 方案 A：LifeTriggerManager 发出信号（`life_trigger_play_card_requested`），GameManager 监听 → 调用 play_card。简单但增加了一个间接层。
  - **推荐方案 B**：直接在 LifeTriggerManager 中注入 `RulesEngine` + `ZoneManager` + `EffectResolver`，它需要的操作（`move_pending_life_card_to_hand`、`finalize_pending_life_damage`）直接调用 EffectResolver；它需要的 `play_card` 逻辑改为直接调用 `zone_manager.move_card` + `effect_resolver.resolve_trigger`，不再绕回 GameManager
- **影响文件**：
  - `core/life_trigger_manager.gd` — 构造函数改为接收具体依赖，移除 callback
  - `core/game_manager.gd` — 移除 callback 设置代码
- **验证**：`life_reveal_modal_smoke_test.gd` + `vs_ai_smoke_test.gd`
- **工作量**：2-3 小时
- **技能**：`godot-prompter:component-system`

### Task 2.3: BattleScene 拆分

- **问题**：BattleScene 1376 行，承担了布局计算、布局验证、AI 提示动画、卡组选择、手牌交互、战场交互、Log 面板、Modal 管理等过多职责
- **方案**：提取以下独立组件（均作为 BattleScene 的子节点或同级 Control）：

| 新组件 | 职责 | 从 BattleScene 移出的内容 | 预计行数 |
|---|---|---|---|
| `LayoutValidator` | 布局完整性校验 | `_verify_layout()` 及相关 helper（~70 行） | ~80 行 |
| `AIActionHint` | AI 动作提示淡入淡出 | `_show_ai_action_hint()` 等（~50 行） | ~60 行 |
| `DeckSelector` | 卡组选择 Modal 逻辑 | `_populate_deck_selectors()` 等（~80 行） | ~100 行 |
| `BoardInteractionHandler` | 战场点击/悬停路由 | 战场相关 input 处理（~120 行） | ~150 行 |

- **影响文件**：
  - `ui/battle_scene.gd` — 缩减至 ~900 行（协调 + HUD 更新）
  - `ui/layout_validator.gd` — **新建**
  - `ui/ai_action_hint.gd` — **新建**
  - `ui/deck_selector.gd` — **新建**
  - `ui/board_interaction_handler.gd` — **新建**
  - `scenes/battle_scene.tscn` — 新增子节点
- **验证**：人工启动游戏验证 UI 布局不遮挡、手牌交互正常、AI 提示动画正常
- **工作量**：4-6 小时
- **技能**：`godot-prompter:godot-ui`, `godot-prompter:scene-organization`

### Task 2.4: 全量类型标注

- **问题**：核心模块大量变量、参数、返回值缺少类型提示
- **方案**：逐文件添加类型标注，优先处理 `core/` 下的所有文件。**注意**：此任务应在 Phase 2 其他重构完成后执行，否则后续代码移动会使标注失效
- **清单**（按优先级）：
  - `core/effect_resolver.gd`（1337 行）— 所有 var、func 参数、func 返回值
  - `core/game_manager.gd`（982 行）— 同上
  - `core/rules_engine.gd`（879 行）— 同上
  - `core/battle_resolver.gd`（300 行）— 同上
  - `core/effects/*.gd` — 同上
  - `core/life_trigger_manager.gd`（279 行）— 同上
  - `core/turn_manager.gd` — 同上
  - `data/*.gd` — 确认已有类型
- **验证**：编译零 warning，冒烟测试全部通过
- **工作量**：3-4 小时
- **技能**：`godot-prompter:gdscript-patterns`

---

## Phase 3 — 技术债务清理（预计 5-6 小时）

> 不紧急但重要的收尾工作。

### Task 3.1: `emit_signal()` → `.emit()` 迁移

- **问题**：项目中存在 18 处旧的字符串形式 `emit_signal("signal_name", ...)`（分布在 `ui/card_view.gd`、`ui/board_view.gd`、`ui/hand_view.gd`、`ui/drop_zone.gd`、`ui/zone_stack_summary_view.gd`、`ui/zone_cards_popup.gd`、`core/game_manager.gd`、`test/preview_selection_modal_smoke_test.gd`）
- **方案**：全项目搜索 `emit_signal(` 替换为 `signal_name.emit(`
- **影响文件**：所有 .gd 文件中的信号发射点
- **验证**：全部冒烟测试
- **工作量**：30 分钟
- **技能**：`godot-prompter:gdscript-advanced`

### Task 3.2: Pending 状态统一封装

- **问题**：`GameState` 中用 5 个独立字段管理不同类型的 pending 状态：
  - `pending_decisions`
  - `pending_life_triggers`
  - `pending_life_reveal`
  - `pending_life_damage_cards`
  - `pending_life_reveal_waiting_for_player`
- **方案**：创建 `PendingState` 内部类或独立 RefCounted，封装以上所有字段 + 常用查询方法（`is_empty()`, `has_any()`, `clear()`）
- **影响文件**：
  - `data/game_state.gd` — 引入 PendingState
  - `core/game_gate_checker.gd` — 改用 PendingState 查询
  - `core/game_manager.gd` — 同上
  - `core/life_trigger_manager.gd` — 同上
- **验证**：全部冒烟测试
- **工作量**：3-4 小时
- **技能**：`godot-prompter:component-system`

### Task 3.3: preload 策略统一

- **问题**：部分文件在 `_init()` 中赋值 `const X = preload(...)`（但写成 `const` 实际上在文件顶层），部分在函数内 `load()`。应确保所有编译期已知的 class 引用使用 `const X = preload(...)`
- **方案**：审查所有文件顶部的 `const` / `var` 声明，将 `const X = preload(...)` 模式统一
- **影响文件**：全部 `core/` 和 `data/` 文件
- **验证**：编译通过
- **工作量**：1 小时
- **技能**：`godot-prompter:gdscript-advanced`

---

## 执行顺序与依赖图

```
Phase 0 (先修 Bug)
├── 0.1 _parse_zone 统一          [无依赖]
├── 0.2 delayed_effects 修复      [无依赖]
└── 0.3 死代码删除                [无依赖]
     ↓
Phase 1 (消除重复)
├── 1.1 EffectUtils 创建           [依赖 0.1]
├── 1.2 keyword → CardInstance     [无依赖，可与 1.1 并行]
├── 1.3 解除反向依赖               [依赖 1.1, 1.2]
└── 1.4 operation 字典分发         [依赖 1.1, 1.3]
     ↓
Phase 2 (瘦身拆分)
├── 2.1 GameManager 瘦身           [依赖 1.3]
├── 2.2 LifeTriggerManager 解耦    [依赖 1.3, 2.1]
├── 2.3 BattleScene 拆分           [无依赖，可与 2.1/2.2 并行]
└── 2.4 全量类型标注               [依赖 2.1, 2.2, 2.3 — 在重构后执行]
     ↓
Phase 3 (技术债务)
├── 3.1 emit_signal → .emit()      [无依赖]
├── 3.2 PendingState 封装          [依赖 2.1]
└── 3.3 preload 统一              [无依赖]
```

---

## 风险与回滚策略

| 风险 | 概率 | 影响 | 缓解措施 |
|---|---|---|---|
| 重构引入回归 bug | 中 | 高 | 每个 Task 后运行全部冒烟测试；Phase 间可独立回滚 |
| Task 2.1 action 字符串不兼容 | **高** | 高 | Step A 前必须运行兼容性对比测试脚本 |
| 类型标注导致编译错误 | 低 | 中 | 逐文件标注，每次标注后编译确认 |
| BattleScene 拆分破坏 UI 布局 | 中 | 高 | 拆分前截图对比；保留原文件备份 |
| 解除反向依赖时破坏效果执行顺序 | 低 | 高 | 运行 duel smoke test（69 个用例覆盖完整对局） |

### Git 策略

```
Phase 开始前: git checkout -b refactor/phase-N
Phase 完成后: git commit -m "refactor: Phase N — <描述>"
验证通过后:  git checkout ds && git merge refactor/phase-N
```

每个 Phase 在自己的分支上工作，验证通过后合入 ds。如果某个 Phase 有问题，可以独立 revert 而不影响其他 Phase。

---

## 成功标准

| 指标 | 当前 | Phase 0 | Phase 1 | Phase 2 | Phase 3 |
|---|---|---|---|---|---|
| `_parse_zone` 实现数 | 4 份 | **1 份** | 1 份 | 1 份 | 1 份 |
| 重复工具函数 | ~9 个 | 9 个 | **0 个** | 0 个 | 0 个 |
| 反向依赖数 | 6 处 | 6 处 | **2 处** | **0 处** | 0 处 |
| GameManager 行数 | 982 | 981 | 981 | **~750** | ~750 |
| BattleScene 行数 | 1376 | 1376 | 1376 | **~900** | ~900 |
| 核心文件类型覆盖率 | ~60% | ~60% | ~60% | **~95%** | ~95% |
| 冒烟测试通过率 | 114/114 | 114/114 | 114/114 | 114/114 | 114/114 |
| emit_signal 字符串形式 | 18 处 | 18 处 | 18 处 | 18 处 | **0** |

---

## 时间估算汇总

| Phase | 总工时 | 建议时间窗 |
|---|---|---|
| Phase 0 — Bug 修复 | 1.5h | 1 天内完成 |
| Phase 1 — 消除重复与解耦 | 7-9h | 2-3 天内完成 |
| Phase 2 — 瘦身拆分 | 13-18h | 3-5 天内完成 |
| Phase 3 — 技术债务 | 5-6h | 1-2 天内完成 |
| **总计** | **26.5-34.5h** | **1.5-2 周** |

---

## 修订记录

| 日期 | 修订内容 |
|---|---|
| 2026-06-05 | 初版创建，基于架构评估报告 |
| 2026-06-06 | 经代码库逐项核验后修订：移除不存在的 Task 0.2；修正 Task 0.3 删除范围（当时改为仅删 L225）；修正 Task 0.4 bug 描述方向；重审 Task 1.1 函数重复清单（缩减为 9 个）；Task 2.1 增加兼容性验证前置步骤；Task 2.4 增加执行顺序约束；更新行数统计和 emit_signal 计数 |
| 2026-06-07 | 审查修正：Task 0.3 方案重新核验——L226 条件与 L209 完全相同（`not play_options.has(...)`），并非"已有 zone_choice 的回退逻辑"，实为复制粘贴残留死代码。修正方案为删除 L226-228（3 行），保留 L225 return；Task 1.1 补充 `ensure_array` 与 `parse_card_state` 的语义分歧警告 |
