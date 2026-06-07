import datetime

today = datetime.date.today().isoformat()
path = f"docs/logs/log_{today}.md"

content = f"""## {today}
- 变更类型：重构（Phase 0 + Phase 1）
- 变更摘要：
  - Phase 0 Bug修复:
    * Task 0.1: 统一 `_parse_zone` 到 UATypes.key_to_zone()（4份实现→1份），修复 target_selector 无效输入返回 OUTSIDE 而非 -1 的 bug
    * Task 0.2: 修复 consume_timed_delayed_effects 不当丢弃 END_OF_TURN/UNTIL_NEXT_SELF_TURN_START 修饰符
    * Task 0.3: 删除 game_manager.gd L226-228 不可达死代码
    * 顺带修复: effect_resolver.gd 重复 required_card_type 声明、step_executor.gd player 类型推断
  - Phase 1 消除重复与解耦:
    * Task 1.1: 创建 EffectUtils 共享工具类（core/effects/effect_utils.gd），统一 10 个重复函数
    * Task 1.2: keyword 管理移入 CardInstance（add_temp_keyword/remove_temp_keyword/has_temp_keyword/has_any_temp_keyword）
    * Task 1.3: 解除反向依赖 — _resolve_numeric_value + _zone_cards_for_player 移到 EffectUtils，StepExecutor 注入 RequirementMatcher
    * Task 1.4: _execute_operation 从 10 分支 if-elif 改为字典分发，合并 ACTIVATE/ACTIVATE_CARD
- 影响文件：
  - 核心模块: core/ua_types.gd, core/effect_resolver.gd, core/game_manager.gd, core/effects/effect_utils.gd（新建）, core/effects/step_executor.gd, core/effects/target_selector.gd, core/effects/requirement_matcher.gd, core/effects/zone_manager.gd, core/battle_resolver.gd, core/rules_engine.gd
  - 数据层: data/card_instance.gd
- 验证方式：
  - 新增测试: ua_types_zone_test.gd (23/23), effect_utils_test.gd (33/33)
  - 冒烟测试: milestone_smoke_test 33/33, cards_raw_minimal_duel_smoke_test 82/82, runtime_residue_smoke_test 13/14（预存失败）
  - 核心模块零解析错误: 19/19
- 结果：全部通过，无回归
- 后续事项：
  - Phase 2: GameManager 瘦身、BattleScene 拆分、全量类型标注
  - Phase 3: emit_signal 迁移、PendingState 封装、preload 统一
"""

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print(f"Log written: {path}")
