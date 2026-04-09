# 当前项目里程碑盘点

更新时间：2026-04-09

## 1. 盘点依据

- 协作规范：`AGENTS.md`
- 权威规则：`docs/rules/rule.md`
- 正式计划：`docs/plan/development_plan.md`
- 核心实现：`core/`、`data/`、`ui/`
- 验证脚本：`docs/milestone_smoke_test.gd`、`docs/cards_raw_minimal_duel_smoke_test.gd`、`docs/draw_phase_smoke_test.gd`、`docs/deck_import_smoke_test.gd`、`docs/simple_ai_v2_smoke_test.gd`、`docs/vs_ai_smoke_test.gd`
- UI 布局验收入口：`res://scenes/battle_scene.tscn` 在命令行参数 `--layout-probe` 下执行自检

本文件用于描述“仓库目前已经实现到了哪里”。若与规则语义冲突，仍以 `docs/rules/rule.md` 为准。

## 2. 当前总体结论

## 2.1 2026-04-02 长链验证补充

- 当前验证资产已从“规则主冒烟 + 正式 raw 样例 + residue 专项 + AI 短链 smoke”收口为四层职责分工：
  - `docs/milestone_smoke_test.gd`：规则主语义与高风险规则断言
  - `docs/cards_raw_minimal_duel_smoke_test.gd`：只承担官方 raw 模板链路验证
  - `docs/runtime_residue_smoke_test.gd`：所有链路收尾无残留校验
  - `docs/long_run_stability_smoke_test.gd`：连续回合、延迟效果、离场链、生命触发二选一与 AI 长局稳定性
- 2026-04-02 已新增 `docs/long_run_stability_smoke_test.gd`，当前结果为 `5 / 0`；既有 `docs/runtime_residue_smoke_test.gd = 9 / 0`、`docs/vs_ai_smoke_test.gd = 4 / 0` 仍保持通过。
- 从本轮开始，“更长链路而不是更多零散样例”成为验证资产的第一优先级，前文中仍偏“继续扩样例”的旧口径均以本段为准。

## 2.2 2026-04-08 Phase E 基线修复补充

- 已修复 Phase E 启动前暴露的基线编译回归：`core/effects/requirement_matcher.gd` 补回 `PlayerState` 预加载后，`docs/milestone_smoke_test.gd` 恢复为 `33 / 0`。
- AI 自动推进链本轮补齐两项关键稳定性：
  - AI 在生命翻牌 reveal 窗口会自动确认，不再残留 `pending_life_reveal`
  - 多目标 `ABILITY_TARGET_SELECTION` 已按统一 `choices` 口径提交，不再把待决策队列卡死
- 长链冻结基线已更新为：
  - `docs/runtime_residue_smoke_test.gd`：10 项通过、0 项失败
  - `docs/long_run_stability_smoke_test.gd`：6 项通过、0 项失败
  - `docs/vs_ai_smoke_test.gd`：5 项通过、0 项失败

当前仓库已经完成从”可开局原型”到”可持续迭代的规则原型”的第一轮收口，项目状态可以概括为：

- 基础对局闭环已实现，核心区域、阶段流转、资源支付、战斗与胜负判断具备稳定主路径。
- 高风险规则区已补齐一轮专项回归，规则主链路已不再依赖临时说明文档来补语义。
- 统一 DSL/IR 已完成对当前正式 raw 卡池的首轮收口；截至 2026-04-02，正式 `cards_raw` 口径结果为 `180` 个已支持能力、`0` 个未支持能力。若按编译器终端的运行时总量口径统计，则显示为 `183 / 0`，其中额外 `3` 个已支持能力来自 base sample。
- 正式 raw 样例验证已形成独立基线，当前重点已从”补能力缺口“转为”维持规则稳定性 + 收敛新增正式卡导入后暴露的未支持能力”。
- `SimpleAI` 已从静态优先级选择器升级为轻量评分式 `v2`，AI 对局基线已形成”行为专项 smoke + 整体流程 smoke“的双层验证。
- UI 已完成战场区、堆叠区、预览区、待决策交互和底部手牌区的第一轮收口，能支撑规则验证与日常调试。
- AI 对局已补齐动作节拍推进与顶部轻量提示位，支持按步观察 AI 抽牌、出牌、攻击、阻挡与待决策处理。
- UI 美术风格规范文档已冻结，下一阶段可以从”可用型界面“切换到”正式视觉落地“。
- **架构重构已完成**：GameManager 从”上帝对象“（1467 行，10+ 职责）重构为协调器模式（1060 行），提取 7 个专用管理器，遵循 SOLID 单一职责原则。
- `compile_cards_effects.py` 的后续识别层重构方向已补充约束：对 `UA31BT_MMM_1_007` 一类同族文本，完成标准必须是参数化模板族复用，而不是仅把逐句匹配迁移到模板注册表。
- 2026-04-02 已完成首轮 registry 化落地，并将正式 raw 基线收口到 `180 / 0`、运行时总量 `183 / 0`。
- 已补中文文档防污染流程，并新增 `tools/check_utf8_docs.py` 轻量检查工具。

