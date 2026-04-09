# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在本仓库工作时提供指导。

## 项目概览

- **引擎**：Godot 4.6
- **语言**：GDScript
- **项目类型**：本地 1v1 卡牌对战原型，规则设计参考 UNION ARENA
- **入口场景**：`res://scenes/battle_scene.tscn`
- **窗口尺寸**：1920x1080

## 常用命令

### 启动游戏
```powershell
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --path D:\CodexWork\TcgDemo
```

### 运行无头冒烟测试
```powershell
# 里程碑冒烟测试
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --script res://docs/milestone_smoke_test.gd

# 正式 raw 最小对局冒烟测试
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --script res://docs/cards_raw_minimal_duel_smoke_test.gd

# 卡组导入冒烟测试
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --script res://docs/deck_import_smoke_test.gd

# AI v2 行为冒烟测试
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --script res://docs/simple_ai_v2_smoke_test.gd

# VS AI 冒烟测试
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --script res://docs/vs_ai_smoke_test.gd

# 运行时残留冒烟测试
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --script res://docs/runtime_residue_smoke_test.gd
```

### 编译卡牌效果
```powershell
python tools/compile_cards_effects.py
```
将 `data/cards/<series>/cards_raw.json` 编译为对应系列目录下的 `cards_effects.json`，生成 DSL/IR 表示。

## 架构

### 核心模块 (`core/`)
- **`game_manager.gd`**：中央协调器，暴露游戏动作，管理状态快照，向 UI 发射信号。**已重构为协调器模式**，单一职责，1060 行。
- **`turn_manager.gd`**：阶段流转（DRAW → MOVE → MAIN → ATTACK → END），AP 成长，额外抽牌，手牌上限强制
- **`rules_engine.gd`**：出牌、移动、攻击、能量/AP 支付、区域容量校验层
- **`effect_resolver.gd`**：效果队列消费，触发结算，目标选择，费用支付，DSL/IR 执行
- **`battle_resolver.gd`**：攻击声明，阻挡，BP 比较，伤害计算，战斗触发
- **`zone_manager.gd`**：卡牌区域间移动，区域容量检查，洗牌，RAID 堆叠
- **`victory_checker.gd`**：胜负检测（生命归零，空牌库抽牌失败）

### 辅助管理器 (`core/` - 从 GameManager 提取)
- **`player_utils.gd`**：共享助手（`opponent_of`）
- **`game_gate_checker.gd`**：状态门检查
- **`deck_loader.gd`**：卡组/卡牌加载
- **`decision_manager.gd`**：决策队列管理
- **`life_trigger_manager.gd`**：生命触发/揭示处理
- **`controller_manager.gd`**：控制器管理（人类/AI）

### UI 序列化 (`core/ui/`)
- **`snapshot_serializer.gd`**：UI 快照序列化

### 数据模型 (`data/`)
- **`game_state.gd`**：运行时状态，包含玩家、卡牌、效果队列、待决策、战斗上下文
- **`player_state.gd`**：玩家区域（deck、hand、life、front_line、energy_line、ap_area、outside、removed）
- **`card_def.gd`**：静态卡牌定义，包含费用、BP、关键词、效果、trigger_effects
- **`card_instance.gd`**：运行时卡牌实例，包含 uid、zone、state、flags、stacked_under

### UI 层 (`ui/`)
- **`battle_scene.gd`**：主场景，消费 `get_snapshot()`，路由用户交互到 GameManager
- **`board_view.gd`**：战场显示，包含前线、能量线、生命区、卡组/场外区域
- **`hand_view.gd`**：手牌显示，包含卡牌缩略图和拖拽出牌
- **`card_view.gd`**：单卡渲染，包含状态/区域指示器

## 关键约束

### 区域容量（来自 `docs/rules/rule.md`）
- 前线：最多 4 张角色
- 能量线：最多 4 张卡（角色 + 场地合计）
- AP 区域：最多 3 槽
- 起始生命：7 张
- 起始手牌：7 张
- 主卡组：50 张
- 手牌上限（结束阶段）：8 张

### 卡牌状态规则
- 角色/场地进入时为 RESTED 状态
- 只有 ACTIVE 角色可以攻击或阻挡
- AP 卡在结束阶段不恢复
- 攻击方 BP 低于阻挡方时不会离场

