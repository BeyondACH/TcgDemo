**LLM 机器方控制器方案 v1**

* Prompt 模板
* 返回 JSON Schema
* Godot 模块草图
* 一次完整调用流程
* 失败回退策略

这套方案的核心是：**规则引擎先给出合法动作列表，大模型只从里面选一个 `action_id`**。这样最稳，也最适合用 Responses API + Structured Outputs 实现。OpenAI 官方目前推荐新项目优先用 Responses API；Structured Outputs 可以强约束 JSON Schema；如果模型需要调用你定义的系统动作，也可以结合 function calling。

---

# 1. 目标

让大模型在你的人机对战里扮演 **AI 玩家控制器**，但不直接改游戏状态。

## 职责边界

大模型只负责：

* 阅读当前局面摘要
* 阅读当前合法动作列表
* 选择一个最优动作
* 返回 `action_id`

你的程序负责：

* 生成合法动作
* 校验合法性
* 执行动作
* 处理触发和结算
* 更新 GameState
* 判定胜负

---

# 2. 总体架构

```text
GameState
  ↓
RulesEngine.get_legal_actions(player_id)
  ↓
StateSummarizer / ActionFormatter
  ↓
LLMController
  ↓
JSON result { action_id, reason }
  ↓
RulesEngine.validate_action(action_id)
  ↓
ActionExecutor.execute(action_id)
  ↓
新状态 / 下一次决策
```

---

# 3. Godot 模块草图

建议目录：

```text
scripts/ai/
  ai_controller.gd
  llm_ai_controller.gd
  simple_ai_controller.gd
  state_summarizer.gd
  action_formatter.gd
  llm_prompt_builder.gd
  llm_response_parser.gd
  ai_fallback.gd
  ai_logger.gd
  openai_client.gd
```

## 各模块职责

### `ai_controller.gd`

统一控制器接口。

建议接口：

```gdscript
class_name AIController
extends RefCounted

func choose_action(game_state: GameState, player_id: String, legal_actions: Array) -> Dictionary:
    return {}
```

---

### `llm_ai_controller.gd`

负责：

* 调用 `state_summarizer`
* 调用 `action_formatter`
* 构造 prompt
* 请求 OpenAI
* 解析结构化 JSON
* 返回选中的动作

---

### `simple_ai_controller.gd`

本地兜底 AI。

作用：

* 模型超时
* 模型返回非法结果
* 网络异常
* 成本控制时

---

### `state_summarizer.gd`

把完整 GameState 压成适合模型决策的摘要，避免上下文过大。

---

### `action_formatter.gd`

把合法动作转成精简 JSON 列表。

---

### `llm_prompt_builder.gd`

拼接 system prompt + state summary + legal actions。

---

### `llm_response_parser.gd`

解析模型返回的结构化 JSON。

---

### `ai_fallback.gd`

处理异常时退回本地 AI。

---

### `ai_logger.gd`

记录：

* 当前局面摘要
* 动作候选
* 模型响应
* 最终执行动作
* 是否 fallback

---

### `openai_client.gd`

单独封装 OpenAI 请求逻辑，避免 AI 控制器和 HTTP 细节耦合。

---

# 4. 给大模型的 Prompt 模板

推荐拆成两段：`system` 和 `input_payload`。

## 4.1 System Prompt

```text
你是一个回合制卡牌游戏的机器方控制器，不是规则执行器。

你的唯一任务是：
从系统提供的“合法动作列表”中，选择当前最优的一个动作。

必须遵守：
1. 你只能选择提供的 action_id，不能发明新动作。
2. 你不能修改游戏状态，不能假设未给出的规则。
3. 若存在直接获胜的动作，优先选择获胜动作。
4. 若无法直接获胜，优先选择能提升胜率、保持合法、减少明显失误的动作。
5. 如果多个动作收益接近，优先选择更稳健、信息损失更小的动作。
6. 返回结果必须符合给定 JSON 结构。
7. 若你无法判断，也必须从合法动作中选择一个最稳妥的动作。

决策偏好：
- 优先直接造成胜利或压低对手生命
- 优先高价值出牌
- 避免无意义结束阶段
- 避免明显亏节奏的攻击
- 若资源紧张，优先保留关键行动点和手牌价值
```