## 2.3 2026-04-09 图片抓取脚本商品名列表补充

- `download_mmm_images.py` 已支持从日文官网 `jp/cardlist/index.php?search=true` 的 `series` 下拉框枚举商品名和对应编号。
- 新增 `--list-products` 只读列表入口，输出格式固定为 `Official products:` + `- <name> [<id>]`，不影响现有 `--product` 手填筛选流程。
- 为避免旧逻辑回归，脚本保留了作品列表 HTML 解析辅助函数的回归测试，但不重新引入 `--list-works` CLI 入口。

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
- `life_trigger_only` 仅表示该卡在生命触发时会出现“加手 / 立即 RAID”二选一，不会取消该卡在主阶段满足条件时的手牌 `RAID` 能力；若在生命翻牌弹窗中点击 `Activate` 后发现当前仍不满足立即 `RAID` 条件，现会直接按既有兜底加入手牌并完成生命伤害收尾，不再额外停留在仅剩禁用 `RAID_NOW` 的待决策态。

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
- 正式 raw 编译结果当前为 `180` 个已支持能力、`0` 个未支持能力；编译器终端的运行时总量口径为 `183 / 0`。
- 已覆盖高阶模板：临时产能修饰、延迟自退场、绑定自身的临时特殊登场 / `RAID` 许可、动态 BP 阈值、条件化阈值替换、公开结果奖励与 fallback 主链/后备链。

当前剩余重点：

- 继续围绕 `docs/milestone_smoke_test.gd` 观察共性生命周期语义，重点确认 `UNTIL_NEXT_SELF_TURN_START` 只在来源方下个回合开始失效、多个 `ON_END_MAIN_PHASE` / `END_OF_TURN` 延迟效果不会残留 `pending_decisions`、`effect_queue` 或 `battle_context` 脏状态。
- 继续围绕 `docs/cards_raw_minimal_duel_smoke_test.gd` 观察正式 raw 组合链路，重点确认跨完整回合的临时特殊登场许可过期、`ON_LEAVE` 回手链与战斗/阶段推进衔接稳定，以及叠放离场后的区域与标记一致性。
- 保持统一 IR 口径稳定，后续新增正式卡文或模板时继续坚持“先扩可复用 requirement / step，再接入数据与回归”的原则，避免回退到按卡硬编码。
- 若重构编译识别层，还需继续坚持“同类文本优先参数化模板化，而不是新增逐句模板”。

## 里程碑 M5：数据、导入与验证资产

状态：基础能力已实现，验证资产持续扩充中

已确认能力：

- 游戏启动优先聚合加载 `data/cards/*/cards_effects.json`，并兼容补充 `data/cards/base_cards.json`。
- 双方起始卡组已切换到 txt 入口：`data/decks/starter_a.txt`、`data/decks/starter_b.txt`。
- txt 卡组行格式支持 `数量 x 卡号`。
- 导入工具已支持缺卡统计、非法行校验、输出 deck json。
- `tools/import_cards_raw_from_pic.ps1` 已补齐抓取失败分类；当前确认 `UA31BT/MMM-1-001` 在沙箱外可正常访问并通过现有 `cardNumData` 解析，之前批量 `official_page_not_found` 的主因是沙箱内网络失败误归类；本轮已在沙箱外成功补录 `UA31BT/MMM-1-001` 到 `034`。
- `tools/generate_micro_card_images.ps1` 已作为补录后的配套缩略图脚本纳入正式流程；导入成功后应顺带补齐 `pic/micro/` 中缺失的 micro 缩略图。
- 当前验证入口已形成分工：
  - `docs/milestone_smoke_test.gd`：规则主冒烟
  - `docs/cards_raw_minimal_duel_smoke_test.gd`：正式 raw 样例回归
  - `docs/draw_phase_smoke_test.gd`：DRAW 阶段专项
  - `docs/deck_import_smoke_test.gd`：导入链路专项
  - `docs/runtime_residue_smoke_test.gd`：运行时 residue / cleanup 专项
  - `docs/long_run_stability_smoke_test.gd`：连续回合与 AI 长链稳定性专项
  - `docs/simple_ai_v2_smoke_test.gd`：AI 评分行为专项
  - `docs/vs_ai_smoke_test.gd`：AI 控制器整体流程 smoke

