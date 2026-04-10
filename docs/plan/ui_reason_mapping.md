# 暂停/恢复与组合选目标错误码 UI 映射表

更新时间：2026-04-10

## 1. 适用范围

- 目标：统一 `GameManager.execute_decision()` 在 `ABILITY_TARGET_SELECTION` 恢复路径返回的 `reason` 与 UI 展示文案。
- 当前覆盖：`TargetSelector.validate_selection_payload()` 已落地的关键失败码，以及分支/组合约束链路会复用的错误码。

## 2. 映射建议

| reason | 触发条件（规则语义） | UI 提示建议（中文） | UI 行为建议 |
| --- | --- | --- | --- |
| `pending_decision_not_found` | 用户提交时已无对应待决策（可能已被消费或上下文失效） | 当前没有可处理的选择，请刷新操作。 | 关闭当前弹窗并刷新可用动作。 |
| `not_enough_targets` | 选择数小于最小要求（`min`） | 选择数量不足，请至少选择指定数量。 | 保留弹窗，阻止提交。 |
| `too_many_targets` | 选择数超过 `max` 或 `selection_constraints.max_count` | 选择数量超出上限。 | 保留弹窗，阻止提交。 |
| `duplicate_target` | 同一卡 UID 被重复提交 | 不能重复选择同一目标。 | 保留弹窗，阻止提交。 |
| `invalid_choice` | 提交值不在候选集合中 | 选择目标无效，请重新选择。 | 保留弹窗，必要时重拉候选。 |
| `duplicate_card_name` | `selection_constraints.distinct_by = CARD_NAME` 下出现同名重复 | 不能选择同名卡牌。 | 保留弹窗，阻止提交。 |
| `selection_sum_exceeded` | 超过 `max_sum_bp` 或 `max_sum_provider` 动态阈值 | 目标总 BP 超过限制。 | 保留弹窗，并显示当前阈值提示。 |
| `selection_not_disjoint` | 与 `disjoint_with_var/other_var` 对应已选集合不互斥 | 目标不能与前一组选择重复。 | 保留弹窗，突出冲突目标。 |

## 3. 与 Week 2 范围的衔接

- `P1-1` 分支子效果模板化后，分支内若再次进入手动选目标，仍复用上表错误码。
- `P1-2` `selection_constraints` 编译映射后，`max_count`、`max_sum_bp`、`max_sum_provider` 对应失败码仍应保持稳定，不新增卡级特判 reason。