---

## 4.2 Input Payload 模板

推荐把实际输入拼成一个 JSON 文本块发给模型：

```json
{
  "match_context": {
    "difficulty": "hard",
    "ai_style": "balanced"
  },
  "state_summary": {
    "turn": 5,
    "phase": "MAIN",
    "active_player": "ai",
    "self": {
      "life": 3,
      "hand_count": 4,
      "deck_count": 21,
      "ap": {
        "total": 3,
        "active": 2,
        "rested": 1
      },
      "front_line": [
        {
          "uid": "c1",
          "name": "基础攻击者A",
          "bp": 4000,
          "state": "ACTIVE",
          "keywords": []
        }
      ],
      "energy_line_count": 4
    },
    "opponent": {
      "life": 2,
      "hand_count": 3,
      "deck_count": 18,
      "ap": {
        "total": 3,
        "active": 1,
        "rested": 2
      },
      "front_line": [
        {
          "uid": "e1",
          "name": "阻挡者X",
          "bp": 3500,
          "state": "ACTIVE",
          "keywords": []
        }
      ],
      "energy_line_count": 4
    }
  },
  "legal_actions": [
    {
      "action_id": "a1",
      "type": "PLAY_CARD",
      "summary": "使用事件牌：抽1张牌"
    },
    {
      "action_id": "a2",
      "type": "ATTACK",
      "summary": "基础攻击者A攻击对方玩家"
    },
    {
      "action_id": "a3",
      "type": "ATTACK",
      "summary": "基础攻击者A攻击阻挡者X"
    },
    {
      "action_id": "a4",
      "type": "END_PHASE",
      "summary": "结束主要阶段"
    }
  ]
}
```

---

# 5. 返回 JSON Schema

OpenAI 官方的 Structured Outputs 可以确保响应遵循你定义的 JSON Schema。官方文档明确建议：当你需要固定 JSON 结构时，用 Structured Outputs；如果你是连接系统功能或工具，则用 function calling。([OpenAI 开发者][2])

## 推荐返回结构

```json
{
  "name": "ai_action_choice",
  "strict": true,
  "schema": {
    "type": "object",
    "properties": {
      "action_id": {
        "type": "string",
        "description": "必须是 legal_actions 中的某一个 action_id"
      },
      "reason": {
        "type": "string",
        "description": "简短说明选择原因，便于调试"
      },
      "confidence": {
        "type": "number",
        "description": "0 到 1 之间的置信度"
      }
    },
    "required": ["action_id", "reason", "confidence"],
    "additionalProperties": false
  }
}
```

---

# 6. Godot 侧数据结构建议

## 6.1 合法动作结构

```gdscript
class_name LegalAction
extends RefCounted

var action_id: String
var type: String
var summary: String
var payload: Dictionary = {}
```

---

## 6.2 状态摘要结构

```gdscript
class_name AIStateSummary
extends RefCounted

var turn: int
var phase: String
var active_player: String
var self_state: Dictionary
var opponent_state: Dictionary
```

---

## 6.3 模型返回结构

```gdscript
class_name AIChoiceResult
extends RefCounted

var action_id: String
var reason: String
var confidence: float
```

---

# 7. 一次完整调用流程

## Step 1：规则层生成合法动作

```gdscript
var legal_actions = rules_engine.get_legal_actions(ai_player_id)
```

---

## Step 2：压缩局面摘要

```gdscript
var summary = state_summarizer.build_summary(game_state, ai_player_id)
```

---

## Step 3：格式化动作列表

```gdscript
var action_data = action_formatter.format_actions(legal_actions)
```

---

## Step 4：构造请求

发给 OpenAI 的内容由两部分组成：

* system prompt
* `state_summary + legal_actions`

