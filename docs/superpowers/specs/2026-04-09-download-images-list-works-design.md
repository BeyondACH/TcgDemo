# download_images `--list-works` 设计

## 目标

为 `download_images.py` 增加 `--list-works` 交互入口。
用户执行该参数后，脚本先从 `attrweblist` 读取官方作品列表，打印带序号的列表，再提示输入编号。
选中作品后，脚本直接进入既有下载主流程，并通过 `weblist?works=<作品名>` 下载该作品下全部产品的图片。

## 约束

- 保持现有 `--list-products` 行为不变。
- 普通 `--product` 下载流程不变。
- `build_source_url()` 新增可选 `works` 参数；当传入作品名时，应优先构造按作品下载的 URL，不再附带 `good` 参数。
- 作品模式不再做“作品 -> 产品 -> 二次选择”的交互。

## 方案

### CLI

- 新增 `--list-works` 参数。
- 新增作品列表打印与编号选择逻辑，交互形式与现有 `--list-products` 保持一致。

### 下载 URL

- `build_source_url()` 接收 `works`。
- 当 `works` 非空时，查询参数包含 `works`、`page`、`limit`，并省略 `good`。
- 当 `works` 为空时，保持现有 `good` 产品筛选逻辑。

### 下载流程

- `--list-works` 选中后，将选中的作品名写回 `args.work`。
- 主流程据此构造 `SOURCE_URL`，继续沿用已有下载、去重、跳过已存在文件与失败统计逻辑。

## 测试

- 为 `build_source_url(works=...)` 增加 URL 断言，确认包含 `works=` 且不包含 `good=`。
- 为 `--list-works` 增加交互测试，确认打印作品列表、接受编号并进入下载主流程。
- 为 `--help` 增加 `--list-works` 文案断言。

## 文档同步

- 更新 `docs/plan/development_plan.md` 中图片抓取脚本部分的 CLI 描述。
- 在 `docs/logs/log_2026-04-09.md` 追加本轮变更记录。
