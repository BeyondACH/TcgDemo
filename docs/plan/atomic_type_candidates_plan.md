# 新增原子类型候选计划（按优先级）

## 1. 目标与范围

- 目标：把当前 `cards_effects.json` 中仍存在的“占位分支文本”和“高频组合流程”下沉为可执行、可复用的原子能力类型。
- 范围：
  - `EffectResolver` 运行时步骤/要求扩展
  - 编译链模板映射（`compile_cards_effects`）
  - 受影响卡牌的迁移与最小回归
- 非目标：不改动 `rule.md` 规则语义，不引入按卡硬编码。

---

## 2. 优先级任务单

## P0：分支占位能力可执行化（最高优先）

### 任务 A1：新增 `APPLY_BRANCH_EFFECT_PRESET`

- **type 名称**：`APPLY_BRANCH_EFFECT_PRESET`
- **动机**：替代 `PENDING_BRANCH_EFFECT`，避免分支效果停留在文本占位。
- **输入字段（建议）**：
  - `preset_id: String`
  - `target_spec: { owner, zones, requirements, min, max, selection_mode }`
  - `duration: String`（如 `END_OF_TURN`）
  - `params: Dictionary`（按 preset 传参）
- **示例迁移卡**：
  - `UA45BT_TLR_1_055` 系列中 `EXECUTE_CHOICE_BRANCH + PENDING_BRANCH_EFFECT`
  - `UA36BT_MCR_1_065_on_play_78e3e36e0b` 的分支 1 占位文本
- **完成判定**：
  - 分支步骤不再使用 `PENDING_BRANCH_EFFECT`
  - 对应卡牌在运行时可执行并可回放

### 任务 A2：首批 preset 收敛（最少 3 个）

- 建议首批 `preset_id`：
  1. `UNSELECTABLE_BY_OPPONENT_EFFECT_THIS_TURN`
  2. `CANNOT_BLOCK_NAME_CONTAINS_THIS_TURN`
  3. `BP_THRESHOLD_OVERRIDE_IF_NAME_PRESENT`
- **完成判定**：
  - 每个 preset 至少有 1 张迁移卡
  - 增补最小对局级测试或流程脚本

---

## P1：高频组合流程抽象（高优先）

### 任务 B1：新增 `SELECT_MOVE_WITH_FALLBACK`

- **type 名称**：`SELECT_MOVE_WITH_FALLBACK`
- **动机**：统一“主动作失败时执行后备动作”的样板流程。
- **输入字段（建议）**：
  - `primary_select: CardSetSpec`
  - `primary_move_to: String`
  - `fallback_action: Step`
  - `success_flag_var: String`（可选，不传则内部自动生成）
- **示例迁移卡**：
  - `UA45BT_TLR_1_002_on_enter_43348ae670`
- **完成判定**：
  - 迁移后删除手写 `SET_CONTEXT_FLAG + CONTEXT_FLAG_FALSE` 样板链
  - 行为与迁移前一致

### 任务 B2：新增 `SELECT_AND_PLAY_BY_PROFILE`

- **type 名称**：`SELECT_AND_PLAY_BY_PROFILE`
- **动机**：统一“多条件筛选后登场”的高频组合。
- **输入字段（建议）**：
  - `from_zones: String[]`
  - `profile_requirements: Requirement[]`
  - `select: { min, max, distinct_by? }`
  - `play_to: String`
  - `play_state: String`
  - `ignore_play_timing: bool`
  - `ignore_play_costs: bool`
  - `allow_current_zone: bool`
- **示例迁移卡**：
  - `UA31BT_MMM_1_001_on_leave_b0a2383fc6`
- **完成判定**：
  - 迁移卡无语义回归
  - 编译链能稳定产出统一结构

---

## P2：规则稳定型复合原子（中优先）

### 任务 C1：新增 `REFILL_LIFE_IF_EMPTY`

- **type 名称**：`REFILL_LIFE_IF_EMPTY`
- **动机**：固化“生命为空时补命”流程。
- **输入字段（建议）**：
  - `player: String`（`SELF` / `OPPONENT`）
  - `source_zone: String`（默认 `DECK_TOP`）
  - `amount: int`（默认 1）
- **示例迁移卡**：
  - `UA48BT_KGD_1_029_on_life_trigger_40f54dabd9`
- **完成判定**：
  - 迁移后保留等价触发时机
  - 覆盖“空牌库抽牌失败”相关边界回归

### 任务 C2：新增 `REGISTER_NEXT_PLAY_COST_MODIFIER`

- **type 名称**：`REGISTER_NEXT_PLAY_COST_MODIFIER`
- **动机**：抽象“注册一次性延迟效果并改下次出牌费用”。
- **输入字段（建议）**：
  - `event: String`（默认 `ON_PLAY_CARD`）
  - `once: bool`
  - `expires: String`
  - `filters: Requirement[]`
  - `cost_delta: { ap?: int, energy?: Dictionary }`
- **示例迁移卡**：
  - `base_cards` 里 `REGISTER_DELAYED_EFFECT + MODIFY_PLAY_COST_AP` 样例
- **完成判定**：
  - 迁移后无行为漂移
  - 支持后续系列复用

---

## P3：高级选择器增强（中低优先）

### 任务 D1：扩展 `SELECT_TARGETS_BY_COMBINATION` 约束协议

- **type 名称**：`SELECT_TARGETS_BY_COMBINATION`（扩展）
- **动机**：在已有 `max_count + max_sum_bp` 基础上增加统一约束能力。
- **新增输入字段（建议）**：
  - `max_sum_cost_energy`
  - `group_by`
  - `per_group_max`
  - `max_per_trait`
  - `distinct_by`
- **示例迁移卡**：
  - `UA45BT_TLR_1_030_on_enter_cae4ef1c23`
- **完成判定**：
  - 新旧约束兼容
  - 新增约束具备单测与流程回归

---

## 3. 里程碑与交付节奏

1. **M1（P0）**：先清理 `PENDING_BRANCH_EFFECT`。
2. **M2（P1）**：沉淀两个高频组合流程原子。
3. **M3（P2）**：规则稳定型复合原子迁移。
4. **M4（P3）**：高级选择器协议扩展与兼容测试。

每个里程碑都要同步：

- 至少一种有效验证（单测 / 流程 / 最小对局）
- `docs/logs/log_yyyy-MM-dd.md` 中文日志
- 迁移清单（卡号、能力 id、变更前后结构对照）

---

## 4. 验收标准

- 与 `rule.md` 语义一致，不引入按卡硬编码
- 要求/步骤边界清晰：requirements 不改状态，steps 只做执行
- 迁移卡行为等价，且关键流程有回归
- 文档、日志、计划同轮同步
