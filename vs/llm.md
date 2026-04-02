
# LLM 机器方控制器完整设计方案（DeepSeek 接入版）

> 适用场景：Godot 卡牌 / 回合制对战项目  
> 设计目标：让大模型只做“合法动作选择”，不直接参与规则执行  
> 当前默认接入：DeepSeek  
> 可扩展方向：OpenAI / 其他兼容 OpenAI API 的 provider

---

## 1. 方案目标

本方案用于实现一套稳定、可回退、可扩展的 **LLM 机器方控制器**。

核心目标：

1. 让大模型扮演 **AI 玩家决策器**
2. 大模型**只从合法动作列表中选择一个 `action_id`**
3. 游戏规则、状态修改、触发结算全部由本地规则层负责
4. 模型调用失败时自动回退到本地 `SimpleAI`
5. 支持少量结构化“决策上下文”，不采用长对话式历史
6. 支持后续从 DeepSeek 平滑切换到其他 provider

这套设计延续了已有方案中的关键原则：

> **让大模型当“合法动作选择器”，不要让它当“规则执行器”。**

---

## 2. 设计原则

### 2.1 职责边界清晰

#### LLM 负责
- 阅读当前局面摘要
- 阅读当前合法动作列表
- 结合少量决策上下文
- 选择一个最优 `action_id`
- 返回简短原因与置信度

#### 本地程序负责
- 生成合法动作
- 校验动作合法性
- 执行动作
- 处理触发 / 连锁 / 结算
- 更新 GameState
- 处理异常与 fallback
- 记录日志

---

### 2.2 白名单动作选择

模型绝不直接输出“执行某某效果”。

模型只能在 `legal_actions` 中选择：

- `action_id`
- `reason`
- `confidence`

即：

- **不能发明新动作**
- **不能假设未提供的规则**
- **不能直接改 GameState**
- **不能跳过规则校验**

---

### 2.3 结构化上下文，不做聊天式多轮记忆

本方案不建议把模型当作长期聊天代理，而是当作：

> **每个决策点执行一次推理的动作选择器**

因此要保留的是：

- 当前局面摘要
- 当前合法动作
- 本回合关键事件
- 最近动作链
- 难度 / 风格 /策略偏好

而不是：

- 所有历史 message
- 所有历史 reason
- 全量操作日志
- 长篇规则文本反复重复

---

### 2.4 失败必可回退

以下情况必须自动 fallback 到本地 AI：

- 网络异常
- 请求超时
- HTTP 非 2xx
- 返回非 JSON
- JSON 字段缺失
- `action_id` 不存在
- `action_id` 当前已不合法
- 模型拒答
- 命中频率 / 成本限制

---

## 3. 总体架构

