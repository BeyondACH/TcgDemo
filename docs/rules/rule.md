# 规则摘要 + 程序数据结构映射文档

> 基于 UNION ARENA 官方规则书整理，目标是把“纸面规则”转成“可编程的数据模型与规则引擎设计”。

---

## 1. 文档目标

本文档解决两个问题：

1. **把官方规则压缩成开发可落地的摘要**
2. **把规则映射成程序里的数据结构、状态机和结算流程**

适用场景：

* Godot 卡牌游戏原型
* 本地 1v1 对战模拟器
* 规则引擎 / 卡牌效果系统设计
* Codex 分阶段生成项目骨架

---

# 2. 游戏规则摘要

## 2.1 游戏目标

UNION ARENA 是 2 人对战型集换式卡牌游戏。
玩家构筑只属于自己作品代号的卡组，与对手对战。

### 胜利条件

满足任一条件即获胜：

* 对方**生命区卡牌数量为 0**
* 对方**卡组数量为 0，且在起始阶段无法再抽牌**

---

## 2.2 卡牌类型

规则书中的基础卡牌类型有 4 种：

### 1）角色卡牌

用于：

* 攻击
* 阻挡
* 登场到前线或能量线
* 在移动阶段移动

特点：

* 登场时为**休息状态**
* 只有**活跃状态**角色可以攻击或阻挡
* 角色有 BP（战斗点数）

---

### 2）场地卡牌

用于支援。

特点：

* 只能登场到**能量线**
* **不能移动到前线**
* 登场时为**休息状态**
* 也会占用场上的位置上限

---

### 3）事件卡牌

从手牌发动，处理效果后进入场外。

特点：

* 不长期留在场上
* 主要是一次性效果

---

### 4）行动点卡牌（AP 卡）

用于支付行动点。

特点：

* 支付 1AP 时，把 1 张活跃 AP 卡横置
* AP 区域最多 3 张
* AP 不是手牌，不属于普通可使用卡牌对象

---

## 2.3 卡牌字段

从规则书可抽出一张卡至少包含以下字段：

* 所需能量
* 消费 AP
* 卡牌名
* 特征
* 作品名
* 卡牌种类
* 效果文本
* 触发效果
* 产生能量
* BP
* 稀有度
* 卡牌编号

---

## 2.4 场地区域

## 2.4.1 前线（Front Line）

* 放置角色卡
* 前线角色可以攻击和阻挡
* **角色卡最多 4 张**
* 场地卡不能放这里

## 2.4.2 能量线（Energy Line）

* 放置角色卡和场地卡
* 只有能量线中的卡牌提供“产生能量”
* **角色卡 + 场地卡合计最多 4 张**
* 能量线与前线合称“场”

## 2.4.3 生命区

* 游戏开始时放 7 张卡
* 玩家受到伤害时，从这里处理生命卡
* 触发效果也从这里结算

## 2.4.4 AP 区域

* 放置 AP 卡牌
* 最多 3 张

## 2.4.5 卡组区

* 放置主卡组

## 2.4.6 场外

* 退场角色
* 退场场地
* 使用完的事件卡

## 2.4.7 移除区

* 被指示“移除”的卡放这里
* 一般不会再回到本局游戏

---

## 2.5 卡组规则

### 主卡组

* **50 张**

### AP 卡

* **3 张**

### 构筑限制

* 只能使用同一作品代号的卡构筑
* 相同编号卡最多 4 张
* 某些带特殊触发标记的卡种，合计投入数量也最多 4 张

---

## 2.6 开局流程

1. 洗切卡组
2. 决定先攻后攻
3. 从卡组抽 **7 张** 作为初始手牌
4. 可进行 **一次手牌调度**

   * 先把当前手牌放到一边
   * 再从卡组抽 7 张
   * 然后把原手牌放回卡组洗切
5. 从卡组上方背面朝上放置 **7 张** 到生命区
6. 先攻玩家开始游戏

---

## 2.7 活跃与休息

### 活跃状态

* 竖置

### 休息状态

* 横置

规则要点：

* 角色和场地登场时处于**休息状态**
* 只有**活跃角色**可以攻击或阻挡
* 攻击或阻挡后会转为**休息状态**
* 结束阶段会把角色、场地转回活跃
* **AP 卡在结束阶段不会恢复活跃**

---

# 3. 回合流程摘要

回合分为 5 个阶段：

1. 起始阶段
2. 移动阶段
3. 主要阶段
4. 攻击阶段
5. 结束阶段

---

## 3.1 起始阶段

按顺序处理：

