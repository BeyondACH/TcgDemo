# TcgDemo 项目开发计划

更新时间：2026-04-02

## 1. 计划摘要

当前仓库已经完成基础对局闭环、主要高风险规则区、统一效果队列主链路、正式系列 `cards_raw.json` 样例回归，以及 UI 美术规范文档的首轮冻结。项目现阶段不再以“继续快速铺能力面”为首要目标，而是转向以下主线：

1. 保持 `docs/rules/rule.md` 与实际实现持续一致。
2. 以统一 DSL/IR 为唯一正式运行时来源，禁止回退到按卡硬编码。
3. 继续补强正式 raw 样例、规则专项回归和布局/交互验收，降低后续新增卡牌或新模板时的回归风险。
4. 在暂不调整 UI 的前提下，继续压实规则稳定性、回归覆盖与调试可见性。
5. 对 `tools/compile_cards_effects.py` 的后续识别层重构，默认以“同类文本参数化复用同一模板族”为约束，不接受仅把逐句匹配搬入注册表的半重构状态。
5. 对 `tools/compile_cards_effects.py` 的后续识别层重构，默认以“同类文本参数化复用同一模板族”为约束，不接受仅把逐句匹配搬入注册表的半重构状态。

涉及 `core + data + ui` 的联动需求，必须先冻结接口和数据契约，再按 `core`、`docs/tests`、`ui` 三线拆分实施。

## 2. 当前基线

截至 2026-04-01，当前仓库基线如下：
- 基础规则闭环已具备：开局、抽牌、AP 成长、阶段推进、出牌、移动、攻击/阻挡、伤害、胜负判定、显式弃牌与生命触发决策均已落地。
- 高风险规则区已覆盖：攻击失败攻击方不退场、AP 在结束阶段不恢复、生命触发可选发动、生命触发 `RAID` 在当前不满足条件时自动回手、同时触发顺序按规则处理。
- 关键词与特殊登场已覆盖一批核心能力：`STEP`、`SNIPER`、`DAMAGE_2`、`IMPACT`、`IMPACT_PLUS_1`、`NEGATE_IMPACT`、`DOUBLE_ATTACK`、`DOUBLE_BLOCK`、`RAID`。
- 效果系统已统一接入 `effect_queue` 执行链，并接入显式决策、目标续执行、延迟效果与静态修正。
- 正式 `cards_raw` 当前基线为 `174` 个已支持能力、`6` 个未支持能力；若按编译器终端的运行时总量口径统计，则显示为 `177 / 6`，其中额外 `3` 个已支持能力来自 base sample。本轮已完成 `P0` 模板范围，当前仅剩 `P1` 缺口继续维护。
- **架构重构已完成**：GameManager 从”上帝对象“（1467 行）重构为协调器模式（1060 行），提取 7 个专用管理器，移除 130 行重复代码，遵循 SOLID 单一职责原则。
- 验证资产当前基线：
  - `docs/milestone_smoke_test.gd`：33 项通过、0 项失败
  - `docs/cards_raw_minimal_duel_smoke_test.gd`：75 项通过、0 项失败
  - `docs/draw_phase_smoke_test.gd`：当前环境稳定通过，可作为 DRAW 阶段专项回归入口
  - `docs/runtime_residue_smoke_test.gd`：7 项通过、0 项失败
- 当前主要风险已从”能力缺口”转为两类稳定性问题：一是规则运行时的跨回合 residue / 生命周期稳定性仍需持续压实；二是完整卡池级别回归与更长链路自动验证仍未建立。
- 2026-03-31 已补一处快照兼容性 bugfix：`SnapshotSerializer` 不再依赖 `GameManager` 已移除的生命翻开私有方法，生命翻开期间的 `get_snapshot()` 恢复稳定，可继续作为 UI 与冒烟脚本的正式读取入口。
- 2026-04-01 已确认 `tools/import_cards_raw_from_pic.ps1` 之前将沙箱内网络失败误归类为 `official_page_not_found`；当前脚本已补齐失败原因分类，能够区分 `network_error`、`request_failed`、`detail_structure_missing` 与 `card_number_mismatch`，并已验证 `UA31BT/MMM-1-001` 在沙箱外可正常解析，导入链路默认应在沙箱外执行。
- 2026-04-02 已完成编译器识别层首轮注册表化，主入口改为 `registry -> legacy fallback`，编译结果保持正式 raw `174 / 6`、运行时总量 `177 / 6` 不变。