```text
GameState
  ↓
RulesEngine.get_legal_actions(player_id)
  ↓
StateSummarizer.build_summary(game_state, player_id)
TurnContextBuilder.build_turn_context(match_memory, game_state, player_id)
ActionFormatter.format_actions(legal_actions)
  ↓
LLMPromptBuilder.build(...)
  ↓
LLMAIController
  ↓
LLMClient(DeepSeekClient)
  ↓
LLMResponseParser.parse_choice()
  ↓
SchemaValidator / legality check
  ↓
合法 -> 返回 action_id
非法/失败 -> AIFallback -> SimpleAIController
  ↓
RulesEngine.validate_action(action_id)
  ↓
ActionExecutor.execute(action_id)
  ↓
MatchMemory.record(...)
  ↓
下一次决策
````

---


## 4. 结合当前仓库的可行性结论

基于当前仓库现状，这份方案整体**可行**，但建议按“贴着现有 AI 闭环增量接入”的方式落地，而不是并行再造一套新的 AI 主链。

当前仓库已经具备以下关键前置条件：

* `RulesEngine.get_legal_actions()` 已能稳定生成合法动作
* `ControllerManager` 已形成“控制器请求动作 -> 执行动作”的驱动闭环
* `AIController` 与 `SimpleAI` 已经承担了机器方常规动作与部分待决策流处理
* `ActionFactory` 已为动作分配稳定 `id`
* `get_snapshot()` 已提供 AI 与 UI 共用的结构化视图

因此，本方案最值得保留的核心是：

* 大模型只做合法动作白名单选择
* 本地规则层保留状态与执行权
* provider 失败时立即 fallback 到 `SimpleAI`
* provider / parser / validator 抽象与具体模型解耦

同时，建议对原方案做以下收敛：

### 4.1 推荐接入姿势

* 优先在现有 `PlayerController -> AIController -> strategy.choose_*` 链路上扩展 `LLM` 控制器
* 第一版只替换“常规主动作选择”，不要一开始覆盖所有 pending decision
* 最终执行仍返回仓库现有 action dictionary，而不是强制引入一套新的运行时动作对象

### 4.2 当前最适合的 MVP 范围

第一版建议只覆盖：

* `request_action()` 下的 `MAIN`
* `request_action()` 下的 `ATTACK`
* 可选：候选动作数量较多的复杂主回合

第一版**暂不覆盖**：

* `request_pending_decision()`
* 生命触发选择
* 阻挡选择
* `RAID` 相关待决策
* 目标选择 / 顺序选择等高风险显式决策流

这些入口当前都已经由 `SimpleAI` 兜底，且直接关联高风险规则区；在规则稳定性优先的阶段，不建议第一版就把它们并入 LLM 决策面。

### 4.3 与当前计划的关系

当前项目主线仍是规则稳定性、长链验证与调试可见性，而不是大规模 AI 架构重写。因此这项工作更适合以 sidecar 能力接入，满足以下约束：

* 不改 `rule.md` 语义
* 不改规则执行权归属
* 不打断现有 `SimpleAI` 与冒烟验证入口
* 不在第一版引入大范围跨层接口改造

---

## 5. 模块目录建议

```text
scripts/ai/
  ai_controller.gd
  llm_ai_controller.gd
  simple_ai_controller.gd
  ai_fallback.gd
  ai_logger.gd

  context/
    state_summarizer.gd
    action_formatter.gd
    turn_context_builder.gd
    match_memory.gd
    llm_prompt_builder.gd

  model/
    legal_action.gd
    ai_choice_result.gd

  parser/
    llm_response_parser.gd
    schema_validator.gd

  provider/
    llm_client.gd
    deepseek_client.gd
    # openai_client.gd（后续可选）

  config/
    llm_config.gd