1. “直到下个我方回合开始为止”的效果失效
2. 我方所有休息状态卡牌转为活跃

   * AP 卡
   * 角色
   * 场地
3. 按回合数增加 AP 卡到 AP 区域
4. 从卡组抽 1 张牌

   * **先攻玩家第 1 回合不抽牌**
5. 可支付 1AP 额外抽 1 张牌

   * 每回合最多 1 次

### AP 增长规则

* 先攻第 1 回合：1 张
* 后攻第 1 回合：2 张
* 第 2 回合：2 张
* 第 3 回合及以后：3 张

---

## 3.2 移动阶段

可以把能量线中的任意数量角色移动到前线。

规则要点：

* 所有移动同时进行
* **不能从前线移动到能量线**
* 只有带 **Step / 撤步** 的角色，才可以从前线移回能量线
* 场地卡不能移动
* 若目标区域已满 4 张：

  * 普通角色不能移动进去
  * 带 Step 的角色可与能量线角色交换位置完成移动

---

## 3.3 主要阶段

可执行任意次数的两类行为：

### A. 使用卡牌

#### 1）登场角色

流程：

1. 检查能量是否满足
2. 支付 AP
3. 将角色以休息状态登场到前线或能量线

补充：

* 若目标区域已满 4 张，需先把目标位卡移除后才能登场

---

#### 2）角色卡的突进 / 叠放登场

规则书里是特殊叠放型登场。

处理顺序：

1. 在指定角色上叠放卡牌
2. 作为“突进元”的卡牌失去自身原有效果及受影响状态
3. 若原角色是休息状态，则转为活跃状态
4. 若原本在能量线，由突进玩家选择叠放后留在能量线，或转移到前线
5. 叠放卡上“突进”框内效果有效

补充：

* 拥有突进的卡牌也可以正常登场
* 但若不是通过突进登场，则“突进框内效果”不发动
* 若突进目标原本在前线，则叠放后的角色必须留在前线
* 突进卡上的效果分为“突进框内效果”和“突进框外效果”
* 只有当该卡是通过突进/叠放登场时，突进框内效果才视为有效并可结算
* 若该卡以普通方式登场，则只适用突进框外效果；突进框内效果视为不存在

---

#### 3）登场场地卡

流程：

1. 检查能量是否满足
2. 支付 AP
3. 以休息状态登场到能量线

补充：

* 场地卡不能放前线

---

#### 4）使用事件卡

流程：

1. 检查能量是否满足
2. 支付 AP
3. 处理事件效果
4. 结算完成后放入场外

---

### B. 发动场上卡牌的【启动主要】效果

规则要点：

* 满足条件即可发动
* 标有“每回合 1 次”的效果，每张卡每回合只能发动一次
* 若一张拥有“每回合 1 次”的卡离场后再次登场，视为新对象，可再次发动
* 发动条件可能包括：

  * 横置自身
  * 扔手牌到场外
  * 支付 AP
  * 让此卡退场

多条件时，必须全部满足后才能发动

---

## 3.4 攻击阶段

只能用前线中的活跃角色攻击。

规则流程：

### 1）指定攻击角色的时点

* 选择我方前线 1 张活跃角色
* 将其横置
* 若有“攻击时”效果，先处理

### 2）指定阻挡角色的时点

* 被攻击方可选择前线 1 张活跃角色横置进行阻挡
* 若有“阻挡时”效果，处理该效果
* 若攻击方有“没有被阻挡时”效果，而本次被阻挡，则该效果不发动
* 若攻击方是“狙击”指定角色攻击，对方不能阻挡

### 3）解决时点

根据攻击目标分两类：

---

### A. 攻击目标是角色

发生战斗，比 BP。

#### 情况 1：攻击方 BP >= 阻挡方 BP

* 阻挡方角色退场
* 处理“退场时”效果
* 处理攻击方战斗胜利时效果

#### 情况 2：攻击方 BP < 阻挡方 BP

* 处理攻击方战斗失败时效果
* 处理阻挡方战斗胜利时效果
* **攻击方即使战斗失败也不会退场**

#### 战斗结束后

* 处理“战斗结束时”效果
* 本次战斗中的指定效果失效

---

### B. 攻击目标是对方玩家

* 默认造成 **1 点伤害**
* 若有“伤害 2”，改为造成 2 点伤害
* 若有“冲击 1”，在战斗胜利时再给对方玩家 1 点伤害
* 伤害会让对方从生命区处理对应数量的卡

---

### 玩家受到伤害时

处理流程：

1. 根据伤害数量，由对方指定对应数量生命卡
2. 同时进行触发判定
3. 若生命卡有触发效果，受伤玩家可按任意顺序选择是否发动
4. 触发效果处理完后，这些生命卡放入场外
5. 若处理后对方生命区为 0，则立即决出胜负