---

## Step 5：模型返回结构化结果

理想返回：

```json
{
  "action_id": "a2",
  "reason": "对方生命较低，当前攻击能制造最大压力。",
  "confidence": 0.84
}
```

---

## Step 6：再次校验动作

```gdscript
if not rules_engine.is_action_still_legal(ai_player_id, result.action_id):
    return fallback_ai.choose_action(game_state, ai_player_id, legal_actions)
```

---

## Step 7：执行动作

```gdscript
action_executor.execute(result.action_id)
```

---

# 8. 回退策略

这部分一定要有。

## 触发 fallback 的情况

* HTTP 请求失败
* 超时
* 返回不是合法 JSON
* `action_id` 不存在
* `action_id` 当前已不合法
* 模型拒绝回答
* 成本/频率限制触发

## fallback 行为

切到 `simple_ai_controller.gd`：

* 主要阶段优先出最高价值牌
* 攻击阶段优先直攻玩家
* 没有更优动作时结束阶段

---

# 9. 一版 `SimpleAI` 规则

你可以先这样定义：

## MAIN 阶段

* 若能直接形成斩杀路线，优先
* 否则优先打出高 BP 角色
* 其次优先抽牌事件
* 再其次优先解场
* 无动作时结束阶段

## ATTACK 阶段

* 若能直接攻击玩家，优先
* 若能解掉高价值敌方前线，次优
* 否则结束攻击阶段

## BLOCK 时机

* 若不挡会接近败北，优先阻挡
* 否则选择交换收益更高的阻挡

---

# 10. 推荐的 OpenAI 请求方式

如果你要用 OpenAI 官方推荐的新接口，优先走 **Responses API**。官方迁移文档也说明了：Responses API 是推荐方向，Structured Outputs 在 Responses 里的接口形态与旧接口不同。([OpenAI 开发者][1])

## 你的接入建议

* 新项目：Responses API
* 返回格式：Structured Outputs
* 仅在你后续需要“模型主动请求更多系统信息”时，再考虑 function calling

---

# 11. 难度模式建议

## 简单

只用 `SimpleAI`

## 普通

本地评分 AI + 偶尔调用大模型

## 困难

每个关键决策点都调用大模型，但仍强制走合法动作白名单

这样你能同时兼顾：

* 开发进度
* 网络波动
* 成本
* 体验

---

# 12. 建议你现在先做的最小版本

先别急着真接 OpenAI，先把这 4 个模块补出来：

1. `get_legal_actions(player_id)`
2. `state_summarizer.gd`
3. `simple_ai_controller.gd`
4. `llm_ai_controller.gd` 的空壳

只要这 4 个东西成型，后面接入大模型就很快了。

---

# 13. 可直接交给 Codex 的提示词

```text
请为当前 Godot 卡牌项目实现一版 LLM 机器方控制器框架。

要求：
1. 新增 AIController 抽象接口。
2. 实现 SimpleAIController 作为本地兜底 AI。
3. 实现 LLM_AIController 框架，但不要直接改 GameState。
4. 由 RulesEngine 提供 get_legal_actions(player_id)。
5. 新增 StateSummarizer，将 GameState 压缩为适合模型决策的摘要。
6. 新增 ActionFormatter，将 legal actions 转为精简 JSON。
7. LLM 只允许从 legal_actions 中选择 action_id。
8. 新增 response parser，解析结构化 JSON：
   - action_id: string
   - reason: string
   - confidence: float
9. 若 LLM 返回非法结果，则自动 fallback 到 SimpleAIController。
10. 输出修改的文件、模块职责、当前缺失项。
```

---

# 14. 一句话总结

这版最关键的点是：

**让大模型当“合法动作选择器”，不要让它当“规则执行器”。**

这样你的人机对战会稳定很多，也方便以后把大模型和本地 AI 混合使用。OpenAI 官方当前也明确支持用 Structured Outputs 保证 JSON 结构稳定，用 Responses API 作为新项目的推荐接口。