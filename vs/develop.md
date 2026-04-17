# 基础人机对战框架开发计划

## 1. 计划目标

本文档用于指导当前 Godot 卡牌项目的人机对战基础框架开发，范围以“规则驱动、合法动作优先”的 AI 路线为主，并严格遵循 `docs/rules/rule.md` 与仓库 `AGENTS.md` 的协作边界。

本计划只覆盖“基础人机框架 + SimpleAI + 验证脚本”，不包含搜索式 AI、联网同步、复杂演出或完整数值平衡。

## 2. 总体开发策略

### 2.1 开发主线

按以下顺序推进：

1. 冻结接口与状态契约
2. 落地统一 Action 模型
3. 落地 PlayerController 抽象
4. 在 `RulesEngine` 中提供合法动作生成
5. 在 `GameManager` 中接入统一动作调度
6. 接入 `SimpleAI`
7. 补齐 UI 适配与自动化验证

### 2.2 关键原则

- 不允许 AI 直接修改 `GameState`
- 不允许 UI 继续独占“可执行动作”语义
- 不允许在未冻结接口前同时大改 `core + ui`
- 不允许为了 AI 简化 `rule.md` 中的高风险规则

## 3. 里程碑划分

建议分 5 个里程碑推进。

## 4. 里程碑 M1：接口冻结与现状梳理

### 4.1 目标

在不引入行为变化的前提下，冻结人机框架所需的核心契约，避免后续多点改动互相打架。

### 4.2 主要产出

- 人机框架设计文档定稿
- Action 数据结构定义
- 控制器接口定义
- `get_legal_actions()` 的输出格式定义
- `GameManager.execute_action()` 的输入输出格式定义

### 4.3 接口冻结项

#### GameState

确认复用或补充以下字段：

- `battle_context`
- `effect_queue`
- `pending_decisions`
- `pending_life_triggers`

如需新增字段，优先新增而不是重写现有字段语义。

#### Action 结构

建议冻结如下最小结构：

```gdscript
{
  "id": "action_xxx",
  "type": "PLAY_CARD",
  "player_id": "P1",
  "params": {}
}
```

#### 合法动作输出

建议至少包含：

- `id`
- `type`
- `player_id`
- `label`
- `params`
- `source_card_uid`
- `priority_hint`

其中 `priority_hint` 只作为 UI 或调试参考，不能替代 AI 的真实决策逻辑。

### 4.4 涉及模块

- `core/game_manager.gd`
- `core/rules_engine.gd`
- `core/battle_resolver.gd`
- `core/effect_resolver.gd`
- 新增 `core/controllers/`
- 新增 `core/actions/`

### 4.5 验证要求

- 文档评审通过
- 不改规则语义
- 现有对局流程不回归

## 5. 里程碑 M2：Action 模型与控制器骨架

### 5.1 目标

建立统一动作通道和玩家控制器抽象，让“人”和“AI”都能通过相同流程驱动对局。

### 5.2 具体任务

#### Action 层

- 新增动作类型常量或工厂
- 定义 `PLAY_CARD / MOVE_CARD / ATTACK / BLOCK / ACTIVATE_EFFECT / RESOLVE_PENDING_DECISION / RESOLVE_LIFE_TRIGGER / ADVANCE_PHASE / END_TURN`
- 为日志、测试和调试保留动作可读描述

#### 控制器层

- 新增 `PlayerController`
- 新增 `HumanController`
- 新增 `AIController`
- 明确“主动回合动作”和“响应式动作”的统一接口

#### GameManager 对接

- 新增控制器注册表
- 新增 `execute_action(action)`
- 状态变化后根据当前行动方与 gate 状态请求控制器动作

### 5.3 实现边界

- 这一阶段先不追求 UI 完全切到动作模式
- 可以先保留原入口，再由 `execute_action` 适配调用现有方法
- 不在此阶段实现 AI 策略，只做骨架

### 5.4 风险点

- `GameManager` 可能形成“动作执行 + 控制器调度 + 状态广播”三重职责，需要注意分层
- pending decision 与 battle response 都可能导致“当前行动方”不是 `active_player_id`

### 5.5 验证要求

- Human vs Human 仍可正常跑通
- `execute_action` 可以覆盖现有主要操作
- 动作日志可读

