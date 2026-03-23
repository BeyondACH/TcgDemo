# 基础人机对战框架设计文档

## 1. 文档目标

本文档结合`docs/rules/rule.md`、当前仓库实现现状，定义本项目基础人机对战框架的设计方案。目标不是直接实现“高智能 AI”，而是先建立一套严格遵守规则、可持续扩展、可被测试和模拟的人机对战基础框架。

本阶段的核心目标只有三个：

1. 让对局中的每一方都通过统一控制器接口行动。
2. 让 AI 只能从规则层提供的合法动作中选择动作，不能直接修改 `GameState`。
3. 让现有 PvP 原型在尽量少改动核心规则语义的前提下扩展为 PvE 基础框架。

## 2. 设计原则

### 2.1 规则权威

- `docs/rules/rule.md` 是最高权威。
- AI 不能绕过 `RulesEngine`、`BattleResolver`、`EffectResolver`、`TurnManager` 直接改状态。
- 生命区触发、攻击/阻挡、区域容量、AP 与能量支付、回合推进都必须继续由核心规则模块控制。

### 2.2 先做“会合法行动”的 AI

1. 合法行动 AI
2. 评分式 AI
3. 搜索式 AI

当前项目应只落地第 1 阶段，并为第 2、3 阶段保留接口。换句话说，当前版本的 AI 重点不是“聪明”，而是：

- 能完整走完回合
- 不执行非法动作
- 能在 MAIN / ATTACK / BLOCK / END 等关键节点作出基础决策
- 能与现有 UI、日志、快照和 pending decision 流程兼容

### 2.3 控制器与规则解耦

当前项目主要由 `GameManager` 驱动 UI 操作。扩展人机对战后，应把“谁做决策”从“如何执行规则”中拆开：

- 控制器负责选择动作
- `GameManager` 负责调度动作
- 规则模块负责验证与执行动作

这样可以避免把 AI 逻辑写进 `TurnManager`、`BattleScene` 或 UI 脚本中。

## 3. 当前项目现状

结合现有代码，项目已经具备以下人机框架基础能力：

- `GameManager` 已统一管理对局状态、阶段推进、出牌、攻击、主效果、STEP、生命触发与 pending decision。
- `RulesEngine` 已有 `can_play_card`、`can_move_energy_to_front`、`can_step_move_to_energy`、`can_attack`、`can_block`。
- `BattleResolver` 已有攻击声明、阻挡选择、直接攻击、狙击攻击、DOUBLE_ATTACK / DOUBLE_BLOCK、IMPACT 等主流程。
- `GameState` 已有 `battle_context`、`effect_queue`、`pending_decisions`、`pending_life_triggers`。
- `GameManager.get_snapshot()` 已能向 UI 暴露可消费快照。

当前缺少的是：

- 玩家控制器抽象层
- 统一 Action 模型
- 面向 AI 的 `get_legal_actions(player_id)` 能力
- AI 回合自动驱动机制
- 基础行为策略与测试脚本

因此本次设计以“增量接入”为原则，不推倒现有核心模块。

## 4. 总体架构

推荐增加如下模块层次：

```text
GameManager
  -> ControllerCoordinator
    -> PlayerController
      -> HumanController
      -> AIController
        -> SimpleAI
  -> ActionDispatcher
  -> RulesEngine / BattleResolver / EffectResolver / TurnManager
```

在当前仓库体量下，可以不强制单独引入 `ControllerCoordinator` 与 `ActionDispatcher` 类，但职责必须明确存在。

### 4.1 核心职责划分

#### GameManager

负责：

- 持有双方控制器配置
- 在阶段推进后判断当前行动方是否为 AI
- 请求当前控制器给出动作
- 调用统一动作执行入口
- 处理 pending decision、状态变更、日志和快照广播

不负责：

- 自己给 AI 打分
- 自己推导合法动作细节
- 自己决定规则是否合法

#### PlayerController

抽象玩家控制器，屏蔽“人类操作”和“AI 选择”的差异。

建议接口：

```gdscript
extends RefCounted
class_name PlayerController

func request_action(game_state: GameState, snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
    return {}

func request_pending_decision(game_state: GameState, snapshot: Dictionary, pending: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
    return {}
```

说明：

- HumanController 不直接返回动作，而是把可行动信息交给 UI，等待 UI 选择。
- AIController 同步或异步返回一个动作。
- 后续如需“思考延迟”或动画窗口，可在 `GameManager` 层做调度，不改变接口语义。

