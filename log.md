# Flash Translate Log

## 2026-03-08
- 初始化 SwiftUI + AppKit 的 macOS 菜单栏应用骨架，默认作为 LSUIElement 运行，不显示 Dock 图标。
- 搭建状态栏图标、Popover 翻译面板、设置页、快捷键监听、双击 Cmd 预留模块。
- 建立选中文本捕获抽象：优先 Accessibility 读取，失败后走剪贴板 Cmd+C 兜底，并补充权限管理。
- 建立翻译服务层：默认 Google Translate，支持自定义 OpenAI-compatible `/chat/completions` 配置。
- 使用 UserDefaults 持久化 provider、URL、API Key、model、快捷键信息。
- 增加最小测试文件：语言方向判断、设置持久化、OpenAI 请求构造。
- 通过 `swift build --package-path “/Users/oran/Documents/Claude Code/Flash Translate”` 完成一次构建验证。
- 当前环境缺少完整 Xcode app SDK / XCTest 支持，`swift test` 与 `xcodebuild` 尚不能在本机命令行直接完成。需安装完整 Xcode 后继续 UI 运行与测试验证。
- 补建 `FlashTranslate.xcodeproj/project.pbxproj`，新增最小 macOS App target `FlashTranslate` 与 XCTest target `FlashTranslateTests`，复用现有 `FlashTranslateApp.swift`、`Sources/`、`Tests/`、`Info.plist`。
- 后续复查发现系统已正确指向 `/Applications/Xcode.app/Contents/Developer`，并且 `xcodebuild -project “.../FlashTranslate.xcodeproj” -scheme FlashTranslate -configuration Debug build` 已成功通过，说明补建后的 Xcode 工程已可被命令行识别并完成 app 构建。
- 当前命令行构建仍有 1 个已有 warning：`Sources/Config/AppSettings.swift:97` 给 `NSEvent.ModifierFlags` 添加 `Codable` conformance，未来若 AppKit 官方补上同样 conformance 可能产生冲突；这不影响当前运行。
- 修复”点击翻译后界面卡死”：将翻译流程从主线程状态更新中拆开，避免 `AppState` 在主线程上串行等待整段翻译任务；同时为重复触发增加 task cancel，翻译按钮在 loading 期间禁用，防止菜单栏弹窗被连续点击拖死。
- 调整交互以便调试：将默认快捷键改为 `Ctrl+Space`，扩展快捷键显示/解析；菜单栏界面改成同时支持”取词翻译”和”手动编辑原文后直接翻译”；底部增加”打开设置”按钮，并兼容不同 macOS 版本的设置窗口 action 名称。
- 修复菜单栏交互闭环：快捷键触发时先自动弹出 popover，再延迟启动取词，避免弹窗切焦点与取词动作互相打架导致界面假死；同时把取词流程拆到独立 `captureTask`，与翻译任务分离，降低主线程阻塞概率。
- 修复设置窗口打不开：不再依赖 `showSettingsWindow:` / `showPreferencesWindow:` action，改为显式创建并复用独立 `NSWindow` 承载 `SettingsView`，从菜单和浮层按钮都可直接打开。
- 调整 loading 表现：删除独立一行”翻译中...”，改为在”取词翻译”或”翻译输入内容”按钮自身切换为”翻译中...”，避免菜单栏浮层布局跳动。
- 重新执行 `xcodebuild -project “/Users/oran/Documents/Claude Code/Flash Translate/FlashTranslate.xcodeproj” -scheme FlashTranslate -configuration Debug build`，构建通过；当前仍保留 `AppSettings.swift:97` 的既有 Codable warning。
- **修复设置窗口冲突导致卡死**：删除 `AppState` 中手动创建的 `settingsWindow`，改用 SwiftUI App 自带的 `Settings` scene，通过 `showSettingsWindow:` action 打开，避免两套窗口系统冲突。
- **修复内存泄漏**：在所有 `Task.detached` 的 `MainActor.run` 闭包中添加 `[weak self]` 捕获，防止循环引用导致 `AppState` 无法释放。
- **修复粘贴板异常崩溃**：`PasteboardCaptureFallback` 恢复原始内容时，不再复用已关联的 `NSPasteboardItem`，改为保存原始字符串并重新写入，避免 "already associated with another pasteboard" 异常。同时修正 Cmd+C 快捷键模拟逻辑，正确按下/释放 Command 和 C 键。
- **启用双击 Command 快捷键**：将 `doubleCommandDetector` 的回调从预留状态改为实际触发取词翻译，现在双击 Command 键即可触发翻译。
- **改进悬浮窗体验**：快捷键触发时，在鼠标位置附近显示独立悬浮窗（NSPanel），而不是固定在菜单栏下方。点击菜单栏图标仍然显示 popover。悬浮窗支持拖动、调整大小、有关闭按钮，可以正常输入和编辑文字。
- **修复悬浮窗卡死问题**：`NSHostingController` 只创建一次并复用，避免重复创建导致卡死。
- **修复取词时序问题**：调整取词和显示窗口的顺序，先立即开始取词（模拟 Cmd+C），等待 250ms 后再打开悬浮窗，确保窗口打开时已经获取到选中文字。这样避免了窗口获取焦点导致无法读取原选中文字的问题。
- **添加屏幕边界检测**：悬浮窗会自动检测屏幕边界，防止窗口超出屏幕可见区域，距离边缘保持 10px 安全距离。
- **添加淡入动画**：悬浮窗显示时有 0.2 秒的淡入动画，使用 easeOut 缓动函数，提升视觉体验。
- **修复窗口位置闪烁**：窗口已打开时不重复触发，避免窗口从旧位置移动到新位置的闪烁问题。每次打开新窗口时在透明状态下创建，然后淡入显示。
- 编译验证通过，`BUILD SUCCEEDED`。功能测试通过，双击 Command 可以正常取词翻译。
- **发布 v1.0 版本**：编译 Release 版本并打包成 DMG 安装包（FlashTranslate-v1.0.dmg，392KB）。
- **完善设置界面**：将翻译服务选择改为分段选择器（Google / OpenAI Compatible），Google 模式下不显示 API 配置，OpenAI Compatible 模式下显示 Base URL、API Key、Model 配置项。添加占位符文本（Base URL: `https://api.openai.com/v1`，API Key: `sk-...`，Model: `openai/gpt-5-nano`）和帮助文本说明 Base URL 格式。添加"测试翻译"按钮，点击后使用"测试翻译"四个字进行实际翻译测试，显示成功或失败结果。设置采用自动保存机制，无需保存按钮。
- **更新默认模型**：将默认 model 从 `gpt-4.1-mini` 改为 `openai/gpt-5-nano`，适配最新的 OpenAI 兼容 API。
- **发布 v1.1 版本**：编译 Release 版本并打包成 DMG 安装包（FlashTranslate-v1.1.dmg，425KB）。