## 3. 开发阶段规划

## 阶段 A：规则与 DSL/IR 基线维护

状态：持续进行

目标：

- 保持 `docs/rules/rule.md`、运行时规则实现、测试脚本三者一致。
- 保持“要求/步骤”边界清晰，不让原始卡文或按卡特判进入运行时。
- 新增能力时，优先扩原子要求、原子步骤、原子目标或原子费用模板。
- 若后续重构 `compile_cards_effects.py` 识别层，必须把同类文本收口为参数化模板族；仅把 `if text == ...` 迁移到注册表，不视为完成。

本阶段约束：

- 禁止为单卡补专用解释逻辑。
- 禁止把特殊登场规则混入普通步骤执行。
- 若某类正式卡文无法表达，应先扩 DSL/IR，再接入数据与回归。

完成判据：

- 新能力接入时同步更新编译链、运行时和至少一条对应回归。
- `docs/plan/todo.md` 中如新增缺口项，必须同步收敛到可复用模板，而不是形成临时字段。

## 阶段 B：规则专项回归加固

状态：当前主线

目标：

- 保持 `docs/milestone_smoke_test.gd` 作为规则主冒烟入口。
- 继续围绕高风险规则区补专项断言，优先覆盖：
  - 攻击/阻挡与战斗结算
  - 生命触发与同时触发顺序
  - 区域容量与落点合法性
  - AP 与能量支付
  - 回合切换、阶段恢复与延迟效果过期

当前实施策略：

- 规则主语义放在 `docs/milestone_smoke_test.gd`。
- 更细粒度的不稳定点允许拆出独立专项脚本，但不应让样例测试反向承担规则主语义。
- 若发现实现与 `rule.md` 冲突，优先修正规则实现与主冒烟，再扩其他回归。

完成判据：

- 所有新增高风险规则改动至少补 1 条专项断言。
- 规则主冒烟持续保持通过，且不混入只属于正式卡编号的数据样例验证。

## 阶段 C：正式 raw 样例扩充与稳定性维护

状态：已完成首轮扩充，转入维护

目标：

- 保持正式系列 `data/cards/<series>/cards_raw.json` 持续走统一 IR 主链路，不回退到按卡特判。
- 保持 `docs/cards_raw_minimal_duel_smoke_test.gd` 作为正式 raw 样例稳定性验证入口。

当前维护重点：

- 连续回合生命周期
- 离场触发链与延迟效果叠加
- 预览链、公开信息链与多段条件追加结算的长期稳定性
- 当前已固定观察入口：规则层放在 `docs/milestone_smoke_test.gd`，正式模板组合链放在 `docs/cards_raw_minimal_duel_smoke_test.gd`。

实施要求：

- 若后续新增 raw 模板，必须同步更新 `tools/compile_cards_effects.py`、重新生成对应系列目录下的 `cards_effects.json` / `cards_semantic.json`，并补最小样例验证。
- 不允许通过对单一编号写特判来“通过样例”。
- 对 `UA31BT_MMM_1_007` 一类“预览牌库后按名称/特征加手并重排”的同族文本，后续新增正式卡时默认应复用同一模板族与同一原子步骤主链。

完成判据：

- 正式 raw 样例覆盖面持续扩展，且每次扩展都能稳定复跑。
- 样例脚本不替代规则主冒烟，只承担正式数据模板回归。
- 连续回合生命周期与离场触发链的观察项至少覆盖“跨完整回合的临时效果过期”“多源延迟效果无残留”“ON_LEAVE 回手/叠放离场后的区域一致性”三类场景。

