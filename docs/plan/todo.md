# 编译器原子能力通用化方案与 TODO

更新时间：2026-04-09

## 1. 文档定位

本文件是面向实现的专项计划，用于把 `tools/compile_cards_effects.py` 从“按单卡 + 精确日文文本匹配”改造成“可复用的模板驱动识别链路”。

它属于 `docs/plan/development_plan.md` 阶段 A 下的子计划，不替代主开发计划。它的职责是定义编译器识别通用化所需的目标架构、冻结契约、执行顺序、风险边界与验收标准。

## 2. 问题陈述

当前编译器虽然已经具备 `registry -> legacy fallback` 的骨架，但仍存在以下结构性问题：

- 部分识别路径仍依赖 `card_id` 或精确日文原文。
- 日文原文仍然泄漏到 semantic / effects 层。
- `cards_semantic.json` 现在更像摘要产物，而不是稳定的中间表示。
- 模板识别与 semantic override 之间的边界还不够严格。
- 如果继续按单卡补支持，会违反仓库中“禁止按卡写运行时逻辑”的规则。

这项工作不是为了再多支持几张卡，而是为了把编译器改造成可复用、可测试、可扩展的识别流水线。

## 3. 目标、非目标与完成定义

### 3.1 目标

- 把日文文本限制在 `cards_raw.json` 与编译器输入边界内。
- 建立稳定链路：文本归一化 -> 模板识别 -> 构建 semantic IR -> 编译运行时 effects。
- 明确冻结模板识别与 `SEMANTIC_OVERRIDE` 的边界。
- 一次性把可复用的 `MMM` 分支迁移进模板体系。
- 让 `TLR` 的同构文本直接复用同一套模板，而不是新增按卡分支。
- 用英文统一 semantic 字段、template id、失败原因与 effects 逻辑字段。

### 3.2 非目标

- 不修改 `rule.md` 的规则语义。
- 不在编译契约对齐之外重做运行时 DSL/IR 行为设计。
- 不引入 OCR、NLP 或模糊语义解释模型。
- 不允许用按卡运行时执行器作为 override 逃生口。
- 本轮范围不包含 UI 或对局功能开发。

### 3.3 完成定义

只有在以下条件全部满足时，才算本计划完成：

- `cards_raw.json` 是唯一正式的日文来源。
- `cards_semantic.json` 成为稳定的英文中间表示。
- `cards_effects.json` 不再保存中文或日文的诊断逻辑字段。
- `MMM` 已支持能力在迁移后不发生回归。
- `TLR` 的同构文本路径改为复用模板，而不是新增 `card_id` 分支。
- 至少存在一种有效验证，覆盖文本识别、semantic 输出、effects 编译与对局级 smoke。

## 4. 目标架构

### 4.1 数据流

```text
cards_raw.json（日文源）
  -> normalize_jp_text()
  -> recognize_template()
  -> semantic IR（英文）
  -> compile_template()
  -> cards_effects.json
```

复杂文本的回退链路：

```text
cards_raw.json
  -> normalize_jp_text()
  -> recognize_template()
  -> SEMANTIC_OVERRIDE（英文结构化声明）
  -> semantic IR（英文）
  -> compile_template() / compile_override()
```

### 4.2 分层职责

- `cards_raw.json`
  - 只保存日文原文事实。
  - 不是运行时语义层。
- `normalize_jp_text`
  - 负责统一标点、空白、token 形态与句式格式。
  - 不负责决定运行时语义。
- `recognize_template`
  - 负责匹配模板族并抽取参数。
  - 返回英文的 template id、params 与 failure reason。
- `cards_semantic.json`
  - 稳定的英文中间表示。
  - 同时承接模板识别结果与 override 回退结果。
- `compile_template`
  - 只消费 semantic IR。
  - 不允许重新打开日文原文作为逻辑分支依据。
- `cards_effects.json`
  - 面向运行时的最终产物。
  - 逻辑字段统一保持英文。

### 4.3 设计规则

- 以原子能力建模，而不是以单卡建模。
- 以模板族复用，而不是以卡牌编号复用。
- 识别层回答“这段文本在结构上表达了什么”。
- 编译层回答“这类结构如何映射到 DSL / effects”。
- 运行时只消费统一 IR。

## 5. 冻结契约

### 5.1 编译阶段契约

必需的逻辑阶段：

- `normalize_jp_text(text_jp) -> normalized_text`
- `recognize_template(normalized_text, raw_context) -> template_match`
- `compile_template(semantic_entry) -> effects_entry`

规则：

- 只允许单向数据流。
- 识别完成后，不允许再出现由日文原文驱动的分支。
- 识别完成后，不允许把 `card_id` 当作主要逻辑键。

### 5.2 Semantic IR 契约

`cards_semantic.json` 需要稳定在以下字段集合附近：

- `card_id`
- `ability_id` 或等价能力键
- `origin`
- `template_id`
- `timing`
- `params`
- `template_types`
- `can_be_expressed_by_dsl`
- `unresolved_capabilities`
- `source_text_jp`

