import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRecordingHotkey = false
    @State private var testResult: String = ""
    @State private var isTesting: Bool = false
    @State private var currentProvider: TranslationProvider = .google

    private var settingsBinding: Binding<AppSettings> {
        Binding(
            get: { appState.settingsStore.settings },
            set: { newValue in
                appState.settingsStore.save(newValue)
                appState.updateHotkeyState()
            }
        )
    }

    var body: some View {
        Form {
            Section("翻译服务") {
                Picker("Provider", selection: $currentProvider) {
                    ForEach(TranslationProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: currentProvider) { oldValue, newValue in
                    var settings = appState.settingsStore.settings
                    settings.provider = newValue
                    appState.settingsStore.save(settings)
                }
            }

            if currentProvider == .google {
                Section("Google Translate") {
                    Text("使用 Google Translate 免费服务，无需配置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if currentProvider == .openAICompatible {
                Section("OpenAI Compatible API") {
                    TextField("Base URL", text: settingsBinding.baseURL, prompt: Text("https://api.openai.com/v1"))
                        .textFieldStyle(.roundedBorder)
                    SecureField("API Key", text: settingsBinding.apiKey, prompt: Text("sk-..."))
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: settingsBinding.model, prompt: Text("openai/gpt-5-nano"))
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button(isTesting ? "测试中..." : "测试翻译") {
                            testTranslation()
                        }
                        .disabled(isTesting || appState.settingsStore.settings.baseURL.isEmpty || appState.settingsStore.settings.apiKey.isEmpty)

                        if !testResult.isEmpty {
                            Text(testResult)
                                .font(.caption)
                                .foregroundStyle(testResult.contains("成功") ? .green : .red)
                        }
                    }

                    Text("Base URL 需要包含 /v1，例如：https://api.openai.com/v1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("快捷键") {
                Toggle("启用 Ctrl+Space 快捷键", isOn: settingsBinding.enableCtrlSpace)
                Toggle("启用双击 Command 键", isOn: settingsBinding.enableDoubleCommand)
                Text("至少启用一种快捷键方式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("权限") {
                Label(appState.permissionManager.accessibilityStatusText, systemImage: appState.permissionManager.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(appState.permissionManager.accessibilityGranted ? .green : .orange)

                Button("重新申请辅助功能权限") {
                    appState.reopenPermissionGuidance()
                }
            }
        }
        .padding()
        .onAppear {
            currentProvider = appState.settingsStore.settings.provider
        }
    }

    private func testTranslation() {
        isTesting = true
        testResult = ""

        Task {
            do {
                let httpClient = HTTPClient()
                let openAIService = OpenAICompatibleTranslateService(httpClient: httpClient)
                let languageResolver = LanguageDirectionResolver()
                let settings = appState.settingsStore.settings

                // 测试翻译
                let testText = "测试翻译"
                let direction = languageResolver.resolve(for: testText)
                let result = try await openAIService.translate(
                    text: testText,
                    direction: direction,
                    settings: settings
                )

                await MainActor.run {
                    testResult = "✓ 成功: \(result)"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "✗ 失败: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

struct HotkeyRecorderButton: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onShortcutChange = { newShortcut in
            shortcut = newShortcut
        }
        view.onRecordingChange = { recording in
            isRecording = recording
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.currentShortcut = shortcut
    }
}

class HotkeyRecorderNSView: NSView {
    var onShortcutChange: ((KeyboardShortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    var currentShortcut: KeyboardShortcut = .defaultShortcut {
        didSet {
            needsDisplay = true
        }
    }

    private var isRecording = false {
        didSet {
            onRecordingChange?(isRecording)
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 200, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let text = isRecording ? "按下快捷键..." : currentShortcut.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]

        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        text.draw(in: textRect, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        // 至少需要一个修饰键
        guard !modifiers.isEmpty else { return }

        let newShortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
        currentShortcut = newShortcut
        onShortcutChange?(newShortcut)

        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }
}

private extension Binding where Value == AppSettings {
    var provider: Binding<TranslationProvider> {
        Binding<TranslationProvider>(
            get: { wrappedValue.provider },
            set: { wrappedValue.provider = $0 }
        )
    }

    var baseURL: Binding<String> {
        Binding<String>(
            get: { wrappedValue.baseURL },
            set: { wrappedValue.baseURL = $0 }
        )
    }

    var apiKey: Binding<String> {
        Binding<String>(
            get: { wrappedValue.apiKey },
            set: { wrappedValue.apiKey = $0 }
        )
    }

    var model: Binding<String> {
        Binding<String>(
            get: { wrappedValue.model },
            set: { wrappedValue.model = $0 }
        )
    }

    var hotkey: Binding<KeyboardShortcut> {
        Binding<KeyboardShortcut>(
            get: { wrappedValue.hotkey },
            set: { wrappedValue.hotkey = $0 }
        )
    }

    var enableCtrlSpace: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.enableCtrlSpace },
            set: { wrappedValue.enableCtrlSpace = $0 }
        )
    }

    var enableDoubleCommand: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.enableDoubleCommand },
            set: { wrappedValue.enableDoubleCommand = $0 }
        )
    }
}