当前验证基线：

- `docs/milestone_smoke_test.gd`：33 项通过、0 项失败
- `docs/cards_raw_minimal_duel_smoke_test.gd`：80 项通过、0 项失败
- `docs/runtime_residue_smoke_test.gd`：10 项通过、0 项失败
- `docs/long_run_stability_smoke_test.gd`：6 项通过、0 项失败
- `docs/life_reveal_modal_smoke_test.gd`：7 项通过、0 项失败
- `docs/simple_ai_v2_smoke_test.gd`：6 项通过、0 项失败
- `docs/vs_ai_smoke_test.gd`：5 项通过、0 项失败

## 里程碑 M5.5：AI 对局启发式与自动推进基线

状态：已完成第一轮收口

已确认能力：

- `SimpleAI` 已保留原有选择接口与阶段入口方法名，并在内部改为评分式选择逻辑。
- `MOVE / MAIN / ATTACK / BLOCK / STEP_SWAP_CHOICE / HAND_LIMIT_DISCARD` 已不再只靠静态优先级，而是会综合前线压力、能量曲线、直攻价值、斩杀线、`NO_BLOCK` 比较与低价值弃换牌判断。
- `BLOCK` 已把 `NO_BLOCK` 纳入同池比较，不再默认选择最高 BP 阻挡。
- `ATTACK` 已固定“直攻优先于无意义解场”与“明显斩杀优先”两类基础节奏。
- AI 行为验证已与规则主冒烟分层，避免把策略选择测试混入规则语义主入口。

当前限制：

- 当前评分仍主要依赖 `snapshot`、`available_actions` 与已有 `action.params` 做近似判断。
- `EVENT`、`ACTIVATE_EFFECT`、关键阻挡位与预估伤害仍缺少显式标签或估值字段，后续若要继续提质，建议补 `estimated_player_damage`、`event_tags`、`effect_tags`、`is_key_blocker` 等参数。

## 里程碑 M6：UI、交互与快照消费

状态：已完成第一轮收口

已确认能力：

- 主战斗场景已接入回合、行动方、阶段、胜者、日志、手牌、前线、能量线展示。
- 战场已形成左列生命/除外、中列前线/能量线、右列卡组/场外的三列布局。
- UI 已接入阻挡选择、`No Block`、额外抽牌、角色前移、`MAIN_ACTIVATE`、`STEP`、`SNIPER` 指定攻击。
- UI 已接入生命触发选择器、待决策面板、独立卡牌预览面板和堆叠区域弹窗查看。
- Top HUD 已接入 AI 动作提示位，运行时会按节拍展示 AI 的最近一步动作。
- 底部手牌区已收敛为纯缩略图展示与独立预览方案，减少对战场遮挡。
- 相关布局改动已通过 `--layout-probe` 验收，当前记录显示手牌区域未遮挡战场区域。
- 生命翻开快照序列化已与重构后的 `LifeTriggerManager` 接口重新对齐，生命翻开期间调用 `get_snapshot()` 不再因旧私有方法缺失而报错。

对应实现位置：

- `ui/battle_scene.gd`
- `ui/board_view.gd`
- `ui/hand_view.gd`
- `ui/card_view.gd`
- `ui/card_preview_panel.gd`
- `ui/zone_cards_popup.gd`
- `ui/zone_stack_summary_view.gd`
- `scenes/battle_scene.tscn`

## 里程碑 M6.5：UI 美术规范冻结

状态：已实现，暂缓落地

已确认能力：

- `docs/plan/ui_art_style_guide.md` 已作为正式视觉规范文档创建完成。
- 当前视觉方向已锁定为“红色竞技桌垫感 + 轻量数字界面感”，不再继续在抽象风格层面反复摇摆。
- 七个核心区域、槽位轮廓、标题承托、卡牌展示、面板、按钮、标签、Tooltip、字体、间距、圆角、阴影与动效基线均已形成统一书面规范。
- 后续 UI 改动可以直接以该文档为依据推进，不需要再次从零定义视觉语言。

当前未完成项：

- 规范已冻结，但尚未完整落地到 `battle_scene`、`board_view`、`hand_view`、`card_view` 和预览面板的实际实现中。
- 视觉资源、主题常量与局部样式仍有分散现象，尚未完成第一轮统一收口。

当前决策：

- 当前阶段暂不进行 UI 视觉落地；仅允许为 AI 调试可见性做最小提示位补强。
- `docs/plan/ui_art_style_guide.md` 作为后续阶段的冻结基线保留，但不作为当前迭代主线。

## 里程碑 M7：架构重构与 SOLID 合规

状态：已完成

已确认能力：

