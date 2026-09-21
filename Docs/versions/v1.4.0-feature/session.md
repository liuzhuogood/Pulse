# 会话记录 - v1.4.0-feature

## 用户需求与背景
用户希望在 Pulse 中增加自定义供应商（Custom Provider / Script Provider）：
- 通过脚本获取所需信息。
- Pulse 定义好约定的 JSON 数据结构。
- 外部脚本执行后输出该 JSON，Pulse 解析并在界面（Panel 悬浮环、卡片详情等）展示。
- 输入与参数就是脚本路径，其他都在脚本内部灵活处理。

## 交互与共识
- **用户**：能不能帮我增加一个自定义的供应商， 可以通过脚本获取到所需信息， 你定义好 结构就行（Json）， 然后执行什么脚本，可以把信息展示出来。你先理解一下。
- **Codex**：梳理架构图（Mermaid）、执行时序图与 JSON 数据结构设计，提炼关键考量（安全超时、参数模式等）。
- **用户**：[$lz-plugin:lz-vlog] 记录一下版本，然后开发完成。输入与参数 就是脚本路径，其他都在脚本里， 灵活处理。
- **Codex**：开启 v1.4.0-feature 版本流，完成所有相关模块实现与多语言校验。

## 最终实现与交付
1. **约定契约**：
   - 支持脚本通过 stdout 输出包含 `plan`、`creditBalance`、`windows`（含 `id`, `kind`, `scope`, `usedFraction`, `resetsAt`, `windowSeconds`, `isExhausted`）的 JSON 报文。
2. **底层执行与监控**：
   - 增加 `CustomScriptUsageService`，支持指定可执行脚本、PATH 继承、10 秒超时中断保护与标准错误日志捕获。
   - 映射到 Pulse 核心模型与多种配额窗口类型（fiveHour, weekly, daily, monthly, balance, messages 等）。
3. **设置与界面**：
   - Settings 中支持配置脚本路径及即时测试按钮；
   - 界面圆环与卡片原生支持 Custom 供应商展示。
4. **多语言与测试**：
   - 补齐 en, zh-Hans, zh-Hant, ja, ko 的 8 组本地化文案，通过 `check-localization.sh`。
   - 单元测试 `CustomScriptUsageTests`（4 个用例全部通过），并通过 Swift 6 严格并发检查。

## 后续补充
- 一个 Custom 脚本既可返回单个 `windows` 对象，也可返回 `providers` 数组；多个脚本实例也可分别配置。
- OpenCodex Antigravity 示例会动态从页面读取会话令牌，返回两个账号的 Gem 与 Cla 共 4 个额度组；每组保留 5h 与 Weekly 两个窗口。
- 设置“Ring shows”为“所有分组”即可显示 4 个圈；每圈的两层用于该组的两个窗口。