## 6. 里程碑 M3：RulesEngine 合法动作生成

### 6.1 目标

把规则合法性从“单点校验函数”提升为“统一合法动作列表”，让 AI 和 UI 都基于同一规则出口工作。

### 6.2 具体任务

#### RulesEngine

- 新增 `get_legal_actions(state, player_id)`
- 在不同阶段枚举所有合法动作
- 为 pending decision / life trigger / block response 提供合法动作

#### Battle / Effect 联动

- 提供当前 battle context 下的阻挡动作生成
- 提供生命触发的“发动/不发动”动作生成
- 提供 STEP 与 RAID 选择动作生成

### 6.3 规则覆盖清单

必须覆盖：

- `MOVE` 阶段：能量线前移、STEP 回退、STEP 交换、阶段推进
- `MAIN` 阶段：角色出牌、场地出牌、事件使用、MAIN_ACTIVATE、RAID 相关动作、阶段推进
- `ATTACK` 阶段：攻击玩家、SNIPER 攻击角色、阶段推进
- 响应阶段：`BLOCK`、`NO_BLOCK`
- 待选阶段：`RESOLVE_PENDING_DECISION`、`RESOLVE_LIFE_TRIGGER`
- `END` 阶段：结束回合

### 6.4 风险点

- 若合法动作生成与 `can_*` 校验逻辑不一致，会导致 UI 与 AI 表现分叉
- 若 pending gate 期间仍暴露普通阶段动作，会破坏规则优先级

### 6.5 验证要求

- 随机抽取多个局面，合法动作列表与现有 `can_*` 结果一致
- 非法阶段不应暴露非法动作
- 高风险规则区必须有覆盖用例

## 7. 里程碑 M4：SimpleAI 落地

### 7.1 目标

落地首个“只会合法行动”的基础 AI，让项目具备最小人机对战能力。

### 7.2 具体任务

#### AIController

- 接入 `get_legal_actions`
- 请求 `SimpleAI` 给出动作
- 支持同步执行与后续延迟执行扩展

#### SimpleAI

- MAIN 阶段优先打出可出的最高 BP 角色
- ATTACK 阶段优先直接攻击玩家
- 能阻挡时选择 BP 最高的可阻挡角色
- 没有更优动作时结束阶段或结束回合
- 生命触发默认“可发动就发动”
- RAID / STEP 等待选项按最简单可解释规则选择

### 7.3 非目标

- 不做局面搜索
- 不做复杂换子判断
- 不做深度资源规划
- 不做难度分级平衡

### 7.4 风险点

- AI 若连续自动推进，可能和 UI 动画或日志刷新时序冲突
- AI 若只看单动作优先级，可能出现“合法但愚蠢”的选择，这是预期内行为

### 7.5 验证要求

- Human vs AI 可完整开局并打完至少数个回合
- AI vs AI 可在 headless 环境跑通
- AI 不出现直接改状态、死循环或卡死在 pending gate 的问题

## 8. 里程碑 M5：UI 适配与自动化验证

### 8.1 目标

让 UI 正确消费动作框架，并通过自动化脚本验证基础人机流程稳定。

### 8.2 具体任务

#### UI 适配

- 把当前主要交互逐步切到“展示合法动作并提交动作”
- 在人类行动时只展示合法项
- 在 AI 行动时正确禁用人类输入
- 展示当前控制器类型、AI 行动日志和关键响应点

#### 测试脚本

- 新增基础人机冒烟脚本
- 新增 AI vs AI 回合推进脚本
- 新增若干规则点验证脚本

推荐覆盖：

- 先攻首回合不抽牌
- 前线/能量线容量上限
- 场地牌不能进前线
- ACTIVE 前线角色才能攻击或阻挡
- 生命区触发可选发动
- 攻击失败攻击者不离场
- AI 会在无更优动作时结束阶段

### 8.3 验证方式

- Headless 冒烟
- 最小对局脚本
- UI 手动验证

## 9. 推荐多 agent 拆分

遵循 `AGENTS.md`，推荐在接口冻结后按以下边界并行：

### 9.1 第一轮并行

- Agent A：`core/actions/` 与 `core/controllers/` 骨架
- Agent B：`docs/` 文档与测试计划
- Agent C：`docs/` 或冒烟脚本，不改核心规则文件

