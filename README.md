# TcgDemo

基于 Godot 4.6 的本地 1v1 卡牌对战原型项目，玩法设计参考 UNION ARENA 风格。当前仓库已经不只是“能开局的原型”，而是具备基础对局闭环、关键高风险规则、统一效果队列消费链路，以及一批正式 `cards_raw.json` 样例验证的可运行版本。

## 项目定位

- 引擎：Godot 4.6
- 语言：GDScript
- 主场景：`res://scenes/battle_scene.tscn`
- 项目目标：先保持规则实现与权威规则文档一致，再逐步把更多正式卡牌文本收敛到统一 DSL/IR 运行时

## 权威来源

开始改代码前，建议先看这几份文件：

- `docs/rules/rule.md`
  - 项目规则、区域限制、结算顺序、状态机和数据映射的最高权威来源
- `AGENTS.md`
  - 本仓库的多 agent 协作规范、边界、验收要求和日志要求
- `docs/plan/project_development_plan.md`
  - 正式开发计划
- `docs/plan/mile_stone.md`
  - 当前里程碑盘点，描述“仓库目前已经实现到了哪里”

如果代码、测试、文档三者不一致，应以 `docs/rules/rule.md` 为准。

## 当前实现状态

### 基础对局闭环

当前已经具备：

- 双方 50 张主卡组、起手 7 张、生命区 7 张
- 回合与阶段流转
- AP 成长、消耗与重置
- 区域管理：牌库、手牌、生命区、前线、能量线、场外、除外
- 基础出牌规则
- 攻击、阻挡、战斗伤害与胜负判定
- 生命触发显式决策
- 一批关键字与特殊规则，包括 `STEP`、`SNIPER`、`DAMAGE_2`、`IMPACT`、`NEGATE_IMPACT`、`DOUBLE_ATTACK`、`DOUBLE_BLOCK`、`RAID`

### 效果系统

当前效果系统已经形成统一的 `effect_queue` 消费主链路，并支持：

- `ON_ENTER`
- `ON_LEAVE`
- `ON_ATTACK`
- `ON_BLOCK`
- `ON_LIFE_TRIGGER`
- `MAIN_ACTIVATE`
- `ON_BATTLE_WIN`
- `ON_BATTLE_LOSE`
- `ON_BATTLE_END`

已接入的效果能力包括基础抽牌、移动、激活/休息、对玩家造成伤害，以及一批显式目标、费用和多步骤结算模板。

### DSL/IR 现状

项目当前遵循这些原则：

- 按原子能力写代码，而不是按单卡写特判
- 运行时只消费统一 IR，不直接执行原始卡文
- 严格区分“要求”和“步骤”
- 目标选择默认进入显式待决策流
- 无法表达的正式卡先标记为“暂不支持”，而不是按卡硬编码

截至当前里程碑，正式 raw 编译结果为：

- 已支持能力：`59`
- 未支持能力：`14`

## 当前已覆盖的正式 raw 样例

`docs/cards_raw_minimal_duel_smoke_test.gd` 目前已经直接消费正式 `cards_raw.json` 卡定义，覆盖了这些典型入口和模板：

- `ON_ENTER` 抽 2
- `ON_PLAY` 从生命区取 1 到手后再抽 2
- 手牌中自减 AP
- `ON_LEAVE` 回手
- 多步骤复杂费用结算
- 看牌堆顶后加入手牌、剩余回底
- 看牌堆顶后按不同卡名去重选择
- `MAIN_ACTIVATE` 从生命区取牌
- 事件牌重置 AP
- 生命触发显式目标选择

## 验证状态

当前关键冒烟结果：

- `docs/milestone_smoke_test.gd`
  - `23` 项通过，`0` 项失败
- `docs/cards_raw_minimal_duel_smoke_test.gd`
  - `10` 项通过，`0` 项失败

Godot 退出时仍有既有资源泄漏告警，但当前未影响断言结果。

## 目录说明

- `core/`
  - 回合流程、规则校验、战斗、效果结算、胜负判断、区域管理
- `data/`
  - 运行时状态模型、卡牌定义、卡组数据
- `ui/`
  - 界面层、交互脚本、快照消费
- `scenes/`
  - Godot 场景
- `docs/`
  - 测试脚本、计划文档、日志和辅助资料
- `tools/`
  - 数据整理、编译与辅助脚本

## 常用命令

### 重新编译正式卡效果

```powershell
python tools/compile_cards_effects.py
```

### 运行里程碑冒烟

```powershell
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --script res://docs/milestone_smoke_test.gd
```

### 运行正式 raw 最小样例冒烟

```powershell
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --script res://docs/cards_raw_minimal_duel_smoke_test.gd
```

### 启动项目

```powershell
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --path D:\CodexWork\TcgDemo
```

## 协作与提交前注意事项

- 不要让实现偏离 `docs/rules/rule.md`
- 涉及 `EffectResolver`、卡牌结构、导入链路或运行时效果模型时，先确认 DSL/IR 契约
- 不要为单卡写专用运行时逻辑
- 每次功能更新或 bugfix 都要同步记录到 `docs/logs.md`
- 修改脚本后优先做一次 headless 冒烟验证
- 涉及界面布局改动后，要额外确认手牌区域没有遮挡战场区域

## 下一步重点

按当前里程碑，下一步最值得继续推进的是：

- 看牌堆顶后的条件追加结算
- 更多多目标并行结算模板
- 更复杂费用组合
- 更多正式 raw 卡样例接入统一 DSL/IR