---

## 3.5 结束阶段

按顺序处理：

1. 处理“结束阶段开始时”发动的效果
2. 我方所有横置的角色、场地转为活跃

   * **AP 卡不转为活跃**
3. 若手牌为 9 张及以上：

   * 选择保留 8 张
   * 其余放入移除区
4. “这个回合中”的效果失效
5. 进入对方回合

---

# 4. 关键词规则摘要

## Step / 撤步

* 在我方移动阶段中，可从前线移到能量线
* 可与能量线移动到前线的角色同时进行移动

---

## 狙击 / 瞄准攻击

* 可指定攻击对方前线中的角色
* 对方不能阻挡
* 无论对方角色当前是活跃还是休息都能指定攻击
* 被指定角色的状态不会变化

---

## 2 次攻击

* 本回合中首次攻击后，转为活跃状态

---

## 2 次阻挡

* 本回合中首次阻挡后，转为活跃状态

---

## 冲击 1

* 在进行攻击的战斗中胜利时，给对方玩家 1 点伤害

---

## 冲击 +1

* 冲击造成的伤害 +1
* 若原本没有冲击，则获得冲击 1

---

## 伤害 2

* 对玩家直接造成伤害时，改为 2 点伤害

---

## 冲击无效

* 与此角色进行战斗的角色，在该次战斗中失去冲击

---

# 5. 用语与触发时机摘要

## 5.1 触发时机

### 登场时

卡牌放到场上时发动。
通过“突进”登场的效果，也可以在对方回合发动。

### 退场时

卡牌退场时发动。

### 攻击时

该卡攻击时发动。

### 阻挡时

该卡阻挡时发动。

### 我方的回合中

只有在我方回合中持续有效。

### 对方的回合中

只有在对方回合中持续有效。

---

## 5.2 发动条件示例

* 前线中存在时
* 能量线中存在时
* 转为休息状态
* 将 n 张手牌置于场外
* 支付 nAP
* 让这张卡退场
* 每回合 1 次

---

# 6. 程序数据结构映射

下面开始把规则映射到程序。

---

## 6.1 核心枚举设计

```ts
enum CardType {
  CHARACTER,
  FIELD,
  EVENT,
  AP
}

enum ZoneType {
  DECK,
  HAND,
  LIFE,
  FRONT_LINE,
  ENERGY_LINE,
  AP_AREA,
  OUTSIDE,
  REMOVED
}

enum CardState {
  ACTIVE,
  RESTED
}

enum Phase {
  START,
  MOVE,
  MAIN,
  ATTACK,
  END
}

enum TriggerType {
  ON_ENTER,
  ON_LEAVE,
  ON_ATTACK,
  ON_BLOCK,
  ON_TURN_START,
  ON_TURN_END,
  ON_BATTLE_WIN,
  ON_BATTLE_LOSE,
  ON_BATTLE_END,
  ON_LIFE_TRIGGER,
  MAIN_ACTIVATE
}
```

---

## 6.2 卡牌静态数据模型

> 用于描述“卡牌本体”，不保存对局中变化状态。

```ts
type CardDef = {
  id: string
  name: string
  cardType: CardType
  titleCode: string          // 作品代号
  number: string             // 卡牌编号
  rarity?: string
  traits: string[]
  costEnergy?: EnergyCost
  costAP?: number
  energyProvided?: EnergyMap
  bp?: number
  keywords: KeywordDef[]
  effects: EffectDef[]
  triggerEffects: EffectDef[]
  stackRule?: StackRuleDef    // 突进/叠放规则
}
```

---

## 6.3 能量数据结构

规则书要求按颜色满足所需能量，且只统计能量线中的“产生能量”。

```ts
type EnergyColor = "RED" | "BLUE" | "GREEN" | "PURPLE" | "YELLOW" | "WHITE"

type EnergyMap = {
  [color in EnergyColor]?: number
}

type EnergyCost = EnergyMap
```

### 规则实现点

* 只能统计 `ENERGY_LINE`
* 统计对象是卡牌的 `energyProvided`
* 前线角色不参与产能计算

---

## 6.4 卡牌实例数据模型

> 一张牌进入对局后，应从静态定义生成实例对象。

```ts
type CardInstance = {
  uid: string
  defId: string
  ownerPlayerId: string
  controllerPlayerId: string
  zone: ZoneType
  state?: CardState
  currentBP?: number
  stackedUnder: string[]       // 突进叠放在下方的实例ID
  flags: {
	attackedThisTurn?: boolean
	blockedThisTurn?: boolean
	activatedMainThisTurn?: boolean
  }
  attachedEffects?: RuntimeEffect[]
}
```