#### HumanController

负责：

- 把合法动作映射为 UI 可点选状态
- 把用户点击转为 Action
- 处理生命触发选择、STEP 交换、RAID 落点等 pending decision

不负责：

- 绕过规则直接执行
- 自己维护回合合法性

#### AIController / SimpleAI

负责：

- 调用规则层提供的合法动作列表
- 按固定优先级从中选择一项
- 在没有更优动作时结束阶段或结束回合

不负责：

- 直接修改 `GameState`
- 在 UI 层编码规则
- 伪造规则不存在的动作

## 5. Action 模型设计

要求统一 Action 模型。建议新增 `data/action` 或 `core/actions` 目录，并以字典模型先落地，避免首版引入过多 class。

推荐基础结构：

```gdscript
{
  "type": "PLAY_CARD",
  "player_id": "P2",
  "card_uid": "P2_012",
  "params": {
    "target_zone": 3,
    "raid_target_uid": "",
    "raid_target_zone_choice": -1
  }
}
```

### 5.1 MVP 动作类型

首版至少支持：

- `PLAY_CARD`
- `MOVE_CARD`
- `ATTACK`
- `BLOCK`
- `ACTIVATE_EFFECT`
- `RESOLVE_PENDING_DECISION`
- `RESOLVE_LIFE_TRIGGER`
- `ADVANCE_PHASE`
- `END_TURN`

说明：

- `EndPhaseAction` 与 `EndTurnAction` 在当前项目可分别映射到 `advance_phase()` 和从 `END` 推进到下一回合。
- `BlockAction` 本质上是“对当前 battle context 的阻挡响应”。
- `RESOLVE_PENDING_DECISION` 用于 STEP、RAID 等框架内决策。
- `RESOLVE_LIFE_TRIGGER` 用于生命触发“是否发动”的显式选择。

### 5.2 动作设计要求

- 动作必须可序列化，便于日志、回放、测试和后续模拟。
- 动作必须显式携带 `player_id`，避免跨玩家误执行。
- 动作参数只描述“意图”，不直接描述“结果”。
- 动作必须能映射回现有 `GameManager` 公开接口。

## 6. 合法动作生成设计

这是整个 AI 框架的核心。规则层需要提供统一入口：

```gdscript
func get_legal_actions(state: GameState, player_id: String) -> Array[Dictionary]
```

### 6.1 设计目标

- 给人类与 AI 提供同一套合法动作集合。
- 让 UI 与 AI 都消费同一规则结果。
- 为未来评分、模拟、回放打基础。

### 6.2 动作生成范围

#### 回合阶段动作
- `DRAW` 阶段:
  - 先攻玩家第一回合不抽牌
  - 后攻玩家第一回合抽牌
  - 后续每个玩家的抽牌阶段都抽一张牌
  - 每回合一次可以支付1AP抽一张牌

- `MOVE` 阶段：
  - 能量线角色移到前线
  - 带 `STEP` 的前线角色回能量线
  - 满位时的 `STEP` 交换动作
  - 结束阶段推进动作

- `MAIN` 阶段：
  - 从手牌打出角色到前线或能量线
  - 从手牌打出场地到能量线
  - 使用事件牌
  - 发动 `MAIN_ACTIVATE`
  - 需要时包含 RAID 相关动作
  - 无更优操作时结束阶段推进动作

- `ATTACK` 阶段：
  - 前线 ACTIVE 角色攻击玩家
  - `SNIPER` 指向前线角色攻击
  - 无可攻击动作时结束阶段推进动作

- `END` 阶段：
  - 结束回合动作

#### 响应动作

- battle context 存在且防守方可操作时：
  - `BLOCK`
  - `NO_BLOCK`

- pending decision 存在时：
  - 对应 `RESOLVE_PENDING_DECISION`

- pending life triggers 存在时：
  - 对应 `RESOLVE_LIFE_TRIGGER`

### 6.3 合法动作生成位置

推荐将 `get_legal_actions` 放在 `RulesEngine`，但它可以调用：

- `BattleResolver` 提供战斗相关补充候选
- `EffectResolver` 提供 `MAIN_ACTIVATE`、生命触发、待选目标等补充信息
- `GameManager` 提供当前门控状态信息，但不直接生成规则动作

原因是：`RulesEngine` 最适合作为“合法性统一出口”，便于 AI 与 UI 共享。

## 7. 动作执行设计