## 阶段 D：数据、导入与调试体验补强

状态：并行维护

目标：

- 保持 `data/cards/<series>/cards_raw.json`、`data/cards/<series>/cards_effects.json`、运行时数据结构和导入工具口径一致。
- 继续完善 txt 卡组导入、错误提示、缺卡统计和调试可见性。
- 维持 `GameManager.get_snapshot()`、日志面板、预览面板与待决策 UI 对当前规则状态的可观察性。

当前关注点：

- `docs/deck_importer.gd` / `docs/import_deck.gd` 与正式数据字段保持同步。
- `tools/import_cards_raw_from_pic.ps1` 的抓取与失败诊断默认按沙箱外执行口径维护；若在沙箱内运行出现 `network_error`，不再按官网缺卡结论处理。
- UI 继续只消费快照，不反向承担规则判断。
- `tools/generate_micro_card_images.ps1` 作为导入后的配套步骤维护，新增卡图补录成功后应顺带补齐 `pic/micro/` 缩略图。
- 若改动 UI 布局或交互，必须补 layout probe 或等价布局验收记录，确认手牌区域不遮挡战场。
- 关键中文文件统一按显式 UTF-8 读取与写回。
- 文档改动后先做 UTF-8 复读、`git diff` 复核，并可补跑 `python tools/check_utf8_docs.py`。

## 阶段 E：规则稳定性与验证资产深化

状态：下一阶段主线

目标：

- 在暂不调整 `ui/` 的前提下，继续压实规则主链、正式 raw 组合链与 residue 专项回归的长期稳定性。
- 逐步补强完整卡池视角下的自动验证、阶段衔接验证和长链路对局验证，避免当前验证入口长期停留在最小样例层面。
- 保持现有调试可见性与日志可观察性，为后续真正进入 UI 阶段前先把规则底座和验证资产打稳。

本阶段范围：

- `docs/milestone_smoke_test.gd`
- `docs/cards_raw_minimal_duel_smoke_test.gd`
- `docs/runtime_residue_smoke_test.gd`
- 需要时新增的规则专项 smoke / 长链路回归脚本
- 与验证链路直接相关的 `core/`、`data/`、`tools/` 最小必要修正

本阶段约束：

- 暂不进行 UI 视觉、布局和交互层改造；`ui/` 与 `scenes/` 仅允许为验证阻塞做最小必要修正。
- 若新增验证发现 `rule.md` 冲突，优先修正规则实现与回归，不把问题转移到文档描述或样例特判。
- 新增自动验证时继续坚持“规则主冒烟 / 正式 raw 样例 / residue 专项”职责分层，不混淆入口职责。
- 若需要补调试字段，优先落在日志、脚本断言或最小必要快照字段，不为尚未开始的 UI 落地提前扩接口。

完成判据：

- `docs/milestone_smoke_test.gd`、`docs/cards_raw_minimal_duel_smoke_test.gd` 与 `docs/runtime_residue_smoke_test.gd` 持续稳定通过。
- 至少新增一类比当前最小样例更长链的自动验证，覆盖连续回合、延迟效果清理、离场链或 AI 对局流程中的一种高风险组合。
- 若本阶段触及 `core/` 或 `data/`，对应变更必须同步落日志并附验证结果。
- 文档、日志与验证基线口径保持一致。

## 4. 关键接口冻结项

以下接口视为当前阶段的冻结重点；跨层开发前必须先锁定：

- `GameState`
  - `effect_queue`
  - `battle_context`
  - `pending_decisions`
  - `pending_life_triggers`
  - `delayed_effects`
  - `static_modifiers`
- `CardInstance.flags`
  - 回合内攻击、阻挡、主动技次数等标记字段
- `EffectResolver`
  - 统一入口为”入队触发、消费队列、执行步骤、在显式决策点暂停”
- `RulesEngine`
  - 出牌合法性、特殊登场许可、区域容量和落点校验
- `GameManager`
  - 玩家决策处理入口
  - `get_snapshot()` 暴露结构
  - **已重构为协调器模式**：新增职责应提取为专用管理器，禁止回退到”上帝对象”模式
