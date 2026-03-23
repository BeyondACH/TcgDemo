# 当前项目里程碑盘点

更新时间：2026-03-23

## 1. 盘点依据

- 协作规范：`AGENTS.md`
- 权威规则：`docs/rules/rule.md`
- 正式计划：`docs/plan/project_development_plan.md`
- 核心实现：`core/`、`data/`、`ui/`
- 验证脚本：`docs/milestone_smoke_test.gd`、`docs/deck_import_smoke_test.gd`、`docs/draw_phase_smoke_test.gd`
- UI 布局验收入口：`res://scenes/battle_scene.tscn` 在命令行参数 `--layout-probe` 下执行自检

本文件用于描述“当前仓库已经实现到哪里”，不是未来规划替代品。若与规则语义冲突，仍以 `docs/rules/rule.md` 为准。

## 2. 当前总体结论

当前仓库已经不是只具备最小开局能力的空壳原型，而是已经完成了一个可运行的规则闭环，并继续向关键词、触发、叠放和显式决策推进。

当前状态可概括为：

- 已完成基础对局闭环：开局、抽牌、AP 成长、阶段推进、出牌、移动、攻击/阻挡、伤害、胜负判定、基础 UI 快照展示。
- 已完成一批高价值规则能力：生命触发显式决策、`MAIN_ACTIVATE`、`STEP`、`SNIPER`、`DAMAGE_2`、`IMPACT`、`NEGATE_IMPACT`、`DOUBLE_ATTACK`、`DOUBLE_BLOCK`、`RAID` 显式落点选择与叠放。
- 已具备数据与工具能力：`cards_raw.json`/`base_cards.json` 双源加载、txt 卡组导入、导入冒烟脚本。
- 已补齐一轮更贴近正式数据的验证资产：`cards_raw.json` 最小样例对局脚本已覆盖 `ON_ENTER`、`MAIN_ACTIVATE`、`ON_PLAY`、`ON_LIFE_TRIGGER` 四类效果入口。
- UI 已进一步贴近示例战场图：双方战场已补齐卡组区、场外区、除外区独立展示，底部手牌区已切为纯缩略图展示。
- 仍有若干里程碑未闭环：效果系统虽已形成统一 `effect_queue` 入队与消费主链路，但更复杂的条件组合、多触发顺序与更多原子费用/目标模板仍未完全扩展到计划终态。

## 3. 里程碑状态

## 里程碑 M1：基础对局闭环

状态：已实现

已确认能力：

- 双方使用 50 张主卡组初始化，起手 7 张，生命区 7 张。
- 常量约束已经落到代码：前线上限 4、能量线上限 4、AP 上限 3、手牌上限 8。
- 回合管理已经具备 `DRAW -> MOVE -> MAIN -> ATTACK -> END` 流程，并在回合切换时重置行动方与 AP。
- 先手首回合跳过自动抽牌，且支持支付 1 AP 进行额外抽 1。
- 结束阶段超手牌已改为显式弃牌待决策；玩家需要把超出的手牌逐张弃到场外，处理完成后才会真正换手。
- 角色可从手牌打到前线或能量线，场地牌只能进入能量线，事件牌结算后进入场外。
- 移动阶段支持能量线角色前移到前线。
- 胜负判定已经覆盖生命归零与抽牌失败导致的空牌库败北。
- `GameManager.get_snapshot()` 已向 UI 暴露玩家、战斗上下文、待决策项、待生命触发项和日志。

对应实现位置：

- `core/game_manager.gd`
- `core/turn_manager.gd`
- `core/rules_engine.gd`
- `core/zone_manager.gd`
- `core/victory_checker.gd`
- `data/game_state.gd`
- `data/player_state.gd`

备注：

- 当前开局后实际阶段已进入 `DRAW`，与部分旧测试仍假定初始化后处于 `MOVE` 不一致。

## 里程碑 M2：战斗与高风险规则增强

状态：大部分已实现

已确认能力：

- 只有前线 `ACTIVE` 角色可攻击。
- 玩家直伤与指定前线角色攻击两条分支都已存在。
- 普通攻击支持阻挡流程，`SNIPER` 攻击不可被阻挡。
- 伤害、战斗胜负、离场与战斗结束触发已接入结算流程。
- `DAMAGE_2` 可造成 2 点直伤。
- `IMPACT`、`IMPACT_PLUS_1`、`NEGATE_IMPACT` 已纳入战斗伤害逻辑。
- `DOUBLE_ATTACK`、`DOUBLE_BLOCK` 已支持第一次后恢复 `ACTIVE`、第二次后消耗完毕。
- 生命受伤后不会立即自动发动效果，而是进入待决策队列，由玩家显式选择是否发动生命触发。

