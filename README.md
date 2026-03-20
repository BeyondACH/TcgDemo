# TcgDemo

基于 Godot 4.6 的本地 1v1 卡牌对战原型项目，当前目标是先跑通一个可迭代的最小玩法闭环，再逐步补齐更完整的规则、卡牌效果和界面体验。

## 项目简介

这个项目实现了一个偏规则驱动的卡牌对战原型，玩法设计参考 UNION ARENA 风格。当前版本更接近“可运行的战斗框架 + 示例卡组”，重点放在：

- 对局初始化
- 回合与阶段流转
- 手牌出牌与能量校验
- 攻击、阻挡、伤害与胜负判断
- 基础卡效与触发
- 简单可操作的对战 UI

## 当前已实现

- 双方卡组加载、洗牌、起手抽牌、生命区初始化
- 回合阶段推进：`START -> MOVE -> MAIN -> ATTACK -> END`
- AP 成长、消耗与每回合重置
- 基础区域管理：牌库、手牌、生命区、前线、能量区、场外区、移除区
- 角色牌、场地牌、事件牌的基础出牌规则
- 能量需求校验
- 移动阶段将角色从能量区移动到前线
- 基础战斗流程：攻击宣言、可选阻挡、BP 比较、对玩家造成伤害
- 胜负判定：生命归零、空牌库抽牌失败
- 基础效果类型：
  - `DRAW`
  - `MOVE_ZONE`
  - `REST`
  - `ACTIVATE`
  - `DEAL_DAMAGE_TO_PLAYER`
- 基础触发入口：
  - `ON_ENTER`
  - `ON_ATTACK`
  - `ON_BLOCK`
  - `ON_LIFE_TRIGGER`
- 原型 UI：手牌点击、拖放出牌、阶段推进、攻击与阻挡选择、日志显示

## 当前未完成

- 更完整的规则细化，当前仍是最小可玩原型
- 更丰富的卡牌效果系统和目标选择
- `MAIN_ACTIVATE` 等主动能力完整接入
- `ON_LEAVE` 等离场触发的统一派发
- 关键字能力支持，例如 `RAID`
- 更完整的真实卡牌数据导入与编码清理
- 自动化测试、调试面板、回放等开发辅助能力
- 更成熟的 UI/UX 与动画反馈

## 运行方式

### 环境要求

- Godot 4.6

### 启动项目

1. 使用 Godot 4.6 打开仓库根目录。
2. 打开项目后直接运行主场景。
3. 当前入口场景为 [scenes/battle_scene.tscn](D:\CodexWork\TcgDemo\scenes\battle_scene.tscn)。

也可以通过 [project.godot](D:\CodexWork\TcgDemo\project.godot) 中配置的 `run/main_scene` 直接启动。

## 操作说明

- 点击手牌可选中卡牌。
- 可通过按钮将角色打到前线、将角色或场地打到能量区、使用事件牌。
- 也支持将手牌拖放到前线或能量区。
- 在 `MOVE` 阶段，点击能量区中的角色可尝试移动到前线。
- 在 `ATTACK` 阶段，点击当前行动方前线角色可宣言攻击。
- 若存在可阻挡角色，防守方可选择阻挡；也可以点击 `No Block` 放弃阻挡。
- 右侧日志区域会记录主要对局过程。

## 目录结构

- [core](D:\CodexWork\TcgDemo\core)：核心规则、回合管理、战斗与效果结算
- [data](D:\CodexWork\TcgDemo\data)：运行时数据结构、卡牌数据和卡组数据
- [scenes](D:\CodexWork\TcgDemo\scenes)：Godot 场景
- [ui](D:\CodexWork\TcgDemo\ui)：界面层与交互脚本
- [rule.md](D:\CodexWork\TcgDemo\rule.md)：规则与设计参考
- [AGENTS.md](D:\CodexWork\TcgDemo\AGENTS.md)：协作代理工作说明

## 核心脚本

- [core/game_manager.gd](D:\CodexWork\TcgDemo\core\game_manager.gd)：对局主控制器，连接数据、规则和 UI
- [core/turn_manager.gd](D:\CodexWork\TcgDemo\core\turn_manager.gd)：回合与阶段推进
- [core/rules_engine.gd](D:\CodexWork\TcgDemo\core\rules_engine.gd)：基础出牌、移动、攻击、阻挡校验
- [core/battle_resolver.gd](D:\CodexWork\TcgDemo\core\battle_resolver.gd)：攻击与阻挡结算
- [core/effect_resolver.gd](D:\CodexWork\TcgDemo\core\effect_resolver.gd)：基础效果与触发结算
- [core/zone_manager.gd](D:\CodexWork\TcgDemo\core\zone_manager.gd)：区域移动与抽牌/AP 等操作

## 数据说明

- 卡牌定义位于 [data/cards/base_cards.json](D:\CodexWork\TcgDemo\data\cards\base_cards.json)
- 示例卡组位于：
  - [data/decks/starter_a.json](D:\CodexWork\TcgDemo\data\decks\starter_a.json)
  - [data/decks/starter_b.json](D:\CodexWork\TcgDemo\data\decks\starter_b.json)

当前仓库里部分中文/Japanese 文本在终端下可能显示乱码，这更像是编码或终端代码页问题；在批量改动数据文件前，建议先确认原始文件编码。

## 卡组导入

项目提供了一个卡组导入脚本，可把类似 [import.txt](D:\CodexWork\TcgDemo\import.txt) 的文本导入为 `data/decks/` 下的 JSON 卡组文件。

支持格式：

- 每行一条卡牌，格式为 `数量x卡牌编号`
- 例如：`4xUA31BT_MMM-1-002`
- 空行、`#` 注释行、`//` 注释行会被忽略

匹配规则：

- 优先按 `base_cards.json` 中的卡牌 `id` / `number` 做规范化匹配
- 会忽略大小写以及 `/`、`-`、`_` 等分隔符差异
- 生成的卡组内容仍使用 `base_cards.json` 里的真实 `id`

执行方式：

```powershell
godot --headless --path D:\CodexWork\TcgDemo --script res://docs/import_deck.gd -- --name 我的卡组
```

也可以显式指定源文件和输出目录：

```powershell
godot --headless --path D:\CodexWork\TcgDemo --script res://docs/import_deck.gd -- --name 我的卡组 --source res://import.txt --output-dir res://data/decks
```

执行成功后会生成：

- `data/decks/我的卡组.json`

## 开发建议

- 规则逻辑优先放在 `core/`
- 共享状态和数据结构优先放在 `data/`
- 界面表现和交互保持在 `ui/`
- 修改玩法时，同时检查状态流转、日志输出和 UI 是否一致
- 非必要不要手改 `.uid` 文件

## 下一步建议

1. 清理并稳定卡牌数据格式与文本编码。
2. 扩展效果系统，补齐目标选择、持续效果和离场触发。
3. 完善关键字与更完整的战斗规则。
4. 增加自动化测试与调试工具。
5. 打磨 UI 表现和交互反馈。