```

---

## 6. 模块职责设计

---

### 6.1 `ai_controller.gd`

统一 AI 控制器接口。

#### 职责

* 约束所有 AI 控制器的统一输入输出
* 屏蔽调用方对具体 AI 实现的差异感知

#### 统一接口建议

```gdscript
func choose_action(game_state, player_id: String, legal_actions: Array) -> Dictionary
```

#### 返回建议

```json
{
  "ok": true,
  "action_id": "a2",
  "reason": "当前攻击对对手生命造成最大压力",
  "confidence": 0.84,
  "used_fallback": false
}
```

---

### 6.2 `llm_ai_controller.gd`

LLM 机器方控制器主入口。

#### 职责

* 组织局面摘要
* 组织动作候选
* 组织决策上下文
* 构造 prompt / payload
* 调用 provider
* 解析与校验响应
* 失败时执行 fallback

#### 关键流程

1. 获取 `state_summary`
2. 获取 `turn_context`
3. 格式化 `legal_actions`
4. 构造输入 payload
5. 调用 `llm_client.choose_action(...)`
6. 解析响应
7. 校验 schema
8. 校验动作合法性
9. 返回动作或 fallback

---

### 6.3 `simple_ai_controller.gd`

本地兜底 AI。

#### 职责

* 在模型失败时提供可执行动作
* 保证流程稳定不中断
* 在简单难度下也可单独使用

#### 推荐规则

##### MAIN 阶段

* 若有斩杀动作，优先
* 否则优先高价值出牌
* 其次优先抽牌
* 其次优先解场
* 无更优动作则结束阶段

##### ATTACK 阶段

* 若可直攻玩家，优先
* 否则优先攻击高价值目标
* 否则结束攻击阶段

##### BLOCK 时机

* 若不挡接近败北，优先阻挡
* 否则优先高收益交换

---

### 6.4 `ai_fallback.gd`

统一封装 fallback 策略。

#### 职责

* 接收失败原因
* 决定是否回退
* 调用 `SimpleAIController`
* 统一输出 fallback 结果

#### 好处

* 让 `llm_ai_controller.gd` 更简洁
* 后续可扩展更多回退策略

  * 降级模型
  * 减少上下文后重试一次
  * 直接走本地 AI

---

### 6.5 `ai_logger.gd`

决策日志模块。

#### 职责

记录以下信息：

* 当前 turn / phase
* 当前局面摘要
* 当前候选动作
* 本回合上下文摘要
* 模型原始返回
* 解析结果
* 是否通过 schema 校验
* 是否通过 legality 校验
* 是否 fallback
* 最终执行动作

#### 建议用途

* 联调
* 复盘
* 质量评估
* 离线对局分析
* 成本 / 胜率统计

---

## 7. Context 层设计

---

### 7.1 `state_summarizer.gd`

将完整 GameState 压缩成适合 LLM 决策的摘要。

#### 目标

* 减少 token
* 减少噪音
* 突出对当前决策最重要的信息

#### 建议输出结构

```json
{
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
}
```

#### 压缩原则

保留：

* 生命
* 手牌数
* 牌库数
* 行动力 / 能量
* 场上核心单位
* 关键 keyword
* 当前 phase
* 先后手 / 当前行动方

省略：

* 与当前决策无关的低价值细节
* UI 信息
* 不会影响本次动作选择的历史信息

---

### 7.2 `action_formatter.gd`

把合法动作列表转成精简 JSON。

#### 目标

让模型只看“动作选择所需信息”，避免原始数据过重。

#### 输入

`Array[LegalAction]`

#### 输出示例

```json
[
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
```

#### 设计原则

* 只给模型必要字段
* `summary` 要可读且简明
* 不直接暴露过多内部实现字段
* 必要时允许附少量 `payload_hint`

---

### 7.3 `match_memory.gd`

保存对“当前与后续决策仍有价值”的结构化记忆。

#### 职责

* 记录当前对局中的关键事件
* 保存最近动作链
* 提供精简上下文给模型
* 不保存无意义冗余流水

#### 建议保存内容

* 当前 turn 关键事件
* 最近 N 个动作链节点
* 已知持续效果摘要
* 特殊限制状态

  * 本回合已攻击次数
  * 本单位本回合不能攻击
  * 某效果已触发一次
  * 某回合结束效果待结算

#### 不建议保存

* 模型长篇 reason
* 所有原始网络响应
* 所有完整历史动作日志

---

### 7.4 `turn_context_builder.gd`

从 `match_memory` 中生成 **本次决策真正需要的上下文摘要**。

#### 目标

不是把历史全塞给模型，而是只提供：

* 本回合关键事件
* 最近动作链
* 持续效果摘要
* 当前决策相关限制

#### 输出示例

```json
{
  "current_turn_key_events": [
    "本回合已使用一次抽牌事件",
    "前线单位 A 本回合刚获得 +1000 BP",
    "对方阻挡者 X 已横置"
  ],
  "recent_action_chain": [
    "PLAY_CARD:a3",
    "TRIGGER_EFFECT:t7",
    "RESOLVE_DRAW:1"
  ],
  "persistent_constraints": [
    "单位 A 本回合不能再次攻击",
    "本回合剩余可用 AP 为 2"
  ]
}
```

#### 原则

* 只保留当前选择会受影响的信息
* 优先结构化字段
* 控制体积，尽量精简

---

### 7.5 `llm_prompt_builder.gd`

负责拼装系统提示词与输入 payload。

#### 建议拆成两部分

1. `system prompt`
2. `input payload`

---

## 8. Prompt 设计

---

### 8.1 System Prompt

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
6. 返回结果必须为 JSON。
7. 若你无法判断，也必须从合法动作中选择一个最稳妥的动作。

决策偏好：
- 优先直接造成胜利或压低对手生命
- 优先高价值出牌
- 避免无意义结束阶段
- 避免明显亏节奏的攻击
- 若资源紧张，优先保留关键行动点和手牌价值
```

---

### 8.2 Input Payload

推荐把真实输入组织成一个 JSON 对象：

```json
{
  "match_context": {
    "difficulty": "hard",
    "ai_style": "balanced"
  },
  "state_summary": {},
  "turn_context": {},
  "legal_actions": []
}
```

---

## 9. 返回格式设计

---

### 8.1 推荐统一返回 JSON

```json
{
  "action_id": "a2",
  "reason": "对方生命较低，当前攻击能制造最大压力。",
  "confidence": 0.84
}
```

---

### 8.2 本地 Schema 约束

```json
{
  "type": "object",
  "properties": {
    "action_id": {
      "type": "string"
    },
    "reason": {
      "type": "string"
    },
    "confidence": {
      "type": "number"
    }
  },
  "required": ["action_id", "reason", "confidence"],
  "additionalProperties": false
}
```

#### 说明

虽然 DeepSeek 支持 JSON Output，但第一版建议：

* 让模型输出 JSON
* 本地使用 `schema_validator.gd` 进行二次校验

这样更稳，也更通用。

---

## 10. Provider 层设计

---

### 10.1 `llm_client.gd`

统一 provider 接口。

#### 职责

* 抽象模型调用行为
* 屏蔽 DeepSeek / OpenAI 等差异
* 向上层提供统一结果结构

#### 接口建议

```gdscript
func choose_action(
    system_prompt: String,
    input_payload: Dictionary,
    response_schema: Dictionary
) -> Dictionary
```

#### 返回建议

```json
{
  "ok": true,
  "content": "{\"action_id\":\"a2\",\"reason\":\"...\",\"confidence\":0.84}",
  "raw": {}
}
```

失败时：

```json
{
  "ok": false,
  "error": "http_429"
}
```

---

### 10.2 `deepseek_client.gd`

DeepSeek 实现类。

#### 目标

* 通过 DeepSeek Chat Completions 接口请求模型
* 默认使用 `deepseek-chat`
* 获取 JSON 输出
* 返回原始响应给上层解析

#### 接入策略

* Base URL：`https://api.deepseek.com/chat/completions`
* 鉴权：`Authorization: Bearer <API_KEY>`
* 输出模式：`response_format = {"type":"json_object"}`

#### 推荐默认模型

* `deepseek-chat`

#### 可选复杂推理模型

* `deepseek-reasoner`

---

### 9.3 为什么先用 DeepSeek JSON Output，而不是更复杂的 tool calling

对当前项目来说，模型只需要返回一个结构化选择结果：

* `action_id`
* `reason`
* `confidence`

不需要复杂工具编排，因此第一版最推荐：

* **JSON Output**
* **本地 Schema 校验**
* **本地 legality 校验**

这样接入快，调试也简单。

---

## 11. Parser 与校验层设计

---

### 11.1 `llm_response_parser.gd`

#### 职责

* 从 provider 返回结果中提取 `content`
* 解析 JSON
* 转换成统一结果结构

#### 流程

1. 提取 `content`
2. `JSON.parse_string(content)`
3. 字段存在性检查
4. 类型转换
5. 返回 `AIChoiceResult`

---

### 11.2 `schema_validator.gd`

#### 职责

做简化版本地 schema 校验：

* 是否为对象
* 是否存在必填字段
* `action_id` 是否为字符串
* `reason` 是否为字符串
* `confidence` 是否为数字

#### 第一版无需实现完整 JSON Schema 标准

只需满足当前项目需要即可。

---

## 12. 数据模型设计

---

### 12.1 `LegalAction`

```gdscript
class_name LegalAction
extends RefCounted

var action_id: String
var type: String
var summary: String
var payload: Dictionary = {}
```

---

### 12.2 `AIChoiceResult`

```gdscript
class_name AIChoiceResult
extends RefCounted

var ok: bool = false
var action_id: String = ""
var reason: String = ""
var confidence: float = 0.0
var provider: String = ""
var raw_content: String = ""
var error: String = ""
var used_fallback: bool = false
```

---

### 12.3 `LLMConfig`

建议集中管理：

* provider 名称
* 模型名
* API Key
* base URL
* timeout
* max_tokens
* 是否开启日志
* 是否启用 turn context
* 最近动作链条数
* 当前回合关键事件条数

---

## 13. 一次完整调用流程

---

### Step 1：规则层生成合法动作

```gdscript
var legal_actions = rules_engine.get_legal_actions(ai_player_id)
```

---

### Step 2：压缩局面摘要

```gdscript
var summary = state_summarizer.build_summary(game_state, ai_player_id)
```

---

### Step 3：构建决策上下文

```gdscript
var turn_context = turn_context_builder.build_turn_context(match_memory, game_state, ai_player_id)
```

---

### Step 4：格式化动作列表

```gdscript
var action_data = action_formatter.format_actions(legal_actions)
```

---

### Step 5：构造 payload

```gdscript
var payload = {
  "match_context": {
    "difficulty": "hard",
    "ai_style": "balanced"
  },
  "state_summary": summary,
  "turn_context": turn_context,
  "legal_actions": action_data
}
```

---

### Step 6：调用 provider

```gdscript
var result = llm_client.choose_action(system_prompt, payload, response_schema)
```

---

### Step 7：解析结果

```gdscript
var parsed = response_parser.parse_choice(result["content"])
```

---

### Step 8：Schema 校验

```gdscript
if not schema_validator.validate_choice(parsed):
    return fallback_ai.choose_action(...)
```

---

### Step 9：合法性二次校验

```gdscript
if not rules_engine.is_action_still_legal(ai_player_id, parsed.action_id):
    return fallback_ai.choose_action(...)
```

---

### Step 10：记录日志与记忆

```gdscript
ai_logger.log_choice(...)
match_memory.record_decision(...)
```

---

### Step 11：执行动作

```gdscript
action_executor.execute(parsed.action_id)
```

---

## 14. 决策上下文设计建议

---

### 13.1 什么时候要带上下文

需要保留的通常是：

* 本回合已发生的关键事件
* 影响当前选择的持续效果
* 最近 1~3 个动作链
* 本回合特殊限制
* AI 风格 / 难度偏好

---

### 13.2 什么不要带

尽量不要直接给模型：

* 所有历史对话
* 所有历史 reason
* 全量日志
* 与当前决策无关的旧信息

---

### 13.3 判断标准

可以用一句话判断某段信息是否应该进上下文：

> **如果去掉这段信息，当前动作选择是否可能明显变差或变错？**

如果会，就保留。
如果不会，就不要塞进去。

---

## 15. Fallback 设计

---

### 14.1 触发条件

* 请求失败
* 超时
* 解析失败
* schema 校验失败
* 动作非法
* provider 返回空结果
* 成本 / 频率限制

---

### 14.2 回退策略建议

#### 第一层

直接 fallback 到 `SimpleAIController`

#### 第二层（可选）

未来可扩展：

* 降级模型
* 缩短上下文后再试一次
* 关键回合尝试 `reasoner`
* 普通回合直接本地 AI

---

## 16. 难度模式建议

---

### 简单

* 全程 `SimpleAI`

### 普通

* 本地评分 AI 为主
* 关键节点调用 `deepseek-chat`

### 困难

* 关键决策优先调用 LLM
* 仍然只允许从合法动作白名单中选择

### 专家 / 实验模式

* 普通回合 `deepseek-chat`
* 复杂斩杀 / 高复杂交换 使用 `deepseek-reasoner`

---

## 17. DeepSeek 接入建议

---

### 16.1 第一版推荐方案

* Provider：DeepSeek
* 模型：`deepseek-chat`
* 输出方式：JSON Output
* 本地做 schema 校验与 legality 校验
* 失败立即 fallback

#### 原因

* 实现简单
* 调试成本低
* 与现有架构最匹配
* 足够支撑“合法动作选择器”场景

---

### 16.2 第二版可扩展方向

* `deepseek-reasoner` 用于复杂回合
* provider 路由器
* 自适应上下文裁剪
* 成本与延迟预算控制
* 离线评估与胜率分析

---

## 18. 日志与评估建议

建议记录：

* 对局 ID
* turn / phase
* state_summary
* turn_context
* legal_actions
* provider / model
* 请求 token 估计
* 原始响应
* 解析结果
* legality 校验结果
* fallback 原因
* 最终动作
* 对局结果

### 用途

* 调试决策质量
* 发现 prompt 问题
* 优化摘要策略
* 统计成本
* 评估胜率

---

## 19. 最小可落地版本（MVP）

第一阶段建议只做以下模块：

1. 复用现有 `RulesEngine.get_legal_actions()`
2. 复用现有 `SimpleAI`
3. `state_summarizer.gd`
4. `action_formatter.gd`
5. `llm_client.gd`
6. `deepseek_client.gd`
7. `llm_response_parser.gd`
8. `llm_ai_controller.gd`
9. `ai_fallback.gd`

第二阶段再补：

1. `match_memory.gd`
2. `turn_context_builder.gd`
3. `ai_logger.gd`
4. `schema_validator.gd`

### 19.1 MVP 范围收敛建议

为控制风险，第一版建议进一步收敛为：

* 仅在 `request_action()` 中启用 LLM
* 仅在 `MAIN / ATTACK` 阶段启用 LLM
* 仅当候选动作数达到一定阈值时调用 LLM
* 其他情况直接复用 `SimpleAI`

推荐的第一版保护链路：

1. 生成现有 `legal_actions`
2. 基于现有 snapshot 生成摘要
3. LLM 仅返回 `action_id`
4. 本地解析并在现有动作列表中查找匹配项
5. 匹配失败或请求失败时直接 fallback 到 `SimpleAI`

这样做的好处是：

* 几乎不改现有执行链
* 避免第一版引入 pending decision 的规则风险
* 更符合当前开发计划中的“规则稳定优先”

---

## 20. 推荐开发顺序

### Phase 1：本地闭环

* 复核现有 `RulesEngine.get_legal_actions()`、`ControllerManager`、`SimpleAI`
* 明确 `LLM` 控制器仅增量接入，不改现有执行闭环
* 统一第一版只覆盖 `MAIN / ATTACK`

### Phase 2：接入 LLM

* 完成 `LLMClient`
* 完成 `DeepSeekClient`
* 完成 `LLMResponseParser`
* 完成 `LLMAIController`

### Phase 3：增强稳定性

* 增加 fallback
* 增加 schema 校验
* 增加日志
* 增加上下文记忆

### Phase 4：增强质量

* 优化状态摘要
* 优化动作 summary
* 分难度调用模型
* 关键回合启用更强推理模型

---

## 21. 主要风险点

### 20.1 模型返回不稳定

解决：

* 强制 JSON 输出
* 本地 parser + schema 校验
* 非法即 fallback

### 20.2 上下文过大导致成本高 / 延迟高

解决：

* 压缩 `state_summary`
* 只保留结构化 turn context
* 避免长对话历史

### 20.3 动作 summary 写得太差导致模型选错

解决：

* 提高 `summary` 可读性
* 使用面向决策的描述
* 避免歧义

### 20.4 模型选到过期动作

解决：

* 执行前再次 legality check
* 不合法即 fallback

### 20.5 网络不稳定

解决：

* timeout
* fallback
* 普通难度减少调用频率


### 21.6 第一版覆盖面过大

若一开始就让 LLM 接管阻挡、生命触发、RAID、目标选择等待决策流，会显著提高接入风险。

解决：

* 第一版只接常规主动作
* 高风险待决策继续由 `SimpleAI` 处理
* 待规则与日志稳定后再逐步扩大覆盖面

### 21.7 与现有仓库结构脱节

若按独立 `scripts/ai/` 重起一套平行目录，容易与现有 `core/controllers/ai_controller.gd`、`core/ai/simple_ai.gd`、`ControllerManager` 形成双轨维护。

解决：

* 贴着现有 `core/` 结构扩展
* 继续复用 snapshot 与动作 dictionary
* 避免第一版引入新的运行时动作模型

### 21.8 返回结构过重导致失败率升高

若第一版强制要求 `action_id + reason + confidence` 全部稳定返回，解析失败率会高于只要求 `action_id`。

解决：

* 第一版把 `action_id` 视为唯一硬要求
* `reason` 与 `confidence` 可作为可选日志字段
* 本地解析与合法性命中优先于解释性文本

---

## 22. 最终结论

本方案的核心不是“让大模型接管游戏”，而是：

> **让大模型在规则引擎给出的合法动作白名单中，做一次受约束的动作选择。**

结合当前仓库实现现状，最终建议如下：

1. **方向成立，但应贴着现有 AI 闭环增量接入，而不是平行重写**
2. **规则层永远掌握真实状态与执行权**
3. **模型第一版只输出 `action_id` 即可，`reason / confidence` 作为可选附加信息**
4. **第一版只覆盖 `MAIN / ATTACK` 常规主动作选择**
5. **高风险待决策流继续由 `SimpleAI` 兜底**
6. **任何异常都必须立即回退到本地 `SimpleAI`**

因此，最关键的落地判断不是“能不能做”，而是“第一版收敛到多小才最稳”。

当前最稳、最适合工程落地的一版，不是“大而全的 LLM AI 系统”，而是：

* 复用现有 `RulesEngine.get_legal_actions()`
* 复用现有 `ControllerManager` 与 `SimpleAI`
* 在 `MAIN / ATTACK` 决策点按需调用 DeepSeek
* 输出严格受限于合法动作白名单
* 本地做解析、命中校验与 legality 校验
* 失败后立即 fallback

其总体思路与原始方案保持一致，但在接入位置、目录组织、MVP 边界和第一版风险控制上，应按本节修订意见收敛实施。

---
