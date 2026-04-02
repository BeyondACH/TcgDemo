# TcgDemo

基于 Godot 4.6 的本地 1v1 卡牌对战原型项目，玩法设计参考 UNION ARENA 风格。当前仓库已完成基础对局闭环、主要高风险规则区、统一 DSL/IR 执行链与正式 raw 首轮收口，当前开发重点已转入“规则稳定性、长链路验证与回归资产建设”。

## 项目定位

- 引擎：Godot 4.6
- 语言：GDScript
- 主场景：`res://scenes/battle_scene.tscn`
- 目标：保持规则实现与 `docs/rules/rule.md` 一致，并持续把更多正式卡牌文本收敛到统一 DSL/IR 运行时

## 先看哪些文档

开始改代码前，建议先读这几份文件：

- `docs/rules/rule.md`
  - 规则、区域限制、结算顺序、状态机和数据映射的最高权威来源
- `AGENTS.md`
  - 多 agent 协作规范、边界、日志要求和验收标准
- `docs/plan/development_plan.md`
  - 当前正式开发计划与阶段安排
- `docs/plan/mile_stone.md`
  - 当前仓库已经实现到哪里的盘点

若代码、测试、README 与规则冲突，以 `docs/rules/rule.md` 为准。

## 当前状态

### 规则与对局闭环

当前已经具备：

- 50 张主卡组、7 张起手、7 张生命区
- `DRAW -> MOVE -> MAIN -> ATTACK -> END` 主阶段流转
- AP 成长、支付、额外抽牌与结束阶段不恢复 AP
- 前线/能量线/生命区/AP/场外/除外等核心区域管理
- 基础出牌、移动、攻击、阻挡、伤害与胜负判断
- 生命触发显式决策、生命触发 `RAID` 失败自动回手与结束阶段显式弃牌决策

### 已覆盖的关键规则能力

当前已接入一批高价值关键词与特殊规则：

- `STEP`
- `SNIPER`
- `DAMAGE_2`
- `IMPACT`
- `IMPACT_PLUS_1`
- `NEGATE_IMPACT`
- `DOUBLE_ATTACK`
- `DOUBLE_BLOCK`
- `RAID`

并已补齐一轮高风险规则专项验证，包括：

- 攻击失败的攻击方不会退场
- 生命触发必须显式选择是否发动
- 同时触发顺序按规则处理
- AP 在结束阶段不恢复

### 效果系统与 DSL/IR

当前效果系统已经统一接入 `effect_queue` 主链路，并配套：

- `pending_decisions`
- `pending_life_triggers`
- `battle_context`
- `delayed_effects`
- `static_modifiers`

运行时当前只消费统一 IR，不直接执行原始卡文。项目坚持以下原则：

- 按原子能力写代码，不按单卡写特判
- 严格区分“要求”和“步骤”
- 默认通过显式待决策流处理目标选择
- 新增模板先扩 DSL/IR，再扩编译链与运行时
- 若后续重构 `tools/compile_cards_effects.py` 识别层，完成标准应是“同类文本参数化复用同一模板族”，而不是仅把逐句匹配搬进注册表
- 2026-04-02 已完成首轮 registry 化落地，编译结果保持正式 raw `174 / 6`、运行时总量 `177 / 6` 不变。
截至 2026-04-01，正式 raw 基线为：

- 已支持能力：`174`
- 未支持能力：`6`

## 验证基线

当前关键验证入口与结果：

- `docs/milestone_smoke_test.gd`
  - 33 项通过，0 项失败
- `docs/cards_raw_minimal_duel_smoke_test.gd`
  - 75 项通过，0 项失败
- `docs/runtime_residue_smoke_test.gd`
  - 7 项通过，0 项失败
- `docs/draw_phase_smoke_test.gd`
  - 当前环境稳定通过，可作为 DRAW 阶段专项回归入口
- `docs/life_reveal_modal_smoke_test.gd`
  - 可作为生命翻开快照与弹窗交互专项回归入口

Godot 退出时仍存在既有 `ObjectDB` / resource 泄漏告警，但目前未影响断言结果。

