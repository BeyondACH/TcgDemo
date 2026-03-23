# 当前项目里程碑盘点

更新时间：2026-03-23

## 1. 盘点依据

- 协作规范：`AGENTS.md`
- 权威规则：`docs/rules/rule.md`
- 正式计划：`docs/plan/project_development_plan.md`
- 核心实现：`core/`、`data/`、`ui/`
- 验证脚本：`docs/milestone_smoke_test.gd`、`docs/deck_import_smoke_test.gd`、`docs/draw_phase_smoke_test.gd`

本文件用于描述“当前仓库已经实现到哪里”，不是未来规划替代品。若与规则语义冲突，仍以 `docs/rules/rule.md` 为准。

## 2. 当前总体结论

当前仓库已经不是只具备最小开局能力的空壳原型，而是已经完成了一个可运行的规则闭环，并继续向关键词、触发、叠放和显式决策推进。

当前状态可概括为：

- 已完成基础对局闭环：开局、抽牌、AP 成长、阶段推进、出牌、移动、攻击/阻挡、伤害、胜负判定、基础 UI 快照展示。
- 已完成一批高价值规则能力：生命触发显式决策、`MAIN_ACTIVATE`、`STEP`、`SNIPER`、`DAMAGE_2`、`IMPACT`、`NEGATE_IMPACT`、`DOUBLE_ATTACK`、`DOUBLE_BLOCK`、`RAID` 显式落点选择与叠放。
- 已具备数据与工具能力：`cards_raw.json`/`base_cards.json` 双源加载、txt 卡组导入、导入冒烟脚本。
- 仍有若干里程碑未闭环：手牌上限仍是自动移除而不是显式弃牌决策，`effect_queue` 已建模但尚未形成完整消费链路。

## 3. 里程碑状态

## 里程碑 M1：基础对局闭环

状态：已实现

已确认能力：

- 双方使用 50 张主卡组初始化，起手 7 张，生命区 7 张。
- 常量约束已经落到代码：前线上限 4、能量线上限 4、AP 上限 3、手牌上限 8。
- 回合管理已经具备 `DRAW -> MOVE -> MAIN -> ATTACK -> END` 流程，并在回合切换时重置行动方与 AP。
- 先手首回合跳过自动抽牌，且支持支付 1 AP 进行额外抽 1。
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
- `GameState` 已预留 `effect_queue`、`delayed_effects`、`static_modifiers`、`battle_context`、`pending_decisions`。

尚未闭环部分：

- `effect_queue` 当前已有入队结构，但未见统一消费执行流程，仍属于预留能力。
- 更复杂的条件、费用、目标选择与多触发顺序仍未完全扩展到计划书目标范围。

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
- UI 已接入阻挡选择、`No Block`、额外抽牌、角色前移、`MAIN_ACTIVATE`、`STEP`、`SNIPER` 指定攻击。
- UI 已接入生命触发选择器与待决策面板，可消费 `pending_life_triggers` 和 `pending_decisions`。
- UI 已具备一定的响应式布局调整逻辑。

对应实现位置：

- `ui/battle_scene.gd`
- `ui/board_view.gd`
- `ui/hand_view.gd`
- `ui/card_view.gd`
- `ui/log_panel.gd`
- `scenes/battle_scene.tscn`

备注：

- 仓库历史记录表明曾多次调整“手牌区域不得遮挡战场区域”，但本次任务未做 UI 改动，因此没有重新做目视验证，只能继承现有实现状态，不新增确认结论。

## 4. 当前已知差距与风险

- 手牌上限处理仍是超限后直接移入 `REMOVED`，尚未实现计划书中提到的“显式弃牌决策流”。
- `effect_queue` 仍偏预留结构，效果系统尚未达到完整的可扩展框架终态。
- `docs/draw_phase_smoke_test.gd` 在本地环境下执行仍出现过 Godot headless 进程崩溃，当前不适合作为稳定验证依据。
- `docs/milestone_smoke_test.gd` 已修正到与当前实现一致，但脚本退出时仍有 Godot 资源未清理警告，暂未影响断言结果。

## 5. 本次验证结果

- 已执行 `docs/milestone_smoke_test.gd`
  - 结果：18 项通过，0 项失败。
  - 当前总冒烟脚本已与现实现状、阶段流转和临时测试卡样本同步。
- 已执行 `docs/deck_import_smoke_test.gd`
  - 结果：通过。
- 已尝试执行 `docs/draw_phase_smoke_test.gd`
  - 结果：Godot headless 进程崩溃，未获得可用业务验证结论。

## 6. 建议的下一步里程碑动作

- 按计划书补齐结束阶段超手牌的显式弃牌决策，而不是直接移除。
- 继续推进效果系统的完整队列消费、条件/目标/费用扩展。
- 在不改规则语义的前提下，补一轮围绕 `cards_raw.json` 的最小样例对局脚本，降低测试与正式数据脱节的风险。
