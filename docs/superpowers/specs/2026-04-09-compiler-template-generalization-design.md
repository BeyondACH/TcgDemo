# 编译器模板通用化重构设计

## 目标

将 `tools/compile_cards_effects.py` 从“按单卡 / 按精确日文文本补支持”的识别方式，重构为“归一化 -> 模板识别 -> 英文 semantic IR -> effects 编译”的稳定流水线。

本轮设计只处理编译链与其中间产物，不修改 `docs/rules/rule.md` 的规则语义，也不为运行时引入按卡特判。

## 范围与非目标

### 范围

- 冻结编译主链阶段职责与单向数据流。
- 冻结 `cards_semantic.json` 与 `cards_effects.json` 的英文逻辑字段口径。
- 明确模板层与 `SEMANTIC_OVERRIDE` 的职责边界。
- 以 `MMM` 为迁移样本，以 `TLR` 为跨系列复用验证样本。
- 建立与迁移工作直接对应的识别、semantic、编译与 smoke 验证矩阵。

### 非目标

- 不修改 `rule.md`、运行时 DSL/IR 语义或 Godot 对局规则。
- 不进行 UI、场景或快照结构改造。
- 不引入 OCR、NLP 或模糊语义解释。
- 不允许用按卡运行时执行逻辑作为回退方案。

## 设计约束

- `cards_raw.json` 是唯一正式日文来源。
- 识别完成后，不再允许用日文原文或 `card_id` 作为运行时逻辑分支键。
- 复杂卡牌如果无法稳定模板化，只能进入英文结构化的 `SEMANTIC_OVERRIDE`，不能演化成按卡执行器。
- 所有 semantic / effects 逻辑字段、失败原因与模板标识必须为英文。
- 重构过程必须保持 `MMM` 已支持能力不回归，并证明 `TLR` 同构文本可以复用同一模板族。

## 推荐方案

采用渐进式双轨迁移，而不是一次性重写。

### 方案要点

- 先冻结契约，再拆分识别职责。
- 保留 `registry -> legacy fallback` 作为过渡保护，直到新模板链路被验证安全。
- 优先迁移已经在 `MMM` 中被证明可复用的句式族。
- 用 `TLR` 做“跨系列复用证明”，而不是继续新增按卡分支。
- 只有在迁移前后编译结果、失败分类和 smoke 验证稳定后，才删除对应 legacy 路径。

### 采用原因

- 当前仓库基线已经处于正式 raw 维护阶段，直接推翻重写的回归成本过高。
- `docs/plan/todo.md` 已按 Phase 1-6 定义了分段推进路径，渐进式迁移与现有计划完全一致。
- 该方案最容易做迁移前后差异比对，也最符合仓库对高风险链路“先冻结、再收敛、后清理”的协作方式。

## 架构设计

### 数据流

```text
cards_raw.json
  -> normalize_jp_text()
  -> recognize_template()
  -> semantic IR (english)
  -> compile_template() / compile_override()
  -> cards_effects.json
```

### 分层职责

- `cards_raw.json`
  - 只保存日文原文事实与溯源输入。
- `normalize_jp_text()`
  - 负责空白、标点、引号、全半角与稳定 token 归一化。
  - 不负责解释运行时语义。
- `recognize_template()`
  - 负责模板命中、参数抽取、模板类型与失败原因判定。
  - 输出英文 `template_id`、`params`、`template_types`、`failure_reason`。
- `cards_semantic.json`
  - 作为稳定英文中间表示，承接模板识别结果与 override 回退结果。
- `compile_template()` / `compile_override()`
  - 只消费 semantic IR。
  - 不允许重新打开日文原文做逻辑分支。
- `cards_effects.json`
  - 作为运行时最终输入，逻辑字段保持英文。

## 契约冻结

### Semantic IR

`cards_semantic.json` 本轮冻结在以下字段集合附近：

- `card_id`
- `ability_id`
- `origin`
- `template_id`
- `timing`
- `params`
- `template_types`
- `can_be_expressed_by_dsl`
- `unresolved_capabilities`
- `source_text_jp`

约束：

- `source_text_jp` 只做溯源，不参与逻辑判断。
- 用 `unresolved_capabilities` 统一替换旧的 `missing_capabilities` 口径。
- 逻辑字段与枚举全部使用英文。

### Effects 输出

`cards_effects.json` 的逻辑字段至少统一为英文：

- `status`
- `reason`
- `template_type`
- `analysis`
- `timing`
- `steps`

### 失败原因

本轮统一 failure enum：

- `NO_TEMPLATE_MATCH`
- `PARAM_EXTRACTION_FAILED`
- `SEMANTIC_OVERRIDE_REQUIRED`
- `UNSUPPORTED_RUNTIME_CAPABILITY`

## 模板层与 Override 层边界

### 模板层负责

- 匹配稳定句式族。
- 抽取稳定参数。
- 将同构文本折叠为同一个 `template_id`。
- 直接产出可进入 semantic IR 的英文结构。

### Override 层负责

- 多句依赖、状态记忆、互斥二选一等暂不适合模板层稳定建模的能力。
- 只作为 semantic 层回退输入，不作为运行时执行器。
- 保持英文、结构化、可编译。

### 禁止项