- 卡牌编译链
  - `tools/compile_cards_effects.py`
  - `data/cards/<series>/cards_effects.json`
  - 统一 IR 字段格式

## 4.1 架构原则（新增）

基于 2026-03-31 重构经验，后续开发应遵循：

- **单一职责原则 (SRP)**：每个类只有一个变更理由，职责超出 200 行时应考虑拆分
- **DRY 原则**：重复代码超过 10 行必须提取为共享方法或工具类
- **协调器模式**：GameManager 仅负责协调，不直接实现具体逻辑
- **管理器提取标准**：
  - 提取的管理器应继承 `RefCounted`
  - 通过依赖注入接收外部引用
  - 公共方法数量控制在 5-10 个
- **禁止回退**：不得将已提取的职责重新内联回 GameManager

## 5. 推荐协作拆分

规则/效果需求推荐拆分：

- Agent A：`core/` 主逻辑或 DSL/IR 运行时接入
- Agent B：`docs/` 回归脚本、最小样例、计划与验收文档
- Agent C：`ui/` 快照消费适配与布局验证

数据/导入需求推荐拆分：

- Agent A：编译链与数据结构
- Agent B：导入工具与数据校验
- Agent C：文档与冒烟脚本

默认限制：

- 不允许两个 agent 同时修改同一个 `.gd` 文件。
- 未冻结快照结构前，不允许 `core` 与 `ui` 并行修改同一接口。
- 修改规则语义与补测试必须按同一语义基线推进，不能一边改规则、一边按旧规则补测试。

## 6. 测试与验收要求

所有规则相关改动至少执行一种验证，优先覆盖：

- 攻击/阻挡结算
- 生命区触发
- 区域容量上限
- AP 与能量支付
- 回合切换与状态恢复

当前推荐验证入口：

- 规则主冒烟：`docs/milestone_smoke_test.gd`
- 正式 raw 样例：`docs/cards_raw_minimal_duel_smoke_test.gd`
- DRAW 阶段专项：`docs/draw_phase_smoke_test.gd`
- 导入链路：`docs/deck_import_smoke_test.gd`
- 手牌动作合法性：`docs/hand_available_actions_smoke_test.gd`
- 生命翻开弹窗：`docs/life_reveal_modal_smoke_test.gd`

## 7. 近期执行顺序

1. 保持 `docs/milestone_smoke_test.gd`、`docs/cards_raw_minimal_duel_smoke_test.gd` 与 `docs/runtime_residue_smoke_test.gd` 三个入口稳定通过，作为当前阶段规则冻结基线。
2. 下一阶段优先补更长链路的自动验证，重点放在连续回合生命周期、延迟效果过期、离场触发链衔接和完整对局推进稳定性。
3. 暂不推进 UI 视觉规范落地；若无验证阻塞，不修改 `ui/` 与 `scenes/`。
4. 持续观察 Godot 退出时既有的 `ObjectDB` / resource 泄漏告警，确认其不会演化为断言不稳定。
5. 若后续需要重新开启 UI 阶段，再以 `docs/plan/ui_art_style_guide.md` 为冻结基线单独立项推进。

## 8. 实施假设

- 当前版本仍以本地 1v1 原型为目标，不规划网络同步。
- 短期内不引入大规模美术或动画重构，且暂不进行 UI 相关调整；当前仍以规则可见性和验证效率为优先。
- `docs/rules/rule.md` 高于 README、旧计划文档和现有实现；若存在冲突，以 `docs/rules/rule.md` 为准。
- 所有功能更新和 bugfix 必须同步记录到 `docs/logs/log_yyyy-MM-dd.md` 当日日志，且内容使用中文。
- 后续每次功能更新完成后，必须同步统一 `docs/plan/development_plan.md`、`docs/plan/mile_stone.md`、`README.md` 与当日日志中的阶段口径、统计基线、验证结果和下一步方向；若其中任一文档仍停留在旧口径，则该次更新视为未完成。
