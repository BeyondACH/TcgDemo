## AI 动作展示延迟与提示

**问题描述**：AI 控制器执行动作太快，用户无法看清每个操作的执行过程。

**根本原因**：`controller_manager.gd` 的 `drive_controllers()` 方法在第117-147行有一个同步循环，在单帧内可能连续执行多个 AI 动作（最多64步）。

**当前流程**：
```
emit_state_changed() -> queue_drive() -> _process_drive_deferred() -> drive_controllers(64)
```
- 循环中每次 `_execute_action()` 后立即继续下一个动作
- UI 只在循环结束后收到一次状态更新

**用户需求**：
1. 每次 AI 动作执行后添加时间延迟（如 0.3秒）
2. 在 UI 上显示动作提示文字（如"AI 抽牌"、"AI 攻击"）

## 实现方案

采用 **SceneTreeTimer 延迟 + 动作提示文字方案**。

### 关键修改文件

| 文件 | 修改内容 |
|------|----------|
| `core/controllers/controller_manager.gd` | 添加延迟机制，发射动作执行信号 |
| `core/game_manager.gd` | 新增 `ai_action_executed` 信号，注入 SceneTree |
| `ui/battle_scene.gd` | 响应动作信号，显示提示文字 |

### 详细实现步骤

#### 1. GameManager 新增动作执行信号

```gdscript
# game_manager.gd 新增信号（约第27行）
signal ai_action_executed(action_info: Dictionary)

# 新增配置参数
@export var ai_action_delay := 0.3
```

#### 2. ControllerManager 添加延迟机制和动作信号发射

**新增属性**：
```gdscript
# controller_manager.gd 新增
var ai_action_delay_seconds := 0.3
var _scene_tree: SceneTree = null
var _action_signal_emitter: Callable = Callable()  # 发射 ai_action_executed 信号
```

**修改 `drive_controllers()` 为异步**：
```gdscript
func drive_controllers(max_steps: int = 64) -> void:
    if not _can_drive():
        return
    _drive_in_progress = true
    var safety := max_steps
    while safety > 0:
        if _check_winner():
            break
        _refresh_life_reveal()
        if _is_life_reveal_waiting():
            break
        var player_id := _get_priority_player_id()
        var controller: PlayerController = _controllers.get(player_id)
        if controller == null or controller.is_human():
            break
        var legal_actions := _get_legal_actions(player_id)
        if legal_actions.is_empty():
            break
        var snapshot := _get_snapshot()
        var chosen_action := {}
        if _has_pending_gate() or _has_battle_context():
            chosen_action = controller.request_pending_decision(game_state, snapshot, _get_pending_context(), legal_actions)
        else:
            chosen_action = controller.request_action(game_state, snapshot, legal_actions)
        if chosen_action.is_empty():
            break
        
        # 发射动作信号，让 UI 显示提示
        if _action_signal_emitter.is_valid():
            _action_signal_emitter.call(_build_action_info(chosen_action, snapshot))
        
        _execute_action(chosen_action)
        safety -= 1
        
        # 关键：AI 动作后延迟
        if _scene_tree != null and ai_action_delay_seconds > 0:
            await _scene_tree.create_timer(ai_action_delay_seconds).timeout
    
    _drive_in_progress = false
    if _drive_pending and not _check_winner():
        _process_drive_deferred()
```

**新增 `_build_action_info()` 方法**：
```gdscript
func _build_action_info(action: Dictionary, snapshot: Dictionary) -> Dictionary:
    var action_type := str(action.get("type", ""))
    var params: Dictionary = action.get("params", {})
    var phase := str(snapshot.get("phase", ""))
    var player_id := str(snapshot.get("priority_player_id", ""))
    return {
        "action_type": action_type,
        "params": params,
        "phase": phase,
        "player_id": player_id,
    }
```

#### 3. GameManager 初始化注入

