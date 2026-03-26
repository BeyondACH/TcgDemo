# 简单人机开发计划

## Summary

基于 `vs/design.md`、`vs/develop.md` 与当前仓库现状，简单人机开发按“先统一动作出口，再接控制器，再接 SimpleAI，最后补 UI 与自动化验证”的顺序推进。

当前仓库已经具备 `GameManager` 主流程、`RulesEngine.can_*` 校验、`pending_decisions` / `pending_life_triggers` 与快照中的 `available_actions` 基础，因此本次实现采用增量收敛到统一动作框架的路线，不重写既有规则核心。

## Key Changes

### M1：冻结动作契约与控制器边界
- 统一 Action 结构，至少包含 `id`、`type`、`player_id`、`params`、`label`、`source_card_uid`。
- 冻结控制器接口，统一覆盖主动行动与响应决策。
- `GameManager` 负责调度与执行，规则合法性继续由 `RulesEngine`、`BattleResolver`、`EffectResolver` 判定。
- 保留现有 `pending_decisions`、`pending_life_triggers`、`battle_context`、`effect_queue` 语义。

### M2：收敛到统一动作执行层
- 在 `core/actions/` 新增动作类型常量与动作构造工具。
- 在 `core/controllers/` 新增 `PlayerController`、`HumanController`、`AIController`。
- 在 `GameManager` 中新增 `execute_action(action)`，把现有分散入口收敛到统一动作分发。
- 首轮保留旧 UI 入口，通过兼容层继续调用。

### M3：从 `available_actions` 升级到统一 `get_legal_actions`
- 在 `RulesEngine` 中新增 `get_legal_actions(state, player_id)`，统一返回完整动作对象。
- 复用现有 `can_play_card`、`can_move_energy_to_front`、`can_step_move_to_energy`、`can_attack`、`can_block`，避免重复实现规则。
- 覆盖 `DRAW / MOVE / MAIN / ATTACK / END` 主阶段动作，以及 `BLOCK`、`NO_BLOCK`、`RESOLVE_PENDING_DECISION`、`RESOLVE_LIFE_TRIGGER`。
- 快照中的 `available_actions` 改为统一合法动作的投影视图。

### M4：接入 SimpleAI
- 在 `core/ai/simple_ai.gd` 实现只从合法动作中选的基础 AI。
- `MAIN` 阶段优先高 BP 角色，其次补场，再次事件或 `MAIN_ACTIVATE`。
- `ATTACK` 阶段优先直接攻击玩家，其次 `SNIPER` 指向前线角色。
- `BLOCK` 阶段优先 BP 最高可阻挡者。
- 生命触发、`STEP`、`RAID`、手牌超限弃牌采用固定占位策略。

### M5：对局驱动、UI 适配与模式配置
- 开局配置支持 `{ "P1": {"controller": "HUMAN"}, "P2": {"controller": "AI_SIMPLE"} }`。
- `GameManager` 在状态变化后根据当前优先行动方自动驱动控制器。
- UI 保持现有交互，但在 AI 行动时锁定人工输入，并显示当前行动方控制器类型。
- 本阶段不引入 `vs/llm.md` 中的 LLM 控制器。

### M6：测试与交付补齐
- 新增 `Human vs AI` 与 `AI vs AI` 冒烟脚本。
- 新增 `get_legal_actions` 冒烟断言。
- 同轮实现完成后，按仓库要求向 `docs/logs.md` 追加一条中文记录。

## Public APIs / Interfaces

- `RulesEngine.get_legal_actions(state: GameState, player_id: String) -> Array[Dictionary]`
- `GameManager.execute_action(action: Dictionary) -> Dictionary`
- `PlayerController.request_action(game_state: GameState, snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary`
- `PlayerController.request_pending_decision(game_state: GameState, snapshot: Dictionary, pending: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary`

## Test Plan

- 开局流程：起手 7、生命 7、先攻首回合不抽、双方一次 mulligan 后能进入对局。
- 合法动作：不同阶段只返回对应动作；`pending gate` 时只返回响应动作；非行动方不返回主动动作。
- 规则高风险区：前线上限 4、能量线上限 4、AP 上限 3、场地牌不能进前线、只有 ACTIVE 前线角色能攻击或阻挡、攻击失败攻击者不离场、生命触发为可选发动。
- 人机流程：`Human vs AI` 能推进至少一个 AI 回合；`AI vs AI` 可 headless 跑通；AI 不会死循环、不绕过规则层、不卡在 `pending_decisions` / `pending_life_triggers`。
- UI 验证：AI 行动期间人工输入被禁用；合法动作展示与实际可执行动作一致。

## Assumptions

- 本计划面向简单人机 MVP，不包含 LLM、搜索式 AI、联网同步与复杂演出。
- 当前快照中的 `available_actions` 作为统一 `get_legal_actions` 的派生视图继续保留。
- `GameManager`、`RulesEngine` 属于高风险核心文件，应串行主改；测试脚本与文档可并行补齐。
- 若实现阶段与规则语义冲突，以 `docs/rules/rule.md` 为准。
