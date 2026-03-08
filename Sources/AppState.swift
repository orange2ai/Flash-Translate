import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var originalText: String = ""
    @Published var translatedText: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastTriggerSource: String = ""

    let settingsStore: SettingsStore
    let permissionManager: PermissionManager

    var onRequestShowPopover: (() -> Void)?

    private let textCaptureService: TextCaptureService
    private let translationService: TranslationService
    private let hotkeyManager: HotkeyManager
    private let doubleCommandDetector: DoubleCommandDetector
    private var captureTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?

    init(
        settingsStore: SettingsStore,
        permissionManager: PermissionManager,
        textCaptureService: TextCaptureService,
        translationService: TranslationService,
        hotkeyManager: HotkeyManager,
        doubleCommandDetector: DoubleCommandDetector
    ) {
        self.settingsStore = settingsStore
        self.permissionManager = permissionManager
        self.textCaptureService = textCaptureService
        self.translationService = translationService
        self.hotkeyManager = hotkeyManager
        self.doubleCommandDetector = doubleCommandDetector
    }

    static func bootstrap() -> AppState {
        let settingsStore = SettingsStore()
        let permissionManager = PermissionManager()
        let pasteboardFallback = PasteboardCaptureFallback(permissionManager: permissionManager)
        let selectionCapture = SelectionCaptureService(
            permissionManager: permissionManager,
            fallback: pasteboardFallback
        )
        let languageResolver = LanguageDirectionResolver()
        let httpClient = HTTPClient()
        let googleService = GoogleTranslateService(httpClient: httpClient)
        let openAIService = OpenAICompatibleTranslateService(httpClient: httpClient)
        let translationService = TranslationService(
            settingsStore: settingsStore,
            languageDirectionResolver: languageResolver,
            googleService: googleService,
            openAIService: openAIService
        )
        let hotkeyManager = HotkeyManager(settingsStore: settingsStore)
        let doubleCommandDetector = DoubleCommandDetector()

        return AppState(
            settingsStore: settingsStore,
            permissionManager: permissionManager,
            textCaptureService: selectionCapture,
            translationService: translationService,
            hotkeyManager: hotkeyManager,
            doubleCommandDetector: doubleCommandDetector
        )
    }

    func start() {
        hotkeyManager.onTrigger = { [weak self] in
            self?.handleHotkeyTrigger()
        }

        doubleCommandDetector.onDoubleCommand = { [weak self] in
            self?.handleHotkeyTrigger()
        }

        updateHotkeyState()
    }

    func updateHotkeyState() {
        let settings = settingsStore.settings

        if settings.enableCtrlSpace {
            hotkeyManager.start()
        } else {
            hotkeyManager.stop()
        }

        if settings.enableDoubleCommand {
            doubleCommandDetector.start()
        } else {
            doubleCommandDetector.stop()
        }
    }

    func captureAndTranslateSelection(triggerSource: String = "selection", captureDelay: Duration = .zero) {
        cancelRunningTasks()
        errorMessage = nil
        isLoading = true
        translatedText = ""
        lastTriggerSource = triggerSource

        let permissionManager = self.permissionManager
        let textCaptureService = self.textCaptureService

        captureTask = Task.detached(priority: .userInitiated) { [weak self, permissionManager, textCaptureService] in
            do {
                if captureDelay > .zero {
                    try await Task.sleep(for: captureDelay)
                }

                try await MainActor.run {
                    try permissionManager.ensureCapturePermissionIfPossible()
                }

                let capturedText = try await textCaptureService.captureText()
                let trimmedText = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmedText.isEmpty else {
                    throw AppError.emptySelection
                }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.originalText = trimmedText
                    self.captureTask = nil
                    self.startTranslationTask(for: trimmedText)
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.captureTask = nil
                    self.isLoading = false
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.captureTask = nil
                    self.errorMessage = message
                    self.isLoading = false
                }
            }
        }
    }

    func translateManually() {
        let currentText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !currentText.isEmpty else {
            errorMessage = AppError.emptyManualInput.errorDescription
            return
        }

        cancelRunningTasks()
        errorMessage = nil
        isLoading = true
        translatedText = ""
        lastTriggerSource = "manual"
        startTranslationTask(for: currentText)
    }

    private func startTranslationTask(for text: String) {
        translationTask?.cancel()
        let translationService = self.translationService

        translationTask = Task.detached(priority: .userInitiated) { [weak self, translationService] in
            do {
                let translatedText = try await translationService.translate(text: text)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.translatedText = translatedText
                    self.isLoading = false
                    self.translationTask = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    self.translationTask = nil
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.errorMessage = message
                    self.isLoading = false
                    self.translationTask = nil
                }
            }
        }
    }

    func copyTranslation() {
        guard !translatedText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translatedText, forType: .string)
    }

    func openSettings() {
        // 使用 Command+, 快捷键打开设置
        if #available(macOS 13, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func reopenPermissionGuidance() {
        permissionManager.promptForAccessibilityPermission()
    }

    private func handleHotkeyTrigger() {
        // 先取词，不要延迟
        captureAndTranslateSelection(triggerSource: "hotkey", captureDelay: .zero)
        // 延迟打开窗口，等取词和翻译开始
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            onRequestShowPopover?()
        }
    }

    private func cancelRunningTasks() {
        captureTask?.cancel()
        translationTask?.cancel()
        captureTask = nil
        translationTask = nil
    }
}

enum AppError: LocalizedError {
    case emptySelection
    case emptyManualInput

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "没有读取到选中文本，请先去别的应用里选中文字后，再用“取词翻译”。"
        case .emptyManualInput:
            return "请先输入要翻译的文本。"
        }
    }
}