规则：

- 逻辑字段必须全部使用英文。
- `source_text_jp` 只承担溯源职责。
- 用 `unresolved_capabilities` 替换旧的 `missing_capabilities`。

### 5.3 Effects 输出契约

以下逻辑字段必须保持英文：

- `status`
- `reason`
- `template_type`
- `analysis`
- `timing`
- `steps`

规则：

- 保持与运行时现有消费方的兼容性。
- 日文原文只能通过 `source_text_jp` 这类 provenance 字段保留。

### 5.4 失败原因契约

允许的 failure enum：

- `NO_TEMPLATE_MATCH`
- `PARAM_EXTRACTION_FAILED`
- `SEMANTIC_OVERRIDE_REQUIRED`
- `UNSUPPORTED_RUNTIME_CAPABILITY`

不再接受中文失败原因。

## 6. 模板层与 Override 层边界

### 6.1 模板层范围

模板层允许做以下事情：

- 匹配稳定句式族。
- 抽取稳定参数。
- 产出英文的 `template_id`、`params`、`template_types` 与 failure。
- 把同构文本折叠到同一个可复用模板中。

### 6.2 Override 层范围

`SEMANTIC_OVERRIDE` 只用于：

- 带记忆 / 状态影响的互斥二选一分支。
- 无法在模板层稳定建模的多句依赖关系。
- 仍需额外结构化语义补充的复杂文本。

Override 规则：

- 只允许英文结构化声明。
- 只允许作为 semantic 层回退方案。
- 不允许演变为按卡运行时执行逻辑。

### 6.3 明确禁止项

- 只是把精确文本 `if/elif` 分支搬进注册表，就宣称已经完成重构。
- 让 override 演变成按卡执行器。
- 让原始日文文本直接驱动运行时 effects。
- 在 semantic / effects 层引入中文或日文逻辑字段。

## 7. 第一批模板族

首轮迁移应优先覆盖：

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

每个模板都必须定义：

- `template_id`
- 匹配规则
- 参数抽取规则
- 归一化假设
- semantic 输出结构
- compile helper
- 最低限度测试

## 8. 执行阶段

### Phase 1：语言边界与编译职责拆分

目标：

- 把编译器职责拆分为归一化、识别、编译三层。
- 强制落实从原文到 semantic IR 再到 effects 的单向流。

写入范围：

- `tools/compile_cards_effects.py`
- 直接相关测试
- 必要时新增辅助模块

完成判据：

- 识别完成后不再使用日文文本作为逻辑键。
- semantic / effects 逻辑字段全部为英文。
- `cards_raw.json` 仍是唯一日文来源。

最低验证：

- 至少有 1 条“日文原文 -> 英文 semantic / effects”链路测试。

### Phase 2：注册表骨架与归一化层

目标：

- 建立可复用的模板注册表。
- 增加稳定的日文归一化 / token 化层。

优先句式族：

- 预览牌库前 N 张
- 加手后重排
- 从手牌登场
- BP 阈值目标选择
- 二选一分支

完成判据：

- 仅有标点、换行或宽度差异的同构文本，仍会命中同一模板。
- 不再新增绑定 `card_id` 的模板分支。

最低验证：

- 针对名称、特征、颜色、数量与 BP 阈值的参数抽取测试。

### Phase 3：迁移既有 MMM 识别分支

目标：

- 盘点可复用的 `MMM` 分支。
- 把可模板化分支迁移进注册表。
- 把结构上仍可表达的复杂分支迁移到 `SEMANTIC_OVERRIDE`。

完成判据：

- 已迁移的 legacy 分支被移除。
- `MMM` 已支持能力不回归。

最低验证：

- 重新编译 `MMM`，并比较支持数量、失败情况与关键样例输出。

### Phase 4：用 TLR 证明跨系列复用

目标：

- 证明 `TLR` 的同构文本可以直接复用 `MMM` 模板，而不需要新增按卡分支。

完成判据：

- `TLR` 的主要模板类别已经直接走模板族主链。
- 未支持项数量下降，或至少被更准确分类。

最低验证：

- 重新编译 `TLR`。
- 为同构文本补充模板命中断言。

### Phase 5：正式化 Semantic IR 与 Override 输入

目标：

- 把 `cards_semantic.json` 固化为正式英文 IR。
- 冻结 `SEMANTIC_OVERRIDE` 的输入格式与准入规则。

完成判据：

- `cards_semantic.json` 不再漂移成摘要产物。
- Override 继续保持“只在 semantic 层、且结构化”。

最低验证：

- 对字段完整性、英文 enum 与 `source_text_jp` 正确溯源补断言。

### Phase 6：移除双轨并冻结基线

目标：

- 移除已迁移部分对应的 legacy fallback 逻辑。
- 让文档、统计、编译产物与测试基线回到同一口径。

完成判据：

- 已迁移模板不再依赖旧分支。
- 文档、日志、编译输出与测试保持一致。

最低验证：

