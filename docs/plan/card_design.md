# cards_effects 未实现原子能力待办清单

## 当前状态

- 当前 `data/cards/cards_effects.json` 统计为 76 个已支持能力、0 个未支持能力。
- 核心 P1 与剩余 P1 已全部落地，运行时已覆盖“特殊登场/出牌规则授权”“临时产能修饰 + 延迟自退场”“正式 raw RAID/Final/手牌减费”这批高风险模板。
- 现有运行时已落地的原子步骤包括：`ACTIVATE_AP_SLOTS`、`ACTIVATE_CARD`、`ADD_TEMP_BP_MODIFIER`、`ADD_TEMP_KEYWORD`、`DRAW`、`FOR_EACH`、`LIFE_TRIGGER_RAID_CHOICE`、`MOVE_CARD`、`MOVE_SELECTED_CARDS`、`MOVE_TOP_DECK_TO_LIFE`、`MOVE_ZONE`、`PLAY_SELECTED_CARDS`、`PREVIEW_TOP_DECK`、`REGISTER_DELAYED_EFFECT`、`REGISTER_STATIC_MODIFIER`、`REORDER_CONTEXT_CARDS`、`SELECT_TARGETS`、`SET_CONTEXT_FLAG`。
- 本轮补齐的通用能力口径：
  - 手牌中的条件能量减费（`SELF_HAND_ENERGY_DELTA`）
  - 场地牌以 `ACTIVE` 状态登场（`play_rule.enter_state`）
  - “最多 N 张 AP”自动恢复
  - 基于“本回合曾从生命区加手”的条件 requirement
  - 基于 `battle_outcome` 的战斗后条件 requirement
  - 生命/揭示窗口结束后自动恢复 effect queue，避免战斗后队列被挂起

## 优先级 P0：优先补齐的通用能力模板

- [x] 从手牌按过滤条件登场角色
  - 目标：支持“从手牌将满足必要能量、AP、颜色、特征条件的角色以 REST 登场到场上”的统一步骤模板。
  - 影响卡：`UA31BT_MMM_1_075`、`UA31BT_MMM_1_082`、`UA31ST_MMM_1_102`
  - 建议拆分：
    - 新增“从指定区域选择满足过滤条件的卡”目标模板
    - 新增“将选中卡以指定状态登场到 FRONT_LINE”步骤
    - 补齐场上容量与合法落点校验

- [x] 可选支付/可选前置动作后再继续结算
  - 目标：支持“你可以先做 A；若如此做，则执行 B”的固定 IR 组合。
  - 影响卡：`UA31ST_MMM_1_102`、`UA31ST_MMM_1_108`
  - 建议拆分：
    - 沿用显式目标选择，新增“optional 选择成功标记”
    - 用统一上下文变量驱动后续步骤 requirements
    - 禁止退回按卡分支

- [x] 从场外按过滤条件检索到手
  - 目标：支持“从 OUTSIDE 选择满足费用/AP/特征条件的卡加入手牌”的统一步骤模板。
  - 影响卡：`UA31ST_MMM_1_108`

- [x] 临时授予“不能攻击”直到下个自己回合开始
  - 目标：支持非数值型临时限制效果，不只覆盖 BP 增减。
  - 影响卡：`UA31BT_MMM_1_075`
  - 建议拆分：
    - 新增临时 keyword/状态授予模板
    - 明确持续时点：`UNTIL_NEXT_SELF_TURN_START`
    - 在 `RulesEngine` 攻击合法性校验中消费统一状态

## 优先级 P1：需要扩展原子 requirement 的能力

- [x] 动态 BP 上限 requirement
  - 目标：支持“自己场上其他某特征角色的名称种类数 × N”这类动态阈值。
  - 影响卡：`UA31BT_MMM_1_078`
  - 建议拆分：
    - 新增场面计数 requirement/value provider
    - 明确“其他”“名称种类数”“按特征过滤”的统一语义
    - 再复用到 `CARD_BP_LTE_DYNAMIC` 类模板，而不是按卡硬编码

- [x] 条件满足时替换数值阈值
  - 目标：支持“默认 BP3000，若满足条件则改为 BP5000”的统一能力模板。
  - 影响卡：`UA31BT_MMM_1_093`、`UA31BT_MMM_1_094`、`UA31ST_MMM_1_094`
  - 建议拆分：
    - 明确是“可变 requirement 参数”而不是两段按卡分支
    - 支持由场面条件、生命值条件驱动的数值升级