对应实现位置：

- `core/battle_resolver.gd`
- `core/effect_resolver.gd`
- `core/rules_engine.gd`

对应验证：

- `docs/milestone_smoke_test.gd` 中以下场景当前通过：生命触发显式决策、`SNIPER`、`DAMAGE_2`、冲击/无效、双次攻击/阻挡、战斗触发、`RAID`、空牌库败北。

## 里程碑 M3：关键词、叠放与特殊登场

状态：大部分已实现

已确认能力：

- `STEP` 已支持从前线退回能量线。
- 当能量线已满时，`STEP` 已支持进入待决策并与能量线角色交换。
- `RAID` 已支持特殊登场校验、目标合法性校验和能量线目标的显式落点选择。
- `RAID` 目标在能量线时，玩家可决定叠放后留在能量线或转到前线。
- `RAID` 已记录 `stacked_under` 关系。
- 叠放卡离场时，下层卡会被一并释放到场外。
- `RAID_INNER` 效果门控已接入，只在通过 `RAID` 登场时启用。

对应实现位置：

- `core/rules_engine.gd`
- `core/zone_manager.gd`
- `core/game_manager.gd`
- `core/effect_resolver.gd`

对应验证：

- `docs/milestone_smoke_test.gd` 中 `STEP`、`RAID` 显式落点选择、`RAID` 叠放、`RAID` 框内效果门控当前通过。

## 里程碑 M4：效果系统与可扩展能力

状态：部分实现

已确认能力：

- `trigger_effects` 已支持 `ON_ENTER`、`ON_LEAVE`、`ON_ATTACK`、`ON_BLOCK`、`ON_LIFE_TRIGGER`、`MAIN_ACTIVATE`、`ON_BATTLE_WIN`、`ON_BATTLE_LOSE`、`ON_BATTLE_END`。
- `MAIN_ACTIVATE` 已带有 `once_per_turn` 限制与回合重置。
- 已支持基础操作：抽牌、移动区域、休息、激活、对玩家造成伤害。
- 已支持步骤式效果结构、目标选择集合、延迟效果注册、静态修正注册。
- `preview_play_modifiers()` / `commit_play_modifiers()` 已具备出牌前 AP 修正与一次性消耗能力。
- `GameState` 已接入 `effect_queue`、`delayed_effects`、`static_modifiers`、`battle_context`、`pending_decisions` 等运行时容器。
- `resolve_effect`、`resolve_trigger`、`MAIN_ACTIVATE` 与手动目标续执行已统一接入 `effect_queue`，并在遇到显式决策或生命触发阻塞点时暂停消费。
- IR 层 `costs` 与 `target_specs` 已打通运行时消费，当前已覆盖显式目标选择、`PAY_AP`、`REST_SOURCE` 等最小费用链路。
- `GameManager.get_snapshot()` 已补充 `effect_queue_count`，便于 UI 与调试面观察队列状态。
- `cards_raw.json` 新增支持 `DRAW_2`、手牌中自减 AP，以及“先选择己方代价对象，再按其 BP 选择敌方目标并抽 2”这类多步骤费用结算模板；当前统一 DSL 已提升到 57 个已支持能力、16 个未支持能力。

尚未闭环部分：

- 更复杂的条件组合、费用模板、目标筛选与多触发顺序仍未完全扩展到计划书目标范围。
- 当前 `cards_raw.json` 最小样例脚本已覆盖 8 条正式 raw 样例、5 类正式 raw 效果入口，但尚未覆盖更多检索/看牌堆顶、离场触发链与更复杂多目标结算组合。

对应实现位置：

- `core/effect_resolver.gd`
- `data/game_state.gd`
- `data/card_def.gd`

## 里程碑 M5：数据、卡组导入与测试资产

状态：部分实现

已确认能力：

- 游戏启动优先加载 `data/cards/cards_raw.json`，并兼容补充 `data/cards/base_cards.json`。
- 双方起始卡组已经切换为 txt 入口：`data/decks/starter_a.txt`、`data/decks/starter_b.txt`。
- txt 卡组行格式已支持 `数量 x 卡号`。
- 导入工具已支持缺卡统计、非法行校验、输出 deck json。
- 存在独立导入冒烟脚本，且本次执行通过。

对应实现位置：

- `core/game_manager.gd`
- `docs/deck_importer.gd`
- `docs/import_deck.gd`
- `docs/deck_import_smoke_test.gd`