- 全量重新编译。
- 复跑相关 compile tests 与 smoke coverage。

## 9. 测试矩阵与验收门槛

### 9.1 文本识别测试

- [ ] 增加“日文文本 -> 英文模板结果”的识别测试。
- [ ] 覆盖当前已支持的 `MMM` 模板。
- [ ] 覆盖与 `MMM` 同构的 `TLR` 文本。
- [ ] 覆盖标点、引号、换行与全半角差异。
- [ ] 覆盖名称、特征、颜色、数量与 BP 阈值抽取。

### 9.2 Semantic 测试

- [ ] 断言 `cards_semantic.json` 中不再保留中文 `missing_capabilities`。
- [ ] 断言 `origin`、`template_id`、`template_types` 与 `unresolved_capabilities` 全部为英文。
- [ ] 断言 `source_text_jp` 正确保留对应日文原文。

### 9.3 编译测试

- [ ] 为以下模板增加“识别 -> DSL step”断言：
  - `PREVIEW_REORDER`
  - `PREVIEW_ADD_TO_HAND_THEN_REORDER`
  - `HAND_CHARACTER_SUMMON`
  - `BP_THRESHOLD_ACTION`
- [ ] 断言 `status == SUPPORTED`。
- [ ] 断言 step 骨架结构正确。
- [ ] 断言参数映射正确。

### 9.4 回归测试

- [ ] 重新编译 `MMM` 与 `TLR`。
- [ ] 确认 `MMM` 已支持能力不回归。
- [ ] 确认 `TLR` 的同构文本现在复用模板。
- [ ] 确认未支持总量下降，或至少被更准确分类。
- [ ] 确认未支持原因使用英文 enum。

### 9.5 对局级 Smoke

- [ ] 预览并重排。
- [ ] 预览、加手、再重排。
- [ ] 条件式从手牌登场。
- [ ] BP 阈值目标选择与处理。

### 9.6 验收门槛

如果以下条件有任一未满足，本项工作就不能验收通过：

- 至少有 1 条有效识别测试。
- 至少有 1 条有效 semantic 输出测试。
- 至少有 1 条有效编译测试。
- 至少有 1 个相关 smoke 场景。
- `MMM` 支持度不回归。
- `TLR` 的同构支持不依赖新的按卡分支。
- semantic / effects 逻辑字段中不存在中文或日文污染。

## 10. 并行化边界

### 10.1 安全并行拆分

- Agent A：编译主链与模板注册表
- Agent B：测试、编译回归与对局 smoke
- Agent C：文档、迁移盘点与失败分类说明

### 10.2 禁止并行组合

- 两个 agent 同时编辑 `tools/compile_cards_effects.py`。
- semantic 契约尚未冻结时，多方消费者同时按各自理解改结构。
- 一个 agent 改模板语义，另一个 agent 仍按旧语义补测试。
- 一个 agent 改 override 格式，另一个 agent 仍按旧格式补数据。

### 10.3 默认执行顺序

1. 冻结契约。
2. 建立归一化层与注册表骨架。
3. 迁移可复用的 `MMM` 分支。
4. 用 `TLR` 验证跨系列复用。
5. 冻结 semantic IR 与 override 结构。
6. 移除 legacy 双轨路径并冻结基线。

## 11. 风险与回退规则

### 11.1 主要风险

- 归一化过弱，导致同构文本依然被拆散。
- 参数抽取过度拟合某个系列，无法泛化到其他系列。
- semantic 字段迁移破坏 effects 编译或运行时消费方。
- override 范围再次膨胀回按卡处理。
- 在回归保护尚未建立前过早清理 legacy 路径。

### 11.2 回退规则

- 在迁移分支被证明安全前，持续保留迁移前后的编译结果对比。
- 在大规模迁移前先冻结 semantic 字段，避免长期处于半新半旧状态。
- 如果某一类文本无法稳定模板化，就停在 `SEMANTIC_OVERRIDE_REQUIRED`，不要补按卡执行逻辑。
- 对应回归路径未通过前，不要删除 legacy fallback。

## 12. 默认约束

- `cards_raw.json` 是唯一正式日文来源。
- 不引入 OCR 或 NLP 模型。
- 不允许按卡运行时硬编码。
- 不允许在 semantic / effects 层新增中文或日文逻辑字段。
- 复杂卡可以使用 `SEMANTIC_OVERRIDE`，但 override 必须保持英文且结构化。
- 如果这项工作会影响阶段优先级、基线统计或测试策略，必须在同一轮同步更新 `docs/plan/development_plan.md`。

## 13. 交付清单

- [ ] 已冻结并清晰记录契约。
- [ ] 已明确模板层与 override 层边界。
- [ ] 已列出首批模板族与优先级。
- [ ] 每个阶段都具备入口、出口与最低验证要求。
- [ ] 已列出并行边界与禁止组合。
- [ ] 已列出主要风险、失败枚举与回退规则。
- [ ] 文档持续与 `development_plan.md` 和 `rule.md` 保持一致。