- GameManager 从"上帝对象"（1467 行，10+ 职责）重构为协调器模式（1060 行，单一职责）。
- 提取 7 个专用管理器：
  - `PlayerUtils` - 共享助手 (`opponent_of`)
  - `GameGateChecker` - 状态门检查
  - `DeckLoader` - 卡组/卡牌加载
  - `SnapshotSerializer` - UI 序列化
  - `DecisionManager` - 决策队列管理
  - `LifeTriggerManager` - 生命触发/揭示
  - `ControllerManager` - 控制器管理
- 移除代码重复：
  - `_opponent_of()` - 6 处重复合并为 1 处共享
  - `_energy_pool_for_player()` - 80 行重复代码删除
  - `_available_actions_for_card()` - 50 行重复代码删除

架构改进：

- GameManager 成为纯粹的协调器，委托职责给专用管理器
- 遵循 SOLID 单一职责原则 (SRP)
- 遵循 DRY 原则，消除重复逻辑
- 保持向后兼容的公共 API

验证结果：

- `docs/milestone_smoke_test.gd`：33 项通过、0 项失败
- 所有规则语义保持不变
- API 兼容性验证通过

对应实现位置：

- `core/game_manager.gd` - 协调器
- `core/player_utils.gd` - 共享助手
- `core/game_gate_checker.gd` - 门检查
- `core/deck_loader.gd` - 加载器
- `core/ui/snapshot_serializer.gd` - 序列化器
- `core/decision_manager.gd` - 决策管理
- `core/life_trigger_manager.gd` - 生命触发管理
- `core/controllers/controller_manager.gd` - 控制器管理

## 4. 当前主线与风险

当前主线：

- 保持 `docs/milestone_smoke_test.gd`、`docs/cards_raw_minimal_duel_smoke_test.gd`、`docs/runtime_residue_smoke_test.gd` 与 `docs/long_run_stability_smoke_test.gd` 四条规则长链入口稳定通过。
- 暂不推进 UI 视觉落地，当前主线改为继续压实连续回合生命周期、离场触发链、更长链路自动验证，以及 AI 对局可观察性。
- 保持 `docs/simple_ai_v2_smoke_test.gd` 与 `docs/vs_ai_smoke_test.gd` 的 AI 验证分层，逐步压实 AI 节奏判断而不污染规则主冒烟。
- 保持规则、计划与日志描述一致，避免再次出现文档口径滞后。

当前主要风险：

- 当前正式 raw 已全部进入统一 IR 主链路，但完整卡池级别回归仍未建立，样例脚本不能替代更大规模回归。
- Godot 退出时仍保留既有 `ObjectDB` / resource 泄漏告警，虽未影响本轮 `33 / 0`、`80 / 0`、`10 / 0`、`6 / 0`、`5 / 0` 断言基线，但仍需持续观察。
- `SimpleAI v2` 目前仍是轻量启发式，`EVENT / ACTIVATE_EFFECT / 关键阻挡位` 的判断更多依赖近似策略，后续若继续增强 AI，需要在不破坏接口冻结的前提下补充更明确的动作上下文字段。
- 当前验证入口仍偏专项与最小样例，若迟迟不补更长链路自动验证，后续新增改动仍可能在完整流程上暴露迟发问题。

## 5. 下一阶段建议

1. 下一阶段继续聚焦规则稳定性与验证资产，在已修复基线编译回归和 AI 长链待决策回归后，继续观察连续回合生命周期、延迟效果过期、离场触发链与完整流程推进是否保持稳定。
2. 既有正式 raw 未支持能力已经收口到 `180 / 0`，后续重点改为维持 `registry -> legacy fallback` 编译链稳定，并只接受参数化模板族扩展，不回退到按卡或逐句匹配硬编码。
3. 把 `docs/milestone_smoke_test.gd`、`docs/cards_raw_minimal_duel_smoke_test.gd`、`docs/runtime_residue_smoke_test.gd`、`docs/long_run_stability_smoke_test.gd`、`docs/life_reveal_modal_smoke_test.gd` 与 `docs/vs_ai_smoke_test.gd` 作为当前冻结基线；若新增验证暴露回退，优先修正规则实现与断言基线。
4. 暂不进行 UI 视觉重构；`docs/plan/ui_art_style_guide.md` 保留为后续阶段的视觉冻结文档，当前仅保留 AI 动作提示与生命翻牌可见性相关的最小 UI 补强。
5. 若继续提升 AI 质量，优先补动作上下文参数、长链 AI 对局 smoke 与日志可观察性，而不是直接扩大 UI 或搜索式策略改造。
6. 待规则稳定性与长链路验证进一步压实后，再单独评估 UI 视觉落地的启动时机。