## 里程碑 M6：UI、交互与快照消费

状态：部分实现

已确认能力：

- 主战斗场景已接入回合、行动方、阶段、胜者、日志、手牌、前线、能量线展示。
- 主战斗场景已补齐卡组区、场外区、除外区的独立展示，并形成左列生命/除外、中列前线/能量线、右列卡组/场外的三列战场布局。
- UI 已接入阻挡选择、`No Block`、额外抽牌、角色前移、`MAIN_ACTIVATE`、`STEP`、`SNIPER` 指定攻击。
- UI 已接入生命触发选择器与待决策面板，可消费 `pending_life_triggers` 和 `pending_decisions`。
- 底部手牌区已改为纯缩略图展示，移除了手牌标题与手牌卡右侧文字框，拖拽预览也已同步改为图片卡面。
- UI 已具备一定的响应式布局调整逻辑，紧凑模式下会收缩侧列牌堆与手牌缩略图尺寸。

对应实现位置：

- `ui/battle_scene.gd`
- `ui/board_view.gd`
- `ui/hand_view.gd`
- `ui/card_view.gd`
- `ui/log_panel.gd`
- `scenes/battle_scene.tscn`

备注：

- 仓库历史记录表明曾多次调整“手牌区域不得遮挡战场区域”；当前已补一轮 GUI 布局专项验收，覆盖 1920x1080、1600x900、1366x768、1280x720 四组常见窗口尺寸，并确认三列战场与底部手牌纯缩略图未发生遮挡。

## 4. 当前已知差距与风险

- 效果系统虽然已经形成统一 `effect_queue` 消费链路，但复杂条件组合、多触发顺序与更丰富的费用/目标模板仍未完全闭环。
- `docs/draw_phase_smoke_test.gd` 在本地环境下执行仍出现过 Godot headless 进程崩溃，当前不适合作为稳定验证依据。
- `docs/milestone_smoke_test.gd` 已修正到与当前实现一致，但脚本退出时仍有 Godot 资源未清理警告，暂未影响断言结果。
- `docs/cards_raw_minimal_duel_smoke_test.gd` 已降低测试与正式数据脱节风险，但覆盖面仍偏最小样例，尚不能替代完整规则回归。
- UI 新布局已通过 GUI 布局专项验收，但若后续继续改底部 HUD 高度或战场列宽，仍建议补一次实际窗口目视确认。

## 5. 本次验证结果

- 已执行 `docs/milestone_smoke_test.gd`
  - 结果：23 项通过，0 项失败。
  - 当前总冒烟脚本已与现实现状、阶段流转、效果队列消费链路与费用/目标最小样本同步。
- 已执行 `docs/deck_import_smoke_test.gd`
  - 结果：通过。
- 已执行 `docs/cards_raw_minimal_duel_smoke_test.gd`
  - 结果：10 项通过，0 项失败，输出 `CARDS_RAW_MINIMAL_DUEL_SMOKE_OK`。
  - 当前最小样例对局脚本已直接消费正式 `cards_raw.json` 卡定义，覆盖 `ON_ENTER`、`ON_LEAVE`、`MAIN_ACTIVATE`、`ON_PLAY`、`ON_LIFE_TRIGGER` 五类效果入口，并补齐 `DRAW_2`、手牌中自减 AP、离场回手、多步骤复杂费用结算，以及“看牌堆顶后检索/回底”“不同卡名去重选择”两组正式 raw 样例。
- 已尝试执行 `docs/draw_phase_smoke_test.gd`
  - 结果：Godot headless 进程崩溃，未获得可用业务验证结论。
- 已执行 Godot headless 启动检查：`D:\CodexWork\TcgDemo\Godot\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\CodexWork\TcgDemo --quit`
  - 结果：成功启动并正常退出，未新增战场布局与手牌纯缩略图相关脚本解析错误。
- 已执行 `battle_scene --layout-probe` GUI 布局专项验收
  - 结果：在 1920x1080、1600x900、1366x768、1280x720 四组常见窗口尺寸下通过；三列战场区域宽度有效，玩家战场可视底边未压入手牌缩略图区，手牌容器保持纯缩略图结构。

## 6. 建议的下一步里程碑动作

- 继续扩展效果系统的原子条件、目标筛选、费用模板与多触发顺序，向完整 DSL/IR 运行时收敛。
- 以 `docs/cards_raw_minimal_duel_smoke_test.gd` 为基底，继续补齐更多正式 raw 卡样例，优先覆盖看牌堆顶后的条件追加结算、多目标并行结算、离场触发链与更复杂费用组合。