说明：

- 这一轮不建议并行改 `core/game_manager.gd` 与 `ui/`

### 9.2 第二轮并行

- Agent A：`core/rules_engine.gd` 的 `get_legal_actions`
- Agent B：AI 测试脚本与最小对局用例
- Agent C：UI 消费动作展示层，前提是 Action 输出格式已冻结

说明：

- 同一轮不要让两个 agent 同时改 `core/rules_engine.gd`

### 9.3 第三轮并行

- Agent A：`core/game_manager.gd` 动作调度与控制器驱动
- Agent B：`core/ai/simple_ai.gd` 与 `core/controllers/ai_controller.gd`
- Agent C：`ui/` 人类交互适配

说明：

- 若 `GameManager` 的接口仍未冻结，这一轮应串行处理

## 10. 文件级实施建议

### 10.1 新增文件建议

```text
core/actions/action_types.gd
core/actions/action_factory.gd
core/controllers/player_controller.gd
core/controllers/human_controller.gd
core/controllers/ai_controller.gd
core/ai/simple_ai.gd
vs/design.md
vs/develop.md
test/vs_ai_smoke_test.gd
```

### 10.2 高风险改动文件

- `core/game_manager.gd`
- `core/rules_engine.gd`
- `core/battle_resolver.gd`
- `core/effect_resolver.gd`
- `ui/battle_scene.gd`
- `ui/board_view.gd`

这些文件应尽量分轮次处理，避免同轮并改。

## 11. 测试计划

### 11.1 必测场景

#### 开局

- 双方 50 主卡组
- 起手 7
- 生命 7
- 先攻首回合不抽

#### 合法动作

- 不同阶段返回不同动作集合
- pending gate 出现时只返回响应动作
- 非行动方不返回主动动作

#### 人机流程

- P1 Human / P2 AI 正常推进
- AI 回合自动完成 move/main/attack/end
- AI 在阻挡窗口正常响应
- AI 在生命触发窗口正常响应

#### 规则高风险区

- 区域容量上限
- 场地落点限制
- ACTIVE 限制
- AP 与能量支付
- 攻击失败攻击者不离场

### 11.2 自动化优先级

优先级从高到低：

1. Headless AI vs AI 冒烟
2. 合法动作列表断言测试
3. 关键规则样例测试
4. UI 手动回归

## 12. 实施顺序建议

建议实际编码顺序如下：

1. 新增 Action 常量与结构
2. 新增控制器抽象层
3. 给 `GameManager` 增加 `execute_action`
4. 给 `RulesEngine` 增加 `get_legal_actions`
5. 让 HumanController 先接入动作模式
6. 接入 `AIController + SimpleAI`
7. 补充 UI 展示与测试脚本

这个顺序的优势是：

- 每一步都可运行验证
- 旧 UI 入口可以逐步迁移
- AI 接入时已有完整规则出口，不会逼着 AI 反向读 UI

## 13. 阶段验收标准

### M1 验收

- 设计文档和开发计划完成
- 接口冻结清单明确

### M2 验收

- Action 模型可落库/可日志化
- 控制器接口可用
- 旧功能不回归

### M3 验收

- `get_legal_actions` 可覆盖主要动作类型
- UI 与 AI 可共享合法动作源

### M4 验收

- SimpleAI 可稳定进行基础对战
- 不绕过规则层改状态

### M5 验收

- Human vs AI 主流程可玩
- AI vs AI 可冒烟
- 有基础自动化验证

## 14. 后续扩展路线

基础框架完成后，建议按以下路线升级：

1. 新增 `ActionScorer`
2. 新增 `BoardEvaluator`
3. 引入 `AIStrategyProfile`
4. 实现单步模拟
5. 再考虑 2~3 层搜索与难度分级

与当前项目“先规则闭环、再策略增强”的方向一致

## 15. 结论

当前项目最合适的人机开发路径，不是直接把 AI 写进现有 UI 或回合逻辑，而是先把控制器层、动作层和规则层边界立住。只要 `PlayerController`、统一 Action、`RulesEngine.get_legal_actions()` 和 `GameManager.execute_action()` 这四块搭好，SimpleAI 就能低风险接入，而后续评分式 AI、搜索式 AI、AI vs AI 自动测试也都能自然叠加。