---

## 6.5 玩家状态模型

```ts
type PlayerState = {
  playerId: string
  deck: string[]        // CardInstance uid list
  hand: string[]
  life: string[]
  frontLine: string[]
  energyLine: string[]
  apArea: APState[]
  outside: string[]
  removed: string[]
}
```

---

## 6.6 AP 数据结构

AP 区域与普通卡不同，建议单独建模。

```ts
type APState = {
  index: number
  active: boolean
}
```

或：

```ts
type APArea = {
  totalSlots: number
  activeCount: number
  restedCount: number
}
```

---

## 6.7 战斗上下文模型

```ts
type BattleContext = {
  attackerId: string
  defenderId?: string
  attackTargetType: "PLAYER" | "CHARACTER"
  attackPlayerId: string
  defendPlayerId: string
  attackerBP: number
  defenderBP?: number
  blocked: boolean
  damageToPlayer: number
  battleEnded: boolean
}
```

---

## 6.8 效果模型

```ts
type EffectDef = {
  id?: string
  trigger: TriggerType | string
  condition?: ConditionDef[]
  cost?: CostDef[]
  target?: TargetRule
  operation: OperationDef[]
  oncePerTurn?: boolean
  text?: string
}
```

---

## 6.9 条件模型

```ts
type ConditionDef =
  | { type: "IN_FRONT_LINE" }
  | { type: "IN_ENERGY_LINE" }
  | { type: "STATE_IS_ACTIVE" }
  | { type: "STATE_IS_RESTED" }
  | { type: "HAS_KEYWORD"; keyword: string }
  | { type: "TURN_OWNER_ONLY" }
  | { type: "OPPONENT_TURN_ONLY" }
  | { type: "HAND_COUNT_AT_LEAST"; value: number }
  | { type: "AP_AVAILABLE"; value: number }
```

---

## 6.10 费用模型

```ts
type CostDef =
  | { type: "PAY_AP"; value: number }
  | { type: "REST_SELF" }
  | { type: "SEND_SELF_TO_OUTSIDE" }
  | { type: "SEND_HAND_TO_OUTSIDE"; value: number }
```

---

## 6.11 目标模型

```ts
type TargetRule =
  | { type: "SELF" }
  | { type: "ATTACKER" }
  | { type: "DEFENDER" }
  | { type: "TARGET_PLAYER" }
  | { type: "FRONT_ALLY" }
  | { type: "FRONT_ENEMY" }
  | { type: "ENERGY_ALLY" }
  | { type: "LIFE_CARD_SELF" }
  | { type: "LIFE_CARD_OPPONENT" }
```

---

## 6.12 操作模型

```ts
type OperationDef =
  | { type: "DRAW"; value: number }
  | { type: "DEAL_DAMAGE_TO_PLAYER"; value: number }
  | { type: "MOVE_ZONE"; to: ZoneType }
  | { type: "REST" }
  | { type: "ACTIVATE" }
  | { type: "MODIFY_BP"; value: number; duration?: "BATTLE" | "TURN" | "PERMANENT" }
  | { type: "GAIN_KEYWORD"; keyword: string; duration?: "BATTLE" | "TURN" }
  | { type: "LOSE_KEYWORD"; keyword: string; duration?: "BATTLE" | "TURN" }
  | { type: "STACK_ON_TARGET" }
```

---

# 7. 规则引擎模块映射

## 7.1 GameState

```ts
type GameState = {
  turnNumber: number
  activePlayerId: string
  priorityPlayerId: string
  phase: Phase
  players: Record<string, PlayerState>
  cards: Record<string, CardInstance>
  effectQueue: EffectStackItem[]
  battleContext?: BattleContext
  winnerPlayerId?: string
}
```

---

## 7.2 RulesEngine 职责

负责：

* 阶段流转
* 能量判定
* AP 支付判定
* 区域容量判定
* 登场合法性判定
* 移动合法性判定
* 攻击合法性判定
* 战斗结算
* 伤害结算
* 胜负判断

---

## 7.3 EffectResolver 职责

负责：

* 检查 trigger
* 检查 condition
* 支付 cost
* 选择 target
* 执行 operation
* 处理 oncePerTurn
* 处理同时触发顺序

---

## 7.4 TurnManager 职责

负责：

* 进入起始阶段
* 进入移动阶段
* 进入主要阶段
* 进入攻击阶段
* 进入结束阶段
* 切换回合方

---

## 7.5 BattleResolver 职责

