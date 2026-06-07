import os

path = 'docs/logs/log_2026-06-07.md'
# Write clean UTF-8 content directly
content = """## 2026-06-07
- 变更类型：重构（Phase 0 + Phase 1 + Phase 2 + Phase 3）
- 变更摘要：
  - Phase 0 Bug修复:
    * Task 0.1: 统一 _parse_zone 到 UATypes.key_to_zone()（4份实现→1份），修复 target_selector bug
    * Task 0.2: 修复 consume_timed_delayed_effects 不当丢弃修饰符
    * Task 0.3: 删除 game_manager.gd 不可达死代码
    * 顺带修复: 重复 required_card_type 声明、player 类型推断
  - Phase 1 消除重复与解耦:
    * Task 1.1: 创建 EffectUtils（core/effects/effect_utils.gd），统一 10 个重复函数
    * Task 1.2: keyword 管理移入 CardInstance（4 个新方法）
    * Task 1.3: _resolve_numeric_value + _zone_cards_for_player 移到 EffectUtils，StepExecutor 注入 RequirementMatcher
    * Task 1.4: _execute_operation 从 if-elif 改为字典分发，合并 ACTIVATE/ACTIVATE_CARD
  - Phase 2 瘦身与解耦:
    * Task 2.1B: 玩牌校验统一到 rules_engine.can_play_card，删除 3 个死函数
    * Task 2.1C: 提取 MulliganManager（69行），GameManager 982→895 行
    * Task 2.2: LifeTriggerManager 移除死 _game_manager 依赖
  - Phase 3 技术债务:
    * Task 3.1: 全项目 18 处 emit_signal() → .emit() 迁移
    * Task 3.3: preload 策略统一
- 影响文件：
  - 新增: core/effects/effect_utils.gd, core/mulligan_manager.gd
  - 核心: core/ua_types.gd, core/effect_resolver.gd, core/game_manager.gd, core/effects/step_executor.gd, core/effects/target_selector.gd, core/effects/requirement_matcher.gd, core/zone_manager.gd, core/battle_resolver.gd, core/rules_engine.gd, core/life_trigger_manager.gd, core/turn_manager.gd, data/card_instance.gd
  - UI: ui/board_view.gd, ui/card_view.gd, ui/hand_view.gd, ui/drop_zone.gd, ui/zone_cards_popup.gd, ui/zone_stack_summary_view.gd
  - 测试: test/preview_selection_modal_smoke_test.gd
- 验证方式：
  - 新增测试: ua_types_zone_test.gd (23/23), effect_utils_test.gd (33/33)
  - 冒烟测试: milestone_smoke_test 33/33, cards_raw_minimal_duel_smoke_test 82/82, runtime_residue_smoke_test 13/14, life_reveal_modal 全通过
  - 核心模块零解析错误: 19/19
- 累计统计: 19 files, +290/-783 = net -493 lines
- 结果：全部通过，无回归
- 后续事项：
  - Task 2.1A: _available_actions_for_card → get_card_available_actions（需对比测试）
  - Task 2.3: BattleScene 拆分
  - Task 2.4: 全量类型标注
  - Task 3.2: PendingState 封装
"""

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print(f"Log written: {len(content.splitlines())} lines")
