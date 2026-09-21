# 任务清单 - v1.4.0-feature

## 实现
- ✅ 1. 在 `UsageProvider.swift` 中增加 `case custom`，配置显示名称与图标。
- ✅ 2. 在 `UsageRoute.swift` 中增加 `case script` 路由。
- ✅ 3. 在 `ProviderUsage.swift` 中扩展 `Unavailability`（如 `customScriptMissing`, `customScriptNotExecutable`, `customScriptFailed`）。
- ✅ 4. 在 `AppSettings.swift` 中新增 `customScriptPath` 配置项读写支持与持久化。
- ✅ 5. 实现 `CustomScriptUsageService.swift`：支持执行外部脚本、超时处理与 JSON 数据转换映射。
- ✅ 6. 在 `UsageStore.swift` 的刷新循环与单独刷新中接入 `CustomScriptUsageService`。
- ✅ 7. 在 `SettingsView.swift` 中增加自定义脚本供应商设置界面（脚本路径输入框与测试触发）。
- ✅ 8. 添加多语言翻译项（en, zh-Hans, zh-Hant, ja, ko）并运行 `./Scripts/check-localization.sh` 校验通过。
- ✅ 9. 支持一个脚本返回 `providers` 数组，并允许添加多个自定义脚本实例。
- ✅ 10. 在“Ring shows”中增加“所有分组”；Custom 不限制分组数，每组使用主环与第二层环展示配额窗口。

## 测试与验证
- ✅ 11. 编写单元测试，验证合法 JSON 解析、错误容错、脚本执行及 Custom 多分组轨道。
- ✅ 12. 运行 Custom 脚本测试和 RailSlotTests；`swift build -Xswiftc -swift-version -Xswiftc 6` 严格模式编译通过。
- ✅ 13. 验证 OpenCodex 示例脚本返回 4 组、每组 2 个窗口，并完成通用应用包构建。

## 发布
- ✅ 14. 更新 `version.md` 形成最终版本摘要。