- 仅把逐句匹配搬进注册表后继续依赖精确文本分支。
- 用 `SEMANTIC_OVERRIDE` 承载按卡运行时逻辑。
- 在 semantic / effects 层引入中文或日文逻辑字段。

## 首批模板族

首轮迁移优先覆盖以下模板族：

- `PREVIEW_REORDER`
- `PREVIEW_ADD_TO_HAND_THEN_REORDER`
- `HAND_CHARACTER_SUMMON`
- `OUTSIDE_CHARACTER_RECOVERY`
- `BP_THRESHOLD_ACTION`
- `CONDITIONAL_THRESHOLD_REPLACEMENT`
- `TEMP_ATTRIBUTE_GRANT`
- `NAME_ALIAS`
- `CHOOSE_ONE`
- `MOVE_TO_FRONT_AND_READY_TARGET`

每个模板族都需要补齐：

- 匹配规则
- 参数抽取规则
- 归一化假设
- semantic 输出结构
- compile helper
- 最小识别 / 编译测试

## 实施阶段

### Phase 1：冻结职责与单向流

- 在 `tools/compile_cards_effects.py` 中明确归一化、识别、编译三个逻辑阶段。
- 识别完成后禁止再依赖日文原文或 `card_id` 做逻辑判断。
- 建立至少一条“日文文本 -> 英文 semantic / effects”链路测试。

### Phase 2：注册表与归一化层

- 建立模板注册表、模板匹配入口与日文归一化 helper。
- 首先覆盖预览、加手后重排、从手牌登场、BP 阈值与二选一句式。
- 为标点、换行、引号与全半角差异补识别断言。

### Phase 3：迁移 MMM 分支

- 盘点 `MMM` 中已支持的 legacy 识别分支。
- 可模板化的迁入模板主链；无法模板化但仍可表达的迁入 `SEMANTIC_OVERRIDE`。
- 重新编译 `MMM`，比较支持数量、失败原因与关键样例输出。

### Phase 4：用 TLR 验证复用

- 用 `TLR` 同构文本验证新模板链路的跨系列复用能力。
- 禁止为了通过 `TLR` 再增加新的按卡分支。
- 对关键同构文本增加模板命中断言。

### Phase 5：冻结 Semantic IR 与 Override 输入

- 固化 `cards_semantic.json` 字段口径。
- 冻结 `SEMANTIC_OVERRIDE` 输入格式与准入条件。
- 补字段完整性、英文 enum 与 `source_text_jp` 溯源断言。

### Phase 6：移除已迁移 legacy

- 仅在迁移结果稳定后删除对应 legacy fallback。
- 重新编译全量数据，保持文档、统计、编译产物与测试基线一致。

## 验证策略

### 识别测试

- 日文文本命中英文模板结果。
- `MMM` 已支持模板覆盖。
- `TLR` 同构文本覆盖。
- 标点、换行、引号、全半角差异覆盖。
- 名称、特征、颜色、数量、BP 阈值参数抽取覆盖。

### Semantic 测试

- `cards_semantic.json` 不再出现中文逻辑字段。
- `origin`、`template_id`、`template_types`、`unresolved_capabilities` 使用英文。
- `source_text_jp` 正确保留原文溯源。

### 编译测试

- 至少覆盖 `PREVIEW_REORDER`、`PREVIEW_ADD_TO_HAND_THEN_REORDER`、`HAND_CHARACTER_SUMMON`、`BP_THRESHOLD_ACTION`。
- 断言 `status == SUPPORTED`。
- 断言 steps 骨架与参数映射正确。

### Smoke

- 预览并重排。
- 预览、加手、再重排。
- 条件式从手牌登场。
- BP 阈值目标选择与处理。

## 并行拆分建议

- Agent A：编译主链、模板注册表、semantic / compile helper。
- Agent B：识别测试、semantic 测试、编译回归与 smoke。
- Agent C：文档、迁移盘点、失败分类说明与基线对比记录。

禁止并行：

- 两个 agent 同时修改 `tools/compile_cards_effects.py`。
- semantic 契约未冻结时，多方按各自理解修改 consumer。
- 一个 agent 改模板语义，另一个 agent 仍按旧语义补测试。

## 风险与回退

### 主要风险

- 归一化不足，导致同构文本仍然散落为多条分支。
- 参数抽取过拟合 `MMM`，迁到 `TLR` 后失效。
- semantic 字段迁移破坏后续 effects 编译或运行时消费方。
- override 范围膨胀，重新退化为按卡处理。
- 在回归保护不足时过早删除 legacy fallback。

### 回退规则

- 在迁移被证明安全前，始终保留迁移前后编译结果对比。
- 若某类文本无法稳定模板化，停在 `SEMANTIC_OVERRIDE_REQUIRED`，不补按卡执行逻辑。
- 回归未通过前，不删除对应 legacy 路径。

## 完成判据

满足以下条件才视为本专项完成：

- `cards_raw.json` 仍是唯一正式日文来源。
- `cards_semantic.json` 成为稳定英文中间表示。
- `cards_effects.json` 不再保留中文或日文逻辑字段。
- `MMM` 已支持能力迁移后不回归。
- `TLR` 的同构支持复用模板主链，而不是新增按卡分支。
- 至少存在 1 条识别测试、1 条 semantic 测试、1 条编译测试与 1 个相关 smoke 场景。