导入链路方面，`tools/import_cards_raw_from_pic.ps1` 现已同时补齐浏览器请求头与失败原因分类；截至 2026-04-01，已确认 `UA31BT-MMM-1-001` 到 `034` 在沙箱外可正常访问官网详情页，之前批量报 `official_page_not_found` 的直接原因是沙箱内网络失败被脚本误归类。当前导入脚本默认应在沙箱外执行，若在沙箱内复现失败，优先按 `network_error` / `request_failed` 口径排查环境，而不是先假定官网缺卡。正式 raw 的 `6` 条未支持能力清单见 `docs/plan/card_design.md`。

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

脚本会扫描 `data/cards/*/cards_raw.json`，并逐系列生成对应的 `cards_effects.json` 与 `cards_semantic.json`。

### 检查中文文档编码污染

```powershell
python tools/check_utf8_docs.py
```

可选地也可以传入文件或 glob，只扫描局部目标：

```powershell
python tools/check_utf8_docs.py README.md docs/plan/*.md
```

该脚本只做告警与定位，不会自动改写文件；当前会重点报告连续 `?`、Unicode 替代字符以及已知英文旧口径残留。

### 卡图补录到系列 `cards_raw.json`

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\import_cards_raw_from_pic.ps1
```

该抓取脚本默认应在沙箱外执行；若输出 `network_error` 或 `request_failed`，优先排查执行环境网络，而不是直接按 `official_page_not_found` 处理。

当前正式卡池已按系列目录存放，例如 `MMM` 系列使用：

- `data/cards/MMM/cards_raw.json`
- `data/cards/MMM/cards_semantic.json`
- `data/cards/MMM/cards_effects.json`

运行时会自动聚合扫描 `data/cards/*/cards_effects.json`，并额外补充根目录 `data/cards/base_cards.json`。

### 生成 `pic/micro/` 缩略图

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\generate_micro_card_images.ps1
```

建议在卡图补录成功后顺带执行一次，用来为 `pic/` 顶层 `.png` 卡图补齐缺失的 micro 缩略图。

### 运行规则主冒烟

```powershell
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --script res://docs/milestone_smoke_test.gd
```

### 运行正式 raw 样例冒烟

```powershell
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --script res://docs/cards_raw_minimal_duel_smoke_test.gd
```

### 运行 DRAW 阶段专项

```powershell
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --script res://docs/draw_phase_smoke_test.gd
```

### 执行布局验收

```powershell
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --resolution 1920x1080 --path D:\CodexWork\TcgDemo -- --layout-probe
```

### 启动项目

```powershell
D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --path D:\CodexWork\TcgDemo
```

## 协作与提交前注意事项

- 不要让实现偏离 `docs/rules/rule.md`
- 涉及 `EffectResolver`、卡牌结构、导入链路或运行时效果模型时，先确认 DSL/IR 契约
- 不要为单卡写专用运行时逻辑
- 每次功能更新或 bugfix 都要同步记录到 `docs/logs/log_yyyy-MM-dd.md`
- 修改脚本后优先做一次 headless 冒烟验证
- 涉及界面布局改动后，要额外确认手牌区域没有遮挡战场区域
- 读取中文规则、计划、日志时优先使用显式 UTF-8 方式，避免终端编码噪音误判
- 修改中文文档时优先使用 `apply_patch`；若必须脚本写回，需显式指定 UTF-8 无 BOM，避免把 PowerShell 控制台当作文档中转层
- 修改中文文档后，至少补做一次“UTF-8 显式复读 + `git diff` 静态复核”；若有需要，可补跑 `python tools/check_utf8_docs.py`

## 下一步重点

按当前里程碑，下一阶段最值得继续推进的是：

- 保持 `docs/milestone_smoke_test.gd`、`docs/cards_raw_minimal_duel_smoke_test.gd` 与 `docs/runtime_residue_smoke_test.gd` 三个入口稳定通过
- 优先继续收口 `docs/plan/card_design.md` 中剩余 `6` 条正式 raw 未支持能力，继续遵守“先扩可复用 DSL/IR，再接入数据”的原则
- 继续补比当前最小样例更长链的自动验证，优先覆盖连续回合生命周期、延迟效果过期、离场触发链与完整流程推进
- 暂不进行 UI 相关调整，`docs/plan/ui_art_style_guide.md` 保留为后续阶段的冻结基线
- 持续观察 Godot 退出时既有资源告警是否影响长期回归稳定性
