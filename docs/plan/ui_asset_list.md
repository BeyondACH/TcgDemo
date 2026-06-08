# UI 素材清单

更新时间：2026-06-08

所有素材按优先级分三级：
- **A — 阻塞**：没有它面板骨架跑不起来
- **B — 高优**：有了体验完整，没它也能用 Unicode / 纯色 fallback
- **C — 锦上添花**：全部 StyleBoxFlat 跑通后再补

---

## 目录结构

```
assets/ui/
├── icons/           # 图标 (SVG)
│   ├── slot_sword.svg          [A] 20×20, 前线空槽标识
│   ├── slot_diamond.svg        [A] 20×20, 能量线空槽标识
│   ├── func_log.svg            [B] 24×24, 日志抽屉触发按钮
│   ├── func_close.svg          [B] 24×24, 弹窗关闭按钮
│   ├── zone_life.svg           [B] 20×20, 生命堆叠标识
│   ├── zone_deck.svg           [B] 20×20, 牌库堆叠标识
│   ├── zone_outside.svg        [C] 16×16, 场外堆叠标识
│   └── zone_removed.svg        [C] 16×16, 移除堆叠标识
├── dots/            # 能量颜色圆点 (PNG)
│   ├── energy_red.png          [A] 14×14
│   ├── energy_blue.png         [A] 14×14
│   ├── energy_green.png        [A] 14×14
│   ├── energy_purple.png       [A] 14×14
│   ├── energy_yellow.png       [A] 14×14
│   └── energy_white.png        [A] 14×14
├── backgrounds/     # 背景与纹理
│   └── panel_grid_tile.png     [C] 50×50, 面板极淡网格纹理（tileable）
└── effects/         # 高亮与光晕
    ├── glow_selection.png      [B] 128×128, 选中径向光晕
    └── glow_cyan_ring.png      [C] 128×128, 青色环状高亮（可选）
```

---

## A 级素材 — 阻塞项（必须生成）

### A1. `slot_sword.svg` — 前线空槽图标

- **用途**：前线面板空槽位中心的微弱标识图标
- **最终尺寸**：20×20 px
- **方向**：扁平化，最小化线条

**提示词（中英双语）：**

> 生成一个极简、扁平的 SVG 图标，用于数字卡牌游戏的前线槽位。
> 主体是一把居中、竖直的短剑，只用 1.5px 宽度单色线条绘制，无填充。
> 剑柄在上、剑尖朝下，轮廓简洁到只剩可辨识的最少线条。
> 颜色 `#A8B2C2`，透明度 14-18%。
> 整体气质偏赛博/数字竞技场，不带任何装饰花纹、没有渐变、没有阴影、背景透明。
>
> Generate a minimalist flat SVG icon for a digital card game's front-line slot.
> A centered, vertical short sword drawn with 1.5px single-color strokes, no fill.
> Hilt at top, tip pointing down. Remove every unnecessary detail — only the barest recognizable silhouette.
> Color `#A8B2C2`, opacity 14-18%.
> Cyber/digital arena aesthetic. No ornament, no gradient, no shadow, transparent background.

### A2. `slot_diamond.svg` — 能量线空槽图标

- **用途**：能量线面板空槽位中心的微弱标识图标
- **尺寸**：20×20 px

> 生成一个极简、扁平的 SVG 图标，用于数字卡牌游戏的能量线槽位。
> 主体是一个居中的菱形（旋转45°的正方形），1.5px 单色线条描边，无填充。
> 菱形内部中心有一个更小的实心菱形（dim 2×2px），表达"能量核心"。
> 颜色 `#A8B2C2`，外部菱形透明度 14-18%，内部小菱形透明度 24%。
> 赛博/数字竞技场气质，无装饰、无渐变、背景透明。
>
> Generate a minimalist flat SVG icon for a digital card game's energy-line slot.
> A centered diamond (square rotated 45°) — 1.5px stroke, no fill.
> A tiny solid diamond (2×2px) at center suggesting an "energy core."
> Outer diamond color `#A8B2C2` at 14-18% opacity, inner core at 24%.
> Cyber/digital arena aesthetic. No ornament, no gradient, transparent background.

### A3-A8. `energy_*.png` ×6 — 能量颜色圆点

- **用途**：顶部 HUD 能量指示器，6 个颜色各一个
- **尺寸**：14×14 px，圆形

**统一模板（每个颜色替换 color hex）：**

> 生成一个 14×14 像素的 PNG 圆形图标，用于数字卡牌游戏的能量指示器。
> 纯色填充的完美圆形，边缘有 0.5px 的微弱外发光（颜色同填充色，透明度 20%）。
> 不做任何图标、文字、渐变。就是一颗纯粹的颜色圆点。
> 赛博/现代 UI 风格。
>
> Generate a 14×14 pixel PNG circle icon for a digital card game's energy indicator.
> A perfect solid-color circle with a subtle 0.5px outer glow (same color, 20% opacity).
> No icon, no text, no gradient — just a pure colored dot.
> Cyber/modern UI style. Transparent background.

| 文件 | 颜色名 | Hex |
|------|--------|-----|
| `energy_red.png` | 红 | `#D95A5A` |
| `energy_blue.png` | 蓝 | `#4A90D9` |
| `energy_green.png` | 绿 | `#5C9A6E` |
| `energy_purple.png` | 紫 | `#8E6BBF` |
| `energy_yellow.png` | 黄 | `#D4A843` |
| `energy_white.png` | 白 | `#D0D5DE` |

---

## B 级素材 — 高优（建议生成）

### B1. `func_log.svg` — 日志抽屉触发图标

- **用途**：右上角触发日志抽屉的小按钮图标
- **尺寸**：24×24 px