- [x] 公开结果驱动后续奖励
  - 目标：支持“预览并公开选到的牌，若其满足某特征/关键词，则执行额外步骤”的 requirement 模板。
  - 影响卡：`UA31BT_MMM_1_098`
  - 建议拆分：
    - 在上下文中保留“公开加入手牌的那张卡”
    - 新增对上下文卡牌的 trait/keyword/文本标签判断

## 优先级 P1：需要扩展步骤语义的能力

- [x] 临时增加发生产能
  - 目标：支持“这个角色本回合发生产能 +1/获得额外产能颜色”等统一临时资源修饰。
  - 影响卡：`UA31BT_MMM_1_070`、`UA31ST_MMM_1_070`

- [x] 临时授予延迟自退场效果
  - 目标：支持“获得『主阶段结束时，将此角色退场』”这类延迟能力授予。
  - 影响卡：`UA31BT_MMM_1_070`、`UA31ST_MMM_1_070`
  - 建议拆分：
    - 可以是统一的 delayed effect registration 模板
    - 也可以是临时 keyword + 固定触发解释
    - 但必须保持为可复用原子能力

- [x] 生命区回手后临时获得特殊登场/RAID 许可
  - 目标：支持“直到下个自己回合开始，这张卡可从手牌 REST 登场或 RAID”的特殊出牌规则授予。
  - 影响卡：`UA31BT_MMM_1_090`
  - 注意：按 AGENTS 约束，这类能力应归入出牌规则层或专门的出牌规则模型，不混入普通效果步骤硬编码。

## 优先级 P2：需要补齐控制流语义的能力

- [x] 首选动作失败时执行 fallback
  - 目标：支持“若能回收其他角色则回收；否则将自己回手”的统一失败分支模板。
  - 影响卡：`UA31BT_MMM_1_085`、`UA31ST_MMM_1_085`
  - 建议拆分：
    - 明确“无法完成”的判定口径
    - 采用固定格式的 `TRY_* / ELSE_*` 或等价 IR，不回退到脚本式控制流

## 卡牌到能力缺口映射

- `UA31BT_MMM_1_070`、`UA31ST_MMM_1_070`
  - 已补：临时增加发生产能、主阶段结束时自退场
- `UA31BT_MMM_1_078`
  - 已补：动态 BP 上限 requirement
- `UA31BT_MMM_1_085`、`UA31ST_MMM_1_085`
  - 已补：失败分支 fallback
- `UA31BT_MMM_1_090`
  - 已补：生命区回手后临时获得特殊登场/RAID 许可（绑定来源角色自身，持续到下个自己回合开始）
- `UA31BT_MMM_1_093`、`UA31BT_MMM_1_094`、`UA31ST_MMM_1_094`
  - 已补：条件满足时替换 BP 阈值
- `UA31BT_MMM_1_098`
  - 已补：公开结果驱动后续奖励

## 实施顺序建议

- [x] 第一批先做“从手牌过滤登场”“可选前置动作后继续结算”“从场外过滤检索到手”
  - 原因：复用面最大，能直接消化 4 张以上卡
- [x] 第二批先补“临时限制中的不能攻击直到下个自己回合开始”
  - 原因：该模板已覆盖 `UA31BT_MMM_1_075`，但“临时出牌许可/临时产能修饰”仍留在后续阶段继续补齐
- [x] 第三批补“动态 requirement / 条件化阈值替换 / fallback 控制流”
  - 结果：已落地统一 `value_provider`、上下文卡引用与 fallback 主链/后备链表达，覆盖 `078`、`085`、`093`、`094`、`098`

## 开发前冻结项

- [x] 冻结“特殊登场/特殊 RAID 许可”属于出牌规则层的契约，不放回普通步骤特判
- [x] 冻结“optional 成功标记”和“上下文卡引用”的统一字段命名
- [x] 冻结“动态数值来源”的表达格式，避免后续再出现按卡定制字段
- [x] 冻结 fallback 控制流的固定 IR 结构，避免脚本化步骤进入正式模型

## 验收要求

- [ ] 每补一类原子能力，都要同步更新 `tools/compile_cards_effects.py`
- [ ] 每补一类原子能力，都要重新生成 `data/cards/cards_effects.json`
- [ ] 至少补一条对应的最小对局或冒烟用例，覆盖新模板的主链路
- [ ] 正式 raw 样例扩充后，`docs/cards_raw_minimal_duel_smoke_test.gd` 应维持当前 39 项通过、0 项失败基线
- [ ] 若改动触及 UI 待决策流或预览选择流，额外确认手牌区域不遮挡战场区域
