# `cards_raw` 卡图补录说明

本文档记录当前仓库中“读取 `pic/` 卡图并补录到 `data/cards/<series>/cards_raw.json`”的实际操作逻辑、字段映射和已知注意点。后续如果需要继续补卡，默认先按本文档执行，再视情况调整脚本。

当前对应脚本为 `tools/import_cards_raw_from_pic.ps1`。

## 1. 输入范围

- 只读取 `pic/` 顶层图片文件。
- 不读取 `pic/micro/` 缩略图目录。
- 不读取 Godot 自动生成的 `.import` 文件。
- 当前默认接受的图片扩展名：
  - `.png`
  - `.jpg`
  - `.jpeg`
  - `.webp`

## 2. 卡号来源

- 卡号完全来自图片文件名，不做 OCR。
- 文件名必须能直接映射到官网单卡编号。
- 例如：
  - `UA31BT-MMM-1-035.png` -> 官网 `card_no=UA31BT/MMM-1-035`
  - `UA31ST-MMM-104.png` -> 优先尝试 `UA31ST/MMM-104`，若编号后三段只有 3 位数字，再兼容尝试 `UA31ST/MMM-1-104`

脚本会同时生成：

- `number`
  - 例：`UA31BT/MMM-1-035`
- `id`
  - 例：`UA31BT_MMM_1_035`
- `source_image`
  - 例：`UA31BT-MMM-1-035.png`

## 3. 官网抓取口径

- 数据源固定为 Union Arena 官网单卡详情页。
- 当前抓取地址为：
  - `https://www.unionarena-tcg.com/jp/cardlist/detail_iframe.php?card_no=...`
- 请求时会补一组浏览器头，至少包含 `User-Agent`、`Accept`、`Accept-Language` 与 `Referer`，尽量与浏览器访问口径保持一致。
- 该脚本默认应在沙箱外执行；若在沙箱内运行，网络请求可能直接失败，此时不应把失败结果当成官网详情页不存在。
- 写入对应系列目录下的 `cards_raw.json` 时，`source_url` 固定保存为详情页地址：
  - `https://www.unionarena-tcg.com/jp/cardlist/detail.php?card_no=...`
- 不接第三方 API。
- 不依赖 OCR 文本识别。

如果官网页面抓不到、页面结构不符合预期、关键字段缺失、或返回页中的卡号与目标卡号不一致，则该卡不应写入目标系列的 `cards_raw.json`。

补充说明：

- 当前脚本会尽量区分以下失败原因：
  - `network_error`
    - 通常表示 PowerShell 当前环境无法连到官网，常见于沙箱内或临时网络故障
  - `request_failed`
    - 请求已发出，但返回了非 404 的错误状态，或出现其他请求级异常
  - `detail_structure_missing`
    - 请求成功，但返回页缺少脚本当前依赖的详情结构
  - `card_number_mismatch`
    - 请求成功且能解析卡号，但返回卡号与目标候选编号不一致
  - `official_page_not_found`
    - 仅在请求成功但官方页明确不存在、或结构可解析但找不到目标卡时使用

## 4. 写入与去重规则

默认模式：

- 按卡号中的系列码定位并读取现有 `data/cards/<series>/cards_raw.json`
- 建立 `number` 和 `id` 两套索引
- 若候选卡已存在，则跳过，不覆盖旧条目

刷新模式：

- 使用脚本参数 `-RefreshExisting`
- 会重新抓取 `pic/` 顶层图片对应的官网页
- 若目标系列 `cards_raw.json` 中已存在相同 `number` 或 `id`，会先移除旧条目，再写入新条目
- 适合以下情况：
  - 官网字段解析逻辑修复后，需要批量回填旧数据
  - 之前导入成功，但某些字段解析错误或为空

## 5. 系列 `cards_raw.json` 字段映射

官网抓取结果按当前系列 `cards_raw.json` 契约写入以下字段：

- `id`
- `name`
- `card_type`
- `title_code`
- `number`
- `traits`
- `cost_energy`
- `cost_ap`
- `energy_provided`
- `bp`
- `keywords`
- `effects`
- `trigger_effects`
- `rarity`
- `series_title`
- `source_image`
- `source_url`
- `raw_effect_text`
- `raw_trigger_text`
- `ruby`

若检测到 `RAID` 文本，还会补：

- `special_play_rule`

说明：

- `raw_effect_text` / `raw_trigger_text` 保留官网原始文本整理结果
- `effects` / `trigger_effects` 只做原始分段和基础标签映射
- 不在导入阶段做按卡硬编码
- 不在导入阶段做 DSL/IR 专项扩展

## 6. 已实现的基础文本解析规则

### 6.1 卡面基础字段

- `name`
  - 从 `cardNameCol` 提取
- `ruby`
  - 从 `rubyData` 提取
- `number`
  - 从 `cardNumData` 提取
- `rarity`
  - 从 `rareData` 提取
- `series_title`
  - 从标题区域图标 `alt` 提取
- `card_type`
  - 从 `categoryData` 提取并映射为：
    - `CHARACTER`
    - `EVENT`
    - `FIELD`

### 6.2 费用与 BP

- `cost_energy`
  - 从 `needEnergyData` 解析
- `cost_ap`
  - 从 `apData` 解析
- `bp`
  - 从 `bpData` 解析

### 6.3 特征

- `traits`
  - 从 `attributeData` 提取
  - 用全角斜杠 `／` 或普通斜杠 `/` 切分
  - `-` 和空串会被忽略

### 6.4 效果与触发

- `effectData`
  - 生成 `effects`
- `triggerData`
  - 生成 `trigger_effects`