负责：

* 指定攻击角色
* 指定阻挡角色
* 执行战斗
* 结算 BP 比较
* 结算战斗胜败效果
* 结算玩家受伤
* 触发生命区触发

---

# 8. 区域容量规则映射

```ts
const MAX_FRONT_LINE_CHARACTERS = 4
const MAX_ENERGY_LINE_CARDS = 4
const MAX_AP = 3
const STARTING_LIFE = 7
const STARTING_HAND = 7
const MAIN_DECK_SIZE = 50
const HAND_LIMIT_END_PHASE = 8
```

> 注意：前线限制是“角色最多 4 张”；能量线限制是“角色 + 场地合计最多 4 张”。

---

# 9. 阶段状态机映射

```ts
START
  -> refresh temporary effects
  -> ready cards
  -> grow ap
  -> draw
  -> optional extra draw
  -> MOVE

MOVE
  -> move characters
  -> MAIN

MAIN
  -> play cards
  -> activate main abilities
  -> ATTACK

ATTACK
  -> repeat attack flow
  -> END

END
  -> resolve end triggers
  -> ready characters/fields
  -> hand size check
  -> clear turn effects
  -> next player's START
```

---

# 10. 关键规则难点与程序实现建议

## 10.1 攻击失败的攻击方不会退场

这是 UA 与很多传统 TCG 的差异点。

### 程序建议

不要写成“双方比较 BP，低的退场”。
正确做法是：

* 目标是角色时

  * 若攻击方 BP >= 阻挡方 BP：阻挡方退场
  * 若攻击方 BP < 阻挡方 BP：攻击方不退场，只处理失败效果

---

## 10.2 生命区触发不是自动强制发动

规则书写的是：受伤玩家**可按任意意愿选择是否发动**触发效果。

### 程序建议

生命触发要支持：

```ts
type LifeTriggerDecision = {
  cardId: string
  canActivate: boolean
  chosen: boolean
}
```

---

## 10.3 同时触发顺序

* 多个我方效果同时触发：按我方喜欢顺序处理
* 我方与对方同时触发：回合方先处理，非回合方后处理

### 程序建议

必须有队列，不要发现一个就立即执行。

---

## 10.4 突进叠放离场

突进状态角色离开场地时：

* 只有最上方卡按效果移动到新区域
* 下方叠放卡放到场外

### 程序建议

必须保留 `stackedUnder` 结构，不能把突进角色简化成普通替换。

---

## 10.5 AP 在结束阶段不恢复

这点很容易写错。

### 正确处理

结束阶段：

* 角色、场地恢复活跃
* **AP 卡保持当前状态**

---

# 11. 推荐的最小可实现版本（MVP）

第一版建议只做这些：

## 必做

* 50 张牌库 + 7 手牌 + 7 生命
* 前线 / 能量线 / AP / 场外 / 移除区
* 起始、移动、主要、攻击、结束阶段
* 角色登场
* 场地登场
* 事件使用
* 攻击玩家
* 阻挡
* BP 比较
* 生命区受伤与触发
* 胜负判定

## 第二批再做

* 突进叠放
* 每回合 1 次主动效果
* 狙击
* 冲击 / 伤害 2 / 冲击无效
* 2 次攻击 / 2 次阻挡

---

# 12. 推荐的程序类划分

```text
GameManager
TurnManager
RulesEngine
EffectResolver
BattleResolver
TargetSelector
CostProcessor
ZoneManager
TriggerManager
VictoryChecker
```

---

# 13. 推荐的卡牌 JSON 结构

```json
{
  "id": "UA_TEST_001",
  "name": "基础攻击者",
  "cardType": "CHARACTER",
  "titleCode": "HTR",
  "number": "HTR-1-001",
  "traits": ["测试角色"],
  "costEnergy": {
    "GREEN": 1
  },
  "costAP": 1,
  "energyProvided": {
    "GREEN": 1
  },
  "bp": 3000,
  "keywords": [],
  "effects": [
    {
      "trigger": "ON_ATTACK",
      "condition": [],
      "cost": [],
      "target": {
        "type": "TARGET_PLAYER"
      },
      "operation": [
        {
          "type": "DEAL_DAMAGE_TO_PLAYER",
          "value": 1
        }
      ]
    }
  ]
}
```

---

# 14. 一句话开发结论

这套规则最核心的程序化难点，不是 UI，而是下面 5 件事：

1. **区域容量与移动规则**
2. **活跃 / 休息状态**
3. **能量 + AP 双资源判定**
4. **攻击 / 阻挡 / 战斗结算**
5. **触发效果队列与处理顺序**
