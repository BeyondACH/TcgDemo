# 当前项目里程碑盘点

更新时间：2026-03-27

## 1. 盘点依据

- 协作规范：`AGENTS.md`
- 权威规则：`docs/rules/rule.md`
- 正式计划：`docs/plan/project_development_plan.md`
- 核心实现：`core/`、`data/`、`ui/`
- 验证脚本：`docs/milestone_smoke_test.gd`、`docs/cards_raw_minimal_duel_smoke_test.gd`、`docs/draw_phase_smoke_test.gd`、`docs/deck_import_smoke_test.gd`
- UI 布局验收入口：`res://scenes/battle_scene.tscn` 在命令行参数 `--layout-probe` 下执行自检

本文件用于描述“仓库目前已经实现到了哪里”。若与规则语义冲突，仍以 `docs/rules/rule.md` 为准。

## 2. 当前总体结论

当前仓库已经完成从“可开局原型”到“可持续迭代的规则原型”的第一轮收口，项目状态可以概括为：

- 基础对局闭环已实现，核心区域、阶段流转、资源支付、战斗与胜负判断具备稳定主路径。
- 高风险规则区已补齐一轮专项回归，规则主链路已不再依赖临时说明文档来补语义。
- 统一 DSL/IR 已收口到 `73` 个已支持能力、`0` 个未支持能力，当前运行时已具备继续吸收正式 raw 卡模板的基础。
- 正式 raw 样例验证已形成独立基线，当前重点从“补能力缺口”转向“继续扩覆盖面与稳定性”。
- UI 已完成战场区、堆叠区、预览区、待决策交互和底部手牌区的第一轮收口，能支撑规则验证与日常调试。

## 3. 里程碑状态

## 里程碑 M1：基础对局闭环

状态：已实现

已确认能力：

- 双方使用 50 张主卡组初始化，起手 7 张，生命区 7 张。
- 回合阶段已形成 `DRAW -> MOVE -> MAIN -> ATTACK -> END` 主流程。
- 先手首回合跳过自动抽牌，且支持支付 1 AP 额外抽 1。
- 前线、能量线、AP、场外、除外、生命区等核心区域均已接入。
- 场地牌只能进入能量线，事件牌结算后进入场外。
- 结束阶段超手牌已改为显式弃牌待决策，而不是直接硬编码丢弃。
- 胜负判定已覆盖生命归零与起始阶段抽牌失败导致的败北。

对应实现位置：

- `core/game_manager.gd`
- `core/turn_manager.gd`
- `core/rules_engine.gd`
- `core/zone_manager.gd`
- `core/victory_checker.gd`
- `data/game_state.gd`
- `data/player_state.gd`

## 里程碑 M2：战斗与高风险规则区

状态：已实现主链路，专项回归已补齐第一轮

已确认能力：

- 只有前线 `ACTIVE` 角色可以攻击或阻挡。
- 玩家直伤与指定前线角色攻击都已具备。
- 普通攻击支持阻挡，`SNIPER` 攻击不可被阻挡。
- `DAMAGE_2`、`IMPACT`、`IMPACT_PLUS_1`、`NEGATE_IMPACT` 已纳入战斗伤害逻辑。
- `DOUBLE_ATTACK`、`DOUBLE_BLOCK` 已支持第一次后恢复 `ACTIVE`、第二次后正常消耗。
- 已固定验证“攻击失败的攻击方不会退场”。
- 已固定验证“生命触发必须显式选择是否发动”。
- 已固定验证“同时触发顺序”与“AP 在结束阶段不恢复”。

对应验证：

- `docs/milestone_smoke_test.gd`
- `docs/draw_phase_smoke_test.gd`

## 里程碑 M3：关键词、叠放与特殊登场

状态：已实现主链路

已确认能力：

- `STEP` 已支持从前线退回能量线，并在满位时进入交换决策。
- `RAID` 已支持特殊登场合法性校验、目标合法性校验和显式落点选择。
- `RAID` 目标在能量线时，玩家可决定叠放后留在能量线或转到前线。
- `RAID` 已记录 `stacked_under`，离场时下层卡会被一并释放到场外。
- `RAID_INNER` 效果门控已接入，只在通过 `RAID` 登场时启用。
- `life_trigger_only` 手牌 `RAID` 已收敛为“默认不允许，需生命触发或临时许可放行”。

对应实现位置：

- `core/rules_engine.gd`
- `core/zone_manager.gd`
- `core/game_manager.gd`
- `core/effect_resolver.gd`

## 里程碑 M4：效果系统与 DSL/IR 收口

状态：已完成首轮收口，进入持续维护

已确认能力：