- 当前已做的基础触发映射：
  - `登場時` -> `ON_ENTER`
  - `アタック時` -> `ON_ATTACK`
  - `ブロック時` -> `ON_BLOCK`
  - `退場時` -> `ON_LEAVE`
  - `メイン` / `起動メイン` -> `MAIN_ACTIVATE`
  - 触发区普通文本 -> `ON_LIFE_TRIGGER`

### 6.5 关键词

当前脚本会尝试从效果标签或文本中补基础关键词：

- `RAID`
- `DOUBLE_ATTACK`
- `DOUBLE_BLOCK`
- `SNIPER`
- `STEP`
- `DAMAGE_2`
- `IMPACT`
- `IMPACT_PLUS_1`
- `NEGATE_IMPACT`

## 7. 发生产能 `energy_provided` 的注意点

这是本轮补录里最容易出错的字段，必须特别注意。

官网 `generatedEnergyData` 中的图片 `alt` 不止一种写法，当前脚本已兼容以下三类：

- `颜色 + 数字`
  - 例：`紫2`
  - 含义：该颜色产能为 2
- `颜色字符重复`
  - 例：`紫紫`
  - 含义：该颜色产能为 2
- `颜色 + 加号`
  - 例：`紫+`
  - 含义：该颜色基础产能为 1，且通常伴随“发生产能+”相关文本提示

已确认的真实样例：

- `UA31BT/MMM-1-035`
  - 官网 `generatedEnergyData alt="紫紫"`
  - 应写为 `{"PURPLE": 2}`
- `UA31BT/MMM-1-046`
  - 官网 `generatedEnergyData alt="紫+"`
  - 应写为 `{"PURPLE": 1}`

后续如果再发现新的 `alt` 表达形式，必须先扩展解析器，再重新执行 `-RefreshExisting`，不要手动只改单卡 JSON。

## 8. 推荐操作流程

### 8.1 新增缺失卡

适用于：

- `pic/` 顶层新增了卡图
- 对应系列 `cards_raw.json` 中还没有这些卡

执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\import_cards_raw_from_pic.ps1
```

建议直接在沙箱外执行；若在沙箱内执行后看到 `network_error`，应先切换到沙箱外复跑，再判断是否存在真实缺卡。

预期：

- 已存在条目会跳过
- 新卡会被追加写入
- 终端会输出：
  - `scanned`
  - `skipped_existing`
  - `added`
  - `failed`

### 8.2 修复已有卡字段

适用于：

- 解析规则修复后，需要回填旧数据
- 某些已导入卡的字段为空或解析错误

执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\import_cards_raw_from_pic.ps1 -RefreshExisting
```

同样建议在沙箱外执行，避免把环境网络失败误判成官网数据问题。

预期：

- `pic/` 顶层图片对应的卡会全部重新抓取
- 旧条目会按 `number` / `id` 替换
- 可用于统一修复 `energy_provided` 等批量问题

### 8.3 补录后同步生成缩略图

适用于：

- 本轮导入新增了 `pic/` 顶层卡图对应的数据
- 希望 `pic/micro/` 缩略图目录与顶层卡图保持同步

执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\generate_micro_card_images.ps1
```

建议在导入成功后顺带执行一次。该脚本会读取 `pic/` 顶层 `.png` 卡图，并只为 `pic/micro/` 中当前缺失的文件生成缩略图，不会覆盖已有缩略图。

预期：

- 终端会输出：
  - `scanned`
  - `skipped_existing`
  - `generated`
  - `output_dir`

## 9. 导入后的检查项

每次写入系列 `cards_raw.json` 后，至少检查以下内容：

- 条目总数是否符合预期
- 新增卡是否都有：
  - `source_image`
  - `source_url`
  - `number`
  - `id`
- `energy_provided` 是否出现明显异常空值
- `raw_effect_text` / `raw_trigger_text` 是否与官网文本一致
- `effects` / `trigger_effects` 是否仍保持原始分段，不要混入按卡特判

建议优先抽查以下高风险字段：

- `energy_provided`
- `trigger_effects`
- `special_play_rule`
- `keywords`

## 10. 下游同步

按设计，系列 `cards_raw.json` 更新后应继续同步：

- `data/cards/<series>/cards_effects.json`
- `data/cards/<series>/cards_semantic.json`
- `pic/micro/` 缩略图目录

当前编译入口仍是：

```powershell
py tools/compile_cards_effects.py
```

如需完成下游同步，允许在沙箱外调用 Python 执行该编译命令。

缩略图同步入口为：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\generate_micro_card_images.ps1
```

推荐顺序：

1. 先执行 `import_cards_raw_from_pic.ps1`
2. 导入成功后执行 `generate_micro_card_images.ps1`
3. 再执行 `compile_cards_effects.py`

推荐优先使用已安装的明确解释器路径，例如：

```powershell
C:\Users\ACH\AppData\Local\Programs\Python\Python311\python.exe tools\compile_cards_effects.py
```

如果当前环境没有可用 Python，则：

- 先完成目标系列 `cards_raw.json` 写入
- 在日志中明确记录下游编译被环境阻塞
- 待环境补齐后再执行编译和相关回归

## 11. 编码与日志要求

- 所有代码文件和文档保持 UTF-8
- 涉及中文文档、日志、规则说明时，读取时优先使用显式 UTF-8
- 每次功能更新或 bugfix，都必须同步写入：
  - `docs/logs/log_yyyy-MM-dd.md`

日志至少应记录：

- 日期
- 变更类型
- 变更摘要
- 影响文件或模块
- 验证方式与结果