为避免 AI 与人类走两套入口，建议在 `GameManager` 新增统一执行函数：

```gdscript
func execute_action(action: Dictionary) -> Dictionary
```

其内部按 `type` 分发到现有入口：

- `PLAY_CARD` -> `play_card(...)`
- `MOVE_CARD` -> `move_energy_to_front(...)` 或 `request_step_move(...)`
- `ATTACK` -> `request_attack(...)` / `resolve_attack(...)`
- `BLOCK` -> `resolve_attack(attacker_uid, blocker_uid)`
- `NO_BLOCK` -> `resolve_attack(attacker_uid, "")`
- `ACTIVATE_EFFECT` -> `request_main_activate(...)`
- `RESOLVE_PENDING_DECISION` -> `resolve_pending_decision(...)`
- `RESOLVE_LIFE_TRIGGER` -> `resolve_life_trigger_decision(...)`
- `ADVANCE_PHASE` -> `advance_phase()`
- `END_TURN` -> `advance_phase()`，仅在 `END` 阶段可用

### 7.1 执行约束

- 所有动作执行前再次做合法性确认，避免 UI 或 AI 用过期动作执行。
- 动作执行结果应包含日志、是否成功、是否触发新的 pending gate。
- 如果执行后产生 `pending_decisions` 或 `pending_life_triggers`，行动权转为对应控制器处理响应。

## 8. 人机流程设计

### 8.1 对局配置

建议在开局配置层面支持：

```gdscript
{
  "P1": {"controller": "HUMAN"},
  "P2": {"controller": "AI_SIMPLE"}
}
```

首版只需要支持：

- 人类 vs AI
- 人类 vs 人类兼容保留
- AI vs AI 仅用于测试，不作为 UI 主流程目标

### 8.2 回合驱动

推荐流程：

1. `GameManager` 状态变化后检查：
   - 是否已分出胜负
   - 是否有 pending decision
   - 是否有 pending life trigger
   - 当前优先行动方是谁
2. 计算该玩家 `get_legal_actions(...)`
3. 查找该玩家控制器
4. 若为 HumanController，则高亮 UI 并等待输入
5. 若为 AIController，则请求 AI 选择动作
6. 执行动作
7. 回到第 1 步，直到进入需要另一个玩家响应的节点或对局结束

### 8.3 AI 响应窗口

AI 不仅在自己回合行动，也必须处理：

- 是否阻挡
- 生命触发是否发动
- RAID / STEP 等待选项

因此控制器抽象必须覆盖“主动行动”和“被动响应”两类节点。

## 9. SimpleAI 设计

首版 SimpleAI 必须严格符合：规则驱动 + 优先级表。

### 9.1 决策输入

- 当前 `GameState`
- 当前 `snapshot`
- 当前 `legal_actions`

### 9.2 决策原则

#### MAIN 阶段

优先级建议：

1. 能合法打出的最高 BP 角色优先
2. 其次考虑能补场的低费角色
3. 其次考虑事件牌或主效果
4. 没有正收益动作时推进阶段

约束：

- 必须遵守前线最多 4、能量线最多 4、场地只能进能量线
- 必须通过 AP 与能量校验

#### ATTACK 阶段

优先级建议：

1. 能直接攻击玩家则优先攻击玩家
2. 有 `SNIPER` 时优先攻击可击败的敌方前线角色
3. 没有正收益攻击时结束攻击阶段

#### BLOCK 响应

优先级建议：

1. 能阻挡时选择 BP 最高的可阻挡角色
2. 如果后续引入更细策略，再区分“保命阻挡”和“换子阻挡”
3. 当前基础版不做复杂留场计算

#### 待选决策

- 生命触发：首版建议“能发动就发动”，但需要注明这是占位策略
- RAID 在目标位于能量线时：
  - 若前线未满，优先转前线
  - 若前线已满，则留能量线
- STEP 满位交换时：
  - 选择 BP 较低或当前价值较低的能量角色作为交换对象

### 9.3 输出约束

- AI 只能返回 `legal_actions` 中存在的对象或其唯一 ID
- 若 `legal_actions` 为空，必须返回空并由上层容错
- 若策略计算异常，降级为：
  - 有 `ADVANCE_PHASE` 就结束阶段
  - 有 `END_TURN` 就结束回合

## 10. 模块拆分建议

建议新增目录：