## 卡牌效果 DSL/IR 原则

来自 `AGENTS.md`：

1. **按原子能力编码，不按单卡编码**：禁止卡牌专用逻辑；创建可复用的原子要求和步骤
2. **运行时只消费统一 IR**：不执行原始卡文
3. **严格区分要求和步骤**：
   - 要求：可用性、合法性、触发条件、筛选判断——不得修改游戏状态
   - 步骤：原子状态变更——不得包含条件分支或卡牌特判
4. **显式目标选择**：目标选择进入待决策流；禁止自动取前 N 个候选
5. **标记未支持卡牌**：无法用当前 IR 表达的卡牌应标记为"暂不支持"，而非硬编码

### 支持的触发类型
`ON_ENTER`、`ON_LEAVE`、`ON_ATTACK`、`ON_BLOCK`、`ON_LIFE_TRIGGER`、`MAIN_ACTIVATE`、`ON_BATTLE_WIN`、`ON_BATTLE_LOSE`、`ON_BATTLE_END`、`ON_PLAY`（事件）

### 已实现关键词
`STEP`、`SNIPER`、`DAMAGE_2`、`IMPACT`、`IMPACT_PLUS_1`、`NEGATE_IMPACT`、`DOUBLE_ATTACK`、`DOUBLE_BLOCK`、`RAID`

## 数据文件
- `data/cards/<series>/cards_raw.json`：官方源原始卡牌数据
- `data/cards/<series>/cards_effects.json`：编译后 IR（由 `tools/compile_cards_effects.py` 生成）
- `data/cards/base_cards.json`：旧版样例卡牌（由编译器合并）
- `data/decks/*.txt`：卡组列表，格式为 `Nx卡号`（如 `4xUA_BT01-001`）

## 权威来源

当代码、测试或文档冲突时：
1. **`docs/rules/rule.md`** 是游戏规则、状态机、区域限制、结算顺序和数据映射的最高权威
2. **`AGENTS.md`** 定义多 agent 协作协议和 DSL/IR 设计约束

## 验证基线（2026-03-31）

- `docs/milestone_smoke_test.gd`：33 通过，0 失败（规则语义）
- `docs/cards_raw_minimal_duel_smoke_test.gd`：69 通过，0 失败（raw 样例）
- `docs/runtime_residue_smoke_test.gd`：4 通过，0 失败（残留检查）
- `docs/simple_ai_v2_smoke_test.gd`：6 通过，0 失败（AI 行为）
- `docs/vs_ai_smoke_test.gd`：2 通过，0 失败（AI 流程）

## 重要注意事项

- 所有代码文件使用 UTF-8 编码；新增或修改文件时保持此编码
- 脚本变更后，运行无头冒烟测试确认工作完成
- UI 布局变更必须验证手牌区域不遮挡战场
- 除非明确要求，不要手动编辑 `.uid` 文件
- 保持 `res://` 路径有效
- 每次功能更新与每次 bugfix，都必须在同一轮改动中同步记录到 `docs/logs/` 目录下按天存放的日志文件。
- 日志文件命名规则固定为 `docs/logs/log_yyyy-MM-dd.md`，其中日期使用当前工作日日期；当日文件不存在时必须先创建再写入。
- 主 agent 在开始实现前，应先检查并读取最近的相关日志；优先读取当日日志文件，不存在时再查看最近已有的按日日志文件。
- 所有写入 `docs/logs/log_yyyy-MM-dd.md` 的内容必须使用中文描述，不允许使用英文摘要、英文模板或英文结论。
- 实现完成后，交付 agent 必须向当日日志文件 `docs/logs/log_yyyy-MM-dd.md` 追加一条简明记录，至少包含：
  - 日期
  - 变更类型（功能更新或 bugfix）
  - 变更摘要
  - 影响文件或模块
  - 验证方式与结果
- 如果某次改动没有写入对应日期的日志文件 `docs/logs/log_yyyy-MM-dd.md`，则该次工作应视为未完成。
- 多 agent 协作时，由主 agent 负责确保最终集成结果只在当日日志文件中记录一次，且内容为中文。