**修改 `_initialize_controller_manager()`**：
```gdscript
func _initialize_controller_manager() -> void:
    controller_manager.player_one_controller_type = player_one_controller_type
    controller_manager.player_two_controller_type = player_two_controller_type
    controller_manager.game_state = game_state
    controller_manager.action_executor = _execute_controller_action
    controller_manager.legal_actions_provider = _get_controller_legal_actions
    controller_manager.snapshot_provider = get_snapshot
    controller_manager.winner_checker = _has_winner
    controller_manager.pending_gate_checker = _has_pending_gate
    controller_manager.priority_player_provider = _current_priority_player_id
    controller_manager.pending_context_provider = _current_pending_context
    controller_manager.life_reveal_refresher = _refresh_life_reveal_waiting_for_player
    controller_manager.life_reveal_waiting_checker = _is_life_reveal_waiting_for_player
    # 新增注入
    controller_manager._scene_tree = get_tree()
    controller_manager.ai_action_delay_seconds = ai_action_delay
    controller_manager._action_signal_emitter = _emit_ai_action_signal
```

**新增信号发射方法**：
```gdscript
func _emit_ai_action_signal(action_info: Dictionary) -> void:
    emit_signal("ai_action_executed", action_info)
```

#### 4. BattleScene 显示动作提示

**新增 UI 元素**：
- 在 TopHUD 或单独位置添加一个 Label 用于显示动作提示
- 提示文字格式："Player 2 (AI): 抽牌"、"Player 2 (AI): 攻击"

**响应信号**：
```gdscript
# battle_scene.gd _ready() 中新增
game_manager.ai_action_executed.connect(_on_ai_action_executed)

# 新增响应方法
func _on_ai_action_executed(action_info: Dictionary) -> void:
    var action_type := str(action_info.get("action_type", ""))
    var player_id := str(action_info.get("player_id", ""))
    var phase := str(action_info.get("phase", ""))
    var action_text := _format_ai_action_text(action_type, action_info.get("params", {}), phase)
    ai_action_label.text = "%s (AI): %s" % [player_id, action_text]
    # 可选：使用 Tween 让提示淡入淡出

func _format_ai_action_text(action_type: String, params: Dictionary, phase: String) -> String:
    match action_type:
        ActionTypes.ADVANCE_PHASE:
            return "进入 %s 阶段" % phase
        ActionTypes.PLAY_CARD:
            return "出牌"
        ActionTypes.MOVE_CARD:
            var mode := str(params.get("mode", ""))
            if mode == ActionTypes.MOVE_ENERGY_TO_FRONT:
                return "能量线 → 前线"
            elif mode == ActionTypes.MOVE_STEP_TO_ENERGY:
                return "前线 → 能量线"
            return "移动"
        ActionTypes.ATTACK:
            var target_kind := str(params.get("target_kind", "PLAYER"))
            if target_kind == "PLAYER":
                return "攻击玩家"
            else:
                return "狙击角色"
        ActionTypes.BLOCK:
            return "阻挡"
        ActionTypes.NO_BLOCK:
            return "不阻挡"
        ActionTypes.END_TURN:
            return "结束回合"
        ActionTypes.RESOLVE_PENDING_DECISION:
            return "做出决策"
        ActionTypes.RESOLVE_LIFE_TRIGGER:
            return "触发生命"
        _:
            return action_type
```

### 验证方式

1. **手动测试**：启动游戏，观察 AI 对战时每个动作的展示效果
   - 验证提示文字正确显示
   - 验证延迟时间合适
2. **冒烟测试**：运行 `docs/vs_ai_smoke_test.gd` 确保不破坏现有流程
3. **无头测试**：验证无头模式下不依赖 SceneTree（需要处理 null 情况）

### 注意事项

- 延迟时间需要可配置，便于调试和用户偏好
- AI 自测时可以将延迟设为 0 提高效率
- 无头模式下 `get_tree()` 可能返回 null，需要安全处理
- 确保延迟不影响人类玩家的操作流畅性
- 同步更新 `docs/logs/log_2026-04-01.md` 记录变更

---