- `effect_queue`、`pending_decisions`、`pending_life_triggers`、`battle_context`、`delayed_effects`、`static_modifiers` 已接入运行时。
- `resolve_effect`、`resolve_trigger`、`MAIN_ACTIVATE` 与手动目标续执行已统一接入队列消费链。
- `trigger_effects` 已支持 `ON_ENTER`、`ON_LEAVE`、`ON_ATTACK`、`ON_BLOCK`、`ON_LIFE_TRIGGER`、`MAIN_ACTIVATE`、`ON_BATTLE_WIN`、`ON_BATTLE_LOSE`、`ON_BATTLE_END`。
- 已支持显式目标、基础费用、步骤式结算、静态修正、延迟效果与出牌前修饰消费。
- 正式 raw 编译结果已达到 `73` 个已支持能力、`0` 个未支持能力。
- 已覆盖高阶模板：临时产能修饰、延迟自退场、绑定自身的临时特殊登场 / `RAID` 许可、动态 BP 阈值、条件化阈值替换、公开结果奖励与 fallback 主链/后备链。

当前剩余重点：

- 继续补更复杂的正式 raw 组合样例。
- 继续观察连续回合生命周期与离场触发链的长期稳定性。

## 里程碑 M5：数据、导入与验证资产

状态：基础能力已实现，验证资产持续扩充中

已确认能力：

- 游戏启动优先加载 `data/cards/cards_raw.json`，并兼容补充 `data/cards/base_cards.json`。
- 双方起始卡组已切换到 txt 入口：`data/decks/starter_a.txt`、`data/decks/starter_b.txt`。
- txt 卡组行格式支持 `数量 x 卡号`。
- 导入工具已支持缺卡统计、非法行校验、输出 deck json。
- 当前验证入口已形成分工：
  - `docs/milestone_smoke_test.gd`：规则主冒烟
  - `docs/cards_raw_minimal_duel_smoke_test.gd`：正式 raw 样例回归
  - `docs/draw_phase_smoke_test.gd`：DRAW 阶段专项
  - `docs/deck_import_smoke_test.gd`：导入链路专项

当前验证基线：

- `docs/milestone_smoke_test.gd`：27 项通过、0 项失败
- `docs/cards_raw_minimal_duel_smoke_test.gd`：31 项通过、0 项失败

## 里程碑 M6：UI、交互与快照消费

状态：已完成第一轮收口

已确认能力：

- 主战斗场景已接入回合、行动方、阶段、胜者、日志、手牌、前线、能量线展示。
- 战场已形成左列生命/除外、中列前线/能量线、右列卡组/场外的三列布局。
- UI 已接入阻挡选择、`No Block`、额外抽牌、角色前移、`MAIN_ACTIVATE`、`STEP`、`SNIPER` 指定攻击。
- UI 已接入生命触发选择器、待决策面板、独立卡牌预览面板和堆叠区域弹窗查看。
- 底部手牌区已收敛为纯缩略图展示与独立预览方案，减少对战场遮挡。
- 相关布局改动已通过 `--layout-probe` 验收，当前记录显示手牌区域未遮挡战场区域。

对应实现位置：

- `ui/battle_scene.gd`
- `ui/board_view.gd`
- `ui/hand_view.gd`
- `ui/card_view.gd`
- `ui/card_preview_panel.gd`
- `ui/zone_cards_popup.gd`
- `ui/zone_stack_summary_view.gd`
- `scenes/battle_scene.tscn`

## 4. 当前主线与风险

当前主线：

- 继续扩 `docs/cards_raw_minimal_duel_smoke_test.gd` 的正式 raw 模板覆盖面。
- 保持 `docs/milestone_smoke_test.gd` 的规则主冒烟职责不漂移。
- 保持规则、计划、README 与日志描述一致，避免再次出现文档口径滞后。

当前主要风险：

- 正式 raw 样例覆盖仍偏最小样例，尚不能替代完整卡池回归。
- Godot 退出时仍保留既有 `ObjectDB` / resource 泄漏告警，虽未影响断言结果，但仍需持续观察。
- 若后续快照结构或待决策流继续扩展，`ui/` 与 `core/` 的接口冻结需要更严格执行，避免并行接入时漂移。

## 5. 下一阶段建议

1. 继续补正式 raw 样例，优先覆盖更复杂的预览链、多段条件追加结算、连续回合生命周期与离场触发链。
2. 若新增需求触及高风险规则区，先补规则主冒烟，再扩 raw 样例，不要反过来用样例脚本替代规则验证。
3. 若后续改动触及 UI 预览流、待决策流或布局消费，执行 `battle_scene --layout-probe` 并把结果同步写入当日日志。