```text
core/controllers/
  player_controller.gd
  human_controller.gd
  ai_controller.gd

core/actions/
  action_types.gd
  action_factory.gd

core/ai/
  simple_ai.gd
  action_scorer.gd        # 预留
  board_evaluator.gd      # 预留
  ai_strategy_profile.gd  # 预留
  simulation_runner.gd    # 预留
```

### 10.1 首版必须新增

- `player_controller.gd`
- `human_controller.gd`
- `ai_controller.gd`
- `simple_ai.gd`
- Action 常量或工厂文件

### 10.2 首版可以只预留不实现

- `action_scorer.gd`
- `board_evaluator.gd`
- `ai_strategy_profile.gd`
- `simulation_runner.gd`

## 11. 与现有模块的改造边界

### 11.1 GameManager

需要新增：

- 玩家控制器注册
- `execute_action(action)`
- 在状态变化后自动驱动当前控制器
- 提供 AI 所需的可读状态快照或上下文

尽量不改：

- 现有对局初始化主流程
- 现有规则模块调用顺序

### 11.2 RulesEngine

需要新增：

- `get_legal_actions(state, player_id)`
- 补充 pending gate 场景下的合法动作生成

尽量不改：

- 已稳定的 `can_*` 校验语义

### 11.3 BattleResolver / EffectResolver

需要配合提供：

- 当前战斗上下文可序列化信息
- 当前待选项信息可供动作生成消费

尽量不改：

- 规则主语义

### 11.4 UI

需要调整：

- 从“直接调 GameManager 某个具体接口”逐步转向“消费合法动作并提交选择”
- 为 HumanController 留出动作选择与响应入口

不应承担：

- AI 逻辑
- 规则合法性判断

## 12. 后续扩展设计

首版设计必须为以下能力留出扩展点：

### 12.1 ActionScorer

在合法动作基础上为每个动作评分，替代纯固定优先级。

### 12.2 BoardEvaluator

对局面做静态打分，为“一步模拟”或“多步搜索”做准备。

### 12.3 StrategyProfile

把 AI 风格做成参数，而不是复制多份 AI 脚本。例如：

- Aggro
- Control
- Beginner
- Random

### 12.4 Simulation 能力

未来若做搜索式 AI，必须支持：

- 复制 `GameState`
- 在副本上执行动作
- 评估结果并丢弃副本

因此当前新增的 Action 模型与执行入口必须尽量纯逻辑、少依赖 UI。

## 13. 风险与约束

### 13.1 高风险规则区

以下区域在接入 AI 时不能被“为了方便自动化”而简化错误：

- 生命区触发是可选发动，不是强制自动发动
- 阻挡只能由 ACTIVE 前线角色进行
- 攻击失败的攻击者不会离场
- 场地牌不能进入前线
- 前线最多 4、能量线最多 4、AP 最多 3
- 先攻首回合不抽牌

### 13.2 当前代码耦合风险

当前 `GameManager` 已直接承担较多操作编排职责。引入控制器后要避免：

- 再把 AI 分支逻辑塞进 `advance_phase()` 或 UI 脚本
- 让 `get_snapshot()` 变成规则判断入口
- 让 AI 直接消费内部可变对象并写回状态

### 13.3 异步与动画风险

如果后续 UI 加入行动延迟或演出，AI 选择与动作执行必须可拆分为：

- 选择动作
- 等待表现
- 提交执行

当前首版可以先同步执行，但文档上应保留该边界。

## 14. MVP 验收标准

基础人机框架完成后，应至少满足：

1. 可配置 `P1=Human`、`P2=AI` 开局。
2. AI 能在自己的 `MOVE / MAIN / ATTACK / END` 流程持续行动直到无动作。
3. AI 在被攻击时能从合法阻挡动作中选择一项，或选择不阻挡。
4. AI 遇到生命触发、STEP、RAID 等待选项时能给出合法响应。
5. AI 全程不直接改 `GameState`，所有状态变化都通过规则执行入口产生。
6. 合法动作列表能同时服务 UI 与 AI。
7. 至少有一组 headless 或最小对局脚本能跑通 Human vs AI / AI vs AI 基础流程。

## 15. 结论

本项目的人机框架首要任务不是“做强 AI”，而是把“玩家决策”和“规则执行”彻底分层。以 `PlayerController + 统一 Action + RulesEngine.get_legal_actions + SimpleAI` 为核心，可以在不破坏当前 Godot 原型主流程的基础上，稳定扩展出基础人机对战能力，并为后续评分式 AI、搜索式 AI、对局回放和自动化测试打下统一基础。
