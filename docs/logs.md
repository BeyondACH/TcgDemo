# 变更日志

本文件用于记录每一次功能更新与 bugfix。

## 记录模板

- 日期：YYYY-MM-DD
- 类型：功能更新 | bugfix
- 摘要：...
- 影响文件：...
- 验证结果：...

- 日期：2026-03-22
- 类型：功能更新
- 摘要：新增独立的 DRAW 阶段，保留先攻首回合跳过系统抽牌的规则，并支持在当前行动玩家自己的 DRAW 阶段内支付 1 AP 执行每回合一次的额外抽牌。
- 影响文件：core/ua_types.gd，core/turn_manager.gd，core/game_manager.gd，ui/battle_scene.gd，scenes/battle_scene.tscn，docs/draw_phase_smoke_test.gd
- 验证结果：使用 Godot headless 运行 `res://docs/draw_phase_smoke_test.gd`，结果为 `DRAW_PHASE_SMOKE_OK`。