> 生成一个 24×24 的扁平 SVG 图标，用于数字卡牌游戏的"打开日志"按钮。
> 主体是三条水平线（类似 hamburger-menu 但偏右对齐），再加右下角叠一个小矩形表示"面板/文档"。
> 线条 1.5px 宽，颜色 `#A8B2C2`。赛博/终端风格，简洁、不高调。
> 无填充、无阴影、背景透明。
>
> Generate a 24×24 flat SVG icon for a "toggle log" button in a digital card game.
> Three horizontal lines (right-aligned), with a small rectangle overlay at bottom-right suggesting a panel/document.
> 1.5px strokes, color `#A8B2C2`. Cyber/terminal style, understated.
> No fill, no shadow, transparent background.

### B2. `func_close.svg` — 关闭按钮图标

- **用途**：弹窗右上角关闭按钮
- **尺寸**：24×24 px

> 生成一个 24×24 扁平 SVG 关闭图标（X），1.5px 线条，无填充。
> 颜色 `#A8B2C2`，悬停态变 `#00ACC1`（可以在代码里做）。
> 极简、干净的 X，交叉点居中，四个端点与角落微距。
> 透明背景。
>
> Generate a 24×24 flat SVG close/cross icon. Two 1.5px diagonal lines forming an X.
> Color `#A8B2C2`. Minimal, clean, centered intersection.
> Transparent background.

### B3. `zone_life.svg` — 生命堆叠标识

- **用途**：贴在生命附属堆叠上的微弱标识
- **尺寸**：20×20 px

> 生成一个 20×20 极简 SVG 图标，表达"生命/血量"。
> 核心是一个极简的心形轮廓（1.5px 描边，无填充）或者一个竖条上的横断标记。
> 颜色 `#A8B2C2`，透明度 16%。赛博/数字医疗终端风格——不要写实的心形。
> 背景透明。
>
> Generate a 20×20 minimalist SVG icon suggesting "life/HP."
> Could be a clean heart outline (1.5px stroke, no fill) rendered in a cyber/digital-medical-terminal style — not a realistic heart.
> Color `#A8B2C2` at 16% opacity. Transparent background.

### B4. `zone_deck.svg` — 牌库堆叠标识

- **用途**：贴在牌库附属堆叠上的微弱标识
- **尺寸**：20×20 px

> 生成一个 20×20 极简 SVG 图标，表达"牌库/卡组"。
> 两张重叠的卡片轮廓（1.5px 描边、无填充），上方卡片略偏移。
> 颜色 `#A8B2C2`，透明度 16%。透明背景。
>
> Generate a 20×20 minimalist SVG icon for "deck/card stack."
> Two overlapping card silhouettes (1.5px stroke, no fill), slightly offset.
> Color `#A8B2C2` at 16% opacity. Transparent background.

### B5. `glow_selection.png` — 选中径向光晕

- **用途**：卡牌/槽位被选中时叠加的柔光背景
- **尺寸**：128×128 px，中心径向渐变

> 生成一个 128×128 的 PNG，纯径向渐变——中心是青色 `#00ACC1`（透明度 35%），
> 到边缘完全透明（alpha=0）。渐变平滑、柔和，无硬边。
> 用于叠加在选中卡牌或槽位后面做"选中态光晕"。
> 无形状、无图案、无文字——就是一颗纯粹的渐变光点。
>
> Generate a 128×128 PNG radial gradient. Center: cyan `#00ACC1` at 35% opacity,
> fading smoothly to fully transparent at edges. No hard border.
> Used as a "selection glow" behind selected cards or slots.
> No shape, no pattern, no text — just a pure gradient orb.

---

## C 级素材 — 锦上添花（可后补）

### C1/C2. `zone_outside.svg` / `zone_removed.svg`

- **尺寸**：16×16 px
- 场外：向外箭头或方块+箭头组合
- 移除：X 标记或禁止图标
- 极简线条，1.5px 描边，`#A8B2C2`，透明度 14%

### C3. `panel_grid_tile.png` — 面板网格纹理

- **尺寸**：50×50 px，tileable（无缝平铺）
- 极淡的像素网格线（1px 线），颜色 `#FFFFFF`，透明度 4-6%
- 网格间距约 8-10px
- 其余区域完全透明
- 用于面板底色上方叠加微弱"赛博终端屏幕"质感

> 生成一个 50×50 像素的无缝 tileable PNG 纹理。
> 极淡的网格线（1px 细线，间距 10px），颜色白色，透明度 4-6%。
> 网格线外的区域完全透明。用于数字卡牌游戏面板底色的微妙质感叠加。
> 视觉效果：几乎是看不见的终端屏幕像素网格。
>
> Generate a 50×50 pixel seamless tileable PNG texture.
> Very faint grid lines (1px, 10px spacing), white, 4-6% opacity.
> Everything between lines is fully transparent.
> For a subtle "terminal screen" texture overlay on digital card game panels.
> Should be almost invisible — a barely-there pixel grid.

### C4. `glow_cyan_ring.png` — 青色环状高亮

- **尺寸**：128×128 px
- 青色 `#00ACC1` 的细环（3-4px 宽），边缘模糊，中心完全透明
- 用于选中的面板/槽位外环效果

---

## 使用说明

1. 把以上提示词按优先级发送给 ChatGPT / DALL-E / Midjourney 生成
2. SVG 文件直接放入 `assets/ui/icons/`，PNG 文件直接放入对应 `assets/ui/dots/`、`assets/ui/effects/`
3. Godot 里通过 `load("res://assets/ui/icons/slot_sword.svg")` 加载
4. 所有图标在代码中通过 `modulate` 属性动态调色（如 `modulate = Color(0.659, 0.698, 0.761)` 对应 `#A8B2C2`），素材本身用提示词中的颜色生成即可